/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
#import <Foundation/Foundation.h>
#import "MXRBridgeKeys.h"

typedef struct vlc_playlist vlc_playlist_t;
typedef struct intf_thread_t intf_thread_t;

NS_ASSUME_NONNULL_BEGIN

/// Private native helper. All public payloads contain Foundation values only.
@interface MXRSubtitleCueServices : NSObject
- (instancetype)initWithPlaylist:(vlc_playlist_t *)playlist interface:(intf_thread_t *)intf;
@property (nonatomic, readonly, copy) NSDictionary *capabilities;
/// Main: player/subtitleCues {id: selected native SPU track ID}.
/// Returns {cues:[{start,end,text}]} with times in microseconds. Unsupported
/// sources return an empty array; file reads and parsing run off-main.
- (void)request:(MXRBridgeRequest)request service:(MXRBridgeService)service arguments:(NSDictionary *)arguments
      completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion;
/// Main: detach player callbacks and complete outstanding requests once.
- (void)shutdown;
/// Off-main, after shutdown and before VLC teardown: drain the reader.
- (void)finishShutdown;
@end

/// Bounded, deterministic parser used by the reader and native regression tests.
/// format is srt, vtt, ass or ssa; malformed/unsupported/oversized data returns [].
FOUNDATION_EXPORT NSArray<NSDictionary *> *MXRParseSubtitleCues(NSData *data, NSString *format);

NS_ASSUME_NONNULL_END
