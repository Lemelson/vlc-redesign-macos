/* Native root-page ordering fixture. Uses production page/entriesAt logic without VLC/ML state. */
#import <Foundation/Foundation.h>
#import "../module/bridge/MXRLibraryServices.h"
#include <vlc_media_library.h>

@interface MXRLibraryServices (ImportSortFixture)
- (void)ensureIndex;
- (NSArray *)rootFolders:(vlc_ml_media_type_t)type;
- (NSArray *)importedMediaMatching:(NSString *)search type:(vlc_ml_media_type_t)type;
- (NSMutableDictionary *)store;
- (NSDictionary *)page:(NSDictionary *)arguments allMedia:(BOOL)all error:(NSError **)error;
@end
@interface ImportSortFixture : MXRLibraryServices
@property(nonatomic,strong) NSArray *records;
@property(nonatomic,strong) NSMutableDictionary *memoryStore;
@end
@implementation ImportSortFixture
- (void)ensureIndex {}
- (NSArray *)rootFolders:(vlc_ml_media_type_t)type { (void)type; return @[@{@"type":@"folder",@"name":@"Z folder",@"id":@"folder-z"}]; }
- (NSArray *)importedMediaMatching:(NSString *)search type:(vlc_ml_media_type_t)type { (void)search; (void)type; return self.records; }
- (NSMutableDictionary *)store { return self.memoryStore; }
@end

static int failures;
static NSArray *RootTitles(NSArray *records,NSDictionary *dates,NSString *root,NSString *sort,NSUInteger offset,NSUInteger limit) {
    ImportSortFixture *service=[ImportSortFixture new]; service.records=records;
    service.memoryStore=[@{@"importDates":dates} mutableCopy];
    NSError *error=nil;
    NSDictionary *page=[service page:@{@"location":@{@"kind":root},@"query":@{@"sort":sort,@"offset":@(offset),@"limit":@(limit)}} allMedia:NO error:&error];
    if(error) { fprintf(stderr,"FAIL: %s\n",error.localizedDescription.UTF8String); failures++; }
    NSMutableArray *titles=[NSMutableArray array];
    for(NSDictionary *entry in page[@"entries"]) [titles addObject:entry[@"media"][@"title"]?:entry[@"name"]];
    return titles;
}
static void Expect(NSString *name,NSArray *got,NSArray *want) {
    if(![got isEqual:want]) { failures++; fprintf(stderr,"FAIL %s: got %s, expected %s\n",name.UTF8String,got.description.UTF8String,want.description.UTF8String); }
}
int main(void) { @autoreleasepool {
    NSDictionary *bravo=@{@"id":@"ml:1",@"title":@"Bravo",@"url":@"file:///Bravo.mp3",@"artist":@"Zulu",@"album":@"Album B",@"trackNumber":@2,@"discNumber":@1,@"playCount":@1};
    NSDictionary *alpha=@{@"id":@"ml:2",@"title":@"Alpha",@"url":@"file:///Alpha.mp3",@"artist":@"Alpha Artist",@"album":@"Album A",@"trackNumber":@1,@"discNumber":@1,@"playCount":@0};
    NSDictionary *charlie=@{@"id":@"ml:3",@"title":@"Charlie",@"url":@"file:///Charlie.mp3",@"artist":@"Middle Artist",@"album":@"Album C",@"trackNumber":@3,@"discNumber":@2,@"playCount":@1};
    NSArray *records=@[bravo,alpha,charlie]; NSDictionary *dates=@{@"ml:1":@100,@"ml:2":@200,@"ml:3":@300};
    Expect(@"video title ascending",RootTitles(records,dates,@"videos",@"titleAscending",0,100),(@[@"Z folder",@"Alpha",@"Bravo",@"Charlie"]));
    Expect(@"video title descending",RootTitles(records,dates,@"videos",@"titleDescending",0,100),(@[@"Z folder",@"Charlie",@"Bravo",@"Alpha"]));
    Expect(@"newest actual import date",RootTitles(records,dates,@"videos",@"newestFirst",0,100),(@[@"Z folder",@"Charlie",@"Alpha",@"Bravo"]));
    Expect(@"oldest actual import date",RootTitles(records,dates,@"videos",@"oldestFirst",0,100),(@[@"Z folder",@"Bravo",@"Alpha",@"Charlie"]));
    Expect(@"artist ascending",RootTitles(records,dates,@"songs",@"artistAscending",0,100),(@[@"Z folder",@"Alpha",@"Charlie",@"Bravo"]));
    Expect(@"album descending",RootTitles(records,dates,@"songs",@"albumDescending",0,100),(@[@"Z folder",@"Charlie",@"Bravo",@"Alpha"]));
    Expect(@"disc then track ascending",RootTitles(records,dates,@"songs",@"trackNumberAscending",0,100),(@[@"Z folder",@"Alpha",@"Bravo",@"Charlie"]));
    Expect(@"disc descending",RootTitles(records,dates,@"songs",@"discNumberDescending",0,100),(@[@"Z folder",@"Charlie",@"Bravo",@"Alpha"]));
    Expect(@"URI descending",RootTitles(records,dates,@"songs",@"uriDescending",0,100),(@[@"Z folder",@"Charlie",@"Bravo",@"Alpha"]));
    Expect(@"watched grouping with title tie order",RootTitles(records,dates,@"videos",@"watchedFirst",0,100),(@[@"Z folder",@"Bravo",@"Charlie",@"Alpha"]));
    Expect(@"sorting precedes page slicing",RootTitles(records,dates,@"videos",@"titleAscending",2,1),(@[@"Bravo"]));
    Expect(@"unknown dates retain input order",RootTitles(records,@{},@"videos",@"newestFirst",0,100),(@[@"Z folder",@"Bravo",@"Alpha",@"Charlie"]));
    Expect(@"known dates precede unknown dates",RootTitles(@[alpha,bravo,charlie],@{@"ml:1":@100},@"videos",@"newestFirst",0,100),(@[@"Z folder",@"Bravo",@"Alpha",@"Charlie"]));
    ImportSortFixture *cached=[ImportSortFixture new]; cached.records=records; cached.memoryStore=[@{@"importDates":dates} mutableCopy];
    NSError *error=nil;
    NSDictionary *first=[cached page:@{@"location":@{@"kind":@"videos"},@"query":@{@"sort":@"titleAscending",@"offset":@0,@"limit":@2}} allMedia:NO error:&error];
    cached.records=@[charlie,bravo];
    NSDictionary *second=[cached page:@{@"location":@{@"kind":@"videos"},@"query":@{@"sort":@"titleAscending",@"offset":@2,@"limit":@2}} allMedia:NO error:&error];
    NSMutableArray *joined=[NSMutableArray array];
    for(NSDictionary *entry in [first[@"entries"] arrayByAddingObjectsFromArray:second[@"entries"]]) [joined addObject:entry[@"media"][@"title"]?:entry[@"name"]];
    Expect(@"cached pages preserve sorted snapshot",joined,(@[@"Z folder",@"Alpha",@"Bravo",@"Charlie"]));
    if(!failures) puts("PASS: native imported root sorts and pagination (14 assertions)");
    return failures?1:0;
} }
