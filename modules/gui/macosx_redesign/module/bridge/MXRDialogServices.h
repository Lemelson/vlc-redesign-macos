/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
#import <Foundation/Foundation.h>
#import "MXRBridgeKeys.h"
#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_dialog.h>
NS_ASSUME_NONNULL_BEGIN
@interface MXRDialogServices : NSObject
- (instancetype)initWithInterface:(intf_thread_t *)intf;
@property(nonatomic,copy,nullable) void (^serviceChanged)(NSString *);
- (NSDictionary *)snapshot;
- (void)display:(nullable vlc_dialog_id *)identifier values:(NSDictionary *)values;
- (BOOL)performCommand:(MXRBridgeCommand)command arguments:(NSDictionary *)arguments error:(NSError **)error;
- (void)shutdown;
@end
NS_ASSUME_NONNULL_END
