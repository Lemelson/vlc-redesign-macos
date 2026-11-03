/*****************************************************************************
 * MXRUpdaterBridge.m: app updates through Sparkle (D059)
 *****************************************************************************
 * Copyright (C) 2026 VLC Redesign contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *****************************************************************************/

/*
 * The stock interface does the same in modules/gui/macosx/main/VLCMain+Sparkle.m: Sparkle's
 * standard controller and its windows, playback stopped before an install. Differences: one feed
 * for both architectures (the DMG is universal), a manual check is never refused, and the
 * channels allowed are read from the defaults so an opt-in channel can be added later without
 * another manual download (updates-design.md).
 */

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#import <Cocoa/Cocoa.h>

#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_player.h>
#include <vlc_playlist.h>
#include <vlc_window.h>

#import "MXRBridgeInternal.h"

#ifdef HAVE_SPARKLE
#import <Sparkle/Sparkle.h>

/// Extra Sparkle channels this Mac follows (array of strings), e.g. a future "engine" channel.
static NSString *const MXRUpdateChannelsKey = @"MXRUpdateChannels";
static void *MXRUpdaterObservation = &MXRUpdaterObservation;
/* Keeps the controller after the interface closes (main thread only). */
static SPUStandardUpdaterController *g_retained_controller;

@interface MXRUpdaterBridge () <SPUUpdaterDelegate>
@end
#endif

@implementation MXRUpdaterBridge
{
    vlc_playlist_t *_playlist;
#ifdef HAVE_SPARKLE
    SPUStandardUpdaterController *_controller;
#endif
    BOOL _shutDown;
}

- (nullable instancetype)initWithPlaylist:(vlc_playlist_t *)playlist
{
#ifdef HAVE_SPARKLE
    self = [super init];
    if (self) {
        _playlist = playlist;
        // Starts the scheduled checks; Sparkle asks for permission on the second launch.
        _controller = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:YES
                                                                    updaterDelegate:self
                                                                 userDriverDelegate:nil];
        for (NSString *key in @[@"canCheckForUpdates", @"automaticallyChecksForUpdates",
                                @"automaticallyDownloadsUpdates", @"lastUpdateCheckDate"])
            [_controller.updater addObserver:self forKeyPath:key options:0 context:MXRUpdaterObservation];
    }
    return self;
#else
    (void)playlist;
    return nil;
#endif
}

#ifdef HAVE_SPARKLE
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context != MXRUpdaterObservation) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_shutDown)
            [self.sink updaterDidChange];
    });
}

- (BOOL)automaticallyChecksForUpdates { return _controller.updater.automaticallyChecksForUpdates; }
- (void)setAutomaticallyChecksForUpdates:(BOOL)value { _controller.updater.automaticallyChecksForUpdates = value; }
- (BOOL)automaticallyDownloadsUpdates { return _controller.updater.automaticallyDownloadsUpdates; }
- (void)setAutomaticallyDownloadsUpdates:(BOOL)value { _controller.updater.automaticallyDownloadsUpdates = value; }
- (BOOL)canCheckForUpdates { return !_shutDown && _controller.updater.canCheckForUpdates; }
- (nullable NSDate *)lastUpdateCheckDate { return _controller.updater.lastUpdateCheckDate; }

- (void)checkForUpdates
{
    if (self.canCheckForUpdates)
        [_controller checkForUpdates:nil];
}

/* The controller lives until the process exits: an update downloaded for "install on quit"
 * is installed by Sparkle's helper once this process is gone. */
- (void)shutdown
{
    if (_shutDown)
        return;
    _shutDown = YES;
    _sink = nil;
    for (NSString *key in @[@"canCheckForUpdates", @"automaticallyChecksForUpdates",
                            @"automaticallyDownloadsUpdates", @"lastUpdateCheckDate"])
        [_controller.updater removeObserver:self forKeyPath:key context:MXRUpdaterObservation];
    g_retained_controller = _controller;
}

static bool MXRPlayingVideo(vlc_playlist_t *playlist)
{
    vlc_player_t *player = vlc_playlist_GetPlayer(playlist);
    vlc_player_Lock(player);
    bool video = vlc_player_GetState(player) == VLC_PLAYER_STATE_PLAYING
              && vlc_player_GetVideoTrackCount(player) > 0;
    vlc_player_Unlock(player);
    return video;
}

/* A background check waits while a video plays, so no update window covers it; the next
 * scheduled check runs it. A check the user asked for always runs. */
- (BOOL)updater:(SPUUpdater *)updater mayPerformUpdateCheck:(SPUUpdateCheck)updateCheck error:(NSError * __autoreleasing *)error
{
    if (_shutDown)
        return NO;
    if (updateCheck == SPUUpdateCheckUpdatesInBackground && MXRPlayingVideo(_playlist)) {
        if (error != NULL)
            *error = [NSError errorWithDomain:@"io.github.lemelson.vlc-redesign.updates" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"A video is playing."}];
        return NO;
    }
    return YES;
}

/* Received right before Sparkle quits the app to install: stop like the stock interface. */
- (void)updater:(SPUUpdater *)updater willInstallUpdate:(SUAppcastItem *)item
{
    if (_shutDown)
        return;
    vlc_playlist_Lock(_playlist);
    vlc_playlist_Stop(_playlist);
    vlc_playlist_Unlock(_playlist);
}

- (NSSet<NSString *> *)allowedChannelsForUpdater:(SPUUpdater *)updater
{
    NSArray *channels = [NSUserDefaults.standardUserDefaults arrayForKey:MXRUpdateChannelsKey];
    NSMutableSet<NSString *> *allowed = [NSMutableSet set];
    for (id channel in channels)
        if ([channel isKindOfClass:NSString.class])
            [allowed addObject:channel];
    return allowed;
}

- (void)updater:(SPUUpdater *)updater didAbortWithError:(NSError *)error
{
    intf_thread_t *intf = MXRCurrentInterfaceBridge().intf;
    if (intf != NULL)
        msg_Warn(intf, "update check stopped: %s (%ld)", error.localizedDescription.UTF8String, (long)error.code);
}
#else
- (BOOL)automaticallyChecksForUpdates { return NO; }
- (void)setAutomaticallyChecksForUpdates:(BOOL)value {}
- (BOOL)automaticallyDownloadsUpdates { return NO; }
- (void)setAutomaticallyDownloadsUpdates:(BOOL)value {}
- (BOOL)canCheckForUpdates { return NO; }
- (nullable NSDate *)lastUpdateCheckDate { return nil; }
- (void)checkForUpdates {}
- (void)shutdown { _shutDown = YES; }
#endif

@end
