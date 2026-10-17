/*****************************************************************************
 * MXRInterfaceBridge.m: the interface's entry object handed to Swift
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

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#import <Cocoa/Cocoa.h>

#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_input_item.h>
#include <vlc_playlist.h>
#include <vlc_window.h>

#import "MXRBridgeInternal.h"

static MXRInterfaceBridge *g_current_bridge; /* main thread only */

MXRInterfaceBridge *MXRCurrentInterfaceBridge(void)
{
    return g_current_bridge;
}

void MXRSetCurrentInterfaceBridge(MXRInterfaceBridge *bridge)
{
    g_current_bridge = bridge;
}

@implementation MXRInterfaceBridge
{
    intf_thread_t *_intf;
    vlc_playlist_t *_playlist;
    BOOL _shutDown;
}

- (nullable instancetype)initWithInterface:(intf_thread_t *)intf
{
    self = [super init];
    if (self) {
        _intf = intf;
        _playlist = vlc_intf_GetMainPlaylist(intf);
        if (_playlist == NULL)
            return nil;
        _player = [[MXRPlayerBridge alloc] initWithPlaylist:_playlist interface:intf];
        if (_player == nil)
            return nil;
        _services = [[MXRServicesBridge alloc] initWithPlaylist:_playlist interface:intf];
        if (_services == nil) {
            [_player shutdown];
            return nil;
        }
    }
    return self;
}

- (intf_thread_t *)intf
{
    return _intf;
}

- (BOOL)isShutDown
{
    return _shutDown;
}

- (void)shutdown
{
    if (_shutDown)
        return;
    _shutDown = YES;
    _videoSurfaceProvider = nil;
    [_player shutdown];
    [_services shutdown];
}

- (void)finishShutdown { [_services finishShutdown]; }

- (NSString *)vlcVersion
{
    return @VERSION;
}

- (MXRVideoSurfaceView *)makeVideoSurface
{
    return [[MXRVideoSurfaceView alloc] initWithFrame:NSMakeRect(0., 0., 640., 360.)];
}

- (void)openURLs:(NSArray<NSURL *> *)urls play:(BOOL)play
{
    if (_shutDown || urls.count == 0)
        return;

    const size_t capacity = urls.count;
    input_item_t **items = vlc_alloc(capacity, sizeof(*items));
    if (items == NULL)
        return;

    size_t count = 0;
    for (NSURL *url in urls) {
        NSString *uri = url.absoluteString;
        if (uri.length == 0)
            continue;
        input_item_t *item = input_item_New(uri.UTF8String, NULL);
        if (item != NULL)
            items[count++] = item;
    }

    if (count > 0) {
        vlc_playlist_Lock(_playlist);
        const size_t index = vlc_playlist_Count(_playlist);
        int ret = vlc_playlist_Insert(_playlist, index, items, count);
        if (ret == VLC_SUCCESS && play)
            vlc_playlist_PlayAt(_playlist, index);
        vlc_playlist_Unlock(_playlist);
        if (ret != VLC_SUCCESS)
            msg_Err(_intf, "could not add %zu item(s) to the playlist", count);
    }

    for (size_t i = 0; i < count; i++)
        input_item_Release(items[i]);
    free(items);
}

- (void)quit
{
    if (_shutDown)
        return;
    msg_Dbg(_intf, "quit requested by the user interface");
    libvlc_Quit(vlc_object_instance(_intf));
}

- (void)log:(NSString *)message level:(MXRLogLevel)level
{
    if (_shutDown || message == nil)
        return;
    int vlcLevel;
    switch (level) {
        case MXRLogLevelError:   vlcLevel = VLC_MSG_ERR;  break;
        case MXRLogLevelWarning: vlcLevel = VLC_MSG_WARN; break;
        case MXRLogLevelDebug:   vlcLevel = VLC_MSG_DBG;  break;
        case MXRLogLevelInfo:
        default:                 vlcLevel = VLC_MSG_INFO; break;
    }
    msg_Generic(_intf, vlcLevel, "%s", message.UTF8String);
}

@end
