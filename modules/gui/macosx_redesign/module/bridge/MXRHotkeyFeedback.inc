/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later.
 *
 * Hotkey feedback for the redesign OSD (D027, review findings MISS-01, ENG-M1, BB-06, R8).
 *
 * The engine OSD is switched off for this interface (the bridge sets "osd" = false on the
 * player, which every vout inherits). The text VLC would have drawn into the video for a
 * hotkey action (src/player/osd.c, src/player/vout.c, modules/control/hotkeys.c) is rebuilt
 * here, with VLC's own translated strings, and shown by the redesign's two-line OSD next to
 * "Pressed <key>". Included only by MXRServicesBridge.m.
 *
 * The key-action variable callback of the hotkeys module runs synchronously, so values the
 * action stores synchronously (volume, rate variable, delays, vout variables, playlist modes)
 * are read right after the trigger. Values the input thread applies later (track and
 * program selection, rate) are resolved from the matching player callback instead
 * (MXRFeedbackAwait*). Nothing here runs on a hot path: only on an explicit hotkey.
 */

/// The part of the player state an action's text depends on, read before the action runs.
typedef struct {
    enum vlc_player_state state;
    bool has_media, can_seek, recording;
    /// The input handles arrows itself (a disc menu title, or a 360° video's viewpoint):
    /// the core's navigation fallback (seek / volume, src/player/input.c) does not run.
    bool navigates;
    bool fullscreen;
    vlc_tick_t time, length, subtitle_delay;
    size_t title_count, chapter_count;
} MXRActionBefore;

/// A result the input thread reports later.
enum { MXRFeedbackAwaitNone = 0, MXRFeedbackAwaitAudio, MXRFeedbackAwaitSubtitle, MXRFeedbackAwaitProgram, MXRFeedbackAwaitRate, MXRFeedbackAwaitVolume,
       /* The target of a jump, reported by the player timer's on_seek (MXRServicesBridge). */
       MXRFeedbackAwaitSeek };

static NSString *FeedbackFormat(const char *format, ...) __attribute__((format(printf, 1, 2)));
static NSString *FeedbackFormat(const char *format, ...)
{
    va_list args;
    va_start(args, format);
    char *text = NULL;
    int length = vasprintf(&text, format, args);
    va_end(args);
    if (length < 0)
        return nil;
    NSString *result = [NSString stringWithUTF8String:text];
    free(text);
    return result;
}

static MXRActionBefore MXRCaptureActionBefore(vlc_player_t *player)
{
    MXRActionBefore before = { .time = VLC_TICK_INVALID, .length = VLC_TICK_INVALID };
    vlc_player_Lock(player);
    before.state = vlc_player_GetState(player);
    before.has_media = vlc_player_GetCurrentMedia(player) != NULL;
    before.can_seek = vlc_player_CanSeek(player);
    before.recording = vlc_player_IsRecording(player);
    before.fullscreen = vlc_player_vout_IsFullscreen(player);
    before.time = vlc_player_GetTime(player);
    before.length = vlc_player_GetLength(player);
    before.subtitle_delay = vlc_player_GetSubtitleDelay(player);
    vlc_player_title_list *titles = vlc_player_GetTitleList(player);
    before.title_count = titles ? vlc_player_title_list_GetCount(titles) : 0;
    const struct vlc_player_title *title = vlc_player_GetSelectedTitle(player);
    before.chapter_count = title ? title->chapter_count : 0;
    before.navigates = title && (title->flags & VLC_PLAYER_TITLE_MENU) != 0;
    vlc_player_Unlock(player);
    if (before.has_media && !before.navigates) {
        size_t count = 0;
        vout_thread_t **vouts = vlc_player_vout_HoldAll(player, &count);
        for (size_t i = 0; i < count; i++) {
            if (var_GetBool(vouts[i], "viewpoint-changeable")) before.navigates = true;
            vout_Release(vouts[i]);
        }
        free(vouts);
    }
    return before;
}

/// "00:12:34 / 00:25:40", as vlc_player_osd_Position draws it.
static NSString *FeedbackPosition(vlc_tick_t time, vlc_tick_t length)
{
    if (time == VLC_TICK_INVALID)
        return nil;
    char time_text[MSTRTIME_MAX_SIZE], length_text[MSTRTIME_MAX_SIZE];
    vlc_tick_to_str(time_text, time - VLC_TICK_0);
    if (length == VLC_TICK_INVALID || length <= 0)
        return FeedbackFormat("%s", time_text);
    vlc_tick_to_str(length_text, length);
    return FeedbackFormat("%s / %s", time_text, length_text);
}

/// The choice text of a vout variable ("2.35:1"), like vout_osd_PrintVariableText.
static NSString *FeedbackVoutChoice(vout_thread_t *vout, const char *name, int type)
{
    vlc_value_t value;
    if (var_Get(vout, name, &value) != VLC_SUCCESS)
        return nil;
    size_t count = 0;
    vlc_value_t *choices = NULL;
    char **texts = NULL;
    NSString *result = nil;
    if (var_Change(vout, name, VLC_VAR_GETCHOICES, &count, &choices, &texts) == VLC_SUCCESS) {
        for (size_t i = 0; i < count; i++) {
            bool match = type == VLC_VAR_STRING
                ? strcmp(choices[i].psz_string, value.psz_string) == 0
                : choices[i].f_float == value.f_float;
            if (match && result == nil && texts[i] != NULL)
                result = [NSString stringWithUTF8String:texts[i]];
            if (type == VLC_VAR_STRING)
                free(choices[i].psz_string);
            free(texts[i]);
        }
        free(choices);
        free(texts);
    }
    if (type == VLC_VAR_STRING)
        free(value.psz_string);
    return result;
}

static const char *FeedbackCategoryName(enum es_format_category_e category)
{
    switch (category) {
        case AUDIO_ES: return vlc_gettext("Audio");
        case SPU_ES: return vlc_gettext("Subtitle");
        case VIDEO_ES: return vlc_gettext("Video");
        default: return "";
    }
}

/// "Subtitle track: English", or "Subtitle track: Disabled" (vlc_player_osd_Tracks).
static NSString *FeedbackSelectedTracks(vlc_player_t *player, enum es_format_category_e category)
{
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    vlc_player_Lock(player);
    for (size_t i = 0; i < vlc_player_GetTrackCount(player, category); i++) {
        const struct vlc_player_track *track = vlc_player_GetTrackAt(player, category, i);
        if (track->selected && track->name)
            [names addObject:[NSString stringWithUTF8String:track->name] ?: @""];
    }
    vlc_player_Unlock(player);
    const char *kind = FeedbackCategoryName(category);
    if (names.count == 0)
        return FeedbackFormat(vlc_gettext("%s track: %s"), kind, vlc_gettext("Disabled"));
    NSString *joined = [names componentsJoinedByString:@", "];
    return FeedbackFormat(names.count == 1 ? vlc_gettext("%s track: %s") : vlc_gettext("%s tracks: %s"),
                          kind, joined.UTF8String);
}

static NSString *FeedbackRate(vlc_player_t *player)
{
    vlc_player_Lock(player);
    float rate = vlc_player_GetRate(player);
    vlc_player_Unlock(player);
    return FeedbackFormat("Speed: %.2fx", rate);
}

static NSString *FeedbackSelectedProgram(vlc_player_t *player)
{
    NSString *name = nil;
    vlc_player_Lock(player);
    for (size_t i = 0; i < vlc_player_GetProgramCount(player); i++) {
        const struct vlc_player_program *program = vlc_player_GetProgramAt(player, i);
        if (program->selected && program->name)
            name = [NSString stringWithUTF8String:program->name];
    }
    vlc_player_Unlock(player);
    return name ? FeedbackFormat(vlc_gettext("Program Service ID: %s"), name.UTF8String) : nil;
}

static NSString *FeedbackVolume(vlc_player_t *player, bool mute_action)
{
    if (mute_action && vlc_player_aout_IsMuted(player) == 1)
        return [NSString stringWithUTF8String:vlc_gettext("Mute")];
    float volume = vlc_player_aout_GetVolume(player);
    if (volume < 0.f)
        return nil;
    return FeedbackFormat(vlc_gettext("Volume: %ld%%"), lroundf(volume * 100.f));
}

static NSString *FeedbackAudioDevice(vlc_player_t *player)
{
    audio_output_t *aout = vlc_player_aout_Hold(player);
    if (aout == NULL)
        return nil;
    NSString *result = nil;
    char *current = aout_DeviceGet(aout);
    char **ids = NULL, **names = NULL;
    int count = aout_DevicesList(aout, &ids, &names);
    for (int i = 0; i < count; i++) {
        if (current && result == nil && strcmp(ids[i], current) == 0)
            result = FeedbackFormat(vlc_gettext("Audio device: %s"), names[i]);
        free(ids[i]);
        free(names[i]);
    }
    if (count >= 0) {
        free(ids);
        free(names);
    }
    free(current);
    aout_Release(aout);
    return result;
}

/// The vout-variable actions (aspect ratio, crop, zoom, deinterlace, subtitle position).
static NSString *FeedbackVout(vlc_player_t *player, vlc_action_id_t action)
{
    vout_thread_t *vout = vlc_player_vout_Hold(player);
    if (vout == NULL)
        return nil;
    NSString *result = nil;
    NSString *choice;
    switch (action) {
        case ACTIONID_ASPECT_RATIO:
            if ((choice = FeedbackVoutChoice(vout, "aspect-ratio", VLC_VAR_STRING)))
                result = FeedbackFormat(vlc_gettext("Aspect ratio: %s"), choice.UTF8String);
            break;
        case ACTIONID_CROP:
            if ((choice = FeedbackVoutChoice(vout, "crop", VLC_VAR_STRING)))
                result = FeedbackFormat(vlc_gettext("Crop: %s"), choice.UTF8String);
            break;
        case ACTIONID_CROP_TOP: case ACTIONID_UNCROP_TOP:
            result = FeedbackFormat(vlc_gettext("Top crop: %d px"), (int)var_GetInteger(vout, "crop-top"));
            break;
        case ACTIONID_CROP_BOTTOM: case ACTIONID_UNCROP_BOTTOM:
            result = FeedbackFormat(vlc_gettext("Bottom crop: %d px"), (int)var_GetInteger(vout, "crop-bottom"));
            break;
        case ACTIONID_CROP_LEFT: case ACTIONID_UNCROP_LEFT:
            result = FeedbackFormat(vlc_gettext("Left crop: %d px"), (int)var_GetInteger(vout, "crop-left"));
            break;
        case ACTIONID_CROP_RIGHT: case ACTIONID_UNCROP_RIGHT:
            result = FeedbackFormat(vlc_gettext("Right crop: %d px"), (int)var_GetInteger(vout, "crop-right"));
            break;
        case ACTIONID_TOGGLE_AUTOSCALE: {
            float zoom = var_GetFloat(vout, "zoom");
            if (zoom != 1.f)
                result = FeedbackFormat(vlc_gettext("Zoom: x%.2f"), zoom);
            else
                result = [NSString stringWithUTF8String:var_GetBool(vout, "autoscale")
                    ? vlc_gettext("Scaled to screen") : vlc_gettext("Original size")];
            break;
        }
        case ACTIONID_SCALE_UP: case ACTIONID_SCALE_DOWN: case ACTIONID_ZOOM: case ACTIONID_UNZOOM:
        case ACTIONID_ZOOM_QUARTER: case ACTIONID_ZOOM_HALF: case ACTIONID_ZOOM_ORIGINAL: case ACTIONID_ZOOM_DOUBLE: {
            float zoom = var_GetFloat(vout, "zoom");
            if (zoom == 1.f)
                result = [NSString stringWithUTF8String:vlc_gettext("Zooming reset")];
            else if ((choice = FeedbackVoutChoice(vout, "zoom", VLC_VAR_FLOAT)))
                result = FeedbackFormat(vlc_gettext("Zoom mode: %s"), choice.UTF8String);
            else
                result = FeedbackFormat(vlc_gettext("Zoom: x%.2f"), zoom);
            break;
        }
        case ACTIONID_DEINTERLACE: case ACTIONID_DEINTERLACE_MODE: {
            char *mode = var_GetString(vout, "deinterlace-mode");
            result = FeedbackFormat(vlc_gettext("Deinterlace %s (%s)"),
                                    var_GetInteger(vout, "deinterlace") == 1 ? vlc_gettext("On") : vlc_gettext("Off"),
                                    mode ? mode : "");
            free(mode);
            break;
        }
        case ACTIONID_SUBPOS_UP: case ACTIONID_SUBPOS_DOWN:
            result = FeedbackFormat(vlc_gettext("Subtitle position %d px"), (int)MXRSubtitleUserMargin(vout));
            break;
        default:
            break;
    }
    vout_Release(vout);
    return result;
}

/// The OSD line for `action` after it ran, or nil. `*await` names a result that arrives later.
static NSString *MXRHotkeyFeedback(vlc_playlist_t *playlist, vlc_player_t *player,
                                   vlc_action_id_t action, const MXRActionBefore *before,
                                   bool *secondarySubtitleControl, int *await)
{
    *await = MXRFeedbackAwaitNone;
    switch (action) {
        case ACTIONID_PLAY_PAUSE:
            if (before->state == VLC_PLAYER_STATE_PAUSED)
                return [NSString stringWithUTF8String:vlc_gettext("Play")];
            if (before->state == VLC_PLAYER_STATE_PLAYING || before->state == VLC_PLAYER_STATE_STARTED)
                return [NSString stringWithUTF8String:vlc_gettext("Pause")];
            return nil;
        case ACTIONID_PLAY:
            return before->has_media ? [NSString stringWithUTF8String:vlc_gettext("Play")] : nil;
        case ACTIONID_PAUSE:
            return before->has_media ? [NSString stringWithUTF8String:vlc_gettext("Pause")] : nil;
        case ACTIONID_STOP:
            return before->has_media ? [NSString stringWithUTF8String:vlc_gettext("Stop")] : nil;
        case ACTIONID_FRAME_NEXT:
            return before->has_media ? [NSString stringWithUTF8String:vlc_gettext("Next frame")] : nil;
        case ACTIONID_FRAME_PREVIOUS:
            return before->has_media ? [NSString stringWithUTF8String:vlc_gettext("Previous frame")] : nil;

        /* Plain arrows on macOS. Without a menu or viewpoint the core falls back to a
         * short jump (left/right) or a volume step (up/down) on the input thread
         * (vlc_player_input_NavigationFallback), whose OSD text is off with the engine OSD. */
        case ACTIONID_NAV_UP: case ACTIONID_NAV_DOWN:
            if (before->has_media && !before->navigates)
                *await = MXRFeedbackAwaitVolume;
            return nil;
        case ACTIONID_NAV_LEFT: case ACTIONID_NAV_RIGHT:
            if (!before->has_media || before->navigates)
                return nil;
            /* fall through: the core jumps by "short-jump-size" */
        case ACTIONID_JUMP_BACKWARD_EXTRASHORT: case ACTIONID_JUMP_FORWARD_EXTRASHORT:
        case ACTIONID_JUMP_BACKWARD_SHORT: case ACTIONID_JUMP_FORWARD_SHORT:
        case ACTIONID_JUMP_BACKWARD_MEDIUM: case ACTIONID_JUMP_FORWARD_MEDIUM:
        case ACTIONID_JUMP_BACKWARD_LONG: case ACTIONID_JUMP_FORWARD_LONG:
            /* The text is the time the core seeks to, as vlc_player_input_SeekByTime prints it.
             * It is not predictable from here: the core adds the jump to the target of a seek
             * still in flight (vlc_player_input_GetTime(seeking=true)), which vlc_player_GetTime
             * does not report, and an arrow's jump runs later on the input thread. Repeated
             * presses showed the time one jump behind the seek bar (live run 1, "00:48" vs 00:38). */
            if (before->can_seek && before->time != VLC_TICK_INVALID)
                *await = MXRFeedbackAwaitSeek;
            return nil;
        case ACTIONID_POSITION:
            return before->has_media ? FeedbackPosition(before->time, before->length) : nil;

        case ACTIONID_VOL_UP: case ACTIONID_VOL_DOWN:
            return FeedbackVolume(player, false);
        case ACTIONID_VOL_MUTE:
            return FeedbackVolume(player, true);
        case ACTIONID_AUDIODEVICE_CYCLE:
            return FeedbackAudioDevice(player);

        case ACTIONID_RATE_NORMAL: case ACTIONID_RATE_SLOWER: case ACTIONID_RATE_FASTER:
        case ACTIONID_RATE_SLOWER_FINE: case ACTIONID_RATE_FASTER_FINE:
            /* vlc_player_GetRate() follows once the input thread applied the new rate. */
            if (before->has_media)
                *await = MXRFeedbackAwaitRate;
            return nil;

        case ACTIONID_AUDIODELAY_UP: case ACTIONID_AUDIODELAY_DOWN:
        case ACTIONID_SUBDELAY_UP: case ACTIONID_SUBDELAY_DOWN: {
            if (!before->has_media)
                return nil;
            bool audio = action == ACTIONID_AUDIODELAY_UP || action == ACTIONID_AUDIODELAY_DOWN;
            vlc_player_Lock(player);
            vlc_tick_t delay = audio ? vlc_player_GetAudioDelay(player) : vlc_player_GetSubtitleDelay(player);
            vlc_player_Unlock(player);
            return FeedbackFormat(vlc_gettext("%s delay: %i ms"), FeedbackCategoryName(audio ? AUDIO_ES : SPU_ES),
                                  (int)MS_FROM_VLC_TICK(delay));
        }

        case ACTIONID_AUDIO_TRACK:
            if (before->has_media)
                *await = MXRFeedbackAwaitAudio;
            return nil;
        case ACTIONID_SUBTITLE_TRACK: case ACTIONID_SUBTITLE_REVERSE_TRACK: case ACTIONID_SUBTITLE_TOGGLE:
            if (before->has_media)
                *await = MXRFeedbackAwaitSubtitle;
            return nil;
        case ACTIONID_PROGRAM_SID_NEXT: case ACTIONID_PROGRAM_SID_PREV:
            if (before->has_media)
                *await = MXRFeedbackAwaitProgram;
            return nil;
        case ACTIONID_SUBTITLE_CONTROL_SECONDARY:
            *secondarySubtitleControl = !*secondarySubtitleControl;
            return FeedbackFormat(vlc_gettext("%s subtitle control"), *secondarySubtitleControl ? "Secondary" : "Primary");

        case ACTIONID_TITLE_NEXT:
            return before->title_count > 1 ? [NSString stringWithUTF8String:vlc_gettext("Next title")] : nil;
        case ACTIONID_TITLE_PREV:
            return before->title_count > 1 ? [NSString stringWithUTF8String:vlc_gettext("Previous title")] : nil;
        case ACTIONID_CHAPTER_NEXT:
            return before->chapter_count > 1 ? [NSString stringWithUTF8String:vlc_gettext("Next chapter")] : nil;
        case ACTIONID_CHAPTER_PREV:
            return before->chapter_count > 1 ? [NSString stringWithUTF8String:vlc_gettext("Previous chapter")] : nil;

        case ACTIONID_RECORD:
            if (!before->has_media)
                return nil;
            return [NSString stringWithUTF8String:before->recording ? vlc_gettext("Recording done") : vlc_gettext("Recording")];

        case ACTIONID_LOOP: {
            vlc_playlist_Lock(playlist);
            enum vlc_playlist_playback_repeat repeat = vlc_playlist_GetPlaybackRepeat(playlist);
            vlc_playlist_Unlock(playlist);
            return repeat == VLC_PLAYLIST_PLAYBACK_REPEAT_ALL ? @"Repeat: All"
                 : repeat == VLC_PLAYLIST_PLAYBACK_REPEAT_CURRENT ? @"Repeat: One" : @"Repeat: Off";
        }
        case ACTIONID_RANDOM: {
            vlc_playlist_Lock(playlist);
            enum vlc_playlist_playback_order order = vlc_playlist_GetPlaybackOrder(playlist);
            vlc_playlist_Unlock(playlist);
            return order == VLC_PLAYLIST_PLAYBACK_ORDER_RANDOM ? @"Shuffle: On" : @"Shuffle: Off";
        }

        case ACTIONID_SUBTITLE_TEXT_SCALE_NORMAL: case ACTIONID_SUBTITLE_TEXT_SCALE_UP: case ACTIONID_SUBTITLE_TEXT_SCALE_DOWN: {
            vlc_player_Lock(player);
            unsigned scale = vlc_player_GetSubtitleTextScale(player);
            vlc_player_Unlock(player);
            return FeedbackFormat(vlc_gettext("Subtitle text scale %d%%"), (int)scale);
        }

        case ACTIONID_SUBSYNC_MARKAUDIO:
            return [NSString stringWithUTF8String:vlc_gettext("Sub sync: bookmarked audio time")];
        case ACTIONID_SUBSYNC_MARKSUB:
            return [NSString stringWithUTF8String:vlc_gettext("Sub sync: bookmarked subtitle time")];
        case ACTIONID_SUBSYNC_RESET:
            return [NSString stringWithUTF8String:vlc_gettext("Sub sync: delay reset")];
        case ACTIONID_SUBSYNC_APPLY: {
            vlc_player_Lock(player);
            vlc_tick_t delay = vlc_player_GetSubtitleDelay(player);
            vlc_player_Unlock(player);
            if (delay == before->subtitle_delay)
                return [NSString stringWithUTF8String:vlc_gettext("Sub sync: set bookmarks first!")];
            return FeedbackFormat(vlc_gettext("Sub sync: corrected %"PRId64" ms (total delay = %"PRId64" ms)"),
                                  MS_FROM_VLC_TICK(delay - before->subtitle_delay), MS_FROM_VLC_TICK(delay));
        }

        case ACTIONID_ASPECT_RATIO: case ACTIONID_CROP:
        case ACTIONID_CROP_TOP: case ACTIONID_UNCROP_TOP: case ACTIONID_CROP_BOTTOM: case ACTIONID_UNCROP_BOTTOM:
        case ACTIONID_CROP_LEFT: case ACTIONID_UNCROP_LEFT: case ACTIONID_CROP_RIGHT: case ACTIONID_UNCROP_RIGHT:
        case ACTIONID_TOGGLE_AUTOSCALE: case ACTIONID_SCALE_UP: case ACTIONID_SCALE_DOWN:
        case ACTIONID_ZOOM: case ACTIONID_UNZOOM: case ACTIONID_ZOOM_QUARTER: case ACTIONID_ZOOM_HALF:
        case ACTIONID_ZOOM_ORIGINAL: case ACTIONID_ZOOM_DOUBLE:
        case ACTIONID_DEINTERLACE: case ACTIONID_DEINTERLACE_MODE:
        case ACTIONID_SUBPOS_UP: case ACTIONID_SUBPOS_DOWN:
            return before->has_media ? FeedbackVout(player, action) : nil;

        case ACTIONID_TOGGLE_FULLSCREEN: case ACTIONID_LEAVE_FULLSCREEN: {
            /* VLC draws no text for these; its own hotkey names say what happened (D027: the
             * action, then "Pressed <key>"). The core sets the player's fullscreen synchronously
             * (vlc_player_vout_SetFullscreen); Esc out of a window changes nothing. */
            bool fullscreen = vlc_player_vout_IsFullscreen(player);
            if (fullscreen == before->fullscreen)
                return nil;
            return [NSString stringWithUTF8String:vlc_gettext(fullscreen ? "Fullscreen" : "Exit fullscreen")];
        }

        default:
            /* Navigation, quit, bookmarks, viewpoint...: the result is visible by itself; the
             * OSD shows only the pressed key. A snapshot reports its file from the
             * "snapshot-file" variable once it is written. */
            return nil;
    }
}
