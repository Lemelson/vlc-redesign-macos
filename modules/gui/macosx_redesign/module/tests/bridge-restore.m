/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later.
 * Resume prompt time for external media (A-window verifier open item). A file played from outside
 * every indexed folder is "external" to the media library: it keeps the progress but not the
 * duration, so the bridge takes the time from the player's length. Before that, F2: Convert and
 * Stream (with Play locally on) leave the source's media-library playback state alone; the same
 * probe then sees the main player's playback recorded. Real engine, real media library, real
 * services bridge. usage: bridge-restore <video of a few seconds or more> */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#define MODULE_NAME mxr_bridge_restore
#import <Cocoa/Cocoa.h>
#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_window.h>
#include <vlc_interface.h>
#include <vlc_playlist.h>
#include <vlc_player.h>
#include <vlc_input_item.h>
#include <vlc_configuration.h>
#include <vlc_media_library.h>
#include <sys/socket.h>
#include <netinet/in.h>
extern libvlc_int_t *libvlc_InternalCreate(void);
extern int libvlc_InternalInit(libvlc_int_t *,int,const char *[]);
extern void libvlc_InternalCleanup(libvlc_int_t *);
extern void libvlc_InternalDestroy(libvlc_int_t *);
#import "MXRBridgeInternal.h"
#include "MXRModule.h"

/* The plugin's local display filter for "Play locally while streaming", registered as module.c does
 * (the plugin itself is not loaded here). */
vlc_module_begin()
    set_capability("sout filter", 0)
    add_shortcut(MXR_LOCAL_DISPLAY_MODULE)
    set_callback(MXRLocalDisplayOpen)
vlc_module_end()
VLC_EXPORT const vlc_plugin_cb vlc_static_modules[] = { VLC_SYMBOL(vlc_entry), NULL };

static void Require(BOOL condition,NSString *message) { if(!condition) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); } }
static BOOL PumpUntil(BOOL (^done)(void),NSTimeInterval seconds) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:seconds];
    while(!done()) { if(deadline.timeIntervalSinceNow<=0) return NO; [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]]; }
    return YES;
}
/* The media library's record of `url`: nil when it has none, else its play count and progress. */
static NSDictionary *LibraryState(intf_thread_t *intf,NSString *url) {
    vlc_medialibrary_t *ml=vlc_ml_instance_get(intf); Require(ml!=NULL,@"media library");
    vlc_ml_media_t *media=vlc_ml_get_media_by_mrl(ml,url.UTF8String);
    if(media==NULL) return nil;
    NSDictionary *state=@{@"playcount":@(media->i_playcount),@"progress":@(media->f_progress),@"lastPlayed":@((long long)media->i_last_played_date)};
    vlc_ml_release(media);
    return state;
}
/* Runs one Convert or Stream job through the services bridge to its end. */
static NSDictionary *RunOutputJob(MXRServicesBridge *bridge,NSDictionary *arguments) {
    __block NSDictionary *started=nil; __block NSError *failure=nil; __block BOOL answered=NO;
    [bridge request:@"start" service:@"output" arguments:arguments completion:^(NSDictionary *value,NSError *error){ started=value; failure=error; answered=YES; }];
    Require(PumpUntil(^BOOL{ return answered; },10)&&started!=nil,[NSString stringWithFormat:@"%@ job starts: %@",arguments[@"mode"],failure]);
    __block NSDictionary *job=nil;
    Require(PumpUntil(^BOOL{ job=[[bridge snapshotForService:@"output"][@"jobs"] lastObject];
                              return [@[@"completed",@"failed",@"cancelled"] containsObject:job[@"state"]]; },30),@"output job ends");
    PumpUntil(^BOOL{ return NO; },1.0);
    return job;
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

        /* F2: Convert and Stream jobs run on players parented to the interface, so the engine
         * records no playback state for their source (src/player/medialib.c). */
        Require(LibraryState(intf,url)==nil,@"the media library starts without the source");
        NSString *converted=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"bridge-restore-%@.ts",NSUUID.UUID.UUIDString]];
        NSDictionary *job=RunOutputJob(bridge,@{@"sourceURL":url,@"destinationURL":[NSURL fileURLWithPath:converted].absoluteString,@"profile":@"copy",@"mode":@"convert"});
        [NSFileManager.defaultManager removeItemAtPath:converted error:NULL];
        Require([job[@"state"] isEqual:@"completed"],[NSString stringWithFormat:@"the conversion completes: %@",job]);
        Require(LibraryState(intf,url)==nil,[NSString stringWithFormat:@"a conversion records no playback of its source: %@",LibraryState(intf,url)]);
        int receiver=socket(AF_INET,SOCK_DGRAM,IPPROTO_UDP);
        struct sockaddr_in address={.sin_len=sizeof(address),.sin_family=AF_INET,.sin_port=htons(19098),.sin_addr={.s_addr=htonl(INADDR_LOOPBACK)}};
        Require(receiver>=0&&bind(receiver,(struct sockaddr *)&address,sizeof(address))==0,@"localhost UDP receiver opens");
        config_PutInt("sout-display",1);
        job=RunOutputJob(bridge,@{@"sourceURL":url,@"streamURL":@"udp://127.0.0.1:19098",@"profile":@"copy",@"mode":@"stream"});
        config_PutInt("sout-display",0);
        close(receiver);
        Require([job[@"state"] isEqual:@"completed"],[NSString stringWithFormat:@"the stream played locally completes: %@",job]);
        Require(LibraryState(intf,url)==nil,[NSString stringWithFormat:@"a stream played locally records no playback of its source: %@",LibraryState(intf,url)]);

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
        /* The probe above can see a recorded playback: the main player's is there now. */
        NSDictionary *played=LibraryState(intf,url);
        Require(played!=nil&&[played[@"progress"] doubleValue]>0.1,[NSString stringWithFormat:@"the main player records its playback: %@",played]);

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
