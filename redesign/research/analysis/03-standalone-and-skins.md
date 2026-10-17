# 03 — Standalone players and Skins2 skins

Scope: five shallow-cloned repos that implement Juxtopposed's "VLC Redesign" (video 2026-10-12, Figma community file `1691465999134370980`), evaluated for a **macOS** implementation on top of VLC's engine.
Method: read-only inspection of code, git history, screenshots, cross-checked against the video transcript and frames in `research/video/`, and against the Figma REST dump already in `research/figma/figma_file.json`.

Repos live in `../reference/standalone/`.

---

## 0. TL;DR

| Need for macOS build | Best source | What to take |
|---|---|---|
| Icons as SVG (from the Figma file) | **nagasab221** `vlcr/assets/icons.json` (now) / **Green-Skeleton** `render.js` (full file) | 96 icon names, 206 variant SVGs, 24×24, exported from the Figma "Icon" component set |
| Color tokens | Figma styles (table in §6), cross-checked against **Green-Skeleton** `build-skin.js` and **nagasab221** `theme.py` | Dark + Light palettes, 9 accent swatches |
| Full design extraction (all frames, vectors, text) | **Green-Skeleton** `tools/figma/decode.js` + `render.js` | A working `.fig` → JSON → SVG/PNG pipeline. Needs a `.fig` that **is not in the repo**. |
| Feature logic and behavior | **nagasab221** (most complete), **pylon** (subtitle timeline, bulk sub matching), **Sayandeep** (effects catalogue, seek thumbnails, waveform) | Algorithms and data models, not code |
| Settings information architecture | **nagasab221** `vlcr/prefs.py` | 13 categories, 215 rows, each tagged with how it's applied in libVLC |

- **Skins2 (.vlt) is a dead end for this goal.** Released VLC for macOS (3.0.x) has no Skins2. VLC 4.0-dev master gained a macOS Skins2 backend in March 2026 (see §1). Even so, Skins2 is bitmap-only and can't express most of the redesign.
- **All five repos are heavily AI-assisted.** They were built between 12 and 13 Oct 2026, the day of or the day after the video. Most commits carry `Co-Authored-By: Claude …` trailers.

---

## 1. What VLC "Skins2" is, and does it work on macOS?

- **Skins2** is VLC's second skinnable interface module (`modules/gui/skins2`). It's an alternative to the Qt interface. A skin is a `.vlt` file: a tar or tar.gz holding `theme.xml` plus PNG bitmaps and fonts. `theme.xml` follows a DTD ("VLC Skins V2.0") and declares:
  - `Window`s and `Layout`s
  - `Image`, `Button`, `Checkbox`, `Slider`, `Text`, `Playtree` and `Video` controls
  - Actions bound to VLC commands, e.g. `vlc.play()`, `dialogs.popup()`, `main.setLayout(mini)`
- **What it can do:** absolute or anchored placement of bitmaps, 3-state buttons, sliders backed by sprite strips, a native video sub-window, a playlist tree, and switching between layouts.
- **What it can't do:**
  - Hover-reveal or animation
  - Custom dialogs: every dialog falls back to VLC's Qt dialogs
  - Rounded clipping of the video
  - HiDPI scaling
  - Translucency on Windows: semi-transparent pixels are darkened
- **Platforms in VLC 3.0.x:** `win32/`, `x11/` and `os2/` only. I verified this with `git ls-tree origin/3.0.x modules/gui/skins2/`: there's no `macosx/` dir. **VLC 3 for macOS has no Skins2. Your belief is correct for every released VLC.**
- **Nuance, VLC 4.0-dev:** master in `repos/vlc` now has `modules/gui/skins2/macosx/*.mm`.
  - It started as a 2005 skeleton. About 12 commits by Felix Paul Kühne on 27–28 Mar 2026 (window dragging, fullscreen, AppKit dialogs, popup menus) brought it back.
  - `configure.ac` has `-DMACOSX_SKINS`, and `NEWS` under "3.0.x → 4.0.0-dev" says *"Skins2: add macOS backend support"*.
  - `extras/package/macosx/package.mak` copies skins2 data into the app bundle.
  - So VLC 4 nightlies for macOS *may* load `.vlt` files. I didn't test whether these specific VLC-3-targeted skins render there, and it's dev-only. Either way, Skins2 can't deliver the redesign's library, settings, sidebar panels, onboarding or hover bars, so it's irrelevant to a real macOS redesign.

---

## 2. Sayandeep1013 / vlc-skins (3★)

### What the "skins" part is

**Mostly unrelated third-party material.** The repo is a grab-bag called "VLC Skins" that existed before the video:

| Folder | What | Origin | Size | Related to redesign? |
|---|---|---|---|---|
| `VeLoCity-Skin-for-VLC/` | 5 zipped `.vlt` skins (Dark, Dark Mist, Deep-Blue, light, light Mist) + 1 extracted | Copied from github.com/dmtiir/VeLoCity-Skin-for-VLC (MIT, 2022) | 16 MB | **No** |
| `materia-vlc/` | Materia `.vlt` + 63 source PNGs | Copied from PapirusDevelopmentTeam/materia-vlc (GPL-3) | 1.8 MB | **No** |
| `vlc-redesign/dist/VLC-Redesign.vlt` + `src/build.mjs` + `helper/AutoHide.cs` | The author's own **earlier Skins2 attempt** at the redesign, using Lucide icons. AutoHide is a Windows helper that posts double-clicks into VLC's window to fake hover-hide. | Own | ~0.7 MB | Yes, superseded by the player |
| `vlc-redesign/player/` | **The actual "VLC Redesign" player** | Own | — | **Yes** |

- **History:**
  - `c49ec56` (2026-05-25) "Add tested VLC skin projects"
  - `8328042` (2026-08-18) swapped in preview images
  - The redesign player arrived on **2026-10-13**, in 6 commits
  - The README even lists install paths like `D:\vlc\skins\…`
- **Share of the repo:** the third-party skins are about 18 MB of 38 MB on disk. The player is about 5.6 kLOC of code.

### The player (`vlc-redesign/player/`)

- **Language and stack:** C# .NET 8 **WPF** (`net8.0-windows`, `UseWPF`), LibVLCSharp 3.9.1 + LibVLCSharp.WPF, against the user's installed VLC 3 (64-bit).
- **LOC:** C# 4,516 + XAML 1,113 + Node generators 135 ≈ **5.8 k**. Biggest files: `MainWindow.xaml.cs` (1,590), `MainWindow.Effects.cs` (726), `Theme.xaml` (630).
- **Platform:** **Windows-only**, in several ways:
  - WPF
  - P/Invoke into `libvlccore.dll` (`Core/VlcVars.cs`)
  - HKCU "Open with" registration
  - MSIX/Store packaging
  - Lots of release plumbing: GitHub Actions, SignPath docs, about 60 MSIX logo PNGs
- **Implemented from the video:**
  - Auto-hiding top and bottom bars; a fullscreen floating controller
  - Thick seek bar with **YouTube-style thumbnail preview**. A hidden, silent second `MediaPlayer` builds a coarse-to-fine storyboard, then decodes exact frames on hover (`Core/Thumbnails.cs`).
  - **Waveform seek bar** for music (`Core/Waveform.cs` decodes peaks with libVLC)
  - Green→orange **cone volume**
  - Audio and subtitle pickers on the bar, including the audio output device
  - Player-settings sidebar with Playback, Subtitles, Audio and Video tabs (speed, chapters, delays, tracks, aspect, snapshot)
  - Queue; music view with big cover art
  - OSD that shows the key pressed
  - Dark right-click menu and a single `⋯` menu
  - **Not part of the video:** a full re-implementation of VLC's "Effects and Filters", Media/Codec info, Statistics and Messages. This uses `libvlccore` `var_Set*` on the live aout/vout objects, the way VLC's own Qt dialog does.
- **Not built** (per its README): library/home, **subtitle timeline**, the settings redesign, onboarding, presets, bulk subtitle import, bookmarks sidebar.
- **Fidelity: medium.** The control-bar layout and proportions match: pill play button, prev/next around it, thick dark seek bar with a brown fill and orange handle, the wedge, icons on the right.
  - Icons are **Lucide**, not the Figma set (`player/tools/gen-icons.mjs`).
  - Colors are eyeballed: accent `#E8710A` vs Figma `#D37918`, bar `#181818` vs `#1B1B1B`/`#191919`.
  - The cone is a green→orange gradient; the design uses a dark wedge with an olive/orange fill.
  - The top bar has no sidebar or folder chip. Fonts are Inter.
- **Red flags:**
  - 7 of 8 commits are Claude co-authored (6× Opus 5.5, 1× Sonnet 5).
  - The repo mixes unrelated GPL-3 and MIT third-party skins.
  - A committed binary `dist/VLC-Redesign-AutoHide.exe`.
  - Unsupported pointer arithmetic into libvlccore struct layouts (`VlcVars.cs` assumes VLC 3.0 object layout) breaks across VLC versions.
- **macOS:** not runnable. Porting means rewriting the UI. LibVLCSharp does support macOS, but WPF doesn't.
- **Reusable ideas:**
  - The effects catalogue in `Core/Effects.cs`: VLC module and variable names, ranges and defaults for EQ, compressor, spatializer, stereo widener, image adjust, etc. It's good reference data for our Audio/Video filter panels.
  - The two-player thumbnail strategy
  - Waveform peak extraction
  - Reading the user's `vlcrc` hotkeys

---

## 3. nirmaljosephukken / pylon-player ("Pylon")

- **Language and stack:** Python 3.10+, **PySide6** + **python-vlc**, using the installed VLC 3. There's also a tiny C launcher, `Pylon.exe` (committed binary, unsigned), plus `.bat` setup and registration scripts.
- **LOC:** `app/*.py` + `main.py` = **5,631**. Largest: `window.py` 1,304, `sidebar.py` 804, `library.py` 739, `engine.py` 563, `dialogs.py` 549.
- **Platform:** marketed as Windows 10/11.
  - The code is mostly cross-platform Qt. `engine.py` already branches `set_hwnd` / **`set_nsobject` (darwin)** / `set_xwindow`, and `library.py` has a darwin branch for "reveal in Finder".
  - Windows-only parts are guarded: winreg VLC lookup, DWM dark title bar, `SetWindowPos` topmost, AppUserModelID.
  - **It would probably start on macOS with `PYTHON_VLC_LIB_PATH` pointed at VLC.app's libvlc.** The bars are `Qt.Tool` frameless translucent top-level windows (`widgets.OverlayWindow`) floating over the video, which is the right approach on macOS, where a native video NSView covers sibling widgets. Untested.
- **Implemented from the video:** the widest feature coverage relative to its size.
  - Hover bars (also in fullscreen), `H` to hide the UI, thick seek bar with bookmark and chapter ticks, cone volume
  - Subtitle and audio buttons (audio includes output devices)
  - Queue with drag-reorder; playing a file queues the rest of its folder
  - Settings sidebar: Subtitles, Audio, Video, Playback, Bookmarks
  - **Subtitle timeline**: `widgets.SubtitleTimeline`, a 10 s window of cue blocks around the playhead. Drag to shift the delay in 50 ms steps. Cues are parsed from SRT/VTT/ASS in `util.parse_subtitles`.
  - Relative or exact subtitle size, font, colour, outline, background box, position
  - **Per-show presets** (per folder); default subtitle and audio language
  - **Bulk subtitle import** to a file, folder or queue, auto-matching `S01E02` / `1x02` / `E02`. Manual fixes are remembered.
  - Picture presets (Vivid, Cinema…); EQ presets as chips; rotate, flip, crop, zoom; sleep timer
  - Library with back/forward/up/address bar/search/sort (unwatched first), pins, recents, playlists, streams (`.m3u`)
  - Home page with **Continue watching** and a "Continue from 12:34" chip near the controls
  - `Ctrl+B` bookmarks; OSD with the key name; rebindable shortcuts
  - Plain-language prefs with info icons; accent colour
  - **Not built:** seek thumbnails, waveform, reverse playback, music by artist/album, casting, layout editor, the full settings rework.
- **Fidelity: low.**
  - Icons are its own hand-drawn line icons (`app/icons.py`), not Figma.
  - Accent `#FF8800`; font Segoe UI first; generic Qt stylesheet look.
  - The seek bar spans the very bottom under the controls instead of sitting inline. The play button isn't the orange pill. Settings are a docked right panel rather than the floating rounded card.
  - It's an "inspired by" app ("adapted implementation of many of its ideas"). The README says no Figma files or artwork are included.
- **Red flags:**
  - No co-author trailers: 4 commits, all "Add files via upload" through the web UI.
  - But `docs/home.png` shows a library folder path **`/tmp/claude-0/-home-claud…`**, so the screenshots were produced inside a Claude Code sandbox on Linux. That's strong evidence the whole app was agent-generated.
  - Committed unsigned `Pylon.exe`.
- **Reusable for macOS:**
  - `SubtitleTimeline.paintEvent` / drag math: a compact reference for the timeline UX
  - `util.auto_match_folder` and the episode regexes
  - The preset data model in `sidebar.current_settings` (which fields a show preset stores)
  - The `store.py` JSON schema for history, resume, bookmarks and pairings

---

## 4. nagasab221 / vlc-redesign

- **Language and stack:** Python 3 + **PyQt5** + vendored **python-vlc** (`vendor/vlc.py`, 8.7 k lines, excluded below), using the system libVLC 3.
  - Optional dependencies: python-xlib, ffmpeg/ffprobe, pactl, wmctrl.
  - Installer `install.sh` supports apt, pacman and dnf.
- **LOC:** `vlcr/*.py` + `main.py` = **15,925**, the largest real codebase of the five. Biggest: `widgets.py` 2,096, `engine.py` 2,008, `library.py` 1,887, `window.py` 1,872, `dialogs.py` 1,350, `panels.py` 1,251.
- **Platform:** **Linux/X11 only** as written.
  - `set_xwindow` with no darwin or win32 branch
  - `wm.py` sends `_NET_WM_MOVERESIZE` via Xlib
  - Uses `pactl` for audio sink handling, `wmctrl` for always-on-top, and `libc.so.6` (guarded)
  - Expects VDPAU hardware decoding options
  - **macOS port effort:** moderate. Add `set_nsobject`; replace pactl with `audio_output_device_enum`; drop or replace `wm.py` with Qt's `startSystemMove`; deal with native-NSView-over-widgets z-order for the overlay bars and side panels. It would still be a Python/Qt app, not a native mac app.
- **Implemented from the video:** essentially **every section**.
  - Title bar: cone → Home, `⋯`, sidebar toggle, folder chip, title, PiP / min / max / fullscreen / close
  - Control bar: pill play, thick seek with hover preview frame (ffmpeg), click time to jump or show remaining, cone volume to 200%, audio, subtitles, playback settings, queue buttons
  - Fullscreen edge-reveal
  - Tracks panel with output devices
  - Settings panels: Playback, Video, Audio, Subtitles, all with presets per show
  - **Subtitle timeline drawn on the seek bar** (`SeekBar` "subtitle timeline" mode) with ‹ − / + › nudge buttons
  - Queue, bookmarks and chapters panel
  - Library as a compact sidebar or full window with a mini player: videos, music (songs/albums/artists/genres), streams, m3u, podcasts, radio, playlists, favourites, recents, watched dimming, **Continue Watching**, Customize Home
  - Add Subtitles dialog with season matching
  - Network, Disc, Capture, Convert and Stream dialogs
  - Keyboard Shortcuts dialog, including global hotkeys
  - **Settings dialog with all 13 categories** from the video
  - **Onboarding** with theme, accent and keys
  - **Customize Player** drag-and-drop layout editor; profiles; light/dark themes with 9 accents; PiP, snapshots, recording
  - **Disabled with reasons:** reverse playback, HDR tone-mapping, casting (libVLC 3 limits)
- **Fidelity: high, the closest of the standalone apps.**
  - Icons are **the Figma icons**, exported as SVG (below). Theme tokens are taken from the Figma styles (`theme.py`), with Inter Regular/Medium/SemiBold bundled.
  - The screenshot `screenshots/player.jpg` lines up almost 1:1 with the design frame "Player + sidebar" (compare `Green-Skeleton…/docs/design/player-sidebar.png`): same rail icons, breadcrumb row, item rows, control bar.
- **Red flags:**
  - All 17 commits on 2026-10-13 carry `Co-Authored-By: Claude Opus 5.5`.
  - The `curl | bash` installer runs `sudo` package installs.
  - The code is large and fast-written. Expect rough edges, e.g. filter changes "blink" because the engine restarts libVLC.
- **Reusable for macOS (high value):**
  1. **`vlcr/assets/icons.json`:** 96 icon names → 206 variant SVGs (24×24, stroke `#8F8F8F`, accent `#D37918`/`#AB6314`). It's a direct export of the Figma "Icon" component set, keyed by variant string, e.g. `direction=left`. 2 variants are export errors (`"0"`). The icon names exactly match the 96 `name=` values in the Figma set. You can drop these straight into an asset catalog as SVG/PDF symbols. They're CC BY 4.0, so credit Juxtopposed. `icons.py` `ALIASES` documents the Figma naming quirks, e.g. speaker-level icons are filed under "close".
  2. **`vlcr/theme.py`:** DARK and LIGHT palettes with semantic names (bar, rail, base, panel_head, field, hover, line, text…), plus `ACCENTS = [#d37918, #e15032, #c49e23, #19a234, #18aad3, #185dd3, #8e42ff, #f052b3, #afafaf]` from the onboarding and General settings screens.
  3. **`vlcr/prefs.py`:** the complete Settings IA. 13 categories (General, Interface, Privacy, Controls, Playback, Video, Audio, Subtitles, Library, Network, Performance, Recording, Extensions), 215 rows. Each row has a kind (toggle/dropdown/segmented/slider…), default, info text, and how it's applied (`ui` / `runtime` / `instance` = requires libVLC restart). It's a ready-made spec for a SwiftUI `Form`.
  4. Behaviour references: seek-bar modes (plain / waveform / subtitle cues), `customize.py` drag-layout model, `miniplayer.py`, `onboarding.py`.

---

## 5. Green-Skeleton / vlc-redesign-skin: the .fig decoder (most important)

### 5.1 The repo

- **Purpose:** a Skins2 `.vlt` for VLC 3 (Windows/Linux). **It is generated programmatically from the Figma `.fig` file.** The repo also links a separate VLC 4 Qt fork, `Green-Skeleton/vlc-redesign`, which is a remote in `repos/vlc` and covered elsewhere.
- **Code (JS, Node):** `tools/` **1,077 LOC** + `install.ps1` 65.

  | File | LOC | Purpose |
  |---|---|---|
  | `tools/figma/decode.js` | 40 | `.fig` → `build/figma/doc.json` + images |
  | `tools/figma/render.js` | 368 | Node → SVG/PNG |
  | `tools/figma/tree.js` | 22 | Prints the node tree |
  | `tools/build-skin.js` | 552 | Builds the skin |
  | `tools/vlc4-icons.js` | 74 | VLC 4 icon-font replacement |
  | `tools/package.js` | 21 | Packs the `.vlt` |

  Dependencies: `kiwi-schema`, `pako`, `fzstd`, `fflate`, `@resvg/resvg-js`, `potrace`, `@expo-google-fonts/inter`.
- **Assets:** `skin/images/` holds 209 rasterized 1× PNGs (all button states and sprite strips), `skin/theme.xml` (451 lines), Inter fonts, `dist/VLC-Redesign.vlt`. `docs/design/` has 4 reference renders of Figma frames made by their renderer: `player.png` (frame `187:328`), `player-sidebar.png`, `mini-player.png`, `equalizer.png`.
- **Skin features:** windows `main` / `plwin` / `eqwin` / `fullscreenController`; layouts normal / sidebar / mini.
  - Top bar
  - Rounded 10 px video stage
  - Seek bar: black track, brown fill as a 101-frame sprite, orange handle
  - **Volume wedge rendered from the Figma "volume" component** at 51 fill levels
  - Sidebar rail
  - Queue popup
  - 10-band EQ with toggle
  - Mini player; fullscreen controller
  - **Not possible in Skins2:** library grid, settings, onboarding, open dialogs, rounded video corners, light theme, HiDPI
- **Fidelity: highest of all five for what it covers**, because every icon and component is rendered from the actual Figma geometry. Compare `docs/screenshots/player.png` with `docs/design/player.png`. Coverage, though, is limited to the player chrome.
- **Red flags:** 5 of 6 commits Claude co-authored (Opus 5.5). Author "Sharan Senthil" (student address). Made 12–13 Oct.

### 5.2 Is the `.fig` or decoded data in the repo?

**No.**
- `.gitignore` excludes `*.fig` and `build/`, so neither the `.fig` nor the decoded `doc.json` or images are committed.
- The repo contains only:
  - the tooling;
  - hard-coded **Figma node IDs** and **color tokens** at the top of `build-skin.js`;
  - an icon-ID map in `vlc4-icons.js`;
  - the rasterized outputs (PNGs at 1×, recoloured and flattened onto opaque backgrounds). These are not useful as macOS assets.
- I searched the whole `..` tree: no `.fig` and no `doc.json` anywhere.

**What we do have locally:** `research/figma/figma_file.json` (26 MB). It's a **Figma REST API** `GET /v1/files/:key` dump of the same file ("VLC Redesign (Community)", lastModified 2026-10-12T17:33:47Z).
- All **78 node IDs** used by Green-Skeleton and BettererVLC resolve in it. IDs are stable between the `.fig` and the REST API.
- Contents: 1 page ("Page 1"), 105 top-level nodes = **68 frames + 35 component sets + 2 texts**.
- In total about 26.4 k nodes: 9,336 FRAME, 7,482 VECTOR, 5,241 INSTANCE, 3,182 TEXT, 2,031 RECTANGLE, 606 ELLIPSE, 322 COMPONENT, 71 BOOLEAN_OPERATION.
- 323 components, 36 component sets, 51 styles (49 FILL, 2 EFFECT).
- Fonts: Inter 300/400/500/600 (mostly 14/12/16 px), plus a little DM Mono.
- **It has no vector geometry:** it was fetched without `geometry=paths`, so there's no `fillGeometry`. It also lacks values for styles that aren't applied to any node.

Top-level frames (screens) in the file:

| Group | Frames |
|---|---|
| Player (1920×1080) | `Player` ×7 (187:328, 970:3308, 970:3792, 970:2703, 970:4028, 6261:15078, 247:445), `Player - Music` ×2, `Player - hide UI`, `Player - Light`, `Player - customize` ×9 |
| Settings (1048×865) | global ×2, interface ×2, privacy, playback ×2, video ×2, audio ×2, subtitles ×2, controls, library, network, performance, recording, extensions (19 total) |
| Dialogs | `Add Subtitles to Playlist/Folder` ×4 (1048×800), `Keyboard Shortcuts`, `Open network stream`, `new playlist` |
| Onboarding (1090×759) | ×11 |
| Menus | `Sorting Options`, `context menu`, `folder context menu`, `file context menu`, `playlist context menu`, `View Options`, `menu`, `right-click menu`, `Profiles`, `thumbnail`, `audio value` |

Component sets: `Icon` (208 variants, 96 icon names), `Icon Wrapper`, `volume`, `Controls` (1960×11139, the big control-bar variant sheet), `Button`, `Toggle`, `Audio - Compressor/Equalizer/Spatializer/Stereo Widener`, `Video - Essential/Crop/Colors`, `Values` ×2, `play`, `sidebar` (4492×1028), `Miniplayer`, `Current Time`, `Duration`, `subtitle multiple`, `subtitle one`, `target`, `origin`, `option`, `Dropdown`, `Setting Preset`, `EQ presets`, `Audio Visualizer`, `HDR Options`, `sub filename`, `media`, `playlist`, `setting category`, `EQ`.

### 5.3 How the `.fig` decoder works (`tools/figma/decode.js`, 40 lines)

1. **Unzip.** A modern `.fig` from "File → Save local copy" is a ZIP (`PK` magic) containing `canvas.fig`, `meta.json`, `thumbnail.png` and `images/<sha1-hex>`. The script extracts `images/*` to `build/figma/images/` and takes `canvas.fig`. A raw non-zipped `canvas.fig` is also accepted.
2. **Header.** `canvas.fig` begins with the 8-byte magic `fig-kiwi`, then a uint32 LE **version**, then a sequence of `[uint32 LE length][bytes]` chunks.
3. **Decompress each chunk.** If it starts with the zstd magic `28 B5 2F FD`, it uses `fzstd`; otherwise raw DEFLATE via `pako.inflateRaw`. Newer files use zstd, older ones deflate.
4. **Schema-driven decode.** Chunk 0 is a **binary Kiwi schema** (Evan Wallace's Kiwi format, which Figma uses for its wire and file format). `kiwi.decodeBinarySchema` → `compileSchema` gives a decoder. Chunk 1 is the **`Message`** encoded with that schema, decoded via `schema.decodeMessage`. The file carries its own schema, so the decoder is **version-tolerant**: no hard-coded Figma schema to go stale.
5. **Output.** `JSON.stringify` with `Uint8Array` → base64 gives `build/figma/doc.json`.
   - The message is `{ nodeChanges: [...], blobs: [...] , ...}`.
   - `nodeChanges` is a **flat list of every node in the document**: DOCUMENT, CANVAS, FRAME, SYMBOL (=component), INSTANCE, VECTOR, TEXT, style nodes, VARIABLE / VARIABLE_SET.
   - Each node has a `guid {sessionID, localID}` (→ `"187:328"`) and `parentIndex {guid, position}`. The tree is rebuilt by grouping on the parent guid and sorting by the fractional-index string `position`.
   - `blobs[]` holds binary geometry referenced by index.

### 5.4 How the renderer works (`tools/figma/render.js`, 368 lines)

- **Geometry:** `fillGeometry` / `strokeGeometry` reference `commandsBlob` indexes. A blob is a byte-coded path: `0`=close, `1`=M x y, `2`=L, `3`=Q, `4`=C, coordinates as float32 LE. `blobPath()` turns it into an SVG `d` string. **Strokes are already outlined by Figma** (stroke geometry is a filled shape), so no stroke math is needed. Rect-like nodes without geometry get a path built from per-corner radii.
- **Text:** uses `derivedTextData.glyphs[]`, i.e. Figma's **pre-computed glyph outlines** (blob + position + fontSize), so text renders exactly **without the fonts installed**. Decorations (underline) come from `derivedTextData.decorations`.
- **Paints:** SOLID; LINEAR and RADIAL gradients (Figma's paint transform is inverted into an SVG `gradientTransform`); IMAGE fills via `images/<hash-hex>` with FILL/FIT/STRETCH. Blend modes go to `mix-blend-mode`.
- **Effects:** DROP_SHADOW and LAYER_BLUR as SVG filters. **BACKGROUND_BLUR, INNER_SHADOW and angular/diamond gradients are not implemented.** The file's `bg blur` styles (BACKGROUND_BLUR r=50, plus a drop shadow 0/8/15 @46%) would render without the blur.
- **Structure:**
  - Transforms are `m00..m12` affine matrices. Because Figma stores *resolved* transforms, **auto-layout is already baked in**, so positions and sizes are exact layout measurements.
  - Frame clipping (`frameMaskDisabled`) and mask layers are supported.
  - **INSTANCE resolution** recurses into the referenced SYMBOL. It applies `symbolData.symbolOverrides` and `derivedSymbolData` keyed by guid paths, outer scope winning. It also applies **component properties** (`componentPropRefs` → VISIBLE, OVERRIDDEN_SYMBOL_ID for instance swap, TEXT_DATA).
- **Exports:**
  - `renderToSvg(id)` gives a standalone SVG of any node (CLI: `node render.js <id> out.png|out.svg [scale]`, PNG via resvg).
  - `collectOutlines(id)` gives flattened absolute paths (used for icon fonts).
  - `collectTexts(id)` gives all visible text with positions and sizes after overrides.
  - It also exports `nodes`, `kids` and `gid`.
- `tree.js` prints `TYPE [id] name WxH @x,y "text"` to a chosen depth.

**Quality:** it's compact and correct in its core: geometry, glyphs and instance overrides are the hard parts, and they're handled. `docs/design/player.png` shows a faithful render of frame `187:328`.

### 5.5 Can we reuse it to extract the full design for macOS? **Yes, with one manual step.**

1. **Get the `.fig`.** Someone with a Figma account opens the community file → "Open in Figma" (duplicates it to drafts) → File → **Save local copy**. Note the CC BY 4.0 attribution requirement. *This is the only manual step, and it requires the user's own Figma login, so it's not something an agent should do.*
2. Run it in an isolated working copy, not inside the read-only clone: `npm install`, then `node tools/figma/decode.js "<file>.fig"`, which writes `build/figma/doc.json` and `images/`.
3. Write a ~50-line exporter on top of `render.js`'s exports:
   - **Icons as SVG:** iterate the children of component set `42:356` ("Icon", 208 variants) and call `renderToSvg(id)` → `icons/<name>__<variant>.svg`. Optionally recolour to `currentColor` and convert to PDF/SF-Symbol templates for an Xcode asset catalog.
   - **All frames as reference SVG/PNG @2x:** the 68 top-level frames.
   - **Tokens:**
     - Style nodes in `nodeChanges` carry `styleType` + `name` (e.g. `Dark/Accent/Main`) + `fillPaints`. That gives **all 49 colour styles with values, including the ones the REST dump can't resolve** (e.g. `Dark/Accent/Bright` = `#FC9729` per Green-Skeleton; most Light/* values).
     - VARIABLE / VARIABLE_SET nodes, if present: the REST dump shows 44 nodes with `boundVariables`.
     - Effect styles map to `NSVisualEffectView` / shadow specs.
   - **Layout measurements:** walk any frame with absolute transforms, which gives exact x/y/w/h of the title bar, control bar, sidebar, panels and settings rows. `collectTexts` gives copy, font sizes and positions.
4. **Caveats:**
   - Background blur isn't rendered. Implement it natively; it's just a token.
   - The decoder relies on Figma's undocumented format. It's self-describing via the embedded schema, so it's robust, but not guaranteed.
   - Use the same Node environment; the code is plain CommonJS.

**Alternative without a `.fig`:** the REST API we already used can produce the same assets. Call `GET /v1/images/:key?ids=<ids>&format=svg` (nagasab221 evidently did exactly this; its `icons.json` contains the REST "Failed to export node" error string) and `GET /v1/files/:key?geometry=paths`. Both need a Figma personal access token. Either route works. The `.fig` route is offline and gives style and variable values directly.

**Directly reusable now (no `.fig` needed):**
- The **node-ID → semantic-name maps** in `build-skin.js` (`I = { play:'44:419', pause:'44:427', volume0:'244:185', volume200:'244:183', sidebar:'69:814', … }`) and `vlc4-icons.js` (`MAP`, VLC 4 `VLCIcons.json` key → Figma icon ID). The latter is handy if we restyle VLC's own macOS/Qt icon set.
- The token block `C` (Dark/BG/A4 `#191919`, BG/A3 `#1b1b1b`, BG/B1 `#0e0e0e`, Accent/Main `#d37918`, Accent/Bright `#fc9729`, Accent/Dim `#ab6314`, BG/Accent Bright `#371f06`, FG ramp `#eaeaea / #c6c6c6 / #969696 / #8f8f8f / #6b6b6b`, Divider `#222222` / `#373737`).
- Layout constants: top bar 40 px, control bar 54 px, play pill 54×28 r6, icon buttons 30×28 r6 with 24 px icons, window buttons 36×24 with 20 px icons, seek handle 8×24 r4, stage radius 9–10 px inset 10 px, rail buttons 36×36, volume wedge 88×28.

---

## 6. Figma colour tokens (resolved from `research/figma/figma_file.json`)

Values found on nodes that reference each style. "?" means the style isn't applied anywhere in the dump; get it from the `.fig` (§5.5) or the REST `/nodes` endpoint.

| Dark | Value | Light | Value |
|---|---|---|---|
| Accent/Main, Accent/Logo | `#D37918` | Accent/Main | `#E8851A` |
| Accent/Bright | ? (`#FC9729` per Green-Skeleton) | Accent/Logo | `#C2711A` |
| Accent/DIm | `#AB6314` | BG/Accent Bright | `#D8BA9A` |
| BG/A1 | `#222222` | BG/A3 Transparent | `#D5D5D5` @0.75 |
| BG/A2 | `#1F1F1F` | BG/A5 | `#888888` |
| BG/A3 | `#1B1B1B` | BG/B1 Transparent | `#E7E7E7` @0.80 |
| BG/A3 Transparent | `#191919` @0.95 | BG/B2 | `#DEDEDE` |
| BG/A4 | `#191919` | Divider/Bright | `#9B9B9B` |
| BG/A5 | `#151515` | Divider/Dim | `#ACACAC` |
| BG/B1 | `#0E0E0E` (+ Transparent @0.95) | FG/A2 | `#2E2E2E` |
| BG/B2 | `#090909` | FG/A3 | `#6B6B6B` |
| BG/Accent Bright | `#371F06` | others | ? (nagasab `theme.py` LIGHT has approximations) |
| BG/Accent Dark | `#1A1611` | | |
| Divider/Bright / Dim | `#373737` / `#222222` | | |
| FG/1, FG/2 | `#EAEAEA`, `#C6C6C6` | | |
| FG/A1…A4 | `#969696`, `#8F8F8F`, `#6B6B6B`, `#404040` | | |
| FG/B1 | `#161616` | | |
| Effect `bg blur` | BACKGROUND_BLUR 50 | Effect `bg blur + shadow` | BG blur 50 + drop shadow (0, 8) blur 15, black 46% |

Accent options (onboarding/settings, from nagasab `theme.py`): `#d37918 #e15032 #c49e23 #19a234 #18aad3 #185dd3 #8e42ff #f052b3 #afafaf`.

---

## 7. s1rd0 / BettererVLC

- **What:** another Skins2 `.vlt` for VLC 3 (Windows tested; Linux untested; README says macOS isn't supported).
- **Code:** Python **1,437 LOC** in `tools/`: asset build, theme build, DTD validator, deterministic packager, offline preview renderer, slider-binding regression check, synthetic-media and frame-latency diagnostics. Plus 3 `.bat` launchers and `skin/theme.xml` (257 lines).
- **Assets:** `design-assets/exported/` holds **34 PNGs exported from Figma at 1×** via the Figma Plugin API. `nodes.json` maps name → node ID + size (e.g. `play` = `848:1711` 54×28; window buttons `247:466…469` 36×24). There's also `Inter-Variable.ttf`. All the IDs resolve in our REST dump.
- **Features:** player, playlist ("library"), sidebar, mini and fullscreen-controls layouts. Transport, seek (257-state fill sprite), 0–200% volume, a real VLC playlist, native VLC menus for tracks and prefs, open file/folder/disc/network. Default 1280×720, minimum 1000×600.
- **Fidelity:** good for the main bar, since it uses real exported icons and Figma colours (`#1b1b1b`, `#d37918`, `#0e0e0e`, `#090909`, `#371f06`). `docs/preview-player.png` is an offline render, not a real screenshot. Same Skins2 limits as Green-Skeleton, and less complete: no EQ window.
- **Red flags:** 2 squashed commits, no co-author trailers. But the README's "not verified through the desktop automation tool because it did not expose the Skins2 window", plus the latency-measurement tooling, read like an AI agent's work log. The project name changed from "VLC Redesign" to "BettererVLC" on the same day.
- **Reusable:** only the PNG exports (1×, too low-res for Retina), `nodes.json` IDs, and the colour constants. Green-Skeleton and nagasab supersede it.

---

## 8. Comparison

| | Sayandeep1013 vlc-skins | pylon-player | nagasab221 vlc-redesign | Green-Skeleton redesign-skin | s1rd0 BettererVLC |
|---|---|---|---|---|---|
| Type | Standalone player + unrelated skins | Standalone player | Standalone player | Skins2 `.vlt` + **.fig toolchain** | Skins2 `.vlt` |
| Language / UI | C# .NET 8 WPF, LibVLCSharp | Python, PySide6, python-vlc | Python, PyQt5, python-vlc | Node JS (generator) → XML/PNG | Python (generator) → XML/PNG |
| Real code LOC | ~5.8 k (C# 4.5 k + XAML 1.1 k) + 0.8 k old skin | 5.6 k | **15.9 k** | 1.1 k | 1.4 k |
| Platform | Windows only | Windows (mostly portable Qt) | Linux/X11 only | Win/Linux VLC 3 | Win (Linux untested) VLC 3 |
| Runs on macOS today? | No | Probably, untested (has `set_nsobject` path) | No (X11, pactl, Xlib) | No (VLC 3 mac has no Skins2; VLC 4-dev mac Skins2 untested) | No (same) |
| Port effort to mac | UI rewrite | Low–medium (but stays Python/Qt) | Medium (but stays Python/Qt) | n/a | n/a |
| Uses Figma icons | No (Lucide) | No (own) | **Yes (SVG export, 206 variants)** | **Yes (rendered from .fig)** | Yes (34 PNG @1×) |
| Token fidelity | Approximate | Loose | High | **Exact** | High |
| Layout fidelity | Medium (control bar) | Low | **High (all screens)** | Very high (player chrome only) | High (player chrome only) |
| Video coverage | Bars, auto-hide, seek thumbs, waveform, cone, tracks, sidebar tabs, queue, music view (+ full VLC Effects/Tools) | Bars, subtitle timeline, presets, bulk subs, library, home/continue, bookmarks, prefs | **Nearly everything**: library, music, settings ×13, onboarding, customize, timeline, presets, dialogs | Player, sidebar rail, queue, EQ, mini, fullscreen | Player, playlist, mini, fullscreen |
| Missing | Library, timeline, settings, onboarding | Thumbs, waveform, layout editor, full settings | Reverse, HDR, casting (libVLC limits) | Everything beyond the chrome | Same + EQ |
| AI-generated signals | 7/8 commits Claude co-authored | Screenshot path `/tmp/claude-0/-home-claude…` | 17/17 Claude co-authored | 5/6 Claude co-authored | Agent-style test notes |
| Other red flags | Bundles third-party GPL/MIT skins; committed exe; libvlccore struct poking | Committed unsigned exe | `curl \| bash` + sudo | — | — |
| Best reusable item | `Effects.cs` catalogue; thumbnail and waveform approach | `SubtitleTimeline`; episode matcher; preset schema | **`icons.json`**, **`theme.py`**, **`prefs.py`** | **`decode.js` + `render.js`**; ID maps; layout constants | `nodes.json` |

## 9. Verdict

1. **For the macOS build, use none of these as a codebase.** They're two Python/Qt apps (Linux, Windows), one WPF app, and two Skins2 skins. None is native macOS, and Skins2 can't do the redesign on any platform. Released macOS VLC doesn't support it at all; VLC 4-dev's new macOS Skins2 backend changes nothing about the bitmap-only limits.
2. **Use Green-Skeleton's `.fig` toolchain as the design-extraction pipeline.** It's the only tool here that can losslessly pull **every frame, component, icon (as vector SVG), colour/effect style and exact layout measurement** out of the Figma file offline. It needs one manual step: the user saves a local `.fig` from Figma with their own account. Then add a small exporter script (icons → SVG/PDF assets, frames → @2x reference PNGs, styles → a Swift `Color` token file, frame walk → layout constants JSON).
3. **Until then, use nagasab221's `icons.json` (206 Figma SVGs) and its `theme.py` / `prefs.py` right away.** They're the fastest path to correct icons, tokens and a complete Settings spec. Use the colour table in §6 as ground truth.
4. **Mine the players for behaviour, not code:**
   - nagasab221 for the overall interaction model (library sidebar vs full library + mini player, customize editor, onboarding, presets)
   - pylon for the subtitle-timeline drag UX and episode matching
   - Sayandeep for the seek-thumbnail strategy (a second silent player + storyboard), the waveform, and the libVLC effect variable catalogue
5. **Sayandeep's "skins" are filler:** two unrelated third-party skins (VeLoCity, Materia) collected months before the video, plus the author's own abandoned Skins2 attempt. The relevant part is the Windows-only WPF player. It's moderately faithful (Lucide icons, approximate colours) and covers the player chrome and VLC's Tools, not the library, settings or onboarding.
