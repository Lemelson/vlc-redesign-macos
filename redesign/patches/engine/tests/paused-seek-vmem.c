/* Test-only wrapper around the stock VMEM output. It observes picture PTS
 * without changing decoding, scheduling, pixel copying, or presentation. */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_vout_display.h>

static int ObservedOpen(vout_display_t *, video_format_t *, vlc_video_context *);

/* Stock VMEM already registers these options in the loaded module bank. */
#undef add_integer
#undef add_string
#undef change_private
#define add_integer(...)
#define add_string(...)
#define change_private(...)
#undef set_callback_display
#define set_callback_display(activate, priority) \
    set_callback(ObservedOpen) \
    set_capability("vout display", priority)

#include "video_output/vmem.c"

static void ObservedPrepare(vout_display_t *display, picture_t *picture,
                            const struct vlc_render_subpicture *subpicture,
                            vlc_tick_t system_date)
{
    void (*observe)(void *, vlc_tick_t) =
        var_InheritAddress(display, "seek-vmem-pts");
    if (observe != NULL)
        observe(var_InheritAddress(display, "vmem-data"), picture->date);
    Prepare(display, picture, subpicture, system_date);
}

static const struct vlc_display_operations observed_operations = {
    .close = Close,
    .prepare = ObservedPrepare,
    .display = Display,
};

static int ObservedOpen(vout_display_t *display, video_format_t *format,
                        vlc_video_context *context)
{
    int result = Open(display, format, context);
    if (result == VLC_SUCCESS)
        display->ops = &observed_operations;
    return result;
}
