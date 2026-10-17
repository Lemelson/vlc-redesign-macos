/*****************************************************************************
 * MXRBridgeInternal.h: bridge internals shared by the Objective-C files of module/
 *****************************************************************************
 * Copyright (C) 2026 VLC Redesign contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *****************************************************************************/

/* Requires <vlc_common.h>, <vlc_interface.h> and <vlc_window.h> to be included first.
 * Never visible to Swift. */

#import "MXRBridgeAPI.h"

NS_ASSUME_NONNULL_BEGIN

/// Posted on main when the current title starts or stops taking the pointer (DVD menus).
#define MXRInteractiveVideoDidChangeNotification @"MXRInteractiveVideoDidChange"

@interface MXRInterfaceBridge ()
- (nullable instancetype)initWithInterface:(intf_thread_t *)intf NS_DESIGNATED_INITIALIZER;
/// Removes every engine listener; after this every command is a no-op. Main thread.
- (void)shutdown;
- (void)finishShutdown;
@property (nonatomic, readonly) intf_thread_t *intf;
@property (nonatomic, readonly, getter=isShutDown) BOOL shutDown;
@end

@interface MXRPlayerBridge ()
- (nullable instancetype)initWithPlaylist:(vlc_playlist_t *)playlist
                                interface:(intf_thread_t *)intf NS_DESIGNATED_INITIALIZER;
/// Removes the player listeners and timer (synchronous; no callback runs afterwards).
- (void)shutdown;
@end

@interface MXRServicesBridge ()
- (nullable instancetype)initWithPlaylist:(vlc_playlist_t *)playlist
                                interface:(intf_thread_t *)intf NS_DESIGNATED_INITIALIZER;
- (void)shutdown;
- (void)finishShutdown;
@end

/// The running interface's bridge. Main thread only. nil before start and after shutdown.
MXRInterfaceBridge * _Nullable MXRCurrentInterfaceBridge(void);
void MXRSetCurrentInterfaceBridge(MXRInterfaceBridge * _Nullable bridge);

NS_ASSUME_NONNULL_END
