/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#import <Foundation/Foundation.h>
#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_playlist.h>
#include <signal.h>
#include <execinfo.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include "libvlc_internal.h"
#import "../MXRMediaServices.h"

static void require(BOOL value, NSString *message)
{
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}
static void traceFailure(int signalNumber)
{
    void *frames[40];
    int count = backtrace(frames, 40);
    backtrace_symbols_fd(frames, count, STDERR_FILENO);
    _Exit(128 + signalNumber);
}
static NSDictionary *waitForOutput(MXRMediaServices *service, NSTimeInterval timeout)
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    NSDictionary *job = nil;
    do {
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
        job = [[service snapshotForService:@"output"][@"jobs"] lastObject];
        if ([@[@"completed", @"failed", @"cancelled"] containsObject:job[@"state"]]) return job;
    } while (deadline.timeIntervalSinceNow > 0);
    return job;
}
/* What ffprobe reads from a produced file: nil when it is not a valid media file (no moov atom). */
static NSDictionary *probe(NSString *path)
{
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/env"];
    task.arguments = @[@"ffprobe", @"-v", @"error", @"-show_entries", @"format=duration:stream=codec_type,duration", @"-of", @"json", path];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![task launchAndReturnError:nil]) return nil;
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    return task.terminationStatus == 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}
static NSArray *streamTypes(NSDictionary *probed)
{
    NSMutableArray *types = [NSMutableArray array];
    for (NSDictionary *stream in probed[@"streams"]) [types addObject:stream[@"codec_type"] ?: @""];
    return [types sortedArrayUsingSelector:@selector(compare:)];
}
static double streamDuration(NSDictionary *probed, NSString *type)
{
    for (NSDictionary *stream in probed[@"streams"]) if ([stream[@"codec_type"] isEqual:type]) return [stream[@"duration"] doubleValue];
    return -1;
}
static BOOL noPartialFiles(NSString *directory)
{
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:nil])
        if ([name hasSuffix:@".vlc-partial"]) return NO;
    return YES;
}
static NSDictionary *startOutput(MXRMediaServices *service, NSDictionary *arguments, NSError **error)
{
    __block BOOL finished = NO;
    __block NSDictionary *result = nil;
    __block NSError *failure = nil;
    [service request:@"start" service:@"output" arguments:arguments completion:^(NSDictionary *value, NSError *requestError) {
        result = value; failure = requestError; finished = YES;
    }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!finished && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    require(finished, @"output request completes");
    *error = failure;
    return result;
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        signal(SIGABRT, traceFailure);
        require(argc == 4, @"pass a local transport-stream fixture, output directory and isolated extension marker");
        NSString *extensionMarker = [NSString stringWithUTF8String:argv[3]];
        require(![NSFileManager.defaultManager fileExistsAtPath:extensionMarker], @"per-run extension marker starts absent");
        const char *options[] = {"MXRMediaServicesRuntimeTests", "--ignore-config", "--no-media-library", "--no-auto-preparse", "--no-video-title-show", "--verbose=0"};
        libvlc_int_t *vlc = libvlc_InternalCreate();
        require(vlc != NULL && libvlc_InternalInit(vlc, 6, options) == VLC_SUCCESS, @"VLC initializes");
        require(var_InheritBool(vlc, "ignore-config"), @"user configuration and config autosave are disabled");
        libvlc_InternalPlay(vlc);
        intf_thread_t *intf = vlc_object_create(vlc, sizeof(*intf));
        vlc_playlist_t *playlist = vlc_intf_GetMainPlaylist(intf);
        require(intf != NULL && playlist != NULL, @"VLC interface and playlist created");
        MXRMediaServices *service = [[MXRMediaServices alloc] initWithPlaylist:playlist interface:intf];
        require([service.capabilities[@"output"] boolValue], @"native output listener registered");
        NSURL *source = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSString *outPath = [[NSString stringWithUTF8String:argv[2]] stringByAppendingPathComponent:@"copy 'quoted', {file} \\ \"video\".ts"];
        [NSFileManager.defaultManager removeItemAtPath:outPath error:nil];
        __block NSError *error = nil;
        __block NSDictionary *result = nil;
        result = startOutput(service, @{@"sourceURL": source.absoluteString,
            @"destinationURL": [NSURL fileURLWithPath:outPath].absoluteString, @"profile": @"copy", @"mode": @"convert"}
            , &error);
        require(result != nil && error == nil, @"output starts using real VLC queue item");
        NSDictionary *job = waitForOutput(service, 20);
        require([job[@"state"] isEqual:@"completed"], [NSString stringWithFormat:@"conversion completes: %@", job]);
        require([[NSFileManager.defaultManager attributesOfItemAtPath:outPath error:nil][NSFileSize] unsignedLongLongValue] > 0,
                @"actual escaped destination contains output bytes");

        NSString *directory = [NSString stringWithUTF8String:argv[2]];
        NSDictionary *sourceProbe = probe(source.path);
        require(streamDuration(sourceProbe, @"video") > 1 && streamDuration(sourceProbe, @"audio") > 1, @"ffprobe reads the source fixture");
        /* D036 (J-01): H.264 transcodes audio and video together, which aborted the process in most
         * runs while transcode forwarded PCR. Repeat it, and check what was written. */
        NSDictionary *expected = @{@"h264": @[@"audio", @"video"], @"audio": @[@"audio"], @"aac": @[@"audio"], @"wav": @[@"audio"]};
        for (NSString *profile in @[@"h264", @"h264", @"h264", @"h264", @"h264", @"audio", @"aac", @"wav"]) {
            NSString *profilePath = [outPath stringByAppendingFormat:@".%@", profile];
            [NSFileManager.defaultManager removeItemAtPath:profilePath error:nil];
            result = startOutput(service, @{@"sourceURL": source.absoluteString,
                @"destinationURL": [NSURL fileURLWithPath:profilePath].absoluteString, @"profile": profile, @"mode": @"convert"}
                , &error);
            require(result != nil && error == nil, @"transcode job starts");
            job = waitForOutput(service, 30);
            require([job[@"state"] isEqual:@"completed"], [NSString stringWithFormat:@"%@ transcode completes: %@", profile, job]);
            NSDictionary *probed = probe(profilePath);
            require(probed != nil, [NSString stringWithFormat:@"%@ output is a readable media file", profile]);
            require([streamTypes(probed) isEqual:expected[profile]],
                    [NSString stringWithFormat:@"%@ output has %@ streams: %@", profile, expected[profile], streamTypes(probed)]);
            for (NSString *type in expected[profile])
                require(fabs(streamDuration(probed, type) - streamDuration(sourceProbe, type)) < 1,
                        [NSString stringWithFormat:@"%@ output %@ lasts as long as the source's: %@", profile, type, probed]);
            require(noPartialFiles(directory), @"a finished job leaves no partial file");
        }

        /* Audio formats keep only the sound, also from a source that carries a subtitle track. */
        NSString *subtitles = [directory stringByAppendingPathComponent:@"subtitles.srt"];
        NSString *subtitled = [directory stringByAppendingPathComponent:@"subtitled.mp4"];
        [@"1\n00:00:00,500 --> 00:00:03,000\nRuntime subtitle\n" writeToFile:subtitles atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSTask *mux = [NSTask new];
        mux.executableURL = [NSURL fileURLWithPath:@"/usr/bin/env"];
        mux.arguments = @[@"ffmpeg", @"-v", @"error", @"-y", @"-i", source.path, @"-i", subtitles, @"-map", @"0", @"-map", @"1",
                          @"-c:v", @"copy", @"-c:a", @"copy", @"-c:s", @"mov_text", subtitled];
        require([mux launchAndReturnError:nil], @"ffmpeg starts");
        [mux waitUntilExit];
        require(mux.terminationStatus == 0 && [streamTypes(probe(subtitled)) containsObject:@"subtitle"], @"subtitled fixture has a subtitle track");
        for (NSString *profile in @[@"audio", @"aac", @"wav"]) {
            NSString *profilePath = [outPath stringByAppendingFormat:@".subtitled.%@", profile];
            [NSFileManager.defaultManager removeItemAtPath:profilePath error:nil];
            result = startOutput(service, @{@"sourceURL": [NSURL fileURLWithPath:subtitled].absoluteString,
                @"destinationURL": [NSURL fileURLWithPath:profilePath].absoluteString, @"profile": profile, @"mode": @"convert"}, &error);
            require(result != nil && error == nil, @"audio job from a subtitled source starts");
            job = waitForOutput(service, 30);
            require([job[@"state"] isEqual:@"completed"], [NSString stringWithFormat:@"%@ from a subtitled source completes: %@", profile, job]);
            require([streamTypes(probe(profilePath)) isEqual:@[@"audio"]],
                    [NSString stringWithFormat:@"%@ output keeps only the sound: %@", profile, streamTypes(probe(profilePath))]);
        }

        /* J-03: an existing file is replaced only when the caller says so. */
        NSString *existing = [outPath stringByAppendingString:@".h264"];
        result = startOutput(service, @{@"sourceURL": source.absoluteString, @"destinationURL": [NSURL fileURLWithPath:existing].absoluteString,
                                        @"profile": @"audio", @"mode": @"convert"}, &error);
        require(result == nil && error.code == EEXIST, @"an existing destination is not replaced without overwrite");

        /* J-05, J-11: Stop reports `stopping` until the engine has closed the output, and a stopped
         * conversion leaves neither the destination nor its partial file. */
        NSString *stoppedPath = [outPath stringByAppendingString:@".stopped.mp4"];
        [NSFileManager.defaultManager removeItemAtPath:stoppedPath error:nil];
        result = startOutput(service, @{@"sourceURL": source.absoluteString, @"destinationURL": [NSURL fileURLWithPath:stoppedPath].absoluteString,
                                        @"profile": @"h264", @"mode": @"convert"}, &error);
        require(result != nil && error == nil, @"conversion to stop starts");
        require([service performCommand:@"stop" service:@"output" arguments:@{@"id": result[@"job"][@"id"]} error:&error],
                @"running conversion can be stopped");
        require([[[service snapshotForService:@"output"][@"jobs"] lastObject][@"state"] isEqual:@"stopping"], @"Stop reports stopping");
        /* Every state published after Stop: the engine's USER stopping event must not turn the
         * stop into `finishing` (which re-enabled the Stop button). */
        NSMutableArray *statesAfterStop = [NSMutableArray array];
        __weak MXRMediaServices *weakService = service;
        service.serviceChanged = ^(NSString *changed) {
            if ([changed isEqual:@"output"])
                [statesAfterStop addObject:[[weakService snapshotForService:@"output"][@"jobs"] lastObject][@"state"] ?: @""];
        };
        job = waitForOutput(service, 20);
        service.serviceChanged = nil;
        require([job[@"state"] isEqual:@"cancelled"], [NSString stringWithFormat:@"stopped conversion reports cancelled: %@", job]);
        require(statesAfterStop.count > 0 && [statesAfterStop.lastObject isEqual:@"cancelled"],
                [NSString stringWithFormat:@"stop publishes its end: %@", statesAfterStop]);
        for (NSString *state in statesAfterStop)
            require([@[@"stopping", @"cancelled"] containsObject:state],
                    [NSString stringWithFormat:@"a stopped job reports only stopping then cancelled: %@", statesAfterStop]);
        require(![NSFileManager.defaultManager fileExistsAtPath:stoppedPath], @"a stopped conversion writes no destination file");
        require(noPartialFiles(directory), @"a stopped conversion removes its partial file");

        int udpSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        struct sockaddr_in udpAddress = {.sin_len = sizeof(udpAddress), .sin_family = AF_INET,
            .sin_port = htons(19099), .sin_addr = {.s_addr = htonl(INADDR_LOOPBACK)}};
        require(udpSocket >= 0 && bind(udpSocket, (struct sockaddr *)&udpAddress, sizeof(udpAddress)) == 0,
                @"localhost UDP receiver opens");
        fcntl(udpSocket, F_SETFL, O_NONBLOCK);
        result = startOutput(service, @{@"sourceURL": source.absoluteString,
            @"streamURL": @"udp://127.0.0.1:19099", @"profile": @"copy", @"mode": @"stream"}
            , &error);
        require(result != nil && error == nil, @"stream starts with real VLC sout");
        unsigned char packet[2048];
        ssize_t received = -1;
        for (int i = 0; i < 20 && received < 0; ++i) {
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
            received = recv(udpSocket, packet, sizeof(packet), 0);
        }
        require(received >= 188 && packet[0] == 0x47, @"VLC actually sends MPEG-TS packets to localhost");
        require([service performCommand:@"stop" service:@"output" arguments:@{@"id": result[@"job"][@"id"]} error:&error],
                @"running stream can be stopped");
        job = waitForOutput(service, 10);
        require([job[@"state"] isEqual:@"cancelled"], [NSString stringWithFormat:@"stop reports cancelled: %@", job]);
        close(udpSocket);

        [NSFileManager.defaultManager removeItemAtPath:[outPath stringByAppendingString:@".missing"] error:nil];
        result = startOutput(service, @{@"sourceURL": @"file:///tmp/MXR-file-that-does-not-exist.ts",
            @"destinationURL": [NSURL fileURLWithPath:[outPath stringByAppendingString:@".missing"]].absoluteString,
            @"profile": @"copy", @"mode": @"convert"}
            , &error);
        require(result != nil && error == nil, @"invalid input submitted to real VLC engine");
        job = waitForOutput(service, 10);
        require([job[@"state"] isEqual:@"failed"], [NSString stringWithFormat:@"engine failure propagates: %@", job]);

        __block BOOL requested = NO;
        [service request:@"list" service:@"extensions" arguments:@{}
            completion:^(NSDictionary *value, NSError *failure) { result = value; error = failure; requested = YES; }];
        NSDate *extensionDeadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (!requested && extensionDeadline.timeIntervalSinceNow > 0)
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
        require(requested && result != nil && error == nil, @"real Lua catalog request completes");
        NSDictionary *fixture = nil;
        for (NSDictionary *entry in result[@"items"])
            if ([entry[@"name"] isEqual:@"MXR runtime trigger"]) fixture = entry;
        require(fixture != nil && [fixture[@"triggerOnly"] boolValue], @"Lua fixture discovered through VLC manager");
        require([result[@"supportsDialogs"] isEqual:@YES] && [result[@"supportsActivation"] isEqual:@YES],
                @"Lua catalog advertises execution: extension dialogs have a provider (C-05)");
        requested = NO;
        [service request:@"trigger" service:@"extensions" arguments:@{@"id": fixture[@"id"]}
            completion:^(NSDictionary *value, NSError *failure) { result = value; error = failure; requested = YES; }];
        extensionDeadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (!requested && extensionDeadline.timeIntervalSinceNow > 0)
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
        require(requested && result != nil && error == nil, [NSString stringWithFormat:@"on-demand Lua extension runs: %@", error]);
        require([NSFileManager.defaultManager fileExistsAtPath:extensionMarker], @"the trigger ran its fixture callback");

        [service shutdown];
        __block BOOL stopped = NO;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [service finishShutdown];
            vlc_object_delete(intf);
            libvlc_InternalCleanup(vlc);
            libvlc_InternalDestroy(vlc);
            dispatch_async(dispatch_get_main_queue(), ^{ stopped = YES; });
        });
        while (!stopped) [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
        NSLog(@"PASS: real VLC conversion, UDP packets, stream cancellation, failure, Lua execution gate and shutdown");
    }
    return 0;
}
