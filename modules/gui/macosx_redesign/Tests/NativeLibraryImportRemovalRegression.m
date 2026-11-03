/* Native Add File fixture (R04). Runs the production importFiles / removeImportedMedia
 * requests and the imported-media listing against a scripted media library (vlc_ml_get /
 * vlc_ml_control) and real files in a temporary directory: one unreadable file no longer
 * fails the selection, removed imports leave the list and the saved store, and an import
 * whose file is gone is hidden. */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdarg.h>
#import "../module/bridge/MXRLibraryServices.h"
#import "MXRBridgeKeys.h"
#include <vlc_media_library.h>

@interface MXRLibraryServices (ImportRemovalFixture)
- (void)ensureIndex;
- (void)markStale;
- (NSURL *)storeDirectory;
- (NSMutableDictionary *)store;
- (NSArray *)importedMediaMatching:(NSString *)search type:(vlc_ml_media_type_t)type;
- (NSDictionary *)execute:(MXRBridgeRequest)request arguments:(NSDictionary *)args error:(NSError **)error;
@end
@interface ImportRemovalFixture : MXRLibraryServices
@property(nonatomic,strong) NSURL *directory;
@end
@implementation ImportRemovalFixture
- (void)ensureIndex {}
/* No user data dir without a VLC instance: the store lives in the test's directory. */
- (NSURL *)storeDirectory { return self.directory; }
@end

/* The scripted media library: external media created on demand, by MRL. A file whose name
 * contains "refused" is one the media library does not take. */
static NSMutableArray<NSString *> *knownMRLs;
static vlc_ml_media_t *NewMedia(int64_t id) {
    NSString *mrl=knownMRLs[(NSUInteger)id-1];
    vlc_ml_media_t *media=calloc(1,sizeof *media);
    media->i_id=id; media->psz_title=strdup(mrl.lastPathComponent.UTF8String);
    media->p_files=calloc(1,sizeof *media->p_files+sizeof(vlc_ml_file_t));
    media->p_files->i_nb_items=1;
    media->p_files->p_items[0]=(vlc_ml_file_t){.psz_mrl=strdup(mrl.UTF8String),.i_type=VLC_ML_FILE_TYPE_MAIN,.b_external=true,.b_present=true};
    return media;
}
void *vlc_ml_get(vlc_medialibrary_t *ml,int query,...) {
    (void)ml; va_list ap; va_start(ap,query); void *result=NULL;
    if(query==VLC_ML_GET_MEDIA) {
        int64_t id=va_arg(ap,int64_t);
        if(id>0&&(NSUInteger)id<=knownMRLs.count) result=NewMedia(id);
    } else if(query==VLC_ML_GET_MEDIA_BY_MRL) {
        NSUInteger index=[knownMRLs indexOfObject:[NSString stringWithUTF8String:va_arg(ap,const char *)]];
        if(index!=NSNotFound) result=NewMedia((int64_t)index+1);
    }
    va_end(ap); return result;
}
int vlc_ml_control(vlc_medialibrary_t *ml,int query,...) {
    (void)ml;
    if(query!=VLC_ML_NEW_EXTERNAL_MEDIA) return VLC_SUCCESS;
    va_list ap; va_start(ap,query);
    NSString *mrl=[NSString stringWithUTF8String:va_arg(ap,const char *)]; vlc_ml_media_t **out=va_arg(ap,vlc_ml_media_t **);
    va_end(ap);
    if([mrl containsString:@"refused"]) return VLC_EGENERIC;
    [knownMRLs addObject:mrl]; *out=NewMedia((int64_t)knownMRLs.count);
    return VLC_SUCCESS;
}
int vlc_ml_list(vlc_medialibrary_t *ml,int query,const vlc_ml_query_params_t *params,...) { (void)ml; (void)query; (void)params; return VLC_EGENERIC; }
void vlc_ml_media_release(vlc_ml_media_t *media) {
    if(!media) return;
    free(media->psz_title);
    if(media->p_files) { free(media->p_files->p_items[0].psz_mrl); free(media->p_files); }
    free(media);
}

static int failures,assertions;
static void Expect(NSString *name,BOOL ok,id detail) {
    assertions++;
    if(!ok) { failures++; fprintf(stderr,"FAIL %s: %s\n",name.UTF8String,[detail description].UTF8String); }
}
static id Saved(NSURL *directory,NSString *key) {
    NSData *data=[NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:@"library-store.json"]];
    return data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil][key]:nil;
}

int main(void) { @autoreleasepool {
    knownMRLs=[NSMutableArray array];
    NSFileManager *files=NSFileManager.defaultManager;
    NSURL *directory=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    [files createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *good=[directory URLByAppendingPathComponent:@"Good.mp4"],*song=[directory URLByAppendingPathComponent:@"Song.mp3"];
    NSURL *gone=[directory URLByAppendingPathComponent:@"Gone.mp4"],*folder=[directory URLByAppendingPathComponent:@"Folder.mp4" isDirectory:YES];
    NSURL *refused=[directory URLByAppendingPathComponent:@"refused.mp4"];
    for(NSURL *url in @[good,song,refused]) [[NSData dataWithBytes:"media" length:5] writeToURL:url atomically:YES];
    [files createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];

    ImportRemovalFixture *service=[ImportRemovalFixture new]; service.directory=directory;
    Ivar mlIvar=class_getInstanceVariable(MXRLibraryServices.class,"_ml");
    *(void **)((__bridge void *)service+ivar_getOffset(mlIvar))=(void *)0x1;

    /* One selection with a good video, a missing file, a folder, a file the library refuses and a song. */
    NSArray *urls=@[good.absoluteString,gone.absoluteString,folder.absoluteString,refused.absoluteString,song.absoluteString];
    NSError *error=nil;
    NSDictionary *result=[service execute:MXRBridgeRequestImportFiles arguments:@{@"urls":urls,@"kinds":@[@"video",@"video",@"video",@"video",@"audio"]} error:&error];
    Expect(@"a partial import succeeds",result!=nil&&error==nil,error?:@"no result");
    NSArray *added=[result[@"media"] valueForKey:@"url"];
    Expect(@"the readable files are imported",[added isEqual:(@[good.absoluteString,song.absoluteString])],added);
    Expect(@"the others are named back in order",[result[@"rejected"] isEqual:(@[gone.absoluteString,folder.absoluteString,refused.absoluteString])],result[@"rejected"]);
    Expect(@"imports carry the removal flag",[[result[@"media"] valueForKey:@"isImported"] isEqual:(@[@YES,@YES])],result[@"media"]);
    Expect(@"the imports are saved",[Saved(directory,@"importedMedia") isEqual:(@[@"ml:1",@"ml:2"])],Saved(directory,@"importedMedia"));
    NSArray *listed=[[service importedMediaMatching:@"" type:VLC_ML_MEDIA_TYPE_UNKNOWN] valueForKey:@"url"];
    Expect(@"both imports are listed",[listed isEqual:(@[good.absoluteString,song.absoluteString])],listed);

    /* Only bad files: nothing changes, and every file is named. */
    error=nil;
    result=[service execute:MXRBridgeRequestImportFiles arguments:@{@"urls":@[gone.absoluteString]} error:&error];
    Expect(@"an import of only bad files reports them",[result[@"media"] count]==0&&[result[@"rejected"] isEqual:@[gone.absoluteString]],result?:error);

    /* An import whose file is gone is hidden, not forgotten. */
    [files removeItemAtURL:song error:nil]; [service markStale];
    listed=[[service importedMediaMatching:@"" type:VLC_ML_MEDIA_TYPE_UNKNOWN] valueForKey:@"url"];
    Expect(@"a deleted file's import is hidden",[listed isEqual:@[good.absoluteString]],listed);
    Expect(@"a hidden import is still recorded",[service.store[@"importedMedia"] containsObject:@"ml:2"],service.store[@"importedMedia"]);

    /* Remove from Library. */
    error=nil;
    result=[service execute:MXRBridgeRequestRemoveImportedMedia arguments:@{@"mediaIDs":@[@"ml:1"]} error:&error];
    Expect(@"removal succeeds",result!=nil&&error==nil,error?:@"no result");
    [service markStale];
    listed=[[service importedMediaMatching:@"" type:VLC_ML_MEDIA_TYPE_UNKNOWN] valueForKey:@"url"];
    Expect(@"a removed import leaves the list",listed.count==0,listed);
    Expect(@"the removal is saved",[Saved(directory,@"importedMedia") isEqual:@[@"ml:2"]],Saved(directory,@"importedMedia"));
    Expect(@"its import date goes too",Saved(directory,@"importDates")&&![[(NSDictionary *)Saved(directory,@"importDates") allKeys] containsObject:@"ml:1"],Saved(directory,@"importDates"));
    error=nil;
    result=[service execute:MXRBridgeRequestRemoveImportedMedia arguments:@{@"mediaIDs":@[]} error:&error];
    Expect(@"an empty removal is refused",result==nil&&error!=nil,result);

    [files removeItemAtURL:directory error:nil];
    if(!failures) printf("PASS: native Add File import and removal (%d assertions)\n",assertions);
    return failures?1:0;
} }
