/*****************************************************************************
 * MXRVideoOutput.h: video embedding ("vout window") as seen from Swift
 *****************************************************************************
 * Copyright (C) 2026 VLC Redesign contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *****************************************************************************/

/*
 * ARCHITECTURE.md §3.2. VLC asks our "vout window" submodule for an NSView; the bridge
 * asks the Swift MXRVideoSurfaceProvider which surface to use. The display module
 * (samplebufferdisplay) then adds its video and subtitle subviews inside that surface.
 * UI overlays must be siblings above the surface, never subviews of it (§3.3).
 */

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class MXRVideoOutput;

/// A layer-backed black container for VLC's display views. Create it with
/// `-[MXRInterfaceBridge makeVideoSurface]`. It reports its size in backing pixels to the
/// attached video output; never add subviews to it yourself.
NS_SWIFT_UI_ACTOR
@interface MXRVideoSurfaceView : NSView
/// The video output currently drawing into this surface, if any.
@property (nonatomic, readonly, weak, nullable) MXRVideoOutput *videoOutput;
/// True while a video output is attached.
@property (nonatomic, readonly, getter=isInUse) BOOL inUse;
@end

/// One VLC video output window (`vlc_window_t`). Created by the engine, handed to the provider.
NS_SWIFT_UI_ACTOR
@interface MXRVideoOutput : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// The size the engine proposed when enabling the window, in backing pixels (may be 0x0).
@property (nonatomic, readonly) CGSize proposedSize;
/// Whether the engine asked for fullscreen when enabling the window.
@property (nonatomic, readonly) BOOL wantsFullscreenAtStart;
/// A local copy of a stream job ("Play locally while streaming"), not the main player: it
/// gets its own window and never the persistent player surface.
@property (nonatomic, readonly, getter=isAuxiliary) BOOL auxiliary;
/// The surface this output draws into while enabled.
@property (nonatomic, readonly, weak, nullable) MXRVideoSurfaceView *surface;

/// Tell the engine the window actually entered (YES) or left (NO) fullscreen
/// (`vlc_window_ReportFullscreen` / `vlc_window_ReportWindowed`). Call it from
/// windowDidEnterFullScreen / windowDidExitFullScreen.
- (void)reportFullscreen:(BOOL)fullscreen NS_SWIFT_NAME(reportFullscreen(_:));
/// Tell the engine the user closed the window showing this output (`vlc_window_ReportClose`).
- (void)reportClose;
@end

/// The view that hosts a surface (any ancestor). While VLC takes the pointer (DVD menus,
/// mouse video filters) the surface asks it whether a click only closes a popup (D024).
NS_SWIFT_UI_ACTOR
@protocol MXRVideoSurfaceHost <NSObject>
- (BOOL)videoSurfaceClickClosesPopup;
@end

/// Implemented by the Swift UI. Called on the main thread.
NS_SWIFT_UI_ACTOR
@protocol MXRVideoSurfaceProvider <NSObject>
/// A video output is being enabled: return a surface that is not in use (made with
/// -makeVideoSurface), placed in a window, or nil to refuse (the video output then fails).
/// Called synchronously from the vout thread through the main queue: do not block.
- (nullable MXRVideoSurfaceView *)surfaceForVideoOutput:(MXRVideoOutput *)output
    NS_SWIFT_NAME(surface(for:));
/// The output was disabled and detached from its surface (end of video).
- (void)videoOutputDidStop:(MXRVideoOutput *)output NS_SWIFT_NAME(videoOutputDidStop(_:));
/// The engine wants this output fullscreen (YES) or windowed (NO). Toggle the window,
/// then call -reportFullscreen: when the transition is done. Must be a no-op when the
/// window is already in the requested state.
- (void)videoOutput:(MXRVideoOutput *)output requestsFullscreen:(BOOL)fullscreen
    NS_SWIFT_NAME(videoOutput(_:requestsFullscreen:));
@optional
/// The engine asks for a window size in backing pixels (`vlc_window_SetSize`), typically the
/// video size. The main player window may ignore it (it is user-sized).
- (void)videoOutput:(MXRVideoOutput *)output requestsSize:(CGSize)size
    NS_SWIFT_NAME(videoOutput(_:requestsSize:));
/// The engine asks to float the window above others (`VLC_WINDOW_STATE_ABOVE`) or not.
- (void)videoOutput:(MXRVideoOutput *)output requestsFloatOnTop:(BOOL)floatOnTop
    NS_SWIFT_NAME(videoOutput(_:requestsFloatOnTop:));
@end

NS_ASSUME_NONNULL_END
