/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#import <CommonCrypto/CommonDigest.h>
#import "MXRBridgeKeys.h"
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#include <stdatomic.h>
#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_input_item.h>
#include <vlc_player.h>
#include <vlc_playlist.h>
#include <vlc_aout.h>
#include <vlc_configuration.h>
#import "MXRAudioServices.h"

static NSError *AE(NSInteger code, NSString *message)
{
    return [NSError errorWithDomain:@"MXRVLCBridge" code:code userInfo:@{NSLocalizedDescriptionKey:message}];
}

NSData *MXRCreateStereoTestWAV(void)
{
    const uint32_t rate = 48000, frames = rate * 5 / 2, bytes = frames * 4;
    NSMutableData *data = [NSMutableData dataWithLength:44 + bytes];
    uint8_t *header = data.mutableBytes;
    memcpy(header, "RIFF", 4); memcpy(header + 8, "WAVEfmt ", 8); memcpy(header + 36, "data", 4);
    uint32_t words[] = {CFSwapInt32HostToLittle(bytes + 36), CFSwapInt32HostToLittle(16),
        CFSwapInt32HostToLittle(rate), CFSwapInt32HostToLittle(rate * 4), CFSwapInt32HostToLittle(bytes)};
    memcpy(header + 4, &words[0], 4); memcpy(header + 16, &words[1], 4);
    memcpy(header + 24, &words[2], 4); memcpy(header + 28, &words[3], 4); memcpy(header + 40, &words[4], 4);
    uint16_t shorts[] = {CFSwapInt16HostToLittle(1), CFSwapInt16HostToLittle(2),
        CFSwapInt16HostToLittle(4), CFSwapInt16HostToLittle(16)};
    memcpy(header + 20, &shorts[0], 2); memcpy(header + 22, &shorts[1], 2);
    memcpy(header + 32, &shorts[2], 2); memcpy(header + 34, &shorts[3], 2);
    int16_t *pcm = (int16_t *)(header + 44);
    for (uint32_t index = 0; index < frames; ++index) {
        double time = (double)index / rate;
        BOOL left = time >= .15 && time < 1.1, right = time >= 1.4 && time < 2.35;
        if (!left && !right) continue;
        double start = left ? .15 : 1.4, end = left ? 1.1 : 2.35;
        double envelope = fmin(1., fmin((time - start) / .01, (end - time) / .01));
        int16_t sample = (int16_t)lrint(.18 * 32767 * envelope * sin(2 * M_PI * (left ? 440 : 660) * (time - start)));
        pcm[index * 2 + (right ? 1 : 0)] = (int16_t)CFSwapInt16HostToLittle((uint16_t)sample);
    }
    return data;
}

@interface MXRAudioServices ()
- (void)toneState:(enum vlc_player_state)state media:(input_item_t *)media;
- (void)toneStopping:(input_item_t *)media reason:(enum vlc_player_media_stopping_reason)reason;
- (void)toneStatistics:(uint64_t)decoded played:(uint64_t)played media:(input_item_t *)media;
@end

static void ToneState(vlc_player_t *player, enum vlc_player_state state, void *data)
{
    MXRAudioServices *owner = (__bridge MXRAudioServices *)data;
    input_item_t *media = vlc_player_GetCurrentMedia(player);
    if (media != NULL) input_item_Hold(media);
    dispatch_async(dispatch_get_main_queue(), ^{
        [owner toneState:state media:media];
        if (media != NULL) input_item_Release(media);
    });
}
static void ToneStopping(vlc_player_t *player, input_item_t *media, enum vlc_player_media_stopping_reason reason, void *data)
{
    VLC_UNUSED(player);
    MXRAudioServices *owner = (__bridge MXRAudioServices *)data;
    input_item_Hold(media);
    dispatch_async(dispatch_get_main_queue(), ^{
        [owner toneStopping:media reason:reason]; input_item_Release(media);
    });
}
static void ToneStatistics(vlc_player_t *player, const struct input_stats_t *stats, void *data)
{
    VLC_UNUSED(player);
    MXRAudioServices *owner = (__bridge MXRAudioServices *)data;
    uint64_t decoded = stats->i_decoded_audio, played = stats->i_played_abuffers;
    input_item_t *media = vlc_player_GetCurrentMedia(player);
    if (media != NULL) input_item_Hold(media);
    dispatch_async(dispatch_get_main_queue(), ^{
        [owner toneStatistics:decoded played:played media:media];
        if (media != NULL) input_item_Release(media);
    });
}
static const struct vlc_player_cbs ToneCallbacks = {
    .on_state_changed = ToneState, .on_stopping_current_media = ToneStopping, .on_statistics_changed = ToneStatistics,
};

@implementation MXRAudioServices
{
    vlc_player_t *_mainPlayer, *_tonePlayer;
    vlc_playlist_t *_tonePlaylist;
    vlc_player_listener_id *_toneListener;
    input_item_t *_toneMedia;
    dispatch_queue_t _toneQueue, _waveQueue;
    atomic_bool _stopped;
    atomic_uint _waveGeneration;
    atomic_bool _waveActive;
    atomic_uint_fast64_t _waveSamplesRead;
    NSUInteger _toneGeneration;
    BOOL _toneEnded, _toneCancelled;
    enum vlc_player_media_stopping_reason _toneReason;
    NSError *_toneFailure;
    NSString *_toneState;
    void (^_toneCompletion)(NSDictionary *, NSError *);
    uint64_t _decoded, _played;
    NSString *_toneFile; /* tone queue only */
    NSMutableDictionary<NSString *, NSDictionary *> *_waveCache; /* waveform queue only */
    NSMutableArray<NSString *> *_waveCacheOrder;
}

- (instancetype)initWithPlaylist:(vlc_playlist_t *)playlist interface:(intf_thread_t *)intf
{
    self = [super init]; if (self == nil) return nil;
    atomic_init(&_stopped, false); atomic_init(&_waveGeneration, 0);
    atomic_init(&_waveActive,false); atomic_init(&_waveSamplesRead,0);
    _mainPlayer = vlc_playlist_GetPlayer(playlist);
    _toneState = @"idle";
    _toneQueue = dispatch_queue_create("org.vlc.redesign.stereo-test", DISPATCH_QUEUE_SERIAL);
    _waveQueue = dispatch_queue_create("org.vlc.redesign.waveforms", DISPATCH_QUEUE_SERIAL);
    _waveCache = [NSMutableDictionary dictionary]; _waveCacheOrder = [NSMutableArray array];
    _tonePlaylist = vlc_playlist_New(VLC_OBJECT(vlc_object_instance(intf)), VLC_PLAYLIST_PREPARSING_DISABLED, 1, 0);
    if (_tonePlaylist != NULL) {
        _tonePlayer = vlc_playlist_GetPlayer(_tonePlaylist);
        vlc_playlist_Lock(_tonePlaylist);
        vlc_playlist_SetMediaStoppedAction(_tonePlaylist, VLC_PLAYLIST_MEDIA_STOPPED_STOP);
        _toneListener = vlc_player_AddListener(_tonePlayer, &ToneCallbacks, (__bridge void *)self);
        vlc_playlist_Unlock(_tonePlaylist);
    }
    return self;
}
- (void)dealloc { assert(_tonePlaylist == NULL && _toneListener == NULL && _toneMedia == NULL); }
- (NSDictionary *)capabilities { return @{@"stereoTest":_toneListener != NULL ? @YES : @NO, @"supportsWaveform":@YES}; }
- (NSDictionary *)snapshotForService:(MXRBridgeService)service
{
    if ([service isEqual:MXRBridgeServiceAudioTest])
        return @{@"state":_toneState, @"available":_toneListener != NULL ? @YES : @NO, @"volume":@.25,
                 @"decodedAudio":@(_decoded), @"playedAudioBuffers":@(_played)};
    if ([service isEqual:MXRBridgeServiceWaveform]) return @{@"active":atomic_load(&_waveActive) ? @YES : @NO,@"samplesRead":@(atomic_load(&_waveSamplesRead))};
    return @{};
}
- (void)changed { if (!atomic_load(&_stopped) && _serviceChanged != nil) _serviceChanged(MXRBridgeServiceAudioTest); }
- (void)completeTone:(NSError *)error state:(NSString *)state
{
    void (^completion)(NSDictionary *, NSError *) = _toneCompletion;
    _toneCompletion = nil; _toneState = state;
    if (_toneMedia != NULL) { input_item_Release(_toneMedia); _toneMedia = NULL; }
    [self changed];
    if (completion != nil) completion(error == nil ? @{@"state":state} : nil, error);
}
- (void)toneState:(enum vlc_player_state)state media:(input_item_t *)media
{
    if (atomic_load(&_stopped) || _toneCompletion == nil) return;
    if (state == VLC_PLAYER_STATE_PLAYING && media == _toneMedia) { _toneState = @"playing"; [self changed]; }
    if (state == VLC_PLAYER_STATE_STOPPED && _toneMedia != NULL) {
        if (_toneCancelled) [self completeTone:AE(ECANCELED,@"Speaker test cancelled.") state:@"cancelled"];
        else if (_toneFailure != nil) [self completeTone:_toneFailure state:@"failed"];
        else if (!_toneEnded || _toneReason != VLC_PLAYER_MEDIA_STOPPING_EOS)
            [self completeTone:AE(EIO,@"VLC could not finish the speaker test.") state:@"failed"];
        else if (_decoded == 0 || _played == 0)
            [self completeTone:AE(EIO,@"VLC could not send the test signal to audio output.") state:@"failed"];
        else [self completeTone:nil state:@"completed"];
    }
}
- (void)toneStopping:(input_item_t *)media reason:(enum vlc_player_media_stopping_reason)reason
{
    if (atomic_load(&_stopped) || media != _toneMedia) return;
    _toneEnded = YES; _toneReason = reason;
}
- (void)toneStatistics:(uint64_t)decoded played:(uint64_t)played media:(input_item_t *)media
{
    if (atomic_load(&_stopped) || _toneCompletion == nil || media != _toneMedia) return;
    _decoded = decoded; _played = played;
}
- (void)startTone:(NSDictionary *)arguments completion:(void (^)(NSDictionary *, NSError *))completion
{
    if (_toneListener == NULL) { completion(nil,AE(ENOTSUP,@"Speaker testing is unavailable.")); return; }
    if (_toneCompletion != nil) { completion(nil,AE(EBUSY,@"A speaker test is already running.")); return; }
    id modeValue = arguments[@"mode"], deviceValue = arguments[@"deviceID"];
    if ((modeValue != nil && (![modeValue isKindOfClass:NSNumber.class] || [modeValue doubleValue] != [modeValue integerValue] || [modeValue integerValue] < 0 || [modeValue integerValue] > 7)) ||
        (deviceValue != nil && deviceValue != NSNull.null && ![deviceValue isKindOfClass:NSString.class])) {
        completion(nil,AE(EINVAL,@"Choose a valid stereo mode and audio device.")); return;
    }
    audio_output_t *mainAout = vlc_player_aout_Hold(_mainPlayer);
    NSInteger mode = modeValue != nil ? [modeValue integerValue] : (mainAout != NULL ? var_GetInteger(mainAout,"stereo-mode") : 0);
    if (modeValue == nil && mainAout != NULL && var_GetInteger(mainAout,"mix-mode") == AOUT_MIX_MODE_BINAURAL) mode = 6;
    NSString *device = [deviceValue isKindOfClass:NSString.class] ? deviceValue : nil;
    if (device == nil && mainAout != NULL) {
        char *current = aout_DeviceGet(mainAout);
        if (current != NULL) { device = [NSString stringWithUTF8String:current]; free(current); }
    }
    if (mainAout != NULL) aout_Release(mainAout);
    _toneCompletion = [completion copy]; _toneState = @"preparing";
    _toneEnded = NO; _toneCancelled = NO; _toneFailure = nil; _decoded = 0; _played = 0;
    NSUInteger generation = ++_toneGeneration;
    [self changed];
    dispatch_async(_toneQueue, ^{ @autoreleasepool {
        NSError *error = nil;
        if (self->_toneFile == nil && !atomic_load(&self->_stopped)) {
            self->_toneFile = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"mxr-stereo-%@.wav",NSUUID.UUID.UUIDString]];
            if (![MXRCreateStereoTestWAV() writeToFile:self->_toneFile options:NSDataWritingAtomic error:&error]) self->_toneFile = nil;
            else [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:self->_toneFile error:nil];
        }
        NSString *path = self->_toneFile;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (atomic_load(&self->_stopped) || self->_toneGeneration != generation || self->_toneCompletion == nil) return;
            if (path == nil) { [self completeTone:error ?: AE(EIO,@"Cannot create the speaker test.") state:@"failed"]; return; }
            [self playToneURL:[NSURL fileURLWithPath:path] mode:mode device:device generation:generation];
        });
    }});
}
- (void)playToneURL:(NSURL *)url mode:(NSInteger)mode device:(NSString *)device generation:(NSUInteger)generation
{
    audio_output_t *aout = vlc_player_aout_Hold(_tonePlayer);
    if (aout == NULL) { [self completeTone:AE(EIO,@"VLC has no audio output for the speaker test.") state:@"failed"]; return; }
    var_SetInteger(aout,"stereo-mode",mode == 6 ? AOUT_VAR_CHAN_UNSET : mode);
    var_SetInteger(aout,"mix-mode",mode == 6 ? AOUT_MIX_MODE_BINAURAL : AOUT_MIX_MODE_UNSET);
    if (var_Type(aout,"volume-save") == 0) var_Create(aout,"volume-save",VLC_VAR_BOOL);
    var_SetBool(aout,"volume-save",false);
    if (var_Type(aout,"audio-resampler") == 0) var_Create(aout,"audio-resampler",VLC_VAR_STRING);
    var_SetString(aout,"audio-resampler","any");
    if (var_Type(aout,"audio-time-stretch") == 0) var_Create(aout,"audio-time-stretch",VLC_VAR_BOOL);
    var_SetBool(aout,"audio-time-stretch",false);
    var_SetString(aout,"audio-filter",""); var_SetString(aout,"audio-replay-gain-mode","none"); var_SetString(aout,"visual","none");
    int deviceStatus = device.length > 0 ? aout_DeviceSet(aout,device.UTF8String) : VLC_SUCCESS;
    aout_Release(aout);
    if (deviceStatus != VLC_SUCCESS) { [self completeTone:AE(EIO,@"VLC could not select the speaker test audio device.") state:@"failed"]; return; }
    /* Some outputs (including adummy) have no volume control. PCM itself is below 0.25 full scale;
       supported outputs also receive the fixed 0.25 volume. Never touch the main player's volume. */
    vlc_player_aout_SetVolume(_tonePlayer,.25f); vlc_player_aout_Mute(_tonePlayer,false);
    _toneMedia = input_item_New(url.absoluteString.UTF8String,"Left and right speaker test");
    if (_toneMedia == NULL) { [self completeTone:AE(ENOMEM,@"Cannot create the speaker test input.") state:@"failed"]; return; }
    for (NSString *option in @[@"audio=1",@"video=0",@"spu=0",@"sout=",@"input-repeat=0",@"rate=1",
                               @"start-time=0",@"stop-time=0",@"run-time=0",
                               @"demux=wav",@"codec=araw",@"audio-track=0",@"audio-track-id=",@"audio-language=any",
                               @"stats=1",@"stats-min-report-interval=100"]) {
        if (input_item_AddOption(_toneMedia,option.UTF8String,VLC_INPUT_OPTION_TRUSTED) != VLC_SUCCESS) {
            [self completeTone:AE(ENOMEM,@"Cannot configure the speaker test input.") state:@"failed"]; return;
        }
    }
    vlc_playlist_Lock(_tonePlaylist);
    vlc_player_ChangeRate(_tonePlayer,1.f);
    vlc_playlist_Clear(_tonePlaylist);
    int status = vlc_playlist_InsertOne(_tonePlaylist,0,_toneMedia);
    if (status == VLC_SUCCESS) status = vlc_playlist_PlayAt(_tonePlaylist,0);
    vlc_playlist_Unlock(_tonePlaylist);
    if (status != VLC_SUCCESS) { [self completeTone:AE(EIO,@"VLC could not start the speaker test.") state:@"failed"]; return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15 * NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if (atomic_load(&self->_stopped) || self->_toneGeneration != generation || self->_toneCompletion == nil) return;
        self->_toneFailure = AE(ETIMEDOUT,@"The speaker test timed out.");
        vlc_playlist_Lock(self->_tonePlaylist); vlc_playlist_Stop(self->_tonePlaylist); vlc_playlist_Unlock(self->_tonePlaylist);
    });
}
- (void)cancelTone
{
    if (_toneCompletion == nil) return;
    _toneCancelled = YES;
    if (_toneMedia == NULL) { ++_toneGeneration; [self completeTone:AE(ECANCELED,@"Speaker test cancelled.") state:@"cancelled"]; }
    else { _toneState = @"cancelling"; vlc_playlist_Lock(_tonePlaylist); vlc_playlist_Stop(_tonePlaylist); vlc_playlist_Unlock(_tonePlaylist); [self changed]; }
}

/* ARC-05: peaks cached on disk, keyed by path, mtime, size and bin count, so reopening a file never
 * decodes it again. Entries are small property lists in the user cache directory, pruned to 300. */
static NSURL *MXRWaveformCacheFile(NSString *key, BOOL create)
{
    NSURL *caches = [NSFileManager.defaultManager URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:NULL];
    if (caches == nil) return nil;
    NSURL *directory = [[caches URLByAppendingPathComponent:@"org.example.vlc-redesign" isDirectory:YES] URLByAppendingPathComponent:@"Waveforms" isDirectory:YES];
    if (create) [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    NSData *text = [key dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(text.bytes,(CC_LONG)text.length,digest);
    NSMutableString *name = [NSMutableString stringWithCapacity:2 * CC_SHA256_DIGEST_LENGTH + 6];
    for (int index = 0; index < CC_SHA256_DIGEST_LENGTH; ++index) [name appendFormat:@"%02x",digest[index]];
    [name appendString:@".plist"];
    return [directory URLByAppendingPathComponent:name];
}
static NSDictionary *MXRWaveformCacheLoad(NSString *key, NSInteger bins)
{
    NSURL *file = MXRWaveformCacheFile(key,NO);
    NSData *data = file != nil ? [NSData dataWithContentsOfURL:file] : nil;
    NSDictionary *entry = data != nil ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL] : nil;
    if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"key"] isEqual:key]) return nil;
    NSArray *samples = entry[@"samples"];
    if (![samples isKindOfClass:NSArray.class] || (NSInteger)samples.count != bins || ![entry[@"duration"] isKindOfClass:NSNumber.class]) return nil;
    return @{@"samples":samples,@"duration":entry[@"duration"]};
}
static void MXRWaveformCacheStore(NSString *key, NSDictionary *value)
{
    NSURL *file = MXRWaveformCacheFile(key,YES);
    if (file == nil) return;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:@{@"key":key,@"samples":value[@"samples"],@"duration":value[@"duration"]}
                                                              format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    if (![data writeToURL:file options:NSDataWritingAtomic error:NULL]) return;
    NSArray<NSURL *> *entries = [NSFileManager.defaultManager contentsOfDirectoryAtURL:file.URLByDeletingLastPathComponent
        includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL];
    if (entries.count <= 300) return;
    NSArray<NSURL *> *oldestFirst = [entries sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        NSDate *da = nil, *db = nil;
        [a getResourceValue:&da forKey:NSURLContentModificationDateKey error:NULL]; [b getResourceValue:&db forKey:NSURLContentModificationDateKey error:NULL];
        return [da ?: NSDate.distantPast compare:db ?: NSDate.distantPast];
    }];
    for (NSUInteger index = 0; index < oldestFirst.count - 300; ++index) [NSFileManager.defaultManager removeItemAtURL:oldestFirst[index] error:NULL];
}

- (BOOL)waveCancelled:(unsigned)generation { return atomic_load(&_stopped) || atomic_load(&_waveGeneration) != generation; }
- (NSDictionary *)readWaveform:(NSURL *)url bins:(NSInteger)bins generation:(unsigned)generation error:(NSError **)error
{
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:error];
    if (attributes == nil || ![attributes[NSFileType] isEqual:NSFileTypeRegular]) { if (*error == nil) *error = AE(EINVAL,@"Choose a readable local audio file."); return nil; }
    NSString *key = [NSString stringWithFormat:@"%@|%.9f|%@|%ld",url.absoluteString,[attributes[NSFileModificationDate] timeIntervalSince1970],attributes[NSFileSize],(long)bins];
    if (_waveCache[key] != nil) return _waveCache[key];
    NSDictionary *stored = MXRWaveformCacheLoad(key,bins);
    if (stored != nil) { _waveCache[key] = stored; [_waveCacheOrder addObject:key]; return stored; }
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey:@YES}];
    dispatch_semaphore_t ready = dispatch_semaphore_create(0);
    __block NSArray<AVAssetTrack *> *tracks = nil;
    __block NSError *loadError = nil;
    [asset loadTracksWithMediaType:AVMediaTypeAudio completionHandler:^(NSArray<AVAssetTrack *> *value,NSError *failure) { tracks = value; loadError = failure; dispatch_semaphore_signal(ready); }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15];
    while (dispatch_semaphore_wait(ready,dispatch_time(DISPATCH_TIME_NOW,100 * NSEC_PER_MSEC)) != 0) {
        if ([self waveCancelled:generation] || deadline.timeIntervalSinceNow <= 0) {
            [asset cancelLoading]; *error = AE([self waveCancelled:generation] ? ECANCELED : ETIMEDOUT,@"Audio analysis cancelled or timed out."); return nil;
        }
    }
    double duration = CMTimeGetSeconds(asset.duration);
    if (tracks.count == 0 || !isfinite(duration) || duration <= 0) { *error = loadError ?: AE(ENOTSUP,@"This file has no decodable audio with a known duration."); return nil; }
    AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:error];
    if (reader == nil) return nil;
    NSDictionary *settings = @{AVFormatIDKey:@(kAudioFormatLinearPCM),AVSampleRateKey:@22050,AVNumberOfChannelsKey:@1,
        AVLinearPCMBitDepthKey:@32,AVLinearPCMIsFloatKey:@YES,AVLinearPCMIsBigEndianKey:@NO,AVLinearPCMIsNonInterleaved:@NO};
    AVAssetReaderAudioMixOutput *output = [[AVAssetReaderAudioMixOutput alloc] initWithAudioTracks:@[tracks.firstObject] audioSettings:settings];
    output.alwaysCopiesSampleData = NO;
    if (![reader canAddOutput:output]) { *error = AE(ENOTSUP,@"The audio format cannot be analyzed."); return nil; }
    [reader addOutput:output];
    if (![reader startReading]) { *error = reader.error ?: AE(EIO,@"Cannot decode this audio file."); return nil; }
    float *peaks = calloc((size_t)bins,sizeof(*peaks));
    if (peaks == NULL) { [reader cancelReading]; *error = AE(ENOMEM,@"Cannot allocate waveform peaks."); return nil; }
    float maximum = 0; uint64_t sampleCount = 0;
    atomic_store(&_waveSamplesRead,0); atomic_store(&_waveActive,true);
    while (reader.status == AVAssetReaderStatusReading && ![self waveCancelled:generation]) { @autoreleasepool {
        CMSampleBufferRef buffer = [output copyNextSampleBuffer];
        if (buffer == NULL) break;
        CMBlockBufferRef block = CMSampleBufferGetDataBuffer(buffer);
        const AudioStreamBasicDescription *format = CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(buffer));
        CMItemCount count = CMSampleBufferGetNumSamples(buffer);
        double start = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer));
        if (block == NULL || format == NULL || format->mChannelsPerFrame != 1 || format->mBitsPerChannel != 32 || !(format->mFormatFlags & kAudioFormatFlagIsFloat) || !isfinite(start)) {
            CFRelease(buffer); *error = AE(ENOTSUP,@"The decoded audio format is unavailable."); break;
        }
        float chunk[4096];
        for (CMItemCount offset = 0; offset < count; offset += 4096) {
            size_t length = (size_t)MIN((CMItemCount)4096,count-offset);
            if (CMBlockBufferCopyDataBytes(block,(size_t)offset*sizeof(float),length*sizeof(float),chunk) != kCMBlockBufferNoErr) { *error = AE(EIO,@"Cannot read decoded audio samples."); break; }
            /* Walk whole bins at a time: one division per bin instead of per sample. fmaxf
               ignores NaN, so non-finite samples never become peaks. */
            const double binFrames = duration * format->mSampleRate / (double)bins;
            const double firstFrame = fmax(0, start * format->mSampleRate) + (double)offset;
            for (size_t index = 0; index < length;) {
                const double frame = firstFrame + (double)index;
                const NSInteger bin = MAX(0,MIN(bins-1,(NSInteger)floor(frame / binFrames)));
                size_t end = length;
                if (bin < bins-1) {
                    const double remaining = ceil((double)(bin+1) * binFrames - frame);
                    end = MIN(length, index + (size_t)MAX(1., remaining));
                }
                float peak = peaks[bin];
                for (; index < end; ++index) peak = fmaxf(peak,fabsf(chunk[index]));
                if (isfinite(peak)) { peaks[bin] = peak; maximum = fmaxf(maximum,peak); }
            }
            sampleCount += length;
            atomic_store(&_waveSamplesRead,sampleCount);
            if (*error != nil || [self waveCancelled:generation]) break;
        }
        CFRelease(buffer);
        if (*error != nil) break;
    }}
    atomic_store(&_waveActive,false);
    if ([self waveCancelled:generation]) *error = AE(ECANCELED,@"Audio analysis cancelled.");
    else if (*error == nil && (reader.status != AVAssetReaderStatusCompleted || sampleCount == 0))
        *error = reader.error ?: AE(EIO,@"Could not read the complete audio waveform.");
    if (*error != nil) { [reader cancelReading]; free(peaks); return nil; }
    NSDictionary *after = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:error];
    if (after == nil || ![after[NSFileModificationDate] isEqual:attributes[NSFileModificationDate]] || ![after[NSFileSize] isEqual:attributes[NSFileSize]]) {
        free(peaks); if (*error == nil) *error = AE(EAGAIN,@"The audio file changed during analysis."); return nil;
    }
    NSMutableArray *samples = [NSMutableArray arrayWithCapacity:(NSUInteger)bins];
    for (NSInteger index = 0; index < bins; ++index) [samples addObject:@(maximum > 0 ? peaks[index] / maximum : 0)];
    free(peaks);
    NSDictionary *result = @{@"samples":samples,@"duration":@(duration)};
    if (_waveCacheOrder.count >= 24) { [_waveCache removeObjectForKey:_waveCacheOrder.firstObject]; [_waveCacheOrder removeObjectAtIndex:0]; }
    _waveCache[key] = result; [_waveCacheOrder addObject:key];
    MXRWaveformCacheStore(key,result);
    return result;
}
- (void)request:(MXRBridgeRequest)request service:(MXRBridgeService)service arguments:(NSDictionary *)arguments completion:(void (^)(NSDictionary<NSString *,id> * _Nullable,NSError * _Nullable))completion
{
    NSAssert(NSThread.isMainThread,@"Audio service requests belong to main.");
    if (atomic_load(&_stopped)) { completion(nil,AE(ECANCELED,@"The VLC interface has closed.")); return; }
    if ([service isEqual:MXRBridgeServiceAudioTest] && [request isEqual:MXRBridgeRequestStart]) { [self startTone:arguments completion:completion]; return; }
    if ([service isEqual:MXRBridgeServiceAudioTest] && [request isEqual:MXRBridgeRequestCancel]) { [self cancelTone]; completion(@{@"state":_toneState},nil); return; }
    if ([service isEqual:MXRBridgeServiceThumbnails] && [request isEqual:MXRBridgeRequestCancelWaveform]) { atomic_fetch_add(&_waveGeneration,1); completion(@{},nil); return; }
    if ([service isEqual:MXRBridgeServiceThumbnails] && [request isEqual:MXRBridgeRequestWaveform]) {
        NSDictionary *media = [arguments[@"media"] isKindOfClass:NSDictionary.class] ? arguments[@"media"] : arguments;
        NSString *text = [media[@"url"] isKindOfClass:NSString.class] ? media[@"url"] : nil;
        NSURL *url = [NSURL URLWithString:text ?: @""];
        id count = arguments[@"bins"];
        if (!url.isFileURL || ![count isKindOfClass:NSNumber.class] || [count doubleValue] != [count integerValue] || [count integerValue] < 1 || [count integerValue] > 4096) {
            completion(nil,AE(ENOTSUP,@"Waveforms require a local audio file and 1–4096 bins.")); return;
        }
        unsigned generation = atomic_load(&_waveGeneration);
        NSInteger bins = [count integerValue]; url = url.URLByResolvingSymlinksInPath.URLByStandardizingPath;
        dispatch_async(_waveQueue,^{ @autoreleasepool {
            NSError *error = nil;
            NSDictionary *value = [self waveCancelled:generation] ? nil : [self readWaveform:url bins:bins generation:generation error:&error];
            dispatch_async(dispatch_get_main_queue(),^{
                if ([self waveCancelled:generation]) completion(nil,AE(ECANCELED,@"Audio analysis cancelled."));
                else completion(value,error);
            });
        }});
        return;
    }
    completion(nil,AE(ENOTSUP,@"This audio service request is unavailable."));
}
- (void)shutdown
{
    NSAssert(NSThread.isMainThread,@"Audio service shutdown belongs to main.");
    if (atomic_exchange(&_stopped,true)) return;
    atomic_fetch_add(&_waveGeneration,1); ++_toneGeneration; _serviceChanged = nil;
    if (_tonePlaylist != NULL) {
        vlc_playlist_Lock(_tonePlaylist); vlc_playlist_Stop(_tonePlaylist);
        if (_toneListener != NULL) vlc_player_RemoveListener(_tonePlayer,_toneListener);
        _toneListener = NULL; vlc_playlist_Unlock(_tonePlaylist);
    }
    [self completeTone:AE(ECANCELED,@"Speaker test cancelled.") state:@"cancelled"];
}
- (void)finishShutdown
{
    NSAssert(!NSThread.isMainThread,@"Join audio workers from the interface thread.");
    dispatch_sync(_waveQueue,^{ [self->_waveCache removeAllObjects]; [self->_waveCacheOrder removeAllObjects]; });
    dispatch_sync(_toneQueue,^{
        if (self->_tonePlaylist != NULL) {
            /* auhal Close persists its device unconditionally. Closing the auxiliary output
               must not replace the user's configured device, including the default choice. */
            audio_output_t *aout = vlc_player_aout_Hold(self->_tonePlayer);
            char *module = aout != NULL ? vlc_object_get_name(aout) : NULL;
            BOOL preserveDevice = module != NULL && strcmp(module,"auhal") == 0 && config_FindConfig("auhal-audio-device") != NULL;
            char *savedDevice = preserveDevice ? config_GetPsz("auhal-audio-device") : NULL;
            if (aout != NULL) aout_Release(aout); free(module);
            vlc_playlist_Delete(self->_tonePlaylist); self->_tonePlaylist = NULL; self->_tonePlayer = NULL;
            if (preserveDevice) config_PutPsz("auhal-audio-device",savedDevice);
            free(savedDevice);
        }
        if (self->_toneFile != nil) { [NSFileManager.defaultManager removeItemAtPath:self->_toneFile error:nil]; self->_toneFile = nil; }
    });
}
@end
