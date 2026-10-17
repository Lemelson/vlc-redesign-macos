/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
#import <Foundation/Foundation.h>
#import "MXRBridgeKeys.h"

NS_ASSUME_NONNULL_BEGIN

/* Internal helper: include VLC types first. No engine types cross the Swift boundary. */
@interface MXRAudioServices : NSObject
- (instancetype)initWithPlaylist:(vlc_playlist_t *)playlist interface:(intf_thread_t *)intf;
@property (nonatomic, copy, nullable) void (^serviceChanged)(NSString *service);
@property (nonatomic, readonly, copy) NSDictionary<NSString *, id> *capabilities;
- (NSDictionary<NSString *, id> *)snapshotForService:(MXRBridgeService)service;
/// audioTest/start {mode?:0...7,deviceID?:String}, audioTest/cancel {}.
/// thumbnails/waveform {media:{url:String},bins:1...4096}; completion is always on main.
- (void)request:(MXRBridgeRequest)request service:(MXRBridgeService)service arguments:(NSDictionary<NSString *, id> *)arguments
      completion:(void (^)(NSDictionary<NSString *, id> * _Nullable, NSError * _Nullable))completion;
/// Main: cancel requests and unregister callbacks. Does not wait for the workers.
- (void)shutdown;
/// Interface thread after shutdown: joins readers, disposes the isolated player and tone file.
- (void)finishShutdown;
@end

/// 2.5 seconds, 48 kHz, signed little-endian 16-bit stereo PCM: left, silence, right.
FOUNDATION_EXPORT NSData *MXRCreateStereoTestWAV(void);

NS_ASSUME_NONNULL_END
