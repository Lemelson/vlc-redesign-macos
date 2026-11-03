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

/* Each element of a sout chain as VLC's parser reads it: its name and its option names. */
static NSArray *parsedChain(NSString *chain)
{
    NSMutableArray *elements = [NSMutableArray array];
    char *rest = strdup(chain.UTF8String);
    while (rest != NULL && *rest != '\0') {
        char *name = NULL;
        config_chain_t *config = NULL;
        char *next = config_ChainCreate(&name, &config, rest);
        free(rest);
        rest = next;
        NSMutableArray *names = [NSMutableArray array];
        for (config_chain_t *option = config; option != NULL; option = option->p_next)
            [names addObject:[NSString stringWithUTF8String:option->psz_name ?: ""]];
        [elements addObject:@[[NSString stringWithUTF8String:name ?: ""], names]];
        free(name);
        config_ChainDestroy(config);
    }
    free(rest);
    return elements;
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
        /* F3, B1 (D060): the local display heads the stream's own chain, which VLC's parser
         * (src/config/chain.c, as sout_StreamChainNew reads it) still sees whole, element by
         * element, for every streamable format and destination. */
        require([options.firstObject isEqual:@"sout=#mxr-local-display:udp{dst=\"239.1.2.3:1234\"}"],
                [NSString stringWithFormat:@"playing locally puts the local display before the stream: %@", options.firstObject]);
        for (NSString *profile in @[@"copy", @"h264"])
            for (NSString *target in @[@"udp://239.1.2.3:1234", @"rtp://127.0.0.1:5004", @"http://127.0.0.1:8080/live.ts"]) {
                NSMutableDictionary *streamed = [stream mutableCopy]; streamed[@"profile"] = profile; streamed[@"streamURL"] = target;
                NSDictionary *streamedDefinition = MXRCreateOutputDefinition(streamed, &error);
                NSString *displayed = [MXROutputOptions(streamedDefinition, flags).firstObject substringFromIndex:@"sout=#".length];
                NSArray *plain = parsedChain([streamedDefinition[@"sout"] substringFromIndex:1]);
                NSArray *expected = [@[@[@"mxr-local-display", @[]]] arrayByAddingObjectsFromArray:plain];
                require(plain.count == ([profile isEqual:@"h264"] ? 2 : 1) && [parsedChain(displayed) isEqual:expected],
                        [NSString stringWithFormat:@"%@ to %@ played locally keeps every stream element: %@ vs %@",
                         profile, target, parsedChain(displayed), plain]);
            }
        require(MXROutputPlaysLocally(definition, flags), @"a stream with Play locally on plays its source locally");
        NSMutableDictionary *changed = [flags mutableCopy];
        changed[@"sout-audio"] = @YES; changed[@"sout-video"] = @NO; changed[@"sout-spu"] = @YES;
        changed[@"sout-display"] = @NO; changed[@"sout-keep"] = @NO;
        options = MXROutputOptions(definition, changed);
        require([options containsObject:@"sout-audio"] && [options containsObject:@"no-sout-video"] &&
                [options containsObject:@"sout-spu"] && [options containsObject:@"no-sout-keep"],
                @"next job replaces every cached inclusion flag");
        require([options.firstObject isEqual:[@"sout=" stringByAppendingString:definition[@"sout"]]], @"display off keeps the original output chain");
        require(!MXROutputPlaysLocally(definition, changed), @"Play locally off plays nothing locally");
        NSDictionary *conversion = MXRCreateOutputDefinition(args, &error);
        options = MXROutputOptions(conversion, flags);
        require([options containsObject:@"no-sout-keep"], @"conversion closes its file even when streaming keep is enabled");
        require([options.firstObject isEqual:[@"sout=" stringByAppendingString:conversion[@"sout"]]],
                @"conversion never duplicates to a local display: it runs faster than real time and must not claim a video window");
        require(!MXROutputPlaysLocally(conversion, flags), @"a conversion never plays a local copy");
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
