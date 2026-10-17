/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#import <Cocoa/Cocoa.h>
#include <os/signpost.h>
#import "MXRBridgeKeys.h"
#include <stdatomic.h>
#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_input_item.h>
#include <vlc_input.h>
#include <vlc_player.h>
#include <vlc_playlist.h>
#include <vlc_window.h>
#include <vlc_aout.h>
#include <vlc_vout.h>
#include <vlc_configuration.h>
#include <vlc_modules.h>
#include <vlc_plugin.h>
#include <vlc_actions.h>
#include <vlc_hash.h>
#include <vlc_url.h>
#include <vlc_strings.h>
#include <vlc_media_library.h>
#import "MXRBridgeInternal.h"
#import "MXRLibraryServices.h"
#import "MXRDialogServices.h"
#import "MXRThumbnailServices.h"
#import "MXREffectsServices.h"
#import "MXRMediaServices.h"
#import "MXRDiscoveryServices.h"
#import "MXRAudioServices.h"
#import "MXRAudioPreferenceServices.h"
#import "MXRSubtitleCueServices.h"

/*
 * Threading and cost (ARCHITECTURE §2.3, §8; review findings ARC-02, BB-02, ENG-M3):
 *  - Engine callbacks never build snapshots. Each one marks the player topic it affects
 *    (MXRTopic) and at most one main-queue hop flushes every marked topic; the Swift side
 *    re-reads only those topics.
 *  - Commands are fire-and-forget: they never notify synchronously. The engine callback
 *    reports the change; commands whose effect has no engine callback mark their topic.
 *  - Audio devices are listed only on a device change or an explicit refresh, effect
 *    variables only when an effect, a vout or the media changes.
 */

static NSString *S(const char *value) { return value ? ([NSString stringWithUTF8String:value] ?: @"") : @""; }
static NSString *OwnedString(char *value) { NSString *s = S(value); free(value); return s; }
static int64_t Time(vlc_tick_t value) { return value == VLC_TICK_INVALID ? -1 : US_FROM_VLC_TICK(value); }
static NSError *Error(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"MXRVLCBridge" code:code userInfo:@{NSLocalizedDescriptionKey:message}];
}
static BOOL Fail(NSError **error, NSString *message) { if (error) *error = Error(1, message); return NO; }
static enum es_format_category_e Category(NSString *kind) {
    if ([kind isEqual:@"audio"]) return AUDIO_ES;
    if ([kind isEqual:@"video"]) return VIDEO_ES;
    if ([kind isEqual:@"subtitle"]) return SPU_ES;
    return UNKNOWN_ES;
}
/// The file name of a URI ("The_Wand_S01E04.mkv"), percent-decoded; nil for URIs without one.
static NSString *FileNameForURI(NSString *uri) {
    NSURL *url = [NSURL URLWithString:uri];
    NSString *name = url.isFileURL ? url.lastPathComponent : url.lastPathComponent.stringByRemovingPercentEncoding;
    return name.length && ![name isEqual:@"/"] ? name : nil;
}
static NSDictionary *Media(input_item_t *item) {
    NSString *uri = OwnedString(input_item_GetURI(item));
    NSString *title = OwnedString(input_item_GetTitleFbName(item));
    NSMutableDictionary *result = [@{@"id":uri, @"url":uri, @"title":title,
        @"duration":@(Time(input_item_GetDuration(item))), @"kind":@"unknown"} mutableCopy];
    NSString *fileName = FileNameForURI(uri);
    if (fileName) result[MXRPlayerKeyFileName] = fileName;
    NSString *art = OwnedString(input_item_GetArtworkURL(item));
    if (art.length) result[@"artworkURL"] = art;
    NSString *artist = OwnedString(input_item_GetArtist(item)), *album = OwnedString(input_item_GetAlbum(item));
    if (artist.length) result[@"artist"] = artist;
    if (album.length) result[@"album"] = album;
    BOOL audio = NO, video = NO;
    vlc_mutex_lock(&item->lock);
    for (size_t i = 0; i < item->es_vec.size; i++) { audio |= item->es_vec.data[i].es.i_cat == AUDIO_ES; video |= item->es_vec.data[i].es.i_cat == VIDEO_ES; }
    vlc_mutex_unlock(&item->lock);
    result[@"kind"] = video ? @"video" : audio ? @"audio" : @"unknown";
    result[@"isFavorite"] = @NO;
    return result;
}
static NSString *MD5Hex(const char *text) {
    char hex[VLC_HASH_MD5_DIGEST_HEX_SIZE];
    vlc_hash_md5_t md5;
    vlc_hash_md5_Init(&md5);
    vlc_hash_md5_Update(&md5, text, strlen(text));
    vlc_hash_FinishHex(&md5, hex);
    return S(hex);
}
/// The MRL VLC itself builds for a local file (vlc_path2uri percent-encodes characters such
/// as ( ) ' that NSURL leaves alone), so its MD5 matches the source prefix of a sidecar the
/// input detected on its own. Other URLs are returned unchanged.
static NSString *CanonicalMRL(NSString *url) {
    if (![url.lowercaseString hasPrefix:@"file:"]) return url;
    char *path = vlc_uri2path(url.UTF8String);
    char *mrl = path ? vlc_path2uri(path, "file") : NULL;
    NSString *result = mrl ? S(mrl) : url;
    free(mrl); free(path);
    return result;
}
/// The source of an ES id: slave sources prefix their ES ids with the MD5 of their MRL
/// ("<md5>/spu/0", src/input/input.c InputSourceNew and es_out.c EsOutCreateStrId); the
/// main source's ids have no prefix ("spu/2").
static NSString *SourceHashOfTrack(NSString *strID) {
    NSRange slash = [strID rangeOfString:@"/"];
    if (slash.location != VLC_HASH_MD5_DIGEST_HEX_SIZE - 1) return nil;
    NSString *prefix = [strID substringToIndex:slash.location];
    return [prefix rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"].invertedSet].location == NSNotFound ? prefix : nil;
}
/// MRLs of the current media's slaves (sidecar subtitles, added tracks), by source hash.
static NSDictionary<NSString *, NSString *> *SlaveURLsByHash(input_item_t *item, NSArray<NSString *> *extra) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (item) {
        vlc_mutex_lock(&item->lock);
        for (int i = 0; i < item->i_slaves; i++) result[MD5Hex(item->pp_slaves[i]->psz_uri)] = S(item->pp_slaves[i]->psz_uri);
        vlc_mutex_unlock(&item->lock);
    }
    for (NSString *url in extra) result[MD5Hex(url.UTF8String)] = url;
    return result;
}
static NSArray *Tracks(vlc_player_t *player, enum es_format_category_e category, NSDictionary<NSString *, NSString *> *slaves) {
    NSMutableArray *result = [NSMutableArray array];
    NSCountedSet *sources = [NSCountedSet set];
    size_t count = vlc_player_GetTrackCount(player, category);
    for (size_t i = 0; i < count; i++) {
        NSString *hash = SourceHashOfTrack(S(vlc_es_id_GetStrId(vlc_player_GetTrackAt(player, category, i)->es_id)));
        if (hash) [sources addObject:hash];
    }
    for (size_t i = 0; i < count; i++) {
        const struct vlc_player_track *track = vlc_player_GetTrackAt(player, category, i);
        NSString *strID = S(vlc_es_id_GetStrId(track->es_id)), *name = S(track->name);
        NSMutableDictionary *d = [@{MXRPlayerKeyID:strID, MXRPlayerKeyName:name, MXRPlayerKeySelected:@(track->selected)} mutableCopy];
        if (track->fmt.psz_language) d[MXRPlayerKeyLanguage] = S(track->fmt.psz_language);
        const char *codec = vlc_fourcc_GetDescription(track->fmt.i_cat, track->fmt.i_codec);
        if (codec && *codec) d[MXRPlayerKeyCodec] = S(codec);
        if (category == VIDEO_ES) { d[MXRPlayerKeyWidth] = @(track->fmt.video.i_visible_width); d[MXRPlayerKeyHeight] = @(track->fmt.video.i_visible_height); }
        NSString *hash = SourceHashOfTrack(strID);
        if (hash) {
            /* External Tracks (S20, §04/§06): named after the file they came from. */
            d[MXRPlayerKeyExternal] = @YES;
            NSString *url = slaves[hash], *fileName = url ? FileNameForURI(url) : nil;
            if (url) d[MXRPlayerKeyURL] = url;
            if (fileName) d[MXRPlayerKeyName] = [sources countForObject:hash] > 1 && name.length
                ? [NSString stringWithFormat:@"%@ [%@]", fileName, name] : fileName;
        }
        [result addObject:d];
    }
    return result;
}
static NSArray *Chapters(const struct vlc_player_title *title) {
    NSMutableArray *result = [NSMutableArray array];
    if (title) for (size_t i = 0; i < title->chapter_count; i++)
        [result addObject:@{MXRPlayerKeyIndex:@(i), MXRPlayerKeyName:S(title->chapters[i].name), MXRPlayerKeyTime:@(Time(title->chapters[i].time))}];
    return result;
}
static id ConfigValue(const char *name) {
    module_config_t *option = config_FindConfig(name);
    if (!option) return nil;
    int type = option->i_type;
    if (IsConfigIntegerType(type)) return @(config_GetInt(name));
    if (IsConfigFloatType(type)) return @(config_GetFloat(name));
    if (IsConfigStringType(type)) return OwnedString(config_GetPsz(name));
    return nil;
}
static id OriginalValue(module_config_t *c) {
    if (IsConfigIntegerType(c->i_type)) return @(c->orig.i);
    if (IsConfigFloatType(c->i_type)) return @(c->orig.f);
    return S(c->orig.psz);
}
static NSString *ConfigType(int type) {
    switch (type) {
        case CONFIG_ITEM_BOOL: return @"bool"; case CONFIG_ITEM_INTEGER: return @"integer";
        case CONFIG_ITEM_RGB: return @"color"; case CONFIG_ITEM_FLOAT: return @"float";
        case CONFIG_ITEM_PASSWORD: return @"password"; case CONFIG_ITEM_KEY: return @"key";
        case CONFIG_ITEM_MODULE: case CONFIG_ITEM_MODULE_CAT: return @"module";
        case CONFIG_ITEM_MODULE_LIST: case CONFIG_ITEM_MODULE_LIST_CAT: return @"moduleList";
        case CONFIG_ITEM_DIRECTORY: return @"directory";
        case CONFIG_ITEM_LOADFILE: case CONFIG_ITEM_SAVEFILE: return @"file";
        default: return @"string";
    }
}
static BOOL UnsupportedSetting(NSString *name) {
    static NSSet *names; static dispatch_once_t once;
    dispatch_once(&once, ^{ names = [NSSet setWithArray:@[@"macosx-redesign-update-check", @"macosx-redesign-custom-skin", @"macosx-redesign-skin-file", @"macosx-redesign-lastfm", @"macosx-redesign-web-remote", @"macosx-redesign-cast-quality", @"macosx-redesign-discover-renderers", @"macosx-redesign-sub-position", @"macosx-redesign-sub-ignore-styles"]]; });
    return [names containsObject:name];
}
static BOOL AllowsPositionForURL(NSString *url) {
    id remembers = ConfigValue("macosx-redesign-remember-position"); if (remembers && ![remembers boolValue]) return NO;
    NSString *exclusions = ConfigValue("macosx-redesign-history-exclude") ?: @"";
    NSString *filename = [NSURL URLWithString:url].lastPathComponent ?: url;
    for (NSString *word in [exclusions componentsSeparatedByString:@","]) {
        NSString *token = [word stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (token.length && [filename rangeOfString:token options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound) return NO;
    }
    return YES;
}
static int SetInputOption(input_item_t *item, NSString *name, NSString *value) {
    NSString *option = [NSString stringWithFormat:@"%@=%@", name, value]; char *replacement = strdup(option.UTF8String); if (!replacement) return VLC_ENOMEM;
    vlc_mutex_lock(&item->lock);
    for (int i = item->i_options - 1; i >= 0; i--) {
        const char *old = item->ppsz_options[i]; if (*old == ':') old++;
        if (!strncmp(old, name.UTF8String, name.length) && old[name.length] == '=') {
            free(item->ppsz_options[i]); item->ppsz_options[i] = replacement; item->optflagv[i] = VLC_INPUT_OPTION_TRUSTED;
            vlc_mutex_unlock(&item->lock); return VLC_SUCCESS;
        }
    }
    vlc_mutex_unlock(&item->lock); free(replacement);
    return input_item_AddOption(item, option.UTF8String, VLC_INPUT_OPTION_TRUSTED);
}
static int ApplyInputPrivacy(input_item_t *item) {
    NSString *url = OwnedString(input_item_GetURI(item)); BOOL remember = AllowsPositionForURL(url);
    BOOL save = config_GetInt("save-recentplay") != 0 && remember;
    int result = SetInputOption(item, @"save-recentplay", save ? @"1" : @"0"); if (result != VLC_SUCCESS) return result;
    NSInteger restore = remember ? config_GetInt("restore-playback-pos") : VLC_PLAYER_RESTORE_PLAYBACK_POS_NEVER;
    return SetInputOption(item, @"restore-playback-pos", [@(restore) stringValue]);
}

#include "MXRHotkeyFeedback.inc"

/// Player topics (MXRBridgeService.player*) plus the queue, settings and shortcuts.
typedef NS_OPTIONS(unsigned, MXRTopic) {
    MXRTopicState = 1u << 0, MXRTopicMedia = 1u << 1, MXRTopicTracks = 1u << 2, MXRTopicTitles = 1u << 3,
    MXRTopicSync = 1u << 4, MXRTopicEffects = 1u << 5, MXRTopicVolume = 1u << 6, MXRTopicDevices = 1u << 7,
    MXRTopicStatistics = 1u << 8, MXRTopicTeletext = 1u << 9, MXRTopicSnapshot = 1u << 10,
    MXRTopicQueue = 1u << 11, MXRTopicSettings = 1u << 12, MXRTopicShortcuts = 1u << 13, MXRTopicQueueState = 1u << 14,
    MXRTopicLast = MXRTopicQueueState,
    /// What a different current media can change.
    MXRTopicNewMedia = MXRTopicState | MXRTopicMedia | MXRTopicTracks | MXRTopicTitles | MXRTopicSync
                     | MXRTopicEffects | MXRTopicStatistics | MXRTopicTeletext,
    MXRTopicAllPlayer = MXRTopicNewMedia | MXRTopicVolume | MXRTopicDevices | MXRTopicSnapshot,
};
static MXRBridgeService TopicService(MXRTopic topic) {
    switch (topic) {
        case MXRTopicState: return MXRBridgeServicePlayerState;
        case MXRTopicMedia: return MXRBridgeServicePlayerMedia;
        case MXRTopicTracks: return MXRBridgeServicePlayerTracks;
        case MXRTopicTitles: return MXRBridgeServicePlayerTitles;
        case MXRTopicSync: return MXRBridgeServicePlayerSync;
        case MXRTopicEffects: return MXRBridgeServicePlayerEffects;
        case MXRTopicVolume: return MXRBridgeServicePlayerVolume;
        case MXRTopicDevices: return MXRBridgeServicePlayerDevices;
        case MXRTopicStatistics: return MXRBridgeServicePlayerStatistics;
        case MXRTopicTeletext: return MXRBridgeServicePlayerTeletext;
        case MXRTopicSnapshot: return MXRBridgeServicePlayerSnapshot;
        case MXRTopicQueue: return MXRBridgeServiceQueue;
        case MXRTopicQueueState: return MXRBridgeServiceQueueState;
        case MXRTopicSettings: return MXRBridgeServiceSettings;
        case MXRTopicShortcuts: return MXRBridgeServiceShortcuts;
        default: return nil;
    }
}

@interface MXRServicesBridge ()
- (void)changed:(MXRBridgeService)service;
- (void)scheduleTopics:(unsigned)topics;
- (void)queueModeChanged:(bool)persist;
- (void)storeBuffering:(float)value;
- (void)applyStoppedAction:(NSInteger)value;
- (void)applyCurrentMediaChanged;
- (void)applyRestoreQueryForURL:(NSString *)url;
- (void)applyPlayerState:(NSInteger)state;
- (void)applyVoutStarted:(NSString *)title timeout:(double)seconds mediaURL:(NSString *)url;
- (void)applySnapshotFile:(NSString *)path;
- (void)awaitedFeedbackArrived:(int)kind;
- (void)hotkeySeekReportedAt:(vlc_tick_t)time length:(vlc_tick_t)length;
- (void)navigationSeekReportedAt:(vlc_tick_t)time length:(vlc_tick_t)length;
- (void)subtitleVoutStarted:(vout_thread_t *)vout order:(enum vlc_vout_order)order;
@end

#pragma mark - Engine callbacks (any thread; never build snapshots)

/* Engine callbacks have fixed signatures; most ignore the player and payload arguments. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-parameter"

static inline MXRServicesBridge *Bridge(void *data) { return (__bridge MXRServicesBridge *)data; }
#define TOPIC_CB(name, topics, signature) static void name signature { [Bridge(data) scheduleTopics:(topics)]; }
static const char StartPausedOption[] = ":start-paused";
@interface MXRServicesBridge (StartPaused)
- (void)dropStartPausedItem;
@end
static void PlayerMedia(vlc_player_t *p, input_item_t *m, void *data) {
    /* Synchronous, under the player lock: the input for m exists and has read its options.
     * A failed vlc_player_input_New reports NULL instead: the paused start will not happen,
     * so the one-shot option goes either way. */
    [Bridge(data) dropStartPausedItem];
    __weak MXRServicesBridge *bridge = Bridge(data);
    dispatch_async(dispatch_get_main_queue(), ^{ [bridge applyCurrentMediaChanged]; });
}
static void PlayerRestore(vlc_player_t *p, void *data) {
    input_item_t *media = vlc_player_GetCurrentMedia(p); NSString *uri = media ? OwnedString(input_item_GetURI(media)) : @"";
    __weak MXRServicesBridge *bridge = Bridge(data);
    dispatch_async(dispatch_get_main_queue(), ^{ [bridge applyRestoreQueryForURL:uri]; });
}
static void PlayerState(vlc_player_t *p, enum vlc_player_state state, void *data) {
    /* Under the player lock. The player reports STOPPED only after it tried to open its next
     * media (src/player/input.c, STOPPED case), so a paused start still pending here was
     * dropped by a Stop that won the race and never reports a media change. */
    if (state == VLC_PLAYER_STATE_STOPPED) [Bridge(data) dropStartPausedItem];
    __weak MXRServicesBridge *bridge = Bridge(data);
    dispatch_async(dispatch_get_main_queue(), ^{ [bridge applyPlayerState:state]; });
}
TOPIC_CB(PlayerMetadata, MXRTopicMedia, (vlc_player_t *p, input_item_t *m, void *data))
TOPIC_CB(PlayerError, MXRTopicState, (vlc_player_t *p, enum vlc_player_error e, void *data))
static void PlayerBuffering(vlc_player_t *p, float value, void *data) { [Bridge(data) storeBuffering:value]; }
TOPIC_CB(PlayerCaps, MXRTopicState, (vlc_player_t *p, int old, int new, void *data))
TOPIC_CB(PlayerSubtitleFPS, MXRTopicSync, (vlc_player_t *p, float value, void *data))
TOPIC_CB(PlayerDelay, MXRTopicSync, (vlc_player_t *p, enum es_format_category_e c, vlc_tick_t t, void *data))
TOPIC_CB(PlayerTrackList, MXRTopicTracks | MXRTopicMedia, (vlc_player_t *p, enum vlc_player_list_action a, const struct vlc_player_track *t, void *data))
TOPIC_CB(PlayerTitles, MXRTopicTitles, (vlc_player_t *p, vlc_player_title_list *t, void *data))
TOPIC_CB(PlayerTitle, MXRTopicTitles, (vlc_player_t *p, const struct vlc_player_title *t, size_t i, void *data))
TOPIC_CB(PlayerChapter, MXRTopicTitles, (vlc_player_t *p, const struct vlc_player_title *t, size_t i, const struct vlc_player_chapter *c, size_t j, void *data))
TOPIC_CB(PlayerProgram, MXRTopicTitles, (vlc_player_t *p, enum vlc_player_list_action a, const struct vlc_player_program *t, void *data))
TOPIC_CB(PlayerRecording, MXRTopicState, (vlc_player_t *p, bool b, void *data))
TOPIC_CB(PlayerLoop, MXRTopicState, (vlc_player_t *p, enum vlc_player_abloop s, vlc_tick_t t, double pos, void *data))
TOPIC_CB(PlayerStatistics, MXRTopicStatistics, (vlc_player_t *p, const struct input_stats_t *s, void *data))
TOPIC_CB(PlayerTeletextBool, MXRTopicTeletext, (vlc_player_t *p, bool b, void *data))
TOPIC_CB(PlayerTeletextPage, MXRTopicTeletext, (vlc_player_t *p, unsigned v, void *data))
static void PlayerRate(vlc_player_t *p, float rate, void *data) {
    [Bridge(data) scheduleTopics:MXRTopicState];
    __weak MXRServicesBridge *bridge = Bridge(data);
    dispatch_async(dispatch_get_main_queue(), ^{ [bridge awaitedFeedbackArrived:MXRFeedbackAwaitRate]; });
}
static void PlayerSelection(vlc_player_t *p, vlc_es_id_t *unselected, vlc_es_id_t *selected, void *data) {
    [Bridge(data) scheduleTopics:MXRTopicTracks];
    vlc_es_id_t *id = selected ?: unselected;
    enum es_format_category_e category = id ? vlc_es_id_GetCat(id) : UNKNOWN_ES;
    int kind = category == AUDIO_ES ? MXRFeedbackAwaitAudio : category == SPU_ES ? MXRFeedbackAwaitSubtitle : MXRFeedbackAwaitNone;
    if (kind == MXRFeedbackAwaitNone) return;
    __weak MXRServicesBridge *bridge = Bridge(data);
    /* A cycle unselects, then selects: read the outcome once both have arrived. */
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [bridge awaitedFeedbackArrived:kind]; });
}
static void PlayerProgramSelection(vlc_player_t *p, int unselected, int selected, void *data) {
    [Bridge(data) scheduleTopics:MXRTopicTitles];
    __weak MXRServicesBridge *bridge = Bridge(data);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [bridge awaitedFeedbackArrived:MXRFeedbackAwaitProgram]; });
}
static void PlayerVout(vlc_player_t *p, enum vlc_player_vout_action action, vout_thread_t *vout, enum vlc_vout_order order, vlc_es_id_t *es_id, void *data) {
    [Bridge(data) scheduleTopics:MXRTopicEffects | MXRTopicState];
    /* A new (or reused) vout starts below the UI's overlays too: raise its subtitles now, while
     * the callback holds it. */
    if (action == VLC_PLAYER_VOUT_STARTED) [Bridge(data) subtitleVoutStarted:vout order:order];
    if (action != VLC_PLAYER_VOUT_STARTED || order != VLC_VOUT_ORDER_PRIMARY || !var_InheritBool(vout, "video-title-show")) return;
    /* "Show filename when a video starts": the core draws it through the OSD, which is
     * off for this interface (resource.c DisplayVoutTitle); show it in the redesign OSD. */
    input_item_t *media = vlc_player_GetCurrentMedia(p);
    if (!media) return;
    NSString *title = OwnedString(input_item_GetNowPlayingFb(media));
    if (!title.length) {
        NSString *name = OwnedString(input_item_GetTitle(media)), *artist = OwnedString(input_item_GetArtist(media));
        title = name.length && artist.length ? [NSString stringWithFormat:@"%@ - %@", artist, name] : name.length ? name : OwnedString(input_item_GetTitleFbName(media));
    }
    NSString *url = OwnedString(input_item_GetURI(media));
    double seconds = var_InheritInteger(vout, "video-title-timeout") / 1000.0;
    __weak MXRServicesBridge *bridge = Bridge(data);
    dispatch_async(dispatch_get_main_queue(), ^{ [bridge applyVoutStarted:title timeout:seconds mediaURL:url]; });
}
/* Registering the frame-step listeners suppresses the core's "Next frame" OSD after every
 * paused seek and its modal frame-step error dialogs (src/player/input.c:941-953, ARC-12). */
static void PlayerNextFrameStatus(vlc_player_t *p, int status, void *data) { VLC_UNUSED(p); VLC_UNUSED(status); VLC_UNUSED(data); }
static void PlayerPrevFrameStatus(vlc_player_t *p, int status, void *data) { VLC_UNUSED(p); VLC_UNUSED(status); VLC_UNUSED(data); }
static const struct vlc_player_cbs PlayerCallbacks = {
    .on_current_media_changed = PlayerMedia, .on_state_changed = PlayerState, .on_error_changed = PlayerError,
    .on_buffering_changed = PlayerBuffering, .on_rate_changed = PlayerRate, .on_capabilities_changed = PlayerCaps,
    .on_track_list_changed = PlayerTrackList, .on_track_selection_changed = PlayerSelection,
    .on_titles_changed = PlayerTitles, .on_title_selection_changed = PlayerTitle, .on_chapter_selection_changed = PlayerChapter,
    .on_program_list_changed = PlayerProgram, .on_program_selection_changed = PlayerProgramSelection,
    .on_category_delay_changed = PlayerDelay, .on_associated_subs_fps_changed = PlayerSubtitleFPS,
    .on_recording_changed = PlayerRecording, .on_atobloop_changed = PlayerLoop, .on_media_meta_changed = PlayerMetadata,
    .on_teletext_menu_changed = PlayerTeletextBool, .on_teletext_enabled_changed = PlayerTeletextBool,
    .on_teletext_page_changed = PlayerTeletextPage, .on_teletext_transparency_changed = PlayerTeletextBool,
    .on_statistics_changed = PlayerStatistics, .on_vout_changed = PlayerVout,
    .on_playback_restore_queried = PlayerRestore,
    .on_next_frame_status = PlayerNextFrameStatus, .on_prev_frame_status = PlayerPrevFrameStatus,
};
static void VoutFullscreen(vout_thread_t *vout, bool enabled, void *data) { [Bridge(data) scheduleTopics:MXRTopicState]; }
static const struct vlc_player_vout_cbs VoutCallbacks = { .on_fullscreen_changed = VoutFullscreen };
static void QueueReset(vlc_playlist_t *p, vlc_playlist_item_t *const items[], size_t n, void *data) {
    for (size_t i = 0; i < n; i++) ApplyInputPrivacy(vlc_playlist_item_GetMedia(items[i]));
    [Bridge(data) scheduleTopics:MXRTopicQueue];
}
static void QueueAdded(vlc_playlist_t *p, size_t index, vlc_playlist_item_t *const items[], size_t n, void *data) {
    for (size_t i = 0; i < n; i++) ApplyInputPrivacy(vlc_playlist_item_GetMedia(items[i]));
    [Bridge(data) scheduleTopics:MXRTopicQueue];
}
TOPIC_CB(QueueItems, MXRTopicQueue, (vlc_playlist_t *p, size_t i, vlc_playlist_item_t *const items[], size_t n, void *data))
TOPIC_CB(QueueMove, MXRTopicQueue, (vlc_playlist_t *p, size_t i, size_t n, size_t j, void *data))
TOPIC_CB(QueueRemove, MXRTopicQueue, (vlc_playlist_t *p, size_t i, size_t n, void *data))
TOPIC_CB(QueueIndex, MXRTopicQueueState, (vlc_playlist_t *p, ssize_t i, void *data))
TOPIC_CB(QueueBool, MXRTopicQueueState, (vlc_playlist_t *p, bool b, void *data))
/* Repeat and order persist however they change: our queue commands, a VLC hotkey action,
 * another playlist client (C-12). */
static bool PutIntIfChanged(const char *name, int64_t value) {
    if (config_GetInt(name) == value) return false;
    config_PutInt(name, value); return true;
}
static void QueueRepeat(vlc_playlist_t *p, enum vlc_playlist_playback_repeat value, void *data) {
    bool changed = PutIntIfChanged("loop", value == VLC_PLAYLIST_PLAYBACK_REPEAT_ALL);
    changed |= PutIntIfChanged("repeat", value == VLC_PLAYLIST_PLAYBACK_REPEAT_CURRENT);
    [Bridge(data) queueModeChanged:changed];
}
static void QueueOrder(vlc_playlist_t *p, enum vlc_playlist_playback_order value, void *data) {
    [Bridge(data) queueModeChanged:PutIntIfChanged("random", value == VLC_PLAYLIST_PLAYBACK_ORDER_RANDOM)];
}
static void QueueStopAction(vlc_playlist_t *p, enum vlc_playlist_media_stopped_action value, void *data) {
    __weak MXRServicesBridge *bridge = Bridge(data);
    dispatch_async(dispatch_get_main_queue(), ^{ [bridge applyStoppedAction:value]; });
}
static const struct vlc_playlist_callbacks QueueCallbacks = {
    .on_items_reset = QueueReset, .on_items_added = QueueAdded, .on_items_updated = QueueItems,
    .on_items_moved = QueueMove, .on_items_removed = QueueRemove, .on_current_index_changed = QueueIndex,
    .on_has_next_changed = QueueBool, .on_has_prev_changed = QueueBool,
    .on_playback_repeat_changed = QueueRepeat, .on_playback_order_changed = QueueOrder,
    .on_media_stopped_action_changed = QueueStopAction,
};
static void AudioVolume(audio_output_t *a, float v, void *data) {
    [Bridge(data) scheduleTopics:MXRTopicVolume];
    __weak MXRServicesBridge *bridge = Bridge(data);
    /* An arrow key's volume step lands here from the input thread (navigation fallback). */
    dispatch_async(dispatch_get_main_queue(), ^{ [bridge awaitedFeedbackArrived:MXRFeedbackAwaitVolume]; });
}
TOPIC_CB(AudioMute, MXRTopicVolume, (audio_output_t *a, bool v, void *data))
TOPIC_CB(AudioDevice, MXRTopicDevices, (audio_output_t *a, const char *v, void *data))
static const struct vlc_player_aout_cbs AudioCallbacks = {.on_volume_changed = AudioVolume, .on_mute_changed = AudioMute, .on_device_changed = AudioDevice};
/* A jump hotkey's OSD text is the target the core seeks to (vlc_player_input_SeekByTime adds the
 * jump to a seek still in flight). The timer reports it on_seek, synchronously on the thread that
 * seeks (before input_ControlPush), under the timer lock. The hotkeys module runs key-action on
 * the caller's thread, so the report of a jump triggered from main arrives on main while
 * triggerAction is still inside var_SetInteger; it is taken there and only there. Chapter keys and
 * the seek bar seek on main outside that call and never count. A plain arrow has no synchronous
 * seek: the core jumps later on the input thread (vlc_player_input_NavigationFallback); main-thread
 * seeks never fill its slot, only the next input-thread report does. Updates are not used. */
static void SeekFeedbackUpdate(const struct vlc_player_timer_point *value, void *data) {}
static void SeekFeedbackSeek(const struct vlc_player_timer_point *value, void *data) {
    if (value == NULL || value->ts == VLC_TICK_INVALID) return;
    const vlc_tick_t time = value->ts, length = value->live ? VLC_TICK_INVALID : value->length;
    if (pthread_main_np()) { [Bridge(data) hotkeySeekReportedAt:time length:length]; return; }
    __weak MXRServicesBridge *bridge = Bridge(data);
    dispatch_async(dispatch_get_main_queue(), ^{ [bridge navigationSeekReportedAt:time length:length]; });
}
static const struct vlc_player_timer_cbs SeekFeedbackTimer = {.on_update = SeekFeedbackUpdate, .on_seek = SeekFeedbackSeek};
#pragma clang diagnostic pop
static int SnapshotFile(vlc_object_t *object, const char *name, vlc_value_t old, vlc_value_t value, void *data) {
    VLC_UNUSED(object); VLC_UNUSED(name); VLC_UNUSED(old);
    NSString *path = S(value.psz_string);
    __weak MXRServicesBridge *bridge = Bridge(data);
    if (path.length) dispatch_async(dispatch_get_main_queue(), ^{ [bridge applySnapshotFile:path]; });
    return VLC_SUCCESS;
}

@implementation MXRServicesBridge {
    intf_thread_t *_intf;
    vlc_playlist_t *_playlist;
    vlc_player_t *_player;
    vlc_playlist_listener_id *_queueListener;
    vlc_player_listener_id *_playerListener;
    vlc_player_aout_listener_id *_audioListener;
    vlc_player_vout_listener_id *_voutListener;
    BOOL _snapshotCallback;
    dispatch_queue_t _workQueue;
    BOOL _shutDown;
    atomic_uint _pendingTopics;
    _Atomic(float) _buffering;
    NSUInteger _saveGeneration;
    BOOL _savePending;
    NSInteger _stoppedAction;
    NSNumber *_pendingVolume;
    NSNumber *_acceptedVolume;
    BOOL _pauseAtEnd;
    /* "Start playing when opened" off: the item that carries a one-shot ":start-paused"
     * option (held). Guarded by the player (= playlist) lock. */
    input_item_t *_startPausedItem;
    MXRLibraryServices *_library;
    MXRDialogServices *_dialogs;
    MXRThumbnailServices *_thumbnails;
    MXREffectsServices *_effects;
    MXRMediaServices *_mediaServices;
    MXRDiscoveryServices *_discovery;
    MXRAudioServices *_audioServices;
    MXRAudioPreferenceServices *_audioPreferences;
    MXRSubtitleCueServices *_subtitleCues;
    NSDictionary *_restorePrompt;
    NSString *_restoreURL;
    /* Redesign OSD (D027) */
    NSDictionary *_osd;
    NSUInteger _osdSerial;
    int _awaitedFeedback;
    CFTimeInterval _awaitedFeedbackDeadline;
    vlc_player_timer_id *_seekTimer;
    /* The seek target reported while a hotkey action runs on main (triggerAction). */
    BOOL _capturingHotkeySeek, _hotkeySeekReported;
    vlc_tick_t _hotkeySeekTime, _hotkeySeekLength;
    /* Arrow jumps the input thread has not reported yet, in order, and when they stop waiting. */
    NSUInteger _navigationSeeksPending;
    CFTimeInterval _navigationSeekDeadline;
    bool _secondarySubtitleControl;
    NSString *_titleShownForURL;
    /* External files: added this session, and library subtitle mappings of the current media */
    /* URL -> CACurrentMediaTime of its add: the input loads a slave asynchronously. */
    NSMutableDictionary<NSString *, NSNumber *> *_addedTrackURLs;
    NSArray<NSDictionary *> *_librarySubtitles; /* MXRLibraryExternalTracks: subtitles and soundtracks */
    NSValue *_librarySubtitlesItem;
    NSString *_snapshotURL;
    BOOL _pictureInPicture;
    __weak MXRPictureInPictureController *_pictureInPictureController;
    /* Settings schema: module options do not change while VLC runs. */
    NSArray *_settingsOptions;
    NSArray<NSString *> *_settingsNames;
}
- (instancetype)initWithPlaylist:(vlc_playlist_t *)playlist interface:(intf_thread_t *)intf {
    if (!(self = [super init])) return nil;
    _intf = intf; _playlist = playlist; _player = vlc_playlist_GetPlayer(playlist);
    atomic_init(&_pendingTopics, 0);
    atomic_init(&_buffering, 1.f);
    _addedTrackURLs = [NSMutableDictionary dictionary];
    _workQueue = dispatch_queue_create("org.vlc-redesign.services", DISPATCH_QUEUE_SERIAL);
    /* D027: our UI owns the OSD. Every vout inherits "osd" from its parents (vout -> dummy
     * vout -> player -> instance, src/input/resource.c), so this switches off the core's
     * text, icon and slider OSD (video_text.c, video_widgets.c) without touching the engine
     * or the user's "osd" preference, which now drives only the redesign OSD. Subtitles
     * are unaffected ("spu"). */
    vlc_object_t *instance = VLC_OBJECT(vlc_object_instance(intf));
    var_Create(instance, "osd", VLC_VAR_BOOL);
    var_SetBool(instance, "osd", false);
    var_AddCallback(instance, "snapshot-file", SnapshotFile, (__bridge void *)self);
    _snapshotCallback = YES;
    vlc_playlist_Lock(_playlist);
    _queueListener = vlc_playlist_AddListener(_playlist, &QueueCallbacks, (__bridge void *)self, true);
    _playerListener = vlc_player_AddListener(_player, &PlayerCallbacks, (__bridge void *)self);
    vlc_playlist_Unlock(_playlist);
    _audioListener = vlc_player_aout_AddListener(_player, &AudioCallbacks, (__bridge void *)self);
    _voutListener = vlc_player_vout_AddListener(_player, &VoutCallbacks, (__bridge void *)self);
    /* Only seek reports are used; the long period keeps periodic updates away. */
    _seekTimer = vlc_player_AddTimer(_player, VLC_TICK_FROM_SEC(3600), &SeekFeedbackTimer, (__bridge void *)self);
    if (!_queueListener || !_playerListener || !_audioListener || !_voutListener || !_seekTimer) { [self shutdown]; return nil; }
    _pauseAtEnd = var_InheritBool(intf, "play-and-pause");
    _library = [[MXRLibraryServices alloc] initWithInterface:intf];
    _dialogs = [[MXRDialogServices alloc] initWithInterface:intf];
    _thumbnails = [[MXRThumbnailServices alloc] initWithInterface:intf];
    _effects = [[MXREffectsServices alloc] initWithPlayer:_player];
    _mediaServices = [[MXRMediaServices alloc] initWithPlaylist:playlist interface:intf];
    _discovery = [[MXRDiscoveryServices alloc] initWithInterface:intf];
    _audioServices = [[MXRAudioServices alloc] initWithPlaylist:playlist interface:intf];
    _audioPreferences = [[MXRAudioPreferenceServices alloc] initWithPlayer:_player];
    _subtitleCues = [[MXRSubtitleCueServices alloc] initWithPlaylist:playlist interface:intf];
    __weak MXRServicesBridge *weakSelf = self;
    /* Helpers publish immutable scalar/cache updates on main. Deliver there immediately so
     * consecutive source event snapshots cannot overwrite one another before the sink
     * reads them. Engine-thread callers still enqueue. */
    void (^changed)(NSString *) = ^(NSString *service) {
        if (NSThread.isMainThread) [weakSelf changed:service];
        else dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf changed:service]; });
    };
    _library.serviceChanged = changed; _dialogs.serviceChanged = changed; _mediaServices.serviceChanged = changed;
    _discovery.serviceChanged = changed; _audioServices.serviceChanged = changed;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(pictureInPictureDidChange:)
                                               name:MXRPictureInPictureActiveDidChangeNotification object:nil];
    return self;
}
- (void)shutdown {
    if (_shutDown) return;
    /* An explicit save remains durable when quit races the debounce timer. */
    if (_savePending) [self enqueueConfigSave];
    _shutDown = YES; _sink = nil; _saveGeneration++;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_library shutdown]; [_dialogs shutdown]; [_thumbnails shutdown];
    [_mediaServices shutdown]; [_discovery shutdown]; [_audioServices shutdown];
    [_audioPreferences shutdown]; [_subtitleCues shutdown];
    if (_snapshotCallback) var_DelCallback(vlc_object_instance(_intf), "snapshot-file", SnapshotFile, (__bridge void *)self);
    _snapshotCallback = NO;
    vlc_playlist_Lock(_playlist);
    if (_queueListener) vlc_playlist_RemoveListener(_playlist, _queueListener);
    if (_playerListener) vlc_player_RemoveListener(_player, _playerListener);
    [self dropStartPausedItem];
    vlc_playlist_Unlock(_playlist);
    if (_audioListener) vlc_player_aout_RemoveListener(_player, _audioListener);
    if (_voutListener) vlc_player_vout_RemoveListener(_player, _voutListener);
    if (_seekTimer) vlc_player_RemoveTimer(_player, _seekTimer);
    _queueListener = NULL; _playerListener = NULL; _audioListener = NULL; _voutListener = NULL; _seekTimer = NULL;
}
/* Quit latency (C-13): every service joins its own workers and owns its engine objects, so
 * they are joined together and Cmd-Q waits for the slowest one, not for their sum. Each step
 * is an os_signpost interval ("org.videolan.vlc.macosx-redesign" / "Shutdown") so a trace
 * shows where quit spends its time. */
- (void)finishShutdown {
    NSAssert(!NSThread.isMainThread, @"Service teardown must run off main");
    os_log_t log = os_log_create("org.videolan.vlc.macosx-redesign", "Shutdown");
    os_signpost_id_t all = os_signpost_id_generate(log);
    os_signpost_interval_begin(log, all, "Services");
    dispatch_sync(_workQueue, ^{});
    NSDictionary<NSString *, id> *services = @{ @"library":_library ?: NSNull.null, @"thumbnails":_thumbnails ?: NSNull.null,
        @"media":_mediaServices ?: NSNull.null, @"discovery":_discovery ?: NSNull.null,
        @"audio":_audioServices ?: NSNull.null, @"subtitleCues":_subtitleCues ?: NSNull.null };
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t workers = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    [services enumerateKeysAndObjectsUsingBlock:^(NSString *name, id service, BOOL *stop) {
        if (service == NSNull.null) return;
        dispatch_group_async(group, workers, ^{
            os_signpost_id_t step = os_signpost_id_generate(log);
            os_signpost_interval_begin(log, step, "Service", "%{public}@", name);
            [service finishShutdown];
            os_signpost_interval_end(log, step, "Service", "%{public}@", name);
        });
    }];
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    os_signpost_interval_end(log, all, "Services");
}
- (void)dealloc { assert(!_queueListener && !_playerListener && !_audioListener && !_voutListener && !_seekTimer && !_snapshotCallback); }

#pragma mark Change delivery

/// Any thread. Marks topics; at most one main-queue hop delivers every marked topic.
- (void)scheduleTopics:(unsigned)topics {
    if (atomic_fetch_or(&_pendingTopics, topics) != 0) return; /* a flush is already queued */
    __weak MXRServicesBridge *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf flushTopics]; });
}
/// Any thread (on_buffering_changed fires often while a stream fills).
- (void)storeBuffering:(float)value {
    atomic_store(&_buffering, value);
    [self scheduleTopics:MXRTopicState];
}
- (void)flushTopics {
    unsigned topics = atomic_exchange(&_pendingTopics, 0);
    if (_shutDown) return;
    /* A pixel subtitle size follows the height of the video that is now playing. */
    if ((topics & MXRTopicTracks) && [_effects applySubtitleSizePreference]) topics |= MXRTopicSync | MXRTopicEffects;
    /* The queue service re-reads the state as well. */
    if (topics & MXRTopicQueue) topics &= ~(unsigned)MXRTopicQueueState;
    for (unsigned bit = 1; bit <= MXRTopicLast; bit <<= 1)
        if (topics & bit) [_sink bridgeServiceDidChange:TopicService(bit)];
}
/// Main thread, synchronous. Library changes refresh only what shows library fields: the
/// media cache reports which of its entries went stale or changed (ENG-M3).
- (void)changed:(MXRBridgeService)service {
    if (_shutDown) return;
    if ([service isEqual:MXRBridgeServicePlayer]) { [self scheduleTopics:MXRTopicMedia]; return; }
    if ([service isEqual:MXRBridgeServiceMediaStale]) { [self scheduleTopics:MXRTopicMedia | MXRTopicQueue]; return; }
    if ([service isEqual:MXRBridgeServiceQueueFavorites]) { [self scheduleTopics:MXRTopicQueue]; return; }
    [_sink bridgeServiceDidChange:service];
}

#pragma mark Engine state (main thread)

- (void)applyStoppedAction:(NSInteger)value { if (!_shutDown) { _stoppedAction = value; [self scheduleTopics:MXRTopicQueueState | MXRTopicSettings]; } }
- (void)applyCurrentMediaChanged {
    if (_shutDown) return;
    _restorePrompt = nil; _restoreURL = nil; [_addedTrackURLs removeAllObjects];
    [self scheduleTopics:MXRTopicNewMedia];
    [self loadLibrarySubtitlesForCurrentMedia];
}
- (void)applyPlayerState:(NSInteger)state {
    if (_shutDown) return;
    if (state == VLC_PLAYER_STATE_STOPPING || state == VLC_PLAYER_STATE_STOPPED) { _restorePrompt = nil; _restoreURL = nil; }
    [self applyPendingVolume];
    if (state == VLC_PLAYER_STATE_PLAYING || state == VLC_PLAYER_STATE_PAUSED) [self attachLibrarySubtitles];
    [self scheduleTopics:MXRTopicState];
}
- (void)applyPendingVolume {
    if (_shutDown || !_pendingVolume) return;
    NSNumber *pending = _pendingVolume;
    int result = vlc_player_aout_SetVolume(_player, pending.floatValue);
    float reported = vlc_player_aout_GetVolume(_player);
    if (result == VLC_SUCCESS || fabsf(reported - pending.floatValue) < 0.001f) { _pendingVolume = nil; _acceptedVolume = pending; }
    else if (reported >= 0) { _pendingVolume = nil; [self postNotice:@"Audio output rejected the requested startup volume." duration:0]; }
    [self scheduleTopics:MXRTopicVolume];
}
- (void)applyRestoreQueryForURL:(NSString *)url {
    if (_shutDown || !url.length) return;
    if (!AllowsPositionForURL(url)) { _restorePrompt = nil; _restoreURL = nil; [self scheduleTopics:MXRTopicState]; return; }
    _restoreURL = [url copy]; _restorePrompt = @{@"time":@(-1)};
    __weak MXRServicesBridge *weakSelf = self;
    [_library request:@"media" arguments:@{@"id":url} completion:^(NSDictionary *result, NSError *error) {
        (void)error;
        MXRServicesBridge *self = weakSelf; if (!self || self->_shutDown || ![self->_restoreURL isEqual:url]) return;
        NSDictionary *media = result[@"media"]; int64_t duration = [media[@"duration"] longLongValue];
        double progress = [media[@"progress"] doubleValue];
        /* Media played from outside an indexed folder are "external" in the media library: it keeps
         * their progress but not their duration, so the player's length gives the time (A-window). */
        if (duration <= 0) {
            vlc_player_Lock(self->_player); vlc_tick_t length = vlc_player_GetLength(self->_player); vlc_player_Unlock(self->_player);
            if (length != VLC_TICK_INVALID && length > 0) duration = US_FROM_VLC_TICK(length);
        }
        self->_restorePrompt = duration > 0 ? @{@"time":@((int64_t)(duration * progress))} : @{@"time":@(-1), @"progress":@(progress)};
        [self scheduleTopics:MXRTopicState];
    }];
    [self scheduleTopics:MXRTopicState];
}
/// Any thread (player vout callback). `_effects` is set once in init and never cleared.
- (void)subtitleVoutStarted:(vout_thread_t *)vout order:(enum vlc_vout_order)order { [_effects applySubtitleSafeInsetToVout:vout order:order]; }
- (void)applyVoutStarted:(NSString *)title timeout:(double)seconds mediaURL:(NSString *)url {
    if (_shutDown || !title.length || seconds <= 0 || [_titleShownForURL isEqual:url]) return;
    _titleShownForURL = [url copy];
    [self postNotice:title duration:seconds];
}
- (void)applySnapshotFile:(NSString *)path {
    if (_shutDown) return;
    _snapshotURL = [NSURL fileURLWithPath:path].absoluteString;
    [self scheduleTopics:MXRTopicSnapshot];
    /* VLC writes the file name into the video after a snapshot (vout_intf.c VoutOsdSnapshot). */
    [self postFeedback:path.lastPathComponent];
}
- (void)pictureInPictureDidChange:(NSNotification *)note {
    MXRPictureInPictureController *controller = note.object;
    if (_shutDown || ![controller isKindOfClass:MXRPictureInPictureController.class]) return;
    _pictureInPictureController = controller;
    _pictureInPicture = controller.isActive;
    [self scheduleTopics:MXRTopicState];
}

#pragma mark Redesign OSD (D027)

- (void)postOSD:(NSString *)text kind:(NSString *)kind duration:(double)seconds {
    if (_shutDown || !text.length) return;
    NSMutableDictionary *message = [@{MXROSDKeyText:text, MXROSDKeyKind:kind, MXROSDKeySerial:@(++_osdSerial)} mutableCopy];
    if (seconds > 0) message[MXROSDKeyDuration] = @(seconds);
    _osd = message;
    /* Synchronous: a hotkey's text pairs with its "Pressed <key>" in the same frame. */
    [_sink bridgeServiceDidChange:MXRBridgeServiceOSD];
}
- (void)postFeedback:(NSString *)text { [self postOSD:text kind:MXROSDKindFeedback duration:0]; }
- (void)postNotice:(NSString *)text duration:(double)seconds { [self postOSD:text kind:MXROSDKindNotice duration:seconds]; }
- (void)awaitedFeedbackArrived:(int)kind {
    if (_shutDown || _awaitedFeedback != kind) return;
    _awaitedFeedback = MXRFeedbackAwaitNone;
    if (CACurrentMediaTime() > _awaitedFeedbackDeadline) return;
    NSString *text = kind == MXRFeedbackAwaitAudio ? FeedbackSelectedTracks(_player, AUDIO_ES)
                   : kind == MXRFeedbackAwaitSubtitle ? FeedbackSelectedTracks(_player, SPU_ES)
                   : kind == MXRFeedbackAwaitProgram ? FeedbackSelectedProgram(_player)
                   : kind == MXRFeedbackAwaitRate ? FeedbackRate(_player)
                   : kind == MXRFeedbackAwaitVolume ? FeedbackVolume(_player, false) : nil;
    if (text) [self postFeedback:text];
}
- (void)hotkeySeekReportedAt:(vlc_tick_t)time length:(vlc_tick_t)length {
    /* Main thread, under the timer lock: record only. The last report wins (one action, one seek). */
    if (!_capturingHotkeySeek) return;
    _hotkeySeekReported = YES; _hotkeySeekTime = time; _hotkeySeekLength = length;
}
static NSString *FeedbackSeekTarget(vlc_tick_t time, vlc_tick_t length) {
    if (length != VLC_TICK_INVALID && length > 0 && time > VLC_TICK_0 + length) time = VLC_TICK_0 + length;
    return FeedbackPosition(time, length);
}
- (void)navigationSeekReportedAt:(vlc_tick_t)time length:(vlc_tick_t)length {
    /* Main, from an input-thread on_seek: the oldest pending arrow's target. */
    if (_shutDown || _navigationSeeksPending == 0) return;
    if (CACurrentMediaTime() > _navigationSeekDeadline) { _navigationSeeksPending = 0; return; }
    _navigationSeeksPending--;
    NSString *text = FeedbackSeekTarget(time, length);
    if (text) [self postFeedback:text];
}
- (BOOL)triggerAction:(NSString *)name error:(NSError **)error {
    vlc_action_id_t action = vlc_actions_get_id([@"key-" stringByAppendingString:name ?: @""].UTF8String);
    if (action == ACTIONID_NONE) return Fail(error, @"Unknown hotkey action.");
    MXRActionBefore before = MXRCaptureActionBefore(_player);
    /* The hotkeys module handles key-action synchronously (modules/control/hotkeys.c). */
    _capturingHotkeySeek = YES; _hotkeySeekReported = NO;
    var_SetInteger(vlc_object_instance(_intf), "key-action", action);
    _capturingHotkeySeek = NO;
    int await = MXRFeedbackAwaitNone;
    NSString *text = MXRHotkeyFeedback(_playlist, _player, action, &before, &_secondarySubtitleControl, &await);
    if (await == MXRFeedbackAwaitSeek) {
        /* The jump's own target, reported inside the call above; a jump that did not seek
         * (a negative jump size) shows nothing rather than the next unrelated seek. */
        if (_hotkeySeekReported) {
            text = FeedbackSeekTarget(_hotkeySeekTime, _hotkeySeekLength);
        } else if (action == ACTIONID_NAV_LEFT || action == ACTIONID_NAV_RIGHT) {
            _navigationSeeksPending++;
            _navigationSeekDeadline = CACurrentMediaTime() + 1.0;
        }
        await = MXRFeedbackAwaitNone;
    }
    _awaitedFeedback = await;
    _awaitedFeedbackDeadline = CACurrentMediaTime() + 1.0;
    if (text) [self postFeedback:text];
    return YES;
}

#pragma mark Library subtitle mappings (§06, MISS-02)

/* Add Subtitles can match files to every episode of a folder or playlist. They are stored
 * as external files of each media in the media library (VLC_ML_MEDIA_ADD_EXTERNAL_MRL), which
 * the core does not load by itself. Items entering the queue carry them as slaves (below);
 * as a fallback (a mapping made after the item was queued, or an item queued elsewhere) they
 * are also looked up when a media becomes current and attached once its input runs (after
 * LoadSlaves, so a file the item already carries is not added twice). The first mapped
 * subtitle is selected. */
/// Subtitle and audio files the media library maps to `uri` (Add Subtitles, Edit/Add Audio
/// Tracks), in library order; MXRLibraryAddTrackSlaves adds them as user slaves, so the core
/// loads them when its input starts and selects the first of each.
static NSArray<NSDictionary *> *LibrarySubtitleURLs(vlc_medialibrary_t *ml, const char *uri) { return MXRLibraryExternalTracks(ml, uri); }
static void AddSubtitleSlaves(input_item_t *item, NSArray<NSDictionary *> *subtitles) { MXRLibraryAddTrackSlaves(item, subtitles); }
/// Library media enter the queue carrying their mapped subtitles (MISS-02). The database is
/// read on the work queue, never on main. The slaves are added under the player lock and
/// only while the item is not current: an input is created for an item only when it becomes
/// current (under that lock), so LoadSlaves either sees the slaves, or the item was already
/// current and the current-media path below attaches them to the running input instead.
- (void)attachLibrarySubtitlesToInputs:(input_item_t *const *)inputs count:(size_t)count startingAt:(NSInteger)started {
    (void)started;
    vlc_medialibrary_t *ml = vlc_ml_instance_get(_intf);
    if (!ml || !_library.available || !count) return;
    NSMutableArray<NSValue *> *pending = [NSMutableArray arrayWithCapacity:count];
    for (size_t i = 0; i < count; i++) { input_item_Hold(inputs[i]); [pending addObject:[NSValue valueWithPointer:inputs[i]]]; }
    vlc_player_t *player = _player;
    dispatch_async(_workQueue, ^{
        for (NSValue *value in pending) { @autoreleasepool {
            input_item_t *item = value.pointerValue;
            char *uri = input_item_GetURI(item);
            NSArray<NSDictionary *> *subtitles = LibrarySubtitleURLs(ml, uri);
            free(uri);
            if (subtitles.count) {
                vlc_player_Lock(player);
                if (vlc_player_GetCurrentMedia(player) != item) AddSubtitleSlaves(item, subtitles);
                vlc_player_Unlock(player);
            }
            input_item_Release(item);
        }}
    });
}
- (void)loadLibrarySubtitlesForCurrentMedia {
    _librarySubtitles = nil; _librarySubtitlesItem = nil;
    vlc_medialibrary_t *ml = vlc_ml_instance_get(_intf);
    if (!ml || !_library.available) return;
    vlc_player_Lock(_player);
    input_item_t *item = vlc_player_GetCurrentMedia(_player);
    if (item) input_item_Hold(item);
    vlc_player_Unlock(_player);
    if (!item) return;
    __weak MXRServicesBridge *weakSelf = self;
    dispatch_async(_workQueue, ^{ @autoreleasepool {
        char *uri = input_item_GetURI(item);
        NSArray<NSDictionary *> *subtitles = LibrarySubtitleURLs(ml, uri);
        free(uri);
        dispatch_async(dispatch_get_main_queue(), ^{
            MXRServicesBridge *self = weakSelf;
            if (self && !self->_shutDown && subtitles.count) {
                self->_librarySubtitles = subtitles;
                self->_librarySubtitlesItem = [NSValue valueWithPointer:item];
                [self attachLibrarySubtitles];
            }
            input_item_Release(item);
        });
    }});
}
- (void)attachLibrarySubtitles {
    if (_shutDown || !_librarySubtitles.count) return;
    vlc_player_Lock(_player);
    input_item_t *item = vlc_player_GetCurrentMedia(_player);
    enum vlc_player_state state = vlc_player_GetState(_player);
    BOOL ready = item && item == _librarySubtitlesItem.pointerValue && (state == VLC_PLAYER_STATE_PLAYING || state == VLC_PLAYER_STATE_PAUSED);
    if (ready) {
        NSDictionary *loaded = SlaveURLsByHash(item, _addedTrackURLs.allKeys);
        BOOL selectSubtitle = YES, selectAudio = YES;
        for (NSDictionary *track in _librarySubtitles) {
            BOOL audio = [track[MXRLibraryTrackAudio] boolValue];
            NSString *mrl = CanonicalMRL(track[MXRLibraryTrackURL]);
            if (loaded[MD5Hex(mrl.UTF8String)]) continue;
            if (vlc_player_AddAssociatedMedia(_player, audio ? AUDIO_ES : SPU_ES, mrl.UTF8String, audio ? selectAudio : selectSubtitle, false, false) == VLC_SUCCESS) {
                _addedTrackURLs[mrl] = @(CACurrentMediaTime());
                if (audio) selectAudio = NO; else selectSubtitle = NO;
            }
        }
        /* Soundtracks the item carried as slaves: VLC keeps the media's own audio (D039). */
        if (selectAudio) MXRLibrarySelectSoundtrack(_player, _librarySubtitles);
    }
    vlc_player_Unlock(_player);
    if (ready) { _librarySubtitles = nil; _librarySubtitlesItem = nil; }
}

#pragma mark Snapshots

- (NSDictionary *)capabilities {
    NSMutableDictionary *capabilities = [@{@"player":@YES, @"queue":@YES, @"settings":@YES, @"shortcuts":@YES,
      @"library":@(_library.available), @"dialogs":@YES, @"thumbnails":@(_thumbnails.available), @"extensions":@NO, @"mediaSources":@NO,
      @"supportsWaveform":@NO, @"supportsSubtitleTimeline":@NO, @"supportsPictureInPicture":@NO,
      @"recording":@YES, @"globalHotkeys":@NO, @"addons":@NO, @"supportsReversePlayback":@NO, @"stereoTest":@NO} mutableCopy];
    [capabilities addEntriesFromDictionary:_mediaServices.capabilities];
    [capabilities addEntriesFromDictionary:_discovery.capabilities];
    [capabilities addEntriesFromDictionary:_audioServices.capabilities];
    [capabilities addEntriesFromDictionary:_subtitleCues.capabilities];
    if (capabilities[@"hasMediaSources"]) capabilities[@"mediaSources"] = capabilities[@"hasMediaSources"];
    /* C comparison expressions box as integers. The public flag wire type is Boolean. */
    for (NSString *key in capabilities.allKeys) {
        id value = capabilities[key]; if ([value isKindOfClass:NSNumber.class]) capabilities[key] = [value boolValue] ? @YES : @NO;
    }
    return capabilities;
}
- (BOOL)settingAvailable:(NSString *)name {
    if (UnsupportedSetting(name)) return NO;
    if ([MXRAudioPreferenceServices handlesOption:name]) return [_audioPreferences availabilityForOption:name];
    if ([name isEqual:@"macosx-redesign-sub-shadow"] && !config_FindConfig("freetype-shadow-opacity")) return NO;
    if ([name isEqual:@"macosx-redesign-sub-background"] && !config_FindConfig("freetype-background-opacity")) return NO;
    return YES;
}
- (NSDictionary *)stateSnapshot {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    vlc_player_Lock(_player);
    d[MXRPlayerKeyState] = @(vlc_player_GetState(_player));
    d[MXRPlayerKeyRate] = @(vlc_player_GetRate(_player));
    d[MXRPlayerKeyBufferingProgress] = @(vlc_player_GetCurrentMedia(_player) ? atomic_load(&_buffering) : 1.f);
    d[MXRPlayerKeyCanPause] = @(vlc_player_CanPause(_player)); d[MXRPlayerKeyCanSeek] = @(vlc_player_CanSeek(_player));
    d[MXRPlayerKeyCanChangeRate] = @(vlc_player_CanChangeRate(_player)); d[MXRPlayerKeyCanRecord] = @(vlc_player_GetCurrentMedia(_player) != NULL);
    if (vlc_player_GetError(_player) != VLC_PLAYER_ERROR_NONE) d[MXRPlayerKeyErrorMessage] = @"VLC could not play this media.";
    vlc_tick_t a = VLC_TICK_INVALID, b = VLC_TICK_INVALID; double ap, bp;
    enum vlc_player_abloop loop = vlc_player_GetAtoBLoop(_player, &a, &ap, &b, &bp);
    d[MXRPlayerKeyABLoop] = @{@"state":@(loop), @"a":@(Time(a)), @"b":@(Time(b))};
    d[MXRPlayerKeyIsRecording] = @(vlc_player_IsRecording(_player));
    if (_restorePrompt[@"progress"]) {
        /* The length arrives once the input opened (PLAYING), after an external media's restore query. */
        vlc_tick_t length = vlc_player_GetLength(_player);
        if (length != VLC_TICK_INVALID && length > 0)
            _restorePrompt = @{@"time":@((int64_t)(US_FROM_VLC_TICK(length) * [_restorePrompt[@"progress"] doubleValue]))};
    }
    vlc_player_Unlock(_player);
    if (_restorePrompt) d[MXRPlayerKeyRestorePrompt] = _restorePrompt;
    d[MXRPlayerKeyIsFullscreen] = @(vlc_player_vout_IsFullscreen(_player));
    d[MXRPlayerKeyIsPictureInPicture] = @(_pictureInPicture);
    return d;
}
- (NSDictionary *)mediaSnapshot {
    vlc_player_Lock(_player);
    input_item_t *media = vlc_player_GetCurrentMedia(_player);
    NSMutableDictionary *info = nil;
    if (media) {
        info = [Media(media) mutableCopy];
        if (vlc_player_GetTrackCount(_player, VIDEO_ES) > 0) info[@"kind"] = @"video";
        else if (vlc_player_GetTrackCount(_player, AUDIO_ES) > 0) info[@"kind"] = @"audio";
    }
    vlc_player_Unlock(_player);
    if (!info) return @{};
    NSDictionary *cached = [_library cachedMediaForURL:info[@"url"]];
    if (cached) {
        for (NSString *key in @[@"isFavorite", @"progress", @"playCount"]) if (cached[key]) info[key] = cached[key];
        /* Library-only facts: the containing folder (top-bar chip, per-folder presets) and album metadata. */
        for (NSString *key in @[@"folder", @"artist", @"album", @"genre", @"artworkURL", @"trackNumber"]) if (cached[key] && !info[key]) info[key] = cached[key];
    }
    return @{MXRPlayerKeyMedia:info};
}
- (NSDictionary *)tracksSnapshot {
    vlc_player_Lock(_player);
    NSDictionary *slaves = SlaveURLsByHash(vlc_player_GetCurrentMedia(_player), _addedTrackURLs.allKeys);
    NSDictionary *d = @{MXRPlayerKeyAudioTracks:Tracks(_player, AUDIO_ES, slaves), MXRPlayerKeyVideoTracks:Tracks(_player, VIDEO_ES, slaves),
                        MXRPlayerKeySubtitleTracks:Tracks(_player, SPU_ES, slaves)};
    vlc_player_Unlock(_player);
    return d;
}
- (NSDictionary *)titlesSnapshot {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    NSMutableArray *titles = [NSMutableArray array];
    vlc_player_Lock(_player);
    vlc_player_title_list *list = vlc_player_GetTitleList(_player);
    if (list) for (size_t i = 0; i < vlc_player_title_list_GetCount(list); i++) {
        const struct vlc_player_title *t = vlc_player_title_list_GetAt(list, i);
        [titles addObject:@{MXRPlayerKeyIndex:@(i), MXRPlayerKeyName:S(t->name), MXRPlayerKeyLength:@(Time(t->length)),
                            MXRPlayerKeyIsMenu:@((t->flags & VLC_PLAYER_TITLE_MENU) != 0), MXRPlayerKeyChapters:Chapters(t)}];
    }
    d[MXRPlayerKeyTitles] = titles; d[MXRPlayerKeySelectedTitleIndex] = @(vlc_player_GetSelectedTitleIdx(_player));
    d[MXRPlayerKeySelectedChapterIndex] = @(vlc_player_GetSelectedChapterIdx(_player)); d[MXRPlayerKeyChapters] = Chapters(vlc_player_GetSelectedTitle(_player));
    NSMutableArray *programs = [NSMutableArray array];
    for (size_t i = 0; i < vlc_player_GetProgramCount(_player); i++) {
        const struct vlc_player_program *p = vlc_player_GetProgramAt(_player, i);
        [programs addObject:@{MXRPlayerKeyID:@(p->group_id), MXRPlayerKeyName:S(p->name), MXRPlayerKeySelected:@(p->selected), MXRPlayerKeyScrambled:@(p->scrambled)}];
    }
    d[MXRPlayerKeyPrograms] = programs;
    vlc_player_Unlock(_player);
    return d;
}
- (NSDictionary *)syncSnapshot {
    vlc_player_Lock(_player);
    vlc_tick_t audioDelay = vlc_player_GetAudioDelay(_player), subDelay = vlc_player_GetSubtitleDelay(_player);
    // libvlccore does not export vlc_player_GetAssociatedSubsFPS (D031: no engine edits); it only
    // reads the player's "sub-fps" variable, and the player object starts with its vlc_object_t.
    float fps = var_GetFloat((vlc_object_t *)_player, "sub-fps");
    unsigned scale = vlc_player_GetSubtitleTextScale(_player);
    vlc_player_Unlock(_player);
    return @{MXRPlayerKeyAudioDelay:@(audioDelay == VLC_TICK_INVALID ? 0 : Time(audioDelay)),
             MXRPlayerKeySubtitleDelay:@(subDelay == VLC_TICK_INVALID ? 0 : Time(subDelay)),
             MXRPlayerKeySubtitleFPS:@(fps), MXRPlayerKeySubtitleTextScale:@(scale)};
}
- (NSDictionary *)volumeSnapshot {
    float volume = vlc_player_aout_GetVolume(_player);
    return @{MXRPlayerKeyVolume:_pendingVolume ?: (volume < 0 && _acceptedVolume ? _acceptedVolume : @(volume)),
             MXRPlayerKeyIsMuted:@(vlc_player_aout_IsMuted(_player) == 1)};
}
- (NSDictionary *)devicesSnapshot {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    NSMutableArray *devices = [NSMutableArray array];
    audio_output_t *aout = vlc_player_aout_Hold(_player);
    if (aout) {
        char **ids, **names; int n = aout_DevicesList(aout, &ids, &names);
        for (int i = 0; i < n; i++) { [devices addObject:@{MXRPlayerKeyID:S(ids[i]), MXRPlayerKeyName:S(names[i])}]; free(ids[i]); free(names[i]); }
        if (n >= 0) { free(ids); free(names); }
        char *current = aout_DeviceGet(aout); if (current) d[MXRPlayerKeyCurrentAudioDeviceID] = OwnedString(current);
        aout_Release(aout);
    }
    d[MXRPlayerKeyAudioDevices] = devices;
    return d;
}
- (NSDictionary *)statisticsSnapshot {
    NSDictionary *result = @{};
    vlc_player_Lock(_player);
    const struct input_stats_t *stats = vlc_player_GetStatistics(_player);
    if (stats) result = @{MXRPlayerKeyStatistics:@{@"inputBitrate":@(stats->f_input_bitrate * 1000), @"demuxBitrate":@(stats->f_demux_bitrate * 1000), @"decodedVideoBlocks":@(stats->i_decoded_video), @"displayedPictures":@(stats->i_displayed_pictures), @"lostPictures":@(stats->i_lost_pictures), @"decodedAudioBlocks":@(stats->i_decoded_audio), @"playedAudioBuffers":@(stats->i_played_abuffers), @"lostAudioBuffers":@(stats->i_lost_abuffers)}};
    vlc_player_Unlock(_player);
    return result;
}
- (NSDictionary *)teletextSnapshot {
    vlc_player_Lock(_player);
    NSDictionary *d = @{MXRPlayerKeyTeletext:@{@"available":@(vlc_player_HasTeletextMenu(_player)), @"enabled":@(vlc_player_IsTeletextEnabled(_player)),
      @"page":@(vlc_player_GetTeletextPage(_player)), @"transparent":@(vlc_player_IsTeletextTransparent(_player))}};
    vlc_player_Unlock(_player);
    return d;
}
/// Every player topic: the initial state and resets. Engine events re-read single topics.
- (NSDictionary *)playerSnapshot {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (unsigned bit = 1; bit < MXRTopicQueue; bit <<= 1) [d addEntriesFromDictionary:[self snapshotForTopic:bit]];
    return d;
}
- (NSDictionary *)snapshotForTopic:(MXRTopic)topic {
    switch (topic) {
        case MXRTopicState: return [self stateSnapshot];
        case MXRTopicMedia: return [self mediaSnapshot];
        case MXRTopicTracks: return [self tracksSnapshot];
        case MXRTopicTitles: return [self titlesSnapshot];
        case MXRTopicSync: return [self syncSnapshot];
        case MXRTopicEffects: return [_effects snapshot];
        case MXRTopicVolume: return [self volumeSnapshot];
        case MXRTopicDevices: return [self devicesSnapshot];
        case MXRTopicStatistics: return [self statisticsSnapshot];
        case MXRTopicTeletext: return [self teletextSnapshot];
        case MXRTopicSnapshot: return _snapshotURL ? @{MXRPlayerKeySnapshotURL:_snapshotURL} : @{};
        default: return @{};
    }
}
/// Everything but the items; the playlist is locked.
- (NSDictionary *)queueStateLocked {
    return @{@"currentIndex":@(vlc_playlist_GetCurrentIndex(_playlist)),
      @"repeatMode":@(vlc_playlist_GetPlaybackRepeat(_playlist)), @"order":@(vlc_playlist_GetPlaybackOrder(_playlist)),
      @"mediaStoppedAction":@(_stoppedAction), @"pauseAtEnd":@(_pauseAtEnd),
      @"hasNext":@(vlc_playlist_HasNext(_playlist)), @"hasPrevious":@(vlc_playlist_HasPrev(_playlist))};
}
/// Index, modes and neighbours only: no item is touched (the topic of index and mode callbacks).
- (NSDictionary *)queueStateSnapshot {
    vlc_playlist_Lock(_playlist);
    NSDictionary *result = [self queueStateLocked];
    vlc_playlist_Unlock(_playlist);
    return result;
}
- (NSDictionary *)queueSnapshot {
    NSMutableArray *items = [NSMutableArray array];
    vlc_playlist_Lock(_playlist);
    for (size_t i = 0; i < vlc_playlist_Count(_playlist); i++) {
        vlc_playlist_item_t *item = vlc_playlist_Get(_playlist, i);
        NSMutableDictionary *media = [Media(vlc_playlist_item_GetMedia(item)) mutableCopy];
        [items addObject:@{@"id":[NSString stringWithFormat:@"%llu", (unsigned long long)vlc_playlist_item_GetId(item)], @"media":media}];
    }
    NSMutableDictionary *result = [[self queueStateLocked] mutableCopy];
    result[@"items"] = items;
    vlc_playlist_Unlock(_playlist);
    /* Library lookups stay outside the playlist lock (the cache may start a request). */
    for (NSDictionary *entry in items) {
        NSMutableDictionary *media = entry[@"media"];
        NSDictionary *cached = [_library cachedMediaForURL:media[@"url"]]; if (cached) media[@"isFavorite"] = cached[@"isFavorite"] ?: @NO;
    }
    return result;
}
/// Module options are fixed while VLC runs: list them (gettext texts, choices) once.
- (void)loadSettingsSchema {
    if (_settingsOptions) return;
    NSMutableArray *options = [NSMutableArray array], *names = [NSMutableArray array];
    size_t n; module_t **modules = module_list_get(&n);
    for (size_t i = 0; i < n; i++) {
        unsigned count; module_config_t *configs = module_config_get(modules[i], &count);
        for (unsigned j = 0; j < count; j++) {
            module_config_t *c = &configs[j]; if (!CONFIG_ITEM(c->i_type) || !c->psz_name) continue;
            NSString *name = S(c->psz_name); [names addObject:name];
            if (![self settingAvailable:name]) continue;
            NSMutableDictionary *d = [@{@"name":name, @"type":ConfigType(c->i_type),
              @"defaultValue":OriginalValue(c), @"text":S(module_gettext(modules[i], c->psz_text)),
              @"longText":S(module_gettext(modules[i], c->psz_longtext)), @"module":S(module_get_object(modules[i]))} mutableCopy];
            if (IsConfigIntegerType(c->i_type) && c->min.i != c->max.i) { d[@"min"] = @(c->min.i); d[@"max"] = @(c->max.i); }
            if (IsConfigFloatType(c->i_type) && c->min.f != c->max.f) { d[@"min"] = @(c->min.f); d[@"max"] = @(c->max.f); }
            NSMutableArray *choices = [NSMutableArray array];
            for (unsigned k = 0; k < c->list_count; k++) [choices addObject:@{@"value":IsConfigIntegerType(c->i_type) ? @(c->list.i[k]) : S(c->list.psz[k]), @"title":S(module_gettext(modules[i], c->list_text[k]))}];
            d[@"choices"] = choices; [options addObject:d];
        }
        module_config_free(configs);
    }
    module_list_free(modules);
    _settingsOptions = [options copy]; _settingsNames = [names copy];
}
/* ARC-15: the schema is built once; "settingsValues" walks values only, and
 * "settings:<name>" reads a single value. */
- (NSDictionary *)syntheticSettingValues {
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    /* Queue commands and core hotkeys also change these modes. Reflect the
     * current playlist state instead of its startup configuration. */
    vlc_playlist_Lock(_playlist);
    enum vlc_playlist_playback_repeat repeat = vlc_playlist_GetPlaybackRepeat(_playlist);
    values[@"loop"] = @(repeat == VLC_PLAYLIST_PLAYBACK_REPEAT_ALL);
    values[@"repeat"] = @(repeat == VLC_PLAYLIST_PLAYBACK_REPEAT_CURRENT);
    values[@"random"] = @(vlc_playlist_GetPlaybackOrder(_playlist) == VLC_PLAYLIST_PLAYBACK_ORDER_RANDOM);
    values[@"play-and-stop"] = @(_stoppedAction == VLC_PLAYLIST_MEDIA_STOPPED_STOP);
    values[@"play-and-exit"] = @(_stoppedAction == VLC_PLAYLIST_MEDIA_STOPPED_EXIT);
    values[@"play-and-pause"] = @(_pauseAtEnd);
    vlc_playlist_Unlock(_playlist);
    /* Read-only values keep dependent rows consistent while the unavailable controls have
     * no writable schema metadata. */
    values[@"macosx-redesign-sub-position"] = @"bottom"; values[@"macosx-redesign-sub-ignore-styles"] = @NO;
    if (config_FindConfig("freetype-shadow-opacity")) values[@"macosx-redesign-sub-shadow"] = config_GetInt("freetype-shadow-opacity") > 0 ? @YES : @NO;
    if (config_FindConfig("freetype-background-opacity")) values[@"macosx-redesign-sub-background"] = config_GetInt("freetype-background-opacity") > 0 ? @"box" : @"none";
    [values addEntriesFromDictionary:[_audioPreferences snapshotValues]];
    return values;
}
- (NSDictionary *)settingValueSnapshot:(NSString *)name {
    id value = [self syntheticSettingValues][name] ?: (config_FindConfig(name.UTF8String) ? ConfigValue(name.UTF8String) : nil);
    return value ? @{@"value":value} : @{};
}
- (NSDictionary *)settingsSnapshot { return [self settingsSnapshotIncludingSchema:YES]; }
- (NSDictionary *)settingsSnapshotIncludingSchema:(BOOL)schema {
    [self loadSettingsSchema];
    NSMutableDictionary *values = [NSMutableDictionary dictionaryWithCapacity:_settingsNames.count];
    for (NSString *name in _settingsNames) { id value = ConfigValue(name.UTF8String); if (value) values[name] = value; }
    [values addEntriesFromDictionary:[self syntheticSettingValues]];
    if (!schema) return @{@"values":values};
    return @{@"options":_settingsOptions, @"values":values, @"configurationDirectory":OwnedString(config_GetUserDir(VLC_CONFIG_DIR)),
             @"userDataDirectory":OwnedString(config_GetUserDir(VLC_USERDATA_DIR))};
}
- (NSDictionary *)shortcutsSnapshot {
    NSMutableArray *actions = [NSMutableArray array]; const char *const *names = vlc_actions_get_key_names(_intf);
    if (names) for (size_t i = 0; names[i]; i++) {
        NSMutableArray *local = [NSMutableArray array], *global = [NSMutableArray array];
        NSString *text = @"";
        for (int g = 0; g < 2; g++) {
            NSString *option = [NSString stringWithFormat:@"%skey-%s", g ? "global-" : "", names[i]];
            if (!g) {
                /* The engine's human action name: the option text of add_key() ("Volume up"),
                 * translated (SD-01). Some actions have none; Swift overlays Figma wording. */
                module_config_t *c = config_FindConfig(option.UTF8String);
                if (c && c->psz_text && *c->psz_text) text = S(vlc_gettext(c->psz_text));
            }
            NSString *configured = OwnedString(config_GetPsz(option.UTF8String));
            for (NSString *binding in [configured componentsSeparatedByString:@"\t"]) {
                uint_fast32_t code = vlc_str2keycode(binding.UTF8String);
                if (code) [(g ? global : local) addObject:OwnedString(vlc_keycode2str(code, false))];
            }
        }
        [actions addObject:@{MXRShortcutKeyID:S(names[i]), MXRShortcutKeyName:text, MXRShortcutKeyHotkeys:local, MXRShortcutKeyGlobal:global}];
    }
    /* App-level actions store their bindings in macosx-redesign-key-<id> options. */
    [self loadSettingsSchema];
    NSMutableDictionary *appBindings = [NSMutableDictionary dictionary];
    for (NSString *name in _settingsNames) if ([name hasPrefix:@"macosx-redesign-key-"]) { id value = ConfigValue(name.UTF8String); if ([value isKindOfClass:NSString.class]) appBindings[name] = value; }
    return @{MXRShortcutKeyActions:actions, MXRShortcutKeyAppBindings:appBindings};
}
- (NSDictionary *)snapshotForService:(MXRBridgeService)service {
    if (_shutDown) return @{};
    if ([service hasPrefix:MXRBridgeServicePlayer]) {
        if ([service isEqual:MXRBridgeServicePlayer]) return [self playerSnapshot];
        for (unsigned bit = 1; bit < MXRTopicQueue; bit <<= 1) if ([service isEqual:TopicService(bit)]) return [self snapshotForTopic:bit];
        return @{};
    }
    if ([service isEqual:MXRBridgeServiceOSD]) return _osd ?: @{};
    if ([service isEqual:MXRBridgeServiceQueue]) return [self queueSnapshot];
    if ([service isEqual:MXRBridgeServiceQueueState]) return [self queueStateSnapshot];
    if ([service isEqual:MXRBridgeServiceSettings]) return [self settingsSnapshot];
    if ([service isEqual:MXRBridgeServiceSettingsValues]) return [self settingsSnapshotIncludingSchema:NO];
    if ([service hasPrefix:@"settings:"]) return [self settingValueSnapshot:[service substringFromIndex:9]];
    if ([service isEqual:MXRBridgeServiceShortcuts]) return [self shortcutsSnapshot];
    if ([service isEqual:MXRBridgeServiceLibrary]) return [_library snapshot];
    if ([service isEqual:MXRBridgeServiceDialogs]) return [_dialogs snapshot];
    if ([@[MXRBridgeServiceOutput, MXRBridgeServiceExtensions, MXRBridgeServiceRenderers] containsObject:service]) return [_mediaServices snapshotForService:service];
    if ([service isEqual:MXRBridgeServiceMediaSources]) return [_discovery snapshotForService:service];
    if ([service isEqual:MXRBridgeServiceAudioTest]) return [_audioServices snapshotForService:service];
    return @{};
}

#pragma mark Commands (main thread; fire-and-forget)

/// Playlist locked.
- (BOOL)startPlayback:(NSError **)error {
    /* D029: play with an empty queue is not an error; the UI offers the library or file
     * picker. With items but no current one (after a stop at the end), start at the first. */
    if (vlc_playlist_Count(_playlist) == 0) return YES;
    int ret = vlc_playlist_GetCurrentIndex(_playlist) < 0 ? vlc_playlist_PlayAt(_playlist, 0) : vlc_playlist_Start(_playlist);
    return ret == VLC_SUCCESS ?: Fail(error, @"VLC could not start playback.");
}
- (BOOL)playerCommand:(MXRBridgeCommand)command arguments:(NSDictionary *)args error:(NSError **)error {
    /* Layout, not a setting: no snapshot shows it, so no topic is published. */
    if ([command isEqual:MXRBridgeCommandSetSubtitleSafeInset]) return [_effects performCommand:command arguments:args error:error];
    if ([@[MXRBridgeCommandSetVideoEffects, MXRBridgeCommandSetAudioEffects, MXRBridgeCommandSetSubtitleStyle, MXRBridgeCommandSetTrackDefaults, MXRBridgeCommandSetAudioVisualization, MXRBridgeCommandSetSubtitleDurationFactor] containsObject:command]) {
        BOOL success = [_effects performCommand:command arguments:args error:error];
        if (success) {
            if ([command isEqual:MXRBridgeCommandSetAudioEffects]) [_audioPreferences reconcileAfterEffectsChange];
            if ([command isEqual:MXRBridgeCommandSetSubtitleStyle] && _effects.lastStyleChangeAppliesFromNextVideo)
                [self postNotice:@"Subtitle font and shadow changes apply from the next video." duration:0];
            [self scheduleTopics:MXRTopicEffects | MXRTopicSync | MXRTopicSettings];
        }
        return success;
    }
    double value = [args[@"value"] doubleValue];
    if ([@[MXRBridgeCommandPlay, MXRBridgeCommandPause, MXRBridgeCommandTogglePause, MXRBridgeCommandStop] containsObject:command]) {
        vlc_playlist_Lock(_playlist); BOOL ok = YES;
        enum vlc_player_state state = vlc_player_GetState(_player);
        if ([command isEqual:MXRBridgeCommandStop]) { _restorePrompt = nil; _restoreURL = nil; vlc_playlist_Stop(_playlist); }
        else if ([command isEqual:MXRBridgeCommandPause] || ([command isEqual:MXRBridgeCommandTogglePause] && (state == VLC_PLAYER_STATE_PLAYING || state == VLC_PLAYER_STATE_STARTED))) vlc_player_Pause(_player);
        else if (state == VLC_PLAYER_STATE_PAUSED) vlc_player_Resume(_player);
        else if (state == VLC_PLAYER_STATE_STOPPED) ok = [self startPlayback:error];
        vlc_playlist_Unlock(_playlist);
        return ok;
    }
    if ([command isEqual:MXRBridgeCommandSetVolume]) {
        if (!isfinite(value) || value < 0 || value > 3) return Fail(error, @"Volume must be between 0 and 3.");
        /* No OSD: the volume tooltip is the only indicator while dragging (D027, C7). */
        _pendingVolume = nil; int result = vlc_player_aout_SetVolume(_player, value);
        /* auhal records/reports the requested gain before its output unit starts. */
        BOOL accepted = result == VLC_SUCCESS || fabs(vlc_player_aout_GetVolume(_player) - value) < 0.001;
        if (accepted) { _acceptedVolume = @(value); return YES; }
        if (vlc_player_aout_GetVolume(_player) < 0) { _pendingVolume = @(value); [self scheduleTopics:MXRTopicVolume]; return YES; }
        return Fail(error, @"Audio output rejected the volume.");
    }
    if ([command isEqual:MXRBridgeCommandSetMuted]) return vlc_player_aout_Mute(_player, [args[@"value"] boolValue]) == VLC_SUCCESS ?: Fail(error, @"Audio output rejected mute.");
    if ([command isEqual:MXRBridgeCommandSetFullscreen]) { vlc_player_vout_SetFullscreen(_player, [args[@"value"] boolValue]); return YES; }
    if ([command isEqual:MXRBridgeCommandTakeSnapshot]) { vlc_player_vout_Snapshot(_player); return YES; }
    if ([command isEqual:MXRBridgeCommandShowMessage]) {
        NSString *text = args[@"text"]; if (![text isKindOfClass:NSString.class]) return Fail(error, @"An on-screen message requires text.");
        [self postFeedback:text]; return YES;
    }
    if ([command isEqual:MXRBridgeCommandRefreshAudioDevices]) { [self scheduleTopics:MXRTopicDevices]; return YES; }
    if ([command isEqual:MXRBridgeCommandSelectAudioDevice]) {
        audio_output_t *aout = vlc_player_aout_Hold(_player); if (!aout) return Fail(error, @"Audio output is unavailable.");
        int ret = aout_DeviceSet(aout, [args[@"id"] UTF8String]); aout_Release(aout);
        return ret == VLC_SUCCESS ?: Fail(error, @"Audio device selection failed.");
    }
    if ([command isEqual:MXRBridgeCommandSetPictureInPicture]) {
        MXRPictureInPictureController *controller = _pictureInPictureController;
        if (!controller.isAvailable) return Fail(error, @"Picture in Picture is unavailable.");
        if (controller.isActive != [args[@"value"] boolValue]) [controller toggle];
        return YES;
    }
    BOOL supported = YES; int status = VLC_SUCCESS; MXRTopic manual = 0;
    vlc_player_Lock(_player);
    if ([command isEqual:MXRBridgeCommandSeek]) {
        int64_t time = [args[@"time"] longLongValue]; if (time < 0 || !vlc_player_CanSeek(_player)) status = VLC_EINVAL;
        else vlc_player_SeekByTime(_player, VLC_TICK_0 + VLC_TICK_FROM_US(time), [args[@"precise"] boolValue] ? VLC_PLAYER_SEEK_PRECISE : VLC_PLAYER_SEEK_FAST, VLC_PLAYER_WHENCE_ABSOLUTE);
    } else if ([command isEqual:MXRBridgeCommandJump]) vlc_player_JumpTime(_player, VLC_TICK_FROM_US([args[@"value"] longLongValue]));
    else if ([command isEqual:MXRBridgeCommandSeekPosition]) {
        double position = [args[@"position"] doubleValue];
        if (!isfinite(position) || position < 0 || position > 1) status = VLC_EINVAL;
        else vlc_player_SeekByPos(_player, position, [args[@"precise"] boolValue] ? VLC_PLAYER_SEEK_PRECISE : VLC_PLAYER_SEEK_FAST, VLC_PLAYER_WHENCE_ABSOLUTE);
    } else if ([command isEqual:MXRBridgeCommandNextFrame]) vlc_player_NextVideoFrame(_player);
    else if ([command isEqual:MXRBridgeCommandSetRate]) { if (!isfinite(value) || value < 0.25 || value > 4) status = VLC_EINVAL; else vlc_player_ChangeRate(_player, value); }
    else if ([command isEqual:MXRBridgeCommandSetAudioDelay]) vlc_player_SetAudioDelay(_player, VLC_TICK_FROM_US([args[@"value"] longLongValue]), VLC_PLAYER_WHENCE_ABSOLUTE);
    else if ([command isEqual:MXRBridgeCommandSetSubtitleDelay]) vlc_player_SetSubtitleDelay(_player, VLC_TICK_FROM_US([args[@"value"] longLongValue]), VLC_PLAYER_WHENCE_ABSOLUTE);
    else if ([command isEqual:MXRBridgeCommandSetSubtitleFPS]) { if (value < 0 || !isfinite(value)) status = VLC_EINVAL; else vlc_player_SetAssociatedSubsFPS(_player, value); }
    else if ([command isEqual:MXRBridgeCommandSetSubtitleTextScale]) { if (value < 10 || value > 500) status = VLC_EINVAL; else { vlc_player_SetSubtitleTextScale(_player, (unsigned)value); manual = MXRTopicSync | MXRTopicEffects; } }
    else if ([command isEqual:MXRBridgeCommandSelectTitle]) {
        NSInteger index = [args[@"index"] integerValue]; vlc_player_title_list *list = vlc_player_GetTitleList(_player);
        if (!list || index < 0 || (size_t)index >= vlc_player_title_list_GetCount(list)) status = VLC_EINVAL;
        else vlc_player_SelectTitleIdx(_player, index);
    } else if ([command isEqual:MXRBridgeCommandSelectChapter]) {
        NSInteger index = [args[@"index"] integerValue]; const struct vlc_player_title *title = vlc_player_GetSelectedTitle(_player);
        if (!title || index < 0 || (size_t)index >= title->chapter_count) status = VLC_EINVAL; else vlc_player_SelectChapterIdx(_player, index);
    } else if ([command isEqual:MXRBridgeCommandSelectProgram]) {
        int group = [args[@"id"] intValue]; if (!vlc_player_GetProgram(_player, group)) status = VLC_EINVAL; else vlc_player_SelectProgram(_player, group);
    } else if ([command isEqual:MXRBridgeCommandToggleABLoop]) {
        enum vlc_player_abloop current = vlc_player_GetAtoBLoop(_player, NULL, NULL, NULL, NULL);
        status = vlc_player_SetAtoBLoop(_player, current == VLC_PLAYER_ABLOOP_NONE ? VLC_PLAYER_ABLOOP_A : current == VLC_PLAYER_ABLOOP_A ? VLC_PLAYER_ABLOOP_B : VLC_PLAYER_ABLOOP_NONE);
    } else if ([command isEqual:MXRBridgeCommandSetRecording]) vlc_player_SetRecordingEnabled(_player, [args[@"value"] boolValue], NULL);
    else if ([command isEqual:MXRBridgeCommandAnswerRestorePrompt]) {
        /* GetState is asynchronous: Stop can already detach input while still
         * reporting PLAYING. CanSeek reads the current input under this lock,
         * so it also protects RestorePlaybackPos's non-null-input precondition. */
        input_item_t *current = vlc_player_GetCurrentMedia(_player);
        NSString *uri = current ? OwnedString(input_item_GetURI(current)) : @"";
        if (!_restorePrompt || ![_restoreURL isEqual:uri] || !AllowsPositionForURL(uri) || !vlc_player_CanSeek(_player)) status = VLC_EINVAL;
        else if ([args[@"resume"] boolValue]) vlc_player_RestorePlaybackPos(_player);
        _restorePrompt = nil; _restoreURL = nil; manual = MXRTopicState;
    }
    else if ([command isEqual:MXRBridgeCommandSetTeletextEnabled]) vlc_player_SetTeletextEnabled(_player, [args[@"value"] boolValue]);
    else if ([command isEqual:MXRBridgeCommandSelectTeletextPage]) { if (value < 100 || value > 899) status = VLC_EINVAL; else vlc_player_SelectTeletextPage(_player, value); }
    else if ([command isEqual:MXRBridgeCommandSetTeletextTransparent]) vlc_player_SetTeletextTransparency(_player, [args[@"value"] boolValue]);
    else if ([command isEqual:MXRBridgeCommandUnselectTracks]) { enum es_format_category_e cat = Category(args[@"kind"]); if (cat == UNKNOWN_ES) status = VLC_EINVAL; else vlc_player_UnselectTrackCategory(_player, cat); }
    else if ([command isEqual:MXRBridgeCommandAddExternalTrack]) {
        enum es_format_category_e cat = Category(args[@"kind"]); NSString *url = args[@"url"];
        if (cat == UNKNOWN_ES || ![url isKindOfClass:NSString.class] || ![NSURL URLWithString:url].scheme) status = VLC_EINVAL;
        else {
            /* A file that is already a track of this media is selected, never loaded twice:
             * an explicit add (drop, Add Subtitle File) of an auto-detected sidecar the user
             * switched off turns it back on. A slave source prefixes its ES ids with the MD5
             * of its MRL. Without such a track the file is loaded, unless our own add of it
             * is still in flight; the input reports no failure, so an add that produced no
             * track after a few seconds is retried. */
            BOOL select = [args[@"select"] boolValue];
            url = CanonicalMRL(url);
            const struct vlc_player_track *existing = NULL;
            NSString *hash = MD5Hex(url.UTF8String);
            for (size_t i = 0; i < vlc_player_GetTrackCount(_player, cat) && !existing; i++) {
                const struct vlc_player_track *track = vlc_player_GetTrackAt(_player, cat, i);
                if ([SourceHashOfTrack(S(vlc_es_id_GetStrId(track->es_id))) isEqual:hash]) existing = track;
            }
            NSNumber *added = _addedTrackURLs[url];
            if (existing) { if (select) vlc_player_SelectTrack(_player, existing, VLC_PLAYER_SELECT_EXCLUSIVE); }
            else if (!added || CACurrentMediaTime() - added.doubleValue > 5.0) {
                status = vlc_player_AddAssociatedMedia(_player, cat, url.UTF8String, select, false, false);
                if (status == VLC_SUCCESS) _addedTrackURLs[url] = @(CACurrentMediaTime());
            }
        }
    } else if ([command isEqual:MXRBridgeCommandSelectTrack] || [command isEqual:MXRBridgeCommandUnselectTrack]) {
        const struct vlc_player_track *found = NULL;
        enum es_format_category_e categories[] = {AUDIO_ES, VIDEO_ES, SPU_ES};
        for (size_t k = 0; k < 3 && !found; k++) for (size_t i = 0; i < vlc_player_GetTrackCount(_player, categories[k]); i++) {
            const struct vlc_player_track *t = vlc_player_GetTrackAt(_player, categories[k], i);
            if ([S(vlc_es_id_GetStrId(t->es_id)) isEqual:args[@"id"]]) { found = t; break; }
        }
        if (!found) status = VLC_EINVAL;
        else if ([command isEqual:MXRBridgeCommandSelectTrack]) vlc_player_SelectTrack(_player, found, [args[@"exclusive"] boolValue] ? VLC_PLAYER_SELECT_EXCLUSIVE : VLC_PLAYER_SELECT_SIMULTANEOUS);
        else vlc_player_UnselectTrack(_player, found);
    } else supported = NO;
    vlc_player_Unlock(_player);
    if (!supported) return Fail(error, [NSString stringWithFormat:@"Player command %@ is unavailable.", command]);
    if (status != VLC_SUCCESS) return Fail(error, @"VLC rejected this player command or its arguments.");
    /* The engine callbacks report everything else. */
    if (manual) [self scheduleTopics:manual];
    return YES;
}
/* Player lock held. Removes the one-shot option and forgets the item. */
- (void)dropStartPausedItem {
    input_item_t *item = _startPausedItem;
    if (!item) return;
    _startPausedItem = NULL;
    vlc_mutex_lock(&item->lock);
    for (int i = 0; i < item->i_options; i++) {
        if (strcmp(item->ppsz_options[i], StartPausedOption)) continue;
        free(item->ppsz_options[i]);
        memmove(&item->ppsz_options[i], &item->ppsz_options[i + 1], (size_t)(item->i_options - i - 1) * sizeof(*item->ppsz_options));
        memmove(&item->optflagv[i], &item->optflagv[i + 1], (size_t)(item->optflagc - i - 1) * sizeof(*item->optflagv));
        item->i_options--; item->optflagc--;
        break;
    }
    vlc_mutex_unlock(&item->lock);
    input_item_Release(item);
}
- (BOOL)queueCommand:(MXRBridgeCommand)command arguments:(NSDictionary *)args error:(NSError **)error {
    /* Create and retain all inputs before touching the queue. A malformed request cannot
     * clear a valid queue, and neither NSURL nor input option memory outlives its owner. */
    if ([command isEqual:MXRBridgeCommandInsert] || [command isEqual:MXRBridgeCommandPlayNow]) {
        NSArray *descriptions = args[@"items"]; if (![descriptions isKindOfClass:NSArray.class] || !descriptions.count) return Fail(error, @"No media was supplied.");
        input_item_t **inputs = vlc_alloc(descriptions.count, sizeof(*inputs)); if (!inputs) return Fail(error, @"Cannot allocate playlist inputs.");
        size_t count = 0; BOOL valid = YES;
        for (NSDictionary *description in descriptions) {
            NSString *url = description[@"url"], *title = description[@"title"];
            if (![url isKindOfClass:NSString.class] || ![NSURL URLWithString:url].scheme) { valid = NO; break; }
            input_item_t *item = input_item_New(url.UTF8String, [title isKindOfClass:NSString.class] ? title.UTF8String : NULL);
            if (!item) { valid = NO; break; }
            inputs[count++] = item;
            for (NSString *option in description[@"options"]) {
                if (![option isKindOfClass:NSString.class] || !option.length) { valid = NO; break; }
                if (input_item_AddOption(item, option.UTF8String, VLC_INPUT_OPTION_TRUSTED) != VLC_SUCCESS) { valid = NO; break; }
            }
            if (valid && ApplyInputPrivacy(item) != VLC_SUCCESS) valid = NO;
            if (!valid) break;
        }
        int ret = VLC_EINVAL; NSInteger index = [args[@"index"] integerValue];
        if (valid && ([command isEqual:MXRBridgeCommandInsert] || (index >= 0 && (NSUInteger)index < descriptions.count))) {
            [self attachLibrarySubtitlesToInputs:inputs count:count startingAt:[command isEqual:MXRBridgeCommandPlayNow] ? index : -1];
            vlc_playlist_Lock(_playlist);
            if ([command isEqual:MXRBridgeCommandPlayNow]) {
                /* Insert first; only clear the old slice after successful allocation. */
                size_t oldCount = vlc_playlist_Count(_playlist);
                ret = vlc_playlist_Insert(_playlist, oldCount, inputs, count);
                if (ret == VLC_SUCCESS) {
                    if (oldCount) vlc_playlist_Remove(_playlist, 0, oldCount);
                    /* "Start playing when opened" off (SET-02): pause only this start.
                     * vlc_player_SetStartPaused cannot do it: when an input already exists
                     * the player defers the new one to its destructor thread, which starts
                     * it without reading that flag (src/player/player.c, input.c). The input
                     * reads item options when it is created (src/input/input.c), so only the
                     * started item gets a one-shot ":start-paused"; PlayerMedia strips it as
                     * soon as that input exists, so neither the next items nor a later
                     * replay of this one start paused. */
                    [self dropStartPausedItem];
                    if ([args[@"startPaused"] boolValue]
                        && input_item_AddOption(inputs[index], StartPausedOption, VLC_INPUT_OPTION_TRUSTED | VLC_INPUT_OPTION_UNIQUE) == VLC_SUCCESS)
                        _startPausedItem = input_item_Hold(inputs[index]);
                    ret = vlc_playlist_PlayAt(_playlist, index);
                    if (ret != VLC_SUCCESS) [self dropStartPausedItem];
                }
            } else {
                size_t target = index < 0 ? vlc_playlist_Count(_playlist) : (size_t)index;
                ret = target <= vlc_playlist_Count(_playlist) ? vlc_playlist_Insert(_playlist, target, inputs, count) : VLC_EINVAL;
            }
            vlc_playlist_Unlock(_playlist);
        }
        for (size_t i = 0; i < count; i++) input_item_Release(inputs[i]); free(inputs);
        if (ret != VLC_SUCCESS) return Fail(error, @"VLC could not insert or start these media.");
        return YES;
    }
    BOOL supported = YES; int ret = VLC_SUCCESS; NSInteger index = [args[@"index"] integerValue];
    vlc_playlist_Lock(_playlist);
    if ([command isEqual:MXRBridgeCommandPlay]) { if (index < 0 || (size_t)index >= vlc_playlist_Count(_playlist)) ret = VLC_EINVAL; else ret = vlc_playlist_PlayAt(_playlist, index); }
    else if ([command isEqual:MXRBridgeCommandStart]) { if (![self startPlayback:NULL]) ret = VLC_EGENERIC; }
    else if ([command isEqual:MXRBridgeCommandNext]) ret = vlc_playlist_Next(_playlist);
    else if ([command isEqual:MXRBridgeCommandPrevious]) ret = vlc_playlist_Prev(_playlist);
    else if ([command isEqual:MXRBridgeCommandClear]) vlc_playlist_Clear(_playlist);
    else if ([command isEqual:MXRBridgeCommandSetPauseAtEnd]) { _pauseAtEnd = [args[@"value"] boolValue]; config_PutInt("play-and-pause", _pauseAtEnd); [self scheduleTopics:MXRTopicSettings]; vlc_player_SetPlayAndPause(_player, _pauseAtEnd); [self scheduleTopics:MXRTopicQueueState]; }
    else if ([command isEqual:MXRBridgeCommandSetRepeatMode]) { int value = [args[@"value"] intValue]; if (value < 0 || value > 2) ret = VLC_EINVAL; else vlc_playlist_SetPlaybackRepeat(_playlist, value); }
    else if ([command isEqual:MXRBridgeCommandSetOrder]) { int value = [args[@"value"] intValue]; if (value < 0 || value > 1) ret = VLC_EINVAL; else vlc_playlist_SetPlaybackOrder(_playlist, value); }
    else if ([command isEqual:MXRBridgeCommandSetMediaStoppedAction]) { id supplied = args[@"value"]; NSDictionary *actions = @{@"continue":@0, @"stop":@1, @"exit":@2}; int value = [supplied isKindOfClass:NSString.class] ? (actions[supplied] ? [actions[supplied] intValue] : -1) : [supplied intValue]; if (value < 0 || value > 2) ret = VLC_EINVAL; else { config_PutInt("play-and-exit", value == VLC_PLAYLIST_MEDIA_STOPPED_EXIT); config_PutInt("play-and-stop", value == VLC_PLAYLIST_MEDIA_STOPPED_STOP); vlc_playlist_SetMediaStoppedAction(_playlist, value); _stoppedAction = value; [self scheduleTopics:MXRTopicSettings]; } }
    else if ([command isEqual:MXRBridgeCommandRemove] || [command isEqual:MXRBridgeCommandMove]) {
        NSArray *ids = args[@"ids"]; NSMutableSet *wanted = [NSMutableSet setWithArray:ids ?: @[]];
        vlc_playlist_item_t **items = vlc_alloc(wanted.count, sizeof(*items)); size_t n = 0;
        if (!items && wanted.count) ret = VLC_ENOMEM;
        else {
            for (size_t i = 0; i < vlc_playlist_Count(_playlist); i++) {
                vlc_playlist_item_t *item = vlc_playlist_Get(_playlist, i);
                if ([wanted containsObject:[NSString stringWithFormat:@"%llu", (unsigned long long)vlc_playlist_item_GetId(item)]]) items[n++] = item;
            }
            if (n != wanted.count) ret = VLC_EINVAL;
            else if ([command isEqual:MXRBridgeCommandRemove]) ret = vlc_playlist_RequestRemove(_playlist, items, n, -1);
            else if (index < 0 || (size_t)index >= vlc_playlist_Count(_playlist)) ret = VLC_EINVAL;
            else ret = vlc_playlist_RequestMove(_playlist, items, n, index, -1);
            free(items);
        }
    } else if ([command isEqual:MXRBridgeCommandSort]) {
        NSString *key = args[@"key"];
        if ([key isEqual:@"shuffle"]) vlc_playlist_Shuffle(_playlist);
        else {
            NSDictionary *keys = @{@"title":@(VLC_PLAYLIST_SORT_KEY_TITLE), @"duration":@(VLC_PLAYLIST_SORT_KEY_DURATION), @"artist":@(VLC_PLAYLIST_SORT_KEY_ARTIST), @"album":@(VLC_PLAYLIST_SORT_KEY_ALBUM), @"albumArtist":@(VLC_PLAYLIST_SORT_KEY_ALBUM_ARTIST), @"genre":@(VLC_PLAYLIST_SORT_KEY_GENRE), @"date":@(VLC_PLAYLIST_SORT_KEY_DATE), @"trackNumber":@(VLC_PLAYLIST_SORT_KEY_TRACK_NUMBER), @"discNumber":@(VLC_PLAYLIST_SORT_KEY_DISC_NUMBER), @"rating":@(VLC_PLAYLIST_SORT_KEY_RATING), @"url":@(VLC_PLAYLIST_SORT_KEY_URL)};
            NSNumber *sortKey = keys[key]; if (!sortKey) ret = VLC_EINVAL;
            else { struct vlc_playlist_sort_criterion c = {sortKey.intValue, [args[@"descending"] boolValue] ? VLC_PLAYLIST_SORT_ORDER_DESCENDING : VLC_PLAYLIST_SORT_ORDER_ASCENDING}; ret = vlc_playlist_Sort(_playlist, &c, 1); }
        }
    } else supported = NO;
    vlc_playlist_Unlock(_playlist);
    if (!supported) return Fail(error, [NSString stringWithFormat:@"Queue command %@ is unavailable.", command]);
    if (ret != VLC_SUCCESS) return Fail(error, @"Queue item is stale or VLC rejected this operation.");
    return YES;
}
- (void)applyConfig:(NSString *)name value:(id)value object:(vlc_object_t *)object {
    module_config_t *option = config_FindConfig(name.UTF8String);
    if (!option) return;
    int type = option->i_type, varType;
    if (IsConfigIntegerType(type)) varType = type == CONFIG_ITEM_BOOL ? VLC_VAR_BOOL : VLC_VAR_INTEGER;
    else if (IsConfigFloatType(type)) varType = VLC_VAR_FLOAT; else varType = VLC_VAR_STRING;
    var_Create(object, name.UTF8String, varType | VLC_VAR_DOINHERIT);
    if (varType == VLC_VAR_BOOL) var_SetBool(object, name.UTF8String, [value boolValue]);
    else if (varType == VLC_VAR_INTEGER) var_SetInteger(object, name.UTF8String, [value longLongValue]);
    else if (varType == VLC_VAR_FLOAT) var_SetFloat(object, name.UTF8String, [value floatValue]);
    else var_SetString(object, name.UTF8String, [value UTF8String]);
}
- (BOOL)setConfig:(NSString *)name value:(id)value apply:(NSString *)apply error:(NSError **)error {
    if (![self settingAvailable:name]) return Fail(error, @"This setting is unavailable in the native VLC interface.");
    module_config_t *c = config_FindConfig(name.UTF8String); if (!c) return Fail(error, @"This configuration option does not exist.");
    if (IsConfigIntegerType(c->i_type)) {
        if (![value isKindOfClass:NSNumber.class]) return Fail(error, @"An integer configuration value is required.");
        int64_t number = [value longLongValue];
        if ((c->i_type == CONFIG_ITEM_BOOL && number != 0 && number != 1) || (c->min.i != c->max.i && (number < c->min.i || number > c->max.i))) return Fail(error, [NSString stringWithFormat:@"%@: the value is outside its supported range.", name]);
    } else if (IsConfigFloatType(c->i_type)) {
        if (![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue])) return Fail(error, @"A finite numeric configuration value is required.");
        double number = [value doubleValue]; if (c->min.f != c->max.f && (number < c->min.f || number > c->max.f)) return Fail(error, [NSString stringWithFormat:@"%@: the value is outside its supported range.", name]);
    } else if (IsConfigStringType(c->i_type)) {
        if (![value isKindOfClass:NSString.class]) return Fail(error, @"A string configuration value is required.");
    } else return Fail(error, @"This configuration type cannot be changed.");
    BOOL audioPreference = [MXRAudioPreferenceServices handlesOption:name];
    if (audioPreference && ![_audioPreferences applyOption:name value:value error:error]) return NO;
    if ([name isEqual:@"macosx-redesign-sub-shadow"]) {
        if (![self setConfig:@"freetype-shadow-opacity" value:[value boolValue] ? @128 : @0 apply:nil error:error]) return NO;
    } else if ([name isEqual:@"macosx-redesign-sub-background"]) {
        if (![@[@"none", @"box"] containsObject:value]) return Fail(error, @"Choose a supported subtitle background.");
        int64_t opacity = config_FindConfig("freetype-background-opacity") ? config_GetInt("freetype-background-opacity") : 0;
        if (![self setConfig:@"freetype-background-opacity" value:[value isEqual:@"box"] ? @(opacity > 0 ? opacity : 128) : @0 apply:@"vout" error:error]) return NO;
    } else if ([name isEqual:@"macosx-redesign-sub-size-mode"] && ![@[@"relative", @"pixels"] containsObject:value]) return Fail(error, @"Choose relative or pixel subtitle sizes.");
    else if ([name isEqual:@"macosx-redesign-osd-duration"] && ([value doubleValue] < 0.5 || [value doubleValue] > 5)) return Fail(error, @"On-screen message duration must be between 0.5 and 5 seconds.");
    if (IsConfigIntegerType(c->i_type)) config_PutInt(name.UTF8String, [value longLongValue]);
    else if (IsConfigFloatType(c->i_type)) config_PutFloat(name.UTF8String, [value floatValue]);
    else config_PutPsz(name.UTF8String, [value UTF8String]);
    if ([name isEqual:@"macosx-redesign-remember-position"] || [name isEqual:@"macosx-redesign-history-exclude"] || [name isEqual:@"save-recentplay"] || [name isEqual:@"restore-playback-pos"]) {
        /* Remembering gates each input via ApplyInputPrivacy; retain the user's
         * independent Never/Ask/Always restore choice when toggling it. */
        vlc_playlist_Lock(_playlist);
        for (size_t i = 0; i < vlc_playlist_Count(_playlist); i++) ApplyInputPrivacy(vlc_playlist_item_GetMedia(vlc_playlist_Get(_playlist, i)));
        input_item_t *current = vlc_player_GetCurrentMedia(_player); NSString *url = current ? OwnedString(input_item_GetURI(current)) : @"";
        vlc_playlist_Unlock(_playlist);
        if (!AllowsPositionForURL(url)) { _restorePrompt = nil; _restoreURL = nil; [self scheduleTopics:MXRTopicState]; }
    }
    /* These options configure long-lived playlist/player state, not merely the
     * config file. Keep order changes live; rate updates only the inherited
     * default on the player, without pushing a rate control to the current input. */
    if ([name isEqual:@"rate"]) {
        vlc_playlist_Lock(_playlist);
        var_SetFloat((vlc_object_t *)_player, "rate", [value floatValue]);
        vlc_playlist_Unlock(_playlist);
    }
    if ([@[@"loop", @"repeat", @"random", @"play-and-stop", @"play-and-exit", @"play-and-pause"] containsObject:name]) {
        vlc_playlist_Lock(_playlist);
        if ([name isEqual:@"loop"] || [name isEqual:@"repeat"])
            vlc_playlist_SetPlaybackRepeat(_playlist, config_GetInt("repeat") ? VLC_PLAYLIST_PLAYBACK_REPEAT_CURRENT : config_GetInt("loop") ? VLC_PLAYLIST_PLAYBACK_REPEAT_ALL : VLC_PLAYLIST_PLAYBACK_REPEAT_NONE);
        else if ([name isEqual:@"random"])
            vlc_playlist_SetPlaybackOrder(_playlist, [value boolValue] ? VLC_PLAYLIST_PLAYBACK_ORDER_RANDOM : VLC_PLAYLIST_PLAYBACK_ORDER_NORMAL);
        else if ([name isEqual:@"play-and-pause"]) {
            _pauseAtEnd = [value boolValue]; vlc_player_SetPlayAndPause(_player, _pauseAtEnd);
        } else {
            _stoppedAction = config_GetInt("play-and-exit") ? VLC_PLAYLIST_MEDIA_STOPPED_EXIT : config_GetInt("play-and-stop") ? VLC_PLAYLIST_MEDIA_STOPPED_STOP : VLC_PLAYLIST_MEDIA_STOPPED_CONTINUE;
            vlc_playlist_SetMediaStoppedAction(_playlist, _stoppedAction);
        }
        vlc_playlist_Unlock(_playlist);
        [self scheduleTopics:MXRTopicQueueState];
    }
    /* "osd" is the user's "Show feedback for shortcuts": it drives the redesign OSD only.
     * Never push it onto engine objects, where it would turn the core OSD back on. */
    if (![name isEqual:@"osd"]) {
        if ([apply isEqual:@"instance"]) [self applyConfig:name value:value object:VLC_OBJECT(vlc_object_instance(_intf))];
        else if ([apply isEqual:@"aout"]) { audio_output_t *aout = vlc_player_aout_Hold(_player); if (aout) { [self applyConfig:name value:value object:VLC_OBJECT(aout)]; aout_Release(aout); } }
        else if ([apply isEqual:@"vout"]) { size_t count; vout_thread_t **vouts = vlc_player_vout_HoldAll(_player, &count); for (size_t i = 0; i < count; i++) { [self applyConfig:name value:value object:VLC_OBJECT(vouts[i])]; vout_Release(vouts[i]); } free(vouts); }
    }
    if ([name isEqual:@"macosx-redesign-sub-size-mode"] || [name isEqual:@"macosx-redesign-sub-pixel-size"]) {
        /* Settings and the sidebar share one subtitle size: pixel sizes become VLC's text
         * scale for the current video (CMP-18). */
        [_effects applySubtitleSizePreference];
    }
    /* ARC-15: report only the option that changed; listeners re-read that one value. */
    [self changed:MXRBridgeServiceForSetting(name)];
    MXRTopic topics = 0;
    if ([name hasPrefix:@"macosx-redesign-key-"] || [name hasPrefix:@"key-"] || [name hasPrefix:@"global-key-"]) topics |= MXRTopicShortcuts;
    if ([name hasPrefix:@"macosx-redesign-sub-"] || [name hasPrefix:@"freetype-"] || [name isEqual:@"sub-text-scale"]) topics |= MXRTopicEffects | MXRTopicSync;
    if ([name isEqual:@"preferred-resolution"]) topics |= MXRTopicEffects; /* the Video tab's Resolution row */
    if (audioPreference || [apply isEqual:@"aout"] || [apply isEqual:@"vout"]) topics |= MXRTopicEffects | MXRTopicSync | MXRTopicVolume;
    if (topics) [self scheduleTopics:topics];
    return YES;
}
/// Any thread (playlist callbacks): the config already holds the new mode.
- (void)queueModeChanged:(bool)persist {
    [self scheduleTopics:MXRTopicQueueState | MXRTopicSettings];
    if (!persist) return;
    __weak MXRServicesBridge *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ MXRServicesBridge *self = weakSelf; if (self && !self->_shutDown) [self scheduleSave]; });
}
- (void)scheduleSave {
    _savePending = YES;
    NSUInteger generation = ++_saveGeneration;
    __weak MXRServicesBridge *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        MXRServicesBridge *self = weakSelf; if (!self || self->_shutDown || self->_saveGeneration != generation) return;
        /* finishShutdown drains this queue off main before the instance is destroyed. */
        [self enqueueConfigSave];
    });
}
- (void)enqueueConfigSave {
    _savePending = NO; vlc_object_t *instance = VLC_OBJECT(vlc_object_instance(_intf));
    __weak MXRServicesBridge *weakSelf = self;
    dispatch_async(_workQueue, ^{ @autoreleasepool {
        int result = config_SaveConfigFile(instance);
        if (result != VLC_SUCCESS) dispatch_async(dispatch_get_main_queue(), ^{
            MXRServicesBridge *self = weakSelf;
            if (!self || self->_shutDown) return;
            self->_savePending = YES; /* Retain dirty state; Save retries, shutdown drains it. */
            [self changed:MXRBridgeServiceSettingsSaveFailed];
        });
    }});
}
- (BOOL)settingsCommand:(MXRBridgeCommand)command arguments:(NSDictionary *)args error:(NSError **)error {
    if ([command isEqual:MXRBridgeCommandSet]) return [self setConfig:args[@"name"] value:args[@"value"] apply:args[@"apply"] error:error];
    if ([command isEqual:MXRBridgeCommandReset]) { NSString *name = args[@"name"]; module_config_t *c = config_FindConfig(name.UTF8String); if (!c) return Fail(error, @"Unknown option."); return [self setConfig:name value:OriginalValue(c) apply:nil error:error]; }
    if ([command isEqual:MXRBridgeCommandResetAll]) {
        config_ResetAll();
        [_audioPreferences resetAfterConfigurationReset];
        for (NSString *name in @[@"rate", @"loop", @"repeat", @"random", @"play-and-stop", @"play-and-exit", @"play-and-pause"])
            if ([self settingAvailable:name]) [self setConfig:name value:ConfigValue(name.UTF8String) apply:nil error:NULL];
        vlc_playlist_Lock(_playlist);
        for (size_t i = 0; i < vlc_playlist_Count(_playlist); i++) ApplyInputPrivacy(vlc_playlist_item_GetMedia(vlc_playlist_Get(_playlist, i)));
        vlc_playlist_Unlock(_playlist);
        [self scheduleTopics:MXRTopicSettings | MXRTopicShortcuts | MXRTopicAllPlayer]; return YES;
    }
    if ([command isEqual:MXRBridgeCommandSave]) { [self scheduleSave]; return YES; }
    return Fail(error, [NSString stringWithFormat:@"Settings command %@ is unavailable.", command]);
}
- (BOOL)shortcutsCommand:(MXRBridgeCommand)command arguments:(NSDictionary *)args error:(NSError **)error {
    if ([command isEqual:MXRBridgeCommandTrigger]) return [self triggerAction:args[@"id"] error:error];
    if ([command isEqual:MXRBridgeCommandSetBindings]) {
        NSString *action = args[@"id"]; if (vlc_actions_get_id([@"key-" stringByAppendingString:action ?: @""].UTF8String) == ACTIONID_NONE) return Fail(error, @"Unknown hotkey action.");
        for (NSString *key in @[@"hotkeys", @"global"]) {
            NSArray *bindings = args[key]; NSMutableArray *strings = [NSMutableArray array];
            for (id binding in bindings) {
                if (![binding isKindOfClass:NSString.class] || (!vlc_str2keycode([binding UTF8String]) && [binding length])) return Fail(error, @"Invalid VLC key binding.");
                [strings addObject:binding];
            }
            NSString *option = [NSString stringWithFormat:@"%@key-%@", [key isEqual:@"global"] ? @"global-" : @"", action];
            config_PutPsz(option.UTF8String, [[strings componentsJoinedByString:@"\t"] UTF8String]);
        }
        [self scheduleTopics:MXRTopicShortcuts | MXRTopicSettings]; return YES;
    }
    if ([command isEqual:MXRBridgeCommandResetAll]) {
        const char *const *names = vlc_actions_get_key_names(_intf);
        if (names) for (size_t i = 0; names[i]; i++) for (NSString *prefix in @[@"key-", @"global-key-"]) {
            NSString *option = [prefix stringByAppendingString:S(names[i])]; module_config_t *c = config_FindConfig(option.UTF8String); if (c) config_PutPsz(option.UTF8String, c->orig.psz);
        }
        [self scheduleTopics:MXRTopicShortcuts]; return YES;
    }
    if ([command isEqual:MXRBridgeCommandSave]) { [self scheduleSave]; return YES; }
    return Fail(error, [NSString stringWithFormat:@"Shortcut command %@ is unavailable.", command]);
}
- (BOOL)performCommand:(MXRBridgeCommand)command service:(MXRBridgeService)service arguments:(NSDictionary *)arguments error:(NSError **)error {
    NSAssert(NSThread.isMainThread, @"Bridge commands require the main thread");
    if (_shutDown) return Fail(error, @"VLC is shutting down.");
    if ([service isEqual:MXRBridgeServicePlayer]) return [self playerCommand:command arguments:arguments error:error];
    if ([service isEqual:MXRBridgeServiceQueue]) return [self queueCommand:command arguments:arguments error:error];
    if ([service isEqual:MXRBridgeServiceSettings]) return [self settingsCommand:command arguments:arguments error:error];
    if ([service isEqual:MXRBridgeServiceShortcuts]) return [self shortcutsCommand:command arguments:arguments error:error];
    if ([service isEqual:MXRBridgeServiceDialogs]) return [_dialogs performCommand:command arguments:arguments error:error];
    if ([service isEqual:MXRBridgeServiceLibrary]) {
        if (!_library.available) return Fail(error, @"The VLC media library is unavailable.");
        __weak MXRServicesBridge *weakSelf = self;
        [_library request:command arguments:arguments completion:^(NSDictionary *result, NSError *error) { (void)result; if (error) [weakSelf applyOperationError:error]; }];
        return YES; /* Accepted for asynchronous execution; engine failures are reported as dialogs. */
    }
    if ([@[MXRBridgeServiceOutput, MXRBridgeServiceExtensions, MXRBridgeServiceRenderers] containsObject:service]) return [_mediaServices performCommand:command service:service arguments:arguments error:error];
    if ([service isEqual:MXRBridgeServiceMediaSources]) return [_discovery performCommand:command service:service arguments:arguments error:error];
    return Fail(error, [NSString stringWithFormat:@"Service %@ is unavailable.", service]);
}
- (void)applyOperationError:(NSError *)error {
    if (_shutDown) return;
    [_dialogs display:NULL values:@{@"kind":@"error", @"title":@"VLC operation failed", @"text":error.localizedDescription}];
}
- (void)request:(MXRBridgeRequest)request service:(MXRBridgeService)service arguments:(NSDictionary *)arguments completion:(void (^)(NSDictionary<NSString *, id> * _Nullable, NSError * _Nullable))completion {
    if (_shutDown) { completion(nil, Error(2, @"VLC is shutting down.")); return; }
    if ([service isEqual:MXRBridgeServicePlayer] && [request isEqual:MXRBridgeRequestSubtitleCues]) { [_subtitleCues request:request service:service arguments:arguments completion:completion]; return; }
    if ([service isEqual:MXRBridgeServiceLibrary]) { [_library request:request arguments:arguments completion:completion]; return; }
    if ([service isEqual:MXRBridgeServiceAudioTest] || ([service isEqual:MXRBridgeServiceThumbnails] && ([@[MXRBridgeRequestWaveform, MXRBridgeRequestCancelWaveform] containsObject:request]))) {
        [_audioServices request:request service:service arguments:arguments completion:completion]; return;
    }
    if ([service isEqual:MXRBridgeServiceThumbnails]) { [_thumbnails request:request arguments:arguments completion:completion]; return; }
    if ([@[MXRBridgeServiceOutput, MXRBridgeServiceExtensions, MXRBridgeServiceRenderers] containsObject:service]) { [_mediaServices request:request service:service arguments:arguments completion:completion]; return; }
    if ([service isEqual:MXRBridgeServiceMediaSources]) { [_discovery request:request service:service arguments:arguments completion:completion]; return; }
    if ([service isEqual:MXRBridgeServiceSettings] && ([request isEqual:MXRBridgeRequestDynamicChoices] || [request isEqual:MXRBridgeRequestChoices])) {
        NSString *name = [arguments[@"name"] isKindOfClass:NSString.class] ? [arguments[@"name"] copy] : nil;
        module_config_t *option = name && [self settingAvailable:name] ? config_FindConfig(name.UTF8String) : NULL; int type = option ? option->i_type : 0;
        if (!IsConfigIntegerType(type) && !IsConfigStringType(type)) { completion(nil, Error(1, @"Unknown option.")); return; }
        __weak MXRServicesBridge *weakSelf = self;
        dispatch_async(_workQueue, ^{ @autoreleasepool {
            NSMutableArray *choices = [NSMutableArray array]; ssize_t count;
            if (IsConfigIntegerType(type)) {
                int64_t *values = NULL; char **texts = NULL; count = config_GetIntChoices(name.UTF8String, &values, &texts);
                for (ssize_t i = 0; i < count; i++) { [choices addObject:@{@"value":@(values[i]), @"title":S(texts[i])}]; free(texts[i]); }
                if (count >= 0) { free(values); free(texts); }
            } else {
                char **values = NULL, **texts = NULL; count = config_GetPszChoices(name.UTF8String, &values, &texts);
                for (ssize_t i = 0; i < count; i++) { [choices addObject:@{@"value":S(values[i]), @"title":S(texts[i])}]; free(values[i]); free(texts[i]); }
                if (count >= 0) { free(values); free(texts); }
            }
            NSDictionary *reply = @{@"choices":[choices copy]}; NSError *failure = count < 0 ? Error(1, @"VLC could not load this option's choices.") : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                MXRServicesBridge *self = weakSelf;
                if (!self || self->_shutDown) completion(nil, Error(2, @"VLC is shutting down."));
                else completion(failure ? nil : reply, failure);
            });
        }}); return;
    }
    completion(nil, Error(3, [NSString stringWithFormat:@"%@ request %@ is unavailable.", service, request]));
}
@end
