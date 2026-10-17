/*****************************************************************************
 * MXRIntf.m: interface Open/Close, NSApplication bootstrap
 *****************************************************************************
 * Copyright (C) 2026 VLC Redesign contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *****************************************************************************/

/*
 * Startup and shutdown follow the stock macosx interface (modules/gui/macosx/main/VLCMain.m,
 * OpenIntf/CloseIntf) and ARCHITECTURE.md §2.3 rule 7 and §2.4:
 *
 *  bin/darwinvlc.m runs CFRunLoopRun() on the main thread and starts libvlc on a private
 *  serial queue (the "interface thread"). MXROpenIntf is called there. It schedules the
 *  setup on the main run loop, waits for it, and returns; the main thread then stays in
 *  [NSApp run] until MXRCloseIntf stops it. After [NSApp run] returns, the main thread goes
 *  back to darwinvlc's CFRunLoopRun(), which keeps servicing the main queue until libvlc is
 *  released, so late vout blocks still run.
 *
 *  Quit (Cmd-Q, Dock, logout) goes through -[MXRApplication terminate:] -> libvlc_Quit ->
 *  darwinvlc's exit handler -> libvlc_release on the interface queue -> MXRCloseIntf.
 */

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#import <Cocoa/Cocoa.h>

#include <stdatomic.h>

#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_playlist.h>
#include <vlc_window.h>

#import "MXRModule.h"
#import "MXRSwiftEntry.h"
#import "MXRBridgeInternal.h"
#import "bridge/MXRAudioPreferenceServices.h"

#pragma mark - Application

/* The NSApplication instance. Overrides -terminate: so every quit path shuts libvlc down
 * cleanly instead of calling exit() (stock: VLCApplication.m). */
@interface MXRApplication : NSApplication
@end

@implementation MXRApplication

- (void)terminate:(id)sender
{
    VLC_UNUSED(sender);
    MXRInterfaceBridge *bridge = MXRCurrentInterfaceBridge();
    if (bridge != nil && !bridge.isShutDown)
        [bridge quit];
    /* else: already shutting down, the process exits by itself. */
}

@end

#pragma mark - Interface

static atomic_bool g_intf_running = false;
static vlc_sem_t g_wait_quit;

int MXROpenIntf(vlc_object_t *obj)
{
    intf_thread_t *intf = (intf_thread_t *)obj;

    if (atomic_exchange(&g_intf_running, true)) {
        msg_Err(intf, "the macosx_redesign interface is already running");
        return VLC_EGENERIC;
    }

    vlc_sem_init(&g_wait_quit, 0);

    /* Settings ▸ General ▸ Additional command line options, before anything plays. */
    MXRApplyStartupCommandLineOptions(obj);

    __block int retcode = VLC_SUCCESS;
    __block MXRInterfaceBridge *failedStartupBridge;
    dispatch_semaphore_t setupDone = dispatch_semaphore_create(0);

    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopDefaultMode, ^{
        @autoreleasepool {
            NSApplication *app = [MXRApplication sharedApplication];
            if (![app isKindOfClass:[MXRApplication class]])
                msg_Warn(intf, "NSApp already exists as %s; quit will bypass libvlc_Quit",
                         NSStringFromClass([app class]).UTF8String);
            [app setActivationPolicy:NSApplicationActivationPolicyRegular];

            MXRInterfaceBridge *bridge = [[MXRInterfaceBridge alloc] initWithInterface:intf];
            if (bridge == nil) {
                retcode = VLC_ENOMEM;
                dispatch_semaphore_signal(setupDone);
                return;
            }
            MXRSetCurrentInterfaceBridge(bridge);
            MXRVoutWindowSetInterfaceStarted();

            msg_Dbg(intf, "starting the Swift interface");
            int swiftStatus = MXRSwiftStart((__bridge void *)bridge);
            if (swiftStatus != 0) {
                msg_Err(intf, "the Swift interface failed to start (%d)", swiftStatus);
                MXRSwiftStop();
                [bridge shutdown];
                failedStartupBridge=bridge;
                MXRSetCurrentInterfaceBridge(nil);
                retcode = VLC_EGENERIC;
                dispatch_semaphore_signal(setupDone);
                return;
            }
            msg_Dbg(intf, "macosx_redesign interface started");
        }
        dispatch_semaphore_signal(setupDone);

        [NSApp run];

        vlc_sem_post(&g_wait_quit);
    });
    CFRunLoopWakeUp(CFRunLoopGetMain());

    dispatch_semaphore_wait(setupDone, DISPATCH_TIME_FOREVER);

    if (retcode != VLC_SUCCESS) {
        /* Shutdown detached main-thread listeners above; drain worker-owned
         * engine resources here before the failed interface is destroyed. */
        [failedStartupBridge finishShutdown];
        atomic_store(&g_intf_running, false);
    }
    return retcode;
}

void MXRCloseIntf(vlc_object_t *obj)
{
    intf_thread_t *intf = (intf_thread_t *)obj;

    __block MXRInterfaceBridge *closingBridge;
    void (^stopInterface)(void) = ^{
        @autoreleasepool {
            msg_Dbg(intf, "closing the macosx_redesign interface");
            MXRSwiftStop();
            MXRInterfaceBridge *bridge = MXRCurrentInterfaceBridge();
            closingBridge = bridge;
            [bridge shutdown];
            MXRSetCurrentInterfaceBridge(nil);
        }
        /* Leave [NSApp run]: -stop: takes effect after the next event, so post one. */
        [NSApp stop:nil];
        NSEvent *wakeUp = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                             location:NSZeroPoint
                                        modifierFlags:0
                                            timestamp:0.0
                                         windowNumber:0
                                              context:nil
                                              subtype:0
                                                data1:0
                                                data2:0];
        [NSApp postEvent:wakeUp atStart:YES];
    };

    if (CFRunLoopGetCurrent() == CFRunLoopGetMain())
        stopInterface();
    else
        dispatch_sync(dispatch_get_main_queue(), stopInterface);

    /* Slow service teardown joins workers on the interface thread after main detached sinks. */
    [closingBridge finishShutdown];

    /* Wait until [NSApp run] has returned on the main thread. */
    vlc_sem_wait(&g_wait_quit);
    atomic_store(&g_intf_running, false);
    msg_Dbg(intf, "macosx_redesign interface closed");
}
