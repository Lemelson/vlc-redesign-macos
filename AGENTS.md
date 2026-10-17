# AGENTS.md — VLC Redesign for macOS

This repository is a fork of VLC (`videolan/vlc`). It adds a **new native macOS
interface** that reproduces Juxtopposed's VLC redesign 1:1, on top of an
**unmodified VLC engine**. Everything except `redesign/` and
`modules/gui/macosx_redesign/` is upstream VLC; treat it as read-only. Optional
engine fixes are kept as patches in `redesign/patches/engine/` and are never
applied to this tree (D031).

## Read before doing anything

1. `redesign/docs/PHILOSOPHY.md`: what we build and why; sources of truth; principles.
2. `redesign/docs/DECISIONS.md`: decisions already made (don't relitigate silently).
3. `redesign/docs/PLAN.md`: phases and current priorities.
4. `redesign/docs/WORKFLOW.md`: how to take a task, the verify loop, definition of done.
5. `redesign/docs/ARCHITECTURE.md` and `redesign/docs/BUILD.md`: module layout, VLC APIs, building.

## Where things are

| Path | What |
|---|---|
| `redesign/design/SCREENS.md` | Master list of screens and panels (S-ids) with status. Pick work here. |
| `redesign/design/figma/` | Figma data: `figma_file.json`, `renders/` (4K PNGs), `icons-svg/`, `INDEX.md`, `ICONS.md` |
| `redesign/design/tokens/` | Canonical colors, typography and metrics extracted from Figma |
| `redesign/design/spec/` | Detailed specs written from the video (`spec-part1.md` 01–08, `spec-part2.md` 09–16) |
| `redesign/docs/design/VIDEO_BREAKDOWN.md` | The video section by section: intent, rules, key frames, matching renders |
| `redesign/research/` | `FORKS.md` (community forks, verdicts) and `analysis/` (deep reports). `from-forks/` holds specs and research copied from forks |
| `redesign/tools/` | `fetch-reference.sh` (local video and frames), `add-fork-remotes.sh` (fork remotes) |
| `modules/gui/macosx_redesign/` | Our interface module (created in phase 0) |
| `../reference/` (outside the repo, local only) | Video, transcript (`transcript.txt`, Russian `transcript.ru.md`), frames by topic, `key-frames/`, standalone implementations. Never commit it. |

## Hard rules

- Don't modify upstream files beyond the short list in `ARCHITECTURE.md`. Engine changes need a `DECISIONS.md` entry first.
- Visual values come from Figma tokens, never from video frames or guesses. No literal colors or sizes in views.
- Native macOS behavior (traffic lights, menu bar, fullscreen, PiP, media keys, accessibility) with the Figma look.
- Every UI change is checked visually against its Figma render before it's called done. A different agent verifies it.
- Never commit the video, frames, transcript, or anything else under `../reference/`.
- Merge `upstream/master`; never rebase published history.
- Build and install the app only with `modules/gui/macosx_redesign/tools/install-app.sh`: it produces exactly one copy, `/Applications/VLC Redesign.app` (own icon), and removes the build-dir `VLC.app`. Never leave other VLC bundles around, never touch `/Applications/VLC.app` (the owner's official VLC).
- Remotes named `fork-*` are other people's work: read-only references. Never push there.

## Credits

Design: Juxtopposed (CC BY 4.0). Engine: VideoLAN and the VLC contributors (GPL-2.0-or-later).
