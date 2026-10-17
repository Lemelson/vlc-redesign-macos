/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
#import <Foundation/Foundation.h>
#import "MXRBridgeKeys.h"
#include <vlc_common.h>
#include <vlc_player.h>
#include <vlc_vout.h>
NS_ASSUME_NONNULL_BEGIN
@interface MXREffectsServices : NSObject
- (instancetype)initWithPlayer:(vlc_player_t *)player;
- (NSDictionary *)snapshot;
- (BOOL)performCommand:(MXRBridgeCommand)command arguments:(NSDictionary *)arguments error:(NSError **)error;
/// Applies the shared subtitle size (macosx-redesign-sub-size-mode / -sub-pixel-size, or the
/// relative text scale) to the current video. Pixel sizes become VLC's text scale for the
/// video height. Returns YES when the scale changed. Main thread, player unlocked.
- (BOOL)applySubtitleSizePreference;
/// After a successful setSubtitleStyle: the change includes values VLC's text renderer reads
/// only when it is created (font, bold, opacity, outline colour, shadow), so it shows from
/// the next video. They are saved and applied to the current outputs.
@property (nonatomic, readonly) BOOL lastStyleChangeAppliesFromNextVideo;
/// Raises a vout's subtitles by the current safe inset (setSubtitleSafeInset), once: a vout that
/// already carries it is left alone. Only the primary vout is the main window's video under the
/// overlays; a secondary vout (a second selected video track) keeps the user's position. Any
/// thread; the vout must be held (a player vout callback).
- (void)applySubtitleSafeInsetToVout:(vout_thread_t *)vout order:(enum vlc_vout_order)order;
@end
/// A vout's "sub-margin" without the safe inset: the user's Subtitle Offset as moved by hotkeys.
int64_t MXRSubtitleUserMargin(vout_thread_t *vout);
NS_ASSUME_NONNULL_END
