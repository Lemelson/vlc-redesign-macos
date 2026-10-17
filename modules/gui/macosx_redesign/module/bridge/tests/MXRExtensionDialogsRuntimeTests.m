/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
/* A real Lua extension opens a dialog through the real engine: the dialog provider draws it
 * natively, a typed value and a button click reach the script, the script's own update is
 * drawn, closing the window deactivates it, and closing the interface while a dialog is open
 * never waits for the main thread (C-05). */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#import <Cocoa/Cocoa.h>
#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_playlist.h>
#include "libvlc_internal.h"
#import "../MXRMediaServices.h"
#import "../MXRDialogServices.h"

static void require(BOOL value, NSString *message)
{
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}

static void spinUntil(BOOL (^done)(void), NSString *message)
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!done() && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
    require(done(), message);
}

static NSDictionary *request(MXRMediaServices *service, NSString *name, NSDictionary *arguments)
{
    __block BOOL completed = NO;
    __block NSDictionary *result = nil;
    __block NSError *failure = nil;
    [service request:name service:@"extensions" arguments:arguments completion:^(NSDictionary *value, NSError *error) {
        completed = YES; result = value; failure = error;
    }];
    spinUntil(^{ return completed; }, [NSString stringWithFormat:@"%@ completes", name]);
    require(failure == nil, [NSString stringWithFormat:@"%@ succeeds: %@", name, failure]);
    return result;
}

static NSArray<NSView *> *descendants(NSView *view)
{
    NSMutableArray *all = [NSMutableArray arrayWithObject:view];
    for (NSView *child in view.subviews) [all addObjectsFromArray:descendants(child)];
    return all;
}

static NSDictionary *dialogWindows(MXRDialogServices *dialogs) { return [dialogs valueForKey:@"extWindows"]; }
static NSWindow *onlyWindow(MXRDialogServices *dialogs)
{
    NSDictionary *windows = dialogWindows(dialogs);
    return windows.count == 1 ? [windows.allValues.firstObject valueForKey:@"window"] : nil;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        char temporary[] = "/private/tmp/MXR-extension-dialogs-XXXXXX";
        require(mkdtemp(temporary) != NULL, @"private isolated test root created");
        NSString *root = [NSString stringWithUTF8String:temporary];
        NSString *user = [root stringByAppendingPathComponent:@"user"];
        NSString *marker = [root stringByAppendingPathComponent:@"typed.txt"];
        NSString *script = [user stringByAppendingPathComponent:@"lua/extensions/Dialog.lua"];
        [NSFileManager.defaultManager createDirectoryAtPath:script.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *lua = [NSString stringWithFormat:
            @"function descriptor() return {title=\"Dialog fixture\", capabilities={}} end\n"
             "local d, label, field\n"
             "function activate()\n"
             "  d = vlc.dialog(\"Fixture dialog\")\n"
             "  label = d:add_label(\"Hello <b>world</b>\", 1, 1, 2, 1)\n"
             "  field = d:add_text_input(\"typed\", 1, 2, 1, 1)\n"
             "  d:add_button(\"Go\", go, 2, 2, 1, 1)\n"
             "  d:show()\n"
             "end\n"
             "function go()\n"
             "  label:set_text(\"Got \" .. field:get_text())\n"
             "  local f = io.open(\"%@\", \"w\"); f:write(field:get_text()); f:close()\n"
             "end\n"
             "function close() vlc.deactivate() end\n"
             "function deactivate() if d then d:delete(); d = nil end end\n", marker];
        require([lua writeToFile:script atomically:YES encoding:NSUTF8StringEncoding error:nil], @"fixture extension written");
        setenv("VLC_USERDATA_PATH", user.fileSystemRepresentation, 1);
        setenv("VLC_DATA_PATH", root.fileSystemRepresentation, 1);
        const char *options[] = {"MXRExtensionDialogsRuntimeTests", "--ignore-config", "--no-media-library", "--no-auto-preparse", "--aout=dummy", "--verbose=0"};
        libvlc_int_t *vlc = libvlc_InternalCreate();
        require(vlc != NULL && libvlc_InternalInit(vlc, 6, options) == VLC_SUCCESS, @"real VLC initializes");
        libvlc_InternalPlay(vlc);
        intf_thread_t *intf = vlc_object_create(vlc, sizeof(*intf));
        require(intf != NULL, @"test interface created");
        MXRDialogServices *dialogs = [[MXRDialogServices alloc] initWithInterface:intf];
        MXRMediaServices *service = [[MXRMediaServices alloc] initWithPlaylist:vlc_intf_GetMainPlaylist(intf) interface:intf];

        NSDictionary *catalog = request(service, @"list", @{});
        NSString *identifier = nil;
        for (NSDictionary *item in catalog[@"items"]) if ([item[@"name"] isEqual:@"Dialog fixture"]) identifier = item[@"id"];
        require(identifier != nil && [catalog[@"supportsActivation"] boolValue], @"fixture discovered and activatable");

        request(service, @"activate", @{@"id": identifier});
        spinUntil(^{ return (BOOL)(onlyWindow(dialogs).visible); }, @"the script's dialog is shown in a native window");
        NSWindow *window = onlyWindow(dialogs);
        require([window.title isEqual:@"Fixture dialog"], @"dialog title");
        NSArray<NSView *> *views = descendants(window.contentView);
        NSTextField *label = nil, *field = nil; NSButton *go = nil;
        for (NSView *view in views) {
            if ([view isKindOfClass:NSButton.class] && [((NSButton *)view).title isEqual:@"Go"]) go = (NSButton *)view;
            else if ([view isKindOfClass:NSTextField.class] && ((NSTextField *)view).editable) field = (NSTextField *)view;
            else if ([view isKindOfClass:NSTextField.class] && [((NSTextField *)view).stringValue isEqual:@"Hello world"]) label = (NSTextField *)view;
        }
        require(label != nil && field != nil && go != nil, @"label (rich text), text field and button are drawn");
        require([field.stringValue isEqual:@"typed"], @"the field shows the script's initial text");

        field.stringValue = @"abc";
        [NSNotificationCenter.defaultCenter postNotificationName:NSControlTextDidChangeNotification object:field];
        [go performClick:nil];
        spinUntil(^{ return [[NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:nil] isEqual:@"abc"]; },
                  @"the click runs the script, which reads the typed value");
        spinUntil(^{ return [label.stringValue isEqual:@"Got abc"]; }, @"the script's label update is drawn");
        const char *snapshot = getenv("MXR_EXTENSION_DIALOG_SNAPSHOT"); /* optional visual evidence */
        if (snapshot != NULL) {
            NSView *content = window.contentView;
            [content layoutSubtreeIfNeeded];
            NSBitmapImageRep *image = [content bitmapImageRepForCachingDisplayInRect:content.bounds];
            [content cacheDisplayInRect:content.bounds toBitmapImageRep:image];
            [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(snapshot) atomically:YES];
        }

        [window performClose:nil];
        spinUntil(^{ return (BOOL)(dialogWindows(dialogs).count == 0); }, @"closing the window lets the script delete its dialog");
        spinUntil(^{
            for (NSDictionary *item in request(service, @"list", @{})[@"items"])
                if ([item[@"id"] isEqual:identifier]) return (BOOL)![item[@"active"] boolValue];
            return NO;
        }, @"the script deactivated itself on close");

        /* Quit with a dialog open: the provider lets go synchronously, unloading never waits for main. */
        request(service, @"activate", @{@"id": identifier});
        spinUntil(^{ return (BOOL)(onlyWindow(dialogs).visible); }, @"dialog shown again");
        [dialogs shutdown];
        [service shutdown];
        __block BOOL stopped = NO;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [service finishShutdown];
            vlc_object_delete(intf);
            libvlc_InternalCleanup(vlc);
            libvlc_InternalDestroy(vlc);
            stopped = YES;
        });
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (!stopped && deadline.timeIntervalSinceNow > 0) usleep(10000); /* main is deliberately not serviced */
        require(stopped, @"unloading an extension with an open dialog does not need the main thread");
        [NSFileManager.defaultManager removeItemAtPath:root error:nil];
        NSLog(@"PASS: real Lua dialog drawn natively, typed text and click reach the script, script updates drawn, close deactivates, quit never waits for main");
    }
    return 0;
}
