# VLC Redesign for macOS

**Juxtopposed's VLC redesign, built as a native Mac app in Swift, on top of VLC 4's unmodified engine.**

![VLC Redesign for macOS in dark mode: the library panel, the player and the queue in one window.](media/hero-player-library-queue-dark.jpg)

macOS 14+ · Apple Silicon · Swift 6 · SwiftUI + AppKit · VLC 4 engine untouched · GPL-2.0-or-later · design CC BY 4.0

> Unofficial. Not affiliated with or endorsed by VideoLAN or Juxtopposed.

## What this is

On 12 October 2026 Juxtopposed published [“I Redesigned VLC After 25 Years”](https://www.youtube.com/watch?v=ERFeOgqk324) and an [open Figma file](https://www.figma.com/community/file/1691465999134370980). About 20 community implementations appeared within 48 hours. Most of them restyle VLC's Qt interface, which VideoLAN does not ship on macOS. The rest are standalone players or skins for Windows and Linux. None of them runs as a Mac app.

This fork does. It is a new VLC interface module, `modules/gui/macosx_redesign`, written in Swift with SwiftUI and AppKit. The Figma file is the reference for every colour, size and icon. The video is the reference for behaviour. Upstream VLC decides what each setting means.

VLC itself is unchanged. Playback, codecs, network streams, conversion, the media library and settings all come from upstream VLC 4. Against the upstream base (`4ca4eb0c3e`), `git diff` over `src/`, `lib/`, `include/` and `modules/gui/macosx` is empty.

## Gallery

<table>
<tr>
<td width="50%"><img src="media/player-light-library-panel.jpg" alt="Light theme player with the folder panel"><br><sub>Light theme: the player with the folder panel open on the left.</sub></td>
<td width="50%"><img src="media/library-home-dark.jpg" alt="Library home"><br><sub>Library home with Continue Watching, Listen Again and Frequently Visited Folders.</sub></td>
</tr>
<tr>
<td><img src="media/library-grid-light.jpg" alt="Library grid, light"><br><sub>A show's folder in the grid view, light theme, with watched-progress bars.</sub></td>
<td><img src="media/music-now-playing.jpg" alt="Music now playing"><br><sub>Music playback with the album art and a blurred backdrop.</sub></td>
</tr>
<tr>
<td><img src="media/playback-panel-subtitle-timeline.jpg" alt="Playback panel and subtitle timeline"><br><sub>Playback side panel, the subtitle timeline on the seek bar and the metadata overlay.</sub></td>
<td><img src="media/side-panels-and-filters.jpg" alt="Side panels and filter cards"><br><sub>Playback and Audio panels, plus the Equalizer and Video Colors filter cards.</sub></td>
</tr>
<tr>
<td><img src="media/subtitle-settings-panel.jpg" alt="Subtitle side panel"><br><sub>Subtitle panel: defaults, synchronization, appearance and presets.</sub></td>
<td><img src="media/queue-and-osd.jpg" alt="Queue and OSD"><br><sub>Queue panel with an on-screen display after a keyboard shortcut.</sub></td>
</tr>
<tr>
<td><img src="media/settings-general-dark.jpg" alt="Global Settings, dark"><br><sub>Global Settings, dark: theme, accent colour, startup and diagnostics.</sub></td>
<td><img src="media/settings-audio-light.jpg" alt="Audio settings, light"><br><sub>Audio Defaults settings page in the light theme.</sub></td>
</tr>
<tr>
<td><img src="media/customize-player.jpg" alt="Customize Player"><br><sub>Customize Player: drag controls in and out of the control bar.</sub></td>
<td><img src="media/onboarding.jpg" alt="Onboarding"><br><sub>First-run onboarding: welcome, then theme and accent colour.</sub></td>
</tr>
<tr>
<td><img src="media/dialog-open-network-stream.jpg" alt="Open Network Stream"><br><sub>Open Network Stream dialog.</sub></td>
<td><img src="media/menus-more-and-context.jpg" alt="Menus"><br><sub>The ⋯ menu, and the right-click menu with its Video submenu open.</sub></td>
</tr>
<tr>
<td colspan="2"><img src="media/mini-player.jpg" alt="Mini player"><br><sub>Mini player on hover, and expanded with the queue.</sub></td>
</tr>
</table>

The video area in these renders shows the still from the Figma design (the pixel cat). The screenshots were rendered offscreen by the project's `mxr-snapshot` tool at 2x, using the same SwiftUI views the app runs.

## Figma vs. this app

Figma on the left, the app on the right, same size, same Figma node.

![Player, dark: Figma (left) and the app (right).](media/compare-player-dark.jpg)
<sub>Player, dark.</sub>

![Player with the library panel, light: Figma (left) and the app (right).](media/compare-player-light.jpg)
<sub>Player with the library panel, light.</sub>

![Library grid view: Figma (left) and the app (right).](media/compare-library-grid.jpg)
<sub>Library grid view.</sub>

![Global Settings: Figma (left) and the app (right).](media/compare-settings.jpg)
<sub>Global Settings. The app leaves out the interface-language and auto-update rows on purpose; the reasons are in the [decisions log](../redesign/docs/DECISIONS.md).</sub>

## Highlights

**Player**
- 40 pt top bar with native traffic lights, title, and library and queue toggles; framed video; Hide UI (⌘\\) and a fullscreen reveal.
- Control bar: seek bar with preview thumbnails, a volume cone from 0 to 200 %, and one track popover for subtitles, audio and video.
- Continue-watching toast with a resume marker on the seek bar; an on-screen display of the key you pressed.
- Subtitle timeline as a seek-bar mode, with cue blocks and nudges (SRT, WebVTT, ASS/SSA).

**Side panels** (they overlay the video and do not shrink it)
- Playback, Video (Essential, Crop and Colors filter cards; HDR), Audio (equalizer, compressor, spatializer, stereo widener, presets) and Subtitles.
- Queue with sort, repeat, shuffle and drag from the library; bookmarks; chapters.

**Library**
- A compact library beside the video: Home, Recent, Videos, Music, network streams and playlists, plus an icon rail with pins.
- A full-window library with Home, a grid with watched states, a list view, a mini player and search (⌥⌘F).

**Settings and dialogs**
- 13 settings pages in Dark and Light, from General and Privacy to Network, Performance, Recording/Casting/Streaming and local Lua extensions; a keyboard-shortcut editor.
- Open Network Stream, Open Disc, Capture Device, Convert, Stream, Open from Clipboard, New Playlist.

**Customization**
- Customize Player with drag and drop, a two-row bottom bar, and profiles.
- Onboarding with a media folder, the theme, nine accent colours and the basic shortcuts.

**A real Mac app**
- Menu bar mirroring the app menu, native fullscreen and Spaces, Picture in Picture, media keys and Now Playing.
- Accessibility labels and actions, and reduce-motion support.
- The colour, type and size tokens and the icons are generated from the Figma file (`tools/gen-tokens.py`, `tools/gen-icons.py`).

Some limits come from the engine: no reverse playback, HDR offers Auto only, and OpenSubtitles needs your own API key.

## Try it

It installs as a **separate app, `/Applications/VLC Redesign.app`**, next to the official VLC. The installer never touches `/Applications/VLC.app`.

**You need:** an Apple Silicon Mac, Xcode 27 with the command-line tools (run `sudo xcodebuild -license accept` and `xcodebuild -runFirstLaunch` once), git, curl and python3. The build needs network access to artifacts.videolan.org, downloads.videolan.org, www.lua.org and github.com, and at least 6 GB of free disk space. The stock baseline alone takes about 30 minutes the first time; the redesign build comes after it. Do not point `VLC_PATH` at a Homebrew folder.

```sh
# 1. Clone, and add upstream VLC as "upstream"
git clone https://github.com/Lemelson/vlc-redesign-macos.git && cd vlc-redesign-macos
git remote add upstream https://code.videolan.org/videolan/vlc.git && git fetch upstream
SRC=$PWD

# 2-3. Point the build at VideoLAN's prebuilt contribs for this base
export VLC_FORCE_KERNELVERSION=19
BASE=$(git merge-base HEAD upstream/master)
CONTRIB_SHA=$(git rev-list -1 $BASE -- extras/tools contrib extras/ci extras/package/macosx)
export VLC_PREBUILT_CONTRIBS_URL=https://artifacts.videolan.org/vlc/macos-arm64/vlc-contrib-aarch64-apple-darwin19-$CONTRIB_SHA.tar.zst

# 4. Stock baseline: contribs and native tools
mkdir -p ../stock && cd ../stock && STOCK=$PWD
VLC_CONFIGURE_ARGS='--disable-macosx-ui-shaders --disable-ncurses' \
  "$SRC/extras/package/macosx/build.sh" -a aarch64 -j 10
rm -rf VLC.app   # the stock build also makes a VLC.app; you don't need it

# 5. Configure and build the redesign (build dir, stock build dir, stock source dir)
"$SRC/modules/gui/macosx_redesign/tools/build-native.sh" ../redesign-build "$STOCK" "$SRC"

# 6. Install, with the app closed
"$SRC/modules/gui/macosx_redesign/tools/install-app.sh" ../redesign-build
```

`install-app.sh` builds the bundle and checks a staged copy: its identity, that the stock interface is absent, a fresh `plugins.dat`, and `codesign --verify --deep --strict`. Then it swaps the copy into place, with rollback if anything fails. The app is ad-hoc signed and not notarized yet, so Gatekeeper may ask you to confirm the first launch.

**Tests** (from the same folder as the steps above): `make -C ../redesign-build/modules check-macosx-redesign`. After installing, `make -C ../redesign-build/modules check-macosx-redesign-app MXR_SMOKE_MEDIA=<a media file>` starts the installed app, plays the file and quits.

**Only want to see the UI?** You need nothing but Xcode. From the clone:

```sh
cd vlc-redesign-macos/modules/gui/macosx_redesign
swift run MXRGallery          # every screen, on a mock backend
swift run mxr-snapshot list   # offscreen renders and Figma comparison
```

The full guide, with sanity checks and troubleshooting, is in [`redesign/docs/BUILD.md`](../redesign/docs/BUILD.md). All of this was verified on one Mac; a run on a fresh machine has not been done yet. Reports are very welcome.

## Status

**Verified**
- 561 of 561 Swift tests pass, none skipped, in two consecutive runs.
- 10 of 10 native suites pass against the real engine: contracts, schema, fixtures, library, audio, media, extensions, subtitle runtime, build runtime and headless regressions.
- In the latest Figma-parity review, judges ran 167 checks: 115 match, 33 have minor differences, 1 has a major difference (the mini player in Light), and 18 were not checked.
- All 72 screens in the master list (S01–S72, from the video and the Figma file) are implemented. Of the 119 gallery entries, `mxr-snapshot check --all` passes 26, flags 70 for review and fails 23. Eleven of the failures are crop artefacts at the edges of the onboarding frames.
- Agents drove the installed app on a real Mac for live acceptance. Some groups of that run are still outstanding (see below).

**Known issues.** These were found in live acceptance; a fix wave for them is in progress:
- Two crashes: a fast Brightness drag in the Essential card, and playing an http:// item from its card.
- Repeat does not loop a single item. Arrow keys don't move the library selection.
- Convert's "Replace" does nothing. HTTP streams are not paced to real time.
- Side panels close without a fade. The 480×270 minimum window size is not enforced.
- Dragging a library row onto the queue may replace the queue (seen with synthetic input; not yet confirmed by hand).

**Also open**
- Bookmarks fail silently for media outside the library.
- The full-library mini player doesn't scale down, and its controls are hard to see in the Light theme.
- Convert and Stream jobs mark the source as played.
- Live acceptance is partial: three test groups never ran. Hardware checks (camera, audio CD, Chromecast, SMB) and VoiceOver and Full Keyboard Access need a person.
- Seeking while paused hits an upstream engine bug. The app works around it; the full fix is an optional patch series (see below).
- Picture in Picture uses a private system route that a future macOS may break.
- There is no signed, notarized binary yet. The name and bundle ID are provisional.

The full record is in [`redesign/design/SCREENS.md`](../redesign/design/SCREENS.md), [`redesign/docs/DECISIONS.md`](../redesign/docs/DECISIONS.md) (57 decisions) and [`redesign/research/final-polish/results/`](../redesign/research/final-polish/results/).

## How it was made

One person, Lemelson, built it in about two days, working with many AI agents in parallel: **Claude Opus 5.5** (Anthropic, in Claude Code) and **GPT-6.1 Sol** (OpenAI, in Codex).

- **Sources.** Behaviour comes from the video, broken down frame by frame in [`VIDEO_BREAKDOWN.md`](../redesign/docs/design/VIDEO_BREAKDOWN.md) and the screen specs. Appearance comes from the Figma file: tokens, icons and 105 node renders in [`redesign/design`](../redesign/design). Semantics come from upstream VLC.
- **Research.** 16 community forks were reviewed first ([`FORKS.md`](../redesign/research/FORKS.md)).
- **Decisions.** Every deviation from the design is logged in [`DECISIONS.md`](../redesign/docs/DECISIONS.md).
- **Fixer and verifier waves.** Each area (window, controls, bridge, menus, library, settings, panels, design, media I/O) had a fixer agent. A separate verifier agent checked each fixer's work.
- **Figma-parity judges.** Each screen is rendered offscreen and compared with its Figma node, pixel by pixel, by `mxr-snapshot`.
- **Engine tests and live acceptance.** Native test suites run against the real VLC engine. Acceptance agents drove the installed app on a real Mac.

About 41k lines of Swift sources, 12k lines of Swift tests, and 9k lines of Objective-C bridge.

## For VLC developers

The redesign is designed to be easy to review, and easy to drop.

- **Module.** `modules/gui/macosx_redesign/` builds `libmacosx_redesign_plugin.dylib` (`--intf macosx_redesign`, shortcut `mxr`). `--enable-macosx-redesign` selects it, and the build disables the stock macOS interface.
- **Layers.** `module/` is about 9.2k lines of Objective-C that call VLC's C APIs and own the callbacks and locks, behind Foundation-only headers. `MXRVLCBackend` turns snapshots and commands into `@MainActor @Observable` models. `MXRDesign` and `MXRUI` depend only on protocols, so the same UI also runs on a mock backend. The video is VLC's own vout in a layer-backed `NSView`.
- **Upstream touch points.** Outside the redesign folders, three build files change: `configure.ac` (+1 line), `modules/gui/Makefile.am` (+1) and `extras/package/macosx/package.mak` (+5). Three files are new: `AGENTS.md`, `CLAUDE.md` and this `.github/README.md`.
- **Engine patches.** The paused-seek fix is a five-patch series in [`redesign/patches/engine`](../redesign/patches/engine/README.md). It is never applied to the tree. Setting `MXR_ENGINE_PATCHES=1` applies it to a separate copy only.
- **How to review.** Start with [`ARCHITECTURE.md`](../redesign/docs/ARCHITECTURE.md), then `git diff 4ca4eb0c3e -- configure.ac modules/gui/Makefile.am extras/package/macosx`.

The author would love to see this upstreamed, in whatever shape VideoLAN prefers, or to hand it over entirely.

## Other community implementations

Many people built this design within days, and several did careful work: Figma data and renders, a settings mapping, specs and coverage matrices. This project reuses some of that material, with attribution in [`from-forks/README.md`](../redesign/research/from-forks/README.md). [`FORKS.md`](../redesign/research/FORKS.md) lists every implementation we know of and what each one does well.

## Contributing

Issues and pull requests are welcome on this repository. Good first areas:
- the open items under [Status](#status);
- the gallery entries flagged REVIEW (`swift run mxr-snapshot check --all`);
- testing on hardware: camera, audio CD, Chromecast, SMB, VoiceOver;
- building on a fresh Mac and reporting what broke.

Start with [`AGENTS.md`](../AGENTS.md), a map of the repo for people and AI agents, then [`PHILOSOPHY.md`](../redesign/docs/PHILOSOPHY.md) and [`WORKFLOW.md`](../redesign/docs/WORKFLOW.md). Engine changes need a documented, narrow exception; fixes that belong in VLC itself go to VideoLAN.

## Credits and license

- **VLC:** [VideoLAN](https://www.videolan.org) and the VLC contributors. GPL-2.0-or-later ([`COPYING`](../COPYING)); libVLC is LGPL-2.1-or-later ([`COPYING.LIB`](../COPYING.LIB)).
- **Design and mock artwork:** [Juxtopposed](https://www.youtube.com/@juxtopposed) ([video](https://www.youtube.com/watch?v=ERFeOgqk324)), from the [VLC redesign Figma file](https://www.figma.com/community/file/1691465999134370980), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The video itself is not part of this repository.
- **Font:** [Inter](https://github.com/rsms/inter) by The Inter Project Authors, SIL Open Font License 1.1 (bundled with its license).
- **This fork:** GPL-2.0-or-later.

"VLC" and the cone logo are trademarks of VideoLAN. If you like VLC, consider [donating to VideoLAN](https://www.videolan.org/contribute.html). Upstream VLC's own README is [`README.md`](../README.md).

---

**If you want this design in VLC on the Mac, star the repo and share it.**
