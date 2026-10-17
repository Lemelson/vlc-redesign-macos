#import <Foundation/Foundation.h>
#include <vlc_common.h>
#include <vlc_player.h>

NS_ASSUME_NONNULL_BEGIN

/* Main-thread preference adapter. The player outlives this helper. */
@interface MXRAudioPreferenceServices : NSObject
- (instancetype)initWithPlayer:(vlc_player_t *)player;
+ (BOOL)handlesOption:(NSString *)option;
- (BOOL)availabilityForOption:(NSString *)option;
- (NSDictionary<NSString *, id> *)snapshotValues;
/// Call after a successful Effects setAudioEffects command to reconcile app opt-ins.
- (void)reconcileAfterEffectsChange;
/// Call after config_ResetAll; discard Night restore data before applying defaults.
- (void)resetAfterConfigurationReset;
- (BOOL)applyOption:(NSString *)option value:(id)value error:(NSError * _Nullable * _Nullable)error;
- (void)shutdown;
@end

/* Settings ▸ General ▸ Additional command line options (Figma 3046:9524).
 * Splits the text like a shell does (spaces separate words; '…', "…" and \ quote). */
NSArray<NSString *> *MXRSplitCommandLineOptions(NSString *text);
/* Applies `--name=value`, `--name value`, `--name` and `--no-name` to `object` the way
 * src/config/cmdline.c applies VLC's own command line: as variables that every object created
 * afterwards inherits, without writing vlcrc. Unknown and obsolete options are skipped with a
 * warning. Returns the number of options applied. */
NSUInteger MXRApplyCommandLineOptions(vlc_object_t *object, NSString *text);
/* Reads the saved `macosx-redesign-extra-args` and applies it to the VLC instance; called once
 * when the interface opens, before anything plays. */
void MXRApplyStartupCommandLineOptions(vlc_object_t *intf);

NS_ASSUME_NONNULL_END
