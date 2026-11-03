/*****************************************************************************
 * MXRUpdateDeferral.h: a background update check skipped during video runs later
 *****************************************************************************
 * Copyright (C) 2026 VLC Redesign contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *****************************************************************************/

/*
 * No engine or Sparkle types, so tools/test-updater-deferral.py tests it on its own. Main thread
 * only (MXRUpdaterBridge.m): Sparkle asks its delegate there and the bridge hops player events there.
 */

#ifndef MXR_UPDATE_DEFERRAL_H
#define MXR_UPDATE_DEFERRAL_H

#include <stdbool.h>

/// Seconds playback must stay stopped before the remembered check runs, so a stop between two
/// items or a quick restart never puts an update window over the next video.
#define MXR_UPDATE_DEFERRAL_SETTLE_SECONDS 10.0

typedef struct {
    /// A background check was refused while a video played and has not run since.
    bool pending;
} MXRUpdateDeferral;

/// Sparkle asks before every check. A background check is refused while a video plays and is
/// remembered; any check that runs (also the remembered one, or one the user asked for) clears it.
static inline bool MXRUpdateDeferralMayCheck(MXRUpdateDeferral *deferral, bool background, bool playingVideo)
{
    if (background && playingVideo) {
        deferral->pending = true;
        return false;
    }
    deferral->pending = false;
    return true;
}

/// Playback stopped and stayed stopped: true, once, when the remembered check should run now.
/// Nothing runs while a video plays (the check stays remembered) or after the user turned
/// automatic checks off (it is dropped).
static inline bool MXRUpdateDeferralTakeWhenIdle(MXRUpdateDeferral *deferral, bool playingVideo, bool automaticChecks)
{
    if (!deferral->pending || playingVideo)
        return false;
    deferral->pending = false;
    return automaticChecks;
}

#endif
