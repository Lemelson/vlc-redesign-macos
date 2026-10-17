/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#import <Foundation/Foundation.h>
#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_playlist.h>
#include <vlc_configuration.h>
#include <sys/stat.h>
#include "libvlc_internal.h"
#import "../MXRMediaServices.h"

static void require(BOOL value, NSString *message)
{
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}

static NSDictionary *request(MXRMediaServices *service, NSString *name, NSDictionary *arguments, NSError **error)
{
    __block NSUInteger completions = 0;
    __block NSDictionary *result = nil;
    __block NSError *failure = nil;
    [service request:name service:@"extensions" arguments:arguments completion:^(NSDictionary *value, NSError *requestError) {
        completions++; result = value; failure = requestError;
    }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (completions == 0 && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
    require(completions == 1, [NSString stringWithFormat:@"%@ completes exactly once", name]);
    *error = failure;
    return result;
}

static NSString *waitForText(NSString *path, NSString *expected)
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    NSString *text = nil;
    while (deadline.timeIntervalSinceNow > 0) {
        text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        if ([text isEqual:expected]) break;
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
    }
    return text;
}

static NSDictionary *find(NSDictionary *catalog, NSString *title)
{
    for (NSDictionary *item in catalog[@"items"]) if ([item[@"name"] isEqual:title]) return item;
    return nil;
}

static void writeFile(NSString *path, NSString *text)
{
    NSError *error = nil;
    require([NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:nil error:&error], @"isolated fixture directory created");
    require([text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error], @"isolated fixture written");
}

static NSString *fixture(NSString *title, NSString *marker)
{
    return [NSString stringWithFormat:
        @"function descriptor() return {title=\"%@\", version=\"1\", capabilities={}} end\n"
         "function activate() local f=io.open(\"%@\",\"a\"); f:write(\"A\"); f:close() end\n"
         "function deactivate() local f=io.open(\"%@\",\"a\"); f:write(\"D\"); f:close() end\n",
        title, marker, marker];
}

int main(void)
{
    @autoreleasepool {
        char temporary[] = "/private/tmp/MXR-extension-services-XXXXXX";
        require(mkdtemp(temporary) != NULL, @"private isolated test root created");
        NSString *root = [NSString stringWithUTF8String:temporary];
        NSString *user = [root stringByAppendingPathComponent:@"user"];
        NSString *system = [root stringByAppendingPathComponent:@"system"];
        NSString *extensions = [user stringByAppendingPathComponent:@"lua/extensions"];
        NSString *source = [root stringByAppendingPathComponent:@"incoming/Local.lua"];
        NSString *installed = [extensions stringByAppendingPathComponent:@"Local.lua"];
        NSString *marker = [root stringByAppendingPathComponent:@"activation.txt"];
        NSString *stock = [system stringByAppendingPathComponent:@"lua/extensions/Stock.lua"];
        NSString *localText = fixture(@"Local managed fixture", marker);
        writeFile(source, localText);
        writeFile(stock, fixture(@"Stock fixture", [root stringByAppendingPathComponent:@"stock-activation.txt"]));
        setenv("VLC_USERDATA_PATH", user.fileSystemRepresentation, 1);
        setenv("VLC_DATA_PATH", system.fileSystemRepresentation, 1);
        setenv("VLC_LIBEXEC_PATH", system.fileSystemRepresentation, 1);
        const char *options[] = {"MXRExtensionServicesRuntimeTests", "--ignore-config", "--no-media-library", "--no-auto-preparse", "--aout=dummy", "--verbose=0"};
        libvlc_int_t *vlc = libvlc_InternalCreate();
        require(vlc != NULL && libvlc_InternalInit(vlc, 6, options) == VLC_SUCCESS, @"real VLC initializes without user config");
        require(var_InheritBool(vlc, "ignore-config"), @"user config and autosave remain disabled");
        char *actualUser = config_GetUserDir(VLC_USERDATA_DIR);
        require(actualUser != NULL && [user isEqual:[NSString stringWithUTF8String:actualUser]], @"Darwin userdata resolves to the isolated fixture root");
        free(actualUser);
        libvlc_InternalPlay(vlc);
        intf_thread_t *intf = vlc_object_create(vlc, sizeof(*intf));
        require(intf != NULL, @"test interface created");
        vlc_playlist_t *playlist = vlc_intf_GetMainPlaylist(intf);
        MXRMediaServices *service = [[MXRMediaServices alloc] initWithPlaylist:playlist interface:intf];
        NSError *error = nil;
        NSDictionary *catalog = request(service, @"list", @{}, &error);
        require(catalog != nil && error == nil && find(catalog, @"Stock fixture") != nil, @"real engine discovers isolated stock fixture");

        catalog = request(service, @"installExtension", @{@"url": [NSURL fileURLWithPath:source].absoluteString}, &error);
        require(catalog != nil && error == nil, [NSString stringWithFormat:@"local Lua installation succeeds: %@", error]);
        NSDictionary *item = find(catalog, @"Local managed fixture");
        require(item != nil && [item[@"removable"] boolValue], [NSString stringWithFormat:@"real Lua manager discovers removable installed descriptor: %@ (%@)", item, catalog[@"localUnavailableReason"]]);
        require([catalog[@"supportsInstall"] boolValue] && [catalog[@"supportsRemove"] boolValue], @"local capabilities enabled after manager load");
        require(![catalog[@"supportsSearchCatalog"] boolValue], @"online provider remains explicitly unsupported");
        require([[NSString stringWithContentsOfFile:installed encoding:NSUTF8StringEncoding error:nil] isEqual:localText], @"installed bytes match original");
        require([[NSString stringWithContentsOfFile:source encoding:NSUTF8StringEncoding error:nil] isEqual:localText], @"incoming source is unchanged");
        NSString *identifier = item[@"id"];
        require([identifier isEqual:installed], @"installed ID comes from actual VLC descriptor path");

        require(request(service, @"installExtension", @{@"url": [NSURL fileURLWithPath:source].absoluteString}, &error) == nil && error.code == EEXIST,
                @"duplicate installation never overwrites an existing Lua file");
        require([[NSString stringWithContentsOfFile:installed encoding:NSUTF8StringEncoding error:nil] isEqual:localText], @"duplicate leaves installed bytes intact");
        require(request(service, @"searchAddons", @{@"text": @"fixture"}, &error) == nil && error.code == ENOTSUP, @"no fake online catalog success");
        for (id invalidURL in @[@"https://example.com/extension.lua", @"file:relative.lua", @"file:///tmp/file.txt", NSNull.null])
            require(request(service, @"installExtension", @{@"url": invalidURL}, &error) == nil && error.code == EINVAL,
                    @"installation requires an absolute local Lua file URL");

        NSString *invalid = [root stringByAppendingPathComponent:@"incoming/Invalid.lua"];
        writeFile(invalid, @"this is not valid lua");
        require(request(service, @"installExtension", @{@"url": [NSURL fileURLWithPath:invalid].absoluteString}, &error) == nil,
                @"invalid Lua descriptor reports failure");
        require(![NSFileManager.defaultManager fileExistsAtPath:[extensions stringByAppendingPathComponent:@"Invalid.lua"]], @"failed install rolls back only its own file");
        require([NSFileManager.defaultManager fileExistsAtPath:installed], @"failed install preserves other installed extensions");

        require(request(service, @"removeExtension", @{@"id": stock}, &error) == nil && error.code == EPERM, @"stock extension removal is refused");
        require([NSFileManager.defaultManager fileExistsAtPath:stock], @"stock fixture remains intact");
        require(request(service, @"removeExtension", @{@"id": [extensions stringByAppendingPathComponent:@"../../incoming/Local.lua"]}, &error) == nil,
                @"escaping IDs are refused");
        require([NSFileManager.defaultManager fileExistsAtPath:source], @"escaping request leaves outside source intact");

        NSString *sourceLink = [root stringByAppendingPathComponent:@"incoming/Linked.lua"];
        require([NSFileManager.defaultManager createSymbolicLinkAtPath:sourceLink withDestinationPath:source error:nil], @"source symlink fixture created");
        require(request(service, @"installExtension", @{@"url": [NSURL fileURLWithPath:sourceLink].absoluteString}, &error) == nil, @"source symlink installation is refused");
        NSString *installedLink = [extensions stringByAppendingPathComponent:@"Linked.lua"];
        require([NSFileManager.defaultManager createSymbolicLinkAtPath:installedLink withDestinationPath:source error:nil], @"installed symlink fixture created");
        catalog = request(service, @"rescan", @{}, &error);
        require(catalog != nil && error == nil, @"rescan loads isolated symlink descriptor");
        require(request(service, @"removeExtension", @{@"id": installedLink}, &error) == nil && error.code == EPERM, @"symlink removal is refused");
        NSString *replacement = [root stringByAppendingPathComponent:@"replacement/Linked.lua"];
        writeFile(replacement, fixture(@"Replacement fixture", [root stringByAppendingPathComponent:@"replacement-activation.txt"]));
        require(request(service, @"installExtension", @{@"url": [NSURL fileURLWithPath:replacement].absoluteString}, &error) == nil && error.code == EEXIST,
                @"install never replaces an existing destination symlink");
        struct stat linkStat;
        require(lstat(installedLink.fileSystemRepresentation, &linkStat) == 0 && S_ISLNK(linkStat.st_mode), @"symlink and its target remain intact");

        require([catalog[@"supportsDialogs"] isEqual:@YES] && [catalog[@"supportsActivation"] isEqual:@YES],
                @"catalog advertises execution: extension dialogs have a provider (C-05)");
        require(![NSFileManager.defaultManager fileExistsAtPath:marker], @"discovery never calls Lua activate");
        require(request(service, @"triggerMenu", @{@"id": identifier}, &error) == nil && error.code == EINVAL, @"a menu trigger needs a menu item id");
        require(request(service, @"activate", @{@"id": identifier}, &error) != nil && error == nil, @"managed extension activates");
        require([waitForText(marker, @"A") isEqual:@"A"], @"activation runs the script's activate() once");
        require(request(service, @"activate", @{@"id": identifier}, &error) != nil && error == nil, @"activating an active extension is a no-op");
        require(request(service, @"deactivate", @{@"id": identifier}, &error) != nil && error == nil, @"active extension deactivates");
        require([waitForText(marker, @"AD") isEqual:@"AD"], @"deactivation runs the script's deactivate() once");
        require(request(service, @"deactivate", @{@"id": identifier}, &error) != nil && error == nil,
                @"inactive managed extension can still be deactivated safely");
        catalog = request(service, @"removeExtension", @{@"id": identifier}, &error);
        require(catalog != nil && error == nil && ![NSFileManager.defaultManager fileExistsAtPath:installed], @"inactive user extension removed");
        require([waitForText(marker, @"AD") isEqual:@"AD"], @"deactivation and removal never execute an inactive Lua callback again");
        for (NSDictionary *remaining in catalog[@"items"]) require(![remaining[@"id"] isEqual:identifier], @"removed descriptor disappears from reloaded manager");
        require(request(service, @"removeExtension", @{@"id": identifier}, &error) == nil && error.code == ENOENT, @"repeat removal reports missing extension");

        NSString *saved = [user stringByAppendingPathComponent:@"saved-extensions"];
        NSString *outside = [root stringByAppendingPathComponent:@"outside"];
        require([NSFileManager.defaultManager createDirectoryAtPath:outside withIntermediateDirectories:YES attributes:nil error:nil], @"outside fixture directory created");
        require([NSFileManager.defaultManager moveItemAtPath:extensions toPath:saved error:nil], @"extension directory fixture moved");
        require([NSFileManager.defaultManager createSymbolicLinkAtPath:extensions withDestinationPath:outside error:nil], @"extension directory symlink fixture created");
        require(request(service, @"installExtension", @{@"url": [NSURL fileURLWithPath:source].absoluteString}, &error) == nil, @"symlinked install directory is refused");
        require(![NSFileManager.defaultManager fileExistsAtPath:[outside stringByAppendingPathComponent:@"Local.lua"]], @"no file written through directory symlink");
        require([NSFileManager.defaultManager removeItemAtPath:extensions error:nil], @"test directory symlink restored");
        require([NSFileManager.defaultManager moveItemAtPath:saved toPath:extensions error:nil], @"test directory restored");

        __block NSUInteger completions = 0;
        __block NSUInteger successes = 0;
        __block NSUInteger duplicates = 0;
        for (NSUInteger i = 0; i < 2; i++) {
            [service request:@"installExtension" service:@"extensions" arguments:@{@"url": [NSURL fileURLWithPath:source].absoluteString}
                completion:^(NSDictionary *value, NSError *failure) {
                    completions++;
                    if (value != nil && failure == nil) successes++;
                    if (value == nil && failure.code == EEXIST) duplicates++;
                }];
        }
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (completions < 2 && deadline.timeIntervalSinceNow > 0)
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
        require(completions == 2 && successes == 1 && duplicates == 1, @"queued installs serialize with one success, one duplicate and exactly one callback per request");
        require(request(service, @"removeExtension", @{@"id": identifier}, &error) != nil && error == nil, @"serialized installation is removable");

        NSString *triggerSource = [root stringByAppendingPathComponent:@"incoming/Trigger.lua"];
        NSString *triggerMarker = [root stringByAppendingPathComponent:@"trigger.txt"];
        writeFile(triggerSource, [NSString stringWithFormat:
            @"function descriptor() return {title=\"One-shot fixture\", capabilities={\"trigger\"}} end\n"
             "function trigger() local f=io.open(\"%@\",\"a\"); f:write(\"T\"); f:close() end\n", triggerMarker]);
        catalog = request(service, @"installExtension", @{@"url": [NSURL fileURLWithPath:triggerSource].absoluteString}, &error);
        NSDictionary *trigger = find(catalog, @"One-shot fixture");
        require(trigger != nil && [trigger[@"triggerOnly"] boolValue] && [trigger[@"available"] boolValue], @"installed trigger-only descriptor is discoverable");
        require(![NSFileManager.defaultManager fileExistsAtPath:triggerMarker], @"installing a trigger-only extension does not run it");
        require([catalog[@"supportsActivation"] isEqual:@YES], @"trigger-only discovery advertises execution");
        for (NSString *action in @[@"activate", @"trigger"])
            require(request(service, action, @{@"id": trigger[@"id"]}, &error) != nil && error == nil, @"an on-demand extension runs on request");
        require([waitForText(triggerMarker, @"TT") isEqual:@"TT"], @"each request runs trigger() exactly once");
        require(request(service, @"removeExtension", @{@"id": trigger[@"id"]}, &error) != nil && error == nil, @"trigger-only user extension is removable");

        /* The published catalog (what the Extensions submenus read) follows a script's own
         * changes: its menu appears once activate() has run, and a menu the script changes on
         * its own (here when the current media changes) reaches the snapshot without any
         * further request. */
        NSString *menuSource = [root stringByAppendingPathComponent:@"incoming/Menu.lua"];
        writeFile(menuSource,
            @"local entries, inputs = {[1]=\"First\"}, 0\n"
             "function descriptor() return {title=\"Menu fixture\", capabilities={\"menu\", \"input-listener\"}} end\n"
             "function activate() end\n"
             "function deactivate() end\n"
             "function menu() return entries end\n"
             "function trigger_menu(id) end\n"
             /* Activation reports the (empty) current input once; the second report is the media change. */
             "function input_changed() inputs = inputs + 1; if inputs > 1 then entries = {[1]=\"First\", [2]=\"Second\"} end end\n");
        catalog = request(service, @"installExtension", @{@"url": [NSURL fileURLWithPath:menuSource].absoluteString}, &error);
        NSString *menuID = find(catalog, @"Menu fixture")[@"id"];
        require(menuID != nil && [find(catalog, @"Menu fixture")[@"hasMenu"] boolValue], @"installed menu extension is discoverable");
        NSArray *(^publishedMenu)(void) = ^NSArray *{ return [service snapshotForService:@"extensions"][@"menus"][menuID]; };
        NSArray *(^waitForMenu)(NSUInteger) = ^NSArray *(NSUInteger count) {
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
            while ([publishedMenu() count] != count && deadline.timeIntervalSinceNow > 0)
                [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
            return publishedMenu();
        };
        require(request(service, @"activate", @{@"id": menuID}, &error) != nil && error == nil, @"menu extension activates");
        NSArray *menu = waitForMenu(1);
        require(menu.count == 1 && [menu[0][@"title"] isEqual:@"First"], [NSString stringWithFormat:@"activated extension's menu is published: %@", menu]);
        input_item_t *media = input_item_New("file:///nonexistent/mxr-extension-menu.wav", "Menu fixture media");
        require(media != NULL, @"fixture media item");
        vlc_playlist_Lock(playlist);
        require(vlc_playlist_AppendOne(playlist, media) == VLC_SUCCESS && vlc_playlist_PlayAt(playlist, 0) == VLC_SUCCESS, @"current media changes");
        vlc_playlist_Unlock(playlist);
        input_item_Release(media);
        menu = waitForMenu(2);
        require(menu.count == 2 && [menu[1][@"title"] isEqual:@"Second"], [NSString stringWithFormat:@"a menu the script changed is republished: %@", menu]);
        require(request(service, @"deactivate", @{@"id": menuID}, &error) != nil && error == nil, @"menu extension deactivates");
        require(waitForMenu(0).count == 0, @"a deactivated extension publishes no menu");
        require(request(service, @"removeExtension", @{@"id": menuID}, &error) != nil && error == nil, @"menu extension is removable");

        /* A script command that runs for seconds (a VLsub search) holds the extension busy, and
         * reading its menu waits for it. Other media services must still answer meanwhile. */
        NSString *busySource = [root stringByAppendingPathComponent:@"incoming/Busy.lua"];
        writeFile(busySource,
            @"function descriptor() return {title=\"Busy fixture\", capabilities={\"menu\"}} end\n"
             "function activate() end\n"
             "function deactivate() end\n"
             "function menu() return {[1]=\"Work\"} end\n"
             "function trigger_menu(id) local t = os.clock(); while os.clock() - t < 3 do end end\n");
        catalog = request(service, @"installExtension", @{@"url": [NSURL fileURLWithPath:busySource].absoluteString}, &error);
        NSString *busyID = find(catalog, @"Busy fixture")[@"id"];
        require(busyID != nil, @"installed busy extension is discoverable");
        require(request(service, @"activate", @{@"id": busyID}, &error) != nil && error == nil, @"busy extension activates");
        NSDate *activeDeadline = [NSDate dateWithTimeIntervalSinceNow:5];
        while (![find([service snapshotForService:@"extensions"], @"Busy fixture")[@"active"] boolValue] && activeDeadline.timeIntervalSinceNow > 0)
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
        require([find([service snapshotForService:@"extensions"], @"Busy fixture")[@"active"] boolValue], @"busy extension finished activating");
        __block BOOL busyDone = NO;
        [service request:@"triggerMenu" service:@"extensions" arguments:@{@"id": busyID, @"menuID": @1} completion:^(NSDictionary *value, NSError *requestError) { busyDone = YES; }];
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.3]];
        /* Renderer discovery is answered by the media-services queue (here: no renderer module). */
        __block BOOL discovered = NO;
        NSDate *asked = [NSDate date];
        [service request:@"discover" service:@"renderers" arguments:@{} completion:^(NSDictionary *value, NSError *requestError) { discovered = YES; }];
        while (!discovered && -asked.timeIntervalSinceNow < 10) [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        NSTimeInterval answered = -asked.timeIntervalSinceNow;
        require(!busyDone, @"the busy script is still running when the other service answers");
        require(answered < 1, [NSString stringWithFormat:@"a busy extension does not hold up other media services (%.2f s)", answered]);
        NSDate *busyDeadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (!busyDone && busyDeadline.timeIntervalSinceNow > 0) [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
        require(busyDone, @"the busy menu command completes");
        require(request(service, @"deactivate", @{@"id": busyID}, &error) != nil && error == nil, @"busy extension deactivates");
        require(request(service, @"removeExtension", @{@"id": busyID}, &error) != nil && error == nil, @"busy extension is removable");

        [service shutdown];
        require(request(service, @"installExtension", @{@"url": [NSURL fileURLWithPath:source].absoluteString}, &error) == nil && error.code == ECANCELED,
                @"closed service refuses file mutation and completes exactly once");
        __block BOOL stopped = NO;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [service finishShutdown];
            vlc_object_delete(intf);
            libvlc_InternalCleanup(vlc);
            libvlc_InternalDestroy(vlc);
            dispatch_async(dispatch_get_main_queue(), ^{ stopped = YES; });
        });
        while (!stopped) [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        require([NSFileManager.defaultManager removeItemAtPath:root error:nil], @"only isolated test root cleaned up");
        NSLog(@"PASS: real Lua install, no overwrite, invalid rollback, stock/path/symlink refusal, activation/deactivation, on-demand runs, removal, queued installs, live extension menus and exactly-once completions");
    }
    return 0;
}
