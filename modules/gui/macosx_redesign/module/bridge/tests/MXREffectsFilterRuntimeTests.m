/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later.
 * Live blocker (final5 6-panels): a fast Brightness drag crashed in var_SetChecked ->
 * TriggerFilterCallback on a freed adjust filter. The Essential card enables "adjust" while the
 * picture differs from neutral and removes it at neutral, so a drag through neutral rebuilds the
 * vout's interactive filter chain again and again while the bridge keeps writing values.
 * This harness drives MXREffectsServices exactly like that against the real engine. Freed memory
 * is scribbled (MallocScribble), so a proxy callback left on a freed filter crashes at once. */
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
#include <unistd.h>
#include "libvlc_internal.h"
#import "../MXREffectsServices.h"
#import "MXRNativeTestDiagnostics.h"

static void require(BOOL condition, NSString *message)
{
    if (!condition) { NSLog(@"FAIL: %@",message); exit(1); }
}
static void pumpUntil(BOOL (^done)(void), NSString *message)
{
    require(MXRNativeDiagnosticsPumpUntil(done,10,message.UTF8String),message);
}
static vlc_tick_t playerTime(vlc_player_t *player)
{
    vlc_player_Lock(player); vlc_tick_t time = vlc_player_GetTime(player); vlc_player_Unlock(player);
    return time;
}
/* Lets the vout thread display a few pictures, so a chain change requested by the last write
 * has been applied (the vout rebuilds its filters before the next picture). */
static void letFramesPass(vlc_player_t *player)
{
    vlc_tick_t start = playerTime(player);
    pumpUntil(^BOOL { return playerTime(player) >= start + VLC_TICK_FROM_MS(300); },@"playback keeps running");
}
static void essential(MXREffectsServices *effects, BOOL enabled, double brightness, int cropTop)
{
    NSMutableDictionary *video = [[effects snapshot][@"videoEffects"] mutableCopy];
    NSMutableDictionary *values = [video[@"essential"] mutableCopy];
    values[@"isEnabled"] = @(enabled); values[@"brightness"] = @(brightness);
    video[@"essential"] = values;
    NSMutableDictionary *insets = [video[@"cropInsets"] mutableCopy]; insets[@"top"] = @(cropTop); video[@"cropInsets"] = insets;
    NSError *error = nil;
    require([effects performCommand:MXRBridgeCommandSetVideoEffects arguments:video error:&error],
            [NSString stringWithFormat:@"video effects (adjust %d, brightness %g): %@",enabled,brightness,error]);
}
static double voutBrightness(vlc_player_t *player)
{
    vout_thread_t *vout = vlc_player_vout_Hold(player);
    require(vout != NULL,@"the video has a vout");
    double value = var_Type(vout,"brightness") ? var_GetFloat(vout,"brightness") : NAN;
    vout_Release(vout); return value;
}

int main(int argc,const char *argv[])
{
    /* Scribble freed blocks before the engine allocates anything: a dangling filter pointer
     * then reads 0x55 bytes instead of stale but plausible data. */
    if (!getenv("MallocScribble")) {
        setenv("MallocScribble","1",1);
        execv(argv[0],(char *const *)argv);
        perror("execv"); return 1;
    }
    @autoreleasepool {
        require(argc == 2,@"provide a local video fixture (its folder receives a longer one)");
        /* 30 s, so the drags never reach the end (a looping input restarts its clock). */
        NSString *video = [[@(argv[1]) stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"adjust-drag.mp4"];
        NSTask *encode = [NSTask new]; NSError *taskError = nil;
        encode.executableURL = [NSURL fileURLWithPath:@"/usr/bin/env"];
        encode.arguments = @[@"ffmpeg",@"-v",@"error",@"-y",@"-f",@"lavfi",@"-i",@"testsrc=size=320x180:rate=25:duration=30",@"-c:v",@"libx264",@"-pix_fmt",@"yuv420p",video];
        require([encode launchAndReturnError:&taskError],[NSString stringWithFormat:@"ffmpeg: %@",taskError]);
        [encode waitUntilExit]; require(encode.terminationStatus == 0,@"ffmpeg writes the 30 s fixture");
        const char *options[] = {"MXREffectsFilterRuntimeTests","--ignore-config","--no-media-library","--no-auto-preparse",
            "--no-video-title-show","--aout=adummy","--vout=dummy","--no-osd","--no-sub-autodetect-file"};
        libvlc_int_t *vlc = libvlc_InternalCreate();
        require(vlc != NULL && libvlc_InternalInit(vlc,ARRAY_SIZE(options),options) == VLC_SUCCESS,@"real VLC initializes headlessly");
        intf_thread_t *intf = vlc_object_create(vlc,sizeof(*intf));
        vlc_playlist_t *playlist = vlc_intf_GetMainPlaylist(intf);
        vlc_player_t *player = vlc_playlist_GetPlayer(playlist);
        MXREffectsServices *effects = [[MXREffectsServices alloc] initWithPlayer:player];

        input_item_t *media = input_item_New([NSURL fileURLWithPath:video].absoluteString.UTF8String,"Adjust drag");
        vlc_playlist_Lock(playlist);
        require(vlc_playlist_InsertOne(playlist,0,media) == VLC_SUCCESS && vlc_playlist_PlayAt(playlist,0) == VLC_SUCCESS,@"the video plays");
        vlc_playlist_Unlock(playlist);
        pumpUntil(^BOOL { vout_thread_t *vout = vlc_player_vout_Hold(player); if (vout) vout_Release(vout); return vout != NULL && playerTime(player) > 0; },@"the video's vout starts");
        letFramesPass(player);

        /* 1. One drag away from neutral and back, then away again: the adjust filter is added,
         * removed (freed) and the next value is written to the vout. */
        essential(effects,YES,1.5,0); letFramesPass(player);
        essential(effects,NO,1.0,0); letFramesPass(player);
        essential(effects,YES,1.2,0); letFramesPass(player);
        require(fabs(voutBrightness(player) - 1.2) < 0.001,@"the vout carries the dragged brightness");

        /* 2. A fast drag through neutral, as SwiftUI delivers it (one write per gesture event),
         * once with a non-command filter in the chain too (croppadd: its options restart the chain). */
        for (int pass = 0; pass < 2; pass++) {
            for (int step = 0; step < 240; step++) {
                double brightness = 1.0 + 0.5 * sin(step * 0.21);
                BOOL away = fabs(brightness - 1.0) > 0.02;
                essential(effects,away,away ? brightness : 1.0,pass ? 8 : 0);
                if (step % 6 == 0) usleep(15000);
            }
            letFramesPass(player);
        }
        essential(effects,YES,0.7,0); letFramesPass(player);
        require(fabs(voutBrightness(player) - 0.7) < 0.001,@"the last value wins after the drag");
        NSDictionary *final = [effects snapshot][@"videoEffects"];
        require([final[@"essential"][@"isEnabled"] boolValue] && fabs([final[@"essential"][@"brightness"] doubleValue] - 0.7) < 0.001,
                @"the snapshot reports the adjust filter with the dragged value");
        essential(effects,NO,1.0,0); letFramesPass(player);
        require(![[effects snapshot][@"videoEffects"][@"essential"][@"isEnabled"] boolValue],@"back at neutral the adjust filter is off");

        vlc_playlist_Lock(playlist); vlc_playlist_Stop(playlist); vlc_playlist_Unlock(playlist);
        input_item_Release(media); vlc_object_delete(intf);
        libvlc_InternalCleanup(vlc); libvlc_InternalDestroy(vlc);
        puts("PASS: effects filter writes during a fast drag");
    }
    return 0;
}
