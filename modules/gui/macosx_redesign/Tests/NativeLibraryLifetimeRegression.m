/* Deterministic worker-before-submission shutdown regression. No VLC instance or UI. */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "../module/bridge/MXRLibraryServices.h"
#include <vlc_media_library.h>
#include <vlc_preparser.h>

static dispatch_semaphore_t acquired, releaseWorker, finished;
static int deleted;
#define CHECK(condition, message) do { if(!(condition)) { fprintf(stderr,"FAIL: %s\n",message); exit(1); } } while(0)
size_t vlc_preparser_Cancel(vlc_preparser_t *parser, vlc_preparser_req *req) { (void)parser; (void)req; return 0; }
void vlc_preparser_Delete(vlc_preparser_t *parser) { (void)parser; deleted++; }
void vlc_ml_event_unregister_callback(vlc_medialibrary_t *ml, vlc_ml_event_callback_t *callback) { (void)ml; (void)callback; }

@interface MXRLibraryServices (LifetimeProbe)
- (NSArray *)childrenOfPlaylistURL:(NSString *)url;
@end
static void SetPointer(id object, const char *name, void *value) {
    Ivar ivar=class_getInstanceVariable(MXRLibraryServices.class,name);
    *(void **)((__bridge void *)object+ivar_getOffset(ivar))=value;
}
@interface LibraryLifetimeProbe : MXRLibraryServices
@end
@implementation LibraryLifetimeProbe
- (NSArray *)childrenOfPlaylistURL:(NSString *)url {
    (void)url;
    SetPointer(self,"_expander",(void *)0x1);
    dispatch_semaphore_signal(acquired);
    dispatch_semaphore_wait(releaseWorker,DISPATCH_TIME_FOREVER);
    return @[];
}
@end
int main(void) { @autoreleasepool {
    acquired=dispatch_semaphore_create(0); releaseWorker=dispatch_semaphore_create(0); finished=dispatch_semaphore_create(0);
    LibraryLifetimeProbe *service=[LibraryLifetimeProbe new];
    object_setIvar(service,class_getInstanceVariable(MXRLibraryServices.class,"_queue"),dispatch_queue_create("library.regression",DISPATCH_QUEUE_SERIAL));
    Ivar workers=class_getInstanceVariable(MXRLibraryServices.class,"_expansionWorkers");
    if(workers) object_setIvar(service,workers,dispatch_group_create());
    SetPointer(service,"_ml",(void *)0x1); SetPointer(service,"_listener",(void *)0x1);
    [service request:@"addNetworkStream" arguments:@{@"urls":@[@"https://fixture.invalid/list.m3u"]} completion:^(NSDictionary *result,NSError *error){ (void)result; (void)error; }];
    CHECK(dispatch_semaphore_wait(acquired,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0,"Worker did not reach the pre-submission barrier");
    [service shutdown];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{ [service finishShutdown]; dispatch_semaphore_signal(finished); });
    CHECK(dispatch_semaphore_wait(finished,dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC))!=0,"Shutdown returned while an accepted worker still owned the parser");
    CHECK(deleted==0,"Parser deleted before its worker exited");
    dispatch_semaphore_signal(releaseWorker);
    CHECK(dispatch_semaphore_wait(finished,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0,"Shutdown did not join the released worker");
    CHECK(deleted==1,"Parser must be deleted exactly once");
    puts("PASS: shutdown joins accepted expansion worker before deleting parser");
} return 0; }
