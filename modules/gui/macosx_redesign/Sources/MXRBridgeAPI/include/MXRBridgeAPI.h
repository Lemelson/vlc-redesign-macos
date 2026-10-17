/*****************************************************************************
 * MXRBridgeAPI.h: Objective-C interface between the VLC bridge and Swift
 *****************************************************************************
 * Copyright (C) 2026 VLC Redesign contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *****************************************************************************/

/*
 * Umbrella header of the MXRBridgeAPI SwiftPM target (ARCHITECTURE.md §2, §7.2).
 *
 * Rules for every header in this directory:
 *  - Foundation / AppKit / CoreGraphics types only. Never include <vlc_*.h>.
 *  - The implementations live in module/ (Objective-C, compiled by automake) and are
 *    linked into the plugin. Swift code only ever receives instances from the bridge
 *    (MXRSwiftStart hands over the MXRInterfaceBridge); it never allocates bridge classes.
 *  - Classes and sink protocols are NS_SWIFT_UI_ACTOR: they are only used on the main
 *    thread, and every event is delivered on the main queue (threading rules, §2.3).
 *  - Times are signed microseconds (like vlc_tick_t and MXRCore's MediaTime), -1 = unknown.
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#import "MXRBridgeKeys.h"
#import "MXRPlayerBridge.h"
#import "MXRServicesBridge.h"
#import "MXRVideoOutput.h"
#import "MXRInterfaceBridge.h"
#import "MXRPlatformServices.h"
