/*****************************************************************************
 * MXRPlayerBridge.m: vlc_player_t for the Swift UI
 *****************************************************************************
 * Copyright (C) 2026 VLC Redesign contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *****************************************************************************/

/*
 * Threading (ARCHITECTURE.md §2.3): player callbacks arrive on VLC threads with the player
 * lock held, timer callbacks without it. Each callback copies what it needs and hops to the
 * main queue with dispatch_async (never dispatch_sync). The blocks retain the bridge; they
 * check _shutDown before touching the sink. Commands lock the player only around the call.
 *
 * Minimal on purpose (phase 0): state, current media, length, clock, transport, fullscreen.
 * The full bridge (tracks, aout, vout options...) grows here or reuses VLCPlayerController (§4).
 */

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <stdatomic.h>
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_input_item.h>
#include <vlc_player.h>
#include <vlc_playlist.h>
#include <vlc_window.h>

#import "MXRBridgeInternal.h"

static const MXRTimerPoint MXRTimerPointNone = {
    .time = -1, .length = -1, .position = 0., .rate = 1., .hostTime = 0., .live = false,
};

/* Converts a vlc_tick_t system date to the CACurrentMediaTime() base; 0 = not valid. */
static double MXRHostTimeFromSystemDate(vlc_tick_t system_date)
{
    if (system_date == INT64_MAX || system_date == VLC_TICK_INVALID)
        return 0.;
    const vlc_tick_t now = vlc_tick_now();
    return CACurrentMediaTime() + secf_from_vlc_tick(system_date - now);
}

static MXRTimerPoint MXRTimerPointFromVLC(const struct vlc_player_timer_point *p)
{
    MXRTimerPoint point;
    point.time = p->ts != VLC_TICK_INVALID ? US_FROM_VLC_TICK(p->ts - VLC_TICK_0) : -1;
    point.length = p->length != VLC_TICK_INVALID ? US_FROM_VLC_TICK(p->length) : -1;
    point.position = p->position;
    point.rate = p->rate;
    point.hostTime = MXRHostTimeFromSystemDate(p->system_date);
    point.live = p->live;
    return point;
}

static NSString *MXRStringFromUTF8(char *str)
{
    if (str == NULL)
        return nil;
    NSString *result = [NSString stringWithUTF8String:str];
    free(str);
    return result;
}

static MXRPlayerState MXRPlayerStateFromVLC(enum vlc_player_state state)
{
    switch (state) {
        case VLC_PLAYER_STATE_STARTED:  return MXRPlayerStateStarted;
        case VLC_PLAYER_STATE_PLAYING:  return MXRPlayerStatePlaying;
        case VLC_PLAYER_STATE_PAUSED:   return MXRPlayerStatePaused;
        case VLC_PLAYER_STATE_STOPPING: return MXRPlayerStateStopping;
        case VLC_PLAYER_STATE_STOPPED:
        default:                        return MXRPlayerStateStopped;
    }
}

@interface MXRPlayerBridge ()
- (void)applyState:(MXRPlayerState)state;
- (void)applyInteractiveVideo:(BOOL)interactive;
- (void)applySeek;
- (void)applyMediaTitle:(nullable NSString *)title uri:(nullable NSString *)uri;
- (void)applyLength:(int64_t)length;
- (void)applyCapabilities:(int)capabilities;
- (void)applyTimerPoint:(MXRTimerPoint)point;
- (void)applyClockPausedAtHostTime:(double)hostTime;
- (void)applyFullscreen:(BOOL)fullscreen;
@end

#pragma mark - Player callbacks (VLC threads, player locked)

static void cb_current_media_changed(vlc_player_t *player, input_item_t *media, void *data)
{
    VLC_UNUSED(player);
    MXRPlayerBridge *bridge = (__bridge MXRPlayerBridge *)data;
    NSString *title = nil, *uri = nil;
    if (media != NULL) {
        title = MXRStringFromUTF8(input_item_GetTitleFbName(media));
        uri = MXRStringFromUTF8(input_item_GetURI(media));
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [bridge applyMediaTitle:title uri:uri];
    });
}

static void cb_media_meta_changed(vlc_player_t *player, input_item_t *media, void *data)
{
    /* Only the current media matters; the meta title can arrive after opening. */
    if (media == NULL || media != vlc_player_GetCurrentMedia(player))
        return;
    cb_current_media_changed(player, media, data);
}

static void cb_state_changed(vlc_player_t *player, enum vlc_player_state state, void *data)
{
    VLC_UNUSED(player);
    MXRPlayerBridge *bridge = (__bridge MXRPlayerBridge *)data;
    const MXRPlayerState newState = MXRPlayerStateFromVLC(state);
    dispatch_async(dispatch_get_main_queue(), ^{
        [bridge applyState:newState];
    });
}

static void cb_length_changed(vlc_player_t *player, vlc_tick_t length, void *data)
{
    VLC_UNUSED(player);
    MXRPlayerBridge *bridge = (__bridge MXRPlayerBridge *)data;
    const int64_t value = length != VLC_TICK_INVALID ? US_FROM_VLC_TICK(length) : -1;
    dispatch_async(dispatch_get_main_queue(), ^{
        [bridge applyLength:value];
    });
}

static void cb_capabilities_changed(vlc_player_t *player, int old_caps, int new_caps, void *data)
{
    VLC_UNUSED(player); VLC_UNUSED(old_caps);
    MXRPlayerBridge *bridge = (__bridge MXRPlayerBridge *)data;
    dispatch_async(dispatch_get_main_queue(), ^{
        [bridge applyCapabilities:new_caps];
    });
}

static void cb_title_selected(vlc_player_t *player, const struct vlc_player_title *title, size_t index, void *data)
{
    VLC_UNUSED(player); VLC_UNUSED(index);
    MXRPlayerBridge *bridge = (__bridge MXRPlayerBridge *)data;
    BOOL interactive = title && (title->flags & (VLC_PLAYER_TITLE_MENU | VLC_PLAYER_TITLE_INTERACTIVE));
    dispatch_async(dispatch_get_main_queue(), ^{ [bridge applyInteractiveVideo:interactive]; });
}

static void cb_titles_changed(vlc_player_t *player, vlc_player_title_list *titles, void *data)
{
    VLC_UNUSED(titles);
    cb_title_selected(player, vlc_player_GetSelectedTitle(player), 0, data);
}

static const struct vlc_player_cbs player_cbs = {
    .on_title_selection_changed = cb_title_selected,
    .on_titles_changed = cb_titles_changed,
    .on_current_media_changed = cb_current_media_changed,
    .on_state_changed = cb_state_changed,
    .on_capabilities_changed = cb_capabilities_changed,
    .on_length_changed = cb_length_changed,
    .on_media_meta_changed = cb_media_meta_changed,
};

static void cb_vout_fullscreen_changed(vout_thread_t *vout, bool enabled, void *data)
{
    VLC_UNUSED(vout);
    MXRPlayerBridge *bridge = (__bridge MXRPlayerBridge *)data;
    dispatch_async(dispatch_get_main_queue(), ^{
        [bridge applyFullscreen:enabled];
    });
}

static const struct vlc_player_vout_cbs player_vout_cbs = {
    .on_fullscreen_changed = cb_vout_fullscreen_changed,
};

#pragma mark - Timer callbacks (timer thread, player NOT locked)

/* BB-03: between on_seek(point) and on_seek(NULL) the timer may still deliver points from before
 * the seek. They are dropped so the playhead and elapsed label never jump back to the old position.
 * The window is bounded: if the engine never reports the end of a seek, updates resume after 1.5 s. */
static _Atomic uint64_t mxr_seek_started_ns; /* 0 when no seek is pending */
static const uint64_t mxr_seek_window_ns = 1500000000ull;

static void cb_timer_update(const struct vlc_player_timer_point *value, void *data)
{
    const uint64_t started = atomic_load_explicit(&mxr_seek_started_ns, memory_order_relaxed);
    if (started != 0 && clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - started < mxr_seek_window_ns)
        return;
    MXRPlayerBridge *bridge = (__bridge MXRPlayerBridge *)data;
    const MXRTimerPoint point = MXRTimerPointFromVLC(value);
    dispatch_async(dispatch_get_main_queue(), ^{
        [bridge applyTimerPoint:point];
    });
}

static void cb_timer_paused(vlc_tick_t system_date, void *data)
{
    MXRPlayerBridge *bridge = (__bridge MXRPlayerBridge *)data;
    const double hostTime = MXRHostTimeFromSystemDate(system_date);
    dispatch_async(dispatch_get_main_queue(), ^{
        [bridge applyClockPausedAtHostTime:hostTime];
    });
}

static void cb_timer_seek(const struct vlc_player_timer_point *value, void *data)
{
    if (value == NULL) { /* seek finished: the next update carries the new point */
        atomic_store_explicit(&mxr_seek_started_ns, 0, memory_order_relaxed);
        return;
    }
    MXRPlayerBridge *bridge = (__bridge MXRPlayerBridge *)data;
    dispatch_async(dispatch_get_main_queue(), ^{ [bridge applySeek]; });
    /* The seek's own point is delivered once, then stale updates are dropped until it completes. */
    atomic_store_explicit(&mxr_seek_started_ns, 0, memory_order_relaxed);
    cb_timer_update(value, data);
    atomic_store_explicit(&mxr_seek_started_ns, clock_gettime_nsec_np(CLOCK_UPTIME_RAW), memory_order_relaxed);
}

static const struct vlc_player_timer_cbs player_timer_cbs = {
    .on_update = cb_timer_update,
    .on_paused = cb_timer_paused,
    .on_seek = cb_timer_seek,
};

#pragma mark - MXRPlayerBridge

@implementation MXRPlayerBridge
{
    intf_thread_t *_intf;
    vlc_playlist_t *_playlist;
    vlc_player_t *_player;
    vlc_player_listener_id *_listener;
    vlc_player_vout_listener_id *_voutListener;
    vlc_player_timer_id *_timer;
    BOOL _shutDown;
}

- (nullable instancetype)initWithPlaylist:(vlc_playlist_t *)playlist interface:(intf_thread_t *)intf
{
    self = [super init];
    if (self == nil)
        return nil;

    _intf = intf;
    _playlist = playlist;
    _player = vlc_playlist_GetPlayer(playlist);
    _timerPoint = MXRTimerPointNone;
    _length = -1;

    vlc_player_Lock(_player);
    _listener = vlc_player_AddListener(_player, &player_cbs, (__bridge void *)self);
    /* Initial state, in case something is already playing. */
    _state = MXRPlayerStateFromVLC(vlc_player_GetState(_player));
    const struct vlc_player_title *title = vlc_player_GetSelectedTitle(_player);
    _interactiveVideo = title && (title->flags & (VLC_PLAYER_TITLE_MENU | VLC_PLAYER_TITLE_INTERACTIVE));
    input_item_t *media = vlc_player_GetCurrentMedia(_player);
    if (media != NULL) {
        _mediaTitle = MXRStringFromUTF8(input_item_GetTitleFbName(media));
        NSString *uri = MXRStringFromUTF8(input_item_GetURI(media));
        _mediaURL = uri != nil ? [NSURL URLWithString:uri] : nil;
        const vlc_tick_t length = vlc_player_GetLength(_player);
        _length = length != VLC_TICK_INVALID ? US_FROM_VLC_TICK(length) : -1;
    }
    const int caps = vlc_player_GetCapabilities(_player);
    _canPause = (caps & VLC_PLAYER_CAP_PAUSE) != 0;
    _canSeek = (caps & VLC_PLAYER_CAP_SEEK) != 0;
    vlc_player_Unlock(_player);

    /* vlc_player_vout_*() functions need no player lock (vlc_player.h); keep them outside it. */
    _voutListener = vlc_player_vout_AddListener(_player, &player_vout_cbs, (__bridge void *)self);
    _fullscreen = vlc_player_vout_IsFullscreen(_player);

    _timer = vlc_player_AddTimer(_player, VLC_TICK_FROM_MS(250), &player_timer_cbs,
                                 (__bridge void *)self);

    if (_listener == NULL || _voutListener == NULL || _timer == NULL) {
        msg_Err(intf, "could not register the player listeners");
        [self shutdown];
        return nil;
    }
    return self;
}

- (void)dealloc
{
    assert(_listener == NULL && _voutListener == NULL && _timer == NULL);
}

- (void)shutdown
{
    if (_shutDown)
        return;
    _shutDown = YES;
    if (_timer != NULL) {
        vlc_player_RemoveTimer(_player, _timer);
        _timer = NULL;
    }
    if (_voutListener != NULL)
        vlc_player_vout_RemoveListener(_player, _voutListener);
    if (_listener != NULL) {
        vlc_player_Lock(_player);
        vlc_player_RemoveListener(_player, _listener);
        vlc_player_Unlock(_player);
    }
    _listener = NULL;
    _voutListener = NULL;
    _sink = nil;
}

#pragma mark Cached state (main thread)

- (void)applyInteractiveVideo:(BOOL)interactive {
    if (_shutDown || _interactiveVideo == interactive) return;
    _interactiveVideo = interactive;
    [NSNotificationCenter.defaultCenter postNotificationName:MXRInteractiveVideoDidChangeNotification object:self];
}
- (void)applySeek { if (!_shutDown) _seekGeneration++; }

- (BOOL)isActive
{
    return _state == MXRPlayerStatePlaying || _state == MXRPlayerStatePaused
        || _state == MXRPlayerStateStarted;
}

- (void)applyState:(MXRPlayerState)state
{
    if (_shutDown || state == _state)
        return;
    _state = state;
    if (state == MXRPlayerStateStopped)
        _timerPoint.hostTime = 0.;
    [_sink playerStateDidChange];
}

- (void)applyMediaTitle:(nullable NSString *)title uri:(nullable NSString *)uri
{
    if (_shutDown)
        return;
    NSURL *url = uri != nil ? [NSURL URLWithString:uri] : nil;
    const BOOL sameMedia = (url == _mediaURL) || [url isEqual:_mediaURL];
    _mediaTitle = [title copy];
    _mediaURL = url;
    if (!sameMedia) {
        _interactiveVideo = NO;
        _timerPoint = MXRTimerPointNone;
        _length = -1;
    }
    [_sink playerCurrentMediaDidChange];
}

- (void)applyLength:(int64_t)length
{
    if (_shutDown || length == _length)
        return;
    _length = length;
    [_sink playerLengthDidChange];
}

- (void)applyCapabilities:(int)capabilities
{
    if (_shutDown)
        return;
    _canPause = (capabilities & VLC_PLAYER_CAP_PAUSE) != 0;
    _canSeek = (capabilities & VLC_PLAYER_CAP_SEEK) != 0;
    [_sink playerLengthDidChange];
}

- (void)applyTimerPoint:(MXRTimerPoint)point
{
    if (_shutDown)
        return;
    _timerPoint = point;
    if (point.length >= 0 && point.length != _length) {
        _length = point.length;
        [_sink playerLengthDidChange];
    }
    [_sink playerTimeDidChange];
}

- (void)applyClockPausedAtHostTime:(double)hostTime
{
    if (_shutDown)
        return;
    MXRTimerPoint point = _timerPoint;
    if (point.hostTime > 0. && hostTime > 0. && point.time >= 0) {
        /* Freeze the clock where it stopped (vlc_player_timer_point_Interpolate semantics). */
        int64_t time = point.time + (int64_t)((hostTime - point.hostTime) * point.rate * 1e6);
        if (time < 0)
            time = 0;
        if (point.length > 0 && time > point.length)
            time = point.length;
        point.time = time;
        if (point.length > 0)
            point.position = (double)time / (double)point.length;
    }
    point.hostTime = 0.;
    _timerPoint = point;
    [_sink playerClockDidPause];
}

- (void)applyFullscreen:(BOOL)fullscreen
{
    if (_shutDown || fullscreen == _fullscreen)
        return;
    _fullscreen = fullscreen;
    [_sink playerFullscreenDidChange];
}

#pragma mark Commands (main thread)

- (void)play
{
    if (_shutDown)
        return;
    vlc_playlist_Lock(_playlist);
    switch (vlc_player_GetState(_player)) {
        case VLC_PLAYER_STATE_PAUSED:
            vlc_player_Resume(_player);
            break;
        case VLC_PLAYER_STATE_STOPPED:
            if (vlc_playlist_Count(_playlist) > 0)
                vlc_playlist_Start(_playlist);
            break;
        default:
            break;
    }
    vlc_playlist_Unlock(_playlist);
}

- (void)pause
{
    if (_shutDown)
        return;
    vlc_player_Lock(_player);
    vlc_player_Pause(_player);
    vlc_player_Unlock(_player);
}

- (void)togglePlayPause
{
    if (_shutDown)
        return;
    vlc_playlist_Lock(_playlist);
    switch (vlc_player_GetState(_player)) {
        case VLC_PLAYER_STATE_PLAYING:
        case VLC_PLAYER_STATE_STARTED:
            vlc_player_Pause(_player);
            break;
        case VLC_PLAYER_STATE_PAUSED:
            vlc_player_Resume(_player);
            break;
        case VLC_PLAYER_STATE_STOPPED:
            if (vlc_playlist_Count(_playlist) > 0)
                vlc_playlist_Start(_playlist);
            break;
        default:
            break;
    }
    vlc_playlist_Unlock(_playlist);
}

- (void)stop
{
    if (_shutDown)
        return;
    vlc_playlist_Lock(_playlist);
    vlc_playlist_Stop(_playlist);
    vlc_playlist_Unlock(_playlist);
}

- (void)seekToTime:(int64_t)time precise:(BOOL)precise
{
    if (_shutDown || time < 0)
        return;
    vlc_player_Lock(_player);
    vlc_player_SeekByTime(_player, VLC_TICK_0 + VLC_TICK_FROM_US(time),
                          precise ? VLC_PLAYER_SEEK_PRECISE : VLC_PLAYER_SEEK_FAST,
                          VLC_PLAYER_WHENCE_ABSOLUTE);
    vlc_player_Unlock(_player);
}

- (void)jumpBy:(int64_t)offset
{
    if (_shutDown)
        return;
    vlc_player_Lock(_player);
    vlc_player_JumpTime(_player, VLC_TICK_FROM_US(offset));
    vlc_player_Unlock(_player);
}

- (void)setFullscreen:(BOOL)fullscreen
{
    if (_shutDown)
        return;
    vlc_player_vout_SetFullscreen(_player, fullscreen);
}

- (void)toggleFullscreen
{
    if (_shutDown)
        return;
    vlc_player_vout_SetFullscreen(_player, !vlc_player_vout_IsFullscreen(_player));
}

@end
