/* Native title-order fixture (R03). The media library sorts titles with SQLite's NOCASE
 * collation ("Episode 10" before "Episode 2", only ASCII case folded); the production
 * page/entriesAt logic must re-sort title-sorted folder, search and collection pages the
 * way the Finder does, before slicing pages. The engine listing (-mediaAt:identifier:params:)
 * is scripted in the engine's own order; vlc_ml_get / vlc_ml_list answer the folder record,
 * the Music collections and count the engine's paged queries. */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdarg.h>
#import "../module/bridge/MXRLibraryServices.h"
#include <vlc_media_library.h>

@interface MXRLibraryServices (NaturalSortFixture)
- (void)ensureIndex;
- (NSArray *)subfolders:(int64_t)folderID key:(NSString *)key;
- (NSArray *)rootFolders:(vlc_ml_media_type_t)type;
- (NSMutableArray *)mediaAt:(NSString *)kind identifier:(NSString *)identifier params:(vlc_ml_query_params_t *)p;
- (NSArray *)externalHistoryMatching:(NSString *)search type:(vlc_ml_media_type_t)type;
- (NSArray *)importedMediaMatching:(NSString *)search type:(vlc_ml_media_type_t)type;
- (NSDictionary *)page:(NSDictionary *)arguments allMedia:(BOOL)all error:(NSError **)error;
@end
@interface NaturalSortFixture : MXRLibraryServices
/* What the engine answers, in its NOCASE title order. */
@property(nonatomic,strong) NSArray *engine;
/* Imported or directly opened media the search adds after the engine's results. */
@property(nonatomic,strong) NSArray *external;
@end
@implementation NaturalSortFixture
- (void)ensureIndex {}
- (NSArray *)subfolders:(int64_t)folderID key:(NSString *)key { (void)folderID; (void)key; return @[]; }
- (NSArray *)rootFolders:(vlc_ml_media_type_t)type { (void)type; return @[]; }
- (NSMutableArray *)mediaAt:(NSString *)kind identifier:(NSString *)identifier params:(vlc_ml_query_params_t *)p {
    (void)kind; (void)identifier; (void)p; return [[NSMutableArray alloc] initWithArray:self.engine copyItems:NO];
}
- (NSArray *)externalHistoryMatching:(NSString *)search type:(vlc_ml_media_type_t)type { (void)search; (void)type; return self.external?:@[]; }
/* Already part of -externalHistoryMatching:type: here. */
- (NSArray *)importedMediaMatching:(NSString *)search type:(vlc_ml_media_type_t)type { (void)search; (void)type; return @[]; }
@end

static int engineListCalls;
void *vlc_ml_get(vlc_medialibrary_t *ml,int query,...) {
    (void)ml;
    if(query!=VLC_ML_GET_FOLDER) return NULL;
    vlc_ml_folder_t *folder=calloc(1,sizeof *folder);
    folder->i_id=3; folder->psz_name=(char *)"S01"; folder->psz_mrl=(char *)"file:///Shows/S01/"; folder->i_nb_video=4; folder->i_nb_media=4;
    return folder;
}
/* Music ▸ Albums / Artists / Genres in the engine's NOCASE order (artists 1 and 2 are placeholders). */
static const char *collectionNames[]={"Vol. 1","Vol. 10","Vol. 2","Серия 2","серия 1"};
static const size_t collectionCount=sizeof collectionNames/sizeof *collectionNames;
int vlc_ml_list(vlc_medialibrary_t *ml,int query,const vlc_ml_query_params_t *params,...) {
    (void)ml; (void)params;
    va_list ap; va_start(ap,params);
    if(query==VLC_ML_LIST_ARTISTS) (void)va_arg(ap,int);
    void **out=va_arg(ap,void **); va_end(ap);
    if(query==VLC_ML_LIST_ALBUMS) {
        vlc_ml_album_list_t *list=calloc(1,sizeof *list+collectionCount*sizeof(vlc_ml_album_t)); list->i_nb_items=collectionCount;
        for(size_t i=0;i<collectionCount;i++) { list->p_items[i].i_id=(int64_t)i+3; list->p_items[i].psz_title=(char *)collectionNames[i]; }
        *out=list; return VLC_SUCCESS;
    }
    if(query==VLC_ML_LIST_ARTISTS) {
        vlc_ml_artist_list_t *list=calloc(1,sizeof *list+collectionCount*sizeof(vlc_ml_artist_t)); list->i_nb_items=collectionCount;
        for(size_t i=0;i<collectionCount;i++) { list->p_items[i].i_id=(int64_t)i+3; list->p_items[i].psz_name=(char *)collectionNames[i]; }
        *out=list; return VLC_SUCCESS;
    }
    if(query==VLC_ML_LIST_GENRES) {
        vlc_ml_genre_list_t *list=calloc(1,sizeof *list+collectionCount*sizeof(vlc_ml_genre_t)); list->i_nb_items=collectionCount;
        for(size_t i=0;i<collectionCount;i++) { list->p_items[i].i_id=(int64_t)i+3; list->p_items[i].psz_name=(char *)collectionNames[i]; }
        *out=list; return VLC_SUCCESS;
    }
    engineListCalls++; return VLC_EGENERIC;
}
void vlc_ml_album_list_release(vlc_ml_album_list_t *list) { free(list); }
void vlc_ml_artist_list_release(vlc_ml_artist_list_t *list) { free(list); }
void vlc_ml_genre_list_release(vlc_ml_genre_list_t *list) { free(list); }
void vlc_ml_folder_release(vlc_ml_folder_t *folder) { free(folder); }

static int failures,assertions;
static NSDictionary *Media(int64_t n,NSString *title,unsigned plays) {
    return @{@"id":[NSString stringWithFormat:@"ml:%lld",(long long)n],@"title":title,@"url":[NSString stringWithFormat:@"file:///Shows/S01/%@.mkv",title],@"kind":@"video",@"playCount":@(plays)};
}
static NSDictionary *Page(NaturalSortFixture *service,NSString *kind,NSString *sort,NSString *search,NSUInteger offset,NSUInteger limit) {
    NSError *error=nil;
    NSDictionary *location=[kind isEqual:@"folder"]||[kind isEqual:@"album"]||[kind isEqual:@"show"]?@{@"kind":kind,@"id":@"ml:3"}:@{@"kind":kind};
    NSDictionary *page=[service page:@{@"location":location,@"query":@{@"sort":sort,@"searchText":search,@"offset":@(offset),@"limit":@(limit)}} allMedia:NO error:&error];
    if(error) { failures++; fprintf(stderr,"FAIL page %s %s: %s\n",kind.UTF8String,sort.UTF8String,error.localizedDescription.UTF8String); }
    return page;
}
static NSArray *Titles(NSDictionary *page) {
    NSMutableArray *titles=[NSMutableArray array];
    for(NSDictionary *entry in page[@"entries"]) if(entry[@"media"]) [titles addObject:entry[@"media"][@"title"]];
    return titles;
}
static NSArray *Names(NSDictionary *page) {
    NSMutableArray *names=[NSMutableArray array];
    for(NSDictionary *entry in page[@"entries"]) [names addObject:entry[@"title"]?:entry[@"name"]?:@""];
    return names;
}
static void Expect(NSString *name,NSArray *got,NSArray *want) {
    assertions++;
    if(![got isEqual:want]) { failures++; fprintf(stderr,"FAIL %s: got %s, expected %s\n",name.UTF8String,got.description.UTF8String,want.description.UTF8String); }
}
static void Check(NSString *name,BOOL ok,NSString *detail) {
    assertions++;
    if(!ok) { failures++; fprintf(stderr,"FAIL %s: %s\n",name.UTF8String,detail.UTF8String); }
}
static NaturalSortFixture *Service(NSArray *engine,NSArray *external) {
    NaturalSortFixture *service=[NaturalSortFixture new]; service.engine=engine; service.external=external;
    Ivar mlIvar=class_getInstanceVariable(MXRLibraryServices.class,"_ml");
    *(void **)((__bridge void *)service+ivar_getOffset(mlIvar))=(void *)0x1;
    return service;
}

int main(void) { @autoreleasepool {
    NSDictionary *e1=Media(1,@"Episode 1",0),*e10=Media(10,@"Episode 10",1),*e11=Media(11,@"Episode 11",0),*e2=Media(2,@"Episode 2",0);
    NSArray *engineOrder=@[e1,e10,e11,e2];

    /* A folder page: 2 before 10, both directions, and the watched groups keep that order. */
    Expect(@"folder title ascending puts 2 before 10",Titles(Page(Service(engineOrder,nil),@"folder",@"titleAscending",@"",0,100)),
           (@[@"Episode 1",@"Episode 2",@"Episode 10",@"Episode 11"]));
    Expect(@"folder title descending",Titles(Page(Service([[engineOrder reverseObjectEnumerator] allObjects],nil),@"folder",@"titleDescending",@"",0,100)),
           (@[@"Episode 11",@"Episode 10",@"Episode 2",@"Episode 1"]));
    Expect(@"folder unwatched first keeps the natural order in each group",Titles(Page(Service(engineOrder,nil),@"folder",@"unwatchedFirst",@"",0,100)),
           (@[@"Episode 1",@"Episode 2",@"Episode 11",@"Episode 10"]));
    Expect(@"folder pages slice the sorted list",Titles(Page(Service(engineOrder,nil),@"folder",@"titleAscending",@"",1,2)),(@[@"Episode 2",@"Episode 10"]));
    Expect(@"date sorts keep the engine order",Titles(Page(Service(@[e10,e2],nil),@"folder",@"newestFirst",@"",0,100)),(@[@"Episode 10",@"Episode 2"]));

    /* Cyrillic case is folded too (NOCASE folds ASCII only: "Серия 2" sorted before "серия 1"). */
    Expect(@"Cyrillic titles ignore case",Titles(Page(Service(@[Media(5,@"Серия 2",0),Media(4,@"серия 1",0)],nil),@"folder",@"titleAscending",@"",0,100)),
           (@[@"серия 1",@"Серия 2"]));

    /* Search: the engine's results and the imported or opened files merge in one natural order. */
    NSDictionary *imported=Media(20,@"Episode 3",0);
    Expect(@"Videos search puts 2 before 10 and merges imports",Titles(Page(Service(@[e10,e2],@[imported]),@"videos",@"titleAscending",@"Episode",0,100)),
           (@[@"Episode 2",@"Episode 3",@"Episode 10"]));
    Expect(@"Home search puts 2 before 10",Titles(Page(Service(@[e10,e2],@[imported]),@"home",@"titleAscending",@"Episode",0,100)),
           (@[@"Episode 2",@"Episode 3",@"Episode 10"]));
    Expect(@"Music search puts 2 before 10",Titles(Page(Service(@[e10,e2],nil),@"music",@"titleAscending",@"Episode",0,100)),
           (@[@"Episode 2",@"Episode 10"]));

    /* Collections paged in the engine are loaded whole for title sorts, then sliced. */
    engineListCalls=0;
    NSDictionary *album=Page(Service(engineOrder,nil),@"album",@"titleAscending",@"",1,2);
    Expect(@"album title page is sorted before slicing",Titles(album),(@[@"Episode 2",@"Episode 10"]));
    Check(@"album title page counts the whole list",[album[@"totalCount"] integerValue]==4,[album description]);
    Check(@"album title page is not paged in the engine",engineListCalls==0,[NSString stringWithFormat:@"%d engine calls",engineListCalls]);
    Expect(@"show title page puts 2 before 10",Titles(Page(Service(engineOrder,nil),@"show",@"titleAscending",@"",0,100)),
           (@[@"Episode 1",@"Episode 2",@"Episode 10",@"Episode 11"]));
    engineListCalls=0;
    Page(Service(engineOrder,nil),@"album",@"trackNumberAscending",@"",0,2);
    Check(@"track-number pages still page in the engine",engineListCalls>0,@"no engine count");

    /* The Music collections themselves (review В2): listed whole, re-sorted for title sorts only. */
    NSArray *natural=@[@"Vol. 1",@"Vol. 2",@"Vol. 10",@"серия 1",@"Серия 2"];
    for(NSString *kind in @[@"albums",@"artists",@"genres"]) {
        Expect([kind stringByAppendingString:@" title ascending puts Vol. 2 before Vol. 10"],Names(Page(Service(@[],nil),kind,@"titleAscending",@"",0,100)),natural);
        Expect([kind stringByAppendingString:@" title descending"],Names(Page(Service(@[],nil),kind,@"titleDescending",@"",0,100)),[[natural reverseObjectEnumerator] allObjects]);
    }
    Expect(@"albums by artist keep the engine order",Names(Page(Service(@[],nil),@"albums",@"artistAscending",@"",0,100)),
           (@[@"Vol. 1",@"Vol. 10",@"Vol. 2",@"Серия 2",@"серия 1"]));
    Expect(@"collection pages slice the sorted list",Names(Page(Service(@[],nil),@"albums",@"titleAscending",@"",1,2)),(@[@"Vol. 2",@"Vol. 10"]));

    if(!failures) printf("PASS: native natural title order (%d assertions)\n",assertions);
    return failures?1:0;
} }
