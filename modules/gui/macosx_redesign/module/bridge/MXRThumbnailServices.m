/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#import "MXRThumbnailServices.h"
#import "MXRBridgeKeys.h"
#import <CoreGraphics/CoreGraphics.h>
#include <vlc_preparser.h>
#include <vlc_input_item.h>
#include <vlc_picture.h>
#include <vlc_image.h>
#include <stdatomic.h>
#include <errno.h>

/*
 * Library artwork and seek-bar frames (S03, D028, D031 still).
 *
 * - Two thumbnailers, so library artwork never queues in front of scrubbing.
 * - Frames are decoded in memory (vlc_preparser_req_NewThumbnail), converted to BGRA at the
 *   requested size (display aspect kept) and handed to Swift as a CGImage: no PNG, no temp file.
 * - Every request carries a token; "cancel" with that token calls vlc_preparser_Cancel on the
 *   running or queued engine request, so stale scrub frames never pile up.
 * - "exact": decode up to the requested frame (VLC_THUMBNAILER_SEEK_PRECISE) instead of the
 *   nearest keyframe; used when the pointer rests and for the paused-seek still.
 * Threading: requests, cancellation, conversion and bookkeeping run on one serial queue;
 * completions are delivered on main (VLCServiceTransport contract).
 */

static NSError *TE(NSString *message) { return [NSError errorWithDomain:@"MXRVLCBridge" code:6 userInfo:@{NSLocalizedDescriptionKey:message}]; }

@interface MXRThumbnailRequest : NSObject
@property(nonatomic,weak) MXRThumbnailServices *owner;
@property(nonatomic,copy) void (^completion)(NSDictionary * _Nullable,NSError * _Nullable);
@property(nonatomic,strong) NSNumber *token;
@property(nonatomic) unsigned width, height;
@property(nonatomic) vlc_preparser_t *preparser;
@property(nonatomic) vlc_preparser_req *req;
@end
@implementation MXRThumbnailRequest
@end

@interface MXRThumbnailServices ()
- (void)finished:(MXRThumbnailRequest *)request status:(int)status picture:(picture_t *)picture;
@end

/* Thumbnailer thread, no lock held. The picture belongs to the thumbnailer: hold it for the queue. */
static void ThumbnailEnded(vlc_preparser_req *req, int status, picture_t *picture, void *data)
{
    VLC_UNUSED(req);
    MXRThumbnailRequest *request = CFBridgingRelease(data);
    if (picture != NULL) picture_Hold(picture);
    MXRThumbnailServices *owner = request.owner;
    if (owner != nil) { [owner finished:request status:status picture:picture]; return; }
    if (picture != NULL) picture_Release(picture);
    void (^completion)(NSDictionary *, NSError *) = request.completion;
    dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, TE(@"Thumbnail request cancelled.")); });
}
static const struct vlc_thumbnailer_cbs ThumbnailCallbacks = { .on_ended = ThumbnailEnded };
/* Tokens for requests sent without one (negative, never equal to a Swift token). */
static atomic_llong AnonymousTokens = 1;

/* Converts to BGRA, scaled to fit width×height while keeping the display aspect ratio. */
static CGImageRef MXRCreateImage(image_handler_t *handler, picture_t *picture, unsigned maxWidth, unsigned maxHeight)
{
    video_format_t in = picture->format;
    if (in.i_sar_num == 0 || in.i_sar_den == 0) in.i_sar_num = in.i_sar_den = 1;
    const unsigned width = in.i_visible_width ? in.i_visible_width : in.i_width;
    const unsigned height = in.i_visible_height ? in.i_visible_height : in.i_height;
    if (width == 0 || height == 0) return NULL;
    const double displayWidth = (double)width * in.i_sar_num / in.i_sar_den, displayHeight = height;
    const double scale = fmin(1., fmin(maxWidth / displayWidth, maxHeight / displayHeight));
    const unsigned outWidth = MAX(2u, (unsigned)lround(displayWidth * scale)) & ~1u;
    const unsigned outHeight = MAX(2u, (unsigned)lround(displayHeight * scale)) & ~1u;

    video_format_t out;
    video_format_Init(&out, VLC_CODEC_BGRA);
    out.i_width = out.i_visible_width = outWidth;
    out.i_height = out.i_visible_height = outHeight;
    out.i_sar_num = out.i_sar_den = 1;
    picture_t *converted = image_Convert(handler, picture, &in, &out);
    video_format_Clean(&out);
    if (converted == NULL) return NULL;

    const size_t rowBytes = (size_t)outWidth * 4;
    CFMutableDataRef pixels = CFDataCreateMutable(kCFAllocatorDefault, (CFIndex)(rowBytes * outHeight));
    if (pixels == NULL) { picture_Release(converted); return NULL; }
    CFDataSetLength(pixels, (CFIndex)(rowBytes * outHeight));
    uint8_t *destination = CFDataGetMutableBytePtr(pixels);
    const plane_t *plane = &converted->p[0];
    const unsigned lines = MIN(outHeight, (unsigned)MAX(0, plane->i_visible_lines));
    const size_t copy = MIN(rowBytes, (size_t)MAX(0, plane->i_visible_pitch));
    for (unsigned y = 0; y < lines; ++y)
        memcpy(destination + y * rowBytes, plane->p_pixels + (size_t)y * (size_t)plane->i_pitch, copy);
    picture_Release(converted);

    CGDataProviderRef provider = CGDataProviderCreateWithCFData(pixels);
    CFRelease(pixels);
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef image = provider && space
        ? CGImageCreate(outWidth, outHeight, 8, 32, rowBytes, space,
                        kCGBitmapByteOrder32Little | (CGBitmapInfo)kCGImageAlphaNoneSkipFirst,
                        provider, NULL, false, kCGRenderingIntentDefault)
        : NULL;
    if (space) CGColorSpaceRelease(space);
    if (provider) CGDataProviderRelease(provider);
    return image;
}

@implementation MXRThumbnailServices {
    intf_thread_t *_intf;
    vlc_preparser_t *_artwork, *_preview;
    image_handler_t *_converter;                                   /* queue only */
    NSMutableDictionary<NSNumber *, MXRThumbnailRequest *> *_active; /* queue only */
    dispatch_queue_t _queue;
    atomic_bool _stopped;
}

- (instancetype)initWithInterface:(intf_thread_t *)intf
{
    if (!(self = [super init])) return nil;
    atomic_init(&_stopped, false);
    _intf = intf;
    _queue = dispatch_queue_create("org.vlc-redesign.thumbnails", DISPATCH_QUEUE_SERIAL);
    _active = [NSMutableDictionary dictionary];
    struct vlc_preparser_cfg artwork = { .types = VLC_PREPARSER_TYPE_THUMBNAIL, .max_thumbnailer_threads = 1,
                                         .timeout = VLC_TICK_FROM_SEC(8), .external_process = false };
    struct vlc_preparser_cfg preview = { .types = VLC_PREPARSER_TYPE_THUMBNAIL, .max_thumbnailer_threads = 1,
                                         .timeout = VLC_TICK_FROM_SEC(5), .external_process = false };
    _artwork = vlc_preparser_New(VLC_OBJECT(intf), &artwork);
    _preview = vlc_preparser_New(VLC_OBJECT(intf), &preview);
    return self;
}

- (BOOL)available { return _artwork != NULL && _preview != NULL; }

static void MXRComplete(void (^completion)(NSDictionary *, NSError *), NSDictionary *value, NSError *error)
{
    dispatch_async(dispatch_get_main_queue(), ^{ completion(value, error); });
}

- (void)finished:(MXRThumbnailRequest *)request status:(int)status picture:(picture_t *)picture
{
    dispatch_async(_queue, ^{ @autoreleasepool {
        [self->_active removeObjectForKey:request.token];
        if (request.req != NULL) { vlc_preparser_req_Release(request.req); request.req = NULL; }
        CGImageRef image = NULL;
        if (picture != NULL) {
            if (status == VLC_SUCCESS && !atomic_load(&self->_stopped)) {
                if (self->_converter == NULL) self->_converter = image_HandlerCreate(self->_intf);
                if (self->_converter != NULL) image = MXRCreateImage(self->_converter, picture, request.width, request.height);
            }
            picture_Release(picture);
        }
        if (atomic_load(&self->_stopped)) MXRComplete(request.completion, nil, TE(@"Thumbnail request cancelled."));
        else if (image != NULL) MXRComplete(request.completion, @{@"image": (__bridge id)image}, nil);
        else if (status == -EINTR) MXRComplete(request.completion, nil, TE(@"Thumbnail request cancelled."));
        else MXRComplete(request.completion, nil, TE(@"VLC could not generate a thumbnail."));
        if (image != NULL) CGImageRelease(image);
    }});
}

- (void)request:(MXRBridgeRequest)request arguments:(NSDictionary *)arguments completion:(void (^)(NSDictionary * _Nullable,NSError * _Nullable))completion
{
    if (!self.available || atomic_load(&_stopped)) { completion(nil, TE(@"VLC thumbnail service is unavailable.")); return; }
    NSDictionary *args = [arguments copy]; NSString *operation = [request copy];
    dispatch_async(_queue, ^{ @autoreleasepool {
        if (atomic_load(&self->_stopped)) { MXRComplete(completion, nil, TE(@"Thumbnail request cancelled.")); return; }
        if ([operation isEqual:@"cancel"]) {
            MXRThumbnailRequest *running = [args[@"token"] isKindOfClass:NSNumber.class] ? self->_active[args[@"token"]] : nil;
            /* on_ended may run synchronously here; it only enqueues on this queue. */
            if (running.req != NULL) vlc_preparser_Cancel(running.preparser, running.req);
            MXRComplete(completion, @{}, nil);
            return;
        }
        NSDictionary *media = [args[@"media"] isKindOfClass:NSDictionary.class] ? args[@"media"] : args;
        NSString *url = media[@"url"];
        if ([operation isEqual:@"artwork"] && [media[@"artworkURL"] isKindOfClass:NSString.class]) {
            NSURL *art = [NSURL URLWithString:media[@"artworkURL"]];
            if (art.isFileURL) { NSData *data = [NSData dataWithContentsOfURL:art]; if (data) { MXRComplete(completion, @{@"data": data}, nil); return; } }
        }
        if (![operation isEqual:@"artwork"] && ![operation isEqual:@"seekPreview"]) { MXRComplete(completion, nil, TE(@"This thumbnail operation is unavailable.")); return; }
        if (![url isKindOfClass:NSString.class] || ![NSURL URLWithString:url].scheme) { MXRComplete(completion, nil, TE(@"A media URL is required.")); return; }
        input_item_t *item = input_item_New(url.UTF8String, NULL);
        if (!item) { MXRComplete(completion, nil, TE(@"Cannot create thumbnail input.")); return; }
        /* Thumbnail decoding must work even if normal playback video is disabled. */
        if (input_item_AddOption(item, "video=1", VLC_INPUT_OPTION_TRUSTED) != VLC_SUCCESS) {
            input_item_Release(item); MXRComplete(completion, nil, TE(@"Cannot configure thumbnail input.")); return;
        }
        MXRThumbnailRequest *context = [MXRThumbnailRequest new];
        context.owner = self; context.completion = completion;
        context.token = [args[@"token"] isKindOfClass:NSNumber.class] ? args[@"token"] : @(-atomic_fetch_add(&AnonymousTokens, 1));
        int width = [args[@"width"] intValue], height = [args[@"height"] intValue];
        context.width = (unsigned)MAX(16, MIN(4096, width > 0 ? width : 320));
        context.height = (unsigned)MAX(16, MIN(4096, height > 0 ? height : (int)context.width));
        const BOOL exact = [args[@"exact"] boolValue];
        context.preparser = [operation isEqual:@"artwork"] ? self->_artwork : self->_preview;
        struct vlc_thumbnailer_arg arg = {
            .seek = { .type = VLC_THUMBNAILER_SEEK_TIME,
                      .time = VLC_TICK_0 + VLC_TICK_FROM_US(MAX(0, [args[@"time"] longLongValue])),
                      .speed = exact ? VLC_THUMBNAILER_SEEK_PRECISE : VLC_THUMBNAILER_SEEK_FAST },
            /* Upstream thumbnailer_get_device (src/input/decoder.c) intentionally
             * returns NULL even with hw_dec enabled. Keep the supported software
             * path; enabling this flag alone does not provide VideoToolbox. */
            .hw_dec = false,
        };
        /* Artwork without a time: a frame 30 % in, like the media library, not the (often black) first frame (L16). */
        if ([operation isEqual:@"artwork"] && ![args[@"time"] isKindOfClass:NSNumber.class]) {
            arg.seek.type = VLC_THUMBNAILER_SEEK_POS; arg.seek.pos = 0.3;
        }
        void *retained = (__bridge_retained void *)context;
        vlc_preparser_req *req = vlc_preparser_req_NewThumbnail(context.preparser, item, &arg, &ThumbnailCallbacks, retained);
        input_item_Release(item);
        if (req == NULL) {
            CFBridgingRelease(retained);
            MXRComplete(completion, nil, TE(@"VLC could not start the thumbnail request.")); return;
        }
        context.req = req;
        self->_active[context.token] = context;
        if (vlc_preparser_Submit(context.preparser, req) != VLC_SUCCESS) {
            [self->_active removeObjectForKey:context.token];
            context.req = NULL; vlc_preparser_req_Release(req); CFBridgingRelease(retained);
            MXRComplete(completion, nil, TE(@"VLC could not start the thumbnail request."));
        }
    }});
}

- (void)shutdown { atomic_store(&_stopped, true); }

- (void)finishShutdown
{
    dispatch_sync(_queue, ^{
        /* Cancelled requests end with -EINTR; their bookkeeping is queued behind this block. */
        if (self->_artwork) { vlc_preparser_Cancel(self->_artwork, NULL); vlc_preparser_Delete(self->_artwork); self->_artwork = NULL; }
        if (self->_preview) { vlc_preparser_Cancel(self->_preview, NULL); vlc_preparser_Delete(self->_preview); self->_preview = NULL; }
    });
    dispatch_sync(_queue, ^{
        if (self->_converter) { image_HandlerDelete(self->_converter); self->_converter = NULL; }
        [self->_active removeAllObjects];
    });
}

- (void)dealloc { assert(!_artwork && !_preview && !_converter); }
@end
