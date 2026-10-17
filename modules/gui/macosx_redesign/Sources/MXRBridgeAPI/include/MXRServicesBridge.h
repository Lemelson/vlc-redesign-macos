/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
#import <Foundation/Foundation.h>
#import "MXRBridgeKeys.h"

NS_ASSUME_NONNULL_BEGIN

/// Notifications are delivered on main after engine changes. Read a new immutable snapshot.
NS_SWIFT_UI_ACTOR
@protocol MXRServicesEventSink <NSObject>
- (void)bridgeServiceDidChange:(MXRBridgeService)service;
@end

/// Foundation boundary for VLC services. Times are signed microseconds; missing fields
/// are unavailable, never fabricated. Commands fail with NSError for unsupported services,
/// stale IDs and invalid arguments. All public entry points and completions run on main.
NS_SWIFT_UI_ACTOR
@interface MXRServicesBridge : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nonatomic, weak, nullable) id<MXRServicesEventSink> sink;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, id> *capabilities;
- (NSDictionary<NSString *, id> *)snapshotForService:(MXRBridgeService)service NS_SWIFT_NAME(snapshot(for:));
- (BOOL)performCommand:(MXRBridgeCommand)command service:(MXRBridgeService)service
             arguments:(NSDictionary<NSString *, id> *)arguments error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(perform(_:service:arguments:));
- (void)request:(MXRBridgeRequest)request service:(MXRBridgeService)service
       arguments:(NSDictionary<NSString *, id> *)arguments
      completion:(void (^)(NSDictionary<NSString *, id> * _Nullable result, NSError * _Nullable error))completion
    NS_SWIFT_NAME(request(_:service:arguments:completion:));
@end

NS_ASSUME_NONNULL_END
