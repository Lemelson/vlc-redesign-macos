/*****************************************************************************
 * MXRPlayerBridge.h: the VLC player (vlc_player_t) as seen from Swift
 *****************************************************************************
 * Copyright (C) 2026 VLC Redesign contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *****************************************************************************/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Mirrors `enum vlc_player_state`.
typedef NS_ENUM(NSInteger, MXRPlayerState) {
    MXRPlayerStateStopped = 0,
    MXRPlayerStateStarted,
    MXRPlayerStatePlaying,
    MXRPlayerStatePaused,
    MXRPlayerStateStopping,
};

/// One sample of the player clock (`struct vlc_player_timer_point`), converted for Swift.
typedef struct MXRTimerPoint {
    /// Media time in microseconds at `hostTime`; -1 when unknown.
    int64_t time;
    /// Media length in microseconds; -1 when unknown.
    int64_t length;
    /// Position 0...1 at `hostTime`.
    double position;
    /// Playback rate (for interpolation).
    double rate;
    /// `CACurrentMediaTime()`-based seconds at which `time` was valid.
    /// 0 means "do not interpolate" (paused, or no clock yet).
    double hostTime;
    /// True when `length` is a seek range (live streams).
    bool live;
} MXRTimerPoint;

/// Receives player events. Always called on the main queue, after the bridge's cached
/// properties have been updated, so the sink can simply re-read them.
NS_SWIFT_UI_ACTOR
@protocol MXRPlayerEventSink <NSObject>
/// `state` changed.
- (void)playerStateDidChange;
/// A different media became current (or none): `mediaTitle`, `mediaURL`, `length` may have changed.
- (void)playerCurrentMediaDidChange;
/// `length` or `capabilities` changed.
- (void)playerLengthDidChange;
/// A new clock sample is available in `timerPoint` (about every 250 ms while playing).
- (void)playerTimeDidChange;
/// The clock stopped (pause, end of stream): stop interpolating `timerPoint`.
- (void)playerClockDidPause;
/// The engine asks the window to enter or leave fullscreen. Fullscreen itself goes through
/// the video output (MXRVideoSurfaceProvider); this is informational.
- (void)playerFullscreenDidChange;
@end

/// Wraps the interface's `vlc_player_t` (from the main playlist). All methods are
/// non-blocking: they take the player lock only around the call itself.
NS_SWIFT_UI_ACTOR
@interface MXRPlayerBridge : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// The single event sink (the Swift backend fans events out). Weak.
@property (nonatomic, weak, nullable) id<MXRPlayerEventSink> sink;

// MARK: Cached state (updated on main before each sink call)
@property (nonatomic, readonly) MXRPlayerState state;
/// Title of the current media (meta title or file name); nil when nothing is loaded.
@property (nonatomic, readonly, copy, nullable) NSString *mediaTitle;
/// URI of the current media; nil when nothing is loaded.
@property (nonatomic, readonly, copy, nullable) NSURL *mediaURL;
/// Length in microseconds; -1 when unknown.
@property (nonatomic, readonly) int64_t length;
/// The latest clock sample. `time == -1` when nothing has played yet.
@property (nonatomic, readonly) MXRTimerPoint timerPoint;
/// Increments for every engine seek, even when playback remains playing.
@property (nonatomic, readonly) uint64_t seekGeneration;
/// Cached title flags; reading this never acquires the engine player lock.
@property (nonatomic, readonly) BOOL interactiveVideo;
@property (nonatomic, readonly) BOOL canPause;
@property (nonatomic, readonly) BOOL canSeek;
/// Whether the engine currently wants fullscreen (`vlc_player_vout_IsFullscreen`).
@property (nonatomic, readonly, getter=isFullscreen) BOOL fullscreen;
/// True while a media is playing or paused.
@property (nonatomic, readonly, getter=isActive) BOOL active;

// MARK: Commands
/// Resumes when paused; starts the playlist when stopped.
- (void)play;
- (void)pause;
- (void)togglePlayPause;
/// Stops playback (asynchronous in the engine).
- (void)stop;
/// Seeks to an absolute time in microseconds. `precise` = NO is a fast (keyframe) seek.
- (void)seekToTime:(int64_t)time precise:(BOOL)precise NS_SWIFT_NAME(seek(toTime:precise:));
/// Relative seek in microseconds.
- (void)jumpBy:(int64_t)offset NS_SWIFT_NAME(jump(by:));
/// Asks every video output to enter or leave fullscreen (`vlc_player_vout_SetFullscreen`).
- (void)setFullscreen:(BOOL)fullscreen NS_SWIFT_NAME(setFullscreen(_:));
- (void)toggleFullscreen;

@end

NS_ASSUME_NONNULL_END
