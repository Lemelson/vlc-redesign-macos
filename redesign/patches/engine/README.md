# Engine patches (quarantined, optional)

Our branches keep `src/` identical to upstream VLC (D004, D031). This directory holds the
one engine fix we found worth carrying: **a seek while paused does not show the target
frame** in VLC 4, and resuming after such a seek can stall or lose sync. The bug is in
stock VLC 4 too (the stock macOS and Qt interfaces call the same player API). The fix
belongs upstream; until then these patches are applied only to a copy of the source and
only when asked for.

The interface works without them: while paused, a seek shows the exact-time thumbnail as
a still over the video until the next real frame arrives (D031).

## The series

Apply in order. Each patch is in `git format-patch` form, with the reproduction in its
message (summarised from D020 and the 2026-10-14 review, ARC-13).

| Patch | File | Change | Upstream |
|---|---|---|---|
| 0001 | `src/input/decoder.c` | Force the first picture of a paused seek; it was dropped as late. | Narrow. Propose first. |
| 0002 | `src/input/es_out.c` | Convert PCRs received while paused with the frozen pause date, not `vlc_tick_now()`. | Narrow. Propose with 0001. |
| 0003 | `src/clock/clock.c` | Keep `pause_date` across a reset while paused, so resume shifts new references. | Reverses a stated upstream intent; needs 0005. |
| 0004 | `src/input/decoder.c` | Resume a paused video output from `ChangePause(false)` (VideoToolbox pacer stall). | Input thread drives the vout under the FIFO lock; needs separate justification. |
| 0005 | `src/clock/clock.c` | Create the monotonic fallback reference on the pause date while paused. | Needs 0003. |

0001 and 0002 fix the visible bug. 0003–0005 fix what the earlier patches exposed on resume.
They change A/V-sync code that upstream reworks often. If upstream fixes the root cause
differently, drop them.

Possibly related upstream reports (found by title, not verified):
[#25315](https://code.videolan.org/videolan/vlc/-/issues/25315),
[#22456](https://code.videolan.org/videolan/vlc/-/issues/22456).

## Building with the patches

```sh
MXR_ENGINE_PATCHES=1 modules/gui/macosx_redesign/tools/build-native.sh \
    ../build/codex-arm64-engine-patches \
    ../build/arm64 \
    ../vlc-redesign-macos
```

`build-native.sh` mirrors the checkout into `<build-dir>/engine-source`, applies the series
there and configures the build against that copy. Use a build directory of its own: the
script refuses to switch a build directory between the checkout and a patched copy. The
build's revision string ends in `-engine-patches`, and `engine-source/.mxr-engine-patches`
records the source commit and the patch hashes. Re-run the script, not a bare `make`,
after editing the checkout: the script re-syncs the copy (only changed files are touched,
so builds stay incremental).

Without `MXR_ENGINE_PATCHES=1`, the script builds the unmodified engine and stops with an
error if any patch is already in `src/`.

`engine-patches.sh` does the work and can be used on its own:

- `engine-patches.sh check` fails if a patch is already in the checkout's `src/`. That
  happens when upstream merged it (delete the patch) or when someone edited `src/` (restore
  it). It warns when a patch no longer applies.
- `engine-patches.sh files OUT` writes only the patched files under `OUT`.
- `engine-patches.sh copy DEST` mirrors the checkout into `DEST` and patches it.

Never `git apply` these patches in a checkout you commit from. To experiment by hand, use a
throwaway worktree: `git worktree add --detach ../engine-try HEAD`, then
`git -C ../engine-try am redesign/patches/engine/0*.patch`, then
`git worktree remove ../engine-try` when you are done.

## Tests

- `tests/test-clock-pause-reset.sh BUILD OUT` compiles the real `clock.c` with the series
  applied and runs 13 pause/reset/resume cases on the public clock API (no player, no
  hardware). Expected: 0 failures. With `--unpatched` it uses the checkout's `clock.c` and
  is expected to fail (7 of 13 on upstream `4ca4eb0c3e`; 2 with 0003 but without 0005).
  `BUILD` is any configured native build with `macos-install/lib/libvlccore.dylib`.
- `tests/run-paused-seek-smoke.sh` runs a real player on generated media: paused absolute,
  relative and positional seeks, sustained pause, two resumes, playing seeks and clean
  shutdown, checking displayed picture PTS. Topologies: `software|videotoolbox`,
  `auhal|amem`, `video|silent|audio`. The unpatched core fails (12 failures in video
  mode); a core built with `MXR_ENGINE_PATCHES=1` passes all four recorded rows. Do not
  run it while someone is using the app (it opens audio output).

## When upstream changes

`build-native.sh` checks the series on every build. If upstream merges a patch, the build
stops and names it: delete that patch file. If upstream changes the code around a patch,
patched builds stop: refresh the patch against current `src/`, or drop it if upstream
fixed the bug another way.
