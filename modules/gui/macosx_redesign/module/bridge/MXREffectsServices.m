/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#import "MXREffectsServices.h"
#import "MXRBridgeKeys.h"
#include <vlc_configuration.h>
#include <vlc_plugin.h>
#include <vlc_modules.h>
#include <vlc_aout.h>
#include <vlc_vout.h>
#include "../../../../audio_filter/equalizer_presets.h"
static NSString *ES(const char *s) { return s?([NSString stringWithUTF8String:s]?:@""):@""; }
static NSError *EE(NSString *s) { return [NSError errorWithDomain:@"MXRVLCBridge" code:7 userInfo:@{NSLocalizedDescriptionKey:s}]; }
static id Value(NSString *name,vlc_object_t *object,id fallback) {
    int type=config_GetType(name.UTF8String); if(!type) return fallback;
    BOOL live=object&&var_Type(object,name.UTF8String)!=0;
    if(type==VLC_VAR_BOOL) return (live?var_GetBool(object,name.UTF8String):config_GetInt(name.UTF8String)!=0)?@YES:@NO;
    if(type==VLC_VAR_INTEGER) return @(live?var_GetInteger(object,name.UTF8String):config_GetInt(name.UTF8String));
    if(type==VLC_VAR_FLOAT) return @(live?var_GetFloat(object,name.UTF8String):config_GetFloat(name.UTF8String));
    if(type==VLC_VAR_STRING) { char *str=live?var_GetString(object,name.UTF8String):config_GetPsz(name.UTF8String); NSString *s=ES(str); free(str); return s; }
    return fallback;
}
static NSDictionary *Color(NSInteger rgb) { return @{@"red":@((rgb>>16)&255),@"green":@((rgb>>8)&255),@"blue":@(rgb&255)}; }
static NSNumber *RGB(NSDictionary *color) { return @(([color[@"red"] intValue]<<16)|([color[@"green"] intValue]<<8)|[color[@"blue"] intValue]); }
static BOOL HasFilter(NSString *chain,NSString *name) { for(NSString *part in [chain componentsSeparatedByString:@":"]) if([[part componentsSeparatedByString:@"{"][0] isEqual:name]) return YES; return NO; }
static NSDictionary *VideoEssentialMap(void) { return @{@"hue":@"hue",@"brightness":@"brightness",@"contrast":@"contrast",@"saturation":@"saturation",@"gamma":@"gamma",@"sharpenSigma":@"sharpen-sigma",@"bandingRemovalRadius":@"gradfun-radius",@"filmGrainVariance":@"grain-variance"}; }
static NSDictionary *VideoColorsMap(void) { return @{@"extractionColor":@"extract-component",@"thresholdColor":@"colorthres-color",@"thresholdSaturation":@"colorthres-saturationthres",@"thresholdSimilarity":@"colorthres-similaritythres",@"posterizeLevel":@"posterize-level",@"gradientColor":@"gradient-color",@"gradientMode":@"gradient-mode",@"cartoon":@"gradient-cartoon",@"sepiaIntensity":@"sepia-intensity"}; }
static NSDictionary *AudioMaps(void) { return @{
    @"compressor":@{@"rmsPeak":@"compressor-rms-peak",@"attack":@"compressor-attack",@"release":@"compressor-release",@"threshold":@"compressor-threshold",@"ratio":@"compressor-ratio",@"kneeRadius":@"compressor-knee",@"makeupGain":@"compressor-makeup-gain"},
    @"spatializer":@{@"roomSize":@"spatializer-roomsize",@"width":@"spatializer-width",@"wet":@"spatializer-wet",@"dry":@"spatializer-dry",@"damp":@"spatializer-damp"},
    @"stereoWidener":@{@"delay":@"stereowiden-delay",@"feedback":@"stereowiden-feedback",@"crossfeed":@"stereowiden-crossfeed",@"dryMix":@"stereowiden-dry-mix"}}; }
static NSDictionary *MappedSnapshot(NSDictionary *map,vlc_object_t *object) {
    NSMutableDictionary *result=[NSMutableDictionary dictionary]; for(NSString *key in map) result[key]=Value(map[key],object,@0); return result;
}
/// The selected video's height in pixels (its width for portrait video, like freetype's
/// ConvertToLiveSize), or 0.
static unsigned VideoHeight(vlc_player_t *player) {
    unsigned height = 0;
    vlc_player_Lock(player);
    for (size_t i = 0; i < vlc_player_GetVideoTrackCount(player); i++) {
        const struct vlc_player_track *track = vlc_player_GetVideoTrackAt(player, i);
        if (!track->selected) continue;
        unsigned width = track->fmt.video.i_visible_width; height = track->fmt.video.i_visible_height;
        if (width && height > width) height = width;
        break;
    }
    vlc_player_Unlock(player);
    return height;
}
static BOOL PixelSizeMode(void) {
    if (!config_FindConfig("macosx-redesign-sub-size-mode")) return NO;
    char *mode = config_GetPsz("macosx-redesign-sub-size-mode");
    BOOL pixels = mode && !strcmp(mode, "pixels"); free(mode);
    return pixels;
}
/* Subtitle safe inset (live run 1: subtitles hidden under the compact library and the revealed
 * fullscreen control bar). VLC draws subtitles at the bottom of the picture; the UI reports how
 * far its overlays cover the picture, and the inset raises the subtitles through each vout's
 * "sub-margin", on top of the user's Subtitle Offset (config "sub-margin") and of any
 * subtitle-position hotkey change. Each vout records the inset it carries in SafeInsetVar, so a
 * reused vout is not raised twice and the user's offset stays readable. */
static const char SafeInsetVar[] = "macosx-redesign-sub-safe-inset";
/* The player's main vout is created as a child of its dummy vout and inherits the dummy's
 * "sub-margin" (src/input/resource.c, "pre-configured on this dummy vout"): a vout without its
 * own record carries the inset its parent carried. */
static int64_t AppliedSafeInset(vlc_object_t *vout) {
    /* Not var_InheritInteger: the record has no config item to fall back on. */
    for (vlc_object_t *object = vout; object != NULL; object = vlc_object_parent(object))
        if (var_Type(object, SafeInsetVar)) return var_GetInteger(object, SafeInsetVar);
    return 0;
}
int64_t MXRSubtitleUserMargin(vout_thread_t *vout) {
    return var_GetInteger(VLC_OBJECT(vout), "sub-margin") - AppliedSafeInset(VLC_OBJECT(vout));
}
@implementation MXREffectsServices {
    vlc_player_t *_player;
    NSInteger _relativeSize;
    BOOL _customEqualizer;
    BOOL _pixelScaleApplied;
    /* The inset in output pixels, and the lock that orders its read-modify-write of a vout's
     * margin between main (inset or style changes) and the thread that starts a vout. */
    vlc_mutex_t _safeInsetLock;
    int64_t _safeInset;
}
- (BOOL)applySubtitleSizePreference {
    /* CMP-18: VLC 4 sizes subtitle text relative to the video height (freetype font size
     * = 6.25 % of the height x sub-text-scale). An exact pixel size is that scale. */
    unsigned scale;
    if (PixelSizeMode()) {
        unsigned height = VideoHeight(_player);
        int64_t pixels = config_FindConfig("macosx-redesign-sub-pixel-size") ? config_GetInt("macosx-redesign-sub-pixel-size") : 0;
        if (!height || pixels <= 0) return NO;
        scale = (unsigned)MAX(10, MIN(500, llround(pixels * 1600.0 / height)));
        _pixelScaleApplied = YES;
    } else if (_pixelScaleApplied) {
        /* Back to relative sizes: the relative text scale preference. */
        scale = (unsigned)config_GetInt("sub-text-scale");
        _pixelScaleApplied = NO;
    } else return NO;
    vlc_player_Lock(_player);
    BOOL changed = vlc_player_GetSubtitleTextScale(_player) != scale;
    if (changed) vlc_player_SetSubtitleTextScale(_player, scale);
    vlc_player_Unlock(_player);
    return changed;
}
- (instancetype)initWithPlayer:(vlc_player_t *)player { if((self=[super init])) { _player=player; vlc_mutex_init(&_safeInsetLock); } return self; }
- (void)applySubtitleSafeInsetToVout:(vout_thread_t *)vout order:(enum vlc_vout_order)order {
    vlc_object_t *object=VLC_OBJECT(vout);
    if(order!=VLC_VOUT_ORDER_PRIMARY||var_Type(object,"sub-margin")==0) return;
    vlc_mutex_lock(&_safeInsetLock);
    int64_t desired=_safeInset,applied=AppliedSafeInset(object);
    if(desired!=applied) {
        if(!var_Type(object,SafeInsetVar)) var_Create(object,SafeInsetVar,VLC_VAR_INTEGER);
        var_SetInteger(object,SafeInsetVar,desired);
        var_SetInteger(object,"sub-margin",var_GetInteger(object,"sub-margin")-applied+desired);
    }
    vlc_mutex_unlock(&_safeInsetLock);
}
/// The user's Subtitle Offset on a vout that may carry the safe inset.
- (void)setUserSubtitleMargin:(int64_t)margin onVout:(vout_thread_t *)vout {
    vlc_object_t *object=VLC_OBJECT(vout);
    vlc_mutex_lock(&_safeInsetLock);
    var_SetInteger(object,"sub-margin",margin+AppliedSafeInset(object));
    vlc_mutex_unlock(&_safeInsetLock);
}
- (NSDictionary *)snapshot {
    vout_thread_t *vout=vlc_player_vout_Hold(_player); audio_output_t *aout=vlc_player_aout_Hold(_player);
    vlc_object_t *video=vout?VLC_OBJECT(vout):NULL,*audio=aout?VLC_OBJECT(aout):NULL;
    NSString *videoChain=Value(@"video-filter",video,@""),*audioChain=Value(@"audio-filter",audio,@"");
    NSMutableDictionary *essential=[MappedSnapshot(VideoEssentialMap(),video) mutableCopy];
    essential[@"isEnabled"]=@(HasFilter(videoChain,@"adjust")); double hue=[essential[@"hue"] doubleValue]; essential[@"hue"]=@(hue>180?hue-360:hue);
    if(!HasFilter(videoChain,@"sharpen")) essential[@"sharpenSigma"]=@0;
    if(!HasFilter(videoChain,@"gradfun")) essential[@"bandingRemovalRadius"]=@0;
    if(!HasFilter(videoChain,@"grain")) essential[@"filmGrainVariance"]=@0;
    NSMutableDictionary *colors=[MappedSnapshot(VideoColorsMap(),video) mutableCopy];
    colors[@"extractionColor"]=Color([colors[@"extractionColor"] integerValue]); colors[@"thresholdColor"]=Color([colors[@"thresholdColor"] integerValue]);
    NSDictionary *colorFilters=@{@"colorExtraction":@"extract",@"colorThreshold":@"colorthres",@"negate":@"invert",@"posterize":@"posterize",@"gradient":@"gradient",@"sepia":@"sepia"};
    for(NSString *key in colorFilters) colors[key]=@(HasFilter(videoChain,colorFilters[key]));
    NSDictionary *insetsMap=@{@"top":@"croppadd-croptop",@"bottom":@"croppadd-cropbottom",@"left":@"croppadd-cropleft",@"right":@"croppadd-cropright"};
    NSDictionary *insets=HasFilter(videoChain,@"croppadd")?MappedSnapshot(insetsMap,video):@{@"top":@0,@"bottom":@0,@"left":@0,@"right":@0};
    NSString *transform=Value(@"transform-type",video,@""),*flip=HasFilter(videoChain,@"transform")&&[transform isEqual:@"hflip"]?@"horizontal":HasFilter(videoChain,@"transform")&&[transform isEqual:@"vflip"]?@"vertical":@"none";
    double zoom=[Value(@"zoom",video,@1) doubleValue]; NSString *zoomName=[Value(@"autoscale",video,@YES) boolValue]?@"fitWindow":zoom==0.25?@"quarter":zoom==0.5?@"half":zoom==2?@"double":@"original";
    NSInteger deinterlace=[Value(@"deinterlace",video,@(-1)) integerValue];
    NSString *mode=deinterlace<0?@"automatic":deinterlace==0?@"off":Value(@"deinterlace-mode",video,@"yadif");
    NSMutableDictionary *videoEffects=[@{@"flip":flip,@"rotation":HasFilter(videoChain,@"rotate")?Value(@"rotate-angle",video,@0):@0,@"zoom":zoomName,@"hdr":@"auto",@"deinterlace":mode,@"essential":essential,@"cropInsets":insets,@"colors":colors} mutableCopy];
    NSInteger preferredResolution=config_GetInt("preferred-resolution");
    if(preferredResolution>0) videoEffects[@"resolution"]=[NSString stringWithFormat:@"%ldp",(long)preferredResolution];
    NSString *aspect=Value(@"aspect-ratio",video,@""),*crop=Value(@"crop",video,@""); if(aspect.length) videoEffects[@"aspectRatio"]=aspect; if(crop.length) videoEffects[@"crop"]=crop;
    NSMutableArray *bands=[NSMutableArray array]; NSScanner *scanner=[NSScanner scannerWithString:Value(@"equalizer-bands",audio,@"")]; double band;
    while(bands.count<10 && [scanner scanDouble:&band]) [bands addObject:@(band)]; while(bands.count<10) [bands addObject:@0];
    NSMutableDictionary *audioEffects=[NSMutableDictionary dictionary]; NSInteger stereo=[Value(@"stereo-mode",audio,@0) integerValue];
    audioEffects[@"stereoMode"]=[Value(@"mix-mode",audio,@0) integerValue]==AOUT_MIX_MODE_BINAURAL?@6:@(stereo);
    NSMutableDictionary *equalizer=[@{@"isEnabled":@(HasFilter(audioChain,@"equalizer")),@"preamp":Value(@"equalizer-preamp",audio,@12),@"bands":bands,@"twoPass":Value(@"equalizer-2pass",audio,@NO)} mutableCopy];
    NSString *presetID=Value(@"equalizer-preset",audio,@"flat");
    if(!HasFilter(audioChain,@"equalizer")) equalizer[@"presetID"]=@"none";
    else if(!_customEqualizer) {
        for(unsigned i=0;i<NB_PRESETS;i++) if([presetID isEqual:ES(eqz_preset_10b[i].psz_name)]) {
            BOOL matches=fabs([equalizer[@"preamp"] doubleValue]-eqz_preset_10b[i].f_preamp)<0.01;
            for(unsigned j=0;j<10&&matches;j++) matches=fabs([bands[j] doubleValue]-eqz_preset_10b[i].f_amp[j])<0.01;
            if(matches) equalizer[@"presetID"]=presetID; break;
        }
    }
    audioEffects[@"equalizer"]=equalizer;
    NSDictionary *audioFilterNames=@{@"compressor":@"compressor",@"spatializer":@"spatializer",@"stereoWidener":@"stereo_widen"};
    for(NSString *group in AudioMaps()) { NSMutableDictionary *d=[MappedSnapshot(AudioMaps()[group],audio) mutableCopy]; d[@"isEnabled"]=@(HasFilter(audioChain,audioFilterNames[group])); audioEffects[group]=d; }
    audioEffects[@"pitch"]=HasFilter(audioChain,@"scaletempo_pitch")?Value(@"pitch-shift",audio,@0):@0;
    NSMutableDictionary *style=[NSMutableDictionary dictionary];
    style[@"fontFamily"]=Value(@"freetype-font",video,@""); style[@"sizeMode"]=PixelSizeMode()?@"pixels":@"relative"; style[@"relativeSize"]=@0;
    style[@"pixelSize"]=config_FindConfig("macosx-redesign-sub-pixel-size")?@(config_GetInt("macosx-redesign-sub-pixel-size")):@18;
    vlc_player_Lock(_player); unsigned textScale=vlc_player_GetSubtitleTextScale(_player); vlc_player_Unlock(_player);
    for(NSNumber *relative in @[@20,@18,@12,@6]) if(textScale==1600/relative.unsignedIntValue) style[@"relativeSize"]=relative;
    if(textScale==100&&_relativeSize==16) style[@"relativeSize"]=@16;
    style[@"bold"]=Value(@"freetype-bold",video,@NO); style[@"textColor"]=Color([Value(@"freetype-color",video,@(0xFFFFFF)) integerValue]);
    style[@"textOpacity"]=@([Value(@"freetype-opacity",video,@255) doubleValue]/255.0); style[@"outline"]=Value(@"freetype-outline-thickness",video,@4);
    style[@"outlineColor"]=Color([Value(@"freetype-outline-color",video,@0) integerValue]); style[@"shadow"]=[Value(@"freetype-shadow-opacity",video,@128) integerValue]>0?@YES:@NO;
    style[@"shadowColor"]=Color([Value(@"freetype-shadow-color",video,@0) integerValue]); double distance=[Value(@"freetype-shadow-distance",video,@0.06) doubleValue]; style[@"shadowDistance"]=distance>=0.2?@"large":distance>=0.12?@"medium":@"small";
    style[@"background"]=[Value(@"freetype-background-opacity",video,@0) integerValue]>0?@YES:@NO; style[@"backgroundColor"]=Color([Value(@"freetype-background-color",video,@0) integerValue]); style[@"backgroundOpacity"]=@([Value(@"freetype-background-opacity",video,@0) doubleValue]/255.0);
    style[@"position"]=@"bottom"; style[@"offset"]=vout&&var_Type(video,"sub-margin")?@(MXRSubtitleUserMargin(vout)):Value(@"sub-margin",NULL,@0); style[@"useEmbeddedStyles"]=Value(@"subsdec-formatted",video,@YES);
    NSMutableDictionary *defaults=[NSMutableDictionary dictionary]; int audioTrack=[Value(@"audio-track",NULL,@(-1)) intValue],subTrack=[Value(@"sub-track",NULL,@(-1)) intValue];
    if(audioTrack>=0) defaults[@"audioTrack"]=@(audioTrack+1); if(subTrack>=0) defaults[@"subtitleTrack"]=@(subTrack+1);
    NSString *audioLanguage=Value(@"audio-language",NULL,@""),*subLanguage=Value(@"sub-language",NULL,@""); if(audioLanguage.length) defaults[@"audioLanguage"]=audioLanguage; if(subLanguage.length) defaults[@"subtitleLanguage"]=subLanguage;
    NSString *visual=Value(@"audio-visual",audio,@""); if([visual isEqual:@"visual"]) visual=Value(@"effect-list",audio,@"spectrum"); if(!visual.length||[visual isEqual:@"none"]) visual=@"disabled";
    double durationFactor=HasFilter(Value(@"sub-filter",video,@""),@"subsdelay")?[Value(@"subsdelay-factor",video,@1) doubleValue]:1;
    if(vout) vout_Release(vout); if(aout) aout_Release(aout);
    return @{MXRPlayerKeyVideoEffects:videoEffects,MXRPlayerKeyAudioEffects:audioEffects,MXRPlayerKeySubtitleStyle:style,MXRPlayerKeyTrackDefaults:defaults,MXRPlayerKeyAudioVisualization:visual,MXRPlayerKeySubtitleDurationFactor:@(durationFactor)};
}
- (BOOL)validateOptions:(NSDictionary *)options error:(NSError **)error {
    for(NSString *name in options) {
        module_config_t *c=config_FindConfig(name.UTF8String); if(!c) { if(error) *error=EE([NSString stringWithFormat:@"VLC option %@ is unavailable in this build.",name]); return NO; }
        id value=options[name];
        if(IsConfigStringType(c->i_type)) { if(![value isKindOfClass:NSString.class]) { if(error) *error=EE(@"Invalid string effect value."); return NO; } }
        else if(![value isKindOfClass:NSNumber.class]||!isfinite([value doubleValue])) { if(error) *error=EE(@"Invalid numeric effect value."); return NO; }
        else if(IsConfigIntegerType(c->i_type)&&c->min.i!=c->max.i&&([value longLongValue]<c->min.i||[value longLongValue]>c->max.i)) { if(error) *error=EE([NSString stringWithFormat:@"%@ is outside its supported range.",name]); return NO; }
        else if(IsConfigFloatType(c->i_type)&&c->min.f!=c->max.f&&([value doubleValue]<c->min.f||[value doubleValue]>c->max.f)) { if(error) *error=EE([NSString stringWithFormat:@"%@ is outside its supported range.",name]); return NO; }
    }
    return YES;
}
- (void)writeOptions:(NSDictionary *)options target:(vlc_object_t *)target {
    /* The preset callback replaces bands and preamp synchronously. Explicit
     * requested gains must be written afterwards, regardless of dictionary order. */
    NSMutableArray *names=[[[options allKeys] sortedArrayUsingSelector:@selector(compare:)] mutableCopy];
    if(options[@"equalizer-preset"]) { [names removeObject:@"equalizer-preset"]; [names insertObject:@"equalizer-preset" atIndex:0]; }
    for(NSString *name in names) {
        id value=options[name]; int type=config_GetType(name.UTF8String);
        if(type==VLC_VAR_STRING) config_PutPsz(name.UTF8String,[value UTF8String]);
        else if(type==VLC_VAR_FLOAT) config_PutFloat(name.UTF8String,[value floatValue]);
        else config_PutInt(name.UTF8String,[value longLongValue]);
        if(target) { var_Create(target,name.UTF8String,type|VLC_VAR_DOINHERIT);
            if(type==VLC_VAR_STRING) var_SetString(target,name.UTF8String,[value UTF8String]);
            else if(type==VLC_VAR_FLOAT) var_SetFloat(target,name.UTF8String,[value floatValue]);
            else if(type==VLC_VAR_BOOL) var_SetBool(target,name.UTF8String,[value boolValue]);
            else var_SetInteger(target,name.UTF8String,[value longLongValue]); }
    }
}
- (BOOL)validateFilters:(NSDictionary *)filters error:(NSError **)error {
    for(NSString *name in filters) if([filters[name] boolValue]&&!module_find(name.UTF8String)) { if(error) *error=EE([NSString stringWithFormat:@"The %@ filter is unavailable in this build.",name]); return NO; } return YES;
}
- (void)writeFilters:(NSDictionary *)filters option:(NSString *)option target:(vlc_object_t *)target {
    NSMutableArray *chain=[[Value(option,target,@"") componentsSeparatedByString:@":"] mutableCopy]; [chain removeObject:@""];
    for(NSString *name in filters) { for(NSString *part in [chain copy]) if([[part componentsSeparatedByString:@"{"][0] isEqual:name]) [chain removeObject:part]; if([filters[name] boolValue]) [chain addObject:name]; }
    NSString *value=[chain componentsJoinedByString:@":"]; config_PutPsz(option.UTF8String,value.UTF8String);
    if(target) var_SetString(target,option.UTF8String,value.UTF8String);
}
- (BOOL)performCommand:(MXRBridgeCommand)command arguments:(NSDictionary *)args error:(NSError **)error {
    NSMutableDictionary *options=[NSMutableDictionary dictionary],*filters=[NSMutableDictionary dictionary]; BOOL audio=NO;
    if([command isEqual:MXRBridgeCommandSetSubtitleSafeInset]) {
        /* Points the overlays cover above the bottom of the video picture, and the backing scale
         * of the video view: "sub-margin" counts output pixels. Not saved; never the user's offset. */
        double points=[args[@"points"] doubleValue],scale=[args[@"scale"] doubleValue];
        if(!isfinite(points)||!isfinite(scale)||points<0||scale<=0) { if(error) *error=EE(@"Invalid subtitle safe inset."); return NO; }
        vlc_mutex_lock(&_safeInsetLock); _safeInset=llround(MIN(points*scale,16384.0)); vlc_mutex_unlock(&_safeInsetLock);
        /* The main vout (the first, primary one), or the dummy vout a future main vout
         * inherits from: never a secondary vout (input_resource_HoldVout). */
        vout_thread_t *vout=vlc_player_vout_Hold(_player);
        [self applySubtitleSafeInsetToVout:vout order:VLC_VOUT_ORDER_PRIMARY]; vout_Release(vout);
        return YES;
    }
    if([command isEqual:MXRBridgeCommandSetTrackDefaults]) {
        options[@"audio-track"]=args[@"audioTrack"]?@([args[@"audioTrack"] intValue]-1):@(-1); options[@"sub-track"]=args[@"subtitleTrack"]?@([args[@"subtitleTrack"] intValue]-1):@(-1);
        options[@"audio-language"]=args[@"audioLanguage"]?:@""; options[@"sub-language"]=args[@"subtitleLanguage"]?:@"";
        if(![self validateOptions:options error:error]) return NO; [self writeOptions:options target:NULL]; return YES;
    }
    if([command isEqual:MXRBridgeCommandSetVideoEffects]) {
        if(![args[@"hdr"] isEqual:@"auto"]||args[@"rendererID"]) { if(error) *error=EE(@"HDR overrides are unavailable; renderer selection uses the renderer service."); return NO; }
        NSString *flip=args[@"flip"]; filters[@"transform"]=@(![flip isEqual:@"none"]); options[@"transform-type"]=[flip isEqual:@"horizontal"]?@"hflip":@"vflip";
        options[@"rotate-angle"]=args[@"rotation"]?:@0; filters[@"rotate"]=@([args[@"rotation"] doubleValue]!=0);
        NSString *zoom=args[@"zoom"]; options[@"autoscale"]=@([zoom isEqual:@"fitWindow"]); options[@"zoom"]=@{ @"quarter":@0.25,@"half":@0.5,@"original":@1,@"double":@2,@"fitWindow":@1 }[zoom]?:@1;
        options[@"aspect-ratio"]=args[@"aspectRatio"]?:@""; options[@"crop"]=args[@"crop"]?:@"";
        NSString *mode=args[@"deinterlace"]; options[@"deinterlace"]=[mode isEqual:@"automatic"]?@(-1):[mode isEqual:@"off"]?@0:@1; if(![mode isEqual:@"automatic"]&&![mode isEqual:@"off"]) options[@"deinterlace-mode"]=mode;
        NSDictionary *essential=args[@"essential"],*colors=args[@"colors"],*insets=args[@"cropInsets"];
        for(NSString *key in VideoEssentialMap()) if(essential[key]) options[VideoEssentialMap()[key]]=essential[key];
        options[@"hue"]=essential[@"hue"]?:@0;
        filters[@"adjust"]=essential[@"isEnabled"]?:@NO; filters[@"sharpen"]=@([essential[@"sharpenSigma"] doubleValue]>0); filters[@"gradfun"]=@([essential[@"bandingRemovalRadius"] intValue]>0); filters[@"grain"]=@([essential[@"filmGrainVariance"] doubleValue]>0);
        /* A disabled filter's zero is an UI sentinel, not a valid module parameter. */
        if(![filters[@"gradfun"] boolValue]) [options removeObjectForKey:@"gradfun-radius"];
        for(NSString *key in VideoColorsMap()) if(colors[key]) options[VideoColorsMap()[key]]=([key isEqual:@"extractionColor"]||[key isEqual:@"thresholdColor"])?RGB(colors[key]):colors[key];
        NSDictionary *filterNames=@{@"colorExtraction":@"extract",@"colorThreshold":@"colorthres",@"negate":@"invert",@"posterize":@"posterize",@"gradient":@"gradient",@"sepia":@"sepia"}; for(NSString *key in filterNames) filters[filterNames[key]]=colors[key]?:@NO;
        NSDictionary *insetNames=@{@"top":@"croppadd-croptop",@"bottom":@"croppadd-cropbottom",@"left":@"croppadd-cropleft",@"right":@"croppadd-cropright"}; int total=0; for(NSString *key in insetNames) { options[insetNames[key]]=insets[key]?:@0; total+=[insets[key] intValue]; } filters[@"croppadd"]=@(total>0);
    } else if([command isEqual:MXRBridgeCommandSetAudioEffects]) {
        audio=YES; NSInteger stereo=[args[@"stereoMode"] integerValue]; if(stereo<0||stereo>7) { if(error) *error=EE(@"Invalid stereo mode."); return NO; } options[@"stereo-mode"]=stereo==6?@0:@(stereo); options[@"mix-mode"]=stereo==6?@(AOUT_MIX_MODE_BINAURAL):@0;
        NSDictionary *eq=args[@"equalizer"]; NSArray *bands=eq[@"bands"]; if(bands.count!=10) { if(error) *error=EE(@"The equalizer requires ten bands."); return NO; }
        for(NSNumber *band in bands) if(![band isKindOfClass:NSNumber.class]||band.doubleValue < -20||band.doubleValue>20||!isfinite(band.doubleValue)) { if(error) *error=EE(@"Equalizer gains must be between -20 and 20 dB."); return NO; }
        filters[@"equalizer"]=eq[@"isEnabled"]?:@NO; options[@"equalizer-bands"]=[bands componentsJoinedByString:@" "]; options[@"equalizer-preamp"]=eq[@"preamp"]?:@12; options[@"equalizer-2pass"]=eq[@"twoPass"]?:@NO;
        if(eq[@"presetID"]&&![eq[@"presetID"] isEqual:@"none"]) options[@"equalizer-preset"]=eq[@"presetID"];
        NSDictionary *names=@{@"compressor":@"compressor",@"spatializer":@"spatializer",@"stereoWidener":@"stereo_widen"};
        for(NSString *group in AudioMaps()) { NSDictionary *values=args[group],*map=AudioMaps()[group]; filters[names[group]]=values[@"isEnabled"]?:@NO; for(NSString *key in map) if(values[key]) options[map[key]]=values[key]; }
        options[@"pitch-shift"]=args[@"pitch"]?:@0; filters[@"scaletempo_pitch"]=@([args[@"pitch"] doubleValue]!=0);
    } else if([command isEqual:MXRBridgeCommandSetAudioVisualization]) {
        NSString *visual=args[@"value"];
        if(![@[@"disabled",@"spectrometer",@"scope",@"spectrum"] containsObject:visual]) { if(error) *error=EE(@"VLC has no waveform visualization in this build."); return NO; }
        if(![visual isEqual:@"disabled"]&&!module_find("visual")) { if(error) *error=EE(@"The VLC visualization module is unavailable."); return NO; }
        options[@"audio-visual"]=[visual isEqual:@"disabled"]?@"":@"visual";
        if(![visual isEqual:@"disabled"]) options[@"effect-list"]=visual;
        if(![self validateOptions:options error:error]) return NO;
        [self writeOptions:options target:NULL];
        audio_output_t *aout=vlc_player_aout_Hold(_player);
        if(aout) { var_SetString(aout,"visual",[visual isEqual:@"disabled"]?"":visual.UTF8String); aout_Release(aout); }
        return YES;
    } else if([command isEqual:MXRBridgeCommandSetSubtitleDurationFactor]) {
        options[@"subsdelay-factor"]=args[@"value"]; filters[@"subsdelay"]=@([args[@"value"] doubleValue]!=1);
    } else if([command isEqual:MXRBridgeCommandSetSubtitleStyle]) {
        if([args[@"position"] isEqual:@"top"]) { if(error) *error=EE(@"VLC places subtitles at the bottom; use Subtitle Offset to raise them."); return NO; }
        if([args[@"sizeMode"] isEqual:@"pixels"]&&([args[@"pixelSize"] integerValue]<6||[args[@"pixelSize"] integerValue]>200)) { if(error) *error=EE(@"Subtitle size must be between 6 and 200 px."); return NO; }
        /* MISS-03: freetype refreshes only colour, background and outline thickness in
         * Render(); its other style values are read when the renderer is created for the
         * next input (vout_subpictures.c spu_Attach). Save them instead of failing, and
         * report that they show from the next video. */
        _lastStyleChangeAppliesFromNextVideo=NO;
        vout_thread_t *active=vlc_player_vout_Hold(_player);
        if(active) {
            NSDictionary *current=[self snapshot][@"subtitleStyle"];
            NSArray *restartKeys=@[@"fontFamily",@"bold",@"textOpacity",@"outlineColor",@"shadow",@"shadowColor",@"shadowDistance"];
            for(NSString *key in restartKeys) if(args[key]&&![args[key] isEqual:current[key]]) { _lastStyleChangeAppliesFromNextVideo=YES; break; }
            vout_Release(active);
        }
        if(config_FindConfig("macosx-redesign-sub-size-mode")) options[@"macosx-redesign-sub-size-mode"]=[args[@"sizeMode"] isEqual:@"pixels"]?@"pixels":@"relative";
        if(config_FindConfig("macosx-redesign-sub-pixel-size")&&args[@"pixelSize"]) options[@"macosx-redesign-sub-pixel-size"]=args[@"pixelSize"];
        options[@"freetype-font"]=args[@"fontFamily"]?:@""; options[@"freetype-bold"]=args[@"bold"]?:@NO;
        options[@"freetype-color"]=RGB(args[@"textColor"]); options[@"freetype-opacity"]=@((int)([args[@"textOpacity"] doubleValue]*255)); options[@"freetype-outline-thickness"]=args[@"outline"]?:@4; options[@"freetype-outline-color"]=RGB(args[@"outlineColor"]);
        options[@"freetype-shadow-opacity"]=[args[@"shadow"] boolValue]?@128:@0; options[@"freetype-shadow-color"]=RGB(args[@"shadowColor"]);
        options[@"freetype-shadow-distance"]=@{@"small":@0.06,@"medium":@0.12,@"large":@0.2}[args[@"shadowDistance"]]?:@0.06;
        options[@"freetype-background-opacity"]=[args[@"background"] boolValue]?@((int)([args[@"backgroundOpacity"] doubleValue]*255)):@0; options[@"freetype-background-color"]=RGB(args[@"backgroundColor"]); options[@"sub-margin"]=args[@"offset"]?:@0; options[@"subsdec-formatted"]=args[@"useEmbeddedStyles"]?:@YES;
    } else { if(error) *error=EE(@"This effect command is unavailable."); return NO; }
    if(![self validateOptions:options error:error]||![self validateFilters:filters error:error]) return NO;
    if([command isEqual:MXRBridgeCommandSetAudioEffects]) _customEqualizer=[args[@"equalizer"][@"isEnabled"] boolValue]&&args[@"equalizer"][@"presetID"]==nil;
    if(audio) {
        audio_output_t *aout=vlc_player_aout_Hold(_player); [self writeOptions:options target:aout?VLC_OBJECT(aout):NULL];
        [self writeFilters:filters option:@"audio-filter" target:aout?VLC_OBJECT(aout):NULL]; if(aout) aout_Release(aout);
    } else {
        [self writeOptions:options target:NULL]; size_t count; vout_thread_t **vouts=vlc_player_vout_HoldAll(_player,&count);
        NSString *chainOption=[command isEqual:MXRBridgeCommandSetSubtitleDurationFactor]?@"sub-filter":@"video-filter";
        if(filters.count) [self writeFilters:filters option:chainOption target:NULL];
        /* The vouts get the user's offset plus the safe inset they carry, not the offset alone. */
        NSNumber *userMargin=options[@"sub-margin"]; NSMutableDictionary *voutOptions=[options mutableCopy]; [voutOptions removeObjectForKey:@"sub-margin"];
        for(size_t i=0;i<count;i++) { [self writeOptions:voutOptions target:VLC_OBJECT(vouts[i])]; if(userMargin) [self setUserSubtitleMargin:userMargin.longLongValue onVout:vouts[i]]; if(filters.count) [self writeFilters:filters option:chainOption target:VLC_OBJECT(vouts[i])]; vout_Release(vouts[i]); } free(vouts);
        if([command isEqual:MXRBridgeCommandSetSubtitleStyle]) {
            if([args[@"sizeMode"] isEqual:@"pixels"]) [self applySubtitleSizePreference];
            else { int size=[args[@"relativeSize"] intValue]; _relativeSize=size; _pixelScaleApplied=NO; vlc_player_Lock(_player); vlc_player_SetSubtitleTextScale(_player,size?MAX(10,MIN(500,1600/size)):100); vlc_player_Unlock(_player); }
        }
    }
    return YES;
}
@end
