/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
#import <Foundation/Foundation.h>
#import "MXRBridgeKeys.h"
#include <vlc_common.h>
#include <vlc_interface.h>
NS_ASSUME_NONNULL_BEGIN
typedef struct vlc_medialibrary_t vlc_medialibrary_t;
/* The track files the media library keeps for the media at `uri` (VLC_ML_MEDIA_ADD_EXTERNAL_MRL):
 * subtitles from Add Subtitles and soundtracks from Edit/Add Audio Tracks, in library order, each
 * {MXRLibraryTrackURL: mrl, MXRLibraryTrackAudio: BOOL}. The core does not load them by itself.
 * Calls vlc_ml_* on the caller's thread (the bridge's work queue). */
extern NSString *const MXRLibraryTrackURL;
extern NSString *const MXRLibraryTrackAudio;
NSArray<NSDictionary *> *MXRLibraryExternalTracks(vlc_medialibrary_t *ml, const char *_Nullable uri);
/* Adds `tracks` to `item` as user slaves, subtitles as SLAVE_TYPE_SPU and soundtracks as
 * SLAVE_TYPE_GENERIC: the input loads them when it starts and, at SLAVE_PRIORITY_USER, selects
 * the first of each (src/input/input.c LoadSlaves). Call only while the item has no input. */
void MXRLibraryAddTrackSlaves(input_item_t *item, NSArray<NSDictionary *> *tracks);
/* Selects the first of `tracks`' soundtracks that the playing input exposes (a slave source
 * prefixes its ES ids with the MD5 of its MRL). VLC autoselects a forced generic slave only over
 * a main track of lower priority (src/input/es_out.c EsOutSelectMatchPrioritized), so the audio
 * the user attached to this media is selected explicitly. Player locked; YES if one was. */
typedef struct vlc_player_t vlc_player_t;
BOOL MXRLibrarySelectSoundtrack(vlc_player_t *player, NSArray<NSDictionary *> *tracks);
@interface MXRLibraryServices : NSObject
- (instancetype)initWithInterface:(intf_thread_t *)intf;
@property(nonatomic,copy,nullable) void (^serviceChanged)(NSString *);
@property(nonatomic,readonly) BOOL available;
- (NSDictionary *)snapshot;
/* Main-thread cache; a first access queues a lookup and publishes after completion. */
- (nullable NSDictionary *)cachedMediaForURL:(NSString *)url;
- (void)request:(MXRBridgeRequest)request arguments:(NSDictionary *)arguments completion:(void (^)(NSDictionary * _Nullable,NSError * _Nullable))completion;
- (void)shutdown;
- (void)finishShutdown;
@end
NS_ASSUME_NONNULL_END
