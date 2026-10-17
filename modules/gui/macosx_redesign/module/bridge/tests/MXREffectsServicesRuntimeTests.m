/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later.
 * Subtitle safe inset against the real engine: a dummy vout carries VLC's own "sub-margin". */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#import <Foundation/Foundation.h>
#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_input_item.h>
#include <vlc_playlist.h>
#include <vlc_player.h>
#include <vlc_vout.h>
#include <vlc_configuration.h>
#include <stdatomic.h>
#include "libvlc_internal.h"
#import "../MXREffectsServices.h"
#import "MXRNativeTestDiagnostics.h"

static void require(BOOL condition, NSString *message)
{
    if (!condition) { NSLog(@"FAIL: %@",message); exit(1); }
}
static void pumpUntil(BOOL (^done)(void), NSString *message)
{
    require(MXRNativeDiagnosticsPumpUntil(done,8,message.UTF8String),message);
}
static atomic_uint StartedVouts, StartedSecondaryVouts;
/* The bridge's vout callback (MXRServicesBridge PlayerVout): a started vout gets the inset. */
static void VoutChanged(vlc_player_t *player, enum vlc_player_vout_action action, vout_thread_t *vout,
                        enum vlc_vout_order order, vlc_es_id_t *es, void *data)
{
    VLC_UNUSED(player); VLC_UNUSED(es);
    if (action != VLC_PLAYER_VOUT_STARTED) return;
    [(__bridge MXREffectsServices *)data applySubtitleSafeInsetToVout:vout order:order];
    atomic_fetch_add(order == VLC_VOUT_ORDER_PRIMARY ? &StartedVouts : &StartedSecondaryVouts,1);
}
/* The player's vouts other than its main one. */
static int64_t secondaryMargin(vlc_player_t *player)
{
    size_t count = 0; vout_thread_t **vouts = vlc_player_vout_HoldAll(player,&count);
    vout_thread_t *main = vlc_player_vout_Hold(player);
    int64_t value = INT64_MIN;
    for (size_t i = 0; i < count; i++) { if (vouts[i] != main) value = var_GetInteger(vouts[i],"sub-margin"); vout_Release(vouts[i]); }
    vout_Release(main); free(vouts);
    return value;
}
static int64_t margin(vlc_player_t *player)
{
    vout_thread_t *vout = vlc_player_vout_Hold(player);
    require(vout != NULL,@"the video has a vout");
    int64_t value = var_GetInteger(vout,"sub-margin"); vout_Release(vout); return value;
}
static void inset(MXREffectsServices *effects, double points, double scale)
{
    NSError *error = nil;
    require([effects performCommand:MXRBridgeCommandSetSubtitleSafeInset arguments:@{@"points":@(points),@"scale":@(scale)} error:&error],
            [NSString stringWithFormat:@"safe inset %g pt @%gx: %@",points,scale,error]);
}

int main(int argc,const char *argv[])
{
    @autoreleasepool {
        require(argc == 2,@"provide a local video fixture");
        const char *options[] = {"MXREffectsServicesRuntimeTests","--ignore-config","--no-media-library","--no-auto-preparse",
            "--no-video-title-show","--aout=adummy","--vout=dummy","--no-osd"};
        libvlc_int_t *vlc = libvlc_InternalCreate();
        require(vlc != NULL && libvlc_InternalInit(vlc,ARRAY_SIZE(options),options) == VLC_SUCCESS,@"real VLC initializes headlessly");
        /* The user's saved Subtitle Offset; the player's vout exists from the player's creation
         * and inherits it. */
        config_PutInt("sub-margin",7);
        intf_thread_t *intf = vlc_object_create(vlc,sizeof(*intf));
        vlc_playlist_t *playlist = vlc_intf_GetMainPlaylist(intf);
        vlc_player_t *player = vlc_playlist_GetPlayer(playlist);
        MXREffectsServices *effects = [[MXREffectsServices alloc] initWithPlayer:player];
        static const struct vlc_player_cbs callbacks = {.on_vout_changed = VoutChanged};
        vlc_player_Lock(player);
        vlc_player_listener_id *listener = vlc_player_AddListener(player,&callbacks,(__bridge void *)effects);
        vlc_player_Unlock(player);
        require(listener != NULL,@"vout listener");

        NSError *error = nil;
        require(![effects performCommand:MXRBridgeCommandSetSubtitleSafeInset arguments:@{@"points":@(-1),@"scale":@2} error:&error] && error,@"a negative inset is rejected");
        require(![effects performCommand:MXRBridgeCommandSetSubtitleSafeInset arguments:@{@"points":@10,@"scale":@0} error:&error] && error,@"a zero backing scale is rejected");
        /* An overlay already shown when the video starts. */
        inset(effects,30,2);
        require(config_GetInt("sub-margin") == 7,@"the inset never becomes the saved Subtitle Offset");

        input_item_t *media = input_item_New([NSURL fileURLWithPath:@(argv[1])].absoluteString.UTF8String,"Safe inset");
        input_item_AddOption(media,"input-repeat=-1",VLC_INPUT_OPTION_TRUSTED);
        vlc_playlist_Lock(playlist);
        require(vlc_playlist_InsertOne(playlist,0,media) == VLC_SUCCESS && vlc_playlist_PlayAt(playlist,0) == VLC_SUCCESS,@"the video plays");
        vlc_playlist_Unlock(playlist);
        pumpUntil(^BOOL { vout_thread_t *vout = vlc_player_vout_Hold(player); if (vout) vout_Release(vout); return vout != NULL; },@"the video's vout starts");
        pumpUntil(^BOOL { return margin(player) == 67; },@"a vout that starts under an overlay raises subtitles by the inset (7 + 60 px)");
        require([[effects snapshot][@"subtitleStyle"][@"offset"] intValue] == 7,@"the snapshot reports the user's offset, not the inset");
        /* The player keeps its vout across inputs (input_resource): starting it again must not
         * add the inset a second time. */
        pumpUntil(^BOOL { return atomic_load(&StartedVouts) >= 1; },@"the vout start is reported");
        unsigned started = atomic_load(&StartedVouts);
        vlc_playlist_Lock(playlist); vlc_playlist_Stop(playlist); vlc_playlist_Unlock(playlist);
        pumpUntil(^BOOL { vlc_player_Lock(player); bool stopped = vlc_player_GetState(player) == VLC_PLAYER_STATE_STOPPED; vlc_player_Unlock(player); return stopped; },@"the video stops");
        vlc_playlist_Lock(playlist); require(vlc_playlist_PlayAt(playlist,0) == VLC_SUCCESS,@"the video plays again"); vlc_playlist_Unlock(playlist);
        pumpUntil(^BOOL { return atomic_load(&StartedVouts) > started; },@"the reused vout starts again");
        require(margin(player) == 67,[NSString stringWithFormat:@"a restarted vout keeps one inset, not two (%lld)",(long long)margin(player)]);

        inset(effects,30,2);
        require(margin(player) == 67,@"the same inset again does not raise twice");
        inset(effects,12.4,2);
        require(margin(player) == 32,@"a lower overlay lowers subtitles (7 + 25 px)");

        /* A subtitle-position hotkey moves the vout's margin itself (modules/control/hotkeys.c). */
        vout_thread_t *vout = vlc_player_vout_Hold(player);
        var_SetInteger(vout,"sub-margin",var_GetInteger(vout,"sub-margin") + 5);
        require(MXRSubtitleUserMargin(vout) == 12,@"the hotkey's change is the user's, without the inset");
        vout_Release(vout);
        inset(effects,0,2);
        require(margin(player) == 12,@"no overlay: subtitles go back to the user's position, hotkey change kept");

        /* Changing the Subtitle Offset while an overlay is shown keeps both. */
        inset(effects,10,1);
        NSMutableDictionary *style = [[effects snapshot][@"subtitleStyle"] mutableCopy];
        style[@"offset"] = @3;
        require([effects performCommand:MXRBridgeCommandSetSubtitleStyle arguments:style error:&error],[NSString stringWithFormat:@"subtitle style: %@",error]);
        require(margin(player) == 13 && config_GetInt("sub-margin") == 3,@"a new offset under an overlay is offset + inset on the vout, offset alone in the config");
        require([[effects snapshot][@"subtitleStyle"][@"offset"] intValue] == 3,@"the snapshot reports the new offset");
        inset(effects,0,1);
        require(margin(player) == 3,@"the overlay hides: subtitles at the new offset");

        /* A second selected video track gets a secondary vout: it is not the main window's
         * picture under the overlays and keeps the user's position. The fixture's video twice,
         * as MJPEG so the track selected later starts on any frame (the media gate requires ffmpeg). */
        vlc_playlist_Lock(playlist); vlc_playlist_Stop(playlist); vlc_playlist_Unlock(playlist);
        pumpUntil(^BOOL { vlc_player_Lock(player); bool stopped = vlc_player_GetState(player) == VLC_PLAYER_STATE_STOPPED; vlc_player_Unlock(player); return stopped; },@"the video stops before the two-track input");
        NSString *twoPath = [[@(argv[1]) stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"two-video-tracks.mkv"];
        NSTask *mux = [NSTask new];
        mux.executableURL = [NSURL fileURLWithPath:@"/usr/bin/env"];
        mux.arguments = @[@"ffmpeg",@"-v",@"error",@"-y",@"-i",@(argv[1]),@"-map",@"0:v",@"-map",@"0:v",@"-map",@"0:a",@"-c:v",@"mjpeg",@"-c:a",@"copy",twoPath];
        require([mux launchAndReturnError:&error],[NSString stringWithFormat:@"ffmpeg: %@",error]);
        [mux waitUntilExit];
        require(mux.terminationStatus == 0,@"ffmpeg muxes the fixture's video twice");
        input_item_t *twoTracks = input_item_New([NSURL fileURLWithPath:twoPath].absoluteString.UTF8String,"Two video tracks");
        input_item_AddOption(twoTracks,"input-repeat=-1",VLC_INPUT_OPTION_TRUSTED);
        vlc_playlist_Lock(playlist);
        require(vlc_playlist_InsertOne(playlist,1,twoTracks) == VLC_SUCCESS && vlc_playlist_PlayAt(playlist,1) == VLC_SUCCESS,@"the two-track input plays");
        vlc_playlist_Unlock(playlist);
        pumpUntil(^BOOL { vlc_player_Lock(player); size_t n = vlc_player_GetVideoTrackCount(player); vlc_player_Unlock(player); return n >= 2; },@"the input has two video tracks");
        vlc_player_Lock(player);
        vlc_es_id_t *both[] = { vlc_player_GetVideoTrackAt(player,0)->es_id, vlc_player_GetVideoTrackAt(player,1)->es_id, NULL };
        vlc_player_SelectEsIdList(player,VIDEO_ES,both);
        vlc_player_Unlock(player);
        pumpUntil(^BOOL { return atomic_load(&StartedSecondaryVouts) >= 1; },@"the second video track starts a secondary vout");
        inset(effects,30,2);
        pumpUntil(^BOOL { return margin(player) == 63; },@"the main vout raises subtitles by the inset (3 + 60 px)");
        require(secondaryMargin(player) == 3,[NSString stringWithFormat:@"a secondary vout keeps the user's offset, not the inset (%lld)",(long long)secondaryMargin(player)]);
        inset(effects,0,2);
        require(margin(player) == 3 && secondaryMargin(player) == 3,@"no overlay: both vouts at the user's offset");
        input_item_Release(twoTracks);

        vlc_player_Lock(player); vlc_player_RemoveListener(player,listener); vlc_player_Unlock(player);
        vlc_playlist_Lock(playlist); vlc_playlist_Stop(playlist); vlc_playlist_Unlock(playlist);
        input_item_Release(media); vlc_object_delete(intf);
        libvlc_InternalCleanup(vlc); libvlc_InternalDestroy(vlc);
        puts("PASS: subtitle safe inset");
    }
    return 0;
}
