/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#import "MXRLibraryServices.h"
#import "MXRBridgeKeys.h"
#include <vlc_media_library.h>
#include <vlc_input_item.h>
#include <vlc_player.h>
#include <vlc_strings.h>
#include <vlc_hash.h>
#include <vlc_preparser.h>
#include <vlc_configuration.h>
#include <stdatomic.h>
#include <CommonCrypto/CommonDigest.h>

/*
 * The library service answers the interface's library contract on one serial
 * queue (every vlc_ml_* call runs there):
 *
 *   Videos  ▸ entry points holding video ▸ subfolders ▸ media   (folder tree, VIDEO_BREAKDOWN §08)
 *   Music   ▸ + Add · Songs · Albums · Artists · Genres          (§09)
 *     Songs ▸ entry points holding audio ▸ subfolders ▸ media
 *   Network ▸ + Add Network Stream · saved collections ▸ items   (§10, m3u expanded on save)
 *   Playlists ▸ + Create playlist · user playlists ▸ media       (§11)
 *   Home    ▸ Continue Watching · Listen Again · Frequently Visited Folders · … (non-empty only)
 *
 * The media library has no parent link on folders and no folder-by-MRL
 * lookup, so a folder index (every folder that directly holds media, plus
 * the entry points) is built from vlc_ml_list_folders and kept until a
 * folder, entry point or media add/remove event marks it stale.
 */

NSString *const MXRLibraryTrackURL=@"url";
NSString *const MXRLibraryTrackAudio=@"audio";
NSArray<NSDictionary *> *MXRLibraryExternalTracks(vlc_medialibrary_t *ml, const char *uri) {
    NSMutableArray<NSDictionary *> *tracks=[NSMutableArray array];
    vlc_ml_media_t *media=ml&&uri?vlc_ml_get_media_by_mrl(ml,uri):NULL;
    if(!media) return tracks;
    if(media->p_files) for(size_t i=0;i<media->p_files->i_nb_items;i++) {
        const vlc_ml_file_t *file=&media->p_files->p_items[i];
        BOOL audio=file->i_type==VLC_ML_FILE_TYPE_SOUNDTRACK;
        if((audio||file->i_type==VLC_ML_FILE_TYPE_SUBTITLE)&&file->psz_mrl)
            [tracks addObject:@{MXRLibraryTrackURL:[NSString stringWithUTF8String:file->psz_mrl]?:@"",MXRLibraryTrackAudio:@(audio)}];
    }
    vlc_ml_media_release(media);
    return tracks;
}
void MXRLibraryAddTrackSlaves(input_item_t *item, NSArray<NSDictionary *> *tracks) {
    for(NSDictionary *track in tracks) {
        NSString *url=track[MXRLibraryTrackURL]; if(!url.length) continue;
        input_item_slave_t *slave=input_item_slave_New(url.UTF8String,[track[MXRLibraryTrackAudio] boolValue]?SLAVE_TYPE_GENERIC:SLAVE_TYPE_SPU,SLAVE_PRIORITY_USER);
        if(slave&&input_item_AddSlave(item,slave)!=VLC_SUCCESS) input_item_slave_Delete(slave);
    }
}
BOOL MXRLibrarySelectSoundtrack(vlc_player_t *player, NSArray<NSDictionary *> *tracks) {
    for(NSDictionary *track in tracks) {
        NSString *url=track[MXRLibraryTrackURL];
        if(![track[MXRLibraryTrackAudio] boolValue]||!url.length) continue;
        char hex[VLC_HASH_MD5_DIGEST_HEX_SIZE]; vlc_hash_md5_t md5;
        vlc_hash_md5_Init(&md5); vlc_hash_md5_Update(&md5,url.UTF8String,strlen(url.UTF8String)); vlc_hash_FinishHex(&md5,hex);
        size_t count=vlc_player_GetTrackCount(player,AUDIO_ES);
        for(size_t i=0;i<count;i++) {
            const struct vlc_player_track *candidate=vlc_player_GetTrackAt(player,AUDIO_ES,i);
            const char *strID=candidate?vlc_es_id_GetStrId(candidate->es_id):NULL;
            if(!strID||strncmp(strID,hex,VLC_HASH_MD5_DIGEST_HEX_SIZE-1)||strID[VLC_HASH_MD5_DIGEST_HEX_SIZE-1]!='/') continue;
            if(!candidate->selected) vlc_player_SelectTrack(player,candidate,VLC_PLAYER_SELECT_EXCLUSIVE);
            return YES;
        }
    }
    return NO;
}

static NSString *LS(const char *s) { return s?([NSString stringWithUTF8String:s]?:@""):@""; }
static NSString *LID(int64_t value) { return [NSString stringWithFormat:@"ml:%lld",(long long)value]; }
/* Media and playlist IDs occupy separate ML namespaces. A saved network
 * collection is a real playlist, including the directly playable single URL. */
static NSString *const NetworkPlaylistPrefix=@"ml-network-playlist:";
static NSString *NetworkPlaylistID(int64_t value) { return [NetworkPlaylistPrefix stringByAppendingFormat:@"%lld",(long long)value]; }
static int64_t NetworkPlaylistNumber(NSString *value) { return [value hasPrefix:NetworkPlaylistPrefix]?[[value substringFromIndex:NetworkPlaylistPrefix.length] longLongValue]:0; }
static int64_t NumberID(NSString *value) {
    if(![value isKindOfClass:NSString.class]) return 0;
    if(NetworkPlaylistNumber(value)) return NetworkPlaylistNumber(value);
    return [[value hasPrefix:@"ml:"]?[value substringFromIndex:3]:value longLongValue];
}
static NSError *LE(NSString *message) { return [NSError errorWithDomain:@"MXRVLCBridge" code:4 userInfo:@{NSLocalizedDescriptionKey:message}]; }
/* Folder MRLs from the media library end with "/"; all prefix tests use that form. */
static NSString *FolderKey(NSString *mrl) { return !mrl.length||[mrl hasSuffix:@"/"]?mrl:[mrl stringByAppendingString:@"/"]; }
static NSString *ParentKey(NSString *mrl) {
    NSRange slash=[mrl rangeOfString:@"/" options:NSBackwardsSearch];
    return slash.location==NSNotFound?nil:[mrl substringToIndex:slash.location+1];
}
static BOOL IsNetworkMRL(NSString *mrl) {
    NSURL *url=mrl.length?[NSURL URLWithString:mrl]:nil;
    return url.scheme.length>0 && !url.isFileURL;
}
static NSString *Thumbnail(const vlc_ml_thumbnail_t *thumbnails) {
    const vlc_ml_thumbnail_t *small=&thumbnails[VLC_ML_THUMBNAIL_SMALL];
    return small->i_status==VLC_ML_THUMBNAIL_STATUS_AVAILABLE&&small->psz_mrl?LS(small->psz_mrl):nil;
}
static NSComparisonResult NaturalCompare(NSString *a,NSString *b) { return [a?:@"" localizedStandardCompare:b?:@""]; }
static NSString *const AddLibraryAction=@"add";

/* m3u/pls/podcast expansion through VLC's playlist demuxers (preparser with subitems). */
@interface MXRExpansion : NSObject
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *items;
@property(nonatomic,strong) dispatch_semaphore_t done;
@end
@implementation MXRExpansion
@end
static void ExpansionSubtree(vlc_preparser_req *req,input_item_node_t *subtree,void *data) {
    (void)req;
    MXRExpansion *expansion=(__bridge MXRExpansion *)data;
    for(int i=0;i<subtree->i_children;i++) {
        input_item_t *item=subtree->pp_children[i]->p_item;
        char *uri=input_item_GetURI(item),*name=input_item_GetTitleFbName(item);
        NSString *url=LS(uri),*title=LS(name); free(uri); free(name);
        if(url.length) @synchronized(expansion) { [expansion.items addObject:@{@"url":url,@"name":title}]; }
    }
    input_item_node_Delete(subtree);
}
static void ExpansionEnded(vlc_preparser_req *req,int status,void *data) {
    (void)req; (void)status;
    MXRExpansion *expansion=CFBridgingRelease(data);
    dispatch_semaphore_signal(expansion.done);
}
static const struct vlc_preparser_cbs ExpansionCallbacks={.on_ended=ExpansionEnded,.on_subtree_added=ExpansionSubtree};

@interface MXRLibraryServices ()
- (void)engineChanged:(BOOL)indexing known:(BOOL)known;
- (void)markStale;
- (void)thumbnailGenerated:(int64_t)mediaID;
- (void)contentDirty;
- (void)mediaChanged:(int64_t)mediaID;
- (void)mediaChangedEverywhere;
- (void)mediaAdded;
@end

static void LibraryEvent(void *data,const vlc_ml_event_t *event) {
    MXRLibraryServices *service=(__bridge MXRLibraryServices *)data;
    switch(event->i_type) {
        case VLC_ML_EVENT_BACKGROUND_IDLE_CHANGED:
            [service engineChanged:!event->background_idle_changed.b_idle known:YES]; return;
        /* Progress-only events: the media they announce arrive as their own events. */
        case VLC_ML_EVENT_PARSING_PROGRESS_UPDATED: case VLC_ML_EVENT_DISCOVERY_PROGRESS:
        case VLC_ML_EVENT_DISCOVERY_STARTED: case VLC_ML_EVENT_RESCAN_STARTED:
            return;
        /* A finished thumbnail only changes that media's picture: report it by id so the
         * interface refreshes the visible entry instead of reloading the page. */
        case VLC_ML_EVENT_MEDIA_THUMBNAIL_GENERATED:
            if(event->media_thumbnail_generated.b_success&&event->media_thumbnail_generated.p_media) {
                [service thumbnailGenerated:event->media_thumbnail_generated.p_media->i_id];
                [service mediaChanged:event->media_thumbnail_generated.p_media->i_id];
                [service engineChanged:NO known:NO];
            }
            return;
        /* Only the cached entry of that media goes stale (ENG-M3). */
        case VLC_ML_EVENT_MEDIA_UPDATED:
            [service mediaChanged:event->modification.i_entity_id]; break;
        case VLC_ML_EVENT_HISTORY_CHANGED: case VLC_ML_EVENT_FAVORITES_CHANGED:
            [service mediaChangedEverywhere]; break;
        case VLC_ML_EVENT_BOOKMARKS_ADDED: case VLC_ML_EVENT_BOOKMARKS_UPDATED: case VLC_ML_EVENT_BOOKMARKS_DELETED:
            break;
        case VLC_ML_EVENT_MEDIA_ADDED:
            [service mediaAdded]; [service markStale]; break;
        case VLC_ML_EVENT_MEDIA_DELETED:
            [service mediaChanged:event->deletion.i_entity_id]; [service markStale]; break;
        default:
            /* Folders, entry points, album/artist/genre/playlist add-remove-rename. */
            [service markStale]; break;
    }
    [service contentDirty];
    [service engineChanged:NO known:NO];
}

@implementation MXRLibraryServices {
    intf_thread_t *_intf;
    vlc_medialibrary_t *_ml;
    vlc_ml_event_callback_t *_listener;
    dispatch_queue_t _queue;
    atomic_bool _stopped;
    atomic_bool _stale;
    atomic_bool _notifyScheduled;
    atomic_int _pendingIndexing;
    NSUInteger _mediaCount;
    BOOL _indexing;
    NSMutableDictionary<NSString *,id> *_mediaCache;
    /* Cache entries whose media changed: still served, refreshed on their next read. */
    NSMutableSet<NSString *> *_staleMedia;
    /* Written by the library callback thread, read on the queue (guarded by _readyThumbnails). */
    NSMutableSet<NSString *> *_dirtyMediaIDs;
    BOOL _dirtyAllMedia, _mediaAdded;
    /* Queue-owned state. */
    NSDictionary<NSString *,NSDictionary *> *_foldersByKey;
    NSArray<NSDictionary *> *_entryPoints;
    NSMutableDictionary<NSNumber *,NSDictionary *> *_albums;
    NSMutableDictionary<NSNumber *,NSString *> *_artists;
    NSMutableDictionary<NSNumber *,NSString *> *_genres;
    NSMutableSet<NSNumber *> *_thumbnailRequests;
    /* Thumbnails finished since the last notification (any thread, guarded by self). */
    NSMutableSet<NSNumber *> *_readyThumbnails;
    atomic_bool _contentDirty;
    NSArray<NSString *> *_publishedThumbnails;
    BOOL _publishedContentChanged;
    unsigned _thumbnailWidth,_thumbnailHeight;
    NSMutableDictionary<NSString *,id> *_store;
    vlc_preparser_t *_expander;
    dispatch_group_t _expansionWorkers;
    NSString *_pageCacheKey;
    NSArray *_pageCacheEntries;
    NSString *_pageCacheAddAction;
    NSArray *_homeCache;
    NSDictionary *_homeCacheLimits;
    NSArray *_importedCache;
    atomic_bool _queryDirty;
}

- (instancetype)initWithInterface:(intf_thread_t *)intf {
    if(!(self=[super init])) return nil;
    _expansionWorkers=dispatch_group_create(); atomic_init(&_queryDirty,true);
    atomic_init(&_stopped,false); atomic_init(&_stale,true); atomic_init(&_notifyScheduled,false); atomic_init(&_pendingIndexing,-1);
    _intf=intf;
    _queue=dispatch_queue_create("org.vlc-redesign.library",DISPATCH_QUEUE_SERIAL); _mediaCache=[NSMutableDictionary dictionary]; _staleMedia=[NSMutableSet set]; _dirtyMediaIDs=[NSMutableSet set];
    _albums=[NSMutableDictionary dictionary]; _artists=[NSMutableDictionary dictionary]; _genres=[NSMutableDictionary dictionary];
    _thumbnailRequests=[NSMutableSet set]; _readyThumbnails=[NSMutableSet set];
    atomic_init(&_contentDirty,false); _thumbnailWidth=640; _thumbnailHeight=360;
    _ml=vlc_ml_instance_get(intf);
    if(_ml) { _listener=vlc_ml_event_register_callback(_ml,LibraryEvent,(__bridge void *)self); [self engineChanged:NO known:NO]; }
    return self;
}
- (BOOL)available { return _ml!=NULL && _listener!=NULL; }
- (NSDictionary *)snapshot {
    return @{@"mediaCount":@(_mediaCount),@"isIndexing":@(_indexing),
             @"thumbnails":_publishedThumbnails?:@[],@"contentChanged":@(_publishedContentChanged)};
}
- (NSDictionary *)cachedMediaForURL:(NSString *)url {
    NSAssert(NSThread.isMainThread,@"Library cache belongs to main");
    if(!self.available||!url.length||atomic_load(&_stopped)) return nil;
    id cached=_mediaCache[url];
    if(!cached||[_staleMedia containsObject:url]) {
        /* A stale entry is served while it refreshes; only a real change is reported. */
        [_staleMedia removeObject:url];
        if(!cached) _mediaCache[url]=NSNull.null;
        [self request:@"media" arguments:@{@"id":url} completion:^(NSDictionary *result,NSError *error){
            (void)error;
            if(atomic_load(&self->_stopped)) return;
            id previous=self->_mediaCache[url],fresh=result[@"media"]?:NSNull.null;
            self->_mediaCache[url]=fresh;
            if([previous isEqual:fresh]) return;
            if(!self.serviceChanged) return;
            self.serviceChanged(MXRBridgeServicePlayer);
            /* Queue rows show the favorite flag only. */
            BOOL before=[previous isKindOfClass:NSDictionary.class]&&[previous[@"isFavorite"] boolValue];
            BOOL after=[fresh isKindOfClass:NSDictionary.class]&&[fresh[@"isFavorite"] boolValue];
            if(before!=after) self.serviceChanged(MXRBridgeServiceQueueFavorites);
        }];
    }
    return [cached isKindOfClass:NSDictionary.class]?cached:nil;
}
/// Library events name the media they change; only those cache entries are refreshed.
- (void)mediaChanged:(int64_t)mediaID { @synchronized(_readyThumbnails) { [_dirtyMediaIDs addObject:LID(mediaID)]; } }
- (void)mediaChangedEverywhere { @synchronized(_readyThumbnails) { _dirtyAllMedia=YES; } }
- (void)mediaAdded { @synchronized(_readyThumbnails) { _mediaAdded=YES; } }
/// Main. Marks the cache entries the events of one burst touch as stale.
- (NSUInteger)invalidateMedia:(NSSet<NSString *> *)ids everything:(BOOL)everything unknown:(BOOL)unknown {
    for(NSString *url in _mediaCache.allKeys) {
        id entry=_mediaCache[url];
        BOOL isNull=entry==NSNull.null;
        if(everything||(isNull&&unknown)||(!isNull&&[ids containsObject:[entry isKindOfClass:NSDictionary.class]?entry[@"id"]:@""])) [_staleMedia addObject:url];
    }
    return _staleMedia.count;
}
- (void)markStale { atomic_store(&_stale,true); atomic_store(&_queryDirty,true); }
- (void)contentDirty { atomic_store(&_contentDirty,true); atomic_store(&_queryDirty,true); }
- (void)thumbnailGenerated:(int64_t)mediaID {
    @synchronized(_readyThumbnails) { [_readyThumbnails addObject:@(mediaID)]; }
}
/* Media-library events arrive in bursts (indexing, thumbnails, playback
 * progress). Coalesce them so the interface refreshes at most every 250 ms
 * and keeps showing its current content meanwhile. */
- (void)engineChanged:(BOOL)indexing known:(BOOL)known {
    if(atomic_load(&_stopped)) return;
    if(known) atomic_store(&_pendingIndexing,indexing?1:0);
    if(atomic_exchange(&_notifyScheduled,true)) return;
    __weak MXRLibraryServices *weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),_queue,^{ @autoreleasepool {
        MXRLibraryServices *self=weakSelf; if(!self||atomic_load(&self->_stopped)) return;
        atomic_store(&self->_notifyScheduled,false);
        NSUInteger count=[self knownMediaCount];
        int pending=atomic_exchange(&self->_pendingIndexing,-1);
        BOOL dirty=atomic_exchange(&self->_contentDirty,false);
        NSMutableArray<NSString *> *ready=[NSMutableArray array];
        NSSet<NSString *> *changedMedia; BOOL everything,unknown;
        @synchronized(self->_readyThumbnails) {
            changedMedia=[self->_dirtyMediaIDs copy]; [self->_dirtyMediaIDs removeAllObjects];
            everything=self->_dirtyAllMedia; unknown=self->_mediaAdded; self->_dirtyAllMedia=NO; self->_mediaAdded=NO;
            for(NSNumber *n in self->_readyThumbnails) [ready addObject:LID(n.longLongValue)];
            [self->_readyThumbnails removeAllObjects];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            MXRLibraryServices *self=weakSelf; if(!self||atomic_load(&self->_stopped)) return;
            BOOL stale=[self invalidateMedia:changedMedia everything:everything unknown:unknown]>0;
            self->_publishedThumbnails=ready; self->_publishedContentChanged=dirty||ready.count==0;
            self->_mediaCount=count; if(pending>=0) self->_indexing=pending==1;
            if(stale&&self.serviceChanged) self.serviceChanged(MXRBridgeServiceMediaStale);
            if(self.serviceChanged) self.serviceChanged(MXRBridgeServiceLibrary);
        });
    }});
}
- (void)shutdown {
    if(atomic_exchange(&_stopped,true)) return;
    _serviceChanged=nil;
    if(_listener) vlc_ml_event_unregister_callback(_ml,_listener);
    _listener=NULL;
    @synchronized(self) { if(_expander) vlc_preparser_Cancel(_expander,NULL); }
}
- (void)finishShutdown {
    dispatch_group_wait(_expansionWorkers,DISPATCH_TIME_FOREVER);
    dispatch_sync(_queue,^{});
    @synchronized(self) { if(_expander) { vlc_preparser_Delete(_expander); _expander=NULL; } }
}
- (void)dealloc { assert(!_listener); }

#pragma mark App-side store (titles of expanded stream items, playlist artwork, network collection ids)

/* Next to VLC's own media-library database (VLC_USERDATA_DIR), so both move together. */
- (NSURL *)storeDirectory {
    char *userdata=config_GetUserDir(VLC_USERDATA_DIR);
    NSString *base=userdata?LS(userdata):NSTemporaryDirectory(); free(userdata);
    NSURL *directory=[[NSURL fileURLWithPath:base isDirectory:YES] URLByAppendingPathComponent:@"macosx-redesign-library" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return directory;
}
- (NSMutableDictionary *)store {
    if(!_store) {
        NSData *data=[NSData dataWithContentsOfURL:[self.storeDirectory URLByAppendingPathComponent:@"library-store.json"]];
        NSDictionary *saved=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
        _store=[NSMutableDictionary dictionary];
        _store[@"titles"]=[([saved[@"titles"] isKindOfClass:NSDictionary.class]?saved[@"titles"]:@{}) mutableCopy];
        _store[@"networkPlaylists"]=[([saved[@"networkPlaylists"] isKindOfClass:NSArray.class]?saved[@"networkPlaylists"]:@[]) mutableCopy];
        _store[@"importedMedia"]=[([saved[@"importedMedia"] isKindOfClass:NSArray.class]?saved[@"importedMedia"]:@[]) mutableCopy];
        _store[@"importDates"]=[([saved[@"importDates"] isKindOfClass:NSDictionary.class]?saved[@"importDates"]:@{}) mutableCopy];
        _store[@"seededDefaults"]=saved[@"seededDefaults"]?:@NO;
        _store[@"seededPlaylists"]=[([saved[@"seededPlaylists"] isKindOfClass:NSArray.class]?saved[@"seededPlaylists"]:@[]) mutableCopy];
    }
    return _store;
}
- (void)saveStore {
    NSData *data=[NSJSONSerialization dataWithJSONObject:self.store options:0 error:nil];
    [data writeToURL:[self.storeDirectory URLByAppendingPathComponent:@"library-store.json"] atomically:YES];
}
- (NSMutableDictionary<NSString *,NSString *> *)titles { return self.store[@"titles"]; }
- (NSMutableArray<NSNumber *> *)networkPlaylistIDs { return self.store[@"networkPlaylists"]; }
- (NSURL *)artworkDirectory {
    NSURL *directory=[self.storeDirectory URLByAppendingPathComponent:@"PlaylistArtwork" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return directory;
}
- (NSURL *)artworkForPlaylist:(int64_t)playlistID {
    NSString *prefix=[NSString stringWithFormat:@"%lld.",(long long)playlistID];
    for(NSURL *url in [NSFileManager.defaultManager contentsOfDirectoryAtURL:self.artworkDirectory includingPropertiesForKeys:nil options:0 error:nil])
        if([url.lastPathComponent hasPrefix:prefix]) return url;
    return nil;
}
- (void)setArtwork:(NSString *)source forPlaylist:(int64_t)playlistID {
    NSURL *existing=[self artworkForPlaylist:playlistID]; if(existing) [NSFileManager.defaultManager removeItemAtURL:existing error:nil];
    NSURL *url=source.length?[NSURL URLWithString:source]:nil; if(!url.isFileURL) return;
    NSString *extension=url.pathExtension.length?url.pathExtension.lowercaseString:@"png";
    NSURL *target=[self.artworkDirectory URLByAppendingPathComponent:[NSString stringWithFormat:@"%lld.%@",(long long)playlistID,extension]];
    [NSFileManager.defaultManager copyItemAtURL:url toURL:target error:nil];
}

#pragma mark Folder index

- (void)ensureIndex {
    if(!atomic_exchange(&_stale,false) && _foldersByKey) return;
    [_albums removeAllObjects]; [_artists removeAllObjects]; [_genres removeAllObjects];
    NSMutableDictionary *folders=[NSMutableDictionary dictionary];
    vlc_ml_folder_list_t *list=vlc_ml_list_folders(_ml,NULL);
    if(list) { for(size_t i=0;i<list->i_nb_items;i++) {
        const vlc_ml_folder_t *f=&list->p_items[i];
        if(!f->psz_mrl||f->b_banned) continue;
        NSDictionary *folder=[self folderInfo:f]; folders[folder[@"key"]]=folder;
    } vlc_ml_folder_list_release(list); }
    NSMutableArray *roots=[NSMutableArray array];
    vlc_ml_folder_list_t *points=vlc_ml_list_entry_points(_ml,NULL);
    if(points) { for(size_t i=0;i<points->i_nb_items;i++) if(points->p_items[i].psz_mrl) [roots addObject:[self folderInfo:&points->p_items[i]]];
        vlc_ml_folder_list_release(points); }
    [roots sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){ return NaturalCompare(a[@"name"],b[@"name"]); }];
    _foldersByKey=folders; _entryPoints=roots;
}
- (NSDictionary *)folderInfo:(const vlc_ml_folder_t *)f {
    NSString *key=FolderKey(LS(f->psz_mrl)),*name=LS(f->psz_name);
    if(!name.length) name=[[NSURL URLWithString:key].lastPathComponent stringByRemovingPercentEncoding]?:key;
    return @{@"n":@(f->i_id),@"id":LID(f->i_id),@"name":name,@"key":key,@"video":@(f->i_nb_video),@"audio":@(f->i_nb_audio),@"media":@(f->i_nb_media)};
}
/* True when `key` or a folder below it directly holds media of `type` (UNKNOWN = any). */
- (BOOL)folder:(NSString *)key contains:(vlc_ml_media_type_t)type {
    for(NSDictionary *folder in _foldersByKey.allValues) {
        if(![folder[@"key"] hasPrefix:key]) continue;
        NSUInteger count=[folder[type==VLC_ML_MEDIA_TYPE_VIDEO?@"video":type==VLC_ML_MEDIA_TYPE_AUDIO?@"audio":@"media"] unsignedIntegerValue];
        if(count) return YES;
    }
    return NO;
}
/* MRLs of the direct children of `key` that contain media somewhere below. */
- (NSSet<NSString *> *)childKeys:(NSString *)key {
    NSMutableSet *children=[NSMutableSet set];
    for(NSString *candidate in _foldersByKey) {
        if(candidate.length<=key.length||![candidate hasPrefix:key]) continue;
        NSRange slash=[candidate rangeOfString:@"/" options:0 range:NSMakeRange(key.length,candidate.length-key.length)];
        if(slash.location!=NSNotFound) [children addObject:[candidate substringToIndex:slash.location+1]];
    }
    return children;
}
- (NSDictionary *)folderEntry:(NSDictionary *)folder entryPoint:(BOOL)entryPoint {
    NSString *key=folder[@"key"];
    NSUInteger count=[self childKeys:key].count+[_foldersByKey[key][@"media"] unsignedIntegerValue];
    BOOL video=[self folder:key contains:VLC_ML_MEDIA_TYPE_VIDEO];
    return @{@"type":@"folder",@"id":folder[@"id"],@"name":folder[@"name"],@"url":key,@"itemCount":@(count),
             @"kind":video||![self folder:key contains:VLC_ML_MEDIA_TYPE_AUDIO]?@"video":@"audio",@"isEntryPoint":@(entryPoint)};
}
- (NSArray *)subfolders:(int64_t)folderID key:(NSString *)key {
    NSSet *children=[self childKeys:key]; NSMutableArray *result=[NSMutableArray array];
    if(!children.count) return result;
    vlc_ml_folder_list_t *list=NULL;
    if(vlc_ml_list(_ml,VLC_ML_LIST_SUBFOLDERS,NULL,folderID,&list)!=VLC_SUCCESS) list=NULL;
    if(list) { for(size_t i=0;i<list->i_nb_items;i++) {
        if(!list->p_items[i].psz_mrl||list->p_items[i].b_banned) continue;
        NSDictionary *folder=[self folderInfo:&list->p_items[i]];
        if([children containsObject:folder[@"key"]]) [result addObject:folder];
    } vlc_ml_folder_list_release(list); }
    return result;
}
- (NSArray *)rootFolders:(vlc_ml_media_type_t)type {
    NSMutableArray *result=[NSMutableArray array];
    for(NSDictionary *root in _entryPoints) if([self folder:root[@"key"] contains:type]) [result addObject:[self folderEntry:root entryPoint:YES]];
    return result;
}
/* Entry point → … → folder, found by walking subfolders along the MRL. */
- (NSArray<NSDictionary *> *)folderChain:(int64_t)folderID {
    vlc_ml_folder_t *target=vlc_ml_get_folder(_ml,folderID);
    if(!target) return @[];
    NSDictionary *info=[self folderInfo:target]; vlc_ml_folder_release(target);
    NSString *key=info[@"key"]; NSDictionary *current=nil;
    for(NSDictionary *root in _entryPoints) if([key hasPrefix:root[@"key"]] && (!current||[root[@"key"] length]>[current[@"key"] length])) current=root;
    if(!current) return @[info];
    NSMutableArray *chain=[NSMutableArray arrayWithObject:current];
    for(int depth=0;![current[@"key"] isEqual:key]&&depth<64;depth++) {
        vlc_ml_folder_list_t *list=NULL; NSDictionary *next=nil;
        if(vlc_ml_list(_ml,VLC_ML_LIST_SUBFOLDERS,NULL,[current[@"n"] longLongValue],&list)!=VLC_SUCCESS) list=NULL;
        if(list) { for(size_t i=0;i<list->i_nb_items&&!next;i++) {
            if(!list->p_items[i].psz_mrl) continue;
            NSDictionary *child=[self folderInfo:&list->p_items[i]];
            if([key hasPrefix:child[@"key"]]) next=child;
        } vlc_ml_folder_list_release(list); }
        if(!next) break;
        [chain addObject:next]; current=next;
    }
    if(![current[@"key"] isEqual:key]) [chain addObject:info];
    return chain;
}

#pragma mark Entities

- (NSDictionary *)album:(int64_t)albumID {
    if(albumID<=0) return nil;
    NSDictionary *cached=_albums[@(albumID)]; if(cached) return [cached isKindOfClass:NSDictionary.class]&&[cached count]?cached:nil;
    vlc_ml_album_t *album=vlc_ml_get_album(_ml,albumID);
    NSMutableDictionary *info=[NSMutableDictionary dictionary];
    if(album) { info[@"title"]=LS(album->psz_title); NSString *art=Thumbnail(album->thumbnails); if(art) info[@"artworkURL"]=art; vlc_ml_album_release(album); }
    _albums[@(albumID)]=info; return info.count?info:nil;
}
/* Unknown (1) and Various (2) artists are medialibrary placeholders, not names. */
- (NSString *)artist:(int64_t)artistID {
    if(artistID<=2) return nil;
    NSString *cached=_artists[@(artistID)]; if(cached) return cached.length?cached:nil;
    vlc_ml_artist_t *artist=vlc_ml_get_artist(_ml,artistID); NSString *name=artist?LS(artist->psz_name):@"";
    if(artist) vlc_ml_artist_release(artist);
    _artists[@(artistID)]=name; return name.length?name:nil;
}
- (NSString *)genre:(int64_t)genreID {
    if(genreID<=0) return nil;
    NSString *cached=_genres[@(genreID)]; if(cached) return cached.length?cached:nil;
    vlc_ml_genre_t *genre=vlc_ml_get_genre(_ml,genreID); NSString *name=genre?LS(genre->psz_name):@"";
    if(genre) vlc_ml_genre_release(genre);
    _genres[@(genreID)]=name; return name.length?name:nil;
}
- (NSDictionary *)media:(const vlc_ml_media_t *)media {
    NSString *url=@""; BOOL external=NO;
    if(media->p_files) for(size_t i=0;i<media->p_files->i_nb_items;i++) {
        if(media->p_files->p_items[i].i_type==VLC_ML_FILE_TYPE_MAIN) { url=LS(media->p_files->p_items[i].psz_mrl); external=media->p_files->p_items[i].b_external; break; }
    }
    BOOL network=IsNetworkMRL(url);
    NSString *kind=media->i_type==VLC_ML_MEDIA_TYPE_AUDIO?@"audio":media->i_type==VLC_ML_MEDIA_TYPE_VIDEO?@"video":network?@"stream":@"unknown";
    NSString *title=self.titles[url]?:LS(media->psz_title);
    NSMutableDictionary *d=[@{@"id":LID(media->i_id),@"url":url,@"title":title,@"kind":kind,
      @"isFavorite":@(media->b_is_favorite),@"playCount":@(media->i_playcount),@"lastPlayedDate":@(media->i_last_played_date)} mutableCopy];
    if(media->i_duration>0) d[@"duration"]=@(media->i_duration*1000);
    if(media->psz_filename&&!network) d[@"fileName"]=LS(media->psz_filename);
    if(media->i_year>0) d[@"year"]=@(media->i_year);
    /* lastPosition is -1 when nothing is stored and is reset to -1 when a play
     * completes (the play count is incremented instead), so only a partial
     * position is a progress; a watched item draws a full line from playCount. */
    if(media->f_progress>0&&media->f_progress<1) d[@"progress"]=@(media->f_progress);
    if(external) d[@"isExternal"]=@YES;
    NSString *art=Thumbnail(media->thumbnails);
    if(media->i_subtype==VLC_ML_MEDIA_SUBTYPE_ALBUMTRACK) {
        NSString *artist=[self artist:media->album_track.i_artist_id],*genre=[self genre:media->album_track.i_genre_id];
        NSDictionary *album=[self album:media->album_track.i_album_id];
        if(artist) d[@"artist"]=artist;
        if(genre) d[@"genre"]=genre;
        if(album[@"title"]) d[@"album"]=album[@"title"];
        if(!art) art=album[@"artworkURL"];
        if(media->album_track.i_track_nb>0) d[@"trackNumber"]=@(media->album_track.i_track_nb);
        if(media->album_track.i_disc_nb>0) d[@"discNumber"]=@(media->album_track.i_disc_nb);
    }
    if(art) d[@"artworkURL"]=art;
    if(media->p_tracks) for(size_t i=0;i<media->p_tracks->i_nb_items;i++) {
        const vlc_ml_media_track_t *track=&media->p_tracks->p_items[i];
        if(track->i_type==VLC_ML_TRACK_TYPE_VIDEO&&track->v.i_width&&track->v.i_height) { d[@"width"]=@(track->v.i_width); d[@"height"]=@(track->v.i_height); break; }
    }
    NSString *parent=url.length&&!network?ParentKey(url):nil; NSDictionary *folder=parent?_foldersByKey[parent]:nil;
    if(folder) d[@"folder"]=@{@"id":folder[@"id"],@"name":folder[@"name"]};
    /* The media-library thumbnailer persists a representative frame (30 % in)
     * and announces it with VLC_ML_EVENT_MEDIA_THUMBNAIL_GENERATED. */
    if(!art&&media->i_type==VLC_ML_MEDIA_TYPE_VIDEO&&!network&&media->thumbnails[VLC_ML_THUMBNAIL_SMALL].i_status==VLC_ML_THUMBNAIL_STATUS_MISSING
       &&![_thumbnailRequests containsObject:@(media->i_id)]) {
        [_thumbnailRequests addObject:@(media->i_id)];
        vlc_ml_media_generate_thumbnail(_ml,media->i_id,VLC_ML_THUMBNAIL_SMALL,_thumbnailWidth,_thumbnailHeight,0.3);
    }
    return d;
}
- (NSMutableArray *)mediaList:(vlc_ml_media_list_t *)list {
    NSMutableArray *result=[NSMutableArray array];
    if(list) { for(size_t i=0;i<list->i_nb_items;i++) [result addObject:[self media:&list->p_items[i]]]; vlc_ml_media_list_release(list); }
    return result;
}
static NSString *PlaylistRevision(NSArray *media) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:[media valueForKey:@"id"] options:0 error:nil];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *result=[NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH*2];
    for(NSUInteger i=0;i<CC_SHA256_DIGEST_LENGTH;i++) [result appendFormat:@"%02x",digest[i]];
    return result;
}
static NSArray *MediaEntries(NSArray *media) {
    NSMutableArray *entries=[NSMutableArray arrayWithCapacity:media.count];
    for(NSDictionary *m in media) [entries addObject:@{@"type":@"media",@"media":m}];
    return entries;
}
- (NSDictionary *)playlistEntry:(const vlc_ml_playlist_t *)p {
    NSMutableDictionary *d=[@{@"type":@"playlist",@"id":LID(p->i_id),@"name":LS(p->psz_name),@"itemCount":@(p->i_nb_media),
      @"duration":@(p->i_duration*1000),@"isFavorite":@(p->b_is_favorite)} mutableCopy];
    NSURL *art=[self artworkForPlaylist:p->i_id];
    if(art) d[@"artworkURL"]=art.absoluteString; else if(p->psz_artwork_mrl) d[@"artworkURL"]=LS(p->psz_artwork_mrl);
    return d;
}
- (NSDictionary *)albumEntry:(const vlc_ml_album_t *)a {
    NSMutableDictionary *d=[@{@"type":@"album",@"id":LID(a->i_id),@"title":LS(a->psz_title),@"artist":LS(a->psz_artist),@"trackCount":@(a->i_nb_tracks),@"duration":@(a->i_duration*1000)} mutableCopy];
    if(a->i_year) d[@"year"]=@(a->i_year);
    NSString *art=Thumbnail(a->thumbnails); if(art) d[@"artworkURL"]=art;
    return d;
}
- (NSDictionary *)artistEntry:(const vlc_ml_artist_t *)a {
    NSMutableDictionary *d=[@{@"type":@"artist",@"id":LID(a->i_id),@"name":LS(a->psz_name),@"albumCount":@(a->i_nb_album),@"trackCount":@(a->i_nb_tracks)} mutableCopy];
    NSString *art=Thumbnail(a->thumbnails); if(art) d[@"artworkURL"]=art;
    return d;
}

#pragma mark Counting

/* Home's "N items": indexed media plus media opened directly (history only). */
- (NSUInteger)knownMediaCount {
    NSUInteger count=vlc_ml_count_media(_ml,NULL);
    vlc_ml_query_params_t p=vlc_ml_query_params_create(); p.i_nbResults=1000;
    vlc_ml_media_list_t *history=vlc_ml_list_history(_ml,&p,VLC_ML_HISTORY_TYPE_GLOBAL);
    if(history) { for(size_t i=0;i<history->i_nb_items;i++) {
        const vlc_ml_media_t *m=&history->p_items[i];
        if(m->p_files) for(size_t f=0;f<m->p_files->i_nb_items;f++) if(m->p_files->p_items[f].i_type==VLC_ML_FILE_TYPE_MAIN) { if(m->p_files->p_items[f].b_external) count++; break; }
    } vlc_ml_media_list_release(history); }
    return count;
}

#pragma mark Network collections

/* A network collection is a playlist this service saved (recorded in the
 * store), or any playlist whose items are all network URLs. */
- (NSDictionary *)networkPlaylist:(const vlc_ml_playlist_t *)playlist {
    vlc_ml_media_list_t *media=vlc_ml_list_playlist_media(_ml,NULL,playlist->i_id);
    if(!media) return nil;
    NSMutableArray *urls=[NSMutableArray array];
    BOOL recorded=[self.networkPlaylistIDs containsObject:@(playlist->i_id)];
    BOOL network=recorded||media->i_nb_items>0;
    uint32_t playCount=UINT32_MAX;
    for(size_t i=0;i<media->i_nb_items;i++) {
        const vlc_ml_media_t *m=&media->p_items[i]; NSString *mrl=@"";
        if(m->p_files) for(size_t f=0;f<m->p_files->i_nb_items;f++) if(m->p_files->p_items[f].i_type==VLC_ML_FILE_TYPE_MAIN) { mrl=LS(m->p_files->p_items[f].psz_mrl); break; }
        if(!IsNetworkMRL(mrl)) { if(!recorded) network=NO; continue; }
        [urls addObject:mrl];
        playCount=MIN(playCount,m->i_playcount);
    }
    vlc_ml_media_list_release(media);
    return network?@{@"type":@"stream",@"id":NetworkPlaylistID(playlist->i_id),
                     @"name":LS(playlist->psz_name),@"urls":urls,@"itemCount":@(urls.count),
                     @"sortDate":@(playlist->i_creation_date),@"playCount":@(playCount==UINT32_MAX?0:playCount)}:nil;
}
/* All playlists split into user playlists and saved network collections. */
- (void)playlists:(NSString *)search user:(NSMutableArray *)user network:(NSMutableArray *)network {
    vlc_ml_playlist_list_t *list=vlc_ml_list_playlists(_ml,NULL,VLC_ML_PLAYLIST_TYPE_ALL);
    if(!list) return;
    for(size_t i=0;i<list->i_nb_items;i++) {
        const vlc_ml_playlist_t *p=&list->p_items[i];
        if(search.length&&![LS(p->psz_name) localizedStandardContainsString:search]) continue;
        NSDictionary *stream=[self networkPlaylist:p];
        if(stream) [network addObject:stream]; else [user addObject:[self playlistEntry:p]];
    }
    vlc_ml_playlist_list_release(list);
}
/* §10: "By default there are a bunch of streams saved here" (Podcasts, Radio).
 * Seeded once; they are ordinary collections the user can rename or remove. */
- (void)seedDefaultStreams {
    if([self.store[@"seededDefaults"] boolValue]) return;
    NSMutableArray *existing=[NSMutableArray array]; [self playlists:nil user:[NSMutableArray array] network:existing];
    self.store[@"seededDefaults"]=@YES;
    if(!existing.count) {
        NSArray *defaults=@[
            @{@"name":@"Podcasts",@"items":@[
                @{@"url":@"https://feeds.npr.org/510318/podcast.xml",@"name":@"Up First from NPR"},
                @{@"url":@"https://feeds.npr.org/510289/podcast.xml",@"name":@"Planet Money"},
                @{@"url":@"https://feeds.feedburner.com/TEDTalks_audio",@"name":@"TED Talks Daily"}]},
            @{@"name":@"Radio",@"items":@[
                @{@"url":@"https://stream.radioparadise.com/mp3-192",@"name":@"Radio Paradise · Main Mix"},
                @{@"url":@"https://stream.radioparadise.com/mellow-192",@"name":@"Radio Paradise · Mellow Mix"},
                @{@"url":@"https://kexp-mp3-128.streamguys1.com/kexp128.mp3",@"name":@"KEXP 90.3 FM"},
                @{@"url":@"https://stream.live.vc.bbcmedia.co.uk/bbc_world_service",@"name":@"BBC World Service"}]}];
        for(NSDictionary *collection in defaults) {
            NSDictionary *saved=[self saveNetworkItems:collection[@"items"] name:collection[@"name"] error:NULL];
            int64_t playlistID=NetworkPlaylistNumber(saved[@"stream"][@"id"]);
            if(playlistID) [self.store[@"seededPlaylists"] addObject:@(playlistID)];
        }
    }
    [self saveStore];
}
- (NSArray *)networkEntries:(NSString *)search sort:(NSString *)sort {
    [self seedDefaultStreams];
    NSMutableArray *entries=[NSMutableArray array];
    [self playlists:search user:[NSMutableArray array] network:entries];
    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){
        NSComparisonResult result=NSOrderedSame;
        if([sort isEqual:@"newestFirst"]||[sort isEqual:@"oldestFirst"]) result=[a[@"sortDate"] compare:b[@"sortDate"]];
        else if([sort isEqual:@"watchedFirst"]||[sort isEqual:@"unwatchedFirst"]) result=[a[@"playCount"] compare:b[@"playCount"]];
        else result=NaturalCompare(a[@"name"],b[@"name"]);
        if(result==NSOrderedSame) result=[a[@"sortDate"] compare:b[@"sortDate"]];
        BOOL descending=[sort isEqual:@"newestFirst"]||[sort isEqual:@"watchedFirst"]||[sort hasSuffix:@"Descending"];
        return descending?-result:result;
    }];
    return entries;
}
/* Items are {url, name}; names (an m3u's #EXTINF titles) live in the store
 * because the media library cannot rename stream media. */
- (NSDictionary *)saveNetworkItems:(NSArray<NSDictionary *> *)items name:(NSString *)name error:(NSError **)error {
    int64_t *ids=vlc_alloc(MAX(1u,items.count),sizeof(*ids));
    if(!ids) { if(error) *error=LE(@"The network collection is too large."); return nil; }
    int ret=VLC_SUCCESS;
    for(NSUInteger i=0;i<items.count;i++) {
        NSString *url=items[i][@"url"];
        vlc_ml_media_t *media=vlc_ml_get_media_by_mrl(_ml,url.UTF8String);
        if(!media) media=vlc_ml_new_stream(_ml,url.UTF8String);
        if(!media) { ret=VLC_EGENERIC; break; }
        ids[i]=media->i_id; vlc_ml_media_release(media);
        NSString *title=[items[i][@"name"] isKindOfClass:NSString.class]?items[i][@"name"]:nil;
        if(title.length&&![title isEqual:url]) self.titles[url]=title;
    }
    vlc_ml_playlist_t *playlist=ret==VLC_SUCCESS?vlc_ml_playlist_create(_ml,name.UTF8String):NULL;
    if(playlist&&items.count) ret=vlc_ml_playlist_append(_ml,playlist->i_id,ids,items.count);
    else if(!playlist) ret=VLC_EGENERIC;
    free(ids);
    if(playlist&&ret==VLC_SUCCESS) [self.networkPlaylistIDs addObject:@(playlist->i_id)];
    NSDictionary *stream=ret==VLC_SUCCESS?[self networkPlaylist:playlist]:nil;
    if(!stream) {
        if(playlist) vlc_ml_playlist_delete(_ml,playlist->i_id);
        if(error) *error=LE(@"The media library could not save the network collection.");
    }
    if(playlist) vlc_ml_playlist_release(playlist);
    [self saveStore];
    return stream?@{@"stream":stream}:nil;
}
/* Runs off the library queue: playlist files (m3u, pls, podcast feeds) are
 * opened by VLC's playlist demuxers and replaced by their entries. */
- (NSArray<NSDictionary *> *)expandNetworkURLs:(NSArray<NSString *> *)urls {
    NSMutableArray *items=[NSMutableArray array];
    for(NSString *url in urls) {
        NSArray *children=[self childrenOfPlaylistURL:url];
        if(children.count) [items addObjectsFromArray:children];
        else [items addObject:@{@"url":url,@"name":@""}];
    }
    return items;
}
- (NSArray *)childrenOfPlaylistURL:(NSString *)url {
    NSString *extension=[NSURL URLWithString:url].pathExtension.lowercaseString;
    /* Expanding a live audio or video stream would only probe it; limit the
     * preparse to playlist and feed formats. */
    if(![@[@"m3u",@"m3u8",@"pls",@"xspf",@"asx",@"wpl",@"xml",@"rss"] containsObject:extension?:@""]) return nil;
    vlc_preparser_t *parser=NULL;
    @synchronized(self) {
        if(!_expander&&!atomic_load(&_stopped)) {
            struct vlc_preparser_cfg cfg={.types=VLC_PREPARSER_TYPE_PARSE,.max_parser_threads=1,.timeout=VLC_TICK_FROM_SEC(10),.external_process=false};
            _expander=vlc_preparser_New(VLC_OBJECT(_intf),&cfg);
        }
        parser=_expander;
    }
    if(!parser) return nil;
    input_item_t *item=input_item_New(url.UTF8String,NULL); if(!item) return nil;
    MXRExpansion *expansion=[MXRExpansion new]; expansion.items=[NSMutableArray array]; expansion.done=dispatch_semaphore_create(0);
    void *retained=(__bridge_retained void *)expansion;
    vlc_preparser_req *req=NULL; int submitted=VLC_EGENERIC;
    @synchronized(self) {
        if(!atomic_load(&_stopped)) {
            req=vlc_preparser_req_NewParse(parser,item,VLC_PREPARSER_TYPE_PARSE|VLC_PREPARSER_OPTION_SUBITEMS,&ExpansionCallbacks,retained);
            if(req) submitted=vlc_preparser_Submit(parser,req);
        }
    }
    input_item_Release(item);
    if(!req||submitted!=VLC_SUCCESS) { if(req) vlc_preparser_req_Release(req); CFBridgingRelease(retained); return nil; }
    if(dispatch_semaphore_wait(expansion.done,dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC))) {
        vlc_preparser_Cancel(parser,req);
        dispatch_semaphore_wait(expansion.done,DISPATCH_TIME_FOREVER);
    }
    vlc_preparser_req_Release(req);
    @synchronized(expansion) { return [expansion.items copy]; }
}

#pragma mark Pages

- (vlc_ml_query_params_t)params:(NSString *)sort search:(NSString *)search {
    vlc_ml_query_params_t p=vlc_ml_query_params_create();
    p.psz_pattern=search.length?search.UTF8String:NULL;
    if([sort hasPrefix:@"artist"]) p.i_sort=VLC_ML_SORTING_ARTIST;
    else if([sort hasPrefix:@"album"]) p.i_sort=VLC_ML_SORTING_ALBUM;
    /* The track-number order is disc, then track. */
    else if([sort hasPrefix:@"trackNumber"]||[sort hasPrefix:@"discNumber"]) p.i_sort=VLC_ML_SORTING_TRACKNUMBER;
    else if([sort hasPrefix:@"uri"]) p.i_sort=VLC_ML_SORTING_FILENAME;
    else if([sort isEqual:@"newestFirst"]||[sort isEqual:@"oldestFirst"]) p.i_sort=VLC_ML_SORTING_INSERTIONDATE;
    else p.i_sort=VLC_ML_SORTING_ALPHA; /* title, and the watched sorts' tie order */
    p.b_desc=[sort hasSuffix:@"Descending"]||[sort isEqual:@"newestFirst"];
    return p;
}
/* Watched sorts keep the title order inside each group (key frame 20m14.8s:
 * E05…E15, then the watched E01…E04). */
static NSArray *SortedMedia(NSMutableArray *media,NSString *sort) {
    BOOL unwatchedFirst=[sort isEqual:@"unwatchedFirst"],watchedFirst=[sort isEqual:@"watchedFirst"];
    if(!unwatchedFirst&&!watchedFirst) return media;
    [media sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){
        BOOL wa=[a[@"playCount"] unsignedIntValue]>0,wb=[b[@"playCount"] unsignedIntValue]>0;
        if(wa==wb) return NSOrderedSame;
        return (wa==watchedFirst)?NSOrderedAscending:NSOrderedDescending;
    }];
    return media;
}
/* Imported root rows do not pass through an ML sorted query. Sort their
 * available metadata before page slicing; folders remain in their own group.
 * Only real persisted import dates order dates. Unknown dates retain input
 * order and form an explicit group after records with known dates. */
static NSArray *SortedImportedMedia(NSArray *media,NSString *sort,NSDictionary *importDates) {
    BOOL descending=[sort hasSuffix:@"Descending"]||[sort isEqual:@"newestFirst"];
    return [media sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){
        NSComparisonResult result=NSOrderedSame;
        if([sort isEqual:@"newestFirst"]||[sort isEqual:@"oldestFirst"]) {
            NSNumber *dateA=importDates[a[@"id"]],*dateB=importDates[b[@"id"]];
            BOOL knownA=[dateA isKindOfClass:NSNumber.class],knownB=[dateB isKindOfClass:NSNumber.class];
            if(knownA!=knownB) return knownA?NSOrderedAscending:NSOrderedDescending;
            if(!knownA) return NSOrderedSame;
            result=[dateA compare:dateB];
            return descending?-result:result;
        }
        if([sort isEqual:@"unwatchedFirst"]||[sort isEqual:@"watchedFirst"]) {
            BOOL watchedA=[a[@"playCount"] unsignedIntValue]>0,watchedB=[b[@"playCount"] unsignedIntValue]>0;
            if(watchedA!=watchedB) return watchedA==[sort isEqual:@"watchedFirst"]?NSOrderedAscending:NSOrderedDescending;
        } else if([sort hasPrefix:@"artist"]) result=NaturalCompare(a[@"artist"]?:@"",b[@"artist"]?:@"");
        else if([sort hasPrefix:@"album"]) result=NaturalCompare(a[@"album"]?:@"",b[@"album"]?:@"");
        else if([sort hasPrefix:@"uri"]) result=NaturalCompare(a[@"url"]?:@"",b[@"url"]?:@"");
        if(result==NSOrderedSame&&([sort hasPrefix:@"album"]||[sort hasPrefix:@"trackNumber"]||[sort hasPrefix:@"discNumber"])) {
            result=[a[@"discNumber"]?:@0 compare:b[@"discNumber"]?:@0];
            if(result==NSOrderedSame) result=[a[@"trackNumber"]?:@0 compare:b[@"trackNumber"]?:@0];
        }
        if(result==NSOrderedSame) result=NaturalCompare(a[@"title"]?:a[@"fileName"]?:@"",b[@"title"]?:b[@"fileName"]?:@"");
        return descending?-result:result;
    }];
}
/* A playlist's media in storage order. The engine lists present media only,
 * while vlc_ml_playlist_remove takes storage positions: `complete` says whether
 * the listing is the whole playlist (no item on a disconnected drive), so that
 * row positions are storage positions. Nil when the playlist is gone. */
- (NSMutableArray *)playlistMedia:(int64_t)playlistID complete:(BOOL *)complete {
    vlc_ml_playlist_t *playlist=vlc_ml_get_playlist(_ml,playlistID);
    if(!playlist) { *complete=NO; return nil; }
    unsigned stored=playlist->i_nb_media,present=playlist->i_nb_present_media; vlc_ml_playlist_release(playlist);
    NSMutableArray *items=[self mediaList:vlc_ml_list_playlist_media(_ml,NULL,playlistID)];
    *complete=stored==present&&items.count==stored;
    return items;
}
- (NSMutableArray *)mediaAt:(NSString *)kind identifier:(NSString *)identifier params:(vlc_ml_query_params_t *)p {
    int64_t n=NumberID(identifier);
    if([kind isEqual:@"videos"]) return [self mediaList:vlc_ml_list_video_media(_ml,p)];
    if([kind isEqual:@"music"]||[kind isEqual:@"songs"]||[kind isEqual:@"albums"]||[kind isEqual:@"artists"]||[kind isEqual:@"genres"])
        return [self mediaList:vlc_ml_list_audio_media(_ml,p)];
    if([kind isEqual:@"home"]) return [self mediaList:vlc_ml_list_media(_ml,p)];
    if([kind isEqual:@"recent"]) return [self mediaList:vlc_ml_list_history(_ml,p,VLC_ML_HISTORY_TYPE_GLOBAL)];
    if([kind isEqual:@"folder"]) return [self mediaList:vlc_ml_list_folder_media(_ml,p,n)];
    if([kind isEqual:@"stream"]) return [self mediaList:vlc_ml_list_playlist_media(_ml,p,n)];
    if([kind isEqual:@"playlist"]) {
        BOOL complete=NO;
        NSMutableArray *items=[self playlistMedia:n complete:&complete];
        if(!items) return nil;
        /* Rows carry their storage position only when the listing is the whole
         * playlist; otherwise Remove from Playlist is not offered. */
        if(complete) {
            NSString *revision=PlaylistRevision(items);
            for(NSUInteger i=0;i<items.count;i++) {
                NSMutableDictionary *item=[items[i] mutableCopy];
                item[@"playlistOccurrence"]=@{@"playlistID":identifier,@"position":@(i),@"revision":revision}; items[i]=item;
            }
        }
        if(p->psz_pattern) {
            NSString *search=LS(p->psz_pattern);
            [items filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item,NSDictionary *bindings){
                (void)bindings; return [(item[@"title"]?:@"") localizedStandardContainsString:search];
            }]];
        }
        /* A playlist's dates are its own order: Oldest First is the order the
         * user built, Newest First reverses it. Media index dates say nothing
         * about when an item was added to this playlist. */
        if(p->i_sort==VLC_ML_SORTING_INSERTIONDATE) return p->b_desc?[[[items reverseObjectEnumerator] allObjects] mutableCopy]:items;
        [items sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){
            NSComparisonResult result=NaturalCompare(a[@"title"]?:@"",b[@"title"]?:@"");
            return p->b_desc?-result:result;
        }];
        return items;
    }
    if([kind isEqual:@"album"]) return [self mediaList:vlc_ml_list_album_tracks(_ml,p,n)];
    if([kind isEqual:@"artist"]) return [self mediaList:vlc_ml_list_artist_tracks(_ml,p,n)];
    if([kind isEqual:@"genre"]) return [self mediaList:vlc_ml_list_genre_tracks(_ml,p,n)];
    if([kind isEqual:@"show"]) return [self mediaList:vlc_ml_list_show_episodes(_ml,p,n)];
    return nil;
}
/* Every query cache answers one library state; any engine event or write drops them all. */
- (void)dropQueryCachesIfDirty {
    if(!atomic_exchange(&_queryDirty,false)) return;
    _pageCacheKey=nil; _pageCacheEntries=nil; _homeCache=nil; _importedCache=nil;
}
/* Explicit file imports remain library members even before their first play.
 * They are typed at import (the interface classifies the file); one bridged
 * snapshot serves every root page until the library changes. */
- (NSArray *)importedMedia {
    [self dropQueryCachesIfDirty];
    if(_importedCache) return _importedCache;
    NSMutableArray *items=[NSMutableArray array];
    for(NSString *identifier in self.store[@"importedMedia"]) {
        vlc_ml_media_t *media=vlc_ml_get_media(_ml,NumberID(identifier)); if(!media) continue;
        NSDictionary *item=[self media:media]; vlc_ml_media_release(media);
        if([item[@"isExternal"] boolValue]) [items addObject:item];
    }
    _importedCache=[items copy]; return _importedCache;
}
- (NSArray *)importedMediaMatching:(NSString *)search type:(vlc_ml_media_type_t)type {
    NSMutableArray *result=[NSMutableArray array];
    for(NSDictionary *item in [self importedMedia]) {
        /* An import that predates typing lists under Videos until VLC parses it. */
        BOOL audio=[item[@"kind"] isEqual:@"audio"];
        if(type==VLC_ML_MEDIA_TYPE_AUDIO&&!audio) continue;
        if(type==VLC_ML_MEDIA_TYPE_VIDEO&&audio) continue;
        if(search.length&&![(item[@"title"]?:@"") localizedStandardContainsString:search]) continue;
        [result addObject:item];
    }
    return result;
}
/* Media opened directly (not indexed) only appear in the history. */
- (NSArray *)externalHistoryMatching:(NSString *)search type:(vlc_ml_media_type_t)type {
    vlc_ml_query_params_t p=vlc_ml_query_params_create(); p.psz_pattern=search.UTF8String; p.i_nbResults=200;
    NSMutableArray *result=[NSMutableArray array];
    for(NSDictionary *m in [self mediaList:vlc_ml_list_history(_ml,&p,VLC_ML_HISTORY_TYPE_GLOBAL)]) {
        if(![m[@"isExternal"] boolValue]) continue;
        if(type==VLC_ML_MEDIA_TYPE_VIDEO&&![m[@"kind"] isEqual:@"video"]) continue;
        if(type==VLC_ML_MEDIA_TYPE_AUDIO&&![m[@"kind"] isEqual:@"audio"]) continue;
        [result addObject:m];
    }
    NSMutableSet *known=[NSMutableSet setWithArray:[result valueForKey:@"id"]];
    for(NSDictionary *item in [self importedMediaMatching:search type:type]) if(![known containsObject:item[@"id"]]) [result addObject:item];
    return result;
}
static NSArray *Matching(NSArray *entries,NSString *search) {
    if(!search.length) return entries;
    return [entries filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *entry,NSDictionary *bindings){
        (void)bindings; return [(entry[@"name"]?:entry[@"title"]?:entry[@"media"][@"title"]?:@"") localizedStandardContainsString:search];
    }]];
}
static NSDictionary *Link(NSString *kind,NSString *title,NSString *icon) {
    return @{@"type":@"link",@"id":kind,@"name":title,@"destination":@{@"kind":kind},@"iconName":icon};
}
- (NSArray *)entriesAt:(NSString *)kind identifier:(NSString *)identifier sort:(NSString *)sort search:(NSString *)search
                params:(vlc_ml_query_params_t *)p addAction:(NSString **)addAction error:(NSError **)error {
    [self ensureIndex];
    if([kind isEqual:@"homeSection"]) {
        return Matching([self homeSectionEntries:identifier],search);
    }
    BOOL descendingNames=[sort isEqual:@"titleDescending"];
    NSComparator byName=^NSComparisonResult(NSDictionary *a,NSDictionary *b){ NSComparisonResult r=NaturalCompare(a[@"name"],b[@"name"]); return descendingNames?-r:r; };
    if([kind isEqual:@"home"]) {
        if(!search.length) return @[];
        /* Library-wide search: folders, playlists, then every matching media. */
        NSMutableArray *entries=[NSMutableArray array];
        NSMutableArray *folders=[NSMutableArray array];
        for(NSDictionary *folder in _foldersByKey.allValues) if([folder[@"name"] localizedStandardContainsString:search]) [folders addObject:[self folderEntry:folder entryPoint:NO]];
        for(NSDictionary *root in _entryPoints) if([root[@"name"] localizedStandardContainsString:search]&&!_foldersByKey[root[@"key"]]) [folders addObject:[self folderEntry:root entryPoint:YES]];
        [entries addObjectsFromArray:[folders sortedArrayUsingComparator:byName]];
        NSMutableArray *user=[NSMutableArray array]; [self playlists:search user:user network:[NSMutableArray array]];
        [entries addObjectsFromArray:user];
        NSMutableArray *media=[self mediaAt:kind identifier:nil params:p]; [media addObjectsFromArray:[self externalHistoryMatching:search type:VLC_ML_MEDIA_TYPE_UNKNOWN]];
        NSMutableSet *known=[NSMutableSet setWithArray:[media valueForKey:@"id"]];
        for(NSDictionary *item in [self importedMediaMatching:search type:VLC_ML_MEDIA_TYPE_UNKNOWN]) if(![known containsObject:item[@"id"]]) [media addObject:item];
        [entries addObjectsFromArray:MediaEntries(SortedMedia(media,sort))];
        return entries;
    }
    if([kind isEqual:@"videos"]||[kind isEqual:@"songs"]) {
        vlc_ml_media_type_t type=[kind isEqual:@"videos"]?VLC_ML_MEDIA_TYPE_VIDEO:VLC_ML_MEDIA_TYPE_AUDIO;
        *addAction=AddLibraryAction;
        NSMutableArray *entries=[[Matching([self rootFolders:type],search) sortedArrayUsingComparator:byName] mutableCopy];
        if(!search.length) [entries addObjectsFromArray:MediaEntries(SortedImportedMedia([self importedMediaMatching:search type:type],sort,self.store[@"importDates"]))];
        if(search.length) {
            NSMutableArray *media=[self mediaAt:kind identifier:nil params:p]; [media addObjectsFromArray:[self externalHistoryMatching:search type:type]];
            [entries addObjectsFromArray:MediaEntries(SortedMedia(media,sort))];
        }
        return entries;
    }
    if([kind isEqual:@"music"]) {
        *addAction=AddLibraryAction;
        NSMutableArray *entries=[Matching(@[Link(@"songs",@"Songs",@"music"),Link(@"albums",@"Albums",@"album"),
                                            Link(@"artists",@"Artists",@"artist"),Link(@"genres",@"Genres",@"genre")],search) mutableCopy];
        if(search.length) {
            NSMutableArray *media=[self mediaAt:kind identifier:nil params:p]; [media addObjectsFromArray:[self externalHistoryMatching:search type:VLC_ML_MEDIA_TYPE_AUDIO]];
            [entries addObjectsFromArray:MediaEntries(SortedMedia(media,sort))];
        }
        return entries;
    }
    if([kind isEqual:@"network"]) { *addAction=@"addNetworkStream"; return [self networkEntries:search sort:sort]; }
    if([kind isEqual:@"playlists"]) {
        *addAction=@"createPlaylist";
        NSMutableArray *user=[NSMutableArray array]; [self playlists:search user:user network:[NSMutableArray array]];
        if([sort isEqual:@"titleAscending"]||[sort isEqual:@"titleDescending"]) [user sortUsingComparator:byName];
        else if([sort isEqual:@"newestFirst"]) user=[[[user reverseObjectEnumerator] allObjects] mutableCopy];
        return user;
    }
    if([kind isEqual:@"albums"]) {
        NSMutableArray *entries=[NSMutableArray array];
        vlc_ml_album_list_t *list=vlc_ml_list_albums(_ml,p); if(!list) { *error=LE(@"VLC could not read the albums."); return nil; }
        for(size_t i=0;i<list->i_nb_items;i++) [entries addObject:[self albumEntry:&list->p_items[i]]];
        vlc_ml_album_list_release(list); return entries;
    }
    if([kind isEqual:@"artists"]) {
        NSMutableArray *entries=[NSMutableArray array];
        vlc_ml_artist_list_t *list=vlc_ml_list_artists(_ml,p,false); if(!list) { *error=LE(@"VLC could not read the artists."); return nil; }
        for(size_t i=0;i<list->i_nb_items;i++) if(list->p_items[i].i_id>2) [entries addObject:[self artistEntry:&list->p_items[i]]];
        vlc_ml_artist_list_release(list); return entries;
    }
    if([kind isEqual:@"genres"]) {
        NSMutableArray *entries=[NSMutableArray array];
        vlc_ml_genre_list_t *list=vlc_ml_list_genres(_ml,p); if(!list) { *error=LE(@"VLC could not read the genres."); return nil; }
        for(size_t i=0;i<list->i_nb_items;i++) { vlc_ml_genre_t *g=&list->p_items[i]; [entries addObject:@{@"type":@"genre",@"id":LID(g->i_id),@"name":LS(g->psz_name),@"trackCount":@(g->i_nb_tracks)}]; }
        vlc_ml_genre_list_release(list); return entries;
    }
    if([kind isEqual:@"folder"]) {
        int64_t n=NumberID(identifier);
        vlc_ml_folder_t *f=vlc_ml_get_folder(_ml,n);
        if(!f) { *error=LE(@"This folder is no longer in your library."); return nil; }
        NSDictionary *folder=[self folderInfo:f]; BOOL audio=f->i_nb_audio>0; vlc_ml_folder_release(f);
        NSMutableArray *subfolders=[NSMutableArray array];
        for(NSDictionary *child in [self subfolders:n key:folder[@"key"]]) [subfolders addObject:[self folderEntry:child entryPoint:NO]];
        /* "+ Add" where folders can grow: folders of folders, and music folders (Figma "My Songs"). */
        if(subfolders.count||audio) *addAction=AddLibraryAction;
        NSMutableArray *entries=[[Matching(subfolders,search) sortedArrayUsingComparator:byName] mutableCopy];
        NSMutableArray *media=[self mediaAt:kind identifier:identifier params:p];
        if(media) [entries addObjectsFromArray:MediaEntries(SortedMedia(media,sort))];
        return entries;
    }
    NSMutableArray *media=[self mediaAt:kind identifier:identifier params:p];
    if(!media) { *error=LE(@"This part of the library is no longer available."); return nil; }
    return MediaEntries([kind isEqual:@"recent"]?media:SortedMedia(media,sort));
}
- (NSDictionary *)page:(NSDictionary *)arguments allMedia:(BOOL)all error:(NSError **)error {
    NSDictionary *location=arguments[@"location"],*query=arguments[@"query"]?:@{@"sort":arguments[@"sort"]?:@"titleAscending"};
    NSString *kind=location[@"kind"]?:@"home",*identifier=location[@"id"],*sort=query[@"sort"]?:@"titleAscending";
    NSString *search=[query[@"searchText"] isKindOfClass:NSString.class]?[query[@"searchText"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]:@"";
    vlc_ml_query_params_t p=[self params:sort search:search];
    if(all) return [self allMediaAt:kind identifier:identifier sort:sort params:&p error:error];
    NSInteger offset=MAX(0,[query[@"offset"] integerValue]),limit=MAX(0,[query[@"limit"] integerValue]);
    [self dropQueryCachesIfDirty];
    NSString *cacheKey=[NSString stringWithFormat:@"%@/%@/%@/%@",kind,identifier?:@"",sort,search];
    /* Plain collection queries can page in the engine. Watched ordering and
     * composite folder pages use one queue-owned current-query snapshot. */
    BOOL watched=[sort isEqual:@"watchedFirst"]||[sort isEqual:@"unwatchedFirst"];
    if(limit>0&&!watched&&[@[@"album",@"artist",@"genre",@"show",@"recent"] containsObject:kind]) {
        size_t total=0; int64_t n=NumberID(identifier);
        if([kind isEqual:@"album"]) total=vlc_ml_count_album_tracks(_ml,&p,n);
        else if([kind isEqual:@"artist"]) total=vlc_ml_count_artist_tracks(_ml,&p,n);
        else if([kind isEqual:@"genre"]) total=vlc_ml_count_genre_tracks(_ml,&p,n);
        else if([kind isEqual:@"show"]) total=vlc_ml_count_show_episodes(_ml,&p,n);
        else total=vlc_ml_count_history(_ml,&p,VLC_ML_HISTORY_TYPE_GLOBAL);
        p.i_offset=(uint32_t)MIN(offset,UINT32_MAX); p.i_nbResults=(uint32_t)MIN(limit,UINT32_MAX);
        return @{@"entries":MediaEntries([self mediaAt:kind identifier:identifier params:&p]),@"totalCount":@(total)};
    }
    NSString *addAction=nil;
    NSArray *entries=nil;
    if([cacheKey isEqual:_pageCacheKey]) { entries=_pageCacheEntries; addAction=_pageCacheAddAction; }
    else { entries=[self entriesAt:kind identifier:identifier sort:sort search:search params:&p addAction:&addAction error:error];
        _pageCacheKey=entries?cacheKey:nil; _pageCacheEntries=entries; _pageCacheAddAction=addAction;
    }
    if(!entries) return nil;
    NSUInteger total=entries.count,start=MIN((NSUInteger)offset,total),count=limit?MIN((NSUInteger)limit,total-start):total-start;
    NSMutableDictionary *result=[@{@"entries":[entries subarrayWithRange:NSMakeRange(start,count)],@"totalCount":@(total)} mutableCopy];
    if(addAction) result[@"addAction"]=addAction;
    return result;
}
- (NSDictionary *)allMediaAt:(NSString *)kind identifier:(NSString *)identifier sort:(NSString *)sort params:(vlc_ml_query_params_t *)p error:(NSError **)error {
    [self ensureIndex];
    NSMutableArray *media=[NSMutableArray array];
    if([kind isEqual:@"homeSection"]) {
        for(NSDictionary *entry in [self homeSectionEntries:identifier]) if(entry[@"media"]) [media addObject:entry[@"media"]];
    } else if([kind isEqual:@"network"]) {
        for(NSDictionary *stream in [self networkEntries:nil sort:sort]) [media addObjectsFromArray:[self mediaAt:@"stream" identifier:stream[@"id"] params:p]?:@[]];
    } else if([kind isEqual:@"folder"]) {
        /* Play/enqueue a folder: its media, then each subfolder's, depth first. */
        vlc_ml_folder_t *f=vlc_ml_get_folder(_ml,NumberID(identifier));
        if(!f) { *error=LE(@"This folder is no longer in your library."); return nil; }
        NSString *key=FolderKey(LS(f->psz_mrl)); vlc_ml_folder_release(f);
        NSArray *keys=[[_foldersByKey.allKeys filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF BEGINSWITH %@",key]]
                       sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b){ return NaturalCompare(a,b); }];
        for(NSString *folderKey in keys) {
            NSMutableArray *items=[self mediaAt:@"folder" identifier:_foldersByKey[folderKey][@"id"] params:p];
            if(items) [media addObjectsFromArray:SortedMedia(items,sort)];
        }
    } else if([kind isEqual:@"home"]) {
        return @{@"media":@[]};
    } else {
        NSMutableArray *items=[self mediaAt:kind identifier:identifier params:p];
        if(!items) { *error=LE(@"This part of the library is no longer available."); return nil; }
        [media addObjectsFromArray:[kind isEqual:@"recent"]?items:SortedMedia(items,sort)];
    }
    return @{@"media":media};
}

#pragma mark Home and breadcrumbs

/* Home caps each row to the limit the interface sends (LibraryHomeSectionKind.homeLimit)
 * and ranks from the latest HomeRankingWindow plays, so a long history is never
 * bridged just to draw a row. A section's own page ("›") passes no limits: it
 * ranks the whole history, uncapped, in the same order. */
static const uint32_t HomeRankingWindow=200;
static const NSUInteger HomePlaylistScanLimit=200;
static NSUInteger HomeLimit(NSDictionary *limits,NSString *kind) {
    if(!limits) return NSUIntegerMax;
    NSNumber *limit=[limits[kind] isKindOfClass:NSNumber.class]?limits[kind]:nil;
    return limit.integerValue>0?limit.unsignedIntegerValue:NSUIntegerMax;
}
static NSArray *Prefix(NSArray *items,NSUInteger limit) { return items.count>limit?[items subarrayWithRange:NSMakeRange(0,limit)]:items; }
- (NSArray *)homeSections:(NSDictionary *)limits {
    [self dropQueryCachesIfDirty];
    BOOL capped=limits!=nil;
    if(capped&&_homeCache&&[_homeCacheLimits isEqual:limits]) return _homeCache;
    [self ensureIndex];
    NSMutableArray *sections=[NSMutableArray array];
    vlc_ml_query_params_t p=vlc_ml_query_params_create(); p.i_nbResults=capped?HomeRankingWindow:0;
    NSArray *history=[self mediaList:vlc_ml_list_history(_ml,&p,VLC_ML_HISTORY_TYPE_GLOBAL)];
    /* Only bridge the media a row shows: the progress and artist come from the engine records. */
    NSMutableArray *continuing=[NSMutableArray array]; NSUInteger continuingLimit=HomeLimit(limits,@"continueWatching");
    vlc_ml_media_list_t *videoHistory=vlc_ml_list_video_history(_ml,&p);
    if(videoHistory) { for(size_t i=0;i<videoHistory->i_nb_items&&continuing.count<continuingLimit;i++) {
        const vlc_ml_media_t *m=&videoHistory->p_items[i];
        if(m->f_progress>0&&m->f_progress<1) [continuing addObject:[self media:m]];
    } vlc_ml_media_list_release(videoHistory); }
    if(continuing.count) [sections addObject:@{@"kind":@"continueWatching",@"entries":MediaEntries(continuing),@"destination":@{@"kind":@"homeSection",@"id":@"continueWatching"}}];
    vlc_ml_media_list_t *audioHistory=vlc_ml_list_audio_history(_ml,&p);
    NSMutableArray *audio=[NSMutableArray array]; NSUInteger audioLimit=HomeLimit(limits,@"listenAgain");
    if(audioHistory) for(size_t i=0;i<audioHistory->i_nb_items&&audio.count<audioLimit;i++) [audio addObject:[self media:&audioHistory->p_items[i]]];
    if(audio.count) [sections addObject:@{@"kind":@"listenAgain",@"entries":MediaEntries(audio),@"destination":@{@"kind":@"homeSection",@"id":@"listenAgain"}}];
    /* Folders and artists ranked by how often their media were played recently. */
    NSCountedSet *folderVisits=[NSCountedSet set]; NSMutableArray *folderOrder=[NSMutableArray array];
    for(NSDictionary *m in history) {
        NSString *folder=m[@"folder"][@"id"]; if(!folder) continue;
        if(![folderVisits containsObject:folder]) [folderOrder addObject:folder];
        [folderVisits addObject:folder];
    }
    [folderOrder sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSString *a,NSString *b){ return [@([folderVisits countForObject:b]) compare:@([folderVisits countForObject:a])]; }];
    NSMutableDictionary *foldersByID=[NSMutableDictionary dictionaryWithCapacity:_foldersByKey.count];
    for(NSDictionary *folder in _foldersByKey.allValues) foldersByID[folder[@"id"]]=folder;
    NSMutableArray *folders=[NSMutableArray array]; NSUInteger folderLimit=HomeLimit(limits,@"frequentFolders");
    for(NSString *folderID in folderOrder) {
        if(folders.count>=folderLimit) break;
        NSDictionary *folder=foldersByID[folderID]; if(folder) [folders addObject:[self folderEntry:folder entryPoint:NO]];
    }
    if(folders.count) [sections addObject:@{@"kind":@"frequentFolders",@"entries":folders,@"destination":@{@"kind":@"homeSection",@"id":@"frequentFolders"}}];
    /* Playlists ranked by how many of their items were played recently. The engine
     * has no media-to-playlist query, so compare raw ids without bridging the media. */
    NSMutableSet<NSString *> *played=[NSMutableSet set];
    for(NSDictionary *m in history) [played addObject:m[@"id"]];
    NSMutableArray *user=[NSMutableArray array]; [self playlists:nil user:user network:[NSMutableArray array]];
    NSMutableArray *rankedPlaylists=[NSMutableArray array];
    for(NSDictionary *playlist in Prefix(played.count?user:@[],capped?HomePlaylistScanLimit:NSUIntegerMax)) {
        NSUInteger hits=0; vlc_ml_media_list_t *items=vlc_ml_list_playlist_media(_ml,NULL,NumberID(playlist[@"id"]));
        if(items) { for(size_t i=0;i<items->i_nb_items;i++) if([played containsObject:LID(items->p_items[i].i_id)]) hits++; vlc_ml_media_list_release(items); }
        if(hits) [rankedPlaylists addObject:@[@(hits),playlist]];
    }
    [rankedPlaylists sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSArray *a,NSArray *b){ return [b[0] compare:a[0]]; }];
    NSMutableArray *playlistEntries=[NSMutableArray array];
    for(NSArray *ranked in Prefix(rankedPlaylists,HomeLimit(limits,@"frequentPlaylists"))) [playlistEntries addObject:ranked[1]];
    if(playlistEntries.count) [sections addObject:@{@"kind":@"frequentPlaylists",@"entries":playlistEntries,@"destination":@{@"kind":@"homeSection",@"id":@"frequentPlaylists"}}];
    NSCountedSet *artistPlays=[NSCountedSet set]; NSMutableArray *artistOrder=[NSMutableArray array];
    if(audioHistory) { for(size_t i=0;i<audioHistory->i_nb_items;i++) {
        const vlc_ml_media_t *m=&audioHistory->p_items[i];
        if(m->i_subtype!=VLC_ML_MEDIA_SUBTYPE_ALBUMTRACK||m->album_track.i_artist_id<=2) continue;
        NSNumber *artist=@(m->album_track.i_artist_id);
        if(![artistPlays containsObject:artist]) [artistOrder addObject:artist];
        [artistPlays addObject:artist];
    } vlc_ml_media_list_release(audioHistory); }
    [artistOrder sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSNumber *a,NSNumber *b){ return [@([artistPlays countForObject:b]) compare:@([artistPlays countForObject:a])]; }];
    NSMutableArray *artists=[NSMutableArray array];
    for(NSNumber *artistID in Prefix(artistOrder,HomeLimit(limits,@"frequentArtists"))) {
        vlc_ml_artist_t *artist=vlc_ml_get_artist(_ml,artistID.longLongValue);
        if(artist) { [artists addObject:[self artistEntry:artist]]; vlc_ml_artist_release(artist); }
    }
    if(artists.count) [sections addObject:@{@"kind":@"frequentArtists",@"entries":artists,@"destination":@{@"kind":@"homeSection",@"id":@"frequentArtists"}}];
    /* Seeded defaults only count once they were played: a fresh library's Home stays empty. */
    NSArray *seeded=self.store[@"seededPlaylists"];
    NSArray *streams=[[self networkEntries:nil sort:@"newestFirst"] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *stream,NSDictionary *bindings){
        (void)bindings; return ![seeded containsObject:@(NetworkPlaylistNumber(stream[@"id"]))]||[stream[@"playCount"] unsignedIntValue]>0;
    }]];
    streams=Prefix(streams,HomeLimit(limits,@"latestStreams"));
    if(streams.count) [sections addObject:@{@"kind":@"latestStreams",@"entries":streams,@"destination":@{@"kind":@"homeSection",@"id":@"latestStreams"}}];
    if(!capped) return sections;
    _homeCache=[sections copy]; _homeCacheLimits=[limits copy]; return _homeCache;
}
/* One section of the uncapped ranking: what a Home row's "›" page lists. */
- (NSArray *)homeSectionEntries:(NSString *)kind {
    for(NSDictionary *section in [self homeSections:nil]) if([section[@"kind"] isEqual:kind]) return section[@"entries"];
    return @[];
}
static NSDictionary *Crumb(NSString *title,NSString *kind,NSString *identifier) {
    return @{@"title":title,@"location":identifier?@{@"kind":kind,@"id":identifier}:@{@"kind":kind}};
}
- (NSArray *)breadcrumb:(NSDictionary *)location {
    [self ensureIndex];
    NSString *kind=location[@"kind"]?:@"home",*identifier=location[@"id"]; int64_t n=NumberID(identifier);
    if([kind isEqual:@"homeSection"]) {
        NSDictionary *titles=@{@"continueWatching":@"Continue Watching",@"listenAgain":@"Listen Again",@"frequentFolders":@"Frequently Visited Folders",@"frequentPlaylists":@"Frequently Visited Playlists",@"frequentArtists":@"Frequently Listened Artists",@"latestStreams":@"Latest Streams"};
        return @[Crumb(@"Home",@"home",nil),Crumb(titles[identifier]?:@"Home",kind,identifier)];
    }
    NSDictionary *roots=@{@"home":@"Home",@"videos":@"Videos",@"music":@"Music",@"network":@"Network",@"playlists":@"Playlists",@"recent":@"Recent"};
    if(roots[kind]) return @[Crumb(roots[kind],kind,nil)];
    NSDictionary *music=Crumb(@"Music",@"music",nil);
    NSDictionary *musicPages=@{@"songs":@"Songs",@"albums":@"Albums",@"artists":@"Artists",@"genres":@"Genres"};
    if(musicPages[kind]) return @[music,Crumb(musicPages[kind],kind,nil)];
    if([kind isEqual:@"album"]) {
        vlc_ml_album_t *a=vlc_ml_get_album(_ml,n); NSString *title=a?LS(a->psz_title):@"Album"; if(a) vlc_ml_album_release(a);
        return @[music,Crumb(@"Albums",@"albums",nil),Crumb(title,kind,identifier)];
    }
    if([kind isEqual:@"artist"]) return @[music,Crumb(@"Artists",@"artists",nil),Crumb([self artist:n]?:@"Artist",kind,identifier)];
    if([kind isEqual:@"genre"]) return @[music,Crumb(@"Genres",@"genres",nil),Crumb([self genre:n]?:@"Genre",kind,identifier)];
    if([kind isEqual:@"playlist"]||[kind isEqual:@"stream"]) {
        vlc_ml_playlist_t *p=vlc_ml_get_playlist(_ml,n); NSString *title=p?LS(p->psz_name):[kind isEqual:@"stream"]?@"Stream":@"Playlist"; if(p) vlc_ml_playlist_release(p);
        return @[Crumb([kind isEqual:@"stream"]?@"Network":@"Playlists",[kind isEqual:@"stream"]?@"network":@"playlists",nil),Crumb(title,kind,identifier)];
    }
    if([kind isEqual:@"show"]) {
        vlc_ml_show_t *s=vlc_ml_get_show(_ml,n); NSString *title=s?LS(s->psz_name):@"Show"; if(s) vlc_ml_show_release(s);
        return @[Crumb(@"Videos",@"videos",nil),Crumb(title,kind,identifier)];
    }
    if([kind isEqual:@"folder"]) {
        NSArray *chain=[self folderChain:n];
        NSString *key=chain.lastObject[@"key"];
        BOOL audio=key&&![self folder:key contains:VLC_ML_MEDIA_TYPE_VIDEO]&&[self folder:key contains:VLC_ML_MEDIA_TYPE_AUDIO];
        NSMutableArray *crumbs=[(audio?@[music,Crumb(@"Songs",@"songs",nil)]:@[Crumb(@"Videos",@"videos",nil)]) mutableCopy];
        for(NSDictionary *folder in chain) [crumbs addObject:Crumb(folder[@"name"],@"folder",folder[@"id"])];
        return crumbs;
    }
    return @[Crumb(@"Home",@"home",nil)];
}
- (NSArray *)bookmarks:(int64_t)mediaID {
    NSMutableArray *result=[NSMutableArray array]; vlc_ml_bookmark_list_t *list=vlc_ml_list_media_bookmarks(_ml,NULL,mediaID);
    if(list) { for(size_t i=0;i<list->i_nb_items;i++) { vlc_ml_bookmark_t *b=&list->p_items[i];
        [result addObject:@{@"id":[NSString stringWithFormat:@"%lld",(long long)b->i_time],@"mediaID":LID(mediaID),@"name":LS(b->psz_name),@"time":@(b->i_time*1000)}]; }
        vlc_ml_bookmark_list_release(list); }
    return result;
}
- (int64_t)resolveMedia:(NSString *)identifier import:(BOOL)import {
    if(![identifier isKindOfClass:NSString.class]) return 0;
    if([identifier hasPrefix:@"ml:"]) return NumberID(identifier);
    if(![identifier containsString:@":"]) return NumberID(identifier);
    vlc_ml_media_t *media=vlc_ml_get_media_by_mrl(_ml,identifier.UTF8String);
    if(!media && import) media=IsNetworkMRL(identifier)?vlc_ml_new_stream(_ml,identifier.UTF8String):vlc_ml_new_external_media(_ml,identifier.UTF8String);
    int64_t id=media?media->i_id:0; if(media) vlc_ml_media_release(media); return id;
}

#pragma mark Requests

- (NSDictionary *)execute:(MXRBridgeRequest)request arguments:(NSDictionary *)args error:(NSError **)error {
    if([request isEqual:MXRBridgeRequestPage]||[request isEqual:MXRBridgeRequestAllMedia]) return [self page:args allMedia:[request isEqual:MXRBridgeRequestAllMedia] error:error];
    if([request isEqual:MXRBridgeRequestMedia]) {
        [self ensureIndex];
        int64_t id=[self resolveMedia:args[@"id"] import:NO]; vlc_ml_media_t *media=id?vlc_ml_get_media(_ml,id):NULL;
        if(!media) { *error=LE(@"This item is no longer in your library."); return nil; }
        NSDictionary *result=@{@"media":[self media:media]}; vlc_ml_media_release(media); return result;
    }
    if([request isEqual:MXRBridgeRequestSetThumbnailSize]) {
        /* The largest card the interface draws, in pixels; applies to thumbnails requested from now on. */
        unsigned w=[args[@"width"] unsignedIntValue],h=[args[@"height"] unsignedIntValue];
        if(w>=16&&h>=16&&w<=4096&&h<=4096) { _thumbnailWidth=w; _thumbnailHeight=h; }
        return @{};
    }
    if([request isEqual:MXRBridgeRequestHomeSections]) {
        NSDictionary *limits=[args[@"limits"] isKindOfClass:NSDictionary.class]?args[@"limits"]:@{};
        return @{@"sections":[self homeSections:limits]};
    }
    if([request isEqual:MXRBridgeRequestBreadcrumb]) return @{@"crumbs":[self breadcrumb:args[@"location"]?:@{@"kind":@"home"}]};
    atomic_store(&_queryDirty,true);
    int ret=VLC_SUCCESS; NSDictionary *result=@{};
    int64_t mediaID=[self resolveMedia:args[@"mediaID"] import:NO],id=NumberID(args[@"id"]);
    if([request isEqual:MXRBridgeRequestBookmarks]) return @{@"bookmarks":[self bookmarks:mediaID]};
    if([request isEqual:MXRBridgeRequestAddBookmark]) {
        int64_t ms=[args[@"time"] longLongValue]/1000; if(!mediaID||ms<0) ret=VLC_EINVAL;
        else { ret=vlc_ml_media_add_bookmark(_ml,mediaID,ms); if(ret==VLC_SUCCESS) ret=vlc_ml_media_update_bookmark(_ml,mediaID,ms,[args[@"name"] UTF8String],""); }
        result=@{@"bookmark":@{@"id":[NSString stringWithFormat:@"%lld",(long long)ms],@"mediaID":LID(mediaID),@"name":args[@"name"]?:@"",@"time":@(ms*1000)}};
    } else if([request isEqual:MXRBridgeRequestRenameBookmark]) ret=mediaID?vlc_ml_media_update_bookmark(_ml,mediaID,[args[@"id"] longLongValue],[args[@"name"] UTF8String],""):VLC_EINVAL;
    else if([request isEqual:MXRBridgeRequestRemoveBookmark]) ret=mediaID?vlc_ml_media_remove_bookmark(_ml,mediaID,[args[@"id"] longLongValue]):VLC_EINVAL;
    else if([request isEqual:MXRBridgeRequestSetFavorite]||[request isEqual:MXRBridgeRequestSetWatched]) {
        for(NSString *identifier in args[@"mediaIDs"]) {
            int64_t n=[self resolveMedia:identifier import:NO]; if(!n) { ret=VLC_EINVAL; break; }
            ret=[request isEqual:MXRBridgeRequestSetFavorite]?vlc_ml_media_set_favorite(_ml,n,[args[@"value"] boolValue]):vlc_ml_media_set_played(_ml,n,[args[@"value"] boolValue]); if(ret!=VLC_SUCCESS) break;
        }
    } else if([request isEqual:MXRBridgeRequestAttachSubtitle]||[request isEqual:MXRBridgeRequestAttachAudioTrack]) {
        /* Add Subtitles and Edit/Add Audio Tracks: the file becomes a track of every later playback. */
        NSString *url=args[@"url"];
        ret=mediaID&&[url isKindOfClass:NSString.class]&&url.length?vlc_ml_control(_ml,VLC_ML_MEDIA_ADD_EXTERNAL_MRL,mediaID,url.UTF8String,
            [request isEqual:MXRBridgeRequestAttachAudioTrack]?VLC_ML_FILE_TYPE_SOUNDTRACK:VLC_ML_FILE_TYPE_SUBTITLE):VLC_EINVAL;
    }
    else if([request isEqual:MXRBridgeRequestClearHistory]) ret=vlc_ml_clear_history(_ml,VLC_ML_HISTORY_TYPE_GLOBAL);
    else if([request isEqual:MXRBridgeRequestImportFiles]) {
        NSArray *urls=args[@"urls"];
        if(![urls isKindOfClass:NSArray.class]||!urls.count) ret=VLC_EINVAL;
        for(NSString *value in (ret==VLC_SUCCESS?urls:@[])) {
            NSURL *url=[value isKindOfClass:NSString.class]?[NSURL URLWithString:value]:nil; BOOL directory=NO;
            if(!url.isFileURL||![NSFileManager.defaultManager fileExistsAtPath:url.path isDirectory:&directory]||directory||![NSFileManager.defaultManager isReadableFileAtPath:url.path]) ret=VLC_EINVAL;
        }
        NSArray *kinds=[args[@"kinds"] isKindOfClass:NSArray.class]&&[args[@"kinds"] count]==urls.count?args[@"kinds"]:nil;
        NSMutableArray *importedItems=[NSMutableArray array];
        if(ret==VLC_SUCCESS) for(NSUInteger i=0;i<urls.count;i++) {
            int64_t media=[self resolveMedia:urls[i] import:YES];
            if(!media) { ret=VLC_EGENERIC; break; }
            vlc_ml_media_t *record=vlc_ml_get_media(_ml,media);
            /* VLC types a file only when it parses it; until then use the interface's classification. */
            if(record&&record->i_type==VLC_ML_MEDIA_TYPE_UNKNOWN&&kinds) {
                NSString *kind=kinds[i];
                if([kind isEqual:@"audio"]||[kind isEqual:@"video"]) {
                    vlc_ml_media_set_type(_ml,media,[kind isEqual:@"audio"]?VLC_ML_MEDIA_TYPE_AUDIO:VLC_ML_MEDIA_TYPE_VIDEO);
                    vlc_ml_media_release(record); record=vlc_ml_get_media(_ml,media);
                }
            }
            if(record) { [importedItems addObject:[self media:record]]; vlc_ml_media_release(record); }
            NSMutableArray *imported=self.store[@"importedMedia"];
            if(![imported containsObject:LID(media)]) {
                [imported addObject:LID(media)]; self.store[@"importDates"][LID(media)]=@(NSDate.date.timeIntervalSince1970);
            }
        }
        if(ret==VLC_SUCCESS) { [self saveStore]; result=@{@"media":importedItems}; }
        [self markStale];
    }
    else if([request isEqual:MXRBridgeRequestAddFolder]) { ret=vlc_ml_add_folder(_ml,[args[@"url"] UTF8String]); [self markStale]; }
    else if([request isEqual:MXRBridgeRequestRemoveFolder]) { vlc_ml_folder_t *f=vlc_ml_get_folder(_ml,id); if(!f) ret=VLC_EINVAL; else { ret=vlc_ml_remove_folder(_ml,f->psz_mrl); vlc_ml_folder_release(f); } [self markStale]; }
    else if([request isEqual:MXRBridgeRequestRescan]) {
        NSString *folderID=args[@"folderID"]?:args[@"id"]; vlc_ml_folder_t *f=folderID.length?vlc_ml_get_folder(_ml,NumberID(folderID)):NULL;
        ret=folderID.length&&!f?VLC_EINVAL:vlc_ml_reload_folder(_ml,f?f->psz_mrl:NULL); if(f) vlc_ml_folder_release(f);
    } else if([request isEqual:MXRBridgeRequestSetPlaylistFavorite]) ret=vlc_ml_playlist_set_favorite(_ml,id,[args[@"value"] boolValue]);
    else if([request isEqual:MXRBridgeRequestDeletePlaylist]) {
        ret=vlc_ml_playlist_delete(_ml,id);
        if(ret==VLC_SUCCESS) { NSURL *art=[self artworkForPlaylist:id]; if(art) [NSFileManager.defaultManager removeItemAtURL:art error:nil]; }
    } else if([request isEqual:MXRBridgeRequestRenamePlaylist]) ret=vlc_ml_playlist_rename(_ml,id,[args[@"name"] UTF8String]);
    else if([request isEqual:MXRBridgeRequestRemoveFromPlaylist]) {
        NSArray *positions=[[NSSet setWithArray:args[@"positions"]?:@[]].allObjects sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a,NSNumber *b){ return [b compare:a]; }];
        BOOL complete=NO; NSArray *current=[self playlistMedia:id complete:&complete];
        if(current&&!complete) { *error=LE(@"Some items in this playlist are on a disconnected drive. Reconnect it to remove items."); return nil; }
        NSString *revision=current?PlaylistRevision(current):nil;
        if(!positions.count||![args[@"revision"] isKindOfClass:NSString.class]||![revision isEqual:args[@"revision"]]) ret=VLC_EINVAL;
        for(NSNumber *position in positions) if(![position isKindOfClass:NSNumber.class]||position.longLongValue<0||position.unsignedLongLongValue>=current.count) ret=VLC_EINVAL;
        if(ret==VLC_SUCCESS) for(NSNumber *position in positions) {
            ret=vlc_ml_playlist_remove(_ml,id,position.unsignedIntValue,1); if(ret!=VLC_SUCCESS) break;
        }
    } else if([request isEqual:MXRBridgeRequestCreatePlaylist]||[request isEqual:MXRBridgeRequestAppendToPlaylist]) {
        NSArray *identifiers=args[@"mediaIDs"]?:@[]; int64_t *ids=vlc_alloc(MAX(1u,identifiers.count),sizeof(*ids));
        if(!ids) ret=VLC_ENOMEM;
        else { for(NSUInteger i=0;i<identifiers.count;i++) { ids[i]=[self resolveMedia:identifiers[i] import:YES]; if(!ids[i]) { ret=VLC_EINVAL; break; } }
            vlc_ml_playlist_t *created=NULL;
            if(ret==VLC_SUCCESS && [request isEqual:MXRBridgeRequestCreatePlaylist]) { created=vlc_ml_playlist_create(_ml,[args[@"name"] UTF8String]); if(!created) ret=VLC_EGENERIC; else id=created->i_id; }
            if(ret==VLC_SUCCESS && identifiers.count) ret=vlc_ml_playlist_append(_ml,id,ids,identifiers.count);
            if(created) {
                if(ret!=VLC_SUCCESS) vlc_ml_playlist_delete(_ml,id);
                else {
                    /* §11 New Playlist: "saved and displayed with this title and thumbnail". */
                    if([args[@"artworkURL"] isKindOfClass:NSString.class]) [self setArtwork:args[@"artworkURL"] forPlaylist:id];
                    vlc_ml_playlist_t *p=vlc_ml_get_playlist(_ml,id); result=@{@"playlist":[self playlistEntry:p?:created]}; if(p) vlc_ml_playlist_release(p);
                }
                vlc_ml_playlist_release(created);
            }
            free(ids);
        }
    } else if([request isEqual:MXRBridgeRequestAddNetworkStream]) {
        /* The expanded items were resolved off this queue by -request:. */
        NSArray *items=args[@"items"]; NSString *name=[args[@"name"] isKindOfClass:NSString.class]?[args[@"name"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]:nil;
        if(!name.length) {
            NSURL *first=[NSURL URLWithString:[args[@"urls"] firstObject]];
            name=first.URLByDeletingPathExtension.lastPathComponent.length&&![first.lastPathComponent isEqual:@"/"]?[first.URLByDeletingPathExtension.lastPathComponent stringByRemovingPercentEncoding]:first.host;
            if(!name.length) name=@"Network Stream";
        }
        return [self saveNetworkItems:items name:name error:error];
    } else if([request isEqual:MXRBridgeRequestRemoveNetworkStream]) {
        int64_t playlistID=NetworkPlaylistNumber(args[@"id"]);
        ret=playlistID?vlc_ml_playlist_delete(_ml,playlistID):vlc_ml_remove_stream(_ml,id);
        if(ret==VLC_SUCCESS&&playlistID) { [self.networkPlaylistIDs removeObject:@(playlistID)]; [self saveStore]; }
    } else if([request isEqual:MXRBridgeRequestRenameNetworkStream]) {
        int64_t playlistID=NetworkPlaylistNumber(args[@"id"]);
        ret=playlistID?vlc_ml_playlist_rename(_ml,playlistID,[args[@"name"] UTF8String]):VLC_EINVAL;
    }
    else { *error=LE([NSString stringWithFormat:@"Library operation %@ is unavailable.",request]); return nil; }
    if(ret!=VLC_SUCCESS) { *error=LE(@"The library could not complete this change. The item may have been removed."); return nil; }
    return result;
}
- (void)request:(MXRBridgeRequest)request arguments:(NSDictionary *)arguments completion:(void (^)(NSDictionary * _Nullable,NSError * _Nullable))completion {
    if(!self.available||atomic_load(&_stopped)) { completion(nil,LE(@"The VLC media library is unavailable.")); return; }
    NSString *operation=[request copy]; NSDictionary *args=[arguments copy];
    void (^run)(NSDictionary *)=^(NSDictionary *input){
        dispatch_async(self->_queue,^{ @autoreleasepool {
            NSError *error=nil; NSDictionary *result=atomic_load(&self->_stopped)?nil:[self execute:operation arguments:input error:&error];
            dispatch_async(dispatch_get_main_queue(),^{
                if(atomic_load(&self->_stopped)) { completion(nil,LE(@"The VLC media library is shutting down.")); return; }
                completion(result,error);
                NSSet *reads=[NSSet setWithArray:@[@"page",@"allMedia",@"media",@"homeSections",@"breadcrumb",@"bookmarks",@"setThumbnailSize"]];
                if(!error && ![reads containsObject:operation]) {
                    BOOL stale=[self invalidateMedia:[NSSet set] everything:YES unknown:YES]>0;
                    /* A write changes content; do not replay the last burst's thumbnail ids. */
                    self->_publishedThumbnails=@[]; self->_publishedContentChanged=YES;
                    if(stale&&self.serviceChanged) self.serviceChanged(MXRBridgeServiceMediaStale);
                    if(self.serviceChanged) self.serviceChanged(MXRBridgeServiceLibrary);
                }
            });
        }});
    };
    if([operation isEqual:@"addNetworkStream"]) {
        /* Validate the whole collection before any persistent operation, then
         * expand playlist URLs off the library queue (they open the network). */
        NSArray *urls=args[@"urls"];
        BOOL valid=[urls isKindOfClass:NSArray.class]&&urls.count&&(!args[@"name"]||[args[@"name"] isKindOfClass:NSString.class]);
        for(id value in valid?urls:@[]) if(![value isKindOfClass:NSString.class]||!IsNetworkMRL(value)) valid=NO;
        if(!valid) { completion(nil,LE(@"Enter at least one network address, such as https://example.com/stream.m3u.")); return; }
        /* Register ownership before dispatch: shutdown cannot delete the parser while
         * an accepted worker has not reached Submit yet. */
        @synchronized(self) {
            if(atomic_load(&_stopped)) { completion(nil,LE(@"The library is closing.")); return; }
            dispatch_group_enter(_expansionWorkers);
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{ @autoreleasepool {
            @try {
                if(!atomic_load(&self->_stopped)) {
                    NSMutableDictionary *input=[args mutableCopy]; input[@"items"]=[self expandNetworkURLs:urls];
                    run(input);
                } else run(args);
            } @finally { dispatch_group_leave(self->_expansionWorkers); }
        }});
        return;
    }
    run(args);
}
@end
