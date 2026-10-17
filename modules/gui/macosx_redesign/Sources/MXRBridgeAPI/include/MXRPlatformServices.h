/*****************************************************************************
 * MXRPlatformServices.h: native macOS services, independent of engine headers
 *****************************************************************************
 * Copyright (C) 2026 VLC Redesign contributors
 * Licensed under the GNU General Public License, version 2 or later.
 *****************************************************************************/

#import <AppKit/AppKit.h>
#import "MXRPlayerBridge.h"
#import "MXRVideoOutput.h"

NS_ASSUME_NONNULL_BEGIN

/// Posted on main by an MXRPictureInPictureController (the object) when it starts or stops
/// Picture in Picture; the services bridge reports it as `isPictureInPicture`.
extern NSNotificationName const MXRPictureInPictureActiveDidChangeNotification;

/// Uses the same system PiP controller as the stock macOS interface. The complete
/// video surface moves, preserving VLC's display and subtitle views.
NS_SWIFT_UI_ACTOR
@interface MXRPictureInPictureController : NSObject
- (instancetype)initWithVideoSurface:(MXRVideoSurfaceView *)surface
                              player:(MXRPlayerBridge *)player NS_SWIFT_NAME(init(videoSurface:player:));
@property (nonatomic, readonly, getter=isAvailable) BOOL available;
@property (nonatomic, readonly, getter=isActive) BOOL active;
/// Stable native host to restore the surface into after PiP closes.
@property (nonatomic, weak, nullable) NSView *returnView;
- (void)toggle;
- (void)stop;
- (void)updatePlaying:(BOOL)playing NS_SWIFT_NAME(updatePlaying(_:));
/// Restores the view and removes delegate callbacks during interface shutdown.
- (void)invalidate;
@end

NS_ASSUME_NONNULL_END
