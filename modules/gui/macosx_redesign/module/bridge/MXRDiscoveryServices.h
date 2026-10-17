/*****************************************************************************
 * MXRDiscoveryServices.h: private media-source adapter
 *****************************************************************************
 * Copyright (C) 2026 VLC Redesign contributors
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Foundation/Foundation.h>
#import "MXRBridgeKeys.h"

typedef struct intf_thread_t intf_thread_t;

NS_ASSUME_NONNULL_BEGIN

/// Private bridge helper. Public payloads contain Foundation values only.
/// Entry points, snapshots and delivery use the main thread; discovery and I/O
/// run on a serial worker. finishShutdown must run off-main before core teardown.
@interface MXRDiscoveryServices : NSObject
- (instancetype)initWithInterface:(intf_thread_t *)intf;
@property (nonatomic, copy, nullable) void (^serviceChanged)(NSString *service);
@property (nonatomic, readonly) NSDictionary *capabilities;
- (NSDictionary *)snapshotForService:(MXRBridgeService)service;
- (BOOL)performCommand:(MXRBridgeCommand)command service:(MXRBridgeService)service
             arguments:(NSDictionary *)arguments error:(NSError * _Nullable * _Nullable)error;
- (void)request:(MXRBridgeRequest)request service:(MXRBridgeService)service
       arguments:(NSDictionary *)arguments
      completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion;
- (void)shutdown;
- (void)finishShutdown;
@end

NS_ASSUME_NONNULL_END
