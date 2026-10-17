/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later.
 *
 * Library audio tracks against the real engine (S30 "Edit Audio Tracks", S31/S29 "Add Audio
 * Tracks", D039). A video is indexed by a real media library; the production request
 * (attachAudioTrack, attachSubtitle) stores an audio file and a subtitle as external files of
 * that media; MXRLibraryExternalTracks reads them back with their kinds; MXRLibraryAddTrackSlaves
 * adds them to a fresh input item the way the queue does; and a real vlc_player then plays the
 * item: the input must expose the soundtrack as a second audio track, selected, and the subtitle
 * as a subtitle track.
 *
 * Build and run: tools/native-tests.py --engine-build <build> --suite library (needs ffmpeg).
 * User data and media live in a temporary directory; the user's own VLC library is never touched.
 */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#import <Cocoa/Cocoa.h>
#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_media_library.h>
#include <vlc_input_item.h>
#include <vlc_player.h>
#include <vlc_es.h>
#import "MXRLibraryServices.h"

extern libvlc_int_t *libvlc_InternalCreate(void);
extern int libvlc_InternalInit(libvlc_int_t *,int,const char *[]);
extern void libvlc_InternalCleanup(libvlc_int_t *);
extern void libvlc_InternalDestroy(libvlc_int_t *);

static int Failures=0;
#define CHECK(cond,...) do { if(!(cond)) { Failures++; fprintf(stderr,"FAIL: %s\n",[NSString stringWithFormat:__VA_ARGS__].UTF8String); } else fprintf(stderr,"ok:   %s\n",[NSString stringWithFormat:__VA_ARGS__].UTF8String); } while(0)

static void Run(NSArray<NSString *> *args) {
    NSTask *task=[NSTask new]; task.executableURL=[NSURL fileURLWithPath:@"/usr/bin/env"]; task.arguments=args;
    task.standardOutput=NSFileHandle.fileHandleWithNullDevice; task.standardError=NSFileHandle.fileHandleWithNullDevice;
    [task launchAndReturnError:nil]; [task waitUntilExit];
}
static NSDictionary *Request(MXRLibraryServices *service,NSString *name,NSDictionary *args,NSError **error) {
    __block NSDictionary *result=nil; __block NSError *failure=nil; __block BOOL done=NO;
    [service request:name arguments:args completion:^(NSDictionary *r,NSError *e){ result=r; failure=e; done=YES; }];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:60];
    while(!done&&[deadline timeIntervalSinceNow]>0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    if(error) *error=failure; return result;
}
static void Wait(BOOL (^condition)(void),NSTimeInterval seconds) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:seconds];
    while(!condition()&&[deadline timeIntervalSinceNow]>0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
}

/* Audio tracks of the playing input: count, and the sample rate of the selected one. */
static size_t AudioTracks(vlc_player_t *player,unsigned *selectedRate,size_t *subtitles) {
    vlc_player_Lock(player);
    size_t count=vlc_player_GetTrackCount(player,AUDIO_ES);
    *selectedRate=0;
    for(size_t i=0;i<count;i++) {
        const struct vlc_player_track *track=vlc_player_GetTrackAt(player,AUDIO_ES,i);
        if(track&&track->selected) *selectedRate=track->fmt.audio.i_rate;
    }
    *subtitles=vlc_player_GetTrackCount(player,SPU_ES);
    vlc_player_Unlock(player);
    return count;
}

int main(void) {
    @autoreleasepool {
        NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"mxr-library-soundtrack-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        NSString *user=[root stringByAppendingPathComponent:@"user"],*videos=[root stringByAppendingPathComponent:@"Videos/Show"],*extras=[root stringByAppendingPathComponent:@"Extras"];
        for(NSString *dir in @[user,videos,extras]) [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        setenv("VLC_USERDATA_PATH",user.UTF8String,1);
        /* The episode's own audio is 44.1 kHz; the commentary is 22.05 kHz, so the selected track says which one plays. */
        NSString *video=[videos stringByAppendingPathComponent:@"Show S01E01.mp4"];
        NSString *audio=[extras stringByAppendingPathComponent:@"Show S01E01 Commentary.m4a"];
        NSString *subtitle=[extras stringByAppendingPathComponent:@"Show S01E01.srt"];
        Run(@[@"ffmpeg",@"-y",@"-f",@"lavfi",@"-i",@"testsrc=size=160x90:rate=10:duration=6",@"-f",@"lavfi",@"-i",@"sine=frequency=440:sample_rate=44100:duration=6",
              @"-pix_fmt",@"yuv420p",@"-c:v",@"libx264",@"-c:a",@"aac",@"-shortest",video]);
        Run(@[@"ffmpeg",@"-y",@"-f",@"lavfi",@"-i",@"sine=frequency=880:sample_rate=22050:duration=6",@"-c:a",@"aac",audio]);
        [@"1\n00:00:00,000 --> 00:00:05,000\nCommentary\n" writeToFile:subtitle atomically:YES encoding:NSUTF8StringEncoding error:nil];
        CHECK([NSFileManager.defaultManager fileExistsAtPath:video]&&[NSFileManager.defaultManager fileExistsAtPath:audio],@"fixture media generated (ffmpeg)");

        libvlc_int_t *instance=libvlc_InternalCreate(); CHECK(instance!=NULL,@"libvlc create");
        NSString *configArg=[@"--config=" stringByAppendingString:[root stringByAppendingPathComponent:@"vlcrc"]];
        const char *options[]={"library-soundtrack","--ignore-config","--no-video","--aout=dummy","--no-plugins-cache","--media-library","--no-sub-autodetect-file",configArg.UTF8String};
        CHECK(libvlc_InternalInit(instance,8,options)==VLC_SUCCESS,@"libvlc init");
        intf_thread_t *intf=vlc_object_create(VLC_OBJECT(instance),sizeof(*intf));
        MXRLibraryServices *library=[[MXRLibraryServices alloc] initWithInterface:intf];
        CHECK(library.available,@"media library is available");
        if(!library.available) return 1;

        NSError *error=nil;
        Request(library,@"addFolder",@{@"url":[NSURL fileURLWithPath:videos isDirectory:YES].absoluteString},&error);
        CHECK(error==nil,@"add the video folder (%@)",error.localizedDescription?:@"ok");
        Wait(^BOOL{ return [library.snapshot[@"mediaCount"] integerValue]>=1; },90);
        NSDictionary *page=Request(library,@"allMedia",@{@"location":@{@"kind":@"videos"},@"sort":@"titleAscending"},nil);
        NSDictionary *media=[page[@"media"] firstObject];
        CHECK([media[@"id"] hasPrefix:@"ml:"],@"the episode is indexed: %@",media[@"id"]);
        NSString *mrl=media[@"url"]?:[NSURL fileURLWithPath:video].absoluteString;

        /* The production requests behind Edit/Add Audio Tracks and Add Subtitles. */
        NSString *audioURL=[NSURL fileURLWithPath:audio].absoluteString,*subtitleURL=[NSURL fileURLWithPath:subtitle].absoluteString;
        Request(library,@"attachAudioTrack",@{@"url":audioURL,@"mediaID":media[@"id"]?:@""},&error);
        CHECK(error==nil,@"attachAudioTrack succeeds (%@)",error.localizedDescription?:@"ok");
        Request(library,@"attachSubtitle",@{@"url":subtitleURL,@"mediaID":media[@"id"]?:@""},&error);
        CHECK(error==nil,@"attachSubtitle succeeds (%@)",error.localizedDescription?:@"ok");
        Request(library,@"attachAudioTrack",@{@"url":@"",@"mediaID":media[@"id"]?:@""},&error);
        CHECK(error!=nil,@"an empty audio URL is refused");

        vlc_medialibrary_t *ml=vlc_ml_instance_get(intf);
        NSArray<NSDictionary *> *tracks=MXRLibraryExternalTracks(ml,mrl.UTF8String);
        NSDictionary *audioTrack=nil,*subtitleTrack=nil;
        for(NSDictionary *track in tracks) { if([track[MXRLibraryTrackAudio] boolValue]) audioTrack=track; else subtitleTrack=track; }
        CHECK(tracks.count==2,@"the library keeps both files for the episode: %@",tracks);
        CHECK([audioTrack[MXRLibraryTrackURL] hasSuffix:@"Commentary.m4a"],@"the audio file is a soundtrack: %@",audioTrack);
        CHECK([subtitleTrack[MXRLibraryTrackURL] hasSuffix:@".srt"],@"the subtitle stays a subtitle: %@",subtitleTrack);

        /* Playback: a fresh item carrying the library's tracks, as the queue builds it. */
        input_item_t *item=input_item_New(mrl.UTF8String,"Show S01E01");
        MXRLibraryAddTrackSlaves(item,tracks);
        vlc_mutex_lock(&item->lock); int slaves=item->i_slaves; vlc_mutex_unlock(&item->lock);
        CHECK(slaves==2,@"the item carries two slaves (got %d)",slaves);
        vlc_player_t *player=vlc_player_New(VLC_OBJECT(intf),VLC_PLAYER_LOCK_NORMAL);
        CHECK(player!=NULL,@"player created");
        vlc_player_Lock(player);
        vlc_player_SetCurrentMedia(player,item);
        CHECK(vlc_player_Start(player)==VLC_SUCCESS,@"playback starts");
        vlc_player_Unlock(player);
        __block unsigned rate=0; __block size_t subtitles=0;
        Wait(^BOOL{ return AudioTracks(player,&rate,&subtitles)>=2&&rate!=0&&subtitles>=1; },20);
        size_t audioCount=AudioTracks(player,&rate,&subtitles);
        CHECK(audioCount==2,@"the input has the episode's audio and the soundtrack (%zu audio tracks)",audioCount);
        CHECK(subtitles==1,@"the attached subtitle is a subtitle track (%zu)",subtitles);
        /* The engine keeps the media's own audio for an equal-priority slave; the bridge selects
         * the attached soundtrack (attachLibrarySubtitles → MXRLibrarySelectSoundtrack). */
        CHECK(rate==44100,@"VLC alone keeps the episode's own audio (selected %u Hz)",rate);
        vlc_player_Lock(player); BOOL selected=MXRLibrarySelectSoundtrack(player,tracks); vlc_player_Unlock(player);
        CHECK(selected,@"the soundtrack is found among the input's audio tracks by its source");
        Wait(^BOOL{ AudioTracks(player,&rate,&subtitles); return rate==22050; },10);
        CHECK(rate==22050,@"the attached soundtrack becomes the selected audio track (selected %u Hz)",rate);
        vlc_player_Lock(player); BOOL none=MXRLibrarySelectSoundtrack(player,@[subtitleTrack?:@{}]); vlc_player_Unlock(player);
        CHECK(!none,@"a subtitle never selects an audio track");
        vlc_player_Lock(player); vlc_player_Stop(player); vlc_player_Unlock(player);
        vlc_player_Delete(player);
        input_item_Release(item);

        [library shutdown]; [library finishShutdown];
        vlc_object_delete(intf);
        libvlc_InternalCleanup(instance); libvlc_InternalDestroy(instance);
        [NSFileManager.defaultManager removeItemAtPath:root error:nil];
        fprintf(stderr,Failures?"%d FAILED\n":"all passed\n",Failures);
        return Failures?1:0;
    }
}
