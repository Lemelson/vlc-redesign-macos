/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later.
 * Integration smoke test linked against the actual VLC core, no mock engine. */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#import <Cocoa/Cocoa.h>
#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_playlist.h>
#include <vlc_player.h>
#include <vlc_input_item.h>
#include <vlc_window.h>
#include <vlc_configuration.h>
#include <stdatomic.h>
/* Core lifecycle signatures, exported by libvlccore. */
extern libvlc_int_t *libvlc_InternalCreate(void);
extern int libvlc_InternalInit(libvlc_int_t *,int,const char *[]);
extern void libvlc_InternalCleanup(libvlc_int_t *);
extern void libvlc_InternalDestroy(libvlc_int_t *);
#import "MXRBridgeInternal.h"
#if __has_include("MXRAudioPreferenceServices.h")
#import "MXRAudioPreferenceServices.h"
#endif
@interface MXRServicesBridge (RestoreSmoke)
- (void)applyRestoreQueryForURL:(NSString *)url;
@end
static void Require(BOOL condition,NSString *message) { if(!condition) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); } }
static void ConsumeAudio(void *opaque,const void *data,unsigned samples,int64_t pts) { VLC_UNUSED(opaque); VLC_UNUSED(data); VLC_UNUSED(samples); VLC_UNUSED(pts); }
static _Atomic(float) RequestedOutputVolume;
static int ApplyOutputVolume(void *opaque,float volume,bool mute) { VLC_UNUSED(opaque); VLC_UNUSED(mute); atomic_store(&RequestedOutputVolume,volume); return 0; }
static NSString *ItemOption(input_item_t *item,NSString *name) {
    NSString *value=nil; NSString *prefix=[name stringByAppendingString:@"="]; vlc_mutex_lock(&item->lock);
    for(int i=0;i<item->i_options;i++) { const char *raw=item->ppsz_options[i]; if(*raw==':') raw++; NSString *option=[NSString stringWithUTF8String:raw]; if([option hasPrefix:prefix]) { Require(item->optflagv[i]&VLC_INPUT_OPTION_TRUSTED,@"privacy option is trusted by the input"); value=[option substringFromIndex:prefix.length]; } }
    vlc_mutex_unlock(&item->lock); return value;
}
int main(int argc,const char **argv) {
    @autoreleasepool {
        libvlc_int_t *instance=libvlc_InternalCreate(); Require(instance!=NULL,@"libvlc create");
        BOOL memoryAudio=getenv("MXR_SMOKE_AMEM_VOLUME")!=NULL;
        if(memoryAudio) { var_Create(instance,"amem-play",VLC_VAR_ADDRESS); var_SetAddress(instance,"amem-play",ConsumeAudio); var_Create(instance,"amem-set-volume",VLC_VAR_ADDRESS); var_SetAddress(instance,"amem-set-volume",ApplyOutputVolume); }
        NSString *configPath=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"mxr-bridge-%@.conf",NSUUID.UUID.UUIDString]];
        NSString *aliasConfigPath=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"mxr-bridge-alias-%@.conf",NSUUID.UUID.UUIDString]];
        NSString *configArg=[@"--config=" stringByAppendingString:configPath];
        const char *options[]={"bridge-smoke","--ignore-config","--no-media-library","--no-video",memoryAudio?"--aout=amem":"--aout=dummy","--no-plugins-cache","--no-metadata-network-access","--no-auto-preparse",configArg.UTF8String};
        Require(libvlc_InternalInit(instance,9,options)==VLC_SUCCESS,@"libvlc initialization");
        intf_thread_t *intf=vlc_object_create(VLC_OBJECT(instance),sizeof(*intf)); Require(intf!=NULL,@"interface object");
        vlc_playlist_t *playlist=vlc_intf_GetMainPlaylist(intf); Require(playlist!=NULL,@"playlist");
        MXRServicesBridge *bridge=[[MXRServicesBridge alloc] initWithPlaylist:playlist interface:intf]; Require(bridge!=nil,@"services init");
        BOOL appOptions=getenv("MXR_SMOKE_APP_OPTIONS")!=NULL;
        if(appOptions) Require(config_FindConfig("macosx-redesign-remember-position")!=NULL,@"actual redesign plugin registers app options");
        for(id value in bridge.capabilities.allValues) Require(CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID(),@"public capability flags are Foundation booleans");
        NSError *error=nil;
        Require([bridge performCommand:@"setVolume" service:@"player" arguments:@{@"value":@2.5} error:&error],@"accept startup volume until audio output is ready");
        Require([[[bridge snapshotForService:@"player"] objectForKey:@"volume"] doubleValue]==2.5,@"pending startup volume snapshot");
        Require(![bridge performCommand:@"setVolume" service:@"player" arguments:@{@"value":@3.1} error:&error],@"reject volume beyond configured engine range");
        NSDictionary *settings=[bridge snapshotForService:@"settings"]; Require([settings[@"options"] count]>100,@"real settings schema");
        NSDictionary *values=settings[@"values"]; Require([values[@"audio"] isKindOfClass:NSNumber.class],@"boolean value");
        Require([values[@"network-caching"] isKindOfClass:NSNumber.class],@"integer value");
        Require([values[@"audio-language"] isKindOfClass:NSString.class],@"string value");
        Require([values[@"rate"] isKindOfClass:NSNumber.class],@"float value");
        Require([values[@"macosx-redesign-sub-size-mode"] isEqual:@"relative"]&&[values[@"macosx-redesign-sub-position"] isEqual:@"bottom"],@"unsupported subtitle controls describe actual read-only state");
        for(NSDictionary *option in settings[@"options"]) Require(![option[@"name"] isEqual:@"macosx-redesign-sub-position"],@"unsupported controls have no writable metadata"); /* Pixel sizes are supported: MXREffectsServices applies sub-size-mode. */
        __block BOOL choicesDone=NO; __block NSDictionary *dynamicChoices=nil;
        [bridge request:@"choices" service:@"settings" arguments:@{@"name":@"restore-playback-pos"} completion:^(NSDictionary *reply,NSError *failure){ Require(NSThread.isMainThread,@"dynamic choice completion runs on main"); Require(failure==nil,@"actual config choices"); dynamicChoices=reply; choicesDone=YES; }];
        NSDate *choicesDeadline=[NSDate dateWithTimeIntervalSinceNow:5];
        while(!choicesDone&&choicesDeadline.timeIntervalSinceNow>0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        Require(choicesDone&&[dynamicChoices[@"choices"] count]==3,@"worker returns actual restore choice list");
        Require([bridge performCommand:@"set" service:@"settings" arguments:@{@"name":@"network-caching",@"value":@2345,@"apply":@"next-media"} error:&error],@"set integer config");
        Require(config_GetInt("network-caching")==2345,@"integer read-your-writes");
        Require([bridge performCommand:@"set" service:@"settings" arguments:@{@"name":@"audio-language",@"value":@"ru",@"apply":@"next-media"} error:&error],@"set string config");
        Require(![bridge performCommand:@"set" service:@"settings" arguments:@{@"name":@"audio-language",@"value":@1} error:&error]&&error!=nil,@"reject wrong config type");
        Require([bridge performCommand:@"set" service:@"settings" arguments:@{@"name":@"save-recentplay",@"value":@NO} error:&error],@"disable actual input history");
        NSArray *items=@[@{@"url":@"file:///tmp/mxr-test-a.mp4",@"title":@"A"},@{@"url":@"file:///tmp/mxr-test-b.mp4",@"title":@"B"},@{@"url":@"file:///tmp/mxr-test-c.mp4",@"title":@"C"}];
        Require([bridge performCommand:@"insert" service:@"queue" arguments:@{@"items":items,@"index":@(-1)} error:&error],@"insert actual queue inputs");
        NSDictionary *queue=[bridge snapshotForService:@"queue"]; Require([queue[@"items"] count]==3,@"queue count");
        vlc_playlist_Lock(playlist); input_item_t *privateItem=vlc_playlist_item_GetMedia(vlc_playlist_Get(playlist,0));
        Require([ItemOption(privateItem,@"save-recentplay") isEqual:@"0"],@"history opt-out reaches actual input item");
        int privacyOptionCount=privateItem->i_options; vlc_playlist_Unlock(playlist);
        Require([bridge performCommand:@"set" service:@"settings" arguments:@{@"name":@"save-recentplay",@"value":@YES} error:&error],@"enable future input history");
        vlc_playlist_Lock(playlist); Require([ItemOption(privateItem,@"save-recentplay") isEqual:@"1"]&&privateItem->i_options==privacyOptionCount,@"privacy updates replace options without growing the input"); vlc_playlist_Unlock(playlist);
        if(appOptions) {
            Require([bridge performCommand:@"set" service:@"settings" arguments:@{@"name":@"macosx-redesign-remember-position",@"value":@NO} error:&error],@"disable actual playback position");
            vlc_playlist_Lock(playlist); Require([ItemOption(privateItem,@"save-recentplay") isEqual:@"0"]&&[ItemOption(privateItem,@"restore-playback-pos") isEqual:@"0"],@"remember opt-out reaches trusted input options"); vlc_playlist_Unlock(playlist);
            Require([bridge performCommand:@"set" service:@"settings" arguments:@{@"name":@"macosx-redesign-remember-position",@"value":@YES} error:&error],@"restore playback position preference");
            Require([bridge performCommand:@"set" service:@"settings" arguments:@{@"name":@"macosx-redesign-history-exclude",@"value":@"priváte"} error:&error],@"set accented history exclusion");
            Require([bridge performCommand:@"insert" service:@"queue" arguments:@{@"items":@[@{@"url":@"file:///private/tmp/Pr%C3%ADvate.mp4"}],@"index":@(-1)} error:&error],@"insert excluded filename");
            vlc_playlist_Lock(playlist); input_item_t *excluded=vlc_playlist_item_GetMedia(vlc_playlist_Get(playlist,vlc_playlist_Count(playlist)-1));
            Require([ItemOption(excluded,@"save-recentplay") isEqual:@"0"]&&[ItemOption(excluded,@"restore-playback-pos") isEqual:@"0"],@"native diacritic-insensitive exclusion matches Core policy");
            NSString *excludedID=[NSString stringWithFormat:@"%llu",(unsigned long long)vlc_playlist_item_GetId(vlc_playlist_Get(playlist,vlc_playlist_Count(playlist)-1))]; vlc_playlist_Unlock(playlist);
            Require([bridge performCommand:@"remove" service:@"queue" arguments:@{@"ids":@[excludedID]} error:&error],@"remove exclusion fixture");
            Require([bridge performCommand:@"set" service:@"settings" arguments:@{@"name":@"macosx-redesign-history-exclude",@"value":@""} error:&error],@"restore empty exclusions");
            Require([bridge performCommand:@"set" service:@"settings" arguments:@{@"name":@"macosx-redesign-sub-shadow",@"value":@NO} error:&error]&&config_GetInt("freetype-shadow-opacity")==0,@"subtitle shadow maps to actual renderer config");
            Require([bridge performCommand:@"set" service:@"settings" arguments:@{@"name":@"macosx-redesign-sub-background",@"value":@"box"} error:&error]&&config_GetInt("freetype-background-opacity")>0,@"subtitle box maps to actual background opacity");
        }
        NSString *first=queue[@"items"][0][@"id"];
        Require([bridge performCommand:@"move" service:@"queue" arguments:@{@"ids":@[first],@"index":@2} error:&error],@"move by actual item id");
        queue=[bridge snapshotForService:@"queue"]; Require([queue[@"items"][2][@"id"] isEqual:first],@"move result");
        Require(![bridge performCommand:@"remove" service:@"queue" arguments:@{@"ids":@[@"999999"]} error:&error],@"reject stale item id");
        Require([bridge performCommand:@"remove" service:@"queue" arguments:@{@"ids":@[first]} error:&error],@"remove real item id");
        Require([[[bridge snapshotForService:@"queue"] objectForKey:@"items"] count]==2,@"remove result");
        Require([bridge performCommand:@"setMediaStoppedAction" service:@"queue" arguments:@{@"value":@"stop"} error:&error],@"explicit stop mapping");
        Require([[[bridge snapshotForService:@"queue"] objectForKey:@"mediaStoppedAction"] intValue]==1,@"stop is upstream enum 1");
        Require([bridge performCommand:@"setBindings" service:@"shortcuts" arguments:@{@"id":@"play-pause",@"hotkeys":@[@"Ctrl+Space"],@"global":@[]} error:&error],@"hotkey name lookup");
        NSArray *actions=[bridge snapshotForService:@"shortcuts"][@"actions"]; Require(actions.count>50,@"engine hotkey actions");
        NSDictionary *editedAction=nil; for(NSDictionary *action in actions) if([action[@"id"] isEqual:@"play-pause"]) editedAction=action;
        Require([editedAction[@"hotkeys"] isEqual:@[@"Ctrl+Space"]]&&[editedAction[@"global"] count]==0,@"edited hotkeys snapshot reads current saved config");
        Require(![bridge performCommand:@"unsupported" service:@"player" arguments:@{} error:&error],@"unavailable command reports error");
#if __has_include("MXRAudioServices.h")
        Require([bridge.capabilities[@"stereoTest"] boolValue],@"real stereo-test player capability");
        Require([bridge.capabilities[@"supportsWaveform"] boolValue],@"actual PCM waveform capability");
        Require([[bridge snapshotForService:@"audioTest"][@"state"] isEqual:@"idle"],@"speaker-test snapshot route");
#else
        Require(![bridge.capabilities[@"stereoTest"] boolValue],@"missing speaker helper is unavailable");
        Require(![bridge.capabilities[@"supportsWaveform"] boolValue],@"missing waveform helper is unavailable");
#endif
        Require(![bridge performCommand:@"answerRestorePrompt" service:@"player" arguments:@{@"resume":@YES} error:&error],@"stale resume cannot reach null engine input");
        NSDictionary *player=[bridge snapshotForService:@"player"];
        Require(CFGetTypeID((__bridge CFTypeRef)player[@"videoEffects"][@"colors"][@"cartoon"])==CFBooleanGetTypeID(),@"effect JSON booleans");
        Require(CFGetTypeID((__bridge CFTypeRef)player[@"audioEffects"][@"equalizer"][@"twoPass"])==CFBooleanGetTypeID(),@"equalizer JSON boolean");
        for(NSString *key in @[@"bold",@"shadow",@"background",@"useEmbeddedStyles"]) Require(CFGetTypeID((__bridge CFTypeRef)player[@"subtitleStyle"][key])==CFBooleanGetTypeID(),[@"subtitle JSON boolean " stringByAppendingString:key]);
        NSMutableDictionary *video=[player[@"videoEffects"] mutableCopy],*essential=[video[@"essential"] mutableCopy]; essential[@"hue"]=@(-30); essential[@"isEnabled"]=@YES; video[@"essential"]=essential;
        Require([bridge performCommand:@"setVideoEffects" service:@"player" arguments:video error:&error],[NSString stringWithFormat:@"set negative hue: %@",error]);
        Require(config_GetFloat("hue")==-30,@"VLC4 hue range");
        Require([bridge performCommand:@"setAudioEffects" service:@"player" arguments:player[@"audioEffects"] error:&error],[NSString stringWithFormat:@"audio effects roundtrip: %@",error]);
        NSMutableDictionary *audio=[player[@"audioEffects"] mutableCopy],*eq=[audio[@"equalizer"] mutableCopy];
        eq[@"isEnabled"]=@YES; eq[@"presetID"]=@"rock"; eq[@"preamp"]=@5; eq[@"bands"]=@[@8,@4.8,@(-5.6),@(-8),@(-3.2),@4,@8.8,@11.2,@11.2,@11.2]; audio[@"equalizer"]=eq;
        Require([bridge performCommand:@"setAudioEffects" service:@"player" arguments:audio error:&error],@"select real equalizer preset");
        Require([[[bridge snapshotForService:@"player"] objectForKey:@"audioEffects"][@"equalizer"][@"presetID"] isEqual:@"rock"],@"preset snapshot");
        [eq removeObjectForKey:@"presetID"]; NSMutableArray *customBands=[eq[@"bands"] mutableCopy]; customBands[0]=@9; eq[@"bands"]=customBands;
        Require([bridge performCommand:@"setAudioEffects" service:@"player" arguments:audio error:&error],@"edit custom equalizer band");
        Require([bridge snapshotForService:@"player"][@"audioEffects"][@"equalizer"][@"presetID"]==nil,@"custom preset remains nil");
#if __has_include("MXRAudioPreferenceServices.h")
        if(appOptions) {
            Require([bridge performCommand:@"set" service:@"settings" arguments:@{@"name":@"macosx-redesign-equalizer",@"value":@YES} error:&error],@"Settings enables actual EQ");
            eq[@"isEnabled"]=@NO;
            Require([bridge performCommand:@"setAudioEffects" service:@"player" arguments:audio error:&error],@"Effects disables Settings EQ");
            Require(config_GetInt("macosx-redesign-equalizer")==0&&![[bridge snapshotForService:@"settings"][@"values"][@"macosx-redesign-equalizer"] boolValue],@"Effects reconciles persisted EQ alias");
            Require(config_SaveConfigFile(VLC_OBJECT(instance))==VLC_SUCCESS,@"save Effects-disabled alias to isolated config");
            Require([NSFileManager.defaultManager copyItemAtPath:configPath toPath:aliasConfigPath error:&error],@"retain saved alias restart fixture");
            MXRAudioPreferenceServices *restarted=[[MXRAudioPreferenceServices alloc] initWithPlayer:vlc_playlist_GetPlayer(playlist)];
            Require(![restarted.snapshotValues[@"macosx-redesign-equalizer"] boolValue],@"helper restart does not resurrect disabled EQ"); [restarted shutdown];
            eq[@"isEnabled"]=@YES; Require([bridge performCommand:@"setAudioEffects" service:@"player" arguments:audio error:&error],@"restore custom fixture EQ");
        }
#endif
        Require([bridge performCommand:@"setSubtitleStyle" service:@"player" arguments:player[@"subtitleStyle"] error:&error],[NSString stringWithFormat:@"subtitle style roundtrip: %@",error]);
        NSMutableDictionary *style=[player[@"subtitleStyle"] mutableCopy]; style[@"relativeSize"]=@20;
        Require([bridge performCommand:@"setSubtitleStyle" service:@"player" arguments:style error:&error],@"smaller subtitle selection");
        Require([[[bridge snapshotForService:@"player"] objectForKey:@"subtitleStyle"][@"relativeSize"] intValue]==20,@"subtitle relative selection roundtrip");
        Require([bridge performCommand:@"setTrackDefaults" service:@"player" arguments:@{@"audioTrack":@2,@"subtitleLanguage":@"ru"} error:&error],@"track defaults");
        Require(config_GetInt("audio-track")==1,@"one-based track default mapping");
        if(argc>2) {
            /* The service hands decoded frames to Swift as a CGImage (no PNG round trip). */
            __block BOOL completed=NO; __block id image=nil; __block NSError *thumbnailError=nil;
            NSString *url=[[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]] absoluteString];
            [bridge request:@"seekPreview" service:@"thumbnails" arguments:@{@"media":@{@"url":url},@"time":@500000,@"width":@160,@"height":@90} completion:^(NSDictionary *reply,NSError *failure){ image=reply[@"image"]; thumbnailError=failure; completed=YES; }];
            NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:15];
            while(!completed&&deadline.timeIntervalSinceNow>0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
            Require(completed&&image!=nil&&CFGetTypeID((__bridge CFTypeRef)image)==CGImageGetTypeID(),[NSString stringWithFormat:@"actual thumbnail image: %@",thumbnailError]);
            CGImageRef frame=(__bridge CGImageRef)image;
            Require(CGImageGetWidth(frame)==160&&CGImageGetHeight(frame)==90,[NSString stringWithFormat:@"thumbnail fits the requested 160x90 box at 16:9 (got %zux%zu)",CGImageGetWidth(frame),CGImageGetHeight(frame)]);
        }
        if(argc>3) {
            Require([bridge performCommand:@"setTrackDefaults" service:@"player" arguments:@{@"subtitleLanguage":@"ru"} error:&error],@"restore automatic main audio selection");
            NSString *audioURL=[[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[3]]] absoluteString];
            Require([bridge performCommand:@"playNow" service:@"queue" arguments:@{@"items":@[@{@"url":audioURL}],@"index":@0} error:&error],@"play actual audio file");
            NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5]; NSDictionary *playing;
            do { [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]]; playing=[bridge snapshotForService:@"player"]; } while(deadline.timeIntervalSinceNow>0 && (![playing[@"media"][@"artist"] isEqual:@"Bridge Artist"] || [playing[@"audioTracks"] count]==0));
            Require([playing[@"media"][@"kind"] isEqual:@"audio"],@"actual audio media classification");
            Require([playing[@"media"][@"artist"] isEqual:@"Bridge Artist"]&&[playing[@"media"][@"album"] isEqual:@"Bridge Album"],@"actual demux artist and album metadata");
            Require([playing[@"audioTracks"] count]>0,@"actual audio track enumeration");
            Require([playing[@"audioEffects"][@"equalizer"][@"bands"][0] doubleValue]==9,@"active audio output keeps custom gain");
            if(memoryAudio) {
                NSDate *volumeDeadline=[NSDate dateWithTimeIntervalSinceNow:1];
                while(fabsf(atomic_load(&RequestedOutputVolume)-2.5f)>=0.001f&&volumeDeadline.timeIntervalSinceNow>0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
                Require(fabsf(atomic_load(&RequestedOutputVolume)-2.5f)<0.001f,[NSString stringWithFormat:@"actual amem volume callback receives startup 250 percent volume (received %f)",atomic_load(&RequestedOutputVolume)]);
            }
            /* "Start playing when opened" off while another media plays: the player defers the
             * new input to its destructor thread, so only an item option can pause it. */
            vlc_player_t *engine=vlc_playlist_GetPlayer(playlist);
            enum vlc_player_state (^waitState)(enum vlc_player_state,double)=^enum vlc_player_state(enum vlc_player_state wanted,double seconds) {
                NSDate *until=[NSDate dateWithTimeIntervalSinceNow:seconds]; enum vlc_player_state state;
                do { [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
                     vlc_player_Lock(engine); state=vlc_player_GetState(engine); vlc_player_Unlock(engine); } while(state!=wanted&&until.timeIntervalSinceNow>0);
                return state;
            };
            Require([bridge performCommand:@"playNow" service:@"queue" arguments:@{@"items":@[@{@"url":audioURL}],@"index":@0} error:&error],@"autoplay open");
            Require(waitState(VLC_PLAYER_STATE_PLAYING,5)==VLC_PLAYER_STATE_PLAYING,@"autoplay open plays");
            Require([bridge performCommand:@"playNow" service:@"queue" arguments:@{@"items":@[@{@"url":audioURL}],@"index":@0,@"startPaused":@YES} error:&error],@"paused open while playing");
            Require(waitState(VLC_PLAYER_STATE_PAUSED,5)==VLC_PLAYER_STATE_PAUSED,@"paused open replaces a playing media and stays paused");
            Require(waitState(VLC_PLAYER_STATE_PLAYING,1)==VLC_PLAYER_STATE_PAUSED,@"paused open does not resume by itself");
            vlc_playlist_Lock(playlist); input_item_t *opened=vlc_playlist_item_GetMedia(vlc_playlist_Get(playlist,0)); BOOL leaked=NO;
            vlc_mutex_lock(&opened->lock); for(int i=0;i<opened->i_options;i++) leaked|=strstr(opened->ppsz_options[i],"start-paused")!=NULL; vlc_mutex_unlock(&opened->lock);
            vlc_playlist_Unlock(playlist);
            Require(!leaked,@"start-paused is one-shot and leaves the queue item");
            Require([bridge performCommand:@"play" service:@"queue" arguments:@{@"index":@0} error:&error],@"replay the paused-opened item");
            Require(waitState(VLC_PLAYER_STATE_PLAYING,5)==VLC_PLAYER_STATE_PLAYING,@"replaying the paused-opened item plays");
            /* A Stop that lands before the deferred paused start opens (the player then reports
             * NULL, as it does when vlc_player_input_New fails) must not leave the one-shot
             * option on the queue item for a later, ordinary play. */
            Require([bridge performCommand:@"playNow" service:@"queue" arguments:@{@"items":@[@{@"url":audioURL}],@"index":@0,@"startPaused":@YES} error:&error],@"paused open while playing, then stop");
            vlc_playlist_Lock(playlist); vlc_playlist_Stop(playlist); vlc_playlist_Unlock(playlist);
            Require(waitState(VLC_PLAYER_STATE_STOPPED,5)==VLC_PLAYER_STATE_STOPPED,@"stop after a paused open");
            vlc_playlist_Lock(playlist); opened=vlc_playlist_item_GetMedia(vlc_playlist_Get(playlist,0)); leaked=NO;
            vlc_mutex_lock(&opened->lock); for(int i=0;i<opened->i_options;i++) leaked|=strstr(opened->ppsz_options[i],"start-paused")!=NULL; vlc_mutex_unlock(&opened->lock);
            vlc_playlist_Unlock(playlist);
            Require(!leaked,@"a paused open cut short by Stop leaves no start-paused on the queue item");
            Require([bridge performCommand:@"play" service:@"queue" arguments:@{@"index":@0} error:&error],@"play the item after the cut-short paused open");
            Require(waitState(VLC_PLAYER_STATE_PLAYING,5)==VLC_PLAYER_STATE_PLAYING,@"an ordinary play after a cut-short paused open plays");
            /* C-02: a sidecar whose name holds ( ) ' is auto-detected by the input under
             * vlc_path2uri's MRL (those characters percent-encoded); an explicit add of the same
             * file through an NSURL (which leaves them alone) must select that track, never load
             * the file a second time. */
            NSString *sidecarDir=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"mxr-sidecar-%@",NSUUID.UUID.UUIDString]];
            Require([NSFileManager.defaultManager createDirectoryAtPath:sidecarDir withIntermediateDirectories:YES attributes:nil error:&error],@"sidecar fixture folder");
            NSString *sidecarMedia=[sidecarDir stringByAppendingPathComponent:@"Bridge (2020) it's.m4a"], *sidecarText=[sidecarDir stringByAppendingPathComponent:@"Bridge (2020) it's.srt"];
            Require([NSFileManager.defaultManager copyItemAtPath:[NSString stringWithUTF8String:argv[3]] toPath:sidecarMedia error:&error],@"sidecar fixture media");
            Require([@"1\n00:00:00,000 --> 00:00:30,000\nSidecar cue\n" writeToFile:sidecarText atomically:YES encoding:NSUTF8StringEncoding error:&error],@"sidecar fixture subtitles");
            NSArray *(^subtitleTracks)(void)=^NSArray *{ return [bridge snapshotForService:@"player"][@"subtitleTracks"]; };
            Require([bridge performCommand:@"playNow" service:@"queue" arguments:@{@"items":@[@{@"url":[NSURL fileURLWithPath:sidecarMedia].absoluteString}],@"index":@0} error:&error],@"play media with a punctuated sidecar");
            Require(waitState(VLC_PLAYER_STATE_PLAYING,5)==VLC_PLAYER_STATE_PLAYING,@"media with a punctuated sidecar plays");
            NSDate *sidecarDeadline=[NSDate dateWithTimeIntervalSinceNow:5];
            while(subtitleTracks().count==0&&sidecarDeadline.timeIntervalSinceNow>0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
            NSArray *detected=subtitleTracks();
            Require(detected.count==1&&[detected[0][@"external"] boolValue],[NSString stringWithFormat:@"the input auto-detects the punctuated sidecar as one external track: %@",detected]);
            NSString *sidecarURL=[NSURL fileURLWithPath:sidecarText].absoluteString;
            Require([sidecarURL containsString:@"(2020)"]&&[sidecarURL containsString:@"'"],@"the explicit add uses an NSURL with literal ( ) '");
            Require([bridge performCommand:@"unselectTracks" service:@"player" arguments:@{@"kind":@"subtitle"} error:&error],@"switch the detected sidecar off");
            Require([bridge performCommand:@"addExternalTrack" service:@"player" arguments:@{@"kind":@"subtitle",@"url":sidecarURL,@"select":@YES} error:&error],@"explicit add of the detected sidecar");
            NSDate *settle=[NSDate dateWithTimeIntervalSinceNow:1.5];
            while(settle.timeIntervalSinceNow>0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
            NSArray *afterAdd=subtitleTracks();
            Require(afterAdd.count==1,[NSString stringWithFormat:@"adding a detected punctuated sidecar does not load it twice: %@",afterAdd]);
            Require([afterAdd[0][@"selected"] boolValue]&&[afterAdd[0][@"id"] isEqual:detected[0][@"id"]],@"adding a detected punctuated sidecar selects the existing track");
            [NSFileManager.defaultManager removeItemAtPath:sidecarDir error:nil];
            /* Live run 1: repeated jump hotkeys showed the OSD time one jump behind the seek bar
             * ("00:48" while the bar read 00:38). The text must be the core's own seek target,
             * which adds each jump to a seek still in flight. */
            {
                Require(intf_Create(instance,"hotkeys")==VLC_SUCCESS,@"hotkeys interface handles jump actions");
                config_PutInt("extrashort-jump-size",1);
                vlc_playlist_Lock(playlist); vlc_playlist_Stop(playlist); vlc_playlist_Unlock(playlist);
                Require(waitState(VLC_PLAYER_STATE_STOPPED,5)==VLC_PLAYER_STATE_STOPPED,@"the sidecar media stops before the jump fixture");
                Require([bridge performCommand:@"playNow" service:@"queue" arguments:@{@"items":@[@{@"url":audioURL}],@"index":@0} error:&error],@"play the jump fixture");
                Require(waitState(VLC_PLAYER_STATE_PLAYING,5)==VLC_PLAYER_STATE_PLAYING,@"jump fixture plays");
                NSDate *clock=[NSDate dateWithTimeIntervalSinceNow:3]; vlc_tick_t playing=VLC_TICK_INVALID;
                do { [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
                     vlc_player_Lock(engine); playing=vlc_player_GetTime(engine); vlc_player_Unlock(engine);
                } while(playing==VLC_TICK_INVALID&&clock.timeIntervalSinceNow>0);
                vlc_player_Lock(engine); vlc_player_Pause(engine); vlc_player_Unlock(engine);
                Require(waitState(VLC_PLAYER_STATE_PAUSED,5)==VLC_PLAYER_STATE_PAUSED,@"jump fixture pauses");
                vlc_tick_t start=VLC_TICK_INVALID,length=VLC_TICK_INVALID; bool seekable=false;
                NSDate *ready=[NSDate dateWithTimeIntervalSinceNow:3];
                do { [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
                     vlc_player_Lock(engine); start=vlc_player_GetTime(engine); length=vlc_player_GetLength(engine); seekable=vlc_player_CanSeek(engine); vlc_player_Unlock(engine);
                } while((start==VLC_TICK_INVALID||length==VLC_TICK_INVALID||!seekable)&&ready.timeIntervalSinceNow>0);
                Require(start!=VLC_TICK_INVALID&&seekable&&start+vlc_tick_from_sec(2)<VLC_TICK_0+length,[NSString stringWithFormat:@"paused jump fixture has room for two 1 s jumps (time %lld, length %lld, seekable %d)",(long long)start,(long long)length,seekable]);
                Require([bridge performCommand:@"trigger" service:@"shortcuts" arguments:@{@"id":@"jump+extrashort"} error:&error],[NSString stringWithFormat:@"first jump hotkey: %@",error]);
                Require([bridge performCommand:@"trigger" service:@"shortcuts" arguments:@{@"id":@"jump+extrashort"} error:&error],@"second jump hotkey, before the first seek lands");
                char target[MSTRTIME_MAX_SIZE],total[MSTRTIME_MAX_SIZE];
                vlc_tick_to_str(target,start+vlc_tick_from_sec(2)-VLC_TICK_0); vlc_tick_to_str(total,length);
                NSString *expected=[NSString stringWithFormat:@"%s / %s",target,total];
                NSDate *shown=[NSDate dateWithTimeIntervalSinceNow:1];
                while(![[bridge snapshotForService:@"osd"][@"text"] isEqual:expected]&&shown.timeIntervalSinceNow>0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
                Require([[bridge snapshotForService:@"osd"][@"text"] isEqual:expected],[NSString stringWithFormat:@"the OSD shows the second jump's target %@, not %@",expected,[bridge snapshotForService:@"osd"][@"text"]]);
                /* A jump that does not seek (a negative jump size: hotkeys.c skips it) shows nothing,
                 * and the next unrelated seek (the seek bar's) is not taken for its target. */
                config_PutInt("extrashort-jump-size",-1);
                NSUInteger jumpSerial=[[bridge snapshotForService:@"osd"][@"serial"] unsignedIntegerValue];
                Require([bridge performCommand:@"trigger" service:@"shortcuts" arguments:@{@"id":@"jump+extrashort"} error:&error],@"a jump hotkey that does not seek");
                vlc_player_Lock(engine); vlc_player_SeekByTime(engine,start,VLC_PLAYER_SEEK_PRECISE,VLC_PLAYER_WHENCE_ABSOLUTE); vlc_player_Unlock(engine);
                NSDate *quiet=[NSDate dateWithTimeIntervalSinceNow:0.5];
                while(quiet.timeIntervalSinceNow>0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
                Require([[bridge snapshotForService:@"osd"][@"serial"] unsignedIntegerValue]==jumpSerial,[NSString stringWithFormat:@"a seek-bar seek after a jump that did not seek shows no jump OSD, not %@",[bridge snapshotForService:@"osd"][@"text"]]);
                config_PutInt("extrashort-jump-size",1);
                /* A plain arrow jumps later on the input thread (navigation fallback). A seek-bar seek
                 * made on main right after it is not the arrow's target (critic P2: matching by count
                 * let it take the arrow's slot); the arrow shows its own target, one short jump on. */
                config_PutInt("short-jump-size",1);
                Require([bridge performCommand:@"trigger" service:@"shortcuts" arguments:@{@"id":@"nav-right"} error:&error],[NSString stringWithFormat:@"arrow hotkey: %@",error]);
                vlc_player_Lock(engine); vlc_player_SeekByTime(engine,start,VLC_PLAYER_SEEK_PRECISE,VLC_PLAYER_WHENCE_ABSOLUTE); vlc_player_Unlock(engine);
                vlc_tick_to_str(target,start+vlc_tick_from_sec(1)-VLC_TICK_0);
                NSString *arrowExpected=[NSString stringWithFormat:@"%s / %s",target,total];
                NSDate *arrowShown=[NSDate dateWithTimeIntervalSinceNow:1];
                while(![[bridge snapshotForService:@"osd"][@"text"] isEqual:arrowExpected]&&arrowShown.timeIntervalSinceNow>0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
                Require([[bridge snapshotForService:@"osd"][@"text"] isEqual:arrowExpected],[NSString stringWithFormat:@"the arrow's OSD shows its own target %@, not %@",arrowExpected,[bridge snapshotForService:@"osd"][@"text"]]);
                config_PutInt("short-jump-size",10);
                /* Fullscreen keys name what happened, like every other hotkey (D027; areas C-bridge
                 * open minor). Uses the hotkeys interface created above. */
                vlc_player_vout_SetFullscreen(engine,false);
                Require([bridge performCommand:@"trigger" service:@"shortcuts" arguments:@{@"id":@"toggle-fullscreen"} error:&error],@"fullscreen hotkey");
                Require([[bridge snapshotForService:@"osd"][@"text"] isEqual:@"Fullscreen"],[NSString stringWithFormat:@"entering fullscreen is named: %@",[bridge snapshotForService:@"osd"][@"text"]]);
                Require([bridge performCommand:@"trigger" service:@"shortcuts" arguments:@{@"id":@"leave-fullscreen"} error:&error],@"leave-fullscreen hotkey");
                Require([[bridge snapshotForService:@"osd"][@"text"] isEqual:@"Exit fullscreen"],[NSString stringWithFormat:@"leaving fullscreen is named: %@",[bridge snapshotForService:@"osd"][@"text"]]);
                NSUInteger serial=[[bridge snapshotForService:@"osd"][@"serial"] unsignedIntegerValue];
                Require([bridge performCommand:@"trigger" service:@"shortcuts" arguments:@{@"id":@"leave-fullscreen"} error:&error],@"Esc in a window");
                Require([[bridge snapshotForService:@"osd"][@"serial"] unsignedIntegerValue]==serial,@"Esc in a window shows no fullscreen text");
            }
#if __has_include("MXRAudioServices.h")
            __block BOOL waveformDone=NO; __block NSDictionary *waveform=nil; __block NSError *waveformError=nil;
            [bridge request:@"waveform" service:@"thumbnails" arguments:@{@"media":@{@"url":audioURL},@"bins":@64} completion:^(NSDictionary *reply,NSError *failure){ waveform=reply; waveformError=failure; waveformDone=YES; }];
            deadline=[NSDate dateWithTimeIntervalSinceNow:15];
            while(!waveformDone&&deadline.timeIntervalSinceNow>0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
            Require(waveformDone&&[waveform[@"samples"] count]==64,[NSString stringWithFormat:@"actual waveform route: %@",waveformError]);
            Require([waveform[@"duration"] doubleValue]>0,@"actual waveform duration");
            BOOL audible=NO; for(NSNumber *sample in waveform[@"samples"]) { Require(sample.doubleValue>=0&&sample.doubleValue<=1,@"normalized waveform samples"); audible|=sample.doubleValue>0; } Require(audible,@"waveform comes from non-silent PCM");
            Require([bridge performCommand:@"setTrackDefaults" service:@"player" arguments:@{@"audioTrack":@2} error:&error],@"hostile saved audio preference before speaker test");
            NSArray *queueBefore=[bridge snapshotForService:@"queue"][@"items"];
            __block BOOL toneDone=NO; __block NSDictionary *tone=nil; __block NSError *toneError=nil;
            [bridge request:@"start" service:@"audioTest" arguments:@{@"mode":@0} completion:^(NSDictionary *reply,NSError *failure){ tone=reply; toneError=failure; toneDone=YES; }];
            deadline=[NSDate dateWithTimeIntervalSinceNow:15];
            while(!toneDone&&deadline.timeIntervalSinceNow>0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
            Require(toneDone&&[tone[@"state"] isEqual:@"completed"],[NSString stringWithFormat:@"actual isolated speaker playback: %@",toneError]);
            NSDictionary *toneStats=[bridge snapshotForService:@"audioTest"];
            Require([toneStats[@"decodedAudio"] unsignedLongLongValue]>0&&[toneStats[@"playedAudioBuffers"] unsignedLongLongValue]>0,@"speaker test actually decodes and plays audio despite saved track defaults");
            Require([[bridge snapshotForService:@"queue"][@"items"] isEqual:queueBefore],@"speaker test preserves main playlist");
#endif
        }
        if(argc>1) {
            NSDictionary *full=[bridge snapshotForService:@"settings"];
            NSSet *names=[NSSet setWithArray:@[@"audio",@"network-caching",@"audio-language",@"rate"]];
            NSMutableArray *options=[NSMutableArray array]; NSMutableDictionary *selectedValues=[NSMutableDictionary dictionary];
            for(NSDictionary *option in full[@"options"]) if([names containsObject:option[@"name"]]) {
                [options addObject:option]; selectedValues[option[@"name"]]=full[@"values"][option[@"name"]];
            }
            NSMutableArray *selectedActions=[NSMutableArray array]; for(NSDictionary *action in actions) if([action[@"id"] isEqual:@"play-pause"]) [selectedActions addObject:action];
            NSMutableDictionary *sources=[[bridge snapshotForService:@"mediaSources"] mutableCopy];
            [sources removeObjectForKey:@"children"]; /* Personal filesystem rows remain local to the live provider. */
            NSDictionary *fixture=@{@"capabilities":bridge.capabilities,@"player":[bridge snapshotForService:@"player"],
              @"queue":[bridge snapshotForService:@"queue"],@"settings":@{@"options":options,@"values":selectedValues},
              @"shortcuts":@{@"actions":selectedActions},@"library":[bridge snapshotForService:@"library"],@"dialogs":[bridge snapshotForService:@"dialogs"],@"audioTest":[bridge snapshotForService:@"audioTest"],
              @"output":[bridge snapshotForService:@"output"],@"extensions":[bridge snapshotForService:@"extensions"],@"renderers":[bridge snapshotForService:@"renderers"],@"mediaSources":sources};
            NSData *data=[NSJSONSerialization dataWithJSONObject:fixture options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&error];
            Require(data!=nil,@"fixture JSON serialization"); Require([data writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES],@"fixture write");
        }
        /* Reproduce an external Stop before its queued main-thread state event.
         * The current media stays retained, but the core's input is already NULL. */
        vlc_playlist_Lock(playlist); int start=vlc_playlist_PlayAt(playlist,0); vlc_playlist_Unlock(playlist);
        Require(start==VLC_SUCCESS,@"start for stale resume regression");
        NSString *restoreURL=[bridge snapshotForService:@"player"][@"media"][@"url"];
        [bridge applyRestoreQueryForURL:restoreURL];
        vlc_player_t *playerHandle=vlc_playlist_GetPlayer(playlist);
        vlc_player_Lock(playerHandle); vlc_player_Stop(playerHandle); vlc_player_Unlock(playerHandle);
        Require(![bridge performCommand:@"answerRestorePrompt" service:@"player" arguments:@{@"resume":@YES} error:&error],@"external Stop rejects stale resume before event delivery");
#if __has_include("MXRAudioPreferenceServices.h")
        if(appOptions) {
            /* Exercise Reset All while a real output exists, with Night restoration state. */
            Require([bridge performCommand:@"set" service:@"settings" arguments:@{@"name":@"macosx-redesign-equalizer",@"value":@YES} error:&error],@"enable EQ before Reset All");
            Require([bridge performCommand:@"set" service:@"settings" arguments:@{@"name":@"macosx-redesign-night-mode",@"value":@YES} error:&error],@"enable Night before Reset All");
            Require([bridge performCommand:@"resetAll" service:@"settings" arguments:@{} error:&error],@"Reset All applies engine defaults");
            NSDictionary *defaults=[bridge snapshotForService:@"settings"][@"values"];
            Require(![defaults[@"macosx-redesign-equalizer"] boolValue]&&![defaults[@"macosx-redesign-night-mode"] boolValue]&&![defaults[@"macosx-redesign-compressor"] boolValue],@"Reset All disables current filters and Night request");
            audio_output_t *output=vlc_player_aout_Hold(vlc_playlist_GetPlayer(playlist));
            if(output) {
                char *chain=var_GetString(output,"audio-filter"); Require(chain==NULL||chain[0]=='\0',@"Reset All clears live default filter chain"); free(chain);
                Require(fabsf(var_GetFloat(output,"compressor-threshold")-config_GetFloat("compressor-threshold"))<0.001f,@"Reset All applies default compressor parameter without restoring prior custom value");
                Require(fabsf(var_GetFloat(output,"equalizer-preamp")-config_GetFloat("equalizer-preamp"))<0.001f,@"Reset All clears cached EQ preamp");
                aout_Release(output);
            }
            Require([bridge performCommand:@"set" service:@"settings" arguments:@{@"name":@"network-caching",@"value":@2345} error:&error],@"restore explicit saved setting after Reset All");
        }
#endif
        Require([bridge performCommand:@"save" service:@"settings" arguments:@{} error:&error],@"request explicit save");
        [bridge shutdown];
        Require(![bridge performCommand:@"clear" service:@"queue" arguments:@{} error:&error],@"commands rejected after shutdown");
        dispatch_group_t group=dispatch_group_create(); dispatch_group_async(group,dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{ [bridge finishShutdown]; });
        dispatch_group_wait(group,DISPATCH_TIME_FOREVER);
        NSString *saved=[NSString stringWithContentsOfFile:configPath encoding:NSUTF8StringEncoding error:&error]; Require([saved containsString:@"network-caching=2345"],@"quit flushes pending debounce save");
        vlc_object_delete(intf); libvlc_InternalCleanup(instance); libvlc_InternalDestroy(instance);
        if(appOptions) {
            /* A fresh VLC instance reads the actual config saved at Effects-disable time. */
            libvlc_int_t *reloaded=libvlc_InternalCreate(); Require(reloaded!=NULL,@"fresh core for saved alias restart");
            NSString *aliasArg=[@"--config=" stringByAppendingString:aliasConfigPath];
            const char *restartOptions[]={"bridge-restart","--no-media-library","--no-video","--aout=dummy","--no-plugins-cache","--no-metadata-network-access","--no-auto-preparse",aliasArg.UTF8String};
            Require(libvlc_InternalInit(reloaded,8,restartOptions)==VLC_SUCCESS,@"restart reads isolated saved configuration");
            Require(config_GetInt("macosx-redesign-equalizer")==0,@"saved Effects-disable alias remains off after real core restart");
            intf_thread_t *restartIntf=vlc_object_create(VLC_OBJECT(reloaded),sizeof(*restartIntf)); Require(restartIntf!=NULL,@"restart interface");
            MXRServicesBridge *restartBridge=[[MXRServicesBridge alloc] initWithPlaylist:vlc_intf_GetMainPlaylist(restartIntf) interface:restartIntf];
            Require(![[restartBridge snapshotForService:@"settings"][@"values"][@"macosx-redesign-equalizer"] boolValue],@"composed bridge restart does not resurrect EQ");
            [restartBridge shutdown]; dispatch_group_t restartGroup=dispatch_group_create(); dispatch_group_async(restartGroup,dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{ [restartBridge finishShutdown]; }); dispatch_group_wait(restartGroup,DISPATCH_TIME_FOREVER);
            vlc_object_delete(restartIntf); libvlc_InternalCleanup(reloaded); libvlc_InternalDestroy(reloaded);
        }
        [NSFileManager.defaultManager removeItemAtPath:configPath error:nil];
        [NSFileManager.defaultManager removeItemAtPath:aliasConfigPath error:nil];
        if(appOptions) puts("PASS: actual registered app options, alias save/restart, live Reset All and accented privacy policy");
        puts("PASS: real VLC schema, config, queue, hotkey and shutdown contracts");
    }
    return 0;
}
