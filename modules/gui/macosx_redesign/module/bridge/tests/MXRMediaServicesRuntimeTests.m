/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#define MODULE_NAME mxr_media_runtime
#import <Foundation/Foundation.h>
#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_stream.h>
#include <vlc_window.h>
#include <stdatomic.h>
#include <vlc_interface.h>
#include <vlc_playlist.h>
#include <vlc_configuration.h>
#include <signal.h>
#include <execinfo.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include "libvlc_internal.h"
#include "MXRModule.h"
#import "../MXRMediaServices.h"

/* F3 probes. Every video window the engine asks for: under the output player (auxiliary, the
 * app's own job window) or not (it would take the main player surface). Declines, so the dummy
 * window provider takes over. */
static atomic_int auxiliaryWindows, playerWindows;
static int RecordWindow(vlc_window_t *window)
{
    bool auxiliary = false;
    for (vlc_object_t *object = VLC_OBJECT(window); object != NULL; object = vlc_object_parent(object))
        if (var_Type(object, MXR_AUXILIARY_VIDEO_VAR) != 0) { auxiliary = true; break; }
    atomic_fetch_add(auxiliary ? &auxiliaryWindows : &playerWindows, 1);
    return VLC_EGENERIC;
}
/* The inputs that open the watched file (an input also reopens it for its meta reader). Declines,
 * so the real file access opens it. */
static char watchedPath[PATH_MAX];
static vlc_mutex_t watchedLock = VLC_STATIC_MUTEX;
static const vlc_object_t *watchedInputs[8];
static int watchedInputCount;
static int RecordFileOpen(vlc_object_t *object)
{
    stream_t *access = (stream_t *)object;
    if (access->psz_filepath == NULL || watchedPath[0] == '\0' || strcmp(access->psz_filepath, watchedPath) != 0)
        return VLC_EGENERIC;
    vlc_object_t *input = object;
    while (input != NULL && strcmp(vlc_object_typename(input), "input") != 0) input = vlc_object_parent(input);
    vlc_mutex_lock(&watchedLock);
    bool known = false;
    for (int i = 0; i < watchedInputCount; i++) known |= watchedInputs[i] == input;
    if (!known && watchedInputCount < (int)ARRAY_SIZE(watchedInputs)) watchedInputs[watchedInputCount++] = input;
    vlc_mutex_unlock(&watchedLock);
    return VLC_EGENERIC;
}
static int WatchedInputCount(void)
{
    vlc_mutex_lock(&watchedLock);
    int count = watchedInputCount;
    vlc_mutex_unlock(&watchedLock);
    return count;
}
vlc_module_begin()
    set_capability("vout window", 100000)
    set_callback(RecordWindow)
    add_submodule()
        set_capability("access", 100000)
        add_shortcut("file")
        set_callback(RecordFileOpen)
    /* The plugin's local display filter, registered as module.c does (the plugin is not loaded here). */
    add_submodule()
        set_capability("sout filter", 0)
        add_shortcut(MXR_LOCAL_DISPLAY_MODULE)
        set_callback(MXRLocalDisplayOpen)
vlc_module_end()
VLC_EXPORT const vlc_plugin_cb vlc_static_modules[] = { VLC_SYMBOL(vlc_entry), NULL };

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
        /* Dummy outputs: a stream's local copy plays here without a window or sound. */
        const char *options[] = {"MXRMediaServicesRuntimeTests", "--ignore-config", "--no-media-library", "--no-auto-preparse", "--no-video-title-show", "--verbose=0",
                                 "--vout=dummy", "--aout=adummy"};
        libvlc_int_t *vlc = libvlc_InternalCreate();
        require(vlc != NULL && libvlc_InternalInit(vlc, ARRAY_SIZE(options), options) == VLC_SUCCESS, @"VLC initializes");
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
        /* Live J-overwrite: Replace in the Convert alert sends `overwrite`; VLC then writes over it. */
        error = nil;
        result = startOutput(service, @{@"sourceURL": source.absoluteString, @"destinationURL": [NSURL fileURLWithPath:existing].absoluteString,
                                        @"profile": @"audio", @"mode": @"convert", @"overwrite": @YES}, &error);
        require(result != nil && error == nil, @"Replace starts a conversion over the existing destination");
        job = waitForOutput(service, 30);
        require([job[@"state"] isEqual:@"completed"], [NSString stringWithFormat:@"the replacing conversion completes: %@", job]);
        require([streamTypes(probe(existing)) isEqual:@[@"audio"]],
                [NSString stringWithFormat:@"the existing file now holds the new output: %@", streamTypes(probe(existing))]);
        require(noPartialFiles(directory), @"a replacing job leaves no partial file");

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

        /* F3, B1 and live run 2 (D060): with Play locally on, one input feeds the stream and the
         * local display (the source is opened once, the picture is what is sent), the network
         * receives the whole stream for the original and the transcoded format, and it is paced to
         * real time (live run 2: a bare duplicate chain sent 52 s of media in 4 s). The display's
         * video window is an auxiliary one, never the main player surface. */
        strlcpy(watchedPath, source.path.fileSystemRepresentation, sizeof(watchedPath));
        config_PutInt("sout-display", 1);
        for (NSString *profile in @[@"copy", @"h264"]) {
            while (recv(udpSocket, packet, sizeof(packet), 0) > 0) {}
            vlc_mutex_lock(&watchedLock); watchedInputCount = 0; vlc_mutex_unlock(&watchedLock);
            atomic_store(&auxiliaryWindows, 0);
            atomic_store(&playerWindows, 0);
            NSDate *jobStart = [NSDate date];
            result = startOutput(service, @{@"sourceURL": source.absoluteString,
                @"streamURL": @"udp://127.0.0.1:19099", @"profile": profile, @"mode": @"stream"}, &error);
            require(result != nil && error == nil, [NSString stringWithFormat:@"a %@ stream with a local copy starts", profile]);
            NSDate *firstPacket = nil, *lastPacket = nil;
            NSUInteger packets = 0, bytes = 0, tsPackets = 0;
            NSDate *pacedDeadline = [NSDate dateWithTimeIntervalSinceNow:30];
            do {
                [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
                ssize_t length;
                while ((length = recv(udpSocket, packet, sizeof(packet), 0)) > 0) {
                    lastPacket = [NSDate date]; firstPacket = firstPacket ?: lastPacket; packets++; bytes += (NSUInteger)length;
                    for (ssize_t offset = 0; offset + 188 <= length; offset += 188) tsPackets += packet[offset] == 0x47;
                }
                job = [[service snapshotForService:@"output"][@"jobs"] lastObject];
            } while (![@[@"completed", @"failed", @"cancelled"] containsObject:job[@"state"]] && pacedDeadline.timeIntervalSinceNow > 0);
            require([job[@"state"] isEqual:@"completed"], [NSString stringWithFormat:@"the %@ stream played locally completes: %@", profile, job]);
            NSTimeInterval spread = [lastPacket timeIntervalSinceDate:firstPacket];
            NSTimeInterval duration = -jobStart.timeIntervalSinceNow;
            NSLog(@"played-locally %@ stream: %lu packets, %lu bytes, %lu TS packets over %.2f s, job %.2f s, %d inputs opened the source, %d job windows, %d player windows",
                  profile, (unsigned long)packets, (unsigned long)bytes, (unsigned long)tsPackets, spread, duration, WatchedInputCount(),
                  atomic_load(&auxiliaryWindows), atomic_load(&playerWindows));
            /* B1: the transcoded stream once sent nothing while the display played. 50 KB is well
             * under either format's 4 s of MPEG-TS (copy: about 80 KB). */
            require(bytes > 50000 && tsPackets * 188 > 50000,
                    [NSString stringWithFormat:@"the network receives the %@ stream played locally (%lu bytes)", profile, (unsigned long)bytes]);
            /* Measured for the 4 s fixture: copy, packets over 2.4 s and a 2.9 s job, the same as
             * the stream without the local copy (the first second leaves at once, the input's file
             * caching); H.264, 1.6 s and 2.95 s (the encoder holds the first frames back); a bare
             * duplicate chain sends all of it within 0.2 s. */
            require(spread > 1.0 && duration > 2.5,
                    [NSString stringWithFormat:@"a %@ stream played locally is paced to real time (4 s sent over %.2f s, job %.2f s)", profile, spread, duration]);
            require(WatchedInputCount() == 1,
                    [NSString stringWithFormat:@"playing locally opens the source in one input (%d inputs)", WatchedInputCount()]);
            require(atomic_load(&auxiliaryWindows) >= 1, @"the local display shows the video in a job window");
            require(atomic_load(&playerWindows) == 0, @"the local display never takes the main player surface");
        }
        close(udpSocket);

        /* S1: a stream that cannot open (its HTTP port is taken) fails the job with Play locally
         * on, as it does without it, instead of a "running" job that only plays locally. */
        int busy = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
        struct sockaddr_in busyAddress = {.sin_len = sizeof(busyAddress), .sin_family = AF_INET,
            .sin_port = htons(19097), .sin_addr = {.s_addr = htonl(INADDR_LOOPBACK)}};
        require(busy >= 0 && bind(busy, (struct sockaddr *)&busyAddress, sizeof(busyAddress)) == 0 && listen(busy, 1) == 0,
                @"a localhost TCP listener takes the HTTP port");
        for (NSNumber *display in @[@NO, @YES]) {
            config_PutInt("sout-display", display.boolValue);
            atomic_store(&auxiliaryWindows, 0);
            result = startOutput(service, @{@"sourceURL": source.absoluteString,
                @"streamURL": @"http://127.0.0.1:19097/live.ts", @"profile": @"copy", @"mode": @"stream"}, &error);
            require(result != nil && error == nil, @"a stream to a busy port is submitted");
            job = waitForOutput(service, 10);
            NSLog(@"busy HTTP port, play locally %@: %@ (%d job windows)", display, job[@"state"], atomic_load(&auxiliaryWindows));
            require([job[@"state"] isEqual:@"failed"],
                    [NSString stringWithFormat:@"a stream that cannot open fails the job (play locally %@): %@", display, job]);
        }
        close(busy);
        config_PutInt("sout-display", 0);

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
