/*****************************************************************************
 * MXRPlatformServices.m: native PiP through the stock macOS system controller
 *****************************************************************************
 * Copyright (C) 2026 VLC Redesign contributors
 * Licensed under the GNU General Public License, version 2 or later.
 *****************************************************************************/

#import <AVKit/AVKit.h>
#import "MXRPlatformServices.h"
#import "../../../macosx/private/PIPSPI.h"

@interface MXRPictureInPictureController () <PIPViewControllerDelegate>
@end

@implementation MXRPictureInPictureController
{
    MXRVideoSurfaceView *_surface;
    MXRPlayerBridge *_player;
    PIPViewController *_pip;
    NSViewController *_content;
    BOOL _invalidated;
}

- (instancetype)initWithVideoSurface:(MXRVideoSurfaceView *)surface player:(MXRPlayerBridge *)player
{
    self = [super init];
    if (self) {
        _surface = surface;
        _player = player;
        // Keep an explicit AVKit class reference: merely importing its headers
        // can let a linker discard the framework before this dynamic lookup.
        (void)[AVPlayerView class];
        // No private framework is linked directly and no unavailable class is instantiated.
        Class pipClass = NSClassFromString(@"PIPViewController");
        if (pipClass != Nil && [pipClass instancesRespondToSelector:@selector(presentViewControllerAsPictureInPicture:)]) {
            _pip = [[pipClass alloc] init];
            _pip.delegate = self;
            _pip.userCanResize = YES;
        }
    }
    return self;
}

- (BOOL)isAvailable { return _pip != nil && !_invalidated; }
- (BOOL)isActive { return _content != nil; }

- (void)toggle
{
    if (self.isActive) {
        [self stop];
        return;
    }
    if (!self.isAvailable || !_surface.isInUse || self.returnView.window == nil)
        return;

    NSSize size = _surface.bounds.size;
    if (size.width < 1. || size.height < 1.)
        return;
    NSSize proposed = _surface.videoOutput.proposedSize;
    _pip.aspectRatio = proposed.width > 0. && proposed.height > 0. ? proposed : size;
    _pip.playing = _player.state == MXRPlayerStatePlaying;
    _pip.title = self.returnView.window.title;
    _pip.replacementWindow = self.returnView.window;
    _pip.replacementRect = [self.returnView convertRect:self.returnView.bounds toView:nil];

    _content = [[NSViewController alloc] init];
    [_surface removeFromSuperview];
    _surface.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _content.view = _surface;
    // Upstream presents on the next run-loop cycle: on macOS 26 a detached view
    // does not receive the layout callback older implementations waited for.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_invalidated && self->_content != nil) {
            [self->_pip presentViewControllerAsPictureInPicture:self->_content];
            [NSNotificationCenter.defaultCenter postNotificationName:MXRPictureInPictureActiveDidChangeNotification object:self];
        }
    });
}

- (void)stop
{
    if (_content != nil)
        [_pip dismissViewController:_content];
}

- (void)updatePlaying:(BOOL)playing { if (_pip.playing != playing) _pip.playing = playing; }

- (void)restoreSurface
{
    NSView *host = self.returnView;
    if (host != nil && _surface.superview != host) {
        [_surface removeFromSuperview];
        _surface.frame = host.bounds;
        _surface.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [host addSubview:_surface];
        host.needsLayout = YES;
    }
    BOOL wasActive = _content != nil;
    _content = nil;
    if (wasActive)
        [NSNotificationCenter.defaultCenter postNotificationName:MXRPictureInPictureActiveDidChangeNotification object:self];
}

- (void)invalidate
{
    _invalidated = YES;
    [self stop];
    _pip.delegate = nil;
    [self restoreSurface];
    _pip = nil;
    _player = nil;
}

- (BOOL)pipShouldClose:(PIPViewController *)pip { return YES; }

- (void)pipWillClose:(PIPViewController *)pip
{
    NSView *host = self.returnView;
    pip.replacementWindow = host.window;
    pip.replacementRect = [host convertRect:host.bounds toView:nil];
    [host.window makeKeyAndOrderFront:nil];
}

- (void)pipDidClose:(PIPViewController *)pip { [self restoreSurface]; }
- (void)pipActionPlay:(PIPViewController *)pip { [_player play]; }
- (void)pipActionPause:(PIPViewController *)pip { [_player pause]; }
- (void)pipActionStop:(PIPViewController *)pip { [_player pause]; }

@end
