/* Pause/reset/resume clock contract of engine patches 0003 and 0005 (D031).
 * Compile with test-clock-pause-reset.sh; no player or hardware is started. */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#include <vlc_common.h>
#include <vlc_tick.h>
#include <vlc_es.h>
#include "clock.h"
#include <assert.h>
#include <stdio.h>

const char vlc_module_name[] = "mxr-clock-pause-reset-test";
static unsigned failures;

static void check(const char *name, bool paused, bool reset, bool set_pcr,
                  bool monotonic, unsigned repeats)
{
    vlc_clock_main_t *main_clock = vlc_clock_main_New(NULL, NULL);
    assert(main_clock != NULL);
    vlc_clock_main_Lock(main_clock);
    vlc_clock_main_SetInputDejitter(main_clock, 0);
    vlc_clock_main_SetDejitter(main_clock, 0);
    vlc_clock_t *input = vlc_clock_main_CreateInputSlave(main_clock);
    vlc_clock_t *master = vlc_clock_main_CreateMaster(main_clock, "Audio", NULL, NULL);
    vlc_clock_t *slave = vlc_clock_main_CreateSlave(main_clock, "Video", VIDEO_ES,
                                                 NULL, NULL);
    assert(input != NULL && master != NULL && slave != NULL);

    const vlc_tick_t old_system = VLC_TICK_FROM_SEC(10);
    const vlc_tick_t pause = VLC_TICK_FROM_SEC(11);
    const vlc_tick_t target = VLC_TICK_FROM_SEC(17);
    const vlc_tick_t resume = VLC_TICK_FROM_SEC(14);
    vlc_clock_main_SetFirstPcr(main_clock, old_system, VLC_TICK_0);
    if (monotonic)
        (void)vlc_clock_ConvertToSystem(slave, old_system, VLC_TICK_0, 1, NULL);
    else
        vlc_clock_Update(master, old_system, VLC_TICK_0, 1);
    if (paused)
        vlc_clock_main_ChangePause(main_clock, pause, true);

    for (unsigned i = 0; i < repeats; ++i)
    {
        if (reset)
            vlc_clock_main_Reset(main_clock);
        if (set_pcr)
            vlc_clock_main_SetFirstPcr(main_clock, pause, target);
        if (reset || set_pcr)
        {
            if (monotonic)
                (void)vlc_clock_ConvertToSystem(slave, pause, target, 1, NULL);
            else
                vlc_clock_Update(master, pause, target, 1);
        }
    }

    const vlc_tick_t anchor = reset || set_pcr ? pause : old_system;
    const vlc_tick_t stream = reset || set_pcr ? target : VLC_TICK_0;
    const vlc_tick_t before = vlc_clock_ConvertToSystem(slave, pause, stream, 1, NULL);
    if (paused)
        vlc_clock_main_ChangePause(main_clock, resume, false);
    const vlc_tick_t after = vlc_clock_ConvertToSystem(slave, resume,
                                stream + VLC_TICK_FROM_MS(250), 1, NULL);
    const vlc_tick_t expected = anchor + (paused ? resume - pause : 0)
                                + VLC_TICK_FROM_MS(250);
    const bool ok = before == anchor && after == expected
                    && !vlc_clock_IsPaused(slave);
    failures += !ok;
    printf("CLOCK_PAUSE_RESET %s before=%"PRId64" after=%"PRId64
           " expected=%"PRId64" lost_pause=%"PRId64" PASS=%d\n",
           name, before, after, expected, expected - after, ok);

    vlc_clock_main_Unlock(main_clock);
    vlc_clock_Delete(slave);
    vlc_clock_Delete(master);
    vlc_clock_Delete(input);
    vlc_clock_main_Delete(main_clock);
}

/* An audio output can request its first post-seek date later in the pause,
 * before it has a hardware timing report. The fallback must use the frozen
 * origin so resume does not add the elapsed pause to an already current date. */
static void check_late_reference(const char *name, bool paused, bool audio_master)
{
    vlc_clock_main_t *main_clock = vlc_clock_main_New(NULL, NULL);
    assert(main_clock != NULL);
    vlc_clock_main_Lock(main_clock);
    vlc_clock_main_SetInputDejitter(main_clock, 0);
    vlc_clock_main_SetDejitter(main_clock, 0);
    vlc_clock_t *input = vlc_clock_main_CreateInputSlave(main_clock);
    vlc_clock_t *master = vlc_clock_main_CreateMaster(main_clock, "Audio", NULL, NULL);
    vlc_clock_t *slave = vlc_clock_main_CreateSlave(main_clock, "Video", VIDEO_ES,
                                                 NULL, NULL);
    assert(input != NULL && master != NULL && slave != NULL);
    const vlc_tick_t pause = VLC_TICK_FROM_SEC(11);
    const vlc_tick_t late_now = VLC_TICK_FROM_SEC(13);
    const vlc_tick_t resume = VLC_TICK_FROM_SEC(14);
    const vlc_tick_t target = VLC_TICK_FROM_SEC(17);
    vlc_clock_main_SetFirstPcr(main_clock, VLC_TICK_FROM_SEC(10), VLC_TICK_0);
    vlc_clock_Update(master, VLC_TICK_FROM_SEC(10), VLC_TICK_0, 1);
    if (paused)
        vlc_clock_main_ChangePause(main_clock, pause, true);
    vlc_clock_main_Reset(main_clock);
    vlc_clock_main_SetFirstPcr(main_clock, pause, target);

    const vlc_tick_t before = vlc_clock_ConvertToSystem(
        audio_master ? master : slave, late_now, target, 1, NULL);
    if (paused)
        vlc_clock_main_ChangePause(main_clock, resume, false);
    const vlc_tick_t after = vlc_clock_ConvertToSystem(slave, resume,
                                target + VLC_TICK_FROM_MS(250), 1, NULL);
    const vlc_tick_t expected_before = paused ? pause : late_now;
    const vlc_tick_t expected_after = (paused ? resume : late_now)
                                    + VLC_TICK_FROM_MS(250);
    const bool ok = before == expected_before && after == expected_after
                    && !vlc_clock_IsPaused(slave);
    failures += !ok;
    printf("CLOCK_PAUSE_RESET %s before=%"PRId64" after=%"PRId64
           " expected=%"PRId64" PASS=%d\n", name, before, after, expected_after, ok);
    vlc_clock_main_Unlock(main_clock);
    vlc_clock_Delete(slave);
    vlc_clock_Delete(master);
    vlc_clock_Delete(input);
    vlc_clock_main_Delete(main_clock);
}

int main(void)
{
    check("master pause without reset", true, false, false, false, 1);
    check("master playing reset", false, true, true, false, 1);
    check("master paused reset and PCR", true, true, true, false, 1);
    check("master paused PCR only", true, false, true, false, 1);
    check("master paused repeated reset", true, true, true, false, 5);
    check("monotonic pause without reset", true, false, false, true, 1);
    check("monotonic playing reset", false, true, true, true, 1);
    check("monotonic paused reset and PCR", true, true, true, true, 1);
    check("monotonic paused repeated reset", true, true, true, true, 5);
    check_late_reference("late paused audio fallback", true, true);
    check_late_reference("late paused video fallback", true, false);
    check_late_reference("late playing audio fallback", false, true);
    check_late_reference("late playing video fallback", false, false);
    printf("SUMMARY scenarios=13 failures=%u\n", failures);
    return failures == 0 ? 0 : 1;
}
