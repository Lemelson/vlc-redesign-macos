/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later.
 * Live minor (final5 6-panels): a Font Size change resized only the next cue; the cue on screen
 * kept its size. VLC renders a text cue to a bitmap once (vout_subpictures.c "last minute text
 * rendering" replaces the text region), so a new sub-text-scale reaches only later cues.
 * The real engine renders here into memory (vmem, subtitles blended in software) and the drawn
 * cue's height is measured before and after each Font Size step, playing, paused and resumed.
 * usage: subtitle-rerender-runtime <work directory> (ffmpeg on PATH) */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#import <Foundation/Foundation.h>
#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_input_item.h>
#include <vlc_playlist.h>
#include <vlc_player.h>
#include <vlc_configuration.h>
#include <os/lock.h>
#include "libvlc_internal.h"
#import "../MXREffectsServices.h"
#import "MXRNativeTestDiagnostics.h"

enum { Width = 640, Height = 360 };
static uint32_t Planes[2][Width * Height];
static uint32_t Shown[Width * Height];
static unsigned long Frames;
static os_unfair_lock FrameLock = OS_UNFAIR_LOCK_INIT;

static void *Lock(void *data, void **plane) { *plane = Planes[(uintptr_t)data & 1]; return NULL; }
static void Unlock(void *data, void *picture, void *const *plane) { VLC_UNUSED(data); VLC_UNUSED(picture); VLC_UNUSED(plane); }
static void Display(void *data, void *picture)
{
    VLC_UNUSED(data); VLC_UNUSED(picture);
    os_unfair_lock_lock(&FrameLock);
    memcpy(Shown,Planes[0],sizeof(Shown)); Frames++;
    os_unfair_lock_unlock(&FrameLock);
}
static void require(BOOL condition, NSString *message)
{
    if (!condition) { NSLog(@"FAIL: %@",message); exit(1); }
}
static void pumpUntil(BOOL (^done)(void), double seconds, NSString *message)
{
    require(MXRNativeDiagnosticsPumpUntil(done,seconds,message.UTF8String),message);
}
static unsigned long frames(void) { os_unfair_lock_lock(&FrameLock); unsigned long n = Frames; os_unfair_lock_unlock(&FrameLock); return n; }
/* Rows of the last shown frame that contain bright (white text) pixels; the video is black. */
static int cueHeight(void)
{
    int top = -1, bottom = -1;
    os_unfair_lock_lock(&FrameLock);
    for (int y = 0; y < Height; y++)
        for (int x = 0; x < Width; x++) {
            uint32_t p = Shown[y * Width + x];
            if (((p >> 16) & 255) > 160 && ((p >> 8) & 255) > 160 && (p & 255) > 160) { if (top < 0) top = y; bottom = y; break; }
        }
    os_unfair_lock_unlock(&FrameLock);
    return top < 0 ? 0 : bottom - top + 1;
}
static void fontSize(MXREffectsServices *effects, int relative)
{
    NSMutableDictionary *style = [[effects snapshot][@"subtitleStyle"] mutableCopy];
    style[@"sizeMode"] = @"relative"; style[@"relativeSize"] = @(relative);
    NSError *error = nil;
    require([effects performCommand:MXRBridgeCommandSetSubtitleStyle arguments:style error:&error],
            [NSString stringWithFormat:@"font size %d: %@",relative,error]);
}
/* The height the cue settles at a moment after a change (a few shown frames). */
static int settledHeight(BOOL paused)
{
    unsigned long start = frames();
    vlc_tick_t until = vlc_tick_now() + VLC_TICK_FROM_MS(paused ? 1200 : 700);
    MXRNativeDiagnosticsPumpUntil(^BOOL { return vlc_tick_now() >= until && (paused || frames() >= start + 5); },5,"frames are shown");
    return cueHeight();
}
static void run(NSString *tool, NSArray *arguments)
{
    NSTask *task = [NSTask new]; NSError *error = nil;
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/env"]; task.arguments = [@[tool] arrayByAddingObjectsFromArray:arguments];
    require([task launchAndReturnError:&error],[NSString stringWithFormat:@"%@: %@",tool,error]);
    [task waitUntilExit]; require(task.terminationStatus == 0,[NSString stringWithFormat:@"%@ succeeds",tool]);
}

int main(int argc,const char *argv[])
{
    @autoreleasepool {
        require(argc == 2,@"provide a work directory");
        NSString *dir = @(argv[1]), *video = [dir stringByAppendingPathComponent:@"rerender.mp4"], *cues = [dir stringByAppendingPathComponent:@"rerender.srt"];
        run(@"ffmpeg",@[@"-v",@"error",@"-y",@"-f",@"lavfi",@"-i",@"color=black:size=640x360:rate=25:duration=30",@"-c:v",@"libx264",@"-pix_fmt",@"yuv420p",video]);
        require([@"1\n00:00:00,300 --> 00:00:29,000\nHHHH HHHH\n\n" writeToFile:cues atomically:YES encoding:NSUTF8StringEncoding error:NULL],@"cue file");

        const char *options[] = {"MXRSubtitleRerenderRuntimeTests","--ignore-config","--no-media-library","--no-auto-preparse",
            "--no-video-title-show","--aout=adummy","--vout=vmem","--vmem-chroma=RV32","--vmem-width=640","--vmem-height=360",
            "--vmem-pitch=2560","--no-osd","--no-sub-autodetect-file","--avcodec-hw=none","--codec=avcodec"};
        libvlc_int_t *vlc = libvlc_InternalCreate();
        require(vlc != NULL,@"real VLC");
        var_Create(vlc,"vmem-lock",VLC_VAR_ADDRESS); var_SetAddress(vlc,"vmem-lock",Lock);
        var_Create(vlc,"vmem-unlock",VLC_VAR_ADDRESS); var_SetAddress(vlc,"vmem-unlock",Unlock);
        var_Create(vlc,"vmem-display",VLC_VAR_ADDRESS); var_SetAddress(vlc,"vmem-display",Display);
        require(libvlc_InternalInit(vlc,ARRAY_SIZE(options),options) == VLC_SUCCESS,@"real VLC initializes headlessly");
        intf_thread_t *intf = vlc_object_create(vlc,sizeof(*intf));
        vlc_playlist_t *playlist = vlc_intf_GetMainPlaylist(intf);
        vlc_player_t *player = vlc_playlist_GetPlayer(playlist);
        MXREffectsServices *effects = [[MXREffectsServices alloc] initWithPlayer:player];

        input_item_t *media = input_item_New([NSURL fileURLWithPath:video].absoluteString.UTF8String,"Rerender");
        input_item_AddOption(media,[@":sub-file=" stringByAppendingString:cues].UTF8String,VLC_INPUT_OPTION_TRUSTED);
        vlc_playlist_Lock(playlist);
        require(vlc_playlist_InsertOne(playlist,0,media) == VLC_SUCCESS && vlc_playlist_PlayAt(playlist,0) == VLC_SUCCESS,@"the video plays");
        vlc_playlist_Unlock(playlist);
        pumpUntil(^BOOL { return cueHeight() > 0; },10,@"the cue is drawn");
        int automatic = settledHeight(NO);
        NSLog(@"cue height at Auto: %d px",automatic);
        require(automatic > 4,@"the cue has a measurable height");

        /* Playing: Larger, then Smaller, each while the same cue stays on screen. */
        fontSize(effects,6);
        int larger = settledHeight(NO);
        NSLog(@"cue height at Larger: %d px",larger);
        require(larger > automatic * 3 / 2,[NSString stringWithFormat:@"the cue on screen grows at once (%d -> %d px)",automatic,larger]);
        fontSize(effects,20);
        int smaller = settledHeight(NO);
        NSLog(@"cue height at Smaller: %d px",smaller);
        require(smaller < automatic,[NSString stringWithFormat:@"the cue on screen shrinks at once (%d -> %d px)",automatic,smaller]);

        /* Paused: the change neither seeks nor resumes (a paused input demuxes only until the video
         * has buffered, so a seek there lost the cue or moved on); the cue on screen is redrawn at
         * the new size as soon as playback resumes (the bridge reports every state change). */
        vlc_player_Lock(player); vlc_player_Pause(player); vlc_player_Unlock(player);
        pumpUntil(^BOOL { vlc_player_Lock(player); bool paused = vlc_player_GetState(player) == VLC_PLAYER_STATE_PAUSED; vlc_player_Unlock(player); return paused; },5,@"pauses");
        [effects playerStateChanged:VLC_PLAYER_STATE_PAUSED];
        settledHeight(YES); /* the paused time settles on the last shown frame */
        vlc_tick_t pausedAt = ({ vlc_player_Lock(player); vlc_tick_t t = vlc_player_GetTime(player); vlc_player_Unlock(player); t; });
        fontSize(effects,6);
        int pausedHeight = settledHeight(YES);
        vlc_player_Lock(player); bool stillPaused = vlc_player_GetState(player) == VLC_PLAYER_STATE_PAUSED; vlc_tick_t pausedNow = vlc_player_GetTime(player); vlc_player_Unlock(player);
        require(stillPaused,@"the change does not resume playback");
        require(pausedNow == pausedAt,[NSString stringWithFormat:@"the change does not move a paused position (%lld -> %lld)",(long long)pausedAt,(long long)pausedNow]);
        require(pausedHeight == smaller,[NSString stringWithFormat:@"the paused picture is left as it was (%d -> %d px)",smaller,pausedHeight]);
        vlc_player_Lock(player); vlc_player_Resume(player); vlc_player_Unlock(player);
        pumpUntil(^BOOL { vlc_player_Lock(player); bool playing = vlc_player_GetState(player) == VLC_PLAYER_STATE_PLAYING; vlc_player_Unlock(player); return playing; },5,@"resumes");
        [effects playerStateChanged:VLC_PLAYER_STATE_PLAYING];
        int resumedLarger = settledHeight(NO);
        NSLog(@"cue height at Larger, after resuming: %d px",resumedLarger);
        require(resumedLarger > smaller * 2,[NSString stringWithFormat:@"a cue resized while paused grows on resume (%d -> %d px)",smaller,resumedLarger]);
        /* A change that keeps the size (another style value) does not touch playback. */
        vlc_player_Lock(player); vlc_player_Pause(player); vlc_player_Unlock(player);
        pumpUntil(^BOOL { vlc_player_Lock(player); bool paused = vlc_player_GetState(player) == VLC_PLAYER_STATE_PAUSED; vlc_player_Unlock(player); return paused; },5,@"pauses again");
        vlc_tick_t before = ({ vlc_player_Lock(player); vlc_tick_t t = vlc_player_GetTime(player); vlc_player_Unlock(player); t; });
        fontSize(effects,6);
        vlc_tick_t after = ({ vlc_player_Lock(player); vlc_tick_t t = vlc_player_GetTime(player); vlc_player_Unlock(player); t; });
        require(before == after,@"an unchanged size does not seek");

        vlc_playlist_Lock(playlist); vlc_playlist_Stop(playlist); vlc_playlist_Unlock(playlist);
        input_item_Release(media); vlc_object_delete(intf);
        libvlc_InternalCleanup(vlc); libvlc_InternalDestroy(vlc);
        puts("PASS: a Font Size change redraws the cue on screen");
    }
    return 0;
}
