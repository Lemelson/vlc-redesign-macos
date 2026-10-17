/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#import <Foundation/Foundation.h>
#import "MXRBridgeKeys.h"
#include <stdatomic.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_input_item.h>
#include <vlc_player.h>
#include <vlc_playlist.h>
#include <vlc_extensions.h>
#include <vlc_modules.h>
#include <vlc_configuration.h>
#include <vlc_renderer_discovery.h>
#import "MXRMediaServices.h"

static NSError *MXRMediaError(NSInteger code, NSString *message)
{
    return [NSError errorWithDomain:@"MXRVLCBridge" code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *MXRText(const char *value)
{
    return value != NULL ? ([NSString stringWithUTF8String:value] ?: @"") : @"";
}

static NSString *MXRArgument(NSDictionary *arguments, NSString *key)
{
    id value = arguments[key];
    return [value isKindOfClass:NSString.class] ? value : nil;
}

/* Directory descriptors keep local extension operations inside the configured user
 * directory. Lua/extension directory symlinks and final-file symlinks are refused. */
static int MXROpenExtensionDirectory(NSURL *userDirectory, BOOL create, NSError **error)
{
    if (userDirectory == nil) {
        if (error != NULL) *error = MXRMediaError(ENOTSUP, @"VLC's user extension folder is unavailable.");
        return -1;
    }
    if (create && ![NSFileManager.defaultManager createDirectoryAtURL:userDirectory
        withIntermediateDirectories:YES attributes:nil error:error]) return -1;
    int directory = open(userDirectory.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    for (NSString *component in @[@"lua", @"extensions"]) {
        if (directory < 0) break;
        if (create && mkdirat(directory, component.fileSystemRepresentation, 0700) != 0 && errno != EEXIST) {
            int code = errno; close(directory); directory = -1; errno = code; break;
        }
        int child = openat(directory, component.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        int code = errno;
        close(directory); directory = child; errno = code;
    }
    if (directory < 0 && error != NULL)
        *error = MXRMediaError(errno, @"VLC's user extension folder cannot be opened safely. Check its permissions and directory links.");
    return directory;
}

static BOOL MXRUserExtension(NSString *path, int directory, struct stat *info)
{
    if (directory < 0 || !path.isAbsolutePath || ![path.pathExtension isEqual:@"lua"] ||
        [path.pathComponents containsObject:@".."] || [path.pathComponents containsObject:@"."] ||
        [path rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return NO;
    int parent = open(path.stringByDeletingLastPathComponent.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (parent < 0) return NO;
    struct stat parentInfo, directoryInfo;
    BOOL sameDirectory = fstat(parent, &parentInfo) == 0 && fstat(directory, &directoryInfo) == 0 &&
        parentInfo.st_dev == directoryInfo.st_dev && parentInfo.st_ino == directoryInfo.st_ino;
    close(parent);
    if (!sameDirectory) return NO;
    return fstatat(directory, path.lastPathComponent.fileSystemRepresentation, info, AT_SYMLINK_NOFOLLOW) == 0 &&
        S_ISREG(info->st_mode) && info->st_uid == geteuid();
}

static BOOL MXRUnlinkExtension(int directory, NSString *name, const struct stat *expected)
{
    struct stat current;
    if (fstatat(directory, name.fileSystemRepresentation, &current, AT_SYMLINK_NOFOLLOW) != 0 ||
        !S_ISREG(current.st_mode) || current.st_dev != expected->st_dev || current.st_ino != expected->st_ino) {
        errno = ESTALE; return NO;
    }
    return unlinkat(directory, name.fileSystemRepresentation, 0) == 0;
}

static BOOL MXRCopyExtension(int source, int directory, NSString *name, struct stat *installed, NSError **error)
{
    NSString *temporary = [NSString stringWithFormat:@".mxr-%@.tmp", NSUUID.UUID.UUIDString];
    int output = openat(directory, temporary.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (output < 0) { *error = MXRMediaError(errno, @"VLC could not create a staged extension file."); return NO; }
    BOOL copied = YES;
    int code = 0;
    char bytes[65536];
    for (;;) {
        ssize_t count = read(source, bytes, sizeof(bytes));
        if (count < 0 && errno == EINTR) continue;
        if (count == 0) break;
        if (count < 0) { copied = NO; code = errno; break; }
        for (ssize_t offset = 0; offset < count;) {
            ssize_t written = write(output, bytes + offset, (size_t)(count - offset));
            if (written < 0 && errno == EINTR) continue;
            if (written <= 0) { copied = NO; code = written == 0 ? EIO : errno; break; }
            offset += written;
        }
        if (!copied) break;
    }
    if (copied && (fchmod(output, 0644) != 0 || fsync(output) != 0 || fstat(output, installed) != 0)) { copied = NO; code = errno; }
    close(output);
    /* linkat is an atomic no-replace operation; a destination link/file is never overwritten. */
    if (copied && linkat(directory, temporary.fileSystemRepresentation, directory, name.fileSystemRepresentation, 0) != 0) {
        copied = NO; code = errno;
    }
    unlinkat(directory, temporary.fileSystemRepresentation, 0);
    if (!copied) *error = MXRMediaError(code, code == EEXIST ? @"An extension with this filename is already installed." : @"VLC could not copy the extension file.");
    return copied;
}

static NSString *MXRQuoted(NSString *value)
{
    char *escaped = config_StringEscape(value.UTF8String);
    if (escaped == NULL) return nil;
    NSString *result = [NSString stringWithFormat:@"\"%@\"", MXRText(escaped)];
    free(escaped);
    return result;
}

NSDictionary *MXRCreateOutputDefinition(NSDictionary *arguments, NSError **error)
{
    if (error != NULL) *error = nil;
    NSString *sourceText = MXRArgument(arguments, @"sourceURL");
    NSURL *source = sourceText.length > 0 ? [NSURL URLWithString:sourceText] : nil;
    NSString *mode = MXRArgument(arguments, @"mode") ?: @"convert";
    NSString *profile = MXRArgument(arguments, @"profile") ?: @"copy";
    NSString *message = nil;
    if (source.scheme.length == 0)
        message = @"Choose a valid source URL.";
    else if (![@[@"copy", @"h264", @"audio", @"aac", @"wav"] containsObject:profile])
        message = @"This output profile is unavailable.";
    else if (![@[@"convert", @"stream"] containsObject:mode])
        message = @"Choose conversion or streaming.";

    NSString *destinationText = MXRArgument(arguments, [mode isEqual:@"stream"] ? @"streamURL" : @"destinationURL");
    NSURLComponents *components = destinationText.length > 0 ? [NSURLComponents componentsWithString:destinationText] : nil;
    NSURL *destination = components.URL;
    NSString *output = nil, *partial = nil;
    if (message == nil && [mode isEqual:@"convert"]) {
        if (!destination.isFileURL || destination.path.length == 0)
            message = @"Choose a local output file.";
        else if (source.isFileURL && [[source.URLByResolvingSymlinksInPath URLByStandardizingPath]
                    isEqual:[destination.URLByResolvingSymlinksInPath URLByStandardizingPath]])
            message = @"The output file must differ from the source.";
        else {
            /* SD-19: the formats this build converts reliably (verified with test media). */
            NSString *mux = @{@"audio": @"raw", @"h264": @"mp4", @"aac": @"mp4", @"wav": @"wav"}[profile] ?: @"ts";
            /* VLC writes a hidden file next to the destination; the job renames it over the
             * destination only when the conversion ends naturally (J-11), so a stopped or failed
             * job never leaves a truncated file where the user's file was. */
            partial = [destination.path.stringByDeletingLastPathComponent stringByAppendingPathComponent:
                       [NSString stringWithFormat:@".%@.%@.vlc-partial", destination.lastPathComponent,
                        [NSUUID.UUID.UUIDString substringToIndex:8]]];
            output = [NSString stringWithFormat:@"standard{access=file{no-overwrite},mux=%@,dst=%@}", mux, MXRQuoted(partial)];
        }
    } else if (message == nil) {
        NSString *scheme = components.scheme.lowercaseString;
        NSInteger port = components.port.integerValue;
        if (![@[@"udp", @"rtp", @"http"] containsObject:scheme] || components.host.length == 0 || port <= 0 || port > 65535)
            message = @"Use a UDP, RTP or HTTP URL with an explicit port.";
        else if (components.user != nil || components.password != nil || components.query != nil || components.fragment != nil)
            message = @"Stream destinations cannot contain credentials, a query or a fragment.";
        else if ([@[@"audio", @"aac", @"wav"] containsObject:profile])
            message = @"Audio-only formats are available for conversion to a file.";
        else if (![scheme isEqual:@"http"] && components.path.length > 0 && ![components.path isEqual:@"/"])
            message = @"UDP and RTP destinations cannot contain a path.";
        else {
            NSString *host = components.host;
            if ([host containsString:@":"] && ![host hasPrefix:@"["]) host = [NSString stringWithFormat:@"[%@]", host];
            if ([scheme isEqual:@"rtp"])
                output = [NSString stringWithFormat:@"rtp{mux=ts,dst=%@,port=%ld}", MXRQuoted(host), (long)port];
            else {
                NSString *target = [NSString stringWithFormat:@"%@:%ld%@", host, (long)port,
                                   [scheme isEqual:@"http"] ? (components.percentEncodedPath ?: @"") : @""];
                output = [scheme isEqual:@"udp"] ? [NSString stringWithFormat:@"udp{dst=%@}", MXRQuoted(target)] :
                         [NSString stringWithFormat:@"standard{access=http,mux=ts,dst=%@}", MXRQuoted(target)];
            }
        }
    }
    if (message != nil) {
        if (error != NULL) *error = MXRMediaError(EINVAL, message);
        return nil;
    }
    /* D036: `no-forward-pcr` keeps transcode's PCR synchroniser out of the chain. With audio and
     * video both transcoded it asserts (pcr_sync.c: an ES added after a PCR event is indexed past
     * that event's entries) and aborts the process; the file and TS muxers time their output from
     * the frames themselves. `venc=x264` because the VideoToolbox encoder ignores `vb` (a 2.9 Mbit/s
     * source came out at 14 Mbit/s) and sends its parameter sets only once, so a viewer joining an
     * HTTP stream later never decodes a picture. A keyframe every 60 frames lets a viewer that
     * joins a stream see a picture within about two seconds. */
    NSString *transcode = @{@"h264": @"transcode{venc=x264{keyint=60},vcodec=h264,vb=2500,acodec=mp4a,ab=192,no-forward-pcr}:",
                            @"audio": @"transcode{vcodec=none,acodec=mp3,ab=192,no-forward-pcr}:",
                            @"aac": @"transcode{vcodec=none,acodec=mp4a,ab=192,no-forward-pcr}:",
                            @"wav": @"transcode{vcodec=none,acodec=s16l,no-forward-pcr}:"}[profile] ?: @"";
    NSMutableDictionary *definition = [@{@"sourceURL": source.absoluteString, @"destinationURL": destination.absoluteString,
             @"mode": mode, @"profile": profile, @"sout": [NSString stringWithFormat:@"#%@%@", transcode, output]} mutableCopy];
    if (partial != nil) definition[@"partialPath"] = partial;
    return definition;
}

/* Snapshot policy on every new job, never inherit cached output-player variables.
 * Explicit # chains bypass VLC's sout-display URL shorthand, so duplicate before
 * transcoding: local playback receives the original elementary streams. "Play locally
 * while streaming" is for streams only: a conversion runs faster than real time
 * (clock-synchro=0), so a local copy of it would be unwatchable. */
NSArray<NSString *> *MXROutputOptions(NSDictionary *definition, NSDictionary<NSString *, NSNumber *> *settings)
{
    NSString *chain = definition[@"sout"];
    BOOL stream = [definition[@"mode"] isEqual:@"stream"];
    if (stream && [settings[@"sout-display"] boolValue]) {
        NSString *destination = [chain hasPrefix:@"#"] ? [chain substringFromIndex:1] : chain;
        chain = [NSString stringWithFormat:@"#duplicate{dst=display,dst=%@}", MXRQuoted(destination)];
    }
    BOOL keep = stream && [settings[@"sout-keep"] boolValue];
    NSMutableArray *options = [NSMutableArray arrayWithObjects:[@"sout=" stringByAppendingString:chain],
                               keep ? @"sout-keep" : @"no-sout-keep", @"no-sout-display", nil];
    /* Audio formats keep only the sound: `vcodec=none` drops the picture but not the source's
     * subtitles (an embedded track or an auto-loaded sidecar would be muxed as mov_text). */
    BOOL audioOnly = [@[@"audio", @"aac", @"wav"] containsObject:definition[@"profile"]];
    for (NSString *name in @[@"sout-audio", @"sout-video", @"sout-spu"]) {
        BOOL include = [settings[name] boolValue] && (!audioOnly || [name isEqual:@"sout-audio"]);
        [options addObject:include ? name : [@"no-" stringByAppendingString:name]];
    }
    return options;
}

@interface MXROutputJob : NSObject
@property (nonatomic) input_item_t *media;
@property (nonatomic, strong) NSMutableDictionary *record;
@property (nonatomic) BOOL ended;
@property (nonatomic) BOOL cancelRequested;
@property (nonatomic) enum vlc_player_media_stopping_reason reason;
@property (nonatomic, copy) NSString *partialPath;
@property (nonatomic) BOOL overwrite;
@end
@implementation MXROutputJob
- (void)dealloc { if (_media != NULL) input_item_Release(_media); }
@end

@interface MXRRendererReference : NSObject
@property (nonatomic) vlc_renderer_item_t *item;
@property (nonatomic, strong) NSDictionary *record;
@end
@implementation MXRRendererReference
- (void)dealloc { if (_item != NULL) vlc_renderer_item_release(_item); }
@end

@interface MXRMediaServices ()
- (void)outputState:(enum vlc_player_state)state media:(input_item_t *)media;
- (void)outputStopping:(input_item_t *)media reason:(enum vlc_player_media_stopping_reason)reason;
- (void)outputPosition:(float)position;
- (void)rendererAdded:(vlc_renderer_item_t *)item;
- (void)rendererRemoved:(vlc_renderer_item_t *)item;
- (void)rendererSelected:(vlc_renderer_item_t *)item;
@end

static void MXROutputState(vlc_player_t *player, enum vlc_player_state state, void *data)
{
    MXRMediaServices *owner = (__bridge MXRMediaServices *)data;
    input_item_t *media = vlc_player_GetCurrentMedia(player);
    if (media != NULL) input_item_Hold(media);
    dispatch_async(dispatch_get_main_queue(), ^{
        [owner outputState:state media:media];
        if (media != NULL) input_item_Release(media);
    });
}
static void MXROutputStopping(vlc_player_t *player, input_item_t *media,
                              enum vlc_player_media_stopping_reason reason, void *data)
{
    VLC_UNUSED(player);
    MXRMediaServices *owner = (__bridge MXRMediaServices *)data;
    input_item_Hold(media);
    dispatch_async(dispatch_get_main_queue(), ^{
        [owner outputStopping:media reason:reason];
        input_item_Release(media);
    });
}
static void MXROutputPosition(vlc_player_t *player, vlc_tick_t time, double position, void *data)
{
    VLC_UNUSED(player); VLC_UNUSED(time);
    MXRMediaServices *owner = (__bridge MXRMediaServices *)data;
    dispatch_async(dispatch_get_main_queue(), ^{ [owner outputPosition:position]; });
}
static const struct vlc_player_cbs MXROutputCallbacks = {
    .on_state_changed = MXROutputState,
    .on_stopping_current_media = MXROutputStopping,
    .on_position_changed = MXROutputPosition,
};
static void MXRRendererAdded(vlc_renderer_discovery_t *discovery, vlc_renderer_item_t *item)
{
    MXRMediaServices *owner = (__bridge MXRMediaServices *)discovery->owner.sys;
    vlc_renderer_item_hold(item);
    dispatch_async(dispatch_get_main_queue(), ^{
        [owner rendererAdded:item];
        vlc_renderer_item_release(item);
    });
}
static void MXRRendererRemoved(vlc_renderer_discovery_t *discovery, vlc_renderer_item_t *item)
{
    MXRMediaServices *owner = (__bridge MXRMediaServices *)discovery->owner.sys;
    vlc_renderer_item_hold(item);
    dispatch_async(dispatch_get_main_queue(), ^{
        [owner rendererRemoved:item];
        vlc_renderer_item_release(item);
    });
}
static void MXRRendererSelected(vlc_player_t *player, vlc_renderer_item_t *item, void *data)
{
    VLC_UNUSED(player);
    MXRMediaServices *owner = (__bridge MXRMediaServices *)data;
    if (item != NULL) vlc_renderer_item_hold(item);
    dispatch_async(dispatch_get_main_queue(), ^{
        [owner rendererSelected:item];
        if (item != NULL) vlc_renderer_item_release(item);
    });
}
@interface MXRMediaServices ()
- (void)forEachActiveExtension:(void (^)(extensions_manager_t *manager, extension_t *extension))block then:(nullable dispatch_block_t)done;
@end
/* Active extensions follow the main player, as in the stock interfaces: the current input
 * (input listeners such as VLsub), its play state and its metadata. */
static void MXRCurrentMediaChanged(vlc_player_t *player, input_item_t *item, void *data)
{
    VLC_UNUSED(player);
    if (item != NULL) input_item_Hold(item);
    [(__bridge MXRMediaServices *)data forEachActiveExtension:^(extensions_manager_t *manager, extension_t *extension) {
        extension_SetInput(manager, extension, item);
    } then:^{ if (item != NULL) input_item_Release(item); }];
}
static void MXRPlayStateChanged(vlc_player_t *player, enum vlc_player_state state, void *data)
{
    VLC_UNUSED(player);
    [(__bridge MXRMediaServices *)data forEachActiveExtension:^(extensions_manager_t *manager, extension_t *extension) {
        extension_PlayingChanged(manager, extension, (int)state);
    } then:nil];
}
static void MXRMediaMetaChanged(vlc_player_t *player, input_item_t *item, void *data)
{
    VLC_UNUSED(player); VLC_UNUSED(item);
    [(__bridge MXRMediaServices *)data forEachActiveExtension:^(extensions_manager_t *manager, extension_t *extension) {
        extension_MetaChanged(manager, extension);
    } then:nil];
}
static const struct vlc_player_cbs MXRMainCallbacks = {
    .on_renderer_changed = MXRRendererSelected, .on_current_media_changed = MXRCurrentMediaChanged,
    .on_state_changed = MXRPlayStateChanged, .on_media_meta_changed = MXRMediaMetaChanged,
};

@implementation MXRMediaServices
{
    intf_thread_t *_intf;
    vlc_player_t *_mainPlayer;
    vlc_playlist_t *_outputPlaylist;
    vlc_player_t *_outputPlayer;
    vlc_player_listener_id *_outputListener;
    vlc_player_listener_id *_mainListener;
    dispatch_queue_t _serviceQueue;
    atomic_bool _shutDown;
    NSMutableArray<MXROutputJob *> *_jobs;
    MXROutputJob *_activeJob;
    NSString *_abandonedPartial; /* set by -shutdown, removed by -finishShutdown */
    /* Lua extensions have a serial queue of their own: a script command can hold the
     * extension's running lock for seconds (a VLsub search), and reading its menu waits for
     * it, which must never hold up conversions, renderers or quit's output cleanup. */
    dispatch_queue_t _extensionQueue;
    extensions_manager_t *_extensions; /* extension queue only */
    dispatch_source_t _extensionPoll;
    NSArray *_extensionStates; /* extension queue */
    NSArray *_moduleRecords; /* extension queue */
    NSDictionary *_extensionSnapshot; /* immutable main-thread cache */
    NSMutableArray<NSValue *> *_discoveries; /* serial service queue only */
    NSMutableDictionary<NSString *, MXRRendererReference *> *_renderers; /* main */
    NSString *_selectedRendererID;
    BOOL _discovering;
    NSUInteger _discoveryGeneration; /* main */
    BOOL _hasExtensionModule;
    BOOL _hasRendererModule;
    NSURL *_extensionUserDirectory; /* configured root, resolved once; the extension queue uses directory descriptors */
}

- (instancetype)initWithPlaylist:(vlc_playlist_t *)playlist interface:(intf_thread_t *)intf
{
    self = [super init];
    if (self == nil) return nil;
    _intf = intf;
    atomic_init(&_shutDown, false);
    _mainPlayer = vlc_playlist_GetPlayer(playlist);
    _serviceQueue = dispatch_queue_create("org.vlc.redesign.media-services", DISPATCH_QUEUE_SERIAL);
    _extensionQueue = dispatch_queue_create("org.vlc.redesign.extensions", DISPATCH_QUEUE_SERIAL);
    _jobs = [NSMutableArray array];
    _discoveries = [NSMutableArray array];
    _renderers = [NSMutableDictionary dictionary];
    char *userDirectory = config_GetUserDir(VLC_USERDATA_DIR);
    if (userDirectory != NULL && MXRText(userDirectory).isAbsolutePath)
        _extensionUserDirectory = [[NSURL fileURLWithPath:MXRText(userDirectory) isDirectory:YES].URLByResolvingSymlinksInPath URLByStandardizingPath];
    free(userDirectory);
    _extensionSnapshot = @{@"items": @[], @"modules": @[], @"available": @NO};
    size_t count = 0;
    module_t **modules = module_list_get(&count);
    for (size_t i = 0; i < count; ++i) {
        _hasExtensionModule |= module_provides(modules[i], "extension");
        _hasRendererModule |= module_provides(modules[i], "renderer_discovery");
    }
    module_list_free(modules);
    _outputPlaylist = vlc_playlist_New(VLC_OBJECT(vlc_object_instance(intf)), VLC_PLAYLIST_PREPARSING_DISABLED, 1, 0);
    if (_outputPlaylist != NULL) {
        _outputPlayer = vlc_playlist_GetPlayer(_outputPlaylist);
        /* A player is a VLC object (src/player/player.h: `obj` comes first); vlc_player.h
         * only keeps the type opaque. Its vouts inherit this flag. */
        vlc_object_t *outputObject = (vlc_object_t *)(void *)_outputPlayer;
        var_Create(outputObject, MXR_AUXILIARY_VIDEO_VAR, VLC_VAR_BOOL);
        var_SetBool(outputObject, MXR_AUXILIARY_VIDEO_VAR, true);
        vlc_playlist_Lock(_outputPlaylist);
        vlc_playlist_SetMediaStoppedAction(_outputPlaylist, VLC_PLAYLIST_MEDIA_STOPPED_STOP);
        _outputListener = vlc_player_AddListener(_outputPlayer, &MXROutputCallbacks, (__bridge void *)self);
        vlc_playlist_Unlock(_outputPlaylist);
    }
    vlc_player_Lock(_mainPlayer);
    _mainListener = vlc_player_AddListener(_mainPlayer, &MXRMainCallbacks, (__bridge void *)self);
    vlc_renderer_item_t *selected = vlc_player_GetRenderer(_mainPlayer);
    if (selected != NULL) [self rendererSelected:selected];
    vlc_player_Unlock(_mainPlayer);
    return self;
}

- (NSDictionary *)capabilities
{
    return @{@"output": @(_outputListener != NULL), @"conversion": @(_outputListener != NULL),
             @"streaming": @(_outputListener != NULL), @"extensions": @(_hasExtensionModule),
             @"extensionDialogs": @(_hasExtensionModule), @"extensionInstall": _extensionSnapshot[@"supportsInstall"] ?: @NO,
             @"extensionRemove": _extensionSnapshot[@"supportsRemove"] ?: @NO, @"extensionSearchCatalog": @NO,
             @"renderers": @(_hasRendererModule && _mainListener != NULL), @"pluginDetails": @YES};
}

- (void)dealloc
{
    assert(_outputListener == NULL && _mainListener == NULL && _outputPlaylist == NULL && _extensions == NULL);
}

- (void)changed:(MXRBridgeService)service
{
    if (!atomic_load(&_shutDown) && _serviceChanged != nil) _serviceChanged(service);
}

- (NSDictionary *)snapshotForService:(MXRBridgeService)service
{
    if ([service isEqual:MXRBridgeServiceOutput]) {
        NSMutableArray *records = [NSMutableArray array];
        for (MXROutputJob *job in _jobs) [records addObject:[job.record copy]];
        return @{@"jobs": records, @"available": @(_outputListener != NULL), @"profiles": @[
            @{@"id": @"copy", @"title": @"Keep original codecs (MPEG-TS)", @"fileExtension": @"ts"},
            @{@"id": @"h264", @"title": @"H.264 video + AAC audio", @"fileExtension": @"mp4"},
            @{@"id": @"audio", @"title": @"MP3 audio", @"fileExtension": @"mp3"},
            @{@"id": @"aac", @"title": @"AAC audio", @"fileExtension": @"m4a"},
            @{@"id": @"wav", @"title": @"WAV audio", @"fileExtension": @"wav"}]};
    }
    if ([service isEqual:MXRBridgeServiceExtensions]) return _extensionSnapshot;
    if ([service isEqual:MXRBridgeServiceRenderers]) {
        NSMutableArray *records = [NSMutableArray array];
        for (NSString *identifier in [[_renderers allKeys] sortedArrayUsingSelector:@selector(compare:)])
            [records addObject:_renderers[identifier].record];
        return @{@"items": records, @"selectedID": _selectedRendererID ?: NSNull.null,
                 @"discovering": @(_discovering), @"available": @(_hasRendererModule)};
    }
    return @{};
}

- (BOOL)performCommand:(MXRBridgeCommand)command service:(MXRBridgeService)service arguments:(NSDictionary *)arguments error:(NSError **)error
{
    if (atomic_load(&_shutDown)) {
        if (error != NULL) *error = MXRMediaError(ECANCELED, @"The VLC interface has closed.");
        return NO;
    }
    if ([service isEqual:MXRBridgeServiceOutput] && [command isEqual:MXRBridgeCommandStop]) {
        if (arguments[@"id"] != nil && arguments[@"id"] != NSNull.null && ![arguments[@"id"] isKindOfClass:NSString.class]) {
            if (error != NULL) *error = MXRMediaError(EINVAL, @"Choose a valid output job identifier.");
            return NO;
        }
        NSString *identifier = MXRArgument(arguments, @"id");
        if (_activeJob == nil || (identifier != nil && ![identifier isEqual:_activeJob.record[@"id"]])) {
            if (error != NULL) *error = MXRMediaError(ENOENT, @"The output job is no longer running.");
            return NO;
        }
        _activeJob.record[@"state"] = @"stopping";
        _activeJob.cancelRequested = YES;
        vlc_playlist_Lock(_outputPlaylist);
        vlc_playlist_Stop(_outputPlaylist);
        vlc_playlist_Unlock(_outputPlaylist);
        [self changed:MXRBridgeServiceOutput];
        return YES;
    }
    if ([service isEqual:MXRBridgeServiceRenderers] && [command isEqual:MXRBridgeCommandSelect]) {
        if (arguments[@"id"] != nil && arguments[@"id"] != NSNull.null && ![arguments[@"id"] isKindOfClass:NSString.class]) {
            if (error != NULL) *error = MXRMediaError(EINVAL, @"Choose a valid renderer identifier.");
            return NO;
        }
        NSString *identifier = MXRArgument(arguments, @"id");
        MXRRendererReference *renderer = identifier.length > 0 ? _renderers[identifier] : nil;
        if (identifier.length > 0 && renderer == nil) {
            if (error != NULL) *error = MXRMediaError(ENOENT, @"This renderer is no longer available.");
            return NO;
        }
        vlc_player_Lock(_mainPlayer);
        vlc_player_SetRenderer(_mainPlayer, renderer.item);
        vlc_player_Unlock(_mainPlayer);
        return YES;
    }
    if (error != NULL) *error = MXRMediaError(ENOTSUP, @"This service command is unavailable.");
    return NO;
}

- (NSDictionary *)startOutput:(NSDictionary *)definition arguments:(NSDictionary *)arguments error:(NSError **)error
{
    if (_outputListener == NULL) { *error = MXRMediaError(ENOTSUP, @"VLC output is unavailable."); return nil; }
    if (_activeJob != nil) { *error = MXRMediaError(EBUSY, @"Stop the current output job first."); return nil; }
    MXROutputJob *job = [MXROutputJob new];
    NSString *identifier = NSUUID.UUID.UUIDString;
    job.media = input_item_New([definition[@"sourceURL"] UTF8String], "VLC output job");
    if (job.media == NULL) { *error = MXRMediaError(ENOMEM, @"VLC could not create the output input."); return nil; }
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    for (NSString *name in @[@"sout-display", @"sout-keep", @"sout-audio", @"sout-video", @"sout-spu"])
        settings[name] = @(config_GetInt(name.UTF8String) != 0);
    NSMutableArray *options = [MXROutputOptions(definition, settings) mutableCopy];
    if ([definition[@"mode"] isEqual:@"convert"]) [options addObjectsFromArray:@[@"no-sout-transcode-audio-sync", @"clock-jitter=0", @"clock-synchro=0"]];
    id inputOptions = arguments[@"inputOptions"];
    if (inputOptions != nil) {
        if (![inputOptions isKindOfClass:NSArray.class]) { *error = MXRMediaError(EINVAL, @"Input options must be a list."); return nil; }
        for (id option in inputOptions) {
            if (![option isKindOfClass:NSString.class] || [option length] == 0) { *error = MXRMediaError(EINVAL, @"An input option is invalid."); return nil; }
            NSString *normalized = [option hasPrefix:@":"] ? [option substringFromIndex:1] : option;
            if ([normalized hasPrefix:@"sout"] || [normalized hasPrefix:@"no-sout"])
                { *error = MXRMediaError(EINVAL, @"Input options cannot override the output configuration."); return nil; }
            [options addObject:normalized];
        }
    }
    for (NSString *option in options)
        if (input_item_AddOption(job.media, option.UTF8String, VLC_INPUT_OPTION_TRUSTED) != VLC_SUCCESS)
            { *error = MXRMediaError(ENOMEM, @"VLC could not attach output options."); return nil; }
    job.record = [definition mutableCopy];
    [job.record removeObjectsForKeys:@[@"sout", @"partialPath"]];
    job.partialPath = definition[@"partialPath"];
    job.overwrite = [arguments[@"overwrite"] respondsToSelector:@selector(boolValue)] && [arguments[@"overwrite"] boolValue];
    [job.record addEntriesFromDictionary:@{@"id": identifier, @"state": @"queued", @"progress": @0}];
    _activeJob = job;
    [_jobs addObject:job];
    vlc_playlist_Lock(_outputPlaylist);
    vlc_playlist_Clear(_outputPlaylist);
    int status = vlc_playlist_InsertOne(_outputPlaylist, 0, job.media);
    if (status == VLC_SUCCESS) status = vlc_playlist_PlayAt(_outputPlaylist, 0);
    vlc_playlist_Unlock(_outputPlaylist);
    if (status != VLC_SUCCESS) {
        job.record[@"state"] = @"failed";
        job.record[@"error"] = @"VLC could not start the output job.";
        if (job.partialPath != nil) unlink(job.partialPath.fileSystemRepresentation);
        _activeJob = nil;
        *error = MXRMediaError(EIO, job.record[@"error"]);
        [self changed:MXRBridgeServiceOutput];
        return nil;
    }
    [self changed:MXRBridgeServiceOutput];
    return @{@"job": [job.record copy]};
}

- (void)outputState:(enum vlc_player_state)state media:(input_item_t *)media
{
    if (atomic_load(&_shutDown) || _activeJob == nil) return;
    if (state == VLC_PLAYER_STATE_PLAYING && media == _activeJob.media) _activeJob.record[@"state"] = @"running";
    if (state == VLC_PLAYER_STATE_STOPPED) {
        MXROutputJob *job = _activeJob;
        BOOL natural = !job.cancelRequested && job.ended && job.reason != VLC_PLAYER_MEDIA_STOPPING_ERROR &&
                       job.reason != VLC_PLAYER_MEDIA_STOPPING_USER;
        if (job.cancelRequested) job.record[@"state"] = @"cancelled";
        else if (!job.ended || job.reason == VLC_PLAYER_MEDIA_STOPPING_ERROR) {
            job.record[@"state"] = @"failed"; job.record[@"error"] = @"VLC stopped before the output finished.";
        } else if (job.reason == VLC_PLAYER_MEDIA_STOPPING_USER) job.record[@"state"] = @"cancelled";
        if (job.partialPath != nil) {
            /* The file sink is closed once the player stops: publish the partial file only when the
             * conversion ended naturally, otherwise remove it. The replace decision was made when the
             * job started (EEXIST without `overwrite`), and is applied again here atomically. */
            NSString *partial = job.partialPath, *destination = [NSURL URLWithString:job.record[@"destinationURL"]].path;
            BOOL overwrite = job.overwrite;
            dispatch_async(_serviceQueue, ^{
                struct stat info;
                BOOL produced = natural && stat(partial.fileSystemRepresentation, &info) == 0 && info.st_size > 0;
                int code = 0;
                if (produced && renamex_np(partial.fileSystemRepresentation, destination.fileSystemRepresentation,
                                           overwrite ? 0 : RENAME_EXCL) != 0) code = errno;
                if (!produced || code != 0) unlink(partial.fileSystemRepresentation);
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (atomic_load(&self->_shutDown) || self->_activeJob != job) return;
                    if (natural && produced && code == 0) { job.record[@"state"] = @"completed"; job.record[@"progress"] = @1; }
                    else if (natural) {
                        job.record[@"state"] = @"failed";
                        job.record[@"error"] = code == EEXIST ? @"The output file already exists." :
                                               produced ? @"VLC could not save the output file." : @"VLC did not produce an output file.";
                    }
                    self->_activeJob = nil;
                    [self changed:MXRBridgeServiceOutput];
                });
            });
            return;
        }
        if (natural) { job.record[@"state"] = @"completed"; job.record[@"progress"] = @1; }
        _activeJob = nil;
    }
    [self changed:MXRBridgeServiceOutput];
}
- (void)outputStopping:(input_item_t *)media reason:(enum vlc_player_media_stopping_reason)reason
{
    if (atomic_load(&_shutDown) || _activeJob.media != media) return;
    _activeJob.ended = YES; _activeJob.reason = reason;
    /* A stop the user asked for stays `stopping` until the player has closed the output:
     * the engine reports it as a USER stop, which is not the job finishing. */
    if (!_activeJob.cancelRequested) _activeJob.record[@"state"] = @"finishing";
    [self changed:MXRBridgeServiceOutput];
}
- (void)outputPosition:(float)position
{
    if (atomic_load(&_shutDown) || _activeJob == nil) return;
    double previous = [_activeJob.record[@"progress"] doubleValue];
    if (fabs(previous - position) < .005) return;
    _activeJob.record[@"progress"] = @(position);
    [self changed:MXRBridgeServiceOutput];
}

- (NSDictionary *)moduleRecord:(module_t *)module
{
    NSMutableArray *settings = [NSMutableArray array];
    unsigned count = 0;
    module_config_t *config = module_config_get(module, &count);
    for (unsigned i = 0; i < count; ++i)
        if (config[i].psz_name != NULL && config[i].psz_text != NULL)
            [settings addObject:@{@"name": MXRText(config[i].psz_name), @"title": MXRText(config[i].psz_text),
                                  @"description": MXRText(config[i].psz_longtext), @"type": @(config[i].i_type)}];
    module_config_free(config);
    return @{@"id": MXRText(module_get_object(module)), @"name": MXRText(module_GetLongName(module)),
             @"capability": MXRText(module_get_capability(module)), @"description": MXRText(module_get_help(module)),
             @"settings": settings};
}

- (BOOL)loadExtensions:(NSError **)error
{
    if (_extensions != NULL) return YES;
    /* An unavailable user directory must not prevent stock extensions from loading. */
    int directory = MXROpenExtensionDirectory(_extensionUserDirectory, YES, NULL);
    if (directory >= 0) close(directory);
    _extensions = vlc_object_create(vlc_object_instance(_intf), sizeof(*_extensions));
    if (_extensions != NULL) {
        _extensions->player = _mainPlayer;
        _extensions->p_module = module_need(_extensions, "extension", NULL, false);
        if (_extensions->p_module != NULL) {
            if (_extensionPoll == nil) {
                _extensionPoll = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _extensionQueue);
                dispatch_source_set_timer(_extensionPoll, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, NSEC_PER_SEC / 10);
                __weak MXRMediaServices *weakSelf = self;
                dispatch_source_set_event_handler(_extensionPoll, ^{
                    MXRMediaServices *owner = weakSelf;
                    if (owner == nil || atomic_load(&owner->_shutDown) || owner->_extensions == NULL) return;
                    NSArray *states = [owner extensionStates];
                    if ([states isEqual:owner->_extensionStates]) return;
                    NSDictionary *snapshot = [owner extensionCatalog];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (atomic_load(&owner->_shutDown)) return;
                        owner->_extensionSnapshot = snapshot;
                        [owner changed:MXRBridgeServiceExtensions];
                    });
                });
                dispatch_resume(_extensionPoll);
            }
            return YES;
        }
        vlc_object_delete(_extensions); _extensions = NULL;
    }
    *error = MXRMediaError(ENOTSUP, @"VLC could not load its Lua extension manager.");
    return NO;
}
- (void)unloadExtensions
{
    if (_extensions == NULL) return;
    module_unneed(_extensions, _extensions->p_module);
    vlc_object_delete(_extensions); _extensions = NULL;
}
/* Any thread: runs `block` on the extension queue for every activated extension. */
- (void)forEachActiveExtension:(void (^)(extensions_manager_t *manager, extension_t *extension))block then:(nullable dispatch_block_t)done
{
    dispatch_async(_extensionQueue, ^{
        extensions_manager_t *manager = self->_extensions;
        if (!atomic_load(&self->_shutDown) && manager != NULL) {
            vlc_mutex_lock(&manager->lock);
            for (int i = 0; i < manager->extensions.i_size; ++i) {
                extension_t *extension = ARRAY_VAL(manager->extensions, i);
                if (extension_IsActivated(manager, extension)) block(manager, extension);
            }
            vlc_mutex_unlock(&manager->lock);
        }
        if (done) done();
    });
}
/* What the published catalog depends on that a script changes on its own: activation (the
 * script's activate() finishes after the request returned) and the menu an active script
 * offers (menu() may answer differently after a menu command ran). Caller holds the lock. */
- (NSArray *)stateOfExtension:(extension_t *)extension index:(int)index menu:(NSArray *_Nullable *_Nullable)menu
{
    BOOL active = extension_IsActivated(_extensions, extension);
    NSArray *entries = nil;
    if (active && extension_HasMenu(_extensions, extension)) { int status; entries = [self menuForExtension:extension status:&status]; }
    if (menu != NULL) *menu = entries;
    return @[@(index), @(active), entries ?: NSNull.null];
}
- (NSArray *)extensionStates
{
    NSMutableArray *states = [NSMutableArray array];
    vlc_mutex_lock(&_extensions->lock);
    for (int i = 0; i < _extensions->extensions.i_size; ++i)
        [states addObject:[self stateOfExtension:ARRAY_VAL(_extensions->extensions, i) index:i menu:NULL]];
    vlc_mutex_unlock(&_extensions->lock);
    return states;
}
- (NSArray *)menuForExtension:(extension_t *)extension status:(int *)status
{
    char **titles = NULL;
    uint16_t *ids = NULL;
    NSMutableArray *menu = [NSMutableArray array];
    *status = extension_GetMenu(_extensions, extension, &titles, &ids);
    if (*status == VLC_SUCCESS && titles != NULL && ids != NULL) {
        for (size_t i = 0; titles[i] != NULL; ++i) [menu addObject:@{@"id": @(ids[i]), @"title": MXRText(titles[i])}];
    }
    if (titles != NULL) for (size_t i = 0; titles[i] != NULL; ++i) free(titles[i]);
    free(titles); free(ids);
    return menu;
}
- (NSDictionary *)extensionCatalog
{
    NSMutableArray *items = [NSMutableArray array];
    NSMutableDictionary *menus = [NSMutableDictionary dictionary];
    NSMutableArray *states = [NSMutableArray array];
    NSError *directoryError = nil;
    int directory = MXROpenExtensionDirectory(_extensionUserDirectory, NO, &directoryError);
    BOOL writable = directory >= 0 && faccessat(directory, ".", W_OK, 0) == 0;
    if (!writable && directoryError == nil) directoryError = MXRMediaError(EACCES, @"VLC's user extension folder is not writable.");
    vlc_mutex_lock(&_extensions->lock);
    for (int i = 0; i < _extensions->extensions.i_size; ++i) {
        extension_t *extension = ARRAY_VAL(_extensions->extensions, i);
        NSString *identifier = MXRText(extension->psz_name);
        /* The poll compares against exactly what this pass published, so a script that
         * finishes activating (or changes its menu) right after it is still noticed. */
        NSArray *menu = nil;
        NSArray *state = [self stateOfExtension:extension index:i menu:&menu];
        [states addObject:state];
        BOOL active = [state[1] boolValue];
        BOOL hasMenu = extension_HasMenu(_extensions, extension);
        struct stat info;
        BOOL removable = writable && MXRUserExtension(identifier, directory, &info);
        [items addObject:@{@"id": identifier, @"name": MXRText(extension->psz_title), @"author": MXRText(extension->psz_author),
            @"version": MXRText(extension->psz_version), @"url": MXRText(extension->psz_url),
            @"description": MXRText(extension->psz_description), @"summary": MXRText(extension->psz_shortdescription),
            @"active": @(active), @"isActivated": @(active), @"available": @YES, @"removable": @(removable),
            @"triggerOnly": @(extension_TriggerOnly(_extensions, extension)),
            @"hasMenu": @(hasMenu)}];
        if (menu != nil) menus[identifier] = menu;
    }
    vlc_mutex_unlock(&_extensions->lock);
    if (directory >= 0) close(directory);
    _extensionStates = states;
    if (_moduleRecords == nil) {
        NSMutableArray *modules = [NSMutableArray array];
        size_t count = 0;
        module_t **all = module_list_get(&count);
        for (size_t i = 0; i < count; ++i) [modules addObject:[self moduleRecord:all[i]]];
        module_list_free(all);
        _moduleRecords = [modules copy];
    }
    return @{@"items": items, @"modules": _moduleRecords, @"menus": menus, @"available": @YES,
             @"supportsInstall": @(writable), @"supportsRemove": @(writable), @"supportsActivation": @YES,
             @"supportsSearchCatalog": @NO, @"localUnavailableReason": directoryError.localizedDescription ?: @"",
             @"supportsDialogs": @YES, @"requiresRestartForPluginChanges": @YES};
}

- (NSDictionary *)installExtension:(NSDictionary *)arguments error:(NSError **)error
{
    NSString *text = MXRArgument(arguments, @"url");
    NSURL *source = text.length > 0 ? [NSURL URLWithString:text] : nil;
    if (!source.isFileURL || !source.path.isAbsolutePath || ![source.pathExtension isEqual:@"lua"] ||
        (source.host.length > 0 && ![source.host isEqual:@"localhost"]) || source.query != nil || source.fragment != nil ||
        [source.path rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
        *error = MXRMediaError(EINVAL, @"Choose a local .lua extension file."); return nil;
    }
    int input = open(source.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
    struct stat sourceInfo;
    if (input < 0 || fstat(input, &sourceInfo) != 0 || !S_ISREG(sourceInfo.st_mode)) {
        if (input >= 0) close(input);
        *error = MXRMediaError(EINVAL, @"Choose a regular Lua file, without a symbolic link."); return nil;
    }
    int directory = MXROpenExtensionDirectory(_extensionUserDirectory, YES, error);
    if (directory < 0) { close(input); return nil; }
    struct stat installed;
    BOOL copied = MXRCopyExtension(input, directory, source.lastPathComponent, &installed, error);
    close(input);
    if (!copied) { close(directory); return nil; }
    if (atomic_load(&_shutDown)) {
        MXRUnlinkExtension(directory, source.lastPathComponent, &installed); close(directory);
        *error = MXRMediaError(ECANCELED, @"The VLC interface has closed."); return nil;
    }
    [self unloadExtensions]; /* VLC deactivates and joins every running Lua thread. */
    NSError *loadError = nil;
    NSDictionary *catalog = [self loadExtensions:&loadError] ? [self extensionCatalog] : nil;
    BOOL discovered = NO;
    for (NSDictionary *record in catalog[@"items"]) {
        NSString *identifier = record[@"id"];
        struct stat info;
        if ([identifier.lastPathComponent isEqual:source.lastPathComponent] && MXRUserExtension(identifier, directory, &info) &&
            info.st_dev == installed.st_dev && info.st_ino == installed.st_ino) { discovered = YES; break; }
    }
    if (!discovered) {
        [self unloadExtensions];
        BOOL rolledBack = MXRUnlinkExtension(directory, source.lastPathComponent, &installed);
        NSError *ignored = nil; [self loadExtensions:&ignored];
        *error = MXRMediaError(EINVAL, rolledBack ? (loadError.localizedDescription ?: @"VLC could not load this Lua extension. The copied file was removed.") :
            @"VLC could not load this Lua extension, and its copied file changed before rollback. Review the user extension folder.");
        close(directory); return nil;
    }
    close(directory);
    return catalog;
}

- (NSDictionary *)removeExtension:(NSString *)identifier error:(NSError **)error
{
    int directory = MXROpenExtensionDirectory(_extensionUserDirectory, NO, error);
    if (directory < 0) return nil;
    struct stat original;
    if (!MXRUserExtension(identifier, directory, &original)) {
        close(directory);
        *error = MXRMediaError(EPERM, @"Only regular Lua files in VLC's user extension folder can be removed. Stock extensions and symbolic links are preserved."); return nil;
    }
    [self unloadExtensions]; /* Joins active extensions before their file is unlinked. */
    BOOL removed = MXRUnlinkExtension(directory, identifier.lastPathComponent, &original);
    int code = errno; close(directory);
    NSError *loadError = nil;
    BOOL loaded = [self loadExtensions:&loadError];
    if (!removed) { *error = MXRMediaError(code, @"The extension file changed or could not be removed. No replacement file was deleted."); return nil; }
    if (!loaded) { *error = MXRMediaError(EIO, @"The extension file was removed, but VLC could not reload its extension manager."); return nil; }
    return [self extensionCatalog];
}

- (NSDictionary *)extensionRequest:(MXRBridgeRequest)request arguments:(NSDictionary *)arguments error:(NSError **)error
{
    if (![@[MXRBridgeRequestList, MXRBridgeRequestRescan, MXRBridgeRequestDetails, MXRBridgeRequestModuleDetails, MXRBridgeRequestActivate, MXRBridgeRequestDeactivate, MXRBridgeRequestTrigger, MXRBridgeRequestMenu, MXRBridgeRequestTriggerMenu, MXRBridgeRequestInstallExtension, MXRBridgeRequestRemoveExtension] containsObject:request])
        { *error = MXRMediaError(ENOTSUP, @"This extension action is unavailable."); return nil; }
    NSString *identifier = MXRArgument(arguments, @"id");
    if ([request isEqual:MXRBridgeRequestModuleDetails]) {
        size_t count = 0; module_t **modules = module_list_get(&count); NSDictionary *result = nil;
        for (size_t i = 0; i < count; ++i)
            if ([identifier isEqual:MXRText(module_get_object(modules[i]))]) { result = [self moduleRecord:modules[i]]; break; }
        module_list_free(modules);
        if (result == nil) *error = MXRMediaError(ENOENT, @"The module is no longer installed.");
        return result;
    }
    if ([request isEqual:MXRBridgeRequestRescan]) { [self unloadExtensions]; _moduleRecords = nil; }
    if (![self loadExtensions:error]) return nil;
    if ([@[MXRBridgeRequestList, MXRBridgeRequestRescan] containsObject:request]) return [self extensionCatalog];
    if ([request isEqual:MXRBridgeRequestInstallExtension]) return [self installExtension:arguments error:error];
    extension_t *extension = NULL;
    vlc_mutex_lock(&_extensions->lock);
    for (int i = 0; i < _extensions->extensions.i_size; ++i) {
        extension_t *candidate = ARRAY_VAL(_extensions->extensions, i);
        if ([identifier isEqual:MXRText(candidate->psz_name)]) { extension = candidate; break; }
    }
    vlc_mutex_unlock(&_extensions->lock);
    if (extension == NULL) { *error = MXRMediaError(ENOENT, @"The extension is no longer installed."); return nil; }
    if ([request isEqual:MXRBridgeRequestRemoveExtension]) return [self removeExtension:identifier error:error];
    if ([request isEqual:MXRBridgeRequestDetails]) {
        for (NSDictionary *record in [self extensionCatalog][@"items"]) if ([record[@"id"] isEqual:identifier]) return record;
    }
    /* Dialogs the scripts open are drawn by MXRDialogServices (the extension dialog provider). */
    int status = VLC_EGENERIC;
    if ([request isEqual:MXRBridgeRequestActivate] || [request isEqual:MXRBridgeRequestTrigger]) {
        /* An on-demand script runs once, synchronously here (extension_Trigger); any other one
         * starts its own thread and stays active until deactivated. */
        if (extension_TriggerOnly(_extensions, extension)) status = extension_Trigger(_extensions, extension);
        else if (extension_IsActivated(_extensions, extension)) status = VLC_SUCCESS;
        else {
            status = extension_Activate(_extensions, extension);
            if (status == VLC_SUCCESS) {
                vlc_player_Lock(_mainPlayer);
                input_item_t *item = vlc_player_GetCurrentMedia(_mainPlayer);
                if (item != NULL) input_item_Hold(item);
                vlc_player_Unlock(_mainPlayer);
                extension_SetInput(_extensions, extension, item);
                if (item != NULL) input_item_Release(item);
            }
        }
    }
    else if ([request isEqual:MXRBridgeRequestTriggerMenu]) {
        id menuID = arguments[@"menuID"];
        if (![menuID isKindOfClass:NSNumber.class] || [menuID integerValue] < 0 || [menuID integerValue] > UINT16_MAX) {
            *error = MXRMediaError(EINVAL, @"This extension menu item is unavailable."); return nil;
        }
        status = extension_TriggerMenu(_extensions, extension, (uint16_t)[menuID integerValue]);
    }
    else if ([request isEqual:MXRBridgeRequestDeactivate]) {
        if (extension_TriggerOnly(_extensions, extension)) { *error = MXRMediaError(ENOTSUP, @"This extension runs once and cannot be deactivated."); return nil; }
        status = extension_Deactivate(_extensions, extension);
    }
    else if ([request isEqual:MXRBridgeRequestMenu]) {
        NSArray *menu = [self menuForExtension:extension status:&status];
        if (status == VLC_SUCCESS) return @{@"items": menu};
    } else { *error = MXRMediaError(ENOTSUP, @"This extension action is unavailable."); return nil; }
    if (status != VLC_SUCCESS) { *error = MXRMediaError(EIO, @"VLC could not perform the extension action."); return nil; }
    return [self extensionCatalog];
}

/* A renderer keeps its identifier across rediscovery (J-10): the same device is announced again as
 * a new item, and its type and stream-output target (host and port) are what identify it. */
static NSString *MXRRendererIdentifier(vlc_renderer_item_t *item)
{
    return [NSString stringWithFormat:@"renderer:%@:%@", MXRText(vlc_renderer_item_type(item)), MXRText(vlc_renderer_item_sout(item))];
}
- (void)rendererAdded:(vlc_renderer_item_t *)item
{
    if (atomic_load(&_shutDown)) return;
    NSString *identifier = MXRRendererIdentifier(item);
    MXRRendererReference *reference = [MXRRendererReference new];
    reference.item = vlc_renderer_item_hold(item);
    int flags = vlc_renderer_item_flags(item);
    reference.record = @{@"id": identifier, @"name": MXRText(vlc_renderer_item_name(item)),
        @"type": MXRText(vlc_renderer_item_type(item)), @"iconURL": MXRText(vlc_renderer_item_icon_uri(item)),
        @"canAudio": @((flags & VLC_RENDERER_CAN_AUDIO) != 0), @"canVideo": @((flags & VLC_RENDERER_CAN_VIDEO) != 0)};
    _renderers[identifier] = reference;
    [self changed:MXRBridgeServiceRenderers];
}
- (void)rendererRemoved:(vlc_renderer_item_t *)item
{
    if (atomic_load(&_shutDown)) return;
    NSString *identifier = MXRRendererIdentifier(item);
    if (_renderers[identifier].item != item) return; /* an older announcement of a device seen again */
    [_renderers removeObjectForKey:identifier];
    [self changed:MXRBridgeServiceRenderers];
}
- (void)rendererSelected:(vlc_renderer_item_t *)item
{
    if (atomic_load(&_shutDown)) return;
    _selectedRendererID = item != NULL ? MXRRendererIdentifier(item) : nil;
    if (item != NULL && _renderers[_selectedRendererID] == nil) {
        /* The player's renderer stays listed (and checked) while discovery restarts. */
        [self rendererAdded:item];
        return;
    }
    [self changed:MXRBridgeServiceRenderers];
}
- (NSDictionary *)discoverRenderers:(NSError **)error
{
    for (NSValue *value in _discoveries) vlc_rd_release(value.pointerValue);
    [_discoveries removeAllObjects];
    char **names = NULL, **longNames = NULL;
    if (vlc_rd_get_names(_intf, &names, &longNames) != VLC_SUCCESS) {
        *error = MXRMediaError(ENOTSUP, @"VLC has no renderer discovery module."); return nil;
    }
    struct vlc_renderer_discovery_owner owner = {
        .sys = (__bridge void *)self, .item_added = MXRRendererAdded, .item_removed = MXRRendererRemoved,
    };
    NSMutableArray *modules = [NSMutableArray array];
    for (size_t i = 0; names[i] != NULL; ++i) {
        vlc_renderer_discovery_t *discovery = vlc_rd_new(VLC_OBJECT(vlc_object_instance(_intf)), names[i], &owner);
        if (discovery != NULL) {
            [_discoveries addObject:[NSValue valueWithPointer:discovery]];
            [modules addObject:@{@"id": MXRText(names[i]), @"name": MXRText(longNames[i])}];
        }
        free(names[i]); free(longNames[i]);
    }
    free(names); free(longNames);
    if (_discoveries.count == 0) { *error = MXRMediaError(ENOTSUP, @"VLC could not start renderer discovery."); return nil; }
    return @{@"modules": modules, @"discovering": @YES};
}

- (void)request:(MXRBridgeRequest)request service:(MXRBridgeService)service arguments:(NSDictionary *)arguments completion:(void (^)(NSDictionary<NSString *, id> * _Nullable, NSError * _Nullable))completion
{
    if (atomic_load(&_shutDown)) { completion(nil, MXRMediaError(ECANCELED, @"The VLC interface has closed.")); return; }
    if ([service isEqual:MXRBridgeServiceOutput] && [request isEqual:MXRBridgeRequestStart]) {
        dispatch_async(_serviceQueue, ^{
            if (atomic_load(&self->_shutDown)) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, MXRMediaError(ECANCELED, @"The VLC interface has closed.")); });
                return;
            }
            NSError *error = nil;
            NSDictionary *definition = MXRCreateOutputDefinition(arguments, &error);
            if ([definition[@"mode"] isEqual:@"convert"]) {
                NSURL *source = [NSURL URLWithString:definition[@"sourceURL"]];
                NSURL *destination = [NSURL URLWithString:definition[@"destinationURL"]];
                struct stat sourceStat, destinationStat;
                BOOL sourceExists = source.isFileURL && stat(source.fileSystemRepresentation, &sourceStat) == 0;
                BOOL destinationExists = stat(destination.fileSystemRepresentation, &destinationStat) == 0;
                BOOL overwrite = [arguments[@"overwrite"] respondsToSelector:@selector(boolValue)] && [arguments[@"overwrite"] boolValue];
                if (sourceExists && destinationExists && sourceStat.st_dev == destinationStat.st_dev && sourceStat.st_ino == destinationStat.st_ino)
                    error = MXRMediaError(EINVAL, @"The output file must differ from the source.");
                else if (destinationExists && !overwrite)
                    error = MXRMediaError(EEXIST, @"The output file already exists.");
                else {
                    BOOL directory = NO;
                    NSString *parent = destination.path.stringByDeletingLastPathComponent;
                    if (![NSFileManager.defaultManager fileExistsAtPath:parent isDirectory:&directory] || !directory)
                        error = MXRMediaError(ENOENT, @"The output folder does not exist.");
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (atomic_load(&self->_shutDown)) { completion(nil, MXRMediaError(ECANCELED, @"The VLC interface has closed.")); return; }
                NSError *failure = error;
                NSDictionary *result = failure == nil ? [self startOutput:definition arguments:arguments error:&failure] : nil;
                completion(result, failure);
            });
        });
        return;
    }
    if (![service isEqual:MXRBridgeServiceExtensions] && !([service isEqual:MXRBridgeServiceRenderers] && [request isEqual:MXRBridgeRequestDiscover])) {
        completion(nil, MXRMediaError(ENOTSUP, @"This service request is unavailable.")); return;
    }
    if ([service isEqual:MXRBridgeServiceRenderers]) {
        /* Rediscovery forgets every device except the one in use, which the player still holds. */
        MXRRendererReference *selected = _selectedRendererID != nil ? _renderers[_selectedRendererID] : nil;
        [_renderers removeAllObjects];
        if (selected != nil) _renderers[_selectedRendererID] = selected;
        _discovering = YES; [self changed:service];
    }
    dispatch_async([service isEqual:MXRBridgeServiceExtensions] ? _extensionQueue : _serviceQueue, ^{
        if (atomic_load(&self->_shutDown)) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, MXRMediaError(ECANCELED, @"The VLC interface has closed.")); });
            return;
        }
        NSError *error = nil;
        NSDictionary *result = [service isEqual:MXRBridgeServiceExtensions] ? [self extensionRequest:request arguments:arguments error:&error] : [self discoverRenderers:&error];
        NSDictionary *catalog = [service isEqual:MXRBridgeServiceExtensions] ? (self->_extensions != NULL ? [self extensionCatalog] :
            @{@"items": @[], @"modules": @[], @"available": @NO, @"supportsInstall": @NO, @"supportsRemove": @NO,
              @"supportsActivation": @NO, @"supportsSearchCatalog": @NO, @"localUnavailableReason": error.localizedDescription ?: @"VLC's extension manager is unavailable."}) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (atomic_load(&self->_shutDown)) { completion(nil, MXRMediaError(ECANCELED, @"The VLC interface has closed.")); return; }
            if (catalog != nil) self->_extensionSnapshot = catalog;
            if ([service isEqual:MXRBridgeServiceRenderers]) {
                /* Discovery keeps running in the background; "discovering" covers only the first
                 * answers, so menus offer Refresh again instead of a permanent "Discovering…". */
                NSUInteger generation = ++self->_discoveryGeneration;
                self->_discovering = result != nil;
                if (result != nil)
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        if (atomic_load(&self->_shutDown) || generation != self->_discoveryGeneration) return;
                        self->_discovering = NO;
                        [self changed:MXRBridgeServiceRenderers];
                    });
            }
            [self changed:service];
            completion(result, error);
        });
    });
}

- (void)shutdown
{
    if (atomic_exchange(&_shutDown, true)) return;
    _serviceChanged = nil;
    _abandonedPartial = _activeJob.partialPath;
    if (_outputPlayer != NULL) {
        vlc_playlist_Lock(_outputPlaylist);
        vlc_playlist_Stop(_outputPlaylist);
        if (_outputListener != NULL) vlc_player_RemoveListener(_outputPlayer, _outputListener);
        _outputListener = NULL;
        vlc_playlist_Unlock(_outputPlaylist);
    }
    if (_mainListener != NULL) {
        vlc_player_Lock(_mainPlayer);
        vlc_player_RemoveListener(_mainPlayer, _mainListener);
        vlc_player_Unlock(_mainPlayer); _mainListener = NULL;
    }
}
- (void)finishShutdown
{
    NSAssert(!NSThread.isMainThread, @"Dispose VLC worker services from the interface thread.");
    dispatch_sync(_extensionQueue, ^{
        if (self->_extensionPoll != nil) { dispatch_source_cancel(self->_extensionPoll); self->_extensionPoll = nil; }
        [self unloadExtensions];
    });
    dispatch_sync(_serviceQueue, ^{
        for (NSValue *value in self->_discoveries) vlc_rd_release(value.pointerValue);
        [self->_discoveries removeAllObjects];
        if (self->_outputPlaylist != NULL) {
            vlc_playlist_Delete(self->_outputPlaylist);
            self->_outputPlaylist = NULL; self->_outputPlayer = NULL;
        }
        if (self->_abandonedPartial != nil) unlink(self->_abandonedPartial.fileSystemRepresentation);
    });
}
@end
