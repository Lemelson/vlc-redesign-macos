# Plan

Phases are sequential at the edges and parallel inside. Each phase lists its
exit criteria. Screen ids refer to `redesign/design/SCREENS.md` (72 screens).
How to execute a task is described in `WORKFLOW.md`; technical design is in
`ARCHITECTURE.md`; building is in `BUILD.md`.

```
P0 Foundations ──► P1 Player shell ──► P2 Side panels & subtitles ──► P3 Library ──► P4 Settings ──► P5 Customization ──► P6 Release
                    (design system grows alongside each phase; upstream merged weekly throughout)
```

## P0 — Foundations (spike)

Goal: prove the whole pipeline end to end on a tiny scope, so that later phases are
mostly UI work.

| # | Task | Output | Parallel? |
|---|---|---|---|
| 0.1 | Free disk space: ≥ 12 GB free is the minimum, 30 GB is comfortable | — | owner |
| 0.2 | Build **stock** VLC.app from `main` with prebuilt contribs (`BUILD.md`) and record times, sizes and gotchas in `NOTES.md` | baseline app | A |
| 0.3 | Module skeleton: `configure.m4`, `Makefile.am`, `module.c` and the 3 upstream touches (`ARCHITECTURE.md` §6); interface opens an `NSWindow` and plays a file through our `vout window` | first "hello video" | after 0.2 |
| 0.4 | SwiftPM package skeleton: `MXRCore`, `MXRDesign`, `MXRUI`, `MXRMockBackend`, `MXRGallery`; static `MXRPlugin` force-loaded into the dylib | builds standalone | B |
| 0.5 | Token generator: `design/tokens/*.json` → `Theme.swift` (colors with light/dark and accent, fonts, metrics). Bundle Inter (OFL) | `MXRDesign` | B |
| 0.6 | Icon pipeline: `icons-svg/` → asset catalog (template images for mono icons; two-layer for two-tone); add the missing `check` icon | asset catalog | C |
| 0.7 | `redesign/tools/visual-diff`: render a SwiftUI view at a given size and scale to PNG, compare with a Figma render, output diff image + score | tool | C |
| 0.8 | Resolve `ARCHITECTURE.md` §9 open items 1–3, 6, 7 | notes | after 0.3 |
| 0.9 | Optional: save the Figma file locally (`.fig`) and run Green-Skeleton's decoder to get exact vectors | full vectors | owner + D |

**Exit:** VLC.app built from this repo starts with our interface and plays a video in
our window; the Gallery app shows the token and icon pages; visual-diff compares a
gallery view against a render.

## P1 — Player shell & controls (S01–S13)

Design-system components first, then screens.

- **Components:**
  - `IconButton` (mono, two-tone, active)
  - `PlayButton` (paused/playing)
  - `SeekBar` (thick, buffered, hover time, thumbnail slot, resume marker)
  - `VolumeCone` (0–200%, gradient, tooltip)
  - `TimeLabel` (editable, elapsed/remaining)
  - `TopBar`, `ControlBar`
  - styled menus and popovers
  - hover-reveal container
- **Screens:** player window (S01), time labels (S02), seek thumbnails (S03),
  volume (S04), fullscreen and hover reveal (S05), hide-UI (S06), `⋯` menu
  (S07/S08), right-click menu (S09/S10), native menu bar (S11), continue
  watching (S12), OSD with pressed key (S13).
- **Platform:** traffic lights (D007), native fullscreen, media keys and Now Playing,
  PiP via the stock approach.

**Exit:** daily-drivable player for local files. Every P1 screen verified against
Figma; idle CPU and frame pacing equal to stock VLC.

> **Milestone: public preview.** Publish the repo, a demo video, and an
> announcement (see "Community" below).

## P2 — Side panels & subtitles

- Track popovers: subtitles, audio + output device, video.
- The 400 px right sidebar with Playback / Video / Audio / Subtitles tabs:
  - sliders for delays;
  - subtitle font, size (relative or precise), outline, position;
  - audio filters with presets and the equalizer;
  - video filters with previews;
  - speed, sleep timer.
- Presets per show (new storage; see `research/from-forks/floklein-research/persistence-*`).
- Subtitle timeline (cue parsing in the interface layer).
- Add Subtitles dialog: file / folder / playlist scope; local or link source;
  episode matching. OpenSubtitles needs an API key (D014).
- Queue panel with Bookmarks and Chapters tabs; bookmarks with ⌘B.

**Exit:** a whole season can be watched with external subtitles synced once and
remembered.

## P3 — Library, music, streams, playlists

- Compact library panel beside the video; full-window library with mini player.
- Breadcrumb navigation, sort, view modes, search; "unwatched first" ordering.
- Home, Recent, Pins.
- Music: songs, albums, artists, genres; large cover-art player; optional waveform seek bar (research).
- Network streams: M3U playlists such as public TV lists.
- Split "Open" dialogs: file, folder, network, capture, disc, clipboard. Convert and Stream.
- Playlists: create, add to.

Backed by `vlc_media_library` (`ARCHITECTURE.md` §5.6).

## P4 — Settings & hotkeys

- 13 categories driven by the settings mapping file (D013).
- Basic options first, then Advanced; an info popover for every row; human-readable dropdowns.
- Schema drift check: a dump submodule plus CI diff.
- Keyboard Shortcuts dialog with live remapping via `key-action` (`ARCHITECTURE.md` §5.3); global hotkeys.
- Extensions, add-ons and plugins split as in the design.
- Theme (dark/light) and accent color.

## P5 — Customization, onboarding, profiles

- Drag-and-drop control-bar layout editor.
- Profiles that switch layout and settings.
- Onboarding: theme, accent, basic shortcuts.

## P6 — Release

- **Quality:** performance pass with Instruments; full accessibility audit; localization
  (String Catalog; reuse VLC translations where strings match).
- **Branding (D010):** decide the name and icon; own bundle id and update feed.
- **Distribution:** signing and notarization, DMG, update channel.
- **Documentation:** user docs, contribution guide, screenshots.

## Running agents in parallel

Within a phase, assign one agent per component or screen, each in its own worktree
(`WORKFLOW.md`). Recommended roles:

| Role | Does | Typical count |
|---|---|---|
| **Builder** | Implements one screen or component against the mock backend, then wires it | 3–8 |
| **Verifier** | Independently compares with the Figma render and video intent; checks states, accessibility and performance; approves or files issues | 1 per 2–3 builders |
| **Integrator** | Merges verified branches into `main`, keeps the app building, merges `upstream/master` weekly | 1 |
| **Researcher** | Resolves open items (D014, PiP, HDR, waveform, OpenSubtitles) and writes `NOTES.md` | as needed |

Order of attack inside P1, for maximum parallelism once P0 is done:
1. Wave 1: tokens/icons, `SeekBar`, `VolumeCone`, `PlayButton` + `IconButton`, `TimeLabel`, menus.
2. Wave 2: `ControlBar` and `TopBar` composition, hover reveal, window chrome.
3. Wave 3: menus wired to actions, OSD, continue watching, PiP, media keys.

## Community

The project's message: *the VLC people asked for, on the Mac, built in the open,
with credit to Juxtopposed and VideoLAN*. After the P1 milestone, and **only with
the owner's go-ahead**:
- publish the GitHub repo;
- post a short demo video;
- open Discussions;
- share where VLC and Mac users gather (r/VLC, r/macapps, VideoLAN forum);
- notify Juxtopposed.

Upstream VLC takes contributions through GitLab (code.videolan.org), not GitHub PRs.
Engine fixes we find go there as separate merge requests.
