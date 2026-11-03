/*****************************************************************************
 * MXRUpdateDeferralTests.m: a background update check skipped during video runs later
 *****************************************************************************
 * Copyright (C) 2026 VLC Redesign contributors
 * Licensed under the GNU General Public License, version 2 or later.
 *****************************************************************************/

/*
 * Run by tools/test-updater-deferral.py, without the engine. The policy cases always run; with
 * -DMXR_WITH_SPARKLE the same policy drives a real SPUUpdater (Sparkle 2.8.1 from the contribs)
 * against a local feed: `MXRUpdateDeferralTests <host.bundle> <feed base URL>`.
 */

#import <Foundation/Foundation.h>
#include "MXRUpdateDeferral.h"

static int failures;
#define CHECK(condition, ...) do { if (!(condition)) { failures++; fprintf(stderr, "FAIL %s:%d: ", __FILE__, __LINE__); \
    fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } } while (0)

static void testBackgroundCheckDuringVideoIsDeferredNotDropped(void)
{
    MXRUpdateDeferral deferral = {0};
    CHECK(!MXRUpdateDeferralMayCheck(&deferral, true, true), "a background check must not run while a video plays");
    CHECK(deferral.pending, "the skipped check is remembered");
    CHECK(!MXRUpdateDeferralTakeWhenIdle(&deferral, true, true), "never during playback");
    CHECK(deferral.pending, "still remembered while the video plays on");
    CHECK(MXRUpdateDeferralTakeWhenIdle(&deferral, false, true), "runs once playback stopped");
    CHECK(!MXRUpdateDeferralTakeWhenIdle(&deferral, false, true), "at most once");
    CHECK(MXRUpdateDeferralMayCheck(&deferral, true, false), "the deferred check itself is allowed when idle");
    CHECK(!deferral.pending, "and leaves nothing remembered");
}

static void testDeferredCheckRefusedAgainIfAVideoStartedMeanwhile(void)
{
    MXRUpdateDeferral deferral = {0};
    MXRUpdateDeferralMayCheck(&deferral, true, true);
    CHECK(MXRUpdateDeferralTakeWhenIdle(&deferral, false, true), "stopped: run it");
    CHECK(!MXRUpdateDeferralMayCheck(&deferral, true, true), "a video started before Sparkle asked: refused");
    CHECK(deferral.pending, "remembered again for the next stop");
}

static void testAnyCheckThatRunsClearsTheDeferredOne(void)
{
    MXRUpdateDeferral deferral = {0};
    MXRUpdateDeferralMayCheck(&deferral, true, true);
    CHECK(MXRUpdateDeferralMayCheck(&deferral, false, true), "a check the user asked for always runs");
    CHECK(!MXRUpdateDeferralTakeWhenIdle(&deferral, false, true), "it replaces the deferred one");
    MXRUpdateDeferralMayCheck(&deferral, true, true);
    CHECK(MXRUpdateDeferralMayCheck(&deferral, true, false), "Sparkle's next scheduled check ran first");
    CHECK(!MXRUpdateDeferralTakeWhenIdle(&deferral, false, true), "nothing left to run");
}

static void testDeferredCheckDroppedWhenAutomaticChecksWereTurnedOff(void)
{
    MXRUpdateDeferral deferral = {0};
    MXRUpdateDeferralMayCheck(&deferral, true, true);
    CHECK(!MXRUpdateDeferralTakeWhenIdle(&deferral, false, false), "the user turned automatic checks off");
    CHECK(!deferral.pending, "dropped, not kept for later");
}

static void testNothingRunsWhenNoCheckWasSkipped(void)
{
    MXRUpdateDeferral deferral = {0};
    CHECK(!MXRUpdateDeferralTakeWhenIdle(&deferral, false, true), "a stop alone never starts a check");
    CHECK(MXRUpdateDeferralMayCheck(&deferral, true, false), "a background check while idle runs");
    CHECK(MXRUpdateDeferralMayCheck(&deferral, false, false), "a manual check while idle runs");
}

#ifdef MXR_WITH_SPARKLE
#import <Sparkle/Sparkle.h>

/// The bridge's decisions (MXRUpdaterBridge.m) with the player replaced by a flag; shows no window.
@interface MXRDeferralProbe : NSObject <SPUUserDriver, SPUUpdaterDelegate>
@property (nonatomic) BOOL playingVideo;
@property (nonatomic) NSUInteger refused, finished;
@end

@implementation MXRDeferralProbe
{
@public
    MXRUpdateDeferral _deferral;
}
- (BOOL)updater:(SPUUpdater *)updater mayPerformUpdateCheck:(SPUUpdateCheck)updateCheck error:(NSError * __autoreleasing *)error
{
    if (MXRUpdateDeferralMayCheck(&_deferral, updateCheck == SPUUpdateCheckUpdatesInBackground, self.playingVideo))
        return YES;
    self.refused++;
    if (error != NULL)
        *error = [NSError errorWithDomain:@"io.github.lemelson.vlc-redesign.updates" code:1
                                 userInfo:@{NSLocalizedDescriptionKey: @"A video is playing."}];
    return NO;
}
- (void)updater:(SPUUpdater *)updater didFinishUpdateCycleForUpdateCheck:(SPUUpdateCheck)updateCheck error:(NSError *)error { self.finished++; }
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply
{ reply([[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:YES sendSystemProfile:NO]); }
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancellation {}
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply { reply(SPUUserUpdateChoiceDismiss); }
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)downloadData {}
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error {}
- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement { acknowledgement(); }
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement { acknowledgement(); }
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancellation {}
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)expectedContentLength {}
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length {}
- (void)showDownloadDidStartExtractingUpdate {}
- (void)showExtractionReceivedProgress:(double)progress {}
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply { reply(SPUUserUpdateChoiceDismiss); }
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)applicationTerminated retryTerminatingApplication:(void (^)(void))retryTerminatingApplication {}
- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))acknowledgement { acknowledgement(); }
- (void)dismissUpdateInstallation {}
@end

static BOOL waitFor(BOOL (^done)(void))
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20];
    while (!done() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    return done();
}

static NSInteger feedRequests(NSString *base)
{
    NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:[base stringByAppendingString:@"/count"]]];
    return data == nil ? -1 : [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] integerValue];
}

static void testSparkleBackgroundCheckDuringVideoRunsOnceAfterStop(NSString *hostPath, NSString *base)
{
    NSBundle *host = [NSBundle bundleWithPath:hostPath];
    MXRDeferralProbe *probe = [MXRDeferralProbe new];
    SPUUpdater *updater = [[SPUUpdater alloc] initWithHostBundle:host applicationBundle:host userDriver:probe delegate:probe];
    NSError *error = nil;
    CHECK([updater startUpdater:&error], "Sparkle did not start: %s", error.description.UTF8String);

    probe.playingVideo = YES;
    [updater checkForUpdatesInBackground];
    CHECK(waitFor(^{ return (BOOL)(probe.refused == 1); }), "Sparkle never asked before its background check");
    waitFor(^{ return (BOOL)!updater.sessionInProgress; });
    CHECK(feedRequests(base) == 0, "the feed was read during playback (%ld requests)", (long)feedRequests(base));
    CHECK(probe->_deferral.pending, "the skipped check is remembered");

    CHECK(!MXRUpdateDeferralTakeWhenIdle(&probe->_deferral, true, YES), "never during playback");
    probe.playingVideo = NO;
    CHECK(MXRUpdateDeferralTakeWhenIdle(&probe->_deferral, false, YES), "playback stopped: the check runs");
    [updater checkForUpdatesInBackground];
    CHECK(waitFor(^{ return (BOOL)(probe.finished >= 1 && feedRequests(base) == 1); }),
          "the deferred check did not read the feed once (%ld requests)", (long)feedRequests(base));
    CHECK(!MXRUpdateDeferralTakeWhenIdle(&probe->_deferral, false, YES), "at most once");
    CHECK(probe.refused == 1, "refused %lu times", (unsigned long)probe.refused);
}
#endif

int main(int argc, const char **argv)
{
    @autoreleasepool {
        testBackgroundCheckDuringVideoIsDeferredNotDropped();
        testDeferredCheckRefusedAgainIfAVideoStartedMeanwhile();
        testAnyCheckThatRunsClearsTheDeferredOne();
        testDeferredCheckDroppedWhenAutomaticChecksWereTurnedOff();
        testNothingRunsWhenNoCheckWasSkipped();
#ifdef MXR_WITH_SPARKLE
        if (argc != 3) {
            fprintf(stderr, "usage: %s host.bundle feed-base-url\n", argv[0]);
            return 2;
        }
        testSparkleBackgroundCheckDuringVideoRunsOnceAfterStop(@(argv[1]), @(argv[2]));
#endif
    }
    if (failures == 0)
        printf("PASS: update deferral\n");
    return failures == 0 ? 0 : 1;
}
