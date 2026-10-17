/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later.
 *
 * Library contract against a real media library (L04). The Swift side holds MockLibrary to the same
 * rules in Tests/MXRCoreTests/MockLibraryContractTests.swift; this harness holds the bridge to them:
 * category roots and their "+" rows, folder hierarchy and multi-level breadcrumbs, the Music split,
 * Home sections with destinations, watched progress, m3u expansion and the thumbnail notification.
 *
 * Build and run: tools/native-tests.py --engine-build <build> --suite library, or
 * make check-macosx-redesign-library (needs ffmpeg and python3; user data and media
 * live in a temporary directory, the user's own VLC library is never touched).
 */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#import <Cocoa/Cocoa.h>
#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_media_library.h>
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
static void Video(NSString *path,NSString *title) {
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    Run(@[@"ffmpeg",@"-y",@"-f",@"lavfi",@"-i",@"testsrc=size=320x180:rate=10:duration=4",@"-f",@"lavfi",@"-i",@"sine=frequency=440:duration=4",
          @"-metadata",[@"title=" stringByAppendingString:title],@"-pix_fmt",@"yuv420p",@"-c:v",@"libx264",@"-c:a",@"aac",@"-shortest",path]);
}
static void Song(NSString *path,NSString *title,NSString *artist,NSString *album,NSString *genre,int track) {
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    Run(@[@"ffmpeg",@"-y",@"-f",@"lavfi",@"-i",@"sine=frequency=330:duration=3",@"-metadata",[@"title=" stringByAppendingString:title],
          @"-metadata",[@"artist=" stringByAppendingString:artist],@"-metadata",[@"album=" stringByAppendingString:album],
          @"-metadata",[@"genre=" stringByAppendingString:genre],@"-metadata",[NSString stringWithFormat:@"track=%d",track],@"-c:a",@"libmp3lame",path]);
}

static NSDictionary *Request(MXRLibraryServices *service,NSString *name,NSDictionary *args,NSError **error) {
    __block NSDictionary *result=nil; __block NSError *failure=nil; __block BOOL done=NO;
    [service request:name arguments:args completion:^(NSDictionary *r,NSError *e){ result=r; failure=e; done=YES; }];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:60];
    while(!done&&[deadline timeIntervalSinceNow]>0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    if(error) *error=failure; return result;
}
static NSDictionary *Page(MXRLibraryServices *s,NSDictionary *location) {
    return Request(s,@"page",@{@"location":location,@"query":@{@"sort":@"titleAscending",@"searchText":@"",@"offset":@0,@"limit":@1000}},nil)?:@{};
}
static NSArray *Titles(NSArray *entries) {
    NSMutableArray *t=[NSMutableArray array];
    for(NSDictionary *e in entries) [t addObject:e[@"name"]?:e[@"title"]?:e[@"media"][@"title"]?:@"?"];
    return t;
}
static void Wait(BOOL (^condition)(void),NSTimeInterval seconds) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:seconds];
    while(!condition()&&[deadline timeIntervalSinceNow]>0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
}

int main(void) {
    @autoreleasepool {
        NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"mxr-library-contract-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        NSString *user=[root stringByAppendingPathComponent:@"user"],*media=[root stringByAppendingPathComponent:@"media"];
        [NSFileManager.defaultManager createDirectoryAtPath:user withIntermediateDirectories:YES attributes:nil error:nil];
        setenv("VLC_USERDATA_PATH",user.UTF8String,1);
        Video([media stringByAppendingPathComponent:@"Videos/Show/S01/Show S01E01.mp4"],@"Show S01E01");
        Video([media stringByAppendingPathComponent:@"Videos/Show/S01/Show S01E02.mp4"],@"Show S01E02");
        Video([media stringByAppendingPathComponent:@"Videos/Show/S02/Show S02E01.mp4"],@"Show S02E01");
        Video([media stringByAppendingPathComponent:@"Videos/Clip.mp4"],@"Clip");
        Song([media stringByAppendingPathComponent:@"Music/One/01.mp3"],@"Opening",@"The Band",@"First Album",@"Rock",1);
        Song([media stringByAppendingPathComponent:@"Music/One/02.mp3"],@"Second Song",@"The Band",@"First Album",@"Rock",2);
        Song([media stringByAppendingPathComponent:@"Music/Two/01.mp3"],@"Quiet",@"Solo Artist",@"Alone",@"Folk",1);

        CHECK([NSFileManager.defaultManager fileExistsAtPath:[media stringByAppendingPathComponent:@"Music/Two/01.mp3"]],@"fixture media generated (ffmpeg)");
        libvlc_int_t *instance=libvlc_InternalCreate(); CHECK(instance!=NULL,@"libvlc create");
        NSString *config=[root stringByAppendingPathComponent:@"vlcrc"];
        NSString *configArg=[@"--config=" stringByAppendingString:config];
        const char *options[]={"library-contract","--ignore-config","--no-video","--aout=dummy","--no-plugins-cache","--media-library",configArg.UTF8String};
        CHECK(libvlc_InternalInit(instance,7,options)==VLC_SUCCESS,@"libvlc init");
        intf_thread_t *intf=vlc_object_create(VLC_OBJECT(instance),sizeof(*intf));
        MXRLibraryServices *library=[[MXRLibraryServices alloc] initWithInterface:intf];
        CHECK(library.available,@"media library is available");
        if(!library.available) return 1;
        __block NSMutableArray *changes=[NSMutableArray array];
        __weak MXRLibraryServices *weakLibrary=library;
        library.serviceChanged=^(NSString *service){ (void)service; NSDictionary *s=[weakLibrary snapshot]; if(s) [changes addObject:[s copy]]; };

        /* Roots before any folder: only the "+" rows. */
        NSDictionary *videos=Page(library,@{@"kind":@"videos"});
        CHECK([videos[@"addAction"] isEqual:@"add"]&&[videos[@"entries"] count]==0,@"empty Videos offers + Add only");

        for(NSString *folder in @[@"Videos",@"Music"]) {
            NSURL *url=[NSURL fileURLWithPath:[media stringByAppendingPathComponent:folder] isDirectory:YES];
            NSError *error=nil; Request(library,@"addFolder",@{@"url":url.absoluteString},&error);
            CHECK(error==nil,@"add folder %@ (%@)",folder,error.localizedDescription?:@"ok");
        }
        /* Indexing is asynchronous: wait until all 7 files are in. */
        Wait(^BOOL{ return [library.snapshot[@"mediaCount"] integerValue]>=7; },90);
        CHECK([library.snapshot[@"mediaCount"] integerValue]==7,@"7 media indexed (got %@)",library.snapshot[@"mediaCount"]);

        videos=Page(library,@{@"kind":@"videos"});
        CHECK([Titles(videos[@"entries"]) isEqual:(@[@"Videos"])]&&[videos[@"entries"][0][@"isEntryPoint"] boolValue],@"Videos lists the video entry point: %@",Titles(videos[@"entries"]));
        NSDictionary *videosFolder=[videos[@"entries"] firstObject];
        CHECK([videosFolder[@"itemCount"] integerValue]==2,@"entry point counts its children (Show + Clip = 2): %@",videosFolder[@"itemCount"]);

        NSDictionary *inVideos=Page(library,@{@"kind":@"folder",@"id":videosFolder[@"id"]?:@""});
        NSArray *types=[inVideos[@"entries"] valueForKey:@"type"];
        CHECK([types isEqual:(@[@"folder",@"media"])],@"subfolders first, then media: %@",types);
        CHECK([inVideos[@"addAction"] isEqual:@"add"],@"a folder of folders offers + Add");
        NSDictionary *show=[inVideos[@"entries"] firstObject];
        NSDictionary *inShow=Page(library,@{@"kind":@"folder",@"id":show[@"id"]?:@""});
        CHECK([Titles(inShow[@"entries"]) isEqual:(@[@"S01",@"S02"])],@"Show contains S01 and S02: %@",Titles(inShow[@"entries"]));
        NSDictionary *s01=[inShow[@"entries"] firstObject];
        CHECK([s01[@"itemCount"] integerValue]==2,@"S01 counts 2 items");
        NSDictionary *inS01=Page(library,@{@"kind":@"folder",@"id":s01[@"id"]?:@""});
        CHECK([inS01[@"totalCount"] integerValue]==2&&[inS01[@"entries"] count]==2,@"S01 lists its 2 files");

        NSDictionary *crumbs=Request(library,@"breadcrumb",@{@"location":@{@"kind":@"folder",@"id":s01[@"id"]?:@""}},nil);
        NSArray *crumbTitles=[crumbs[@"crumbs"] valueForKey:@"title"];
        CHECK([crumbTitles isEqual:(@[@"Videos",@"Videos",@"Show",@"S01"])]||[crumbTitles isEqual:(@[@"Videos",@"Show",@"S01"])],@"multi-level breadcrumb from the category root: %@",crumbTitles);
        CHECK([[crumbs[@"crumbs"][0][@"location"][@"kind"] description] isEqual:@"videos"],@"the first crumb is the category");
        CHECK([[crumbs[@"crumbs"] lastObject][@"location"][@"id"] isEqual:s01[@"id"]],@"the last crumb is the current folder");

        /* Music splits into four destinations. */
        NSDictionary *music=Page(library,@{@"kind":@"music"});
        NSMutableArray *destinations=[NSMutableArray array];
        for(NSDictionary *e in music[@"entries"]) [destinations addObject:e[@"destination"][@"kind"]?:@"?"];
        CHECK([destinations isEqual:(@[@"songs",@"albums",@"artists",@"genres"])],@"Music links Songs/Albums/Artists/Genres: %@",destinations);
        NSDictionary *albums=Page(library,@{@"kind":@"albums"}),*artists=Page(library,@{@"kind":@"artists"}),*genres=Page(library,@{@"kind":@"genres"});
        CHECK([Titles(albums[@"entries"]) isEqual:(@[@"Alone",@"First Album"])],@"albums: %@",Titles(albums[@"entries"]));
        CHECK([Titles(artists[@"entries"]) isEqual:(@[@"Solo Artist",@"The Band"])],@"artists: %@",Titles(artists[@"entries"]));
        CHECK([Titles(genres[@"entries"]) isEqual:(@[@"Folk",@"Rock"])],@"genres: %@",Titles(genres[@"entries"]));
        NSString *firstAlbum=nil; for(NSDictionary *a in albums[@"entries"]) if([a[@"title"] isEqual:@"First Album"]) firstAlbum=a[@"id"];
        NSDictionary *tracks=Page(library,@{@"kind":@"album",@"id":firstAlbum?:@""});
        NSDictionary *track=[[tracks[@"entries"] firstObject] objectForKey:@"media"];
        CHECK([track[@"title"] isEqual:@"Opening"]&&[track[@"artist"] isEqual:@"The Band"]&&[track[@"album"] isEqual:@"First Album"],@"track carries title, artist and album: %@",track);

        /* Watched progress: a watched item has a play count and no partial position. */
        NSString *clipID=nil; for(NSDictionary *e in inVideos[@"entries"]) if(e[@"media"]) clipID=e[@"media"][@"id"];
        NSError *error=nil; Request(library,@"setWatched",@{@"value":@YES,@"mediaIDs":@[clipID?:@""]},&error);
        NSDictionary *clip=Request(library,@"media",@{@"id":clipID?:@""},nil)[@"media"];
        CHECK([clip[@"playCount"] integerValue]>0&&clip[@"progress"]==nil,@"watched = play count, no partial progress: %@",clip);

        /* Home: only non-empty sections, each with the destination its chevron opens. */
        NSDictionary *home=Request(library,@"homeSections",@{},nil);
        for(NSDictionary *section in home[@"sections"])
            CHECK([section[@"entries"] count]>0&&section[@"destination"]!=nil,@"Home section %@ has entries and a destination",section[@"kind"]);

        /* m3u: the playlist file is replaced by its entries. */
        NSString *list=[media stringByAppendingPathComponent:@"list.m3u"];
        [@"#EXTM3U\n#EXTINF:-1,First Stream\nhttp://127.0.0.1:9/one.mp3\n#EXTINF:-1,Second Stream\nhttp://127.0.0.1:9/two.mp3\n" writeToFile:list atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSTask *server=[NSTask new]; server.executableURL=[NSURL fileURLWithPath:@"/usr/bin/env"];
        server.arguments=@[@"python3",@"-m",@"http.server",@"18765",@"--bind",@"127.0.0.1",@"--directory",media];
        server.standardOutput=NSFileHandle.fileHandleWithNullDevice; server.standardError=NSFileHandle.fileHandleWithNullDevice;
        [server launchAndReturnError:nil]; [NSThread sleepForTimeInterval:1];
        NSDictionary *saved=Request(library,@"addNetworkStream",@{@"urls":@[@"http://127.0.0.1:18765/list.m3u"],@"name":@"Radio"},&error);
        [server terminate];
        CHECK([saved[@"stream"][@"itemCount"] integerValue]==2,@"m3u expands into its 2 entries: %@",saved);
        NSDictionary *network=Page(library,@{@"kind":@"network"});
        CHECK([network[@"addAction"] isEqual:@"addNetworkStream"],@"Network offers + Add Network Stream");
        CHECK([Titles(network[@"entries"]) containsObject:@"Podcasts"]&&[Titles(network[@"entries"]) containsObject:@"Radio"],@"default and saved streams: %@",Titles(network[@"entries"]));

        /* Playlists: + Create playlist. */
        NSDictionary *created=Request(library,@"createPlaylist",@{@"name":@"Mix",@"mediaIDs":@[clipID?:@""]},&error);
        NSDictionary *playlists=Page(library,@{@"kind":@"playlists"});
        CHECK([playlists[@"addAction"] isEqual:@"createPlaylist"]&&[Titles(playlists[@"entries"]) containsObject:@"Mix"],@"Playlists offers + Create playlist and lists Mix: %@",Titles(playlists[@"entries"]));
        CHECK([created[@"playlist"][@"id"] length]>0,@"the created playlist is returned");

        /* The media-library thumbnailer persists a frame and names the media. */
        Wait(^BOOL{ for(NSDictionary *s in changes) if([s[@"thumbnails"] count]) return YES; return NO; },60);
        BOOL thumbnail=NO; for(NSDictionary *s in changes) if([s[@"thumbnails"] count]) thumbnail=YES;
        CHECK(thumbnail,@"thumbnail-generated events are published by media id");
        NSDictionary *again=Page(library,@{@"kind":@"folder",@"id":s01[@"id"]?:@""});
        NSDictionary *first=[[again[@"entries"] firstObject] objectForKey:@"media"];
        CHECK([first[@"artworkURL"] length]>0,@"a video in the library carries its persisted thumbnail URL");

        [library shutdown]; [library finishShutdown];
        libvlc_InternalCleanup(instance); libvlc_InternalDestroy(instance);
        [NSFileManager.defaultManager removeItemAtPath:root error:nil];
        fprintf(stderr,Failures?"%d FAILED\n":"all passed\n",Failures);
        return Failures?1:0;
    }
}
