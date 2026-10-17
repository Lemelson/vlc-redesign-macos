/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later.
 * Configured module-bank contract dump, without an interface or playback. */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#import <Foundation/Foundation.h>
#include <vlc_common.h>
#include <vlc_configuration.h>
#include <vlc_modules.h>
#include <vlc_plugin.h>
extern libvlc_int_t *libvlc_InternalCreate(void);
extern int libvlc_InternalInit(libvlc_int_t *, int, const char *[]);
extern void libvlc_InternalCleanup(libvlc_int_t *);
extern void libvlc_InternalDestroy(libvlc_int_t *);

static NSString *String(const char *value) { return value ? [NSString stringWithUTF8String:value] : @""; }
int main(void) {
    @autoreleasepool {
        libvlc_int_t *core = libvlc_InternalCreate();
        const char *args[] = {"mxr-dumpconfig", "--ignore-config", "--no-media-library", "--no-auto-preparse", "--no-metadata-network-access", "--no-plugins-cache"};
        if (!core || libvlc_InternalInit(core, 6, args) != VLC_SUCCESS) return 1;
        NSMutableArray *options = [NSMutableArray array];
        size_t count; module_t **modules = module_list_get(&count);
        for (size_t i = 0; i < count; ++i) {
            unsigned length; module_config_t *configs = module_config_get(modules[i], &length);
            for (unsigned j = 0; j < length; ++j) {
                module_config_t *c = &configs[j];
                if (!CONFIG_ITEM(c->i_type) || !c->psz_name) continue;
                NSString *name = String(c->psz_name);
                // App registrations are checked against their consumers by SettingsCatalogLintTests.
                if ([name hasPrefix:@"macosx-redesign-"]) continue;
                BOOL integer = IsConfigIntegerType(c->i_type), floating = IsConfigFloatType(c->i_type);
                id value = integer ? (id)@(c->orig.i) : floating ? (id)@(c->orig.f) : String(c->orig.psz);
                NSMutableArray *choices = [NSMutableArray array];
                for (unsigned k = 0; k < c->list_count; ++k)
                    [choices addObject:integer ? (id)@(c->list.i[k]) : String(c->list.psz[k])];
                NSMutableDictionary *option = [@{@"name": name, @"module": String(module_get_object(modules[i])),
                    @"type": @(c->i_type), @"default": value, @"choices": choices} mutableCopy];
                if (integer) { option[@"min"] = @(c->min.i); option[@"max"] = @(c->max.i); }
                if (floating) { option[@"min"] = @(c->min.f); option[@"max"] = @(c->max.f); }
                [options addObject:option];
            }
            module_config_free(configs);
        }
        module_list_free(modules);
        [options sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES],
                                       [NSSortDescriptor sortDescriptorWithKey:@"module" ascending:YES]]];
        NSError *error = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:options options:NSJSONWritingSortedKeys error:&error];
        if (data) fwrite(data.bytes, 1, data.length, stdout);
        else fprintf(stderr, "schema serialization failed: %s\n", error.localizedDescription.UTF8String);
        libvlc_InternalCleanup(core);
        libvlc_InternalDestroy(core);
        return data ? 0 : 1;
    }
}
