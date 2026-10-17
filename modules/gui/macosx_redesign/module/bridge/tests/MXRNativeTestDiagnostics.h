/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
/*
 * Deadline diagnostics for the headless engine harnesses.
 *
 * A missed deadline used to print only "FAIL: <message>", which says nothing
 * about which engine step was still running (for example the silent stretch of
 * libvlc_InternalCleanup after "removing keystore memory"). These helpers keep
 * a timestamped record of the current harness phase and of the last engine log
 * line, and on a missed deadline print both and attach a `sample` call graph of
 * the still-running process, so the slow step is visible in the failure log.
 *
 * The sample is written to $MXR_NATIVE_EVIDENCE_DIR (set by tools/native-tests.py
 * to its work directory, which is kept after a failure) and copied to stderr.
 */
#ifndef MXR_NATIVE_TEST_DIAGNOSTICS_H
#define MXR_NATIVE_TEST_DIAGNOSTICS_H

#import <Foundation/Foundation.h>
#include <os/lock.h>
#include <spawn.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

typedef struct {
    _Atomic uint64_t start;
    _Atomic uint64_t phaseAt;
    _Atomic(const char *) phase;
    os_unfair_lock lock;
    char lastLog[512];
    uint64_t lastLogAt;
} MXRNativeDiagnosticsState;

static MXRNativeDiagnosticsState MXRNativeDiagnostics = {.lock = OS_UNFAIR_LOCK_INIT};

static inline uint64_t MXRNativeDiagnosticsNow(void)
{
    return clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1000000;
}

/* Milliseconds since the first diagnostics call in this process. */
static inline uint64_t MXRNativeDiagnosticsElapsed(void)
{
    uint64_t now = MXRNativeDiagnosticsNow(), zero = 0;
    atomic_compare_exchange_strong(&MXRNativeDiagnostics.start, &zero, now);
    return now - atomic_load(&MXRNativeDiagnostics.start);
}

/* Names the harness step that is about to run; `phase` must be a string literal. */
static inline void MXRNativeDiagnosticsPhase(const char *phase)
{
    uint64_t at = MXRNativeDiagnosticsElapsed();
    atomic_store(&MXRNativeDiagnostics.phaseAt, at);
    atomic_store(&MXRNativeDiagnostics.phase, phase);
    fprintf(stderr, "[+%llu ms] phase: %s\n", (unsigned long long)at, phase);
}

/* Records an engine log line (any thread) and returns its timestamp. */
static inline uint64_t MXRNativeDiagnosticsNoteLog(const char *message)
{
    uint64_t at = MXRNativeDiagnosticsElapsed();
    os_unfair_lock_lock(&MXRNativeDiagnostics.lock);
    strlcpy(MXRNativeDiagnostics.lastLog, message, sizeof(MXRNativeDiagnostics.lastLog));
    MXRNativeDiagnostics.lastLogAt = at;
    os_unfair_lock_unlock(&MXRNativeDiagnostics.lock);
    return at;
}

/* Prints phase/last-log ages and a call graph of every live thread. */
static inline void MXRNativeDiagnosticsDump(const char *why, double sampleSeconds)
{
    uint64_t now = MXRNativeDiagnosticsElapsed();
    const char *phase = atomic_load(&MXRNativeDiagnostics.phase);
    uint64_t phaseAt = atomic_load(&MXRNativeDiagnostics.phaseAt);
    char last[sizeof(MXRNativeDiagnostics.lastLog)]; uint64_t lastAt;
    os_unfair_lock_lock(&MXRNativeDiagnostics.lock);
    strlcpy(last, MXRNativeDiagnostics.lastLog, sizeof(last)); lastAt = MXRNativeDiagnostics.lastLogAt;
    os_unfair_lock_unlock(&MXRNativeDiagnostics.lock);
    fprintf(stderr, "DEADLINE MISSED at +%llu ms: %s\n", (unsigned long long)now, why);
    fprintf(stderr, "  current phase: %s (running for %llu ms)\n", phase ? phase : "(none)",
            (unsigned long long)(phase ? now - phaseAt : 0));
    fprintf(stderr, "  last engine log: \"%s\" (%llu ms ago)\n", last[0] ? last : "(none)",
            (unsigned long long)(last[0] ? now - lastAt : 0));
    const char *directory = getenv("MXR_NATIVE_EVIDENCE_DIR");
    char path[1024];
    snprintf(path, sizeof(path), "%s/deadline-sample-%d-%llu.txt",
             directory && directory[0] ? directory : "/private/tmp", getpid(), (unsigned long long)now);
    char pid[16], seconds[16];
    snprintf(pid, sizeof(pid), "%d", getpid());
    snprintf(seconds, sizeof(seconds), "%d", sampleSeconds < 1 ? 1 : (int)sampleSeconds);
    const char *argv[] = {"/usr/bin/sample", pid, seconds, "-mayDie", "-file", path, NULL};
    pid_t sampler;
    int status = 0;
    if (posix_spawn(&sampler, argv[0], NULL, NULL, (char *const *)argv, environ) != 0
        || waitpid(sampler, &status, 0) < 0 || !WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        fprintf(stderr, "  call graph unavailable (sample failed, status %d)\n", status);
        return;
    }
    fprintf(stderr, "  call graph of every thread (%s):\n", path);
    FILE *file = fopen(path, "r");
    if (!file) return;
    char line[2048];
    while (fgets(line, sizeof(line), file)) fputs(line, stderr);
    fclose(file);
}

/* Pumps the main run loop until `done`, dumping diagnostics if the deadline passes. */
static inline BOOL MXRNativeDiagnosticsPumpUntil(BOOL (^done)(void), NSTimeInterval seconds, const char *what)
{
    uint64_t began = MXRNativeDiagnosticsElapsed();
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!done() && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    if (done()) {
        fprintf(stderr, "[+%llu ms] done in %llu ms: %s\n", (unsigned long long)MXRNativeDiagnosticsElapsed(),
                (unsigned long long)(MXRNativeDiagnosticsElapsed() - began), what);
        return YES;
    }
    MXRNativeDiagnosticsDump(what, 1);
    return NO;
}

#endif
