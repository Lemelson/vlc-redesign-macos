/*****************************************************************************
 * MXRInterfaceBridge.h: the interface's entry object, handed to Swift at startup
 *****************************************************************************
 * Copyright (C) 2026 VLC Redesign contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *****************************************************************************/

#import <AppKit/AppKit.h>

#import "MXRPlayerBridge.h"
#import "MXRVideoOutput.h"

NS_ASSUME_NONNULL_BEGIN

/// Log levels of `vlc_Log` (visible with `-vv`).
typedef NS_ENUM(NSInteger, MXRLogLevel) {
    MXRLogLevelInfo = 0,
    MXRLogLevelError = 1,
    MXRLogLevelWarning = 2,
    MXRLogLevelDebug = 3,
};

/// Owns the interface's view of the engine (intf_thread_t, main playlist, player).
/// Created on the main thread by MXROpenIntf and passed to `MXRSwiftStart`; it stays valid
/// until `MXRSwiftStop` returns. After shutdown every command is a no-op.
NS_SWIFT_UI_ACTOR
@interface MXRInterfaceBridge : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (nonatomic, readonly) MXRPlayerBridge *player;
@property (nonatomic, readonly) MXRServicesBridge *services;

/// Provides the surfaces VLC renders video into. Weak; set it before returning from
/// `MXRSwiftStart`, or the first video output fails.
@property (nonatomic, weak, nullable) id<MXRVideoSurfaceProvider> videoSurfaceProvider;

/// The VLC version the plugin was built from (`VERSION`, e.g. "4.0.0-dev").
@property (nonatomic, readonly, copy) NSString *vlcVersion;

/// A new, unattached video surface.
- (MXRVideoSurfaceView *)makeVideoSurface;

/// Appends URLs (files or network URLs) to the main playlist. With `play`, playback jumps
/// to the first appended item.
- (void)openURLs:(NSArray<NSURL *> *)urls play:(BOOL)play NS_SWIFT_NAME(open(_:play:));

/// Asks VLC to quit (`libvlc_Quit`). The engine then closes the interface (MXRSwiftStop)
/// and the process exits. Never call `exit()` or `-[NSApplication terminate:]` directly.
- (void)quit;

/// Writes to VLC's log (module "macosx_redesign"), visible with `-vv`.
- (void)log:(NSString *)message level:(MXRLogLevel)level NS_SWIFT_NAME(log(_:level:));

@end

NS_ASSUME_NONNULL_END
