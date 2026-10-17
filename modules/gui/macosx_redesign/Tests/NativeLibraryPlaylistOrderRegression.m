/* Native playlist page and removal fixture. Uses the production page/execute
 * logic; the first part scripts the engine listing (-playlistMedia:complete:), the second
 * runs the real -playlistMedia:complete: against a scripted media library (vlc_ml_get /
 * vlc_ml_list), so its stored/present/listed comparison is exercised too. */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdarg.h>
#import "../module/bridge/MXRLibraryServices.h"
#import "MXRBridgeKeys.h"
#include <vlc_media_library.h>

@interface MXRLibraryServices (PlaylistOrderFixture)
- (void)ensureIndex;
- (NSURL *)storeDirectory;
- (NSMutableArray *)playlistMedia:(int64_t)playlistID complete:(BOOL *)complete;
- (NSDictionary *)page:(NSDictionary *)arguments allMedia:(BOOL)all error:(NSError **)error;
- (NSDictionary *)execute:(MXRBridgeRequest)request arguments:(NSDictionary *)args error:(NSError **)error;
@end
@interface PlaylistOrderFixture : MXRLibraryServices
@property(nonatomic,strong) NSArray *storage;
@property(nonatomic) BOOL complete;
@end
@implementation PlaylistOrderFixture
- (void)ensureIndex {}
- (NSMutableArray *)playlistMedia:(int64_t)playlistID complete:(BOOL *)complete {
    (void)playlistID; *complete=self.complete; return [self.storage mutableCopy];
}
@end

/* The scripted media library: one playlist of `fakeStored` items, `fakePresent` of them on a
 * mounted drive, of which the listing returns `fakeListed`. */
static unsigned fakeStored,fakePresent; static size_t fakeListed; static int engineCalls;
void *vlc_ml_get(vlc_medialibrary_t *ml,int query,...) {
    (void)ml; engineCalls++;
    if(query!=VLC_ML_GET_PLAYLIST) return NULL;
    vlc_ml_playlist_t *playlist=calloc(1,sizeof *playlist);
    playlist->i_nb_media=fakeStored; playlist->i_nb_present_media=fakePresent;
    return playlist;
}
int vlc_ml_list(vlc_medialibrary_t *ml,int query,const vlc_ml_query_params_t *params,...) {
    (void)ml; (void)params; engineCalls++;
    if(query!=VLC_ML_LIST_PLAYLIST_MEDIA) return VLC_EGENERIC;
    va_list ap; va_start(ap,params); (void)va_arg(ap,int64_t); vlc_ml_media_list_t **out=va_arg(ap,vlc_ml_media_list_t **); va_end(ap);
    vlc_ml_media_list_t *list=calloc(1,sizeof *list+fakeListed*sizeof(vlc_ml_media_t));
    list->i_nb_items=fakeListed;
    for(size_t i=0;i<fakeListed;i++) { list->p_items[i].i_id=(int64_t)i+1; list->p_items[i].psz_title=(char *)(i%2?"Alpha":"Bravo"); }
    *out=list; return VLC_SUCCESS;
}
void vlc_ml_playlist_release(vlc_ml_playlist_t *playlist) { free(playlist); }
void vlc_ml_media_list_release(vlc_ml_media_list_t *list) { free(list); }
@interface EngineListingFixture : MXRLibraryServices
@end
@implementation EngineListingFixture
- (void)ensureIndex {}
/* No user data dir without a VLC instance: an empty store in a fresh temporary directory. */
- (NSURL *)storeDirectory {
    static NSURL *directory;
    if(!directory) {
        directory=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
        [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return directory;
}
@end
static BOOL EngineComplete(EngineListingFixture *service,unsigned stored,unsigned present,size_t listed,NSUInteger *count) {
    fakeStored=stored; fakePresent=present; fakeListed=listed;
    BOOL complete=YES; NSArray *items=[service playlistMedia:7 complete:&complete];
    *count=items.count; return complete;
}

static int failures,assertions;
static void Expect(NSString *name,BOOL ok,NSString *detail) {
    assertions++;
    if(!ok) { failures++; fprintf(stderr,"FAIL %s: %s\n",name.UTF8String,detail.UTF8String); }
}
static NSArray *Page(PlaylistOrderFixture *service,NSString *sort) {
    NSError *error=nil;
    NSDictionary *page=[service page:@{@"location":@{@"kind":@"playlist",@"id":@"ml:7"},@"query":@{@"sort":sort,@"offset":@0,@"limit":@100}} allMedia:NO error:&error];
    if(error) { failures++; fprintf(stderr,"FAIL page %s: %s\n",sort.UTF8String,error.localizedDescription.UTF8String); }
    NSMutableArray *media=[NSMutableArray array];
    for(NSDictionary *entry in page[@"entries"]) [media addObject:entry[@"media"]];
    return media;
}
static NSArray *Titles(NSArray *media) { return [media valueForKey:@"title"]; }

int main(void) { @autoreleasepool {
    /* "Alpha" was indexed first (lower id) but the user put "Bravo" first. */
    NSDictionary *alpha=@{@"id":@"ml:1",@"title":@"Alpha",@"url":@"file:///Alpha.mp4",@"playCount":@0};
    NSDictionary *bravo=@{@"id":@"ml:2",@"title":@"Bravo",@"url":@"file:///Bravo.mp4",@"playCount":@0};
    PlaylistOrderFixture *service=[PlaylistOrderFixture new]; service.storage=@[bravo,alpha]; service.complete=YES;

    NSArray *oldest=Page(service,@"oldestFirst");
    Expect(@"default sort keeps the playlist order",[Titles(oldest) isEqual:(@[@"Bravo",@"Alpha"])],[Titles(oldest) description]);
    NSArray *newest=Page(service,@"newestFirst");
    Expect(@"newest first reverses the playlist order",[Titles(newest) isEqual:(@[@"Alpha",@"Bravo"])],[Titles(newest) description]);
    NSArray *byTitle=Page(service,@"titleAscending");
    Expect(@"title sort orders by title",[Titles(byTitle) isEqual:(@[@"Alpha",@"Bravo"])],[Titles(byTitle) description]);
    Expect(@"rows keep their storage positions under any sort",
           [[newest valueForKeyPath:@"playlistOccurrence.position"] isEqual:(@[@1,@0])],[[newest valueForKeyPath:@"playlistOccurrence.position"] description]);
    NSString *revision=oldest.firstObject[@"playlistOccurrence"][@"revision"];
    Expect(@"complete playlists carry a revision",revision.length>0,@"no revision");

    /* A stale revision is refused before any engine call. */
    NSError *error=nil;
    NSDictionary *result=[service execute:MXRBridgeRequestRemoveFromPlaylist arguments:@{@"id":@"ml:7",@"positions":@[@0],@"revision":@"stale"} error:&error];
    Expect(@"stale revision is refused",result==nil&&error!=nil,@"stale removal accepted");

    /* An item on a disconnected drive is not listed, so listed rows are not
     * storage positions: rows carry no occurrence and removal is refused. */
    service.complete=NO;
    NSArray *partial=Page(service,@"oldestFirst");
    Expect(@"partial playlists offer no positions",[partial indexesOfObjectsPassingTest:^BOOL(NSDictionary *m,NSUInteger i,BOOL *stop){ (void)i; (void)stop; return m[@"playlistOccurrence"]!=nil; }].count==0,
           [partial description]);
    error=nil;
    result=[service execute:MXRBridgeRequestRemoveFromPlaylist arguments:@{@"id":@"ml:7",@"positions":@[@0],@"revision":revision} error:&error];
    Expect(@"partial playlist removal is refused",result==nil&&[error.localizedDescription containsString:@"disconnected drive"],error.localizedDescription?:@"accepted");

    /* The real comparison against the engine's counts. */
    EngineListingFixture *engine=[EngineListingFixture new];
    Ivar mlIvar=class_getInstanceVariable(MXRLibraryServices.class,"_ml");
    *(void **)((__bridge void *)engine+ivar_getOffset(mlIvar))=(void *)0x1;
    NSUInteger listed=0;
    Expect(@"every item present and listed is complete",EngineComplete(engine,3,3,3,&listed)&&listed==3,@"not complete");
    Expect(@"an item on a disconnected drive makes the listing partial",!EngineComplete(engine,3,2,2,&listed)&&listed==2,@"reported complete");
    Expect(@"a listing shorter than the stored count is partial",!EngineComplete(engine,3,3,2,&listed),@"reported complete");
    Expect(@"the engine was asked",engineCalls>=6,[NSString stringWithFormat:@"%d engine calls",engineCalls]);
    engineCalls=0;
    fakeStored=2; fakePresent=1; fakeListed=1;
    error=nil;
    NSDictionary *page=[engine page:@{@"location":@{@"kind":@"playlist",@"id":@"ml:7"},@"query":@{@"sort":@"oldestFirst",@"offset":@0,@"limit":@100}} allMedia:NO error:&error];
    NSArray *rows=[page[@"entries"] valueForKey:@"media"];
    Expect(@"an unmounted item's playlist page offers no positions",rows.count==1&&rows.firstObject[@"playlistOccurrence"]==nil,
           [NSString stringWithFormat:@"%@ %@",rows,error]);

    if(!failures) printf("PASS: native playlist order and removal guards (%d assertions)\n",assertions);
    return failures?1:0;
} }
