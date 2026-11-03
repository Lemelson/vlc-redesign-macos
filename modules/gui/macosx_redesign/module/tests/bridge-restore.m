/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later.
 * Resume prompt time for external media (A-window verifier open item). A file played from outside
 * every indexed folder is "external" to the media library: it keeps the progress but not the
 * duration, so the bridge takes the time from the player's length. Real engine, real media
 * library, real services bridge. usage: bridge-restore <video of a few seconds or more> */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#import <Cocoa/Cocoa.h>
#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_playlist.h>
#include <vlc_player.h>
#include <vlc_input_item.h>
#include <vlc_configuration.h>
extern libvlc_int_t *libvlc_InternalCreate(void);
extern int libvlc_InternalInit(libvlc_int_t *,int,const char *[]);
extern void libvlc_InternalCleanup(libvlc_int_t *);
extern void libvlc_InternalDestroy(libvlc_int_t *);
#import "MXRBridgeInternal.h"

static void Require(BOOL condition,NSString *message) { if(!condition) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); } }
static BOOL PumpUntil(BOOL (^done)(void),NSTimeInterval seconds) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:seconds];
    while(!done()) { if(deadline.timeIntervalSinceNow<=0) return NO; [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]]; }
    return YES;
}
static enum vlc_player_state State(vlc_player_t *player) { vlc_player_Lock(player); enum vlc_player_state s=vlc_player_GetState(player); vlc_player_Unlock(player); return s; }

int main(int argc,const char **argv) {
    @autoreleasepool {
        Require(argc==2,@"usage: bridge-restore <video>");
        libvlc_int_t *instance=libvlc_InternalCreate(); Require(instance!=NULL,@"libvlc create");
        const char *options[]={"bridge-restore","--ignore-config","--media-library","--vout=dummy","--aout=dummy","--no-metadata-network-access","--restore-playback-pos=1"};
        Require(libvlc_InternalInit(instance,ARRAY_SIZE(options),options)==VLC_SUCCESS,@"libvlc initialization");
        intf_thread_t *intf=vlc_object_create(VLC_OBJECT(instance),sizeof(*intf)); Require(intf!=NULL,@"interface object");
        vlc_playlist_t *playlist=vlc_intf_GetMainPlaylist(intf); vlc_player_t *player=vlc_playlist_GetPlayer(playlist);
        MXRServicesBridge *bridge=[[MXRServicesBridge alloc] initWithPlaylist:playlist interface:intf]; Require(bridge!=nil,@"services init");
        NSString *url=[NSURL fileURLWithPath:@(argv[1])].absoluteString; NSError *error=nil;
        NSDictionary *item=@{@"url":url,@"title":@"External",@"options":@[]};

        /* Play it, stop past half: the media library records the progress of an external file. */
        Require([bridge performCommand:@"playNow" service:@"queue" arguments:@{@"items":@[item],@"index":@0} error:&error],@"play");
        Require(PumpUntil(^BOOL{ return State(player)==VLC_PLAYER_STATE_PLAYING; },10),@"plays");
        __block vlc_tick_t length=VLC_TICK_INVALID;
        Require(PumpUntil(^BOOL{ vlc_player_Lock(player); length=vlc_player_GetLength(player); vlc_player_Unlock(player); return length>0; },10),@"length known");
        /* Pause once the seek has landed: the media library stores the position the input has when it
         * stops, so playback must not run on between reading the time and the stop. */
        vlc_player_Lock(player); vlc_player_SeekByTime(player,length/2,VLC_PLAYER_SEEK_PRECISE,VLC_PLAYER_WHENCE_ABSOLUTE); vlc_player_Unlock(player);
        Require(PumpUntil(^BOOL{ vlc_player_Lock(player); vlc_tick_t t=vlc_player_GetTime(player); vlc_player_Unlock(player); return t!=VLC_TICK_INVALID&&t>=length/2-VLC_TICK_FROM_MS(100); },10),@"the seek lands");
        vlc_player_Lock(player); vlc_player_Pause(player); vlc_player_Unlock(player);
        Require(PumpUntil(^BOOL{ return State(player)==VLC_PLAYER_STATE_PAUSED; },10),@"pauses");
        PumpUntil(^BOOL{ return NO; },0.3);
        vlc_player_Lock(player); vlc_tick_t stoppedAt=vlc_player_GetTime(player); vlc_player_Unlock(player);
        [bridge performCommand:@"stop" service:@"player" arguments:@{} error:NULL];
        Require(PumpUntil(^BOOL{ return State(player)==VLC_PLAYER_STATE_STOPPED; },10),@"stops");
        PumpUntil(^BOOL{ return NO; },1.0);

        /* Play it again: the prompt offers the time it stopped at, from the player's length. */
        Require([bridge performCommand:@"playNow" service:@"queue" arguments:@{@"items":@[item],@"index":@0} error:&error],@"play again");
        __block NSDictionary *prompt=nil;
        BOOL asked=PumpUntil(^BOOL{ prompt=[bridge snapshotForService:@"player"][@"restorePrompt"]; return [prompt[@"time"] longLongValue]>0; },15);
        fprintf(stderr,"restore prompt %s, length %lld us\n",prompt.description.UTF8String,(long long)US_FROM_VLC_TICK(length));
        Require(asked,@"the resume prompt of an external file has a time");
        int64_t expected=US_FROM_VLC_TICK(stoppedAt);
        Require(llabs([prompt[@"time"] longLongValue]-expected)<500000,[NSString stringWithFormat:@"the prompt time is where playback stopped (%@ vs %lld)",prompt[@"time"],(long long)expected]);

        [bridge performCommand:@"stop" service:@"player" arguments:@{} error:NULL];
        PumpUntil(^BOOL{ return State(player)==VLC_PLAYER_STATE_STOPPED; },10);
        puts("PASS: resume prompt time for external media");
        fflush(stdout);
        _exit(0); /* teardown order is bridge-smoke's business */
    }
}
