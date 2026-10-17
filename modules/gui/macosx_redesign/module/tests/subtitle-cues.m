/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later.
 * Compile with MXRSubtitleCueServices.m and real libvlccore. Pass --native to
 * exercise preattached tracks, or --native-live for playback-time imports.
 * VLC_PLUGIN_PATH must contain the
 * filesystem, WAV, subtitle/WebVTT, PCM, dummy outputs, text/libass decoders.
 * All generated media lives in a unique /private/tmp directory. */
#import <Foundation/Foundation.h>
#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_input_item.h>
#include <vlc_player.h>
#include <vlc_playlist.h>
#include <vlc_hash.h>
#include <vlc_strings.h>
#include <sys/stat.h>
#include "lib/libvlc_internal.h"
#import "MXRSubtitleCueServices.h"

static NSUInteger failures;
static void Check(BOOL condition, NSString *message)
{
    fprintf(stderr, "%s %s\n", condition ? "PASS" : "FAIL", message.UTF8String);
    if (!condition) ++failures;
}
static void Pump(BOOL (^finished)(void), NSTimeInterval timeout)
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!finished() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    Check(finished(), @"Native async operation completes before its deadline");
}
static NSArray *Parse(NSString *text, NSString *format)
{
    return MXRParseSubtitleCues([text dataUsingEncoding:NSUTF8StringEncoding], format);
}
static NSString *SRT(void)
{
    return @"2\r\n00:00:04,000 --> 00:00:05,250\r\nSecond\r\n\r\n1\r\n00:00:01,250 --> 00:00:03,500\r\n<i>First &amp; line</i>\r\nNext line\r\n";
}
static NSString *VTT(void)
{
    return @"WEBVTT\tFixture\n\nNOTE\tcomment\n00:01.000 --> 00:02.000\nComment only\n\nWEBVTT-1\n00:02.500 --> 00:04.000 align:start\n<v Narrator>VTT cue</v>\n";
}
static NSString *ASS(void)
{
    return @"[Script Info]\nScriptType: v4.00+\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:01.20,0:00:02.30,Default,,0,0,0,,{\\i1}ASS cue\\NNext line\n";
}
static void ParserTests(void)
{
    NSArray *srt = Parse([@"\uFEFF" stringByAppendingString:SRT()], @"srt");
    Check(srt.count == 2 && [srt[0][@"start"] longLongValue] == 1250000 && [srt[0][@"end"] longLongValue] == 3500000,
          @"SRT BOM/CRLF cues use actual microsecond times and sorted order");
    Check([srt[0][@"text"] isEqual:@"First & line\nNext line"], @"SRT markup and multiline text become plain text");
    Check([MXRParseSubtitleCues([SRT() dataUsingEncoding:NSUnicodeStringEncoding], @"srt") isEqual:srt], @"UTF-16 BOM files retain subtitle text and times");
    NSArray *vtt = Parse(@"WEBVTT\n\nNOTE ignored comment\n00:01.000 --> 00:02.000\nNot a cue\n\nidentifier\n00:02.500 --> 00:04.000 align:start position:20%\n<v Narrator>Hello &lt;world&gt;</v>\n", @"vtt");
    Check(vtt.count == 1 && [vtt[0][@"start"] longLongValue] == 2500000 && [vtt[0][@"text"] isEqual:@"Hello <world>"],
          @"WebVTT skips metadata/comments and handles identifiers, settings and tags");
    NSArray *identifier = Parse(@"WEBVTT\n\nWEBVTT-1\n00:01.000 --> 00:02.000\nReal cue\n\n", @"vtt");
    Check(identifier.count == 1 && [identifier[0][@"start"] longLongValue] == 1000000 &&
          [identifier[0][@"end"] longLongValue] == 2000000 && [identifier[0][@"text"] isEqual:@"Real cue"],
          @"WebVTT-prefixed cue identifiers are not mistaken for the file signature");
    Check(Parse(@"WEBVTT\n\nNOTE\tcomment\n00:01.000 --> 00:02.000\nComment only\n\n", @"vtt").count == 0,
          @"WebVTT NOTE followed by a tab ignores timing-like comment content");
    for (NSString *signature in @[@"WEBVTT", @"WEBVTT Header", @"WEBVTT\tHeader"]) {
        NSString *fixture = [signature stringByAppendingString:@"\n\nWEBVTT-1\n00:01.000 --> 00:02.000\nReal cue\n\n"];
        Check([Parse(fixture, @"vtt") isEqual:identifier], @"WebVTT signature accepts exact, space and tab boundaries only at the file header");
    }
    Check(Parse(@"WEBVTT-1\n\n00:01.000 --> 00:02.000\nMissing signature\n", @"vtt").count == 0,
          @"A cue identifier cannot substitute for the initial WebVTT signature");
    for (NSString *keyword in @[@"NOTE", @"STYLE", @"REGION"]) {
        NSString *fixture = [NSString stringWithFormat:@"WEBVTT\n\n%@\tmetadata\n00:01.000 --> 00:02.000\nMetadata only\n\n%@-1\n00:03.000 --> 00:04.000\nReal cue\n\n", keyword, keyword];
        NSArray *cues = Parse(fixture, @"vtt");
        Check(cues.count == 1 && [cues[0][@"start"] longLongValue] == 3000000 && [cues[0][@"text"] isEqual:@"Real cue"],
              @"WebVTT metadata keywords require whitespace boundaries and preserve prefixed identifiers");
    }
    NSArray *ass = Parse(@"[Script Info]\nTitle: Fixture\n[Events]\nFormat: Layer, End, Start, Style, Text\nComment: 0,1:02:04.00,1:02:03.45,Default,Ignore\nDialogue: 0,1:02:04.00,1:02:03.45,Default,{\\i1}Hello, world\\NNext\\hline\n", @"ass");
    Check(ass.count == 1 && [ass[0][@"start"] longLongValue] == 3723450000LL && [ass[0][@"end"] longLongValue] == 3724000000LL &&
          [ass[0][@"text"] isEqual:@"Hello, world\nNext line"], @"ASS honors declared field order, centiseconds, commas and overrides");
    NSArray *ssa = Parse(@"[Events]\nDialogue: Marked=0,0:00:01.20,0:00:02.30,Default,Name,0,0,0,,SSA cue\n", @"ssa");
    Check(ssa.count == 1 && [ssa[0][@"start"] longLongValue] == 1200000, @"SSA default event fields are supported");
    Check(Parse(@"1\n00:61:00,000 --> 00:62:00,000\nInvalid\n\n2\n00:00:05,000 --> 00:00:04,000\nReverse\n", @"srt").count == 0,
          @"Invalid timestamps and reversed intervals are rejected");
    NSArray *shortSRT = Parse(@"1\n00:00:01,50 --> 00:00:02,50\nCue\n\n", @"srt");
    Check(shortSRT.count == 1 && [shortSRT[0][@"start"] longLongValue] == 1050000 && [shortSRT[0][@"end"] longLongValue] == 2050000,
          @"SRT fractions match VLC integer milliseconds regardless of field width");
    NSArray *shortVTT = Parse(@"WEBVTT\n\n00:01.50 --> 00:02.50\nCue\n\n", @"vtt");
    Check(shortVTT.count == 1 && [shortVTT[0][@"start"] longLongValue] == 1050000,
          @"WebVTT fractions match VLC integer milliseconds");
    for (NSString *format in @[@"ass", @"ssa"]) {
        NSArray *shortASS = Parse(@"[Events]\nDialogue: 0,0:00:01.2,0:00:02.2,Default,,0,0,0,,Cue\n", format);
        Check(shortASS.count == 1 && [shortASS[0][@"start"] longLongValue] == 1020000 && [shortASS[0][@"end"] longLongValue] == 2020000,
              @"ASS and SSA fractions match VLC integer centiseconds");
    }
    Check(Parse(SRT(), @"sub").count == 0, @"Unsupported formats return no invented cues");
    Check(MXRParseSubtitleCues([NSMutableData dataWithLength:5 * 1024 * 1024 + 1], @"srt").count == 0, @"Oversized subtitle data is rejected before decoding");
    const unsigned char bytes[] = {0xff, 0xee};
    Check(MXRParseSubtitleCues([NSData dataWithBytes:bytes length:sizeof(bytes)], @"srt").count == 0, @"Unsupported encodings return an empty timeline");
    NSMutableString *many = [NSMutableString string];
    for (NSUInteger i = 0; i < 10001; ++i) [many appendString:@"00:00:00,000 --> 00:00:01,000\nx\n\n"];
    Check(Parse(many, @"srt").count == 0, @"Cue-count limit prevents unbounded timeline output");
}
static NSDictionary *Query(MXRSubtitleCueServices *helper, NSString *trackID, NSError **error)
{
    __block BOOL done = NO; __block NSDictionary *result; __block NSError *failure;
    [helper request:@"subtitleCues" service:@"player" arguments:@{@"id": trackID} completion:^(NSDictionary *reply, NSError *problem) {
        Check(NSThread.isMainThread, @"Cue completion uses main"); result = reply; failure = problem; done = YES;
    }];
    Pump(^BOOL { return done; }, 5); if (error) *error = failure; return result;
}
static NSString *Selected(vlc_player_t *player)
{
    vlc_player_Lock(player);
    const struct vlc_player_track *track = vlc_player_GetSelectedTrack(player, SPU_ES);
    NSString *identifier = track ? [NSString stringWithUTF8String:vlc_es_id_GetStrId(track->es_id)] : nil;
    vlc_player_Unlock(player);
    return identifier;
}
static NSString *TrackID(NSURL *url)
{
    const char *uri = url.absoluteString.UTF8String;
    vlc_hash_md5_t hash; char digest[VLC_HASH_MD5_DIGEST_HEX_SIZE];
    vlc_hash_md5_Init(&hash); vlc_hash_md5_Update(&hash, uri, strlen(uri)); vlc_hash_FinishHex(&hash, digest);
    return [[NSString stringWithUTF8String:digest] stringByAppendingString:@"/spu/0"];
}
static NSString *ActualTrackID(vlc_player_t *player, NSURL *url)
{
    NSString *prefix = [TrackID(url) stringByDeletingLastPathComponent];
    NSString *identifier;
    vlc_player_Lock(player);
    for (size_t i = 0; i < vlc_player_GetTrackCount(player, SPU_ES); ++i) {
        const struct vlc_player_track *track = vlc_player_GetTrackAt(player, SPU_ES, i);
        NSString *candidate = [NSString stringWithUTF8String:vlc_es_id_GetStrId(track->es_id)];
        if ([candidate hasPrefix:[prefix stringByAppendingString:@"/"]]) { identifier = candidate; break; }
    }
    vlc_player_Unlock(player);
    return identifier;
}
static void NativeTests(BOOL live)
{
    NSURL *directory = [NSURL fileURLWithPath:[@"/private/tmp/mxr-subtitle-cues-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:NO attributes:nil error:NULL];
    NSURL *audio = [directory URLByAppendingPathComponent:@"fixture.wav"], *subtitle = [directory URLByAppendingPathComponent:@"fixture.srt"],
          *other = [directory URLByAppendingPathComponent:@"other.srt"],
          *vtt = [directory URLByAppendingPathComponent:@"fixture.vtt"],
          *ass = [directory URLByAppendingPathComponent:@"fixture.ass"];
    // 30 seconds of 8 kHz mono PCM silence, with a real WAV header.
    NSMutableData *wav = [NSMutableData dataWithLength:44 + 30 * 8000 * 2]; unsigned char *header = wav.mutableBytes;
    memcpy(header, "RIFF", 4); uint32_t riff = CFSwapInt32HostToLittle((uint32_t)wav.length - 8); memcpy(header + 4, &riff, 4);
    memcpy(header + 8, "WAVEfmt ", 8); uint32_t chunk = CFSwapInt32HostToLittle(16); memcpy(header + 16, &chunk, 4);
    uint16_t one = CFSwapInt16HostToLittle(1), bits = CFSwapInt16HostToLittle(16), align = CFSwapInt16HostToLittle(2);
    memcpy(header + 20, &one, 2); memcpy(header + 22, &one, 2); uint32_t rate = CFSwapInt32HostToLittle(8000), bytes = CFSwapInt32HostToLittle(16000);
    memcpy(header + 24, &rate, 4); memcpy(header + 28, &bytes, 4); memcpy(header + 32, &align, 2); memcpy(header + 34, &bits, 2);
    memcpy(header + 36, "data", 4); chunk = CFSwapInt32HostToLittle((uint32_t)wav.length - 44); memcpy(header + 40, &chunk, 4);
    Check([wav writeToURL:audio atomically:YES] && [SRT() writeToURL:subtitle atomically:YES encoding:NSUTF8StringEncoding error:NULL], @"Native fixtures stay under unique /private/tmp directory");
    [@"1\n00:00:02,000 --> 00:00:04,000\nOther track\n" writeToURL:other atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [VTT() writeToURL:vtt atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [ASS() writeToURL:ass atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    const char *args[] = {"subtitle-cues-test", "--ignore-config", "--no-media-library", "--no-auto-preparse", "--no-metadata-network-access", "--aout=dummy", "--vout=dummy", "--sub-autodetect-fuzzy=0"};
    libvlc_int_t *core = libvlc_InternalCreate();
    if (!core || libvlc_InternalInit(core, 8, args) != VLC_SUCCESS) {
        Check(NO, @"Actual VLC core initializes");
        if (core) libvlc_InternalDestroy(core);
        [NSFileManager.defaultManager removeItemAtURL:directory error:NULL]; return;
    }
    intf_thread_t *intf = vlc_object_create(core, sizeof(*intf));
    vlc_player_t *player = vlc_playlist_GetPlayer(vlc_intf_GetMainPlaylist(intf));
    MXRSubtitleCueServices *helper = [[MXRSubtitleCueServices alloc] initWithPlaylist:vlc_intf_GetMainPlaylist(intf) interface:intf];
    Check([helper.capabilities[@"supportsSubtitleTimeline"] boolValue], @"Actual subtitle listener advertises timeline support");
    Check(CFGetTypeID((__bridge CFTypeRef)helper.capabilities[@"supportsSubtitleTimeline"]) == CFBooleanGetTypeID(),
          @"Subtitle timeline capability uses the public Boolean schema");
    input_item_t *item = input_item_New(audio.absoluteString.UTF8String, "Subtitle fixture");
    if (!live) {
        input_item_slave_t *slave = input_item_slave_New(subtitle.absoluteString.UTF8String, SLAVE_TYPE_SPU, SLAVE_PRIORITY_USER);
        slave->b_forced = true; input_item_AddSlave(item, slave);
        input_item_AddSlave(item, input_item_slave_New(other.absoluteString.UTF8String, SLAVE_TYPE_SPU, SLAVE_PRIORITY_USER));
        input_item_AddSlave(item, input_item_slave_New(vtt.absoluteString.UTF8String, SLAVE_TYPE_SPU, SLAVE_PRIORITY_USER));
        input_item_AddSlave(item, input_item_slave_New(ass.absoluteString.UTF8String, SLAVE_TYPE_SPU, SLAVE_PRIORITY_USER));
    }
    vlc_player_Lock(player); vlc_player_SetStartPaused(player, true);
    int status = vlc_player_SetCurrentMedia(player, item); if (!status) status = vlc_player_Start(player); vlc_player_Unlock(player);
    Check(status == VLC_SUCCESS, live ? @"Actual VLC opens paused fixture without attached subtitles" : @"Actual VLC opens paused fixture with four external subtitles");
    if (live) {
        vlc_player_Lock(player);
        status = vlc_player_AddAssociatedMedia(player, SPU_ES, subtitle.absoluteString.UTF8String, true, false, false);
        vlc_player_Unlock(player);
        Check(status == VLC_SUCCESS, @"Actual player dynamically adds and selects the first external subtitle");
    }
    Pump(^BOOL { return Selected(player) != nil; }, 5);
    NSString *identifier = Selected(player);
    __block NSUInteger cancelled = 0;
    if (identifier) {
        fprintf(stderr, "Selected actual subtitle track: %s\n", identifier.UTF8String);
        Check([identifier isEqual:TrackID(subtitle)], @"Native external track ID matches actual slave URL hash");
        NSError *error; NSDictionary *result = Query(helper, identifier, &error);
        Check(!error && [result[@"cues"] isEqual:Parse(SRT(), @"srt")], @"Native selected SRT returns real cue times and text");
        result = Query(helper, TrackID(other), &error);
        Check(!error && [result[@"cues"] count] == 0, @"Unselected external subtitle is not confused with selected source");
        result = Query(helper, @"spu/0", &error);
        Check(!error && [result[@"cues"] count] == 0, @"Unresolved embedded track returns empty without an error");
        for (NSURL *source in @[vtt, ass]) {
            if (live) {
                vlc_player_Lock(player);
                status = vlc_player_AddAssociatedMedia(player, SPU_ES, source.absoluteString.UTF8String, false, false, false);
                vlc_player_Unlock(player);
                Check(status == VLC_SUCCESS, @"Actual player dynamically adds another external format");
            }
            Pump(^BOOL { return ActualTrackID(player, source) != nil; }, 5);
            NSString *trackID = ActualTrackID(player, source);
            if (!trackID) continue;
            fprintf(stderr, "Selecting actual %s track: %s\n", source.pathExtension.UTF8String, trackID.UTF8String);
            vlc_player_Lock(player); vlc_player_SelectTracksByStringIds(player, SPU_ES, trackID.UTF8String); vlc_player_Unlock(player);
            Pump(^BOOL { return [Selected(player) isEqual:trackID]; }, 5);
            result = Query(helper, trackID, &error);
            NSArray *expected = [source isEqual:vtt]
                ? @[@{@"start": @2500000, @"end": @4000000, @"text": @"VTT cue"}]
                : @[@{@"start": @1200000, @"end": @2300000, @"text": @"ASS cue\nNext line"}];
            Check(!error && [result[@"cues"] isEqual:expected],
                  [NSString stringWithFormat:@"Actual selected %@ source resolves its own real cues", source.pathExtension.uppercaseString]);
        }
        vlc_player_Lock(player); vlc_player_SelectTracksByStringIds(player, SPU_ES, identifier.UTF8String); vlc_player_Unlock(player);
        Pump(^BOOL { return [Selected(player) isEqual:identifier]; }, 5);
        __block NSUInteger staleCompletions = 0;
        [helper request:@"subtitleCues" service:@"player" arguments:@{@"id": identifier} completion:^(NSDictionary *reply, NSError *problem) {
            Check(!problem && [reply[@"cues"] count] == 0, @"Track change discards pending cue results"); ++staleCompletions;
        }];
        vlc_player_Lock(player); vlc_player_UnselectTrackCategory(player, SPU_ES); vlc_player_Unlock(player);
        Pump(^BOOL { return staleCompletions == 1; }, 5);
        vlc_player_Lock(player); vlc_player_SelectTracksByStringIds(player, SPU_ES, identifier.UTF8String); vlc_player_Unlock(player);
        Pump(^BOOL { return [Selected(player) isEqual:identifier]; }, 5);
        __block NSUInteger oldResults = 0, newResults = 0;
        [helper request:@"subtitleCues" service:@"player" arguments:@{@"id": identifier} completion:^(NSDictionary *reply, NSError *problem) {
            Check(!problem && [reply[@"cues"] count] == 0, @"A newer cue request supersedes an older pending result"); ++oldResults;
        }];
        [helper request:@"subtitleCues" service:@"player" arguments:@{@"id": identifier} completion:^(NSDictionary *reply, NSError *problem) {
            Check(!problem && [reply[@"cues"] isEqual:Parse(SRT(), @"srt")], @"The newest cue request returns selected content"); ++newResults;
        }];
        Pump(^BOOL { return oldResults == 1 && newResults == 1; }, 5);
        __block NSUInteger previousMediaResults = 0;
        [helper request:@"subtitleCues" service:@"player" arguments:@{@"id": identifier} completion:^(NSDictionary *reply, NSError *problem) {
            Check(!problem && [reply[@"cues"] count] == 0, @"Restarting the same media URI discards old pending cue results"); ++previousMediaResults;
        }];
        input_item_t *replacement = input_item_New(audio.absoluteString.UTF8String, "Subtitle fixture restart");
        input_item_slave_t *replacementSlave = input_item_slave_New(subtitle.absoluteString.UTF8String, SLAVE_TYPE_SPU, SLAVE_PRIORITY_USER);
        replacementSlave->b_forced = true; input_item_AddSlave(replacement, replacementSlave);
        vlc_player_Lock(player); status = vlc_player_SetCurrentMedia(player, replacement); if (!status) status = vlc_player_Start(player); vlc_player_Unlock(player);
        input_item_Release(replacement);
        Check(status == VLC_SUCCESS, @"Actual VLC restarts another input item with the same URI");
        Pump(^BOOL { return previousMediaResults == 1; }, 5);
        Pump(^BOOL { return [Selected(player) isEqual:identifier]; }, 5);
        [helper request:@"subtitleCues" service:@"player" arguments:@{@"id": identifier} completion:^(NSDictionary *reply, NSError *problem) {
            Check(!reply && problem.code == NSUserCancelledError, @"Shutdown cancels pending cues"); ++cancelled;
        }];
        [helper shutdown]; Check(cancelled == 1, @"Pending cue completion resolves exactly once on shutdown");
    } else [helper shutdown];
    NSNumber *stoppedCapability = helper.capabilities[@"supportsSubtitleTimeline"];
    Check(CFGetTypeID((__bridge CFTypeRef)stoppedCapability) == CFBooleanGetTypeID() && !stoppedCapability.boolValue,
          @"Stopped subtitle timeline capability remains a Boolean false");
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ [helper finishShutdown]; });
    Check(dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0, @"Subtitle reader drains before VLC teardown");
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
    if (identifier) Check(cancelled == 1, @"Reader drain does not deliver a second shutdown completion");
    input_item_Release(item); vlc_object_delete(intf); libvlc_InternalCleanup(core); libvlc_InternalDestroy(core);
    [NSFileManager.defaultManager removeItemAtURL:directory error:NULL];
}
int main(int argc, const char *argv[])
{
    @autoreleasepool {
        ParserTests();
        if (argc > 1 && !strcmp(argv[1], "--native")) NativeTests(NO);
        else if (argc > 1 && !strcmp(argv[1], "--native-live")) NativeTests(YES);
        fprintf(stderr, "%s subtitle cue tests (%lu failures)\n", failures ? "FAIL" : "PASS", (unsigned long)failures);
        return failures ? 1 : 0;
    }
}
