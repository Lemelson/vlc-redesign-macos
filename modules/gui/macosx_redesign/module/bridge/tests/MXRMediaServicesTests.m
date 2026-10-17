/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
#import <Foundation/Foundation.h>
#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_playlist.h>
#include <vlc_configuration.h>
#import "../MXRMediaServices.h"

static void require(BOOL condition, NSString *description)
{
    if (!condition) {
        NSLog(@"FAIL: %@", description);
        exit(1);
    }
}

int main(void)
{
    @autoreleasepool {
        NSError *error = nil;
        NSString *path = @"/tmp/выход 'quoted', {file} \\ \"video\".ts";
        NSDictionary *args = @{@"sourceURL": @"file:///tmp/input.mov", @"mode": @"convert",
                               @"destinationURL": [NSURL fileURLWithPath:path].absoluteString,
                               @"profile": @"copy"};
        NSDictionary *definition = MXRCreateOutputDefinition(args, &error);
        require(definition != nil && error == nil, @"valid Unicode output path accepted");
        char *name = NULL;
        config_chain_t *chain = NULL;
        char *next = config_ChainCreate(&name, &chain, [definition[@"sout"] UTF8String] + 1);
        require(name != NULL && strcmp(name, "standard") == 0, @"real VLC parser reads standard output");
        BOOL foundPath = NO, noOverwrite = NO;
        NSString *partial = definition[@"partialPath"];
        for (config_chain_t *option = chain; option != NULL; option = option->p_next) {
            if (strcmp(option->psz_name, "dst") == 0)
                foundPath = [partial isEqualToString:[NSString stringWithUTF8String:option->psz_value]];
            if (strcmp(option->psz_name, "access") == 0)
                noOverwrite = strcmp(option->psz_value, "file{no-overwrite}") == 0;
        }
        require(foundPath, @"quotes, commas, braces and backslashes survive VLC chain parsing");
        require(noOverwrite, @"the hidden partial file is never an existing file");
        require([partial.stringByDeletingLastPathComponent isEqual:path.stringByDeletingLastPathComponent] &&
                [partial.lastPathComponent hasPrefix:[@"." stringByAppendingString:path.lastPathComponent]] &&
                [partial hasSuffix:@".vlc-partial"],
                @"VLC writes a hidden partial file beside the destination (J-11)");
        require(![MXRCreateOutputDefinition(args, &error)[@"partialPath"] isEqual:partial], @"every job gets its own partial file");
        free(name); free(next); config_ChainDestroy(chain);

        /* D036 (J-01): transcoding never runs transcode's PCR synchroniser, which asserts when audio
         * and video are both transcoded, and H.264 uses x264, which honours the bitrate. */
        for (NSString *profile in @[@"h264", @"audio", @"aac", @"wav"]) {
            NSMutableDictionary *transcoded = [args mutableCopy];
            transcoded[@"profile"] = profile;
            NSString *sout = MXRCreateOutputDefinition(transcoded, &error)[@"sout"];
            require([sout hasPrefix:@"#transcode{"] && [sout containsString:@",no-forward-pcr}:"],
                    [NSString stringWithFormat:@"%@ transcode disables PCR forwarding: %@", profile, sout]);
        }
        NSMutableDictionary *h264 = [args mutableCopy];
        h264[@"profile"] = @"h264";
        require([MXRCreateOutputDefinition(h264, &error)[@"sout"] hasPrefix:@"#transcode{venc=x264{keyint=60},vcodec=h264,vb=2500,"],
                @"H.264 is encoded by x264 at the requested bitrate");

        NSMutableDictionary *invalid = [args mutableCopy];
        invalid[@"destinationURL"] = invalid[@"sourceURL"];
        require(MXRCreateOutputDefinition(invalid, &error) == nil && error != nil,
                @"cannot replace source with output");
        invalid = [args mutableCopy]; invalid[@"profile"] = @"unknown";
        require(MXRCreateOutputDefinition(invalid, &error) == nil, @"unknown profile rejected");
        invalid = [args mutableCopy]; invalid[@"destinationURL"] = @"https://example.com/output";
        require(MXRCreateOutputDefinition(invalid, &error) == nil, @"convert requires file destination");

        NSDictionary *stream = @{@"sourceURL": @"file:///tmp/input.mov", @"mode": @"stream",
                                 @"streamURL": @"udp://239.1.2.3:1234", @"profile": @"copy"};
        definition = MXRCreateOutputDefinition(stream, &error);
        require([definition[@"sout"] isEqual:@"#udp{dst=\"239.1.2.3:1234\"}"],
                @"UDP destination and port represented exactly");
        NSDictionary *flags = @{@"sout-display": @YES, @"sout-keep": @YES,
                                 @"sout-audio": @NO, @"sout-video": @YES, @"sout-spu": @NO};
        NSArray *options = MXROutputOptions(definition, flags);
        require([options containsObject:@"sout-keep"] && [options containsObject:@"no-sout-audio"] &&
                [options containsObject:@"sout-video"] && [options containsObject:@"no-sout-spu"],
                @"each new streaming input receives all current inclusion and keep values");
        NSString *displayChain = [options.firstObject substringFromIndex:6]; // sout=#
        name = NULL; chain = NULL;
        next = config_ChainCreate(&name, &chain, displayChain.UTF8String);
        require(name && strcmp(name, "duplicate") == 0, @"explicit chain duplicates local playback");
        BOOL foundDisplay = NO, foundStream = NO;
        for (config_chain_t *option = chain; option; option = option->p_next) {
            if (strcmp(option->psz_name, "dst") != 0 || !option->psz_value) continue;
            foundDisplay |= strcmp(option->psz_value, "display") == 0;
            foundStream |= strcmp(option->psz_value, [definition[@"sout"] UTF8String] + 1) == 0;
        }
        require(foundDisplay && foundStream, @"VLC parser preserves both original stream and display branches");
        free(name); free(next); config_ChainDestroy(chain);
        NSMutableDictionary *changed = [flags mutableCopy];
        changed[@"sout-audio"] = @YES; changed[@"sout-video"] = @NO; changed[@"sout-spu"] = @YES;
        changed[@"sout-display"] = @NO; changed[@"sout-keep"] = @NO;
        options = MXROutputOptions(definition, changed);
        require([options containsObject:@"sout-audio"] && [options containsObject:@"no-sout-video"] &&
                [options containsObject:@"sout-spu"] && [options containsObject:@"no-sout-keep"],
                @"next job replaces every cached inclusion flag");
        require([options.firstObject isEqual:[@"sout=" stringByAppendingString:definition[@"sout"]]], @"display off restores original output chain");
        NSDictionary *conversion = MXRCreateOutputDefinition(args, &error);
        options = MXROutputOptions(conversion, flags);
        require([options containsObject:@"no-sout-keep"], @"conversion closes its file even when streaming keep is enabled");
        require([options.firstObject isEqual:[@"sout=" stringByAppendingString:conversion[@"sout"]]],
                @"conversion never duplicates to a local display: it runs faster than real time and must not claim a video window");
        for (NSString *profile in @[@"audio", @"aac", @"wav"]) {
            NSMutableDictionary *audioArgs = [args mutableCopy]; audioArgs[@"profile"] = profile;
            NSArray *audioOptions = MXROutputOptions(MXRCreateOutputDefinition(audioArgs, &error), changed);
            require([audioOptions containsObject:@"sout-audio"] && [audioOptions containsObject:@"no-sout-video"] &&
                    [audioOptions containsObject:@"no-sout-spu"] && ![audioOptions containsObject:@"sout-spu"],
                    [NSString stringWithFormat:@"%@ keeps only the sound even when subtitles are included: %@", profile, audioOptions]);
        }
        invalid = [stream mutableCopy]; invalid[@"streamURL"] = @"ftp://127.0.0.1:1234";
        require(MXRCreateOutputDefinition(invalid, &error) == nil, @"unsupported stream protocol rejected");
        invalid = [stream mutableCopy]; invalid[@"streamURL"] = @"udp://127.0.0.1";
        require(MXRCreateOutputDefinition(invalid, &error) == nil, @"stream requires explicit port");
        invalid = [stream mutableCopy]; invalid[@"streamURL"] = @"http://user:secret@localhost:8080/test";
        require(MXRCreateOutputDefinition(invalid, &error) == nil, @"stream credential fields rejected");
        NSLog(@"PASS: native media output contracts");
    }
    return 0;
}
