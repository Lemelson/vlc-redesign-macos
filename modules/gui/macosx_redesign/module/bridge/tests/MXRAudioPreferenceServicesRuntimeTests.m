/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#import <Foundation/Foundation.h>
#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_input_item.h>
#include <vlc_playlist.h>
#include <vlc_aout.h>
#include <vlc_configuration.h>
#include <vlc_modules.h>
#include <stdatomic.h>
#include "libvlc_internal.h"
#include "../../../../../../src/audio_output/aout_internal.h"
#import "../MXRAudioPreferenceServices.h"
#import "MXRNativeTestDiagnostics.h"

static void require(BOOL condition, NSString *message)
{
    if (!condition) { NSLog(@"FAIL: %@",message); exit(1); }
}
static void pumpUntil(BOOL (^done)(void), NSString *message)
{
    /* A miss prints the running phase, the last engine line and a call graph. */
    require(MXRNativeDiagnosticsPumpUntil(done,8,message.UTF8String),message);
}
static const char *FilterObjects[] = {"normvol","equalizer","compressor","stereo_widen","chorus_flanger","karaoke","headphone","spatializer"};
typedef struct { atomic_uint loaded[8]; atomic_uint failures; } EngineEvidence;
static void engineLog(void *opaque,int type,const vlc_log_t *item,const char *format,va_list arguments)
{
    (void)item;
    char *message = NULL;
    if (vasprintf(&message,format,arguments) < 0) return;
    EngineEvidence *evidence = opaque;
    uint64_t at = MXRNativeDiagnosticsNoteLog(message);
    fprintf(stderr,"[+%llu ms][%d] %s\n",(unsigned long long)at,type,message);
    if (type == VLC_MSG_DBG) for (NSUInteger index = 0; index < 8; ++index) {
        char expected[120]; snprintf(expected,sizeof(expected),"using audio filter module \"%s\"",FilterObjects[index]);
        if (strstr(message,expected)) atomic_fetch_add(&evidence->loaded[index],1);
    }
    if (type == VLC_MSG_ERR && (strstr(message,"cannot add user audio filter") || strstr(message,"cannot setup filtering pipeline"))) {
        atomic_fetch_add(&evidence->failures,1); fprintf(stderr,"Engine filter failure: %s\n",message);
    }
    free(message);
}
static NSString *readChain(audio_output_t *aout)
{
    char *value = aout ? var_GetString(aout,"audio-filter") : config_GetPsz("audio-filter");
    NSString *result = value ? [NSString stringWithUTF8String:value] : @""; free(value); return result;
}
static BOOL contains(NSString *chain,NSString *name)
{
    return [[chain componentsSeparatedByString:@":"] containsObject:name];
}
static void apply(MXRAudioPreferenceServices *helper,NSString *suffix,id value)
{
    NSError *error = nil;
    require([helper applyOption:[@"macosx-redesign-" stringByAppendingString:suffix] value:value error:&error],
            [NSString stringWithFormat:@"%@ applied: %@",suffix,error]);
}
static uint64_t playedBuffers(vlc_player_t *player)
{
    vlc_player_Lock(player);
    const struct input_stats_t *stats = vlc_player_GetStatistics(player);
    uint64_t result = stats ? stats->i_played_abuffers : 0;
    vlc_player_Unlock(player); return result;
}
static void verifyChain(MXRAudioPreferenceServices *helper,vlc_player_t *player,NSString *key,NSString *filter,BOOL enabled)
{
    audio_output_t *aout = vlc_player_aout_Hold(player);
    require(aout != NULL,@"real audio output exists");
    NSString *live = readChain(aout), *persisted = readChain(NULL);
    require(contains(live,filter) == enabled && contains(persisted,filter) == enabled,@"live and persisted filter chain agree");
    require(contains(live,@"scaletempo") && contains(persisted,@"scaletempo"),[NSString stringWithFormat:@"unrelated scaletempo filter preserved in live %@ and config %@",live,persisted]);
    aout_Release(aout);
    NSNumber *value = [helper snapshotValues][[@"macosx-redesign-" stringByAppendingString:key]];
    require(value.boolValue == enabled && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID(),@"snapshot reports actual chain as JSON Boolean");
}

int main(int argc,const char *argv[])
{
    @autoreleasepool {
        require(argc == 2 || argc == 3,@"provide a local stereo WAV fixture and optional --expect-no-karaoke");
        BOOL missingKaraoke = argc == 3 && !strcmp(argv[2],"--expect-no-karaoke");
        const char *options[] = {"MXRAudioPreferenceServicesRuntimeTests","--ignore-config","--no-media-library","--no-auto-preparse",
            "--no-video-title-show","--aout=adummy","--vout=dummy","--verbose=2","--stats-min-report-interval=100"};
        libvlc_int_t *vlc = libvlc_InternalCreate();
        require(vlc != NULL && libvlc_InternalInit(vlc,ARRAY_SIZE(options),options) == VLC_SUCCESS,@"real VLC initializes headlessly");
        require(var_InheritBool(vlc,"ignore-config"),@"engine ignores personal config and disables autosave");
        EngineEvidence evidenceStorage = {0}; EngineEvidence *evidence = &evidenceStorage;
        const struct vlc_logger_operations logger = {.log=engineLog};
        vlc_LogSet(vlc,&logger,evidence);
        libvlc_InternalPlay(vlc);
        intf_thread_t *intf = vlc_object_create(vlc,sizeof(*intf));
        require(intf != NULL,@"test interface exists");
        vlc_playlist_t *playlist = vlc_intf_GetMainPlaylist(intf);
        vlc_player_t *player = vlc_playlist_GetPlayer(playlist);
        config_PutPsz("audio-filter","scaletempo:spatializer");
        audio_output_t *initialAout = vlc_player_aout_Hold(player);
        if (initialAout) { var_SetString(initialAout,"audio-filter","scaletempo"); aout_Release(initialAout); }
        /* Settings > General > Additional command line options (macosx-redesign-extra-args): split
         * like a shell, applied like src/config/cmdline.c as variables the engine's objects inherit. */
        require([MXRSplitCommandLineOptions(@"--a 'b c'  \"d\\\"e\" f\\ g") isEqual:(@[@"--a",@"b c",@"d\"e",@"f g"])],@"options split like a shell");
        NSUInteger applied = MXRApplyCommandLineOptions(VLC_OBJECT(vlc),
            @"--sub-margin 12 --rate=1.5 --video-title-show --no-osd --rt-priority --definitely-not-an-option=1 positional --input-title-format");
        require(applied == 4,[NSString stringWithFormat:@"four real options applied, obsolete/unknown/positional/valueless skipped (%lu)",(unsigned long)applied]);
        require(var_InheritInteger(intf,"sub-margin") == 12,@"an integer option reaches objects created by the engine");
        require(var_InheritFloat(intf,"rate") == 1.5f,@"a float option with = applies");
        require(var_InheritBool(intf,"video-title-show"),@"a bare boolean switches on (it was off on the command line)");
        require(!var_InheritBool(intf,"osd"),@"--no-<name> switches a boolean off");
        require(var_Type(vlc,"rt-priority") == 0,@"an obsolete option creates nothing");
        require(config_GetInt("sub-margin") == 0,@"the options never write the saved configuration");
        var_Destroy(vlc,"sub-margin"); var_Destroy(vlc,"rate"); var_Destroy(vlc,"osd");
        var_SetBool(vlc,"video-title-show",false);
        MXRAudioPreferenceServices *helper = [[MXRAudioPreferenceServices alloc] initWithPlayer:player];
        require([MXRAudioPreferenceServices handlesOption:@"macosx-redesign-normvol"] && ![MXRAudioPreferenceServices handlesOption:@"volume"],@"helper handles only its app options");
        NSError *error = nil;
        require(![helper applyOption:@"macosx-redesign-normvol" value:@2 error:&error] && error.code == EINVAL,@"invalid switch is rejected before mutation");
        require([readChain(NULL) isEqual:@"scaletempo:spatializer"],@"invalid input leaves engine preferences unchanged");
        require(![helper applyOption:@"macosx-redesign-spatial-mode" value:@"invented" error:&error] && error.code == EINVAL,@"invalid spatial mode rejected");
        require([helper availabilityForOption:@"macosx-redesign-karaoke"] != missingKaraoke,@"availability follows actual module inventory");
        if (missingKaraoke) {
            require(!module_exists("karaoke") && ![helper applyOption:@"macosx-redesign-karaoke" value:@YES error:&error] && error.code == ENOTSUP,@"missing module does not create a fake setting");
            require([readChain(NULL) isEqual:@"scaletempo:spatializer"],@"missing filter leaves preferences unchanged");
        }
        apply(helper,@"normvol",@YES);
        require(contains(readChain(NULL),@"normvol"),@"pre-playback preference configures future outputs");
        initialAout = vlc_player_aout_Hold(player);
        require(contains(readChain(NULL),@"spatializer") && initialAout != NULL && !contains(readChain(initialAout),@"spatializer"),@"future-only unrelated filter stays configured without changing the live chain");
        aout_Release(initialAout);
        NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        input_item_t *media = input_item_New(url.absoluteString.UTF8String,"Audio preference test");
        for (const char **option = (const char *[]){"input-repeat=-1","audio=1","video=0","spu=0","stats=1",NULL}; *option; ++option)
            input_item_AddOption(media,*option,VLC_INPUT_OPTION_TRUSTED);
        vlc_playlist_Lock(playlist);
        require(vlc_playlist_InsertOne(playlist,0,media) == VLC_SUCCESS && vlc_playlist_PlayAt(playlist,0) == VLC_SUCCESS,@"test media starts through actual queue");
        vlc_playlist_Unlock(playlist);
        pumpUntil(^BOOL { return atomic_load(&evidence->loaded[0]) > 0 && playedBuffers(player) > 0; },@"initial normvol filter loads and PCM reaches audio output");
        float initialVolume = vlc_player_aout_GetVolume(player);
        vlc_player_Lock(player); float initialRate = vlc_player_GetRate(player); vlc_player_Unlock(player);
        verifyChain(helper,player,@"normvol",@"normvol",YES);
        apply(helper,@"normvol",@NO);
        verifyChain(helper,player,@"normvol",@"normvol",NO);
        NSArray *keys = @[@"normvol",@"equalizer",@"compressor",@"stereo-widen",@"chorus",@"karaoke"];
        for (NSUInteger index = 0; index < keys.count; ++index) {
            if (index == 5 && missingKaraoke) continue;
            NSString *key = keys[index], *filter = [NSString stringWithUTF8String:FilterObjects[index]];
            require([helper availabilityForOption:[@"macosx-redesign-" stringByAppendingString:key]],@"available real filter is writable");
            if (index == 1) {
                audio_output_t *eqAout = vlc_player_aout_Hold(player);
                config_PutFloat("equalizer-preamp",15); var_SetFloat(eqAout,"equalizer-preamp",3);
                config_PutPsz("equalizer-bands",""); var_SetString(eqAout,"equalizer-bands","");
                aout_Release(eqAout);
            }
            unsigned before = atomic_load(&evidence->loaded[index]); uint64_t buffers = playedBuffers(player);
            apply(helper,key,@YES);
            pumpUntil(^BOOL { return atomic_load(&evidence->loaded[index]) > before && playedBuffers(player) > buffers; },[NSString stringWithFormat:@"%@ actually loads and processes PCM",filter]);
            verifyChain(helper,player,key,filter,YES);
            if (index == 1) {
                audio_output_t *eqAout = vlc_player_aout_Hold(player);
                require(config_GetFloat("equalizer-preamp") == 15 && var_GetFloat(eqAout,"equalizer-preamp") == 3,@"equalizer initialization preserves distinct configured and live custom preamp gains");
                aout_Release(eqAout);
            }
            apply(helper,key,@NO);
            verifyChain(helper,player,key,filter,NO);
        }
        for (NSUInteger index = 6; index < 8; ++index) {
            NSString *mode = index == 6 ? @"headphones" : @"spatializer";
            apply(helper,@"spatial-mode",mode);
            unsigned before = atomic_load(&evidence->loaded[index]); uint64_t buffers = playedBuffers(player);
            apply(helper,@"spatial-audio",@YES);
            pumpUntil(^BOOL { return atomic_load(&evidence->loaded[index]) > before && playedBuffers(player) > buffers; },@"selected spatial filter loads on the real pipeline");
            require([[helper snapshotValues][@"macosx-redesign-spatial-mode"] isEqual:mode],@"spatial mode reports active filter");
            verifyChain(helper,player,@"spatial-audio",index == 6 ? @"headphone" : @"spatializer",YES);
            apply(helper,@"spatial-audio",@NO);
        }
        /* Effects can mutate aout directly: settings must reflect and preserve it. */
        audio_output_t *aout = vlc_player_aout_Hold(player);
        require(aout != NULL,@"live audio output held");
        var_SetString(aout,"audio-filter","scaletempo:equalizer:spatializer");
        require([[helper snapshotValues][@"macosx-redesign-equalizer"] boolValue],@"direct Effects equalizer change appears in settings");
        require([[helper snapshotValues][@"macosx-redesign-spatial-mode"] isEqual:@"spatializer"],@"direct Effects spatializer change appears in settings");
        apply(helper,@"spatial-audio",@NO); apply(helper,@"spatial-audio",@YES);
        require([[helper snapshotValues][@"macosx-redesign-spatial-mode"] isEqual:@"spatializer"],@"off/on preserves direct Effects spatial selection");
        apply(helper,@"spatial-audio",@NO); apply(helper,@"equalizer",@NO);
        config_PutFloat("compressor-threshold",-10); var_SetFloat(aout,"compressor-threshold",-12);
        unsigned compressorLoads = atomic_load(&evidence->loaded[2]);
        apply(helper,@"night-mode",@YES);
        pumpUntil(^BOOL { return atomic_load(&evidence->loaded[2]) > compressorLoads; },@"night mode loads real compressor");
        require([[helper snapshotValues][@"macosx-redesign-night-mode"] boolValue],@"night-mode reports actual active preset");
        NSDictionary *preset = @{@"compressor-rms-peak":@0.2,@"compressor-attack":@5,@"compressor-release":@200,
            @"compressor-threshold":@(-20),@"compressor-ratio":@8,@"compressor-knee":@6,@"compressor-makeup-gain":@6};
        for (NSString *name in preset)
            require(fabsf(config_GetFloat(name.UTF8String)-[preset[name] floatValue]) < .001 && fabsf(var_GetFloat(aout,name.UTF8String)-[preset[name] floatValue]) < .001,@"night preset sets actual persisted and live compressor parameters");
        apply(helper,@"night-mode",@NO);
        require(fabsf(config_GetFloat("compressor-threshold")+10) < .001 && fabsf(var_GetFloat(aout,"compressor-threshold")+12) < .001 && ![[helper snapshotValues][@"macosx-redesign-compressor"] boolValue],@"night off restores distinct configured/live prior compressor parameters and disabled state");
        apply(helper,@"compressor",@YES); apply(helper,@"night-mode",@YES); apply(helper,@"night-mode",@NO);
        require([[helper snapshotValues][@"macosx-redesign-compressor"] boolValue] && ![[helper snapshotValues][@"macosx-redesign-night-mode"] boolValue],@"night off keeps separately enabled compressor");
        apply(helper,@"night-mode",@YES);
        config_PutFloat("compressor-threshold",-15); var_SetFloat(aout,"compressor-threshold",-15);
        require(![[helper snapshotValues][@"macosx-redesign-night-mode"] boolValue],@"manual compressor edit no longer claims the night preset");
        apply(helper,@"night-mode",@NO);
        require(config_GetFloat("compressor-threshold") == -15 && var_GetFloat(aout,"compressor-threshold") == -15,@"manual compressor edit survives disabling night mode");
        apply(helper,@"compressor",@NO);
        config_PutPsz("audio-filter","scaletempo:compressor");
        apply(helper,@"night-mode",@YES); apply(helper,@"night-mode",@NO);
        require(contains(readChain(NULL),@"compressor") && !contains(readChain(aout),@"compressor"),@"night off preserves a separately configured next-media compressor without enabling it live");
        config_PutPsz("audio-filter","scaletempo");
        apply(helper,@"night-mode",@YES);
        config_ResetAll();
        /* Keep the test's no-autosave contract after resetting option defaults. */
        config_PutInt("ignore-config",1);
        require(var_InheritBool(vlc,"ignore-config"),@"engine still ignores personal config after Reset All");
        [helper resetAfterConfigurationReset];
        require(![[helper snapshotValues][@"macosx-redesign-night-mode"] boolValue] && [readChain(aout) isEqual:readChain(NULL)],@"Reset All disables Night and applies the newly reset default filter chain");
        require(config_GetFloat("compressor-threshold") == -11 && var_GetFloat(aout,"compressor-threshold") == -11,@"Reset All applies compressor defaults without restoring prior custom Night values");
        require(config_GetFloat("equalizer-preamp") == 12 && var_GetFloat(aout,"equalizer-preamp") == 12,@"Reset All clears cached custom equalizer preamp");
        vlc_player_Lock(player); float rate = vlc_player_GetRate(player); vlc_player_Unlock(player);
        vlc_playlist_Lock(playlist); require(vlc_playlist_Count(playlist) == 1,@"preferences preserve queue count"); vlc_playlist_Unlock(playlist);
        vlc_player_Lock(player);
        require(vlc_player_GetCurrentMedia(player) == media && vlc_player_GetState(player) == VLC_PLAYER_STATE_PLAYING && rate == initialRate,@"preferences preserve current media, playing state and rate");
        const struct input_stats_t *stats = vlc_player_GetStatistics(player);
        require(stats && stats->i_decoded_audio > 0 && stats->i_played_abuffers > 0,@"real audio remains decoded and submitted to output");
        NSLog(@"Actual audio preferences PCM decoded=%llu played=%llu",(unsigned long long)stats->i_decoded_audio,(unsigned long long)stats->i_played_abuffers);
        vlc_player_Unlock(player);
        require(initialVolume == vlc_player_aout_GetVolume(player),[NSString stringWithFormat:@"effect preference changes preserve player volume %g -> %g",initialVolume,vlc_player_aout_GetVolume(player)]);
        require(atomic_load(&evidence->failures) == 0,@"all requested modules successfully build audio filtering pipelines");
        config_PutInt("audio-bitexact",1);
        require(![helper availabilityForOption:@"macosx-redesign-normvol"] && ![helper applyOption:@"macosx-redesign-normvol" value:@YES error:&error],@"bit-exact bypass cannot claim enabled effects");
        vlc_playlist_t *bitexactPlaylist = vlc_playlist_New(VLC_OBJECT(intf),VLC_PLAYLIST_PREPARSING_DISABLED,1,0);
        require(bitexactPlaylist != NULL,@"isolated cached bit-exact playlist created");
        vlc_player_t *bitexactPlayer = vlc_playlist_GetPlayer(bitexactPlaylist);
        audio_output_t *bitexactAout = vlc_player_aout_Hold(bitexactPlayer);
        require(bitexactAout != NULL && aout_owner(bitexactAout)->bitexact,@"actual output owner caches bit-exact at creation");
        config_PutInt("audio-bitexact",0);
        MXRAudioPreferenceServices *bitexactHelper = [[MXRAudioPreferenceServices alloc] initWithPlayer:bitexactPlayer];
        require(![bitexactHelper availabilityForOption:@"macosx-redesign-normvol"] && ![bitexactHelper applyOption:@"macosx-redesign-normvol" value:@YES error:&error],@"global config false cannot enable filters on cached bit-exact output");
        var_SetString(bitexactAout,"audio-filter","scaletempo:normvol");
        require(![[bitexactHelper snapshotValues][@"macosx-redesign-normvol"] boolValue],@"bypassed output does not claim a real enabled normalization filter");
        [bitexactHelper shutdown]; aout_Release(bitexactAout);
        aout_Release(aout);
        [helper shutdown];
        require(![helper applyOption:@"macosx-redesign-normvol" value:@YES error:&error] && error.code == ECANCELED,@"shutdown rejects later preference commands");
        __block BOOL stopped = NO;
        MXRNativeDiagnosticsPhase("shutdown requested");
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
            MXRNativeDiagnosticsPhase("vlc_playlist_Delete(bit-exact playlist)");
            vlc_playlist_Delete(bitexactPlaylist);
            MXRNativeDiagnosticsPhase("input_item_Release + vlc_object_delete(intf)");
            input_item_Release(media); vlc_object_delete(intf);
            MXRNativeDiagnosticsPhase("libvlc_InternalCleanup");
            libvlc_InternalCleanup(vlc);
            MXRNativeDiagnosticsPhase("libvlc_InternalDestroy");
            libvlc_InternalDestroy(vlc);
            MXRNativeDiagnosticsPhase("engine destroyed");
            dispatch_async(dispatch_get_main_queue(),^{ stopped = YES; });
        });
        pumpUntil(^BOOL { return stopped; },@"native engine shuts down cleanly");
        NSLog(@"PASS actual audio filter loads, PCM, live/persisted parameters, unavailable modules and queue preservation");
    }
    return 0;
}
