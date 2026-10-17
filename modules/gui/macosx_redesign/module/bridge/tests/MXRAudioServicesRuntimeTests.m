/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#import <Foundation/Foundation.h>
#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_input_item.h>
#include <vlc_player.h>
#include <vlc_playlist.h>
#include <vlc_aout.h>
#include <signal.h>
#include <execinfo.h>
#include <fcntl.h>
#include "libvlc_internal.h"
#import "../MXRAudioServices.h"

static void require(BOOL condition, NSString *message)
{
    if (!condition) { NSLog(@"FAIL: %@",message); exit(1); }
}
static void traceFailure(int signalNumber)
{
    void *frames[40]; int count = backtrace(frames,40); backtrace_symbols_fd(frames,count,STDERR_FILENO); _Exit(128+signalNumber);
}
static void pumpUntil(BOOL (^finished)(void), NSTimeInterval timeout)
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!finished() && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    require(finished(),@"async request completes within its deadline");
}
static NSDictionary *request(MXRAudioServices *helper,NSString *operation,NSString *service,NSDictionary *args,NSError **error)
{
    __block BOOL done = NO; __block NSDictionary *result = nil; __block NSError *failure = nil;
    [helper request:operation service:service arguments:args completion:^(NSDictionary *value,NSError *requestError) {
        require(NSThread.isMainThread,@"request completion returns to main");
        result = value; failure = requestError; done = YES;
    }];
    pumpUntil(^BOOL { return done; },20); *error = failure; return result;
}
static void inspectWaveform(NSDictionary *result,NSString *label)
{
    NSArray<NSNumber *> *samples = result[@"samples"];
    require(samples.count == 25,[label stringByAppendingString:@" has requested bin count"]);
    require(fabs([result[@"duration"] doubleValue]-2.5) < .08,[label stringByAppendingString:@" has the actual file duration"]);
    require(samples[4].doubleValue > .8 && samples[18].doubleValue > .8,[label stringByAppendingString:@" has left and right tone peaks"]);
    require(samples[0].doubleValue < .03 && samples[12].doubleValue < .03 && samples[24].doubleValue < .03,
            [label stringByAppendingString:@" preserves leading, middle and trailing silence"]);
    for (NSNumber *value in samples) require(isfinite(value.doubleValue) && value.doubleValue >= 0 && value.doubleValue <= 1,@"waveform normalized to 0...1");
}

int main(int argc,const char *argv[])
{
    @autoreleasepool {
        signal(SIGABRT,traceFailure);
        if (argc == 3 && strcmp(argv[1],"--write-tone") == 0) {
            return [MXRCreateStereoTestWAV() writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES] ? 0 : 1;
        }
        require(argc == 3,@"pass WAV and AAC fixtures made from MXRCreateStereoTestWAV");
        NSData *wav = MXRCreateStereoTestWAV();
        const uint8_t *bytes = wav.bytes;
        require(wav.length == 44+48000*5/2*4 && !memcmp(bytes,"RIFF",4) && !memcmp(bytes+8,"WAVE",4),@"test signal has a complete PCM WAV header");
        const int16_t *pcm = (const int16_t *)(bytes+44);
        int leftPeak = 0,rightPeak = 0;
        for (NSUInteger index = 0; index < 120000; ++index) {
            int left = (int16_t)CFSwapInt16LittleToHost((uint16_t)pcm[2*index]);
            int right = (int16_t)CFSwapInt16LittleToHost((uint16_t)pcm[2*index+1]);
            double time = (double)index/48000;
            if (time < 1.1) { require(right == 0,@"left tone has no right-channel signal"); leftPeak = MAX(leftPeak,abs(left)); }
            else if (time < 1.4) require(left == 0 && right == 0,@"tones have a silent separator");
            else { require(left == 0,@"right tone has no left-channel signal"); rightPeak = MAX(rightPeak,abs(right)); }
        }
        require(leftPeak > 5000 && leftPeak < 6000 && rightPeak > 5000 && rightPeak < 6000,@"both channels have a capped 0.18 full-scale signal");

        const char *options[] = {"MXRAudioServicesRuntimeTests","--ignore-config","--no-media-library","--no-auto-preparse","--no-video-title-show","--aout=adummy","--vout=dummy","--verbose=0",
            "--start-time=0.8","--stop-time=1.1","--run-time=0.2","--rate=2",
            "--audio-track=1","--audio-track-id=missing-track","--audio-language=none","--audio-resampler=missing-resampler","--no-stats","--stats-min-report-interval=10000"};
        libvlc_int_t *vlc = libvlc_InternalCreate();
        require(vlc != NULL && libvlc_InternalInit(vlc,18,options) == VLC_SUCCESS,@"VLC initializes with dummy output and inherited trimming, rate, track, resampler and statistics settings");
        require(var_InheritBool(vlc,"ignore-config"),@"engine actually ignores user config and skips config autosave");
        libvlc_InternalPlay(vlc);
        intf_thread_t *intf = vlc_object_create(vlc,sizeof(*intf));
        require(intf != NULL,@"VLC interface created");
        vlc_playlist_t *main = vlc_intf_GetMainPlaylist(intf);
        MXRAudioServices *helper = [[MXRAudioServices alloc] initWithPlaylist:main interface:intf];
        require([helper.capabilities[@"stereoTest"] boolValue] && [helper.capabilities[@"supportsWaveform"] boolValue],@"native audio capabilities available");
        require(CFGetTypeID((__bridge CFTypeRef)helper.capabilities[@"stereoTest"]) == CFBooleanGetTypeID(),@"stereo capability serializes as a JSON Boolean");
        NSURL *source = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSError *error = nil;
        NSDictionary *arguments = @{@"media":@{@"url":source.absoluteString},@"bins":@25};
        NSDictionary *wave = request(helper,@"waveform",@"thumbnails",arguments,&error);
        require(error == nil && wave != nil,[NSString stringWithFormat:@"WAV analysis succeeds: %@",error]); inspectWaveform(wave,@"WAV");
        require([request(helper,@"waveform",@"thumbnails",arguments,&error) isEqual:wave] && error == nil,@"cached waveform returns actual samples");
        NSString *cachePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"mxr-wave-cache-%@.wav",NSUUID.UUID.UUIDString]];
        require([wav writeToFile:cachePath atomically:YES],@"cache invalidation fixture written");
        NSDictionary *cacheArgs = @{@"media":@{@"url":[NSURL fileURLWithPath:cachePath].absoluteString},@"bins":@25};
        require(request(helper,@"waveform",@"thumbnails",cacheArgs,&error) != nil && error == nil,@"new waveform cached");
        NSMutableData *silent = [wav mutableCopy]; memset((uint8_t *)silent.mutableBytes+44,0,silent.length-44);
        require([silent writeToFile:cachePath atomically:YES],@"fixture replaced by actual silent PCM");
        [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate:[NSDate dateWithTimeIntervalSinceNow:2]} ofItemAtPath:cachePath error:nil];
        NSDictionary *silentWave = request(helper,@"waveform",@"thumbnails",cacheArgs,&error);
        require(error == nil && silentWave != nil,@"changed file reanalyzed");
        for (NSNumber *peak in silentWave[@"samples"]) require(peak.floatValue == 0,@"mtime cache key returns newly decoded silence");
        [NSFileManager.defaultManager removeItemAtPath:cachePath error:nil];
        NSURL *aac = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]];
        NSDictionary *aacWave = request(helper,@"waveform",@"thumbnails",@{@"media":@{@"url":aac.absoluteString},@"bins":@25},&error);
        require(aacWave != nil && error == nil,[NSString stringWithFormat:@"AAC analysis succeeds: %@",error]); inspectWaveform(aacWave,@"AAC");
        require(request(helper,@"waveform",@"thumbnails",@{@"media":@{@"url":@"https://example.com/song.aac"},@"bins":@25},&error) == nil && error.code == ENOTSUP,@"remote audio has explicit unsupported error");
        require(request(helper,@"waveform",@"thumbnails",@{@"media":@{@"url":source.absoluteString},@"bins":@4097},&error) == nil,@"waveform allocation is bounded");
        __block NSUInteger waveCompletions = 0;
        [helper request:@"waveform" service:@"thumbnails" arguments:arguments completion:^(NSDictionary *value,NSError *failure) {
            require(value == nil && failure.code == ECANCELED,@"waveform cancellation returns no partial or fake values"); ++waveCompletions;
        }];
        request(helper,@"cancelWaveform",@"thumbnails",@{},&error);
        pumpUntil(^BOOL { return waveCompletions == 1; },5);
        NSString *longPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"mxr-wave-cancel-%@.wav",NSUUID.UUID.UUIDString]];
        NSMutableData *longHeader = [wav subdataWithRange:NSMakeRange(0,44)].mutableCopy;
        uint32_t longBytes = 3600*48000*4, size = CFSwapInt32HostToLittle(longBytes), riffSize = CFSwapInt32HostToLittle(longBytes+36);
        memcpy((uint8_t *)longHeader.mutableBytes+40,&size,4); memcpy((uint8_t *)longHeader.mutableBytes+4,&riffSize,4);
        require([longHeader writeToFile:longPath atomically:YES],@"sparse one-hour PCM header created");
        int fd = open(longPath.fileSystemRepresentation,O_WRONLY);
        require(fd >= 0 && ftruncate(fd,44+(off_t)longBytes) == 0,@"large duration fixture uses bounded disk allocation"); close(fd);
        __block NSUInteger readingCompletions = 0;
        [helper request:@"waveform" service:@"thumbnails" arguments:@{@"media":@{@"url":[NSURL fileURLWithPath:longPath].absoluteString},@"bins":@512}
            completion:^(NSDictionary *value,NSError *failure) { require(value == nil && failure.code == ECANCELED,@"active PCM reader cancelled"); ++readingCompletions; }];
        pumpUntil(^BOOL { NSDictionary *status = [helper snapshotForService:@"waveform"]; return [status[@"active"] boolValue] && [status[@"samplesRead"] unsignedLongLongValue] > 4096; },10);
        request(helper,@"cancelWaveform",@"thumbnails",@{},&error);
        pumpUntil(^BOOL { return readingCompletions == 1; },5);
        [NSFileManager.defaultManager removeItemAtPath:longPath error:nil];

        input_item_t *sentinel = input_item_New(source.absoluteString.UTF8String,"Main playback remains paused");
        input_item_AddOption(sentinel,"input-repeat=-1",VLC_INPUT_OPTION_TRUSTED);
        for (const char **option = (const char *[]){"start-time=0","stop-time=0","run-time=0","audio-track=0","audio-track-id=","audio-language=any",NULL}; *option != NULL; ++option)
            input_item_AddOption(sentinel,*option,VLC_INPUT_OPTION_TRUSTED);
        vlc_playlist_Lock(main); require(vlc_playlist_InsertOne(main,0,sentinel) == VLC_SUCCESS && vlc_playlist_PlayAt(main,0) == VLC_SUCCESS,@"main queue plays its own independent media"); vlc_playlist_Unlock(main);
        vlc_player_t *player = vlc_playlist_GetPlayer(main);
        pumpUntil(^BOOL { vlc_player_Lock(player); BOOL playing = vlc_player_GetState(player) == VLC_PLAYER_STATE_PLAYING; vlc_player_Unlock(player); return playing; },10);
        vlc_player_Lock(player); vlc_player_Pause(player); vlc_player_Unlock(player);
        pumpUntil(^BOOL { vlc_player_Lock(player); BOOL paused = vlc_player_GetState(player) == VLC_PLAYER_STATE_PAUSED; vlc_player_Unlock(player); return paused; },5);
        audio_output_t *mainAout = vlc_player_aout_Hold(player);
        int mainStereo = mainAout != NULL ? var_GetInteger(mainAout,"stereo-mode") : 0;
        if (mainAout != NULL) aout_Release(mainAout);
        float mainVolume = vlc_player_aout_GetVolume(player);
        vlc_player_Lock(player); float mainRate = vlc_player_GetRate(player); vlc_player_Unlock(player);
        NSTimeInterval started = NSDate.timeIntervalSinceReferenceDate;
        NSDictionary *result = request(helper,@"start",@"audioTest",@{@"mode":@1},&error);
        require(error == nil && [result[@"state"] isEqual:@"completed"],[NSString stringWithFormat:@"real VLC tone playback reaches EOF: %@",error]);
        NSDictionary *snapshot = [helper snapshotForService:@"audioTest"];
        require(CFGetTypeID((__bridge CFTypeRef)snapshot[@"available"]) == CFBooleanGetTypeID(),@"audio availability serializes as a JSON Boolean");
        require(NSDate.timeIntervalSinceReferenceDate-started > 1.5,@"test overrides inherited trimming/rate and plays both tone intervals");
        require([snapshot[@"decodedAudio"] unsignedLongLongValue] > 0 && [snapshot[@"playedAudioBuffers"] unsignedLongLongValue] > 0,
                [NSString stringWithFormat:@"real PCM decoded and submitted to VLC audio output: %@",snapshot]);
        NSLog(@"Actual native tone statistics: %@",snapshot);
        vlc_playlist_Lock(main); require(vlc_playlist_Count(main) == 1,@"main queue count unchanged"); vlc_playlist_Unlock(main);
        vlc_player_Lock(player); require(vlc_player_GetCurrentMedia(player) == sentinel && vlc_player_GetState(player) == VLC_PLAYER_STATE_PAUSED && vlc_player_GetRate(player) == mainRate,@"main current media, pause state and rate preserved"); vlc_player_Unlock(player);
        mainAout = vlc_player_aout_Hold(player);
        require(mainAout == NULL || var_GetInteger(mainAout,"stereo-mode") == mainStereo,@"main stereo mode unchanged"); if (mainAout != NULL) aout_Release(mainAout);
        require(vlc_player_aout_GetVolume(player) == mainVolume,@"main volume unchanged");
        __block NSUInteger toneCompletions = 0;
        [helper request:@"start" service:@"audioTest" arguments:@{@"mode":@2} completion:^(NSDictionary *value,NSError *failure) {
            require(value == nil && failure.code == ECANCELED,@"playing tone cancelled through VLC stop"); ++toneCompletions;
        }];
        pumpUntil(^BOOL { return [[[helper snapshotForService:@"audioTest"] objectForKey:@"state"] isEqual:@"playing"]; },5);
        request(helper,@"cancel",@"audioTest",@{},&error);
        pumpUntil(^BOOL { return toneCompletions == 1; },10);
        __block NSUInteger shutdownCompletions = 0;
        [helper request:@"start" service:@"audioTest" arguments:@{} completion:^(NSDictionary *value,NSError *failure) {
            require(value == nil && failure.code == ECANCELED,@"shutdown cancels preparing tone once"); ++shutdownCompletions;
        }];
        [helper shutdown]; require(shutdownCompletions == 1,@"shutdown completes outstanding tone request");
        __block BOOL stopped = NO;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
            [helper finishShutdown]; input_item_Release(sentinel); vlc_object_delete(intf); libvlc_InternalCleanup(vlc); libvlc_InternalDestroy(vlc);
            dispatch_async(dispatch_get_main_queue(),^{ stopped = YES; });
        });
        pumpUntil(^BOOL { return stopped; },20);
        require(waveCompletions == 1 && readingCompletions == 1 && toneCompletions == 1 && shutdownCompletions == 1,@"all asynchronous completions fire exactly once");
        NSLog(@"PASS native WAV/AAC peaks, stereo isolation, actual VLC tone output, cancellation and shutdown");
    }
    return 0;
}
