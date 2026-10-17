/* Actual-core regression for the engine patch series in redesign/patches/engine
 * (D031, formerly D020). Generated fixture media stays outside Git.
 * The VMEM companion delegates to the stock output and records displayed PTS.
 * No next-frame, flush, or unpause/reseek workaround is used. */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#import <Foundation/Foundation.h>
#include <vlc_common.h>
#include <vlc_player.h>
#include <vlc_input_item.h>
#include <pthread.h>
#include <unistd.h>

extern libvlc_int_t *libvlc_InternalCreate(void);
extern int libvlc_InternalInit(libvlc_int_t *, int, const char *[]);
extern void libvlc_InternalCleanup(libvlc_int_t *);
extern void libvlc_InternalDestroy(libvlc_int_t *);

typedef struct {
    pthread_mutex_t lock;
    uint8_t pixels[320 * 180 * 4];
    uint64_t frames, hash, audioBuffers;
    vlc_tick_t preparedPTS, presentedPTS, bridgePTS;
} Observation;

static unsigned failures;
static bool audioOnly;
static vlc_tick_t requestedTime;

static void Check(bool condition, const char *description)
{
    printf("%s %s\n", condition ? "PASS" : "FAIL", description);
    if (!condition) failures++;
    fflush(stdout);
}

static void TimerUpdate(const struct vlc_player_timer_point *point, void *opaque)
{
    Observation *observation = opaque;
    pthread_mutex_lock(&observation->lock);
    observation->bridgePTS = point->ts;
    pthread_mutex_unlock(&observation->lock);
}

static void TimerSeek(const struct vlc_player_timer_point *point, void *opaque)
{
    /* This is also how MXRPlayerBridge preserves the requested paused time. */
    if (point != NULL) TimerUpdate(point, opaque);
}

static const struct vlc_player_timer_cbs timerCallbacks = {
    .on_update = TimerUpdate,
    .on_seek = TimerSeek,
};

static void ObservePTS(void *opaque, vlc_tick_t pts)
{
    Observation *observation = opaque;
    observation->preparedPTS = pts;
}

static void *LockPixels(void *opaque, void **planes)
{
    Observation *observation = opaque;
    planes[0] = observation->pixels;
    return observation;
}

static void DisplayPixels(void *opaque, void *picture)
{
    (void)picture;
    Observation *observation = opaque;
    uint64_t hash = 1469598103934665603ULL;
    for (size_t index = 0; index < sizeof(observation->pixels); index++) {
        hash ^= observation->pixels[index];
        hash *= 1099511628211ULL;
    }
    pthread_mutex_lock(&observation->lock);
    observation->frames++;
    observation->hash = hash;
    observation->presentedPTS = observation->preparedPTS;
    pthread_mutex_unlock(&observation->lock);
}

static void AudioPlay(void *opaque, const void *samples, unsigned count, int64_t date)
{
    (void)samples; (void)count; (void)date;
    Observation *observation = opaque;
    pthread_mutex_lock(&observation->lock);
    observation->audioBuffers++;
    pthread_mutex_unlock(&observation->lock);
}

static void Wait(double seconds)
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode
                           beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

static vlc_tick_t Time(vlc_player_t *player)
{
    vlc_player_Lock(player);
    vlc_tick_t value = vlc_player_GetTime(player);
    vlc_player_Unlock(player);
    return value;
}

static enum vlc_player_state State(vlc_player_t *player)
{
    vlc_player_Lock(player);
    enum vlc_player_state value = vlc_player_GetState(player);
    vlc_player_Unlock(player);
    return value;
}

static void Report(const char *name, Observation *observation, vlc_player_t *player)
{
    pthread_mutex_lock(&observation->lock);
    vlc_tick_t presented = observation->presentedPTS, bridge = observation->bridgePTS;
    uint64_t frames = observation->frames, hash = observation->hash, audioBuffers = observation->audioBuffers;
    pthread_mutex_unlock(&observation->lock);
    printf("OBS %s state=%d time=%.6f picture=%.6f bridgeTime=%.6f frames=%llu hash=%016llx PCM=%llu\n",
           name, State(player), (double)Time(player) / CLOCK_FREQ,
           (double)presented / CLOCK_FREQ, (double)bridge / CLOCK_FREQ,
           (unsigned long long)frames, (unsigned long long)hash,
           (unsigned long long)audioBuffers);
    fflush(stdout);
}

static void Seek(Observation *observation, vlc_player_t *player,
                 const char *name, vlc_tick_t value, int kind, bool paused)
{
    vlc_tick_t expected = kind == 1 ? (paused ? requestedTime : Time(player)) + value : value;
    if (paused) requestedTime = expected;
    pthread_mutex_lock(&observation->lock);
    uint64_t oldFrames = observation->frames, oldHash = observation->hash;
    pthread_mutex_unlock(&observation->lock);

    vlc_player_Lock(player);
    if (kind == 1) vlc_player_JumpTime(player, value);
    else if (kind == 2)
        vlc_player_SeekByPos(player, (double)value / vlc_player_GetLength(player),
                            VLC_PLAYER_SEEK_PRECISE, VLC_PLAYER_WHENCE_ABSOLUTE);
    else vlc_player_SetTime(player, value);
    vlc_player_Unlock(player);

    bool targetReached = false;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:4];
    do {
        Wait(0.01);
        pthread_mutex_lock(&observation->lock);
        targetReached = audioOnly
            ? llabs(observation->bridgePTS - expected) < VLC_TICK_FROM_MS(200)
            : observation->frames > oldFrames && observation->hash != oldHash
              && llabs(observation->presentedPTS - expected) < VLC_TICK_FROM_MS(200);
        pthread_mutex_unlock(&observation->lock);
    } while (!targetReached && deadline.timeIntervalSinceNow > 0);
    Report(name, observation, player);
    Check(targetReached, name);
    Check(State(player) == (paused ? VLC_PLAYER_STATE_PAUSED : VLC_PLAYER_STATE_PLAYING),
          "seek preserves requested transport state");
    if (paused) {
        pthread_mutex_lock(&observation->lock);
        bool timeline = llabs(observation->bridgePTS - expected) < VLC_TICK_FROM_MS(200);
        pthread_mutex_unlock(&observation->lock);
        Check(timeline, "native callback timeline matches paused seek");
    }
}

static void ResumeAndCheck(Observation *observation, vlc_player_t *player)
{
    vlc_player_Lock(player);
    vlc_player_Resume(player);
    vlc_player_Unlock(player);
    /* Hardware audio timing disables interpolation for its first point; test
     * sustained playback after two timing reports, as at a normal playing seek. */
    Wait(2.5);
    vlc_tick_t first = Time(player);
    pthread_mutex_lock(&observation->lock);
    vlc_tick_t firstPicture = observation->presentedPTS;
    pthread_mutex_unlock(&observation->lock);
    bool aligned = audioOnly || llabs(firstPicture - first) < VLC_TICK_FROM_MS(400);
    Check(State(player) == VLC_PLAYER_STATE_PLAYING && aligned
          && llabs(first - requestedTime - VLC_TICK_FROM_MS(2500)) < VLC_TICK_FROM_MS(500),
          "resume preserves media position and audio/video clock alignment");
    Wait(1);
    pthread_mutex_lock(&observation->lock);
    vlc_tick_t secondPicture = observation->presentedPTS;
    pthread_mutex_unlock(&observation->lock);
    Check(Time(player) > first + VLC_TICK_FROM_MS(700)
          && (audioOnly || secondPicture > firstPicture + VLC_TICK_FROM_MS(700)),
          "sustained resume advances clock and displayed pictures");
    Report("resumed", observation, player);
}

int main(int argc, const char **argv)
{
    @autoreleasepool {
        if (argc != 5) {
            fprintf(stderr, "usage: paused-seek-smoke MEDIA software|videotoolbox auhal|amem video|silent|audio\n");
            return 2;
        }
        bool software = strcmp(argv[2], "software") == 0;
        bool memoryAudio = strcmp(argv[3], "amem") == 0;
        audioOnly = strcmp(argv[4], "audio") == 0;
        bool silent = strcmp(argv[4], "silent") == 0;
        Observation observation = {0};
        pthread_mutex_init(&observation.lock, NULL);
        libvlc_int_t *instance = libvlc_InternalCreate();
        if (instance == NULL) return 3;
        var_Create(instance, "vmem-lock", VLC_VAR_ADDRESS);
        var_SetAddress(instance, "vmem-lock", LockPixels);
        var_Create(instance, "vmem-display", VLC_VAR_ADDRESS);
        var_SetAddress(instance, "vmem-display", DisplayPixels);
        var_Create(instance, "vmem-data", VLC_VAR_ADDRESS);
        var_SetAddress(instance, "vmem-data", &observation);
        var_Create(instance, "seek-vmem-pts", VLC_VAR_ADDRESS);
        var_SetAddress(instance, "seek-vmem-pts", ObservePTS);
        var_Create(instance, "amem-play", VLC_VAR_ADDRESS);
        var_SetAddress(instance, "amem-play", AudioPlay);
        var_Create(instance, "amem-data", VLC_VAR_ADDRESS);
        var_SetAddress(instance, "amem-data", &observation);
        const char *options[] = {
            "paused-seek-smoke", "--ignore-config", "--no-media-library",
            memoryAudio ? "--aout=amem" : "--aout=auhal",
            memoryAudio ? "--clock-master=monotonic" : "--clock-master=auto",
            "--vout=mxr_seek_vmem,none", "--vmem-chroma=RV32", "--vmem-width=320",
            "--vmem-height=180", "--vmem-pitch=1280", "--no-spu", "--no-osd",
            "--no-metadata-network-access", "--no-auto-preparse", "--no-plugins-cache",
            "--verbose=2", software ? "--codec=avcodec,none" : "--codec=videotoolbox,avcodec,none",
            "--no-volume-save", "--auhal-volume=0", silent ? "--no-audio" : "--audio",
            "--stats", "--stats-min-report-interval=100",
        };
        if (libvlc_InternalInit(instance, sizeof(options) / sizeof(options[0]), options)) return 4;
        vlc_player_t *player = vlc_player_New(VLC_OBJECT(instance), VLC_PLAYER_LOCK_NORMAL);
        if (player == NULL) return 5;
        vlc_player_timer_id *timer = vlc_player_AddTimer(player, VLC_TICK_INVALID,
                                                       &timerCallbacks, &observation);
        if (timer == NULL) return 6;
        NSString *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]].absoluteString;
        input_item_t *item = input_item_New(url.UTF8String, NULL);
        if (item == NULL) return 7;
        vlc_player_Lock(player);
        vlc_player_SetCurrentMedia(player, item);
        int result = vlc_player_Start(player);
        vlc_player_Unlock(player);
        input_item_Release(item);
        if (result != VLC_SUCCESS) return 8;
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:12];
        while (Time(player) < VLC_TICK_FROM_SEC(7) && deadline.timeIntervalSinceNow > 0) Wait(0.01);
        Check(Time(player) >= VLC_TICK_FROM_SEC(7), "actual input plays to initial position");
        vlc_player_Lock(player);
        Check(audioOnly ? vlc_player_GetTrackCount(player, VIDEO_ES) == 0
                        : vlc_player_GetTrackCount(player, VIDEO_ES) > 0,
              "fixture has the requested video track topology");
        vlc_player_Pause(player);
        vlc_player_Unlock(player);
        Wait(2);
        requestedTime = Time(player);
        Report("paused", &observation, player);
        Seek(&observation, player, "absolute17", VLC_TICK_FROM_SEC(17), 0, true);
        if (!audioOnly) {
            Seek(&observation, player, "absolute7", VLC_TICK_FROM_SEC(7), 0, true);
            Seek(&observation, player, "relative+10", VLC_TICK_FROM_SEC(10), 1, true);
            Seek(&observation, player, "position27", VLC_TICK_FROM_SEC(27), 2, true);
            Seek(&observation, player, "absolute3", VLC_TICK_FROM_SEC(3), 0, true);
            Seek(&observation, player, "relative+10again", VLC_TICK_FROM_SEC(10), 1, true);
            Seek(&observation, player, "relative-10", -VLC_TICK_FROM_SEC(10), 1, true);
            Seek(&observation, player, "position52", VLC_TICK_FROM_SEC(52), 2, true);
        }
        Seek(&observation, player, "position12", VLC_TICK_FROM_SEC(12), 2, true);
        pthread_mutex_lock(&observation.lock);
        uint64_t heldHash = observation.hash;
        pthread_mutex_unlock(&observation.lock);
        Wait(1);
        pthread_mutex_lock(&observation.lock);
        Check(observation.hash == heldHash, "sustained pause retains target pixels");
        pthread_mutex_unlock(&observation.lock);
        Check(State(player) == VLC_PLAYER_STATE_PAUSED, "sustained pause remains paused");
        ResumeAndCheck(&observation, player);
        if (!audioOnly) {
            Seek(&observation, player, "playing30", VLC_TICK_FROM_SEC(30), 0, false);
            Wait(2.5);
            Seek(&observation, player, "playing+10", VLC_TICK_FROM_SEC(10), 1, false);
        }
        vlc_player_Lock(player);
        vlc_player_Pause(player);
        vlc_player_Unlock(player);
        Wait(1);
        Seek(&observation, player, "secondPause21", VLC_TICK_FROM_SEC(21), 0, true);
        ResumeAndCheck(&observation, player);
        vlc_player_Lock(player);
        const struct input_stats_t *stats = vlc_player_GetStatistics(player);
        if (!silent) Check(stats != NULL && stats->i_decoded_audio > 0 && stats->i_played_abuffers > 0,
                           "real audio decode and output buffers");
        else Check(stats != NULL && stats->i_decoded_audio == 0 && stats->i_played_abuffers == 0,
                   "silent control has no decoded or played audio");
        if (audioOnly) {
            pthread_mutex_lock(&observation.lock);
            Check(observation.frames == 0, "audio-only control presents no video frames");
            pthread_mutex_unlock(&observation.lock);
        }
        vlc_player_Stop(player);
        vlc_player_Unlock(player);
        vlc_player_RemoveTimer(player, timer);
        __block BOOL finished = NO;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            vlc_player_Delete(player);
            libvlc_InternalCleanup(instance);
            libvlc_InternalDestroy(instance);
            dispatch_async(dispatch_get_main_queue(), ^{ finished = YES; });
        });
        deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (!finished && deadline.timeIntervalSinceNow > 0) Wait(0.01);
        Check(finished, "bounded clean stop and shutdown");
        if (!finished) _exit(1);
        pthread_mutex_destroy(&observation.lock);
        printf("SUMMARY failures=%u\n", failures);
        return failures != 0;
    }
}
