/*****************************************************************************
 * MXRUpdaterBridge.h: app updates through Sparkle, independent of engine headers
 *****************************************************************************
 * Copyright (C) 2026 VLC Redesign contributors
 * Licensed under the GNU General Public License, version 2 or later.
 *****************************************************************************/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Told on main after a value of the updater changed, whoever changed it (Sparkle's own
/// permission question and update window write the same preferences).
NS_SWIFT_UI_ACTOR
@protocol MXRUpdaterEventSink <NSObject>
- (void)updaterDidChange;
@end

/// Sparkle's updater for this app (D059): the feed and EdDSA key come from Info.plist
/// (tools/app-bundle-hook.sh). Owned by MXRInterfaceBridge; nil there in builds without Sparkle.
NS_SWIFT_UI_ACTOR
@interface MXRUpdaterBridge : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (nonatomic, weak, nullable) id<MXRUpdaterEventSink> sink;
@property (nonatomic) BOOL automaticallyChecksForUpdates;
@property (nonatomic) BOOL automaticallyDownloadsUpdates;
@property (nonatomic, readonly) BOOL canCheckForUpdates;
@property (nonatomic, readonly, nullable) NSDate *lastUpdateCheckDate;
/// A user-initiated check; Sparkle's window shows the result.
- (void)checkForUpdates;
@end

NS_ASSUME_NONNULL_END
