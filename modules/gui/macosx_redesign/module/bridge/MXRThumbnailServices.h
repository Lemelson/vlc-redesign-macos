/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
#import <Foundation/Foundation.h>
#import "MXRBridgeKeys.h"
#include <vlc_common.h>
#include <vlc_interface.h>
NS_ASSUME_NONNULL_BEGIN
@interface MXRThumbnailServices : NSObject
- (instancetype)initWithInterface:(intf_thread_t *)intf;
@property(nonatomic,readonly) BOOL available;
- (void)request:(MXRBridgeRequest)request arguments:(NSDictionary *)arguments completion:(void (^)(NSDictionary * _Nullable,NSError * _Nullable))completion;
- (void)shutdown;
- (void)finishShutdown;
@end
NS_ASSUME_NONNULL_END
