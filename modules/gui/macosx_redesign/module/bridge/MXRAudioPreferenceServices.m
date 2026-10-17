/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#import "MXRAudioPreferenceServices.h"
#include <vlc_configuration.h>
#include <vlc_plugin.h> /* CONFIG_CLASS, CONFIG_ITEM_* */
#include <vlc_charset.h>
#include <vlc_modules.h>
#include <vlc_aout.h>
#include "../../../../../src/audio_output/aout_internal.h"
#include "../../../../../src/config/configuration.h"
#include "../../../../audio_filter/equalizer_presets.h"

static NSString *const Prefix = @"macosx-redesign-";
static NSDictionary<NSString *, NSString *> *FilterNames(void)
{
    return @{@"normvol":@"normvol", @"equalizer":@"equalizer", @"compressor":@"compressor",
             @"stereo-widen":@"stereo_widen", @"chorus":@"chorus_flanger", @"karaoke":@"karaoke"};
}
static NSDictionary<NSString *, NSNumber *> *NightPreset(void)
{
    /* Reduce peaks and lift quieter material without a separate fake DSP mode. */
    return @{@"compressor-rms-peak":@0.2, @"compressor-attack":@5.0,
             @"compressor-release":@200.0, @"compressor-threshold":@(-20.0),
             @"compressor-ratio":@8.0, @"compressor-knee":@6.0,
             @"compressor-makeup-gain":@6.0};
}
static NSString *ReadChain(audio_output_t *aout)
{
    char *value = aout ? var_GetString(aout,"audio-filter") : config_GetPsz("audio-filter");
    NSString *result = value ? ([NSString stringWithUTF8String:value] ?: @"") : @"";
    free(value); return result;
}
static NSArray<NSString *> *ChainParts(NSString *chain)
{
    /* These are the exact separators used by aout_FiltersNewWithClock. */
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *part in [chain componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" :"]])
        if (part.length) [result addObject:part];
    return result;
}
static BOOL HasFilter(NSString *chain, NSString *name)
{
    for (NSString *part in ChainParts(chain)) if ([part isEqual:name]) return YES;
    return NO;
}
static BOOL HasModule(NSString *filter)
{
    /* Resolve the registered object, not a filename inferred from its dylib. */
    module_t *module = module_find(filter.UTF8String);
    if (!module && [filter isEqual:@"headphone"]) module = module_find("headphone_channel_mixer");
    return module != NULL && module_provides(module,"audio filter");
}
static float ReadFloat(audio_output_t *aout, NSString *name)
{
    return aout && var_Type(aout,name.UTF8String) == VLC_VAR_FLOAT
        ? var_GetFloat(aout,name.UTF8String) : config_GetFloat(name.UTF8String);
}
static BOOL IsNightPreset(audio_output_t *aout)
{
    for (NSString *name in NightPreset())
        if (fabsf(ReadFloat(aout,name)-[NightPreset()[name] floatValue]) > 0.001f) return NO;
    return YES;
}
static void WriteConfiguredFloats(NSDictionary<NSString *, NSNumber *> *values)
{
    for (NSString *name in values) config_PutFloat(name.UTF8String,values[name].floatValue);
}
static void WriteLiveFloats(NSDictionary<NSString *, NSNumber *> *values, audio_output_t *aout)
{
    if (!aout) return;
    for (NSString *name in values) {
        float value = values[name].floatValue;
        /* Existing filter callbacks subscribe to these variables. */
        if (!var_Type(aout,name.UTF8String)) var_Create(aout,name.UTF8String,VLC_VAR_FLOAT|VLC_VAR_DOINHERIT);
        var_SetFloat(aout,name.UTF8String,value);
    }
}
static void WriteFloats(NSDictionary<NSString *, NSNumber *> *values, audio_output_t *aout)
{
    WriteConfiguredFloats(values); WriteLiveFloats(values,aout);
}
static NSString *ChangeChain(NSString *chain, NSDictionary<NSString *, NSNumber *> *changes)
{
    NSMutableArray<NSString *> *parts = [ChainParts(chain) mutableCopy];
    for (NSString *name in [[changes allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        [parts removeObject:name];
        if (changes[name].boolValue) {
            /* Like aout_EnableFilter, place equalization before the other effects. */
            if ([name isEqual:@"equalizer"]) [parts insertObject:name atIndex:0];
            else [parts addObject:name];
        }
    }
    return [parts componentsJoinedByString:@":"];
}
static void WriteSeparateFilters(NSDictionary<NSString *, NSNumber *> *configuredChanges,
                                 NSDictionary<NSString *, NSNumber *> *liveChanges, audio_output_t *aout)
{
    /* All-settings can set a next-media chain while the live output retains its
     * own filters. Apply the requested change to each chain independently. */
    NSString *configured = ChangeChain(ReadChain(NULL),configuredChanges);
    config_PutPsz("audio-filter",configured.UTF8String);
    if (aout) {
        NSString *live = ChangeChain(ReadChain(aout),liveChanges);
        var_SetString(aout,"audio-filter",live.UTF8String);
    }
}
static void WriteFilters(NSDictionary<NSString *, NSNumber *> *changes, audio_output_t *aout)
{
    WriteSeparateFilters(changes,changes,aout);
}
static NSString *ReadString(audio_output_t *aout,const char *name)
{
    char *value = aout ? var_GetString(aout,name) : config_GetPsz(name);
    NSString *result = value ? ([NSString stringWithUTF8String:value] ?: @"") : @"";
    free(value); return result;
}
static BOOL EnsureEqualizer(audio_output_t *aout)
{
    NSString *bands = ReadString(aout,"equalizer-bands"), *preset = ReadString(aout,"equalizer-preset");
    if (bands.length) return YES;
    bands = ReadString(NULL,"equalizer-bands");
    /* Equalizer Open validates the initially read bands string. Supply real gains
     * before enabling, including when a named preset is configured without bands. */
    if (bands.length) {
        if (aout) {
            var_SetString(aout,"equalizer-bands",bands.UTF8String);
            WriteFloats(@{@"equalizer-preamp":@(config_GetFloat("equalizer-preamp"))},aout);
        }
    } else {
        if (!preset.length) preset = ReadString(NULL,"equalizer-preset");
        if (!preset.length) preset = @"flat";
        const eqz_preset_t *selected = NULL;
        for (unsigned index = 0; index < NB_PRESETS; ++index)
            if (!strcasecmp(eqz_preset_10b[index].psz_name,preset.UTF8String)) { selected = &eqz_preset_10b[index]; break; }
        if (!selected) return NO;
        NSMutableArray *values = [NSMutableArray arrayWithCapacity:10];
        for (unsigned index = 0; index < 10; ++index) [values addObject:[NSString stringWithFormat:@"%.7g",selected->f_amp[index]]];
        bands = [values componentsJoinedByString:@" "];
        config_PutPsz("equalizer-preset",preset.UTF8String);
        config_PutPsz("equalizer-bands",bands.UTF8String);
        if (aout) { var_SetString(aout,"equalizer-preset",preset.UTF8String); var_SetString(aout,"equalizer-bands",bands.UTF8String); }
    }
    return YES;
}
static BOOL Fail(NSError **error, NSInteger code, NSString *message)
{
    if (error) *error = [NSError errorWithDomain:@"MXRVLCBridge" code:code userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}

@implementation MXRAudioPreferenceServices {
    vlc_player_t *_player;
    NSString *_spatialMode;
    NSDictionary<NSString *, NSNumber *> *_beforeNight;
    NSDictionary<NSString *, NSNumber *> *_configuredBeforeNight;
    BOOL _compressorBeforeNight;
    BOOL _configuredCompressorBeforeNight;
    BOOL _nightRequested;
    BOOL _stopped;
}
+ (BOOL)handlesOption:(NSString *)option
{
    if (![option hasPrefix:Prefix]) return NO;
    NSString *name = [option substringFromIndex:Prefix.length];
    return FilterNames()[name] != nil || [@[@"night-mode",@"spatial-audio",@"spatial-mode"] containsObject:name];
}
- (instancetype)initWithPlayer:(vlc_player_t *)player
{
    NSAssert(NSThread.isMainThread,@"Audio preferences belong to the main thread");
    if (!(self = [super init])) return nil;
    _player = player;
    char *mode = config_GetType("macosx-redesign-spatial-mode") == VLC_VAR_STRING
        ? config_GetPsz("macosx-redesign-spatial-mode") : NULL;
    _spatialMode = mode ? ([NSString stringWithUTF8String:mode] ?: @"headphones") : @"headphones";
    free(mode);
    if (![@[@"headphones",@"spatializer"] containsObject:_spatialMode]) _spatialMode = @"headphones";
    /* Persisted app opt-ins are additive. Do not remove existing VLC filters merely
     * because a newly introduced app preference still has its false default. */
    for (NSString *name in @[@"normvol",@"equalizer",@"compressor",@"stereo-widen",@"chorus",@"karaoke",@"spatial-audio",@"night-mode"]) {
        NSString *option = [Prefix stringByAppendingString:name];
        if (config_GetType(option.UTF8String) == VLC_VAR_BOOL && config_GetInt(option.UTF8String))
            [self applyOption:option value:@YES error:NULL];
    }
    return self;
}
- (BOOL)availabilityForOption:(NSString *)option
{
    if (_stopped || ![self.class handlesOption:option] || config_GetType("audio-filter") != VLC_VAR_STRING) return NO;
    /* Bit-exact output intentionally bypasses user filters in VLC. */
    if (config_GetType("audio-bitexact") == VLC_VAR_BOOL && config_GetInt("audio-bitexact")) return NO;
    /* VLC stores this immutable choice in the output owner at creation. A later
     * config change does not make the existing bit-exact output run filters. */
    audio_output_t *aout = vlc_player_aout_Hold(_player);
    BOOL bitexact = aout && aout_owner(aout)->bitexact;
    if (aout) aout_Release(aout);
    if (bitexact) return NO;
    NSString *name = [option substringFromIndex:Prefix.length];
    NSString *filter = FilterNames()[name];
    if (filter) {
        if (!HasModule(filter)) return NO;
        if ([name isEqual:@"normvol"]) return config_GetType("norm-max-level") == VLC_VAR_FLOAT;
        if ([name isEqual:@"equalizer"]) return config_GetType("equalizer-bands") == VLC_VAR_STRING;
        return YES;
    }
    if ([name isEqual:@"night-mode"]) {
        if (!HasModule(@"compressor")) return NO;
        for (NSString *parameter in NightPreset()) if (config_GetType(parameter.UTF8String) != VLC_VAR_FLOAT) return NO;
        return YES;
    }
    if ([name isEqual:@"spatial-mode"]) return HasModule(@"headphone") && HasModule(@"spatializer");
    return HasModule([_spatialMode isEqual:@"headphones"] ? @"headphone" : @"spatializer");
}
- (NSDictionary<NSString *, id> *)snapshotValues
{
    NSAssert(NSThread.isMainThread,@"Audio preferences belong to the main thread");
    if (_stopped) return @{};
    audio_output_t *aout = vlc_player_aout_Hold(_player);
    NSString *chain = aout && aout_owner(aout)->bitexact ? @"" : ReadChain(aout);
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *name in FilterNames())
        result[[Prefix stringByAppendingString:name]] = HasModule(FilterNames()[name]) && HasFilter(chain,FilterNames()[name]) ? @YES : @NO;
    BOOL headphones = HasModule(@"headphone") && HasFilter(chain,@"headphone"), spatializer = HasModule(@"spatializer") && HasFilter(chain,@"spatializer");
    result[@"macosx-redesign-spatial-audio"] = headphones || spatializer ? @YES : @NO;
    result[@"macosx-redesign-spatial-mode"] = headphones ? @"headphones" : spatializer ? @"spatializer" : _spatialMode;
    result[@"macosx-redesign-night-mode"] = _nightRequested && HasFilter(chain,@"compressor") && IsNightPreset(aout) ? @YES : @NO;
    if (aout) aout_Release(aout);
    return result;
}
- (BOOL)applyOption:(NSString *)option value:(id)value error:(NSError **)error
{
    NSAssert(NSThread.isMainThread,@"Audio preferences belong to the main thread");
    if (_stopped) return Fail(error,ECANCELED,@"The audio preferences service has stopped.");
    if (![self.class handlesOption:option]) return Fail(error,ENOTSUP,@"This audio preference is unsupported.");
    NSString *name = [option substringFromIndex:Prefix.length];
    if ([name isEqual:@"spatial-mode"]) {
        if (![value isKindOfClass:NSString.class] || ![@[@"headphones",@"spatializer"] containsObject:value])
            return Fail(error,EINVAL,@"Choose headphone virtualization or room spatializer.");
        if (!HasModule([value isEqual:@"headphones"] ? @"headphone" : @"spatializer"))
            return Fail(error,ENOTSUP,@"The selected spatial audio filter is unavailable in this VLC build.");
    } else if (![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue]) || ([value doubleValue] != 0 && [value doubleValue] != 1))
        return Fail(error,EINVAL,@"An audio effect switch requires a Boolean value.");
    if (![self availabilityForOption:option]) return Fail(error,ENOTSUP,@"The real audio filter or its settings are unavailable in this VLC build.");
    audio_output_t *aout = vlc_player_aout_Hold(_player);
    NSString *chain = ReadChain(aout);
    NSMutableDictionary *changes = [NSMutableDictionary dictionary];
    NSDictionary *configuredChanges = nil;
    if ([name isEqual:@"spatial-mode"] || [name isEqual:@"spatial-audio"]) {
        BOOL enabled = [name isEqual:@"spatial-audio"] ? [value boolValue] : HasFilter(chain,@"headphone") || HasFilter(chain,@"spatializer");
        if ([name isEqual:@"spatial-mode"]) _spatialMode = [value copy];
        else if (HasFilter(chain,@"headphone")) _spatialMode = @"headphones";
        else if (HasFilter(chain,@"spatializer")) _spatialMode = @"spatializer";
        changes[@"headphone"] = enabled && [_spatialMode isEqual:@"headphones"] ? @YES : @NO;
        changes[@"spatializer"] = enabled && [_spatialMode isEqual:@"spatializer"] ? @YES : @NO;
    } else if ([name isEqual:@"night-mode"]) {
        if ([value boolValue]) {
            if (!_nightRequested) {
                NSMutableDictionary *previous = [NSMutableDictionary dictionary], *configuredPrevious = [NSMutableDictionary dictionary];
                for (NSString *parameter in NightPreset()) {
                    previous[parameter] = @(ReadFloat(aout,parameter));
                    configuredPrevious[parameter] = @(ReadFloat(NULL,parameter));
                }
                BOOL persistedNight = config_GetType("macosx-redesign-night-mode") == VLC_VAR_BOOL && config_GetInt("macosx-redesign-night-mode") && IsNightPreset(aout);
                _beforeNight = persistedNight ? nil : previous;
                _configuredBeforeNight = persistedNight ? nil : configuredPrevious;
                _compressorBeforeNight = persistedNight && config_GetType("macosx-redesign-compressor") == VLC_VAR_BOOL
                    ? config_GetInt("macosx-redesign-compressor") != 0 : HasFilter(chain,@"compressor");
                _configuredCompressorBeforeNight = persistedNight && config_GetType("macosx-redesign-compressor") == VLC_VAR_BOOL
                    ? config_GetInt("macosx-redesign-compressor") != 0 : HasFilter(ReadChain(NULL),@"compressor");
            }
            WriteFloats(NightPreset(),aout); changes[@"compressor"] = @YES; _nightRequested = YES;
        } else {
            /* Keep manual compressor edits made through Effects while night mode
             * was on. Restore the previous values only if the preset is unchanged. */
            [self restoreNightParameters:aout];
            if (_nightRequested) {
                changes[@"compressor"] = _compressorBeforeNight ? @YES : @NO;
                configuredChanges = @{@"compressor":_configuredCompressorBeforeNight ? @YES : @NO};
            }
            _beforeNight = nil; _configuredBeforeNight = nil; _nightRequested = NO;
        }
    } else {
        changes[FilterNames()[name]] = [value boolValue] ? @YES : @NO;
        if ([name isEqual:@"equalizer"] && [value boolValue] && !EnsureEqualizer(aout)) {
            if (aout) aout_Release(aout);
            return Fail(error,EINVAL,@"The configured equalizer preset is unknown.");
        }
        if ([name isEqual:@"compressor"]) {
            _compressorBeforeNight = [value boolValue];
            _configuredCompressorBeforeNight = [value boolValue];
            if (![value boolValue]) {
                [self restoreNightParameters:aout];
                _beforeNight = nil; _configuredBeforeNight = nil; _nightRequested = NO;
                if (config_GetType("macosx-redesign-night-mode") == VLC_VAR_BOOL) config_PutInt("macosx-redesign-night-mode",0);
            }
        }
    }
    if (configuredChanges) WriteSeparateFilters(configuredChanges,changes,aout);
    else WriteFilters(changes,aout);
    if (aout) aout_Release(aout);
    return YES;
}
- (void)restoreNightParameters:(audio_output_t *)aout
{
    /* Manual next-media config edits and live Effects edits are independent. */
    BOOL restoreLive = aout && _beforeNight && IsNightPreset(aout);
    if (_configuredBeforeNight && IsNightPreset(NULL)) WriteConfiguredFloats(_configuredBeforeNight);
    if (restoreLive) WriteLiveFloats(_beforeNight,aout);
}
- (void)reconcileAfterEffectsChange
{
    NSAssert(NSThread.isMainThread,@"Audio preferences belong to the main thread");
    if (_stopped) return;
    NSDictionary *values = [self snapshotValues];
    if (![values[@"macosx-redesign-night-mode"] boolValue]) { _nightRequested = NO; _beforeNight = nil; _configuredBeforeNight = nil; }
    for (NSString *option in values) {
        id value = values[option];
        if ([option isEqual:@"macosx-redesign-compressor"] && _nightRequested)
            value = _compressorBeforeNight ? @YES : @NO;
        int type = config_GetType(option.UTF8String);
        if (type == VLC_VAR_BOOL) config_PutInt(option.UTF8String,[value boolValue]);
        else if (type == VLC_VAR_STRING) config_PutPsz(option.UTF8String,[value UTF8String]);
    }
    _spatialMode = values[@"macosx-redesign-spatial-mode"];
}
- (void)resetAfterConfigurationReset
{
    NSAssert(NSThread.isMainThread,@"Audio preferences belong to the main thread");
    if (_stopped) return;
    _nightRequested = NO; _beforeNight = nil; _configuredBeforeNight = nil;
    _compressorBeforeNight = NO; _configuredCompressorBeforeNight = NO;
    _spatialMode = config_GetType("macosx-redesign-spatial-mode") == VLC_VAR_STRING
        ? ReadString(NULL,"macosx-redesign-spatial-mode") : @"headphones";
    audio_output_t *aout = vlc_player_aout_Hold(_player);
    if (!aout) return;
    /* Reset existing cached variables using actual module metadata and the newly
     * reset engine values. Never restore the previous session's Night preset. */
    for (NSString *object in @[@"normvol",@"equalizer",@"compressor",@"stereo_widen",@"chorus_flanger",@"karaoke",@"headphone",@"headphone_channel_mixer",@"spatializer"]) {
        module_t *module = module_find(object.UTF8String);
        if (!module || !module_provides(module,"audio filter")) continue;
        unsigned count = 0; module_config_t *options = module_config_get(module,&count);
        for (unsigned index = 0; index < count; ++index) {
            const char *name = options[index].psz_name;
            if (!name || !var_Type(aout,name)) continue;
            int type = config_GetType(name);
            if (type == VLC_VAR_FLOAT) var_SetFloat(aout,name,config_GetFloat(name));
            else if (type == VLC_VAR_BOOL) var_SetBool(aout,name,config_GetInt(name) != 0);
            else if (type == VLC_VAR_INTEGER) var_SetInteger(aout,name,config_GetInt(name));
            else if (type == VLC_VAR_STRING) { char *value = config_GetPsz(name); var_SetString(aout,name,value ?: ""); free(value); }
        }
        module_config_free(options);
    }
    NSString *chain = ReadChain(NULL);
    var_SetString(aout,"audio-filter",chain.UTF8String);
    aout_Release(aout);
}
- (void)shutdown
{
    NSAssert(NSThread.isMainThread,@"Audio preferences belong to the main thread");
    _stopped = YES; _player = NULL; _beforeNight = nil; _configuredBeforeNight = nil;
}
@end

#pragma mark - Additional command line options

NSArray<NSString *> *MXRSplitCommandLineOptions(NSString *text)
{
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    NSMutableString *word = nil;
    unichar quote = 0;
    BOOL escaped = NO;
    for (NSUInteger index = 0; index < text.length; ++index) {
        unichar c = [text characterAtIndex:index];
        if (escaped) { [word appendFormat:@"%C", c]; escaped = NO; continue; }
        if (c == '\\' && quote != '\'') { if (!word) word = [NSMutableString string]; escaped = YES; continue; }
        if (quote) {
            if (c == quote) quote = 0; else [word appendFormat:@"%C", c];
            continue;
        }
        if (c == '"' || c == '\'') { if (!word) word = [NSMutableString string]; quote = c; continue; }
        if ([NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:c]) {
            if (word) { [words addObject:word]; word = nil; }
            continue;
        }
        if (!word) word = [NSMutableString string];
        [word appendFormat:@"%C", c];
    }
    if (word) [words addObject:word];
    return words;
}

NSUInteger MXRApplyCommandLineOptions(vlc_object_t *object, NSString *text)
{
    NSArray<NSString *> *words = MXRSplitCommandLineOptions(text ?: @"");
    NSUInteger applied = 0;
    for (NSUInteger index = 0; index < words.count; ++index) {
        NSString *word = words[index];
        if (![word hasPrefix:@"--"] || word.length < 3) {
            msg_Warn(object, "additional option \"%s\" is not an --option; skipped", word.UTF8String);
            continue;
        }
        NSString *name = [word substringFromIndex:2];
        NSString *value = nil;
        NSRange equals = [name rangeOfString:@"="];
        if (equals.location != NSNotFound) {
            value = [name substringFromIndex:NSMaxRange(equals)];
            name = [name substringToIndex:equals.location];
        }
        module_config_t *item = config_FindConfig(name.UTF8String);
        BOOL negated = NO;
        if (item == NULL && [name hasPrefix:@"no"]) {
            NSString *positive = [name substringFromIndex:[name hasPrefix:@"no-"] ? 3 : 2];
            module_config_t *flag = config_FindConfig(positive.UTF8String);
            if (flag != NULL && CONFIG_CLASS(flag->i_type) == CONFIG_ITEM_BOOL && value == nil) {
                item = flag; name = positive; negated = YES;
            }
        }
        /* Obsolete options (add_obsolete_*) are still registered, flagged as ignored. */
        if (item == NULL || container_of(item, struct vlc_param, item)->obsolete) {
            msg_Warn(object, "additional option --%s does not exist in this VLC; skipped", name.UTF8String);
            continue;
        }
        int type = CONFIG_CLASS(item->i_type);
        if (type != CONFIG_ITEM_BOOL && value == nil) {
            if (index + 1 >= words.count) {
                msg_Warn(object, "additional option --%s needs a value; skipped", name.UTF8String);
                continue;
            }
            value = words[++index];
        }
        const char *psz_name = name.UTF8String;
        switch (type) {
            case CONFIG_ITEM_STRING:
                var_Create(object, psz_name, VLC_VAR_STRING);
                var_SetString(object, psz_name, value.UTF8String);
                break;
            case CONFIG_ITEM_INTEGER:
                var_Create(object, psz_name, VLC_VAR_INTEGER);
                var_Change(object, psz_name, VLC_VAR_SETMINMAX,
                           (vlc_value_t){ .i_int = item->min.i }, (vlc_value_t){ .i_int = item->max.i });
                var_SetInteger(object, psz_name, strtoll(value.UTF8String, NULL, 0));
                break;
            case CONFIG_ITEM_FLOAT:
                var_Create(object, psz_name, VLC_VAR_FLOAT);
                var_Change(object, psz_name, VLC_VAR_SETMINMAX,
                           (vlc_value_t){ .f_float = item->min.f }, (vlc_value_t){ .f_float = item->max.f });
                var_SetFloat(object, psz_name, vlc_atof_c(value.UTF8String));
                break;
            case CONFIG_ITEM_BOOL: {
                BOOL on = !negated;
                if (value != nil)
                    on = !([value isEqualToString:@"0"] || [value caseInsensitiveCompare:@"false"] == NSOrderedSame
                           || [value caseInsensitiveCompare:@"no"] == NSOrderedSame);
                var_Create(object, psz_name, VLC_VAR_BOOL);
                var_SetBool(object, psz_name, on);
                break;
            }
            default:
                continue;
        }
        msg_Dbg(object, "additional option --%s applied", psz_name);
        ++applied;
    }
    return applied;
}

void MXRApplyStartupCommandLineOptions(vlc_object_t *intf)
{
    char *saved = config_GetPsz("macosx-redesign-extra-args");
    if (saved != NULL && saved[0] != '\0') {
        NSString *text = [NSString stringWithUTF8String:saved];
        if (text != nil) MXRApplyCommandLineOptions(VLC_OBJECT(vlc_object_instance(intf)), text);
    }
    free(saved);
}
