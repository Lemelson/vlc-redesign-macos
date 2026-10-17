/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#import <Foundation/Foundation.h>
#import "MXRBridgeKeys.h"
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_input_item.h>
#include <vlc_player.h>
#include <vlc_playlist.h>
#include <vlc_hash.h>
#include <vlc_strings.h>
#import "MXRSubtitleCueServices.h"

static const NSUInteger MXRSubtitleBytes = 5 * 1024 * 1024;
static const NSUInteger MXRSubtitleCueLimit = 10000;
typedef BOOL (^MXRCueCancelled)(void);
typedef void (^MXRCueCompletion)(NSDictionary * _Nullable, NSError * _Nullable);

static NSError *MXRCueError(NSInteger code, NSString *message)
{
    return [NSError errorWithDomain:@"MXRSubtitleCueServices" code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL MXRCueNumber(NSString *text, NSUInteger maximum, NSUInteger *value)
{
    if (!text.length || text.length > 6) return NO;
    NSUInteger number = 0;
    for (NSUInteger i = 0; i < text.length; ++i) {
        unichar character = [text characterAtIndex:i];
        if (character < '0' || character > '9') return NO;
        number = number * 10 + character - '0';
    }
    if (number > maximum) return NO;
    *value = number;
    return YES;
}

static BOOL MXRCueTime(NSString *text, BOOL ass, int64_t *time)
{
    NSArray<NSString *> *parts = [text componentsSeparatedByString:@":"];
    if (parts.count != 2 && parts.count != 3) return NO;
    NSUInteger hours = 0, minutes, seconds, fraction;
    if (parts.count == 3 && !MXRCueNumber(parts[0], 999999, &hours)) return NO;
    if (!MXRCueNumber(parts[parts.count - 2], 59, &minutes)) return NO;
    NSArray<NSString *> *last = [parts.lastObject componentsSeparatedByCharactersInSet:
        [NSCharacterSet characterSetWithCharactersInString:@".,"]];
    if (last.count != 2 || !MXRCueNumber(last[0], 59, &seconds) ||
        !last[1].length || last[1].length > 3 || !MXRCueNumber(last[1], 999, &fraction)) return NO;
    // VLC reads these fields as integer milliseconds (SRT/VTT) or
    // centiseconds (ASS/SSA), including shorter accepted field widths.
    fraction *= ass ? 10000 : 1000;
    *time = (int64_t)(hours * 3600 + minutes * 60 + seconds) * 1000000 + fraction;
    return YES;
}

static NSString *MXRCueText(NSString *text, BOOL ass)
{
    if (text.length > 4096) return @"";
    static NSRegularExpression *tags, *overrides;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tags = [NSRegularExpression regularExpressionWithPattern:@"<[^>]*>" options:0 error:NULL];
        overrides = [NSRegularExpression regularExpressionWithPattern:@"\\{[^}]*\\}" options:0 error:NULL];
    });
    NSRegularExpression *markup = ass ? overrides : tags;
    text = [markup stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@""];
    if (ass) {
        text = [text stringByReplacingOccurrencesOfString:@"\\N" withString:@"\n"];
        text = [text stringByReplacingOccurrencesOfString:@"\\n" withString:@"\n"];
        text = [text stringByReplacingOccurrencesOfString:@"\\h" withString:@" "];
    } else {
        for (NSString *entity in @[@"&lt;", @"&gt;", @"&nbsp;", @"&amp;"])
            text = [text stringByReplacingOccurrencesOfString:entity withString:
                (@{@"&lt;": @"<", @"&gt;": @">", @"&nbsp;": @" ", @"&amp;": @"&"})[entity]];
    }
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static void MXRAddSubtitleCue(NSMutableArray *cues, NSString *start, NSString *end, NSString *text, BOOL ass)
{
    int64_t first, last;
    if (!MXRCueTime(start, ass, &first) || !MXRCueTime(end, ass, &last) || last <= first) return;
    text = MXRCueText(text, ass);
    if (text.length) [cues addObject:@{@"start": @(first), @"end": @(last), @"text": text}];
}

static BOOL MXRVTTKeyword(NSString *line, NSString *keyword)
{
    if (![line hasPrefix:keyword]) return NO;
    if (line.length == keyword.length) return YES;
    unichar next = [line characterAtIndex:keyword.length];
    return next == ' ' || (next >= '\t' && next <= '\r');
}

static void MXRParseCueBlock(NSArray<NSString *> *block, NSMutableArray *cues, BOOL vtt)
{
    if (!block.count) return;
    NSString *first = block[0];
    if (vtt && (MXRVTTKeyword(first, @"NOTE") || MXRVTTKeyword(first, @"STYLE") ||
                MXRVTTKeyword(first, @"REGION"))) return;
    for (NSUInteger i = 0; i < MIN((NSUInteger)2, block.count); ++i) {
        NSArray<NSString *> *timing = [block[i] componentsSeparatedByString:@"-->"];
        if (timing.count != 2) continue;
        NSString *start = [timing[0] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *tail = [timing[1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *end = [tail componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet].firstObject;
        NSArray *lines = [block subarrayWithRange:NSMakeRange(i + 1, block.count - i - 1)];
        MXRAddSubtitleCue(cues, start, end, [lines componentsJoinedByString:@"\n"], NO);
        return;
    }
}

static NSArray<NSDictionary *> *MXRParseCueData(NSData *data, NSString *format, MXRCueCancelled cancelled)
{
    format = format.lowercaseString;
    BOOL ass = [@[@"ass", @"ssa"] containsObject:format];
    if (!ass && ![@[@"srt", @"vtt"] containsObject:format]) return @[];
    if (!data.length || data.length > MXRSubtitleBytes) return @[];
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text && data.length >= 2) {
        const unsigned char *bytes = data.bytes;
        if ((bytes[0] == 0xff && bytes[1] == 0xfe) || (bytes[0] == 0xfe && bytes[1] == 0xff))
            text = [[NSString alloc] initWithData:data encoding:NSUnicodeStringEncoding];
    }
    if (!text || [text rangeOfString:@"\0"].location != NSNotFound) return @[];
    if ([text hasPrefix:@"\uFEFF"]) text = [text substringFromIndex:1];
    text = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
                  stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    if (lines.count > 100000) return @[];
    BOOL vtt = [format isEqual:@"vtt"];
    if (vtt && !MXRVTTKeyword(lines.firstObject, @"WEBVTT")) return @[];
    NSMutableArray *cues = [NSMutableArray array];
    NSMutableArray *block = [NSMutableArray array];
    BOOL events = NO;
    BOOL header = vtt;
    NSUInteger fieldCount = 10, startIndex = 1, endIndex = 2, textIndex = 9;
    for (NSString *line in lines) {
        if (cancelled && cancelled()) return @[];
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (header) { if (!trimmed.length) header = NO; continue; }
        if (!ass) {
            if (trimmed.length) [block addObject:line];
            else { MXRParseCueBlock(block, cues, vtt); [block removeAllObjects]; }
        } else if ([trimmed hasPrefix:@"["]) {
            events = [trimmed.lowercaseString isEqual:@"[events]"];
        } else if (events && [trimmed.lowercaseString hasPrefix:@"format:"]) {
            NSArray *fields = [[trimmed substringFromIndex:7] componentsSeparatedByString:@","];
            fieldCount = fields.count; startIndex = endIndex = textIndex = NSNotFound;
            for (NSUInteger i = 0; i < fieldCount; ++i) {
                NSString *field = [[fields[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] lowercaseString];
                if ([field isEqual:@"start"]) startIndex = i;
                if ([field isEqual:@"end"]) endIndex = i;
                if ([field isEqual:@"text"]) textIndex = i;
            }
        } else if (events && [trimmed.lowercaseString hasPrefix:@"dialogue:"] && fieldCount <= 32 &&
                   startIndex < fieldCount && endIndex < fieldCount && textIndex == fieldCount - 1) {
            NSString *dialogue = [trimmed substringFromIndex:9];
            NSMutableArray *fields = [NSMutableArray array];
            NSUInteger offset = 0;
            for (NSUInteger i = 1; i < fieldCount; ++i) {
                NSRange comma = [dialogue rangeOfString:@"," options:0 range:NSMakeRange(offset, dialogue.length - offset)];
                if (comma.location == NSNotFound) break;
                [fields addObject:[[dialogue substringWithRange:NSMakeRange(offset, comma.location - offset)]
                    stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];
                offset = comma.location + 1;
            }
            if (fields.count == fieldCount - 1) {
                [fields addObject:[dialogue substringFromIndex:offset]];
                MXRAddSubtitleCue(cues, fields[startIndex], fields[endIndex], fields[textIndex], YES);
            }
        }
        if (cues.count > MXRSubtitleCueLimit) return @[];
    }
    if (!ass) MXRParseCueBlock(block, cues, vtt);
    if (cues.count > MXRSubtitleCueLimit) return @[];
    [cues sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult result = [a[@"start"] compare:b[@"start"]];
        return result == NSOrderedSame ? [a[@"end"] compare:b[@"end"]] : result;
    }];
    return [cues copy];
}

NSArray<NSDictionary *> *MXRParseSubtitleCues(NSData *data, NSString *format)
{
    return MXRParseCueData(data, format, nil);
}

static NSArray *MXRReadSubtitleCues(NSURL *url, MXRCueCancelled cancelled)
{
    if (cancelled()) return @[];
    int descriptor = open(url.fileSystemRepresentation, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (descriptor < 0) return @[];
    struct stat status;
    NSMutableData *data = [NSMutableData data];
    BOOL readable = fstat(descriptor, &status) == 0 && S_ISREG(status.st_mode) &&
        status.st_size > 0 && (uint64_t)status.st_size <= MXRSubtitleBytes;
    unsigned char buffer[65536];
    while (readable && !cancelled()) {
        ssize_t count = read(descriptor, buffer, sizeof(buffer));
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) { readable = NO; break; }
        if (!count) break;
        if (data.length + (NSUInteger)count > MXRSubtitleBytes) { readable = NO; break; }
        [data appendBytes:buffer length:(NSUInteger)count];
    }
    close(descriptor);
    return readable && !cancelled() ? MXRParseCueData(data, url.pathExtension, cancelled) : @[];
}

@interface MXRCueRequest : NSObject
@property (nonatomic) uint64_t epoch, serial;
@property (nonatomic, copy) NSString *trackID;
@property (nonatomic, copy) NSString *mediaURI;
@property (nonatomic, copy) NSURL *url;
@property (nonatomic, copy) MXRCueCompletion completion;
@end
@implementation MXRCueRequest
@end

@interface MXRSubtitleCueServices ()
- (void)invalidate;
@end
static void MXRCueMediaChanged(vlc_player_t *player, input_item_t *media, void *userdata)
{
    (void)player; (void)media;
    [(__bridge MXRSubtitleCueServices *)userdata invalidate];
}
static void MXRCueTracksChanged(vlc_player_t *player, enum vlc_player_list_action action,
                               const struct vlc_player_track *track, void *userdata)
{
    (void)player; (void)action;
    if (track->fmt.i_cat == SPU_ES) [(__bridge MXRSubtitleCueServices *)userdata invalidate];
}
static void MXRCueSelectionChanged(vlc_player_t *player, vlc_es_id_t *unselected,
                                  vlc_es_id_t *selected, void *userdata)
{
    (void)player;
    if ((unselected && vlc_es_id_GetCat(unselected) == SPU_ES) || (selected && vlc_es_id_GetCat(selected) == SPU_ES))
        [(__bridge MXRSubtitleCueServices *)userdata invalidate];
}
static const struct vlc_player_cbs MXRCueCallbacks = {
    .on_current_media_changed = MXRCueMediaChanged,
    .on_track_list_changed = MXRCueTracksChanged,
    .on_track_selection_changed = MXRCueSelectionChanged,
};

@implementation MXRSubtitleCueServices {
    vlc_player_t *_player;
    vlc_player_listener_id *_listener;
    dispatch_queue_t _reader;
    NSLock *_stateLock;
    BOOL _stopped;
    uint64_t _epoch, _serial;
    NSMutableDictionary<NSNumber *, MXRCueRequest *> *_pending; // main only
}
- (instancetype)initWithPlaylist:(vlc_playlist_t *)playlist interface:(intf_thread_t *)intf
{
    (void)intf;
    NSAssert(NSThread.isMainThread, @"Subtitle cues are owned on main");
    if ((self = [super init])) {
        _player = vlc_playlist_GetPlayer(playlist);
        _reader = dispatch_queue_create("org.vlc.macosx-redesign.subtitle-cues", DISPATCH_QUEUE_SERIAL);
        _stateLock = [[NSLock alloc] init];
        _pending = [NSMutableDictionary dictionary];
        vlc_player_Lock(_player);
        _listener = vlc_player_AddListener(_player, &MXRCueCallbacks, (__bridge void *)self);
        vlc_player_Unlock(_player);
    }
    return self;
}
- (NSDictionary *)capabilities { return @{@"supportsSubtitleTimeline": _listener ? @YES : @NO}; }
- (void)invalidate { [_stateLock lock]; ++_epoch; [_stateLock unlock]; }
- (BOOL)cancelled:(MXRCueRequest *)request
{
    [_stateLock lock];
    BOOL cancelled = _stopped || request.epoch != _epoch || request.serial != _serial;
    [_stateLock unlock];
    return cancelled;
}
/// Caller holds the player lock. Never infer association from track names or slave order.
- (NSURL *)urlForTrack:(NSString *)identifier mediaURI:(NSString **)mediaURI
{
    input_item_t *media = vlc_player_GetCurrentMedia(_player);
    if (!media) return nil;
    BOOL selected = NO;
    for (size_t i = 0; i < vlc_player_GetTrackCount(_player, SPU_ES); ++i) {
        const struct vlc_player_track *track = vlc_player_GetTrackAt(_player, SPU_ES, i);
        const char *trackID = vlc_es_id_GetStrId(track->es_id);
        if (track->selected && trackID && [identifier isEqualToString:[NSString stringWithUTF8String:trackID]]) { selected = YES; break; }
    }
    if (!selected) return nil;
    char *uri = input_item_GetURI(media);
    *mediaURI = uri ? [NSString stringWithUTF8String:uri] : @"";
    free(uri);
    NSURL *url;
    vlc_mutex_lock(&media->lock);
    for (int i = 0; i < media->i_slaves; ++i) {
        input_item_slave_t *slave = media->pp_slaves[i];
        if (slave->i_type != SLAVE_TYPE_SPU) continue;
        vlc_hash_md5_t hash;
        char digest[VLC_HASH_MD5_DIGEST_HEX_SIZE];
        vlc_hash_md5_Init(&hash);
        vlc_hash_md5_Update(&hash, slave->psz_uri, strlen(slave->psz_uri));
        vlc_hash_FinishHex(&hash, digest);
        NSString *prefix = [[NSString stringWithUTF8String:digest] stringByAppendingString:@"/spu/"];
        if ([identifier hasPrefix:prefix]) {
            url = [NSURL URLWithString:[NSString stringWithUTF8String:slave->psz_uri]];
            break;
        }
    }
    vlc_mutex_unlock(&media->lock);
    BOOL localHost = !url.host.length || [url.host.lowercaseString isEqual:@"localhost"];
    return url.isFileURL && localHost && [@[@"srt", @"vtt", @"ass", @"ssa"] containsObject:url.pathExtension.lowercaseString] ? url : nil;
}
- (void)complete:(MXRCueRequest *)request cues:(NSArray *)cues
{
    NSAssert(NSThread.isMainThread, @"Subtitle completion uses main");
    if (_pending[@(request.serial)] != request) return;
    [_pending removeObjectForKey:@(request.serial)];
    BOOL stale = [self cancelled:request];
    if (!stale) {
        NSString *mediaURI;
        vlc_player_Lock(_player);
        NSURL *current = [self urlForTrack:request.trackID mediaURI:&mediaURI];
        stale = [self cancelled:request] || ![current isEqual:request.url] || ![mediaURI isEqual:request.mediaURI];
        vlc_player_Unlock(_player);
    }
    request.completion(@{@"cues": stale ? @[] : cues}, nil);
}
- (void)request:(MXRBridgeRequest)request service:(MXRBridgeService)service arguments:(NSDictionary *)arguments
      completion:(MXRCueCompletion)completion
{
    NSAssert(NSThread.isMainThread, @"Subtitle requests originate on main");
    if (![service isEqual:MXRBridgeServicePlayer] || ![request isEqual:MXRBridgeRequestSubtitleCues]) {
        completion(nil, MXRCueError(ENOTSUP, @"Unknown subtitle-cue request.")); return;
    }
    NSString *identifier = arguments[@"id"];
    if (![identifier isKindOfClass:NSString.class]) { completion(nil, MXRCueError(EINVAL, @"A subtitle track ID is required.")); return; }
    [_stateLock lock];
    BOOL stopped = _stopped;
    uint64_t serial = ++_serial;
    [_stateLock unlock];
    if (stopped) { completion(nil, MXRCueError(NSUserCancelledError, @"Subtitle cues have stopped.")); return; }
    NSString *mediaURI;
    vlc_player_Lock(_player);
    NSURL *url = _listener ? [self urlForTrack:identifier mediaURI:&mediaURI] : nil;
    [_stateLock lock]; uint64_t epoch = _epoch; [_stateLock unlock];
    vlc_player_Unlock(_player);
    if (!url) { completion(@{@"cues": @[]}, nil); return; }
    MXRCueRequest *context = [[MXRCueRequest alloc] init];
    context.epoch = epoch; context.serial = serial; context.trackID = identifier;
    context.mediaURI = mediaURI ?: @""; context.url = url; context.completion = completion;
    _pending[@(serial)] = context;
    dispatch_async(_reader, ^{
        @autoreleasepool {
            NSArray *cues = MXRReadSubtitleCues(url, ^BOOL { return [self cancelled:context]; });
            dispatch_async(dispatch_get_main_queue(), ^{ [self complete:context cues:cues]; });
        }
    });
}
- (void)shutdown
{
    NSAssert(NSThread.isMainThread, @"Subtitle shutdown begins on main");
    [_stateLock lock]; _stopped = YES; ++_epoch; [_stateLock unlock];
    if (_listener) {
        vlc_player_Lock(_player);
        vlc_player_RemoveListener(_player, _listener); _listener = NULL;
        vlc_player_Unlock(_player);
    }
    _player = NULL;
    NSArray *requests = _pending.allValues;
    [_pending removeAllObjects];
    for (MXRCueRequest *request in requests)
        request.completion(nil, MXRCueError(NSUserCancelledError, @"Subtitle cues have stopped."));
}
- (void)finishShutdown
{
    NSAssert(!NSThread.isMainThread, @"Subtitle reader joins off-main");
    dispatch_sync(_reader, ^{});
}
@end
