/* Focused engine primitive check for next-media rate defaults. No UI or input decoding. */
#include "config.h"
#include <stdio.h>
#include <stdlib.h>
#include <vlc_common.h>
#include <vlc_configuration.h>
#include <vlc_player.h>
extern libvlc_int_t *libvlc_InternalCreate(void);
extern int libvlc_InternalInit(libvlc_int_t *, int, const char *[]);
extern void libvlc_InternalCleanup(libvlc_int_t *);
extern void libvlc_InternalDestroy(libvlc_int_t *);
static int rate_events;
static void rate_changed(vlc_player_t *p, float rate, void *data) { (void)p; (void)rate; (void)data; rate_events++; }
static const struct vlc_player_cbs callbacks = { .on_rate_changed = rate_changed };
/* Calls with side effects are checked explicitly: assert() would compile them out under NDEBUG. */
static _Noreturn void fail(const char *step) { fprintf(stderr, "FAIL: %s\n", step); exit(1); }
static vlc_object_t *child(vlc_player_t *player) {
    vlc_object_t *value = vlc_object_create((vlc_object_t *)player, sizeof(*value));
    if (value == NULL) fail("vlc_object_create");
    if (var_Create(value, "rate", VLC_VAR_FLOAT | VLC_VAR_DOINHERIT) != VLC_SUCCESS) fail("var_Create(rate)");
    return value;
}
int main(int argc, char **argv) {
    (void)argv;
    /* User data/config locations come from the runner's per-run VLC_USERDATA_PATH;
     * --ignore-config keeps the user's vlcrc out of (and unchanged by) this test. */
    libvlc_int_t *instance = libvlc_InternalCreate();
    if (instance == NULL) fail("libvlc_InternalCreate");
    const char *options[] = { "mxr-settings-test", "--ignore-config", "--no-media-library", "--no-auto-preparse", "--no-metadata-network-access", "--no-plugins-cache", "--aout=dummy", "--vout=dummy" };
    if (libvlc_InternalInit(instance, sizeof(options) / sizeof(options[0]), options) != VLC_SUCCESS) fail("libvlc_InternalInit");
    config_PutFloat("rate", 1.f);
    vlc_player_t *player = vlc_player_New(VLC_OBJECT(instance), VLC_PLAYER_LOCK_NORMAL);
    if (player == NULL) fail("vlc_player_New");
    vlc_player_Lock(player);
    vlc_player_listener_id *listener = vlc_player_AddListener(player, &callbacks, NULL);
    if (listener == NULL) fail("vlc_player_AddListener");
    vlc_object_t *existing = child(player);
    config_PutFloat("rate", 1.5f);
    /* argc > 1 reproduces the old config-only bridge path. The treatment is the
     * exact primitive used in Settings, rather than ChangeRate's live control. */
    if (argc == 1) var_SetFloat((vlc_object_t *)player, "rate", 1.5f);
    vlc_object_t *next = child(player);
    int success = var_GetFloat(existing, "rate") == 1.f && var_GetFloat(next, "rate") == 1.5f && rate_events == 0;
    printf("existing=%.1f next=%.1f live_rate_events=%d result=%s\n", var_GetFloat(existing, "rate"), var_GetFloat(next, "rate"), rate_events, success ? "PASS" : "FAIL");
    vlc_object_delete(existing); vlc_object_delete(next);
    vlc_player_RemoveListener(player, listener);
    vlc_player_Unlock(player);
    vlc_player_Delete(player);
    libvlc_InternalCleanup(instance); libvlc_InternalDestroy(instance);
    return success ? 0 : 1;
}
