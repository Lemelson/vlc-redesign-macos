/*****************************************************************************
 * MXRVoutWindow.m: "vout window" submodule, video surfaces
 *****************************************************************************
 * Copyright (C) 2026 VLC Redesign contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *****************************************************************************/

/*
 * ARCHITECTURE.md §3.2. Patterned on the stock provider
 * (modules/gui/macosx/windows/video/VLCVideoOutputProvider.m and VLCVoutView.m).
 *
 * Threading (§2.3):
 *  - enable runs on the vout thread and needs the view synchronously: dispatch_sync(main).
 *    The main thread must therefore never wait on vout or decoder threads.
 *  - disable, resize, set_state and (un)set_fullscreen hop to main with dispatch_async.
 *  - Size and fullscreen reports go through a private serial queue per output, never inline
 *    from -layout (avoids a deadlock with the display lock, as VLCVoutView.m does). Reports
 *    are dropped while the window is disabled.
 */

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

#include <stdatomic.h>

#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_playlist.h>
#include <vlc_window.h>
#include <vlc_mouse.h>
#include <vlc_variables.h>

#import "MXRModule.h"
#import "MXRBridgeInternal.h"
#import "bridge/MXRMediaServices.h"

static atomic_bool g_intf_started = false;

void MXRVoutWindowSetInterfaceStarted(void)
{
    atomic_store(&g_intf_started, true);
}

static void MXRRunOnMainSync(dispatch_block_t block)
{
    if ([NSThread isMainThread])
        block();
    else
        dispatch_sync(dispatch_get_main_queue(), block);
}

#pragma mark - MXRVideoOutput

@interface MXRVideoOutput ()
@property (nonatomic, readwrite) CGSize proposedSize;
@property (nonatomic, readwrite) BOOL wantsFullscreenAtStart;
@property (nonatomic, readwrite, weak, nullable) MXRVideoSurfaceView *surface;
- (instancetype)initWithWindow:(vlc_window_t *)wnd NS_DESIGNATED_INITIALIZER;
/* Any thread */
- (void)setReportsEnabled:(BOOL)enabled;
- (void)reportBackingSize:(CGSize)size;
- (void)reportMouseAt:(NSPoint)point pressed:(int)pressed released:(int)released;
- (void)stopObservingFilters;
/* Main thread, cheap: VLC wants the pointer (interactive title, or a mouse video filter). */
- (BOOL)wantsPointerWithInteractiveTitle:(BOOL)interactive;
/* Main thread */
- (nullable MXRVideoSurfaceView *)attachSurfaceWithProposedSize:(CGSize)size
                                                     fullscreen:(BOOL)fullscreen;
- (void)detachSurface:(nullable MXRVideoSurfaceView *)surface;
@end

@interface MXRVideoSurfaceView ()
@property (nonatomic, readwrite, weak, nullable) MXRVideoOutput *videoOutput;
- (void)reportSize;
@end

/* Video filters that take the pointer through the vout window (modules/video_filter). */
static bool FilterChainNeedsMouse(const char *chain)
{
    static const char *const names[] = { "magnify", "puzzle", "freeze", "sam3" };
    for (const char *part = chain; part != NULL && *part != '\0';) {
        size_t length = strcspn(part, ":{");
        for (size_t i = 0; i < ARRAY_SIZE(names); i++)
            if (strlen(names[i]) == length && strncmp(part, names[i], length) == 0)
                return true;
        part += length;
        if (*part == '{') { const char *end = strchr(part, '}'); part = end != NULL ? end + 1 : part + strlen(part); }
        if (*part == ':') part++;
    }
    return false;
}

static int VideoFilterChanged(vlc_object_t *object, const char *name, vlc_value_t old,
                              vlc_value_t value, void *data);

@implementation MXRVideoOutput
{
    vlc_window_t *_window;      /* the vlc_window_t; constant */
    vlc_mutex_t _lock;
    bool _reportsEnabled;       /* guarded by _lock: true between enable and disable */
    dispatch_queue_t _reportQueue;
    /* The vout's "video-filter" holds a filter that reads the pointer (magnify, puzzle...).
     * Kept by a variable callback so a mouse event never parses the chain (C-06). */
    atomic_bool _filterNeedsMouse;
    vlc_object_t *_filterSource;
}

- (instancetype)initWithWindow:(vlc_window_t *)wnd
{
    self = [super init];
    if (self) {
        _window = wnd;
        /* window -> vout -> (dummy vout, sout display) -> player: the output player says so. */
        for (vlc_object_t *object = VLC_OBJECT(wnd); object != NULL; object = vlc_object_parent(object))
            if (var_Type(object, MXR_AUXILIARY_VIDEO_VAR) != 0) { _auxiliary = YES; break; }
        vlc_mutex_init(&_lock);
        _reportsEnabled = false;
        char *chain = var_InheritString(wnd, "video-filter");
        atomic_init(&_filterNeedsMouse, FilterChainNeedsMouse(chain));
        free(chain);
        vlc_object_t *vout = vlc_object_parent(VLC_OBJECT(wnd));
        if (vout != NULL && var_Type(vout, "video-filter") != 0) {
            _filterSource = vout;
            var_AddCallback(vout, "video-filter", VideoFilterChanged, (__bridge void *)self);
        }
        _reportQueue = dispatch_queue_create("org.videolan.vlc.macosx-redesign.vout-reports",
                                             DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)setReportsEnabled:(BOOL)enabled
{
    vlc_mutex_lock(&_lock);
    _reportsEnabled = enabled;
    vlc_mutex_unlock(&_lock);
}

/* Runs `report` on the report queue with the window, unless the window is disabled. */
- (void)report:(void (^)(vlc_window_t *wnd))report
{
    dispatch_async(_reportQueue, ^{
        vlc_mutex_lock(&self->_lock);
        if (self->_reportsEnabled)
            report(self->_window);
        vlc_mutex_unlock(&self->_lock);
    });
}

- (void)filterChainChanged:(const char *)chain
{
    bool needs = FilterChainNeedsMouse(chain);
    if (atomic_exchange(&_filterNeedsMouse, needs) == needs)
        return;
    __weak MXRVideoOutput *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf.surface updateTrackingAreas]; });
}

/* Before the window is released (WindowDestroy): var_DelCallback waits for a running callback. */
- (void)stopObservingFilters
{
    if (_filterSource != NULL) {
        var_DelCallback(_filterSource, "video-filter", VideoFilterChanged, (__bridge void *)self);
        _filterSource = NULL;
    }
}

- (BOOL)wantsPointerWithInteractiveTitle:(BOOL)interactive
{
    return interactive || atomic_load(&_filterNeedsMouse);
}

/* `pressed`/`released`: a VLC mouse button, or -1. Only the vlc_window reports leave main. */
- (void)reportMouseAt:(NSPoint)point pressed:(int)pressed released:(int)released
{
    const int x = (int)lround(point.x), y = (int)lround(point.y);
    [self report:^(vlc_window_t *wnd) {
        vlc_window_ReportMouseMoved(wnd, x, y);
        if (pressed >= 0) vlc_window_ReportMousePressed(wnd, (unsigned)pressed);
        if (released >= 0) vlc_window_ReportMouseReleased(wnd, (unsigned)released);
    }];
}

- (void)reportBackingSize:(CGSize)size
{
    if (size.width < 1. || size.height < 1.)
        return;
    const unsigned width = (unsigned)lround(size.width);
    const unsigned height = (unsigned)lround(size.height);
    [self report:^(vlc_window_t *wnd) {
        vlc_window_ReportSize(wnd, width, height);
    }];
}

- (void)reportFullscreen:(BOOL)fullscreen
{
    [self report:^(vlc_window_t *wnd) {
        if (fullscreen)
            vlc_window_ReportFullscreen(wnd, NULL);
        else
            vlc_window_ReportWindowed(wnd);
    }];
}

- (void)reportClose
{
    [self report:^(vlc_window_t *wnd) {
        vlc_window_ReportClose(wnd);
    }];
}

- (nullable MXRVideoSurfaceView *)attachSurfaceWithProposedSize:(CGSize)size
                                                     fullscreen:(BOOL)fullscreen
{
    MXRInterfaceBridge *bridge = MXRCurrentInterfaceBridge();
    if (bridge == nil || bridge.isShutDown)
        return nil;
    id<MXRVideoSurfaceProvider> provider = bridge.videoSurfaceProvider;
    if (provider == nil)
        return nil;

    self.proposedSize = size;
    self.wantsFullscreenAtStart = fullscreen;

    MXRVideoSurfaceView *surface = [provider surfaceForVideoOutput:self];
    if (surface == nil || surface.isInUse)
        return nil;

    surface.videoOutput = self;
    self.surface = surface;
    /* The display reads the size from our reports: send the current one now, layout may not
     * run again for a surface that is already in place. */
    [surface reportSize];
    surface.needsLayout = YES;
    return surface;
}

- (void)detachSurface:(nullable MXRVideoSurfaceView *)surface
{
    if (surface != nil && surface.videoOutput == self)
        surface.videoOutput = nil;
    self.surface = nil;

    MXRInterfaceBridge *bridge = MXRCurrentInterfaceBridge();
    if (bridge != nil && !bridge.isShutDown)
        [bridge.videoSurfaceProvider videoOutputDidStop:self];
}

@end

static int VideoFilterChanged(vlc_object_t *object, const char *name, vlc_value_t old,
                              vlc_value_t value, void *data)
{
    VLC_UNUSED(object); VLC_UNUSED(name); VLC_UNUSED(old);
    [(__bridge MXRVideoOutput *)data filterChainChanged:value.psz_string];
    return VLC_SUCCESS;
}

#pragma mark - MXRVideoSurfaceView

@implementation MXRVideoSurfaceView
{
    unsigned _routedButtons;   /* VLC mouse buttons pressed while routed to VLC */
    unsigned _swallowedButtons; /* presses that only closed a popup: their release is ours too */
}
@synthesize videoOutput = _videoOutput;

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawNever;
        CGColorRef black = CGColorCreateGenericGray(0., 1.);
        self.layer.backgroundColor = black;
        CGColorRelease(black);
        self.layer.opaque = YES;
        self.autoresizesSubviews = YES;
    }
    return self;
}

- (BOOL)isOpaque
{
    return YES;
}

/* No drawRect: the layer background is the black (§3.2). */
- (BOOL)wantsUpdateLayer
{
    return YES;
}

- (void)updateLayer
{
}

- (BOOL)isInUse
{
    return self.videoOutput != nil;
}

/* VLC's display adds its own subviews; keep mouse events on the surface itself so the UI
 * decides what clicks do (§3.2, "Mouse clicks are not forwarded by default"). */
- (nullable NSView *)hitTest:(NSPoint)point
{
    NSView *hit = [super hitTest:point];
    return hit != nil ? self : nil;
}

/* Pointer moves reach VLC only while it wants them (C-06): an interactive title or a mouse
 * video filter. Otherwise the surface has no move tracking and every event goes straight to
 * the host on main, which decides what clicks do (D024 popup-dismiss-first, double click). */
- (BOOL)routesPointer
{
    MXRVideoOutput *output = self.videoOutput;
    return output != nil && [output wantsPointerWithInteractiveTitle:MXRCurrentInterfaceBridge().player.interactiveVideo];
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [NSNotificationCenter.defaultCenter removeObserver:self name:MXRInteractiveVideoDidChangeNotification object:nil];
    if (self.window != nil)
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateTrackingAreas)
                                                   name:MXRInteractiveVideoDidChangeNotification object:nil];
}

- (void)setVideoOutput:(MXRVideoOutput *)videoOutput
{
    _videoOutput = videoOutput;
    _routedButtons = 0; _swallowedButtons = 0;
    [self updateTrackingAreas];
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) [self removeTrackingArea:area];
    if (self.routesPointer)
        [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
            options:NSTrackingMouseMoved | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil]];
}

/* D024: a click first closes an open popup, also over a DVD menu or a mouse filter. */
- (BOOL)clickClosesPopup
{
    for (NSView *view = self.superview; view != nil; view = view.superview)
        if ([view conformsToProtocol:@protocol(MXRVideoSurfaceHost)])
            return [(id<MXRVideoSurfaceHost>)view videoSurfaceClickClosesPopup];
    return NO;
}

/* Main thread, synchronous: the host gets every event VLC does not take, in order. */
- (BOOL)routeMouse:(NSEvent *)event
{
    const NSEventType type = event.type;
    const unsigned button = event.buttonNumber == 1 ? MOUSE_BUTTON_RIGHT : event.buttonNumber == 2 ? MOUSE_BUTTON_CENTER : MOUSE_BUTTON_LEFT;
    const unsigned mask = 1U << button;
    const BOOL down = type == NSEventTypeLeftMouseDown || type == NSEventTypeRightMouseDown || type == NSEventTypeOtherMouseDown;
    const BOOL up = type == NSEventTypeLeftMouseUp || type == NSEventTypeRightMouseUp || type == NSEventTypeOtherMouseUp;
    if (up && (_swallowedButtons & mask)) { _swallowedButtons &= ~mask; return YES; }
    MXRVideoOutput *output = self.videoOutput;
    if (output == nil || (!(_routedButtons & mask) && !self.routesPointer))
        return NO;
    if (type == NSEventTypeLeftMouseDown && event.clickCount == 1 && self.clickClosesPopup) {
        _swallowedButtons |= mask;
        return YES;
    }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    point.x = fmax(NSMinX(self.bounds), fmin(point.x, NSMaxX(self.bounds)));
    point.y = fmax(NSMinY(self.bounds), fmin(point.y, NSMaxY(self.bounds)));
    point = NSMakePoint(point.x - self.bounds.origin.x, NSMaxY(self.bounds) - point.y);
    point = [self convertPointToBacking:point];
    int pressed = -1, released = -1;
    if (down) { _routedButtons |= mask; pressed = (int)button; }
    if (up) { _routedButtons &= ~mask; released = (int)button; }
    [output reportMouseAt:point pressed:pressed released:released];
    return YES;
}

- (void)mouseMoved:(NSEvent *)event { if (![self routeMouse:event]) [super mouseMoved:event]; }
- (void)mouseDragged:(NSEvent *)event { if (![self routeMouse:event]) [super mouseDragged:event]; }
- (void)rightMouseDragged:(NSEvent *)event { if (![self routeMouse:event]) [super rightMouseDragged:event]; }
- (void)otherMouseDragged:(NSEvent *)event { if (![self routeMouse:event]) [super otherMouseDragged:event]; }
- (void)mouseDown:(NSEvent *)event { if (![self routeMouse:event]) [super mouseDown:event]; }
- (void)mouseUp:(NSEvent *)event { if (![self routeMouse:event]) [super mouseUp:event]; }
- (void)rightMouseDown:(NSEvent *)event { if (![self routeMouse:event]) [super rightMouseDown:event]; }
- (void)rightMouseUp:(NSEvent *)event { if (![self routeMouse:event]) [super rightMouseUp:event]; }
- (void)otherMouseDown:(NSEvent *)event { if (![self routeMouse:event]) [super otherMouseDown:event]; }
- (void)otherMouseUp:(NSEvent *)event { if (![self routeMouse:event]) [super otherMouseUp:event]; }

- (void)reportSize
{
    MXRVideoOutput *output = self.videoOutput;
    if (output == nil)
        return;
    NSRect backing = [self convertRectToBacking:self.bounds];
    [output reportBackingSize:backing.size];
}

- (void)layout
{
    [super layout];
    [self reportSize];
}

- (void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    [self reportSize];
}

- (void)viewDidChangeBackingProperties
{
    [super viewDidChangeBackingProperties];
    [self reportSize];
}

@end

#pragma mark - vout window operations

static int WindowEnable(vlc_window_t *wnd, const vlc_window_cfg_t *cfg)
{
    MXRVideoOutput *output = (__bridge MXRVideoOutput *)wnd->sys;
    const CGSize proposed = CGSizeMake(cfg->width, cfg->height);
    const BOOL fullscreen = cfg->is_fullscreen;
    __block MXRVideoSurfaceView *surface = nil;

    msg_Dbg(wnd, "enabling video window (proposed %ux%u px%s)",
            cfg->width, cfg->height, cfg->is_fullscreen ? ", fullscreen" : "");

    /* Enable reports first so the size sent while attaching reaches the core. */
    [output setReportsEnabled:YES];
    MXRRunOnMainSync(^{
        @autoreleasepool {
            surface = [output attachSurfaceWithProposedSize:proposed fullscreen:fullscreen];
        }
    });

    if (surface == nil) {
        [output setReportsEnabled:NO];
        msg_Err(wnd, "no video surface available");
        return VLC_EGENERIC;
    }

    wnd->handle.nsobject = (void *)CFBridgingRetain(surface);
    if (cfg->is_fullscreen)
        vlc_window_SetFullScreen(wnd, NULL);
    return VLC_SUCCESS;
}

static void WindowDisable(vlc_window_t *wnd)
{
    MXRVideoOutput *output = (__bridge MXRVideoOutput *)wnd->sys;
    void *handle = wnd->handle.nsobject;

    [output setReportsEnabled:NO];
    wnd->handle.nsobject = NULL;
    msg_Dbg(wnd, "disabling video window");

    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            /* Takes back the reference retained in WindowEnable; released on main. */
            MXRVideoSurfaceView *surface = (__bridge_transfer MXRVideoSurfaceView *)handle;
            [output detachSurface:surface];
        }
    });
}

static void WindowResize(vlc_window_t *wnd, unsigned width, unsigned height)
{
    MXRVideoOutput *output = (__bridge MXRVideoOutput *)wnd->sys;
    const CGSize size = CGSizeMake(width, height);

    dispatch_async(dispatch_get_main_queue(), ^{
        MXRInterfaceBridge *bridge = MXRCurrentInterfaceBridge();
        id<MXRVideoSurfaceProvider> provider = bridge.isShutDown ? nil : bridge.videoSurfaceProvider;
        if ([provider respondsToSelector:@selector(videoOutput:requestsSize:)])
            [provider videoOutput:output requestsSize:size];
    });
}

static void WindowSetState(vlc_window_t *wnd, unsigned state)
{
    MXRVideoOutput *output = (__bridge MXRVideoOutput *)wnd->sys;
    if (state & VLC_WINDOW_STATE_BELOW)
        msg_Dbg(wnd, "ignoring VLC_WINDOW_STATE_BELOW");
    const BOOL above = (state & VLC_WINDOW_STATE_ABOVE) != 0;

    dispatch_async(dispatch_get_main_queue(), ^{
        MXRInterfaceBridge *bridge = MXRCurrentInterfaceBridge();
        id<MXRVideoSurfaceProvider> provider = bridge.isShutDown ? nil : bridge.videoSurfaceProvider;
        if ([provider respondsToSelector:@selector(videoOutput:requestsFloatOnTop:)])
            [provider videoOutput:output requestsFloatOnTop:above];
    });
}

static void RequestFullscreen(vlc_window_t *wnd, BOOL fullscreen)
{
    MXRVideoOutput *output = (__bridge MXRVideoOutput *)wnd->sys;

    if (fullscreen && var_InheritBool(wnd, "video-wallpaper")) {
        msg_Dbg(wnd, "ignoring fullscreen request: video-wallpaper is on");
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        MXRInterfaceBridge *bridge = MXRCurrentInterfaceBridge();
        if (bridge == nil || bridge.isShutDown)
            return;
        [bridge.videoSurfaceProvider videoOutput:output requestsFullscreen:fullscreen];
    });
}

static void WindowSetFullscreen(vlc_window_t *wnd, const char *id)
{
    VLC_UNUSED(id); /* the output (screen) choice is ours: Settings > "Open fullscreen on" */
    RequestFullscreen(wnd, YES);
}

static void WindowUnsetFullscreen(vlc_window_t *wnd)
{
    RequestFullscreen(wnd, NO);
}

static void WindowDestroy(vlc_window_t *wnd)
{
    void *handle = wnd->handle.nsobject;
    wnd->handle.nsobject = NULL;
    MXRVideoOutput *output = CFBridgingRelease(wnd->sys);
    wnd->sys = NULL;
    [output stopObservingFilters];
    [output setReportsEnabled:NO];

    if (handle != NULL) {
        /* Not disabled first (enable failure paths): release the surface on main. */
        dispatch_async(dispatch_get_main_queue(), ^{
            @autoreleasepool {
                MXRVideoSurfaceView *surface = (__bridge_transfer MXRVideoSurfaceView *)handle;
                [output detachSurface:surface];
            }
        });
    }
}

static const struct vlc_window_operations mxr_window_ops = {
    .enable = WindowEnable,
    .disable = WindowDisable,
    .resize = WindowResize,
    .destroy = WindowDestroy,
    .set_state = WindowSetState,
    .unset_fullscreen = WindowUnsetFullscreen,
    .set_fullscreen = WindowSetFullscreen,
    .set_title = NULL, /* the title comes from the player model */
};

int MXRWindowOpen(vlc_window_t *wnd)
{
    /* Only while our interface runs: `-I dummy`-style runs fall back to window_macosx. */
    if (!atomic_load(&g_intf_started)) {
        msg_Dbg(wnd, "the macosx_redesign interface is not running");
        return VLC_EGENERIC;
    }

    MXRVideoOutput *output = [[MXRVideoOutput alloc] initWithWindow:wnd];
    if (output == nil)
        return VLC_ENOMEM;

    wnd->type = VLC_WINDOW_TYPE_NSOBJECT;
    wnd->info.has_double_click = true; /* the UI decides what a double click does */
    wnd->sys = (void *)CFBridgingRetain(output);
    wnd->ops = &mxr_window_ops;
    return VLC_SUCCESS;
}
