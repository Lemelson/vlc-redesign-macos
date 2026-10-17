/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
#import <Foundation/Foundation.h>
#import "MXRBridgeKeys.h"

NS_ASSUME_NONNULL_BEGIN

/* Set on the conversion/stream player: its video windows ("Play locally while streaming")
 * never take the main player surface (MXRVoutWindow.m). */
#define MXR_AUXILIARY_VIDEO_VAR "macosx-redesign-auxiliary-video"

/* Internal engine helper. Include VLC types before this header; never expose to Swift. */
@interface MXRMediaServices : NSObject
- (nullable instancetype)initWithPlaylist:(vlc_playlist_t *)playlist interface:(intf_thread_t *)intf;
@property (nonatomic, copy, nullable) void (^serviceChanged)(NSString *service);
@property (nonatomic, readonly, copy) NSDictionary<NSString *, id> *capabilities;
- (NSDictionary<NSString *, id> *)snapshotForService:(MXRBridgeService)service;
- (BOOL)performCommand:(MXRBridgeCommand)command service:(MXRBridgeService)service
             arguments:(NSDictionary<NSString *, id> *)arguments error:(NSError **)error;
- (void)request:(MXRBridgeRequest)request service:(MXRBridgeService)service arguments:(NSDictionary<NSString *, id> *)arguments
      completion:(void (^)(NSDictionary<NSString *, id> * _Nullable, NSError * _Nullable))completion;
/// Main: unregister callbacks, cancel output and suppress queued events.
- (void)shutdown;
/// Interface thread after -shutdown: joins service workers before libvlc teardown.
- (void)finishShutdown;
@end

/// Builds and validates VLC sout syntax, without opening the source or writing a file.
FOUNDATION_EXPORT NSDictionary * _Nullable MXRCreateOutputDefinition(NSDictionary *arguments, NSError **error);

/// Trusted options for a new output input, from a fresh engine configuration snapshot.
FOUNDATION_EXPORT NSArray<NSString *> *MXROutputOptions(NSDictionary *definition, NSDictionary<NSString *, NSNumber *> *settings);

NS_ASSUME_NONNULL_END
