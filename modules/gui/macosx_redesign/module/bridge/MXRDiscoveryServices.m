/*****************************************************************************
 * MXRDiscoveryServices.m: installed VLC discovery modules and local browsing
 *****************************************************************************
 * Copyright (C) 2026 VLC Redesign contributors
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#import <AppKit/AppKit.h>
#import "MXRBridgeKeys.h"
#include <fcntl.h>
#include <unistd.h>
#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_input_item.h>
#include <vlc_media_source.h>
#include <vlc_preparser.h>
#import "MXRDiscoveryServices.h"

static NSString * const MXRFoldersSource = @"mxr.local.folders";
static NSString * const MXRVolumesSource = @"mxr.local.volumes";
static NSString * const MXRRootKey = @"$root";
typedef void (^MXRDiscoveryCompletion)(NSDictionary * _Nullable, NSError * _Nullable);

static NSError *MXRDiscoveryError(NSInteger code, NSString *message)
{
    return [NSError errorWithDomain:@"MXRDiscoveryServices" code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSArray<NSString *> *MXRCategories(void)
{
    return @[@"devices", @"localNetwork", @"internet", @"myComputer"];
}

static NSString *MXRCategory(enum services_discovery_category_e category)
{
    switch (category) {
        case SD_CAT_DEVICES: return @"devices";
        case SD_CAT_LAN: return @"localNetwork";
        case SD_CAT_INTERNET: return @"internet";
        case SD_CAT_MYCOMPUTER: return @"myComputer";
        default: return nil;
    }
}

static NSDictionary *MXRSourceInfo(NSString *identifier, NSString *title, NSString *category)
{
    return @{ @"id": identifier, @"title": title, @"name": title, @"category": category };
}

static NSDictionary *MXRNodeInfo(NSString *identifier, NSString *title, NSString *mrl,
                                 BOOL container, NSNumber *childCount)
{
    NSMutableDictionary *result = [@{ @"id": identifier, @"title": title,
        @"mrl": mrl, @"url": mrl, @"isContainer": @(container), @"isDirectory": @(container) } mutableCopy];
    if (childCount) result[@"childCount"] = childCount;
    return [result copy];
}

static NSDictionary *MXRChildrenReply(NSArray *children)
{
    return @{ @"children": children, @"nodes": children };
}

/// A UUID identifies a held input item, never a raw engine address in Swift.
@interface MXRDiscoveryItem : NSObject
@property (nonatomic, readonly) input_item_t *item;
@property (nonatomic, readonly) NSString *identifier;
- (instancetype)initWithItem:(input_item_t *)item;
@end

@implementation MXRDiscoveryItem
- (instancetype)initWithItem:(input_item_t *)item
{
    if ((self = [super init])) {
        _item = input_item_Hold(item);
        _identifier = NSUUID.UUID.UUIDString;
    }
    return self;
}
- (void)dealloc { input_item_Release(_item); }
@end

@class MXRDiscoveryTree;
@interface MXRDiscoveryServices ()
- (void)receivedTreePacket:(NSDictionary *)packet from:(MXRDiscoveryTree *)context;
@end

/// Kept alive until RemoveListener returns, and through each queued callback.
/// All node registries and revisions are accessed with the VLC tree lock held.
@interface MXRDiscoveryTree : NSObject
@property (nonatomic, weak) MXRDiscoveryServices *owner;
@property (nonatomic) vlc_media_source_t *source;
@property (nonatomic) vlc_media_tree_listener_id *listener;
@property (nonatomic, copy) NSString *sourceID;
@property (nonatomic, copy) NSString *category;
@property (nonatomic) uint64_t revision;
@property (nonatomic) uint64_t deliveredRevision; // worker only
@property (nonatomic, strong) NSDictionary<NSString *, MXRDiscoveryItem *> *itemsByID;
@property (nonatomic, strong) NSDictionary<NSValue *, MXRDiscoveryItem *> *itemsByPointer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<MXRDiscoveryCompletion> *> *pending;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *requests;
@property (nonatomic, strong) NSMutableSet<NSString *> *parsed;
- (NSDictionary *)captureLocked:(input_item_node_t *)changed status:(NSNumber * _Nullable)status;
@end

@implementation MXRDiscoveryTree
- (instancetype)init
{
    if ((self = [super init])) {
        _itemsByID = @{}; _itemsByPointer = @{};
        _pending = [NSMutableDictionary dictionary];
        _requests = [NSMutableDictionary dictionary];
        _parsed = [NSMutableSet set];
    }
    return self;
}

- (NSDictionary *)captureLocked:(input_item_node_t *)changed status:(NSNumber *)status
{
    NSMutableDictionary *byID = [NSMutableDictionary dictionary];
    NSMutableDictionary *byPointer = [NSMutableDictionary dictionary];
    NSMutableDictionary *children = [NSMutableDictionary dictionary];
    NSMutableArray<NSValue *> *stack = [NSMutableArray arrayWithObject:[NSValue valueWithPointer:&_source->tree->root]];
    NSMutableArray<NSValue *> *nodes = [NSMutableArray array];
    while (stack.count) {
        input_item_node_t *node = stack.lastObject.pointerValue;
        [stack removeLastObject];
        [nodes addObject:[NSValue valueWithPointer:node]];
        if (node->p_item) {
            NSValue *pointer = [NSValue valueWithPointer:node->p_item];
            MXRDiscoveryItem *item = _itemsByPointer[pointer];
            if (!item) item = [[MXRDiscoveryItem alloc] initWithItem:node->p_item];
            byPointer[pointer] = item;
            byID[item.identifier] = item;
        }
        for (int i = 0; i < node->i_children; ++i)
            [stack addObject:[NSValue valueWithPointer:node->pp_children[i]]];
    }
    NSString *changedID = changed->p_item ? [byPointer[[NSValue valueWithPointer:changed->p_item]] identifier] : nil;
    for (NSValue *value in nodes) {
        input_item_node_t *node = value.pointerValue;
        NSString *nodeID = node->p_item ? [byPointer[[NSValue valueWithPointer:node->p_item]] identifier] : MXRRootKey;
        if (!nodeID) continue;
        NSMutableArray *rows = [NSMutableArray arrayWithCapacity:node->i_children];
        for (int i = 0; i < node->i_children; ++i) {
            input_item_node_t *child = node->pp_children[i];
            if (!child->p_item) continue;
            MXRDiscoveryItem *reference = byPointer[[NSValue valueWithPointer:child->p_item]];
            char *name = input_item_GetName(child->p_item);
            char *uri = input_item_GetURI(child->p_item);
            NSString *mrl = uri ? [NSString stringWithUTF8String:uri] : @"";
            NSString *title = name ? [NSString stringWithUTF8String:name] : nil;
            free(name); free(uri);
            bool network;
            enum input_item_type_e type = input_item_GetType(child->p_item, &network);
            BOOL container = child->i_children > 0 || type == ITEM_TYPE_DIRECTORY ||
                type == ITEM_TYPE_NODE || type == ITEM_TYPE_PLAYLIST || type == ITEM_TYPE_DISC;
            [rows addObject:MXRNodeInfo(reference.identifier, title ?: mrl ?: @"", mrl ?: @"",
                                        container, child->i_children > 0 ? @(child->i_children) : nil)];
        }
        children[nodeID] = [rows copy];
    }
    _itemsByPointer = [byPointer copy]; _itemsByID = [byID copy];
    NSMutableDictionary *packet = [@{ @"revision": @(++_revision), @"children": [children copy],
        @"event": @{ @"type": @"childrenChanged", @"sourceID": _sourceID,
                     @"nodeID": changedID ?: NSNull.null } } mutableCopy];
    if (status) packet[@"status"] = status;
    return [packet copy];
}
@end

static void MXRDiscoveryChanged(vlc_media_tree_t *tree, input_item_node_t *node, void *userdata)
{
    (void)tree;
    @autoreleasepool {
        MXRDiscoveryTree *context = (__bridge MXRDiscoveryTree *)userdata;
        [context.owner receivedTreePacket:[context captureLocked:node status:nil] from:context];
    }
}
static void MXRDiscoveryChildren(vlc_media_tree_t *tree, input_item_node_t *node,
                                 input_item_node_t *const children[], size_t count, void *userdata)
{
    (void)children; (void)count;
    MXRDiscoveryChanged(tree, node, userdata);
}
static void MXRDiscoveryParsed(vlc_media_tree_t *tree, input_item_node_t *node, int status, void *userdata)
{
    (void)tree;
    @autoreleasepool {
        MXRDiscoveryTree *context = (__bridge MXRDiscoveryTree *)userdata;
        [context.owner receivedTreePacket:[context captureLocked:node status:@(status)] from:context];
    }
}
static const struct vlc_media_tree_callbacks MXRDiscoveryCallbacks = {
    .on_children_reset = MXRDiscoveryChanged,
    .on_children_added = MXRDiscoveryChildren,
    .on_children_removed = MXRDiscoveryChildren,
    .on_preparse_end = MXRDiscoveryParsed,
};

@implementation MXRDiscoveryServices
{
    dispatch_queue_t _worker;
    NSLock *_stateLock;
    BOOL _stopped;
    BOOL _finished;
    NSMutableSet<NSString *> *_startedCategories;
    vlc_preparser_t *_parser;
    vlc_media_source_provider_t *_provider;
    NSMutableDictionary<NSString *, MXRDiscoveryTree *> *_trees;
    NSMutableDictionary<NSString *, NSMutableArray *> *_categories;
    NSMutableDictionary<NSString *, NSDictionary *> *_cachedChildren;
    NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSURL *> *> *_localURLs;
    NSMutableDictionary<NSString *, dispatch_source_t> *_watchers;
    NSMutableArray<NSString *> *_watcherOrder;
    NSArray *_volumeObservers;
    NSDictionary *_snapshot;
    NSDictionary *_capabilities;
}

- (instancetype)initWithInterface:(intf_thread_t *)intf
{
    NSAssert(NSThread.isMainThread, @"Discovery is owned by the main-thread bridge");
    if ((self = [super init])) {
        _worker = dispatch_queue_create("org.vlc.macosx-redesign.discovery", DISPATCH_QUEUE_SERIAL);
        _stateLock = [[NSLock alloc] init];
        _trees = [NSMutableDictionary dictionary];
        _startedCategories = [NSMutableSet set];
        _categories = [NSMutableDictionary dictionary];
        for (NSString *category in MXRCategories()) _categories[category] = [NSMutableArray array];
        _cachedChildren = [NSMutableDictionary dictionary];
        _localURLs = [NSMutableDictionary dictionary];
        _watchers = [NSMutableDictionary dictionary];
        _watcherOrder = [NSMutableArray array];
        NSDictionary *empty = @{ @"devices": @[], @"localNetwork": @[], @"internet": @[], @"myComputer": @[] };
        _snapshot = @{ @"sources": empty, @"categories": empty, @"children": @{} };
        _capabilities = @{ @"hasMediaSources": @YES, @"hasLocalBrowsing": @YES, @"hasNetworkDiscovery": @NO };
        __weak typeof(self) weakSelf = self;
        NSMutableArray *observers = [NSMutableArray array];
        for (NSString *name in @[NSWorkspaceDidMountNotification, NSWorkspaceDidUnmountNotification]) {
            id observer = [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:name object:nil queue:nil
                usingBlock:^(NSNotification *notification) {
                    (void)notification;
                    MXRDiscoveryServices *owner = weakSelf;
                    if (owner) dispatch_async(owner->_worker, ^{ if (![owner isStopped]) [owner publishLocalRoot:MXRVolumesSource]; });
                }];
            [observers addObject:observer];
        }
        _volumeObservers = [observers copy];
        dispatch_async(_worker, ^{
            @autoreleasepool {
                if ([self isStopped]) return;
                self->_provider = vlc_media_source_provider_Get(vlc_object_instance(intf));
                const struct vlc_preparser_cfg config = {
                    .types = VLC_PREPARSER_TYPE_PARSE, .max_parser_threads = 1,
                    .timeout = VLC_TICK_FROM_SEC(20), .external_process = false,
                };
                self->_parser = vlc_preparser_New(VLC_OBJECT(intf), &config);
                [self loadSources];
            }
        });
    }
    return self;
}

- (BOOL)isStopped
{
    [_stateLock lock]; BOOL result = _stopped; [_stateLock unlock]; return result;
}

- (NSDictionary *)capabilities { return _capabilities; }
- (NSDictionary *)snapshotForService:(MXRBridgeService)service
{
    NSAssert(NSThread.isMainThread, @"Snapshots are main-thread caches");
    return [service isEqualToString:MXRBridgeServiceMediaSources] ? _snapshot : @{};
}

- (void)publishEvent:(NSDictionary *)event
{
    [self publishEvent:event notify:YES];
}

- (void)publishEvent:(NSDictionary *)event notify:(BOOL)notify
{
    NSMutableDictionary *categories = [NSMutableDictionary dictionary];
    for (NSString *category in MXRCategories()) categories[category] = [_categories[category] copy];
    NSDictionary *snapshot = @{ @"sources": [categories copy], @"categories": [categories copy],
        @"children": [_cachedChildren copy], @"event": event };
    BOOL hasNetwork = [_categories[@"localNetwork"] count] || [_categories[@"internet"] count];
    NSDictionary *capabilities = @{ @"hasMediaSources": @YES, @"hasLocalBrowsing": @YES,
                                   @"hasNetworkDiscovery": @(hasNetwork) };
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self isStopped]) return;
        self->_snapshot = snapshot; self->_capabilities = capabilities;
        if (notify && self.serviceChanged) self.serviceChanged(MXRBridgeServiceMediaSources);
    });
}

- (void)loadSources
{
    [_categories[@"myComputer"] addObject:MXRSourceInfo(MXRFoldersSource, @"My Folders", @"myComputer")];
    [_categories[@"devices"] addObject:MXRSourceInfo(MXRVolumesSource, @"Mounted Volumes", @"devices")];
    [self publishLocalRoot:MXRFoldersSource];
    [self publishLocalRoot:MXRVolumesSource];
    [self publishEvent:@{ @"type": @"sourcesChanged", @"category": @"myComputer" }];
    [self publishEvent:@{ @"type": @"sourcesChanged", @"category": @"devices" }];
}

/* Worker only. Listing/opening SD modules is deferred until its browser is opened. */
- (void)discoverCategory:(NSString *)requestedCategory
{
    if ([_startedCategories containsObject:requestedCategory] || [self isStopped]) return;
    [_startedCategories addObject:requestedCategory];
    if (_provider) {
        vlc_media_source_meta_list_t *list = vlc_media_source_provider_List(_provider, 0);
        if (list) {
            size_t count = vlc_media_source_meta_list_Count(list);
            for (size_t i = 0; i < count && ![self isStopped]; ++i) {
                const struct vlc_media_source_meta *meta = vlc_media_source_meta_list_Get(list, i);
                NSString *category = MXRCategory(meta->category);
                NSString *identifier = meta->name ? [NSString stringWithUTF8String:meta->name] : nil;
                if (![category isEqualToString:requestedCategory] || !identifier.length) continue;
                vlc_media_source_t *source = vlc_media_source_provider_GetMediaSource(_provider, meta->name);
                if (!source) continue; // Only list modules which actually opened.
                MXRDiscoveryTree *context = [[MXRDiscoveryTree alloc] init];
                context.owner = self; context.source = source;
                context.sourceID = identifier; context.category = category;
                context.listener = vlc_media_tree_AddListener(source->tree, &MXRDiscoveryCallbacks,
                                                              (__bridge void *)context, false);
                if (!context.listener) { vlc_media_source_Release(source); continue; }
                _trees[identifier] = context;
                NSString *title = meta->longname ? [NSString stringWithUTF8String:meta->longname] : identifier;
                [_categories[category] addObject:MXRSourceInfo(identifier, title ?: identifier, category)];
                vlc_media_tree_Lock(source->tree);
                NSDictionary *packet = [context captureLocked:&source->tree->root status:nil];
                vlc_media_tree_Unlock(source->tree);
                [self applyTreePacket:packet from:context];
            }
            vlc_media_source_meta_list_Delete(list);
        }
    }
    for (NSString *category in MXRCategories())
        [self publishEvent:@{ @"type": @"sourcesChanged", @"category": category }];
}

- (void)receivedTreePacket:(NSDictionary *)packet from:(MXRDiscoveryTree *)context
{
    // Callback holds the tree lock: capture immutable values there, then release
    // it before touching queue state, preparsing, or delivering UI events.
    dispatch_async(_worker, ^{ @autoreleasepool { if (![self isStopped]) [self applyTreePacket:packet from:context]; } });
}

- (void)applyTreePacket:(NSDictionary *)packet from:(MXRDiscoveryTree *)context
{
    [self applyTreePacket:packet from:context notify:YES];
}

- (void)applyTreePacket:(NSDictionary *)packet from:(MXRDiscoveryTree *)context notify:(BOOL)notify
{
    uint64_t revision = [packet[@"revision"] unsignedLongLongValue];
    if (revision > context.deliveredRevision) {
        context.deliveredRevision = revision;
        _cachedChildren[context.sourceID] = packet[@"children"];
    }
    // Reads can already have captured a newer revision. A real callback still
    // invalidates its affected node, while keeping the newer cached data.
    [self publishEvent:packet[@"event"] notify:notify];
    NSNumber *status = packet[@"status"];
    NSString *nodeID = packet[@"event"][@"nodeID"];
    if (status && [nodeID isKindOfClass:NSString.class]) {
        NSValue *request = context.requests[nodeID];
        if (request) {
            vlc_preparser_req_Release(request.pointerValue);
            [context.requests removeObjectForKey:nodeID];
        }
        if (status.intValue == VLC_SUCCESS) [context.parsed addObject:nodeID];
        NSArray *pending = [context.pending[nodeID] copy];
        [context.pending removeObjectForKey:nodeID];
        NSError *error = status.intValue == VLC_SUCCESS ? nil :
            MXRDiscoveryError(status.intValue, @"VLC could not browse this media source.");
        NSArray *children = _cachedChildren[context.sourceID][nodeID] ?: @[];
        for (MXRDiscoveryCompletion completion in pending)
            [self complete:completion result:error ? nil : MXRChildrenReply(children) error:error];
    }
    // A discovery module may remove a node while it is being preparsed.
    // Such nodes cannot receive on_preparse_end, so resolve their waiters here.
    vlc_media_tree_Lock(context.source->tree);
    NSSet *currentIDs = [NSSet setWithArray:context.itemsByID.allKeys];
    vlc_media_tree_Unlock(context.source->tree);
    [context.parsed intersectSet:currentIDs];
    for (NSString *pendingID in [context.pending.allKeys copy]) {
        if ([currentIDs containsObject:pendingID]) continue;
        for (MXRDiscoveryCompletion completion in context.pending[pendingID])
            [self complete:completion result:nil error:MXRDiscoveryError(ENOENT, @"This source item was removed.")];
        [context.pending removeObjectForKey:pendingID];
        NSValue *request = context.requests[pendingID];
        if (request) {
            vlc_preparser_Cancel(_parser, request.pointerValue);
            vlc_preparser_req_Release(request.pointerValue);
            [context.requests removeObjectForKey:pendingID];
        }
    }
}

- (void)complete:(MXRDiscoveryCompletion)completion result:(NSDictionary *)result error:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        completion([self isStopped] ? nil : result,
            [self isStopped] ? MXRDiscoveryError(NSUserCancelledError, @"Discovery has stopped.") : error);
    });
}

- (BOOL)performCommand:(MXRBridgeCommand)command service:(MXRBridgeService)service
             arguments:(NSDictionary *)arguments error:(NSError **)error
{
    NSString *category = arguments[@"category"];
    if ([command isEqualToString:MXRBridgeCommandDiscover] && [service isEqualToString:MXRBridgeServiceMediaSources]
        && [category isKindOfClass:NSString.class] && [MXRCategories() containsObject:category]) {
        dispatch_async(_worker, ^{ @autoreleasepool { [self discoverCategory:category]; } });
        return YES;
    }
    if (error) *error = MXRDiscoveryError(ENOTSUP, @"Unknown media-source command.");
    return NO;
}

- (void)request:(MXRBridgeRequest)request service:(MXRBridgeService)service arguments:(NSDictionary *)arguments
      completion:(MXRDiscoveryCompletion)completion
{
    NSAssert(NSThread.isMainThread, @"Discovery requests originate on main");
    BOOL refresh = [request isEqualToString:MXRBridgeRequestRefreshChildren];
    if ((!refresh && ![request isEqualToString:MXRBridgeRequestChildren]) || ![service isEqualToString:MXRBridgeServiceMediaSources]) {
        completion(nil, MXRDiscoveryError(ENOTSUP, @"Unknown media-source request.")); return;
    }
    NSString *sourceID = arguments[@"sourceID"];
    id nodeValue = arguments[@"nodeID"];
    NSString *nodeID = nodeValue == NSNull.null ? nil : nodeValue;
    if (![sourceID isKindOfClass:NSString.class] || (nodeID && ![nodeID isKindOfClass:NSString.class])) {
        completion(nil, MXRDiscoveryError(EINVAL, @"A source ID and optional node ID are required.")); return;
    }
    dispatch_async(_worker, ^{
        @autoreleasepool {
            if ([self isStopped]) { [self complete:completion result:nil error:nil]; return; }
            if ([sourceID isEqualToString:MXRFoldersSource] || [sourceID isEqualToString:MXRVolumesSource]) {
                NSError *error;
                NSArray *children = [self localChildrenForSource:sourceID nodeID:nodeID error:&error];
                if (children) {
                    NSMutableDictionary *cache = [self->_cachedChildren[sourceID] mutableCopy] ?: [NSMutableDictionary dictionary];
                    cache[nodeID ?: MXRRootKey] = children;
                    self->_cachedChildren[sourceID] = [cache copy];
                    [self publishEvent:@{ @"type": @"childrenChanged", @"sourceID": sourceID, @"nodeID": nodeID ?: NSNull.null } notify:NO];
                }
                [self complete:completion result:children ? MXRChildrenReply(children) : nil error:error]; return;
            }
            MXRDiscoveryTree *context = self->_trees[sourceID];
            if (!context) { [self complete:completion result:nil error:MXRDiscoveryError(ENOENT, @"This discovery source is unavailable.")]; return; }
            vlc_media_tree_t *tree = context.source->tree;
            vlc_media_tree_Lock(tree);
            input_item_node_t *node = &tree->root;
            MXRDiscoveryItem *reference = nodeID ? context.itemsByID[nodeID] : nil;
            BOOL found = !nodeID || (reference && vlc_media_tree_Find(tree, reference.item, &node, NULL));
            NSDictionary *packet = found ? [context captureLocked:node status:nil] : nil;
            input_item_t *item = found && node->p_item ? input_item_Hold(node->p_item) : NULL;
            vlc_media_tree_Unlock(tree);
            if (!found) { [self complete:completion result:nil error:MXRDiscoveryError(ENOENT, @"This source item no longer exists.")]; return; }
            [self applyTreePacket:packet from:context notify:NO];
            NSArray *children = packet[@"children"][nodeID ?: MXRRootKey] ?: @[];
            bool network;
            enum input_item_type_e type = item ? input_item_GetType(item, &network) : ITEM_TYPE_NODE;
            // Explicit refresh reparses this held item. VLC replaces its child
            // subtree while retaining the container; ordinary reads stay cached.
            BOOL parse = item && (refresh || ![context.parsed containsObject:nodeID]) &&
                (type == ITEM_TYPE_DIRECTORY || type == ITEM_TYPE_NODE || type == ITEM_TYPE_PLAYLIST || type == ITEM_TYPE_DISC);
            if (!parse) {
                if (item) input_item_Release(item);
                [self complete:completion result:MXRChildrenReply(children) error:nil]; return;
            }
            if (!self->_parser) {
                input_item_Release(item);
                [self complete:completion result:nil error:MXRDiscoveryError(ENOTSUP, @"VLC's source browser could not be initialized.")]; return;
            }
            NSMutableArray *pending = context.pending[nodeID];
            if (pending) { [pending addObject:[completion copy]]; input_item_Release(item); return; }
            context.pending[nodeID] = [NSMutableArray arrayWithObject:[completion copy]];
            vlc_preparser_req *handle = vlc_media_tree_Preparse(tree, self->_parser, item);
            input_item_Release(item);
            if (handle) context.requests[nodeID] = [NSValue valueWithPointer:handle];
            else {
                [context.pending removeObjectForKey:nodeID];
                [self complete:completion result:nil error:MXRDiscoveryError(EIO, @"VLC could not start browsing this source item.")];
            }
        }
    });
}

- (NSArray<NSURL *> *)localRootsForSource:(NSString *)sourceID
{
    NSFileManager *manager = NSFileManager.defaultManager;
    if ([sourceID isEqualToString:MXRVolumesSource])
        return [manager mountedVolumeURLsIncludingResourceValuesForKeys:@[NSURLVolumeLocalizedNameKey]
            options:NSVolumeEnumerationSkipHiddenVolumes] ?: @[];
    NSMutableArray *urls = [NSMutableArray arrayWithObject:[NSURL fileURLWithPath:NSHomeDirectory() isDirectory:YES]];
    for (NSNumber *directory in @[@(NSDesktopDirectory), @(NSDocumentDirectory), @(NSDownloadsDirectory),
                                  @(NSMoviesDirectory), @(NSMusicDirectory), @(NSPicturesDirectory)]) {
        NSURL *url = [manager URLsForDirectory:directory.unsignedIntegerValue inDomains:NSUserDomainMask].firstObject;
        BOOL isDirectory;
        if (url && ![urls containsObject:url] && [manager fileExistsAtPath:url.path isDirectory:&isDirectory] && isDirectory)
            [urls addObject:url];
    }
    return [urls copy];
}

- (NSArray *)localChildrenForSource:(NSString *)sourceID nodeID:(NSString *)nodeID error:(NSError **)error
{
    if (error) *error = nil;
    NSMutableDictionary *urlsByID = _localURLs[sourceID];
    if (!urlsByID) { urlsByID = [NSMutableDictionary dictionary]; _localURLs[sourceID] = urlsByID; }
    NSArray<NSURL *> *urls;
    if (nodeID) {
        NSURL *directory = urlsByID[nodeID];
        if (!directory) { if (error) *error = MXRDiscoveryError(ENOENT, @"Unknown local folder."); return nil; }
        urls = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory
            includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLLocalizedNameKey]
            options:NSDirectoryEnumerationSkipsHiddenFiles error:error];
        if (!urls) return nil;
        [self watchURL:directory sourceID:sourceID nodeID:nodeID];
        urls = [urls sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
            NSNumber *aDirectory; NSNumber *bDirectory;
            [a getResourceValue:&aDirectory forKey:NSURLIsDirectoryKey error:nil];
            [b getResourceValue:&bDirectory forKey:NSURLIsDirectoryKey error:nil];
            if (aDirectory.boolValue != bDirectory.boolValue) return aDirectory.boolValue ? NSOrderedAscending : NSOrderedDescending;
            return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent];
        }];
    } else urls = [self localRootsForSource:sourceID];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSURL *url in urls) {
        NSNumber *directory; NSString *name;
        [url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
        if (!directory.boolValue && !input_item_Playable(url.absoluteString.UTF8String)) continue;
        [url getResourceValue:&name forKey:NSURLLocalizedNameKey error:nil];
        if (!nodeID && [sourceID isEqualToString:MXRVolumesSource])
            [url getResourceValue:&name forKey:NSURLVolumeLocalizedNameKey error:nil];
        NSString *identifier = url.absoluteString;
        if (directory.boolValue) urlsByID[identifier] = url;
        [rows addObject:MXRNodeInfo(identifier, name ?: url.lastPathComponent, url.absoluteString, directory.boolValue, nil)];
    }
    return [rows copy];
}

- (void)publishLocalRoot:(NSString *)sourceID
{
    NSError *error;
    NSArray *roots = [self localChildrenForSource:sourceID nodeID:nil error:&error];
    if (!roots) return;
    NSMutableDictionary *cache = [_cachedChildren[sourceID] mutableCopy] ?: [NSMutableDictionary dictionary];
    cache[MXRRootKey] = roots;
    _cachedChildren[sourceID] = [cache copy];
    [self publishEvent:@{ @"type": @"childrenChanged", @"sourceID": sourceID, @"nodeID": NSNull.null }];
}

- (void)watchURL:(NSURL *)url sourceID:(NSString *)sourceID nodeID:(NSString *)nodeID
{
    NSString *key = [NSString stringWithFormat:@"%@\n%@", sourceID, nodeID];
    if (_watchers[key]) {
        [_watcherOrder removeObject:key]; [_watcherOrder addObject:key]; return;
    }
    // Browsing an entire disk must not consume one open descriptor per folder
    // forever. Reads always refresh; recent folders receive live invalidation.
    if (_watcherOrder.count >= 64) {
        NSString *oldest = _watcherOrder.firstObject;
        dispatch_source_cancel(_watchers[oldest]);
        [_watchers removeObjectForKey:oldest]; [_watcherOrder removeObjectAtIndex:0];
    }
    int descriptor = open(url.fileSystemRepresentation, O_EVTONLY | O_CLOEXEC);
    if (descriptor < 0) return;
    dispatch_source_t watcher = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, descriptor,
        DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_REVOKE, _worker);
    if (!watcher) { close(descriptor); return; }
    __weak typeof(self) weakSelf = self;
    __weak dispatch_source_t weakWatcher = watcher;
    dispatch_source_set_cancel_handler(watcher, ^{ close(descriptor); });
    dispatch_source_set_event_handler(watcher, ^{
        @autoreleasepool {
            MXRDiscoveryServices *owner = weakSelf;
            dispatch_source_t currentWatcher = weakWatcher;
            if (!owner || !currentWatcher || [owner isStopped] || owner->_watchers[key] != currentWatcher) return;
            unsigned long flags = dispatch_source_get_data(currentWatcher);
            BOOL invalidated = flags & (DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_REVOKE);
            NSError *error;
            NSArray *children = invalidated ? nil : [owner localChildrenForSource:sourceID nodeID:nodeID error:&error];
            NSMutableDictionary *cache = [owner->_cachedChildren[sourceID] mutableCopy] ?: [NSMutableDictionary dictionary];
            cache[nodeID] = children ?: @[];
            owner->_cachedChildren[sourceID] = [cache copy];
            if (invalidated) {
                dispatch_source_cancel(currentWatcher);
                [owner->_watchers removeObjectForKey:key];
                [owner->_watcherOrder removeObject:key];
                [owner->_localURLs[sourceID] removeObjectForKey:nodeID];
            }
            [owner publishEvent:@{ @"type": @"childrenChanged", @"sourceID": sourceID, @"nodeID": nodeID }];
        }
    });
    _watchers[key] = watcher;
    [_watcherOrder addObject:key];
    dispatch_resume(watcher);
}

- (void)shutdown
{
    NSAssert(NSThread.isMainThread, @"Shutdown begins on main");
    [_stateLock lock]; _stopped = YES; [_stateLock unlock];
    self.serviceChanged = nil;
    for (id observer in _volumeObservers)
        [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:observer];
    _volumeObservers = nil;
}

- (void)finishShutdown
{
    NSAssert(!NSThread.isMainThread, @"The worker must be joined off-main");
    dispatch_sync(_worker, ^{
        if (self->_finished) return;
        self->_finished = YES;
        // Detach listeners first. RemoveListener waits for any callback holding
        // the tree lock, keeping its Objective-C context valid throughout.
        for (MXRDiscoveryTree *context in self->_trees.allValues) {
            vlc_media_tree_RemoveListener(context.source->tree, context.listener);
            context.listener = NULL; context.owner = nil;
        }
        if (self->_parser) {
            vlc_preparser_Cancel(self->_parser, NULL);
            vlc_preparser_Delete(self->_parser); self->_parser = NULL;
        }
        for (MXRDiscoveryTree *context in self->_trees.allValues) {
            for (NSValue *request in context.requests.allValues) vlc_preparser_req_Release(request.pointerValue);
            [context.requests removeAllObjects];
            for (NSArray *pending in context.pending.allValues)
                for (MXRDiscoveryCompletion completion in pending) [self complete:completion result:nil error:nil];
            [context.pending removeAllObjects];
            vlc_media_source_Release(context.source); context.source = NULL;
        }
        [self->_trees removeAllObjects]; self->_provider = NULL;
        for (dispatch_source_t watcher in self->_watchers.allValues) dispatch_source_cancel(watcher);
        [self->_watchers removeAllObjects]; [self->_watcherOrder removeAllObjects]; [self->_localURLs removeAllObjects];
    });
    // Drain vnode cancellation handlers so all descriptors have closed.
    dispatch_sync(_worker, ^{});
}
@end
