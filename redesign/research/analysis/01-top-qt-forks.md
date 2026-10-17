# 01 — Top Qt/QML forks of the Juxtopposed VLC redesign

Scope: `fork-dsojevic/juxtopposed-redesign`, `fork-Pyr0zen/redesign` + `fork-Pyr0zen/redesign-library`, `fork-Hamido212/redesign` (+ `adopt-dsojevic-preferences`), `fork-floklein/feat/redesign` + its 8 `research/*` branches and `prototype/bar-reveal`.
Method: read-only `git diff/log/show` against `git merge-base origin/master <branch>`, GitHub API (`gh`) for stars/CI/releases/issues, and a look at video keyframes and the forks' screenshots. Nothing was built. Date: 2026-10-14.

All four forks are VLC 4 (`master`) forks that restyle the Qt/QML interface in `modules/gui/qt`. All of them were written in the 48 hours after the video came out (2026-10-12), and all of them are AI-written. Pyr0zen, Hamido and floklein say so with `Co-Authored-By: Claude` trailers. dsojevic has no trailers, but it landed 32 commits and about 5.2k lines in about 8.5 hours. **None of them touches the native macOS interface (`modules/gui/macosx`).**

---

## TL;DR

| | dsojevic | Pyr0zen | Hamido212 | floklein |
|---|---|---|---|---|
| Stars | 27 | 23 | 2 (1 at time of list) | 0 |
| What it really is | Separate `player/qml/redesign/` layer swapped in by the main loader, plus a strong redesigned **Settings window and hotkey editor**, plus a compact/expanded library inside the player | Largest and most faithful player-side implementation (menus, sidebars, tracks popup, network dialog, hotkeys, Settings shell). A separate, **never compiled** library branch. **Best Figma-extracted data of any fork** | Player-only (control bar, top bar, tracks, a very complete settings sidebar, queue). Windows preview binary | Small UI (bars, sidebar/Home, two QML dialogs), heavy in-place rewrite. **Best engineering research docs** |
| Core (`src/`, `include/`) touched | Yes (+156/−57): audio output, es_out mouse, actions, vout window, plus pulse.c | **No** | Yes, small (+31/−4 in vout, plus D3D11/transform fixes, Windows-specific) | Yes (+88): new `vlc_player_SetPauseAtEnd`/`IsEnded` API, Win32 static modules |
| In-place edits of existing files | 22 files, +464/−86 | 52 files, +2.5k/−0.9k | 36 files, +1.9k/−0.7k | **149 files, +4.4k/−7.2k** |
| Built / run evidence | Tests in tree; built on Linux (PulseAudio); no CI, no screenshots | **GitHub Actions win64 builds, all green**; library branch never built | **Win64 release zip** + screenshots; also runs on Linux in Docker | Local win64 and Linux (WSL) builds + Qt tests; 82 GitHub issues; no CI or binaries |
| Reuse value for macOS | Settings catalog (Figma row → VLC option), preferences backend, layering pattern | **figma_file.json, FIGMA_FLOWS.md, styles.txt, 102 Figma PNG exports, 206 SVG icons**, VIDEO_INDEX checklist, component kit | tokens.json, figma-nodes.xml, Figma "reference code" TSX, settings-panel wiring for video filters | Research docs (engine feasibility, persistence, ML folders, blur, prefs mapping), ThemeTokens design |

---

## 1. Feature coverage vs the video

Legend: **Y** = implemented and wired to VLC; **P** = partial; **N** = not done; *(n.b.)* = coded but never compiled.

| Video section | dsojevic | Pyr0zen `redesign` | Pyr0zen `redesign-library` *(n.b.)* | Hamido212 | floklein |
|---|---|---|---|---|---|
| 01 Colors, icons, rounding | P: accent `#D37918` and dark BG match. The other tokens are eyeballed (`#101010`, `#292929`, `#e5e5e5`), and the light theme is invented (`#acacac` BG). About 16 toolbar SVG paths copied from Figma, the rest hand-drawn 24px glyphs. User accent color works | **Y**: exact Figma styles (dark + light), live accent with derived ramp, 9 onboarding accent options, Inter bundled, 206 Figma SVGs (audited, truncated exports fixed) | same base | Y: Figma palette dark + light; 80 Figma icons converted into VLC's icon font (stroke outlining script). No Inter yet | Y: `ThemeTokens` named 1:1 after Figma styles, Inter + DM Mono, icon font refresh with two-tone split (`TwoToneIcon.qml`, 264 glyph SVGs) |
| 02 Control bar (one row, play pill, thick seek bar, cone volume) | Y (own `RedesignSeekBar`/`RedesignVolume`; 54px bar, 10px inset) | **Y** + click-time-to-type, remaining-time toggle, 0–200% cone shader, volume tooltip | same | Y + volume box, **seek-preview thumbnail** (from Olmo-Gutierrez) | Y (new default layout, `SeekBarWidget`, cone) |
| 03 Top bar + fullscreen hover reveal | Y (cone, "…", sidebar, folder chip, title, window buttons; edge-hover reveal; auto-hide modes) | **Y** (per-bar near-edge reveal in fullscreen, 3s windowed fade) | – | P (top bar done; fullscreen hover unticked in roadmap) | P (top bar done; reveal only as throwaway HTML prototype + bar test) |
| 04 Subtitle/audio buttons, tracks popup with output device | Y (Video/Audio/Subtitles tabs, output device, add sub file, "Show Preferences") | Y | – | Y (incl. renderer list) | P (buttons added; reuses VLC's tracks menu) |
| 05 "…" menu, right-click menu, Hide UI | P ("…" menu redesigned; right-click = stock VLC menu; no Hide UI) | **Y** (C++ `RdMenuModel` + cascade menus, right-click, Hide UI Ctrl+\\) | – | N | P (top-bar menus restyled, no right-click redesign) |
| 06 Add-subtitles dialog (file/folder/playlist, OpenSubtitles) | N (file picker only) | N (Step 2) | P (library "Add subtitle/audio track" via `:input-slave`) | N | N (researched: OpenSubtitles XML-RPC is dead, REST needs API key/proxy) |
| 07 Settings sidebar (4 tabs), subtitle timeline, presets | P: Playback/Video/Audio/Subtitles sections, delays, speed, sleep timer, EQ with preset curves, zoom/crop/aspect/deinterlace. No timeline, no per-show presets | P+: 4-tab sidebar, 983-line `RdEffects` C++ bridge, EQ presets, filter expanders. No timeline/presets/sleep timer | – | P+: 2,056-line `SettingsPanel.qml`: subtitle style/position, audio filters/EQ/pitch, video filters (flip/rotate/crop/adjust, needed vout fixes), speed, sleep timer, visualizer. No timeline/presets | N (research only) |
| 08 Library (compact sidebar, full view, folders, sort/view, context menus, mini player) | P: compact + expanded library inside the player view (Home/Videos/Music/Network/Playlists/Recent), folder drill-down, back/forward, search, sort, grid/list. No mini player, no styled context menus | N (stock VLC) | **Y (most complete)**: rail, pins, breadcrumbs, folder tree models, Home sections, item/folder/playlist menus, unwatched-first sort, full-window view, **mini player with corner snap**, drag to queue | N | P: existing sidebar reduced to Home/Videos/Music/Network/Playlists/Recent, Home rows (Continue Watching, Listen Again, frequent folders...), edited in place |
| 09 Music view (cover, waveform) | P (artwork + artist when no video) | N | P (music pages; music player view deferred) | N | N |
| 10 Network streams / split open dialogs | P (URL field in library; menu calls stock dialogs) | **Y** (QML Open Network Stream; open/convert/stream QWidgets dialogs split and restyled via `RdWidgetStyle`) | Y (`RdStreamDialog`, m3u → stream list) | N | P (QML Open Disc, QML Media Properties; not network) |
| 11 Playlists / pins / recent / home / resume prompt | P (create playlist, recent, home; resume prompt near controls) | P (resume toast) | Y (playlists dialog, pins, Home, Recent) | N | P (Home/Recent/Continue Watching; queue persistence, "Play next") |
| 12 Bookmarks / chapters / OSD key | P (bookmark panel add/remove) | P (Queue sidebar has Bookmarks + Chapters tabs; no Ctrl+B / OSD key) | – | N | N |
| 14a Settings dialog (13 categories, basic/advanced, info) | **Y (best)**: full window, categories, search, basic/advanced, backed by real VLC options through a C++ catalog/transaction layer, autosave, QML tests | P (shell, search, info popovers; only Subtitles page has real rows) | – | N (WIP port of dsojevic's; does not start on Windows) | N (research: maps about 217 Figma rows to options) |
| 14b Keyboard-shortcuts dialog | **Y** (native capture, conflict reassign, alternates, save/cancel) | Y (`hotkeys_model.cpp` 708 lines; applies after restart) | – | N | N |
| 15 Customize mode / profiles / onboarding | N (menu opens stock toolbar editor) | N (stock editor) | N | N | N |
| Extras not in the video | Spatial-audio/startup-volume/default-device/mouse-click/wheel settings (core changes), PulseAudio fixes | perf harness, Windows test launcher | – | D3D11 hardware-rotation fix, renderer scan | **DirectComposition video-blur spike (Windows)**, QML Media Properties, QML Open Disc, queue persistence, "pause at end" core API, GTK theme provider **deleted** |

**Rough coverage of buildable surface:**
- Pyr0zen (both branches combined) is about 55–60%.
- dsojevic is about 45%, with the widest functional spread: player, library, settings and hotkeys.
- Hamido is about 25%, player only, but deep.
- floklein is about 15–20%.

None of them does the subtitle timeline, waveform, per-show presets, Add-Subtitles matching dialog, customization or onboarding: the "NEW" engine-dependent items.

Fidelity check:
- Hamido's screenshot (`redesign/screenshots/settings.png`) matches the video frames closely: cone gradient, gear-with-play icon, 4-tab sidebar, orange underline.
- Pyr0zen works from the Figma JSON with measured specs, so its fidelity should be highest.
- dsojevic uses approximate sizes: video radius 10 vs Figma 19, an invented light palette, generic secondary icons.

---

## 2. Real code size (excluding binaries, SVG/PNG/fonts, docs/MD, reference data, tooling scripts)

| Branch | QML | Qt C++ (cpp/hpp) | Core `src/include/lib` | Other modules | Build files | Tests |
|---|---|---|---|---|---|---|
| dsojevic | +3,377 / −2 | +823 / −16 | +156 / −57 | +42 / −9 (pulse.c, medialibrary.cpp) | +59 | +746 (QML tests + `test/src/player`, `test/src/misc/actions.c`) |
| Pyr0zen `redesign` | +9,532 / −705 | +4,125 / −163 | 0 | 0 | +586 (incl. 216-line qrc) | 0 (`qmlcheck.py` tooling only) |
| Pyr0zen `redesign-library` | +10,538 / −1,578 (library part ≈ +5.2k new QML, MainDisplay.qml −882) | +3,807 / −137 (library part ≈ +2.6k: 5 new models/store) | 0 | 0 | +598 | 0 |
| Hamido212 `redesign` | +4,178 / −557 | +811 / −90 | +31 / −4 | +45 (d3d11, transform) | +22 | 0 (PowerShell UI scripts) |
| floklein `feat/redesign` | +3,463 / −1,270 | +4,393 / −5,398 (deletes GTK theme provider, QWidgets mediainfo/fingerprint dialogs) | +88 | +11 (hotkeys.c) | +427 / −114 | +2,836 (Qt model tests, QML tests, player EOF test) |

### Non-code bulk, and whether it is useful Figma data

- **Pyr0zen (about 88 MB):**
  - `redesign/reference/figma/figma_file.json` (**26 MB, the full Figma REST API document** of "VLC Redesign (Community)", version 2409521707817118521, 28,360 nodes). It has auto-layout, padding, gaps, radii, text styles and 3,627 text strings, but no vector geometry.
  - `styles.txt`: all 51 color and effect styles, dark and light, with the hex values, plus the blur and shadow specs.
  - **102 PNG exports at 2x of every top-level frame and component** (48 MB).
  - **206 Figma SVG icons** in `modules/gui/qt/pixmaps/redesign/`.
  - `FIGMA_FLOWS.md` (4,213 lines, generated from the JSON). It covers 2,708 prototype interactions, timings and easing, and an exact component spec table: sizes, paddings, radii, token names.
  - `VIDEO_INDEX.md` (709 lines): a 349-row checklist of every item in the video, with UI/NEW tags.
  - `RESIDUAL_AUDIT.md`: where each of 380 current VLC UI elements ends up.
  - Also: 97 scene frames plus 490 library frames from the YouTube video (38 MB) and the full `.srt` transcript. These are copyrighted video content, so do not redistribute them.
  - **Highest-value data asset across all forks.**
- **Hamido212:**
  - `redesign/design/tokens.json`: paint styles from another copy of the Figma file, the same values as Pyr0zen's.
  - `figma-nodes.xml` (7,923 lines): every node's id, type, name, position and size.
  - `player-reference.tsx` and `playback-reference.tsx`: Figma Dev Mode/MCP "reference code" with colors and spacings.
  - `queue-panel.md` (measurements).
  - `icons/figma/` (207 SVGs + `index.json` with node ids; a different export from Pyr0zen's) and `outline.py` (stroke → fill for the icon font).
  - 3 running-app screenshots.
- **floklein:**
  - `AUDIT.md`: Figma node-id inventory per screen and component, plus the transcript.
  - `GLOSSARY.md`: the domain vocabulary.
  - 264 split two-tone icon SVGs + `splitFigmaIcons.py`.
  - Inter/DM Mono fonts.
  - Agent build scripts (`extras/agents/*`, about 1k lines).
- **dsojevic:** none committed. `/.design-reference/` is gitignored. The icons are inlined in `RedesignIcon.qml`, with Figma canvas offsets still visible in their `translate(...)`.

---

## 3. Approach and quality

### dsojevic — additive layer plus core plumbing

**Layering.**
- All UI lives in a new `modules/gui/qt/player/qml/redesign/` directory: 26 `Redesign*.qml` files and a `RedesignTheme` QtObject.
- `MainInterface.qml` changes only the loader. Player mode and `MAININTERFACE_MODE_MAINDISPLAY` both load `RedesignPlayer.qml`; the stock player is kept only for `Player.isInteractive`. So the old MainDisplay library is no longer reachable, because the library lives inside the player view.
- `RedesignPlayerView` is presentation-only, with properties and signals. `RedesignPlayer` binds it to `Player`, `MainPlaylistController` and `MediaLib`. This makes it testable stand-alone (`tst_Redesign.qml`).

**C++ backend.**
- `redesign_preferences.cpp/.hpp` (667 + 65 lines): a transactional preferences object (stage/save/discard/autosave). It provides an option catalog and `describe()` metadata from VLC's config, EQ bands, a shortcut catalog with conflict detection and reassignment, and path/color pickers.
- `RedesignPreferencesCatalog.qml` maps every Figma settings row to a VLC option name. This mapping is reusable anywhere, including a native macOS UI.

**Why core is touched.** The redesigned settings expose options VLC does not have, and dsojevic implemented them in core:
- `src/libvlc-module.c` adds `audio-startup-volume`, `audio-last-volume`, `audio-device-default(-module)`, `audio-spatial(-mode)`, `mouse-double-click-action` and `hotkeys-wheel-direction`.
- `src/audio_output/output.c` applies the startup or last volume and the preferred device in `aout_New`, saves the last volume on change, and adds spatial-mode handling. It also changes the default headphone→binaural auto-select so that it only happens when "spatial" is on. **That is a behavior change for every user.**
- `src/input/es_out.c` and `src/video_output/video_window.c` make the double-click action configurable (fullscreen / play-pause / none) and read the mouse pause policy live.
- `src/misc/actions.c` replaces the startup-time wheel mappings with a live lookup, so wheel preferences apply without a restart.
- `modules/audio_output/pulse.c` remembers volume and device between streams, and supports returning to the default device (Linux only).
- `modules/misc/medialibrary.cpp` adds `cannot_unload_broken_library()`, a teardown crash fix.
- `test/src/player/*` and `test/src/misc/actions.c` are tests for the new aout defaults and the wheel actions. **This is the "why" of the `test/src/player` changes: unit tests for the new startup-volume and default-device core behavior.**

**Qt-side tweaks:**
- `qt-titlebar` now defaults to false on all platforms (client-side decorations).
- The default color scheme index is changed.
- A new `qt-controls-autohide`, `-hide-timeout` and `qt-notification-timeout` option set.

**Quality.**
- The QML is compact, with some very dense one-liners: nested ternaries 200+ characters long.
- It uses `QtQuick.Controls` throughout (20 files). Upstream VLC uses `QtQuick.Templates` almost exclusively (83 vs 6 files).
- Hamido found that **VLC's static Windows Qt has no Controls styles, so dsojevic's QML fails to load on Windows**. On Linux and macOS with a system Qt this works, and upstream already forces the Basic style on macOS.
- Overall: competent and tested, but it mixes UI work with opinionated core behavior changes.

### Pyr0zen — in-place restyle plus an `Rd*` component kit, no core changes

**Changes.**
- New kit: about 25 `widgets/qml/Rd*.qml` controls (Button, Slider, Toggle, Dropdown, ValueBox, Segmented, Expander, Tooltip, Shadow...).
- New C++: `rd_effects.cpp` (983 lines, an audio/video effects bridge with per-key cache and coalesced applies), `rd_menu_model.cpp` (773 lines), `hotkeys_model.cpp` (708 lines), `rdfonts`, `rdwidgetstyle` (QWidgets restyle).
- Existing files restyled in place: `Player.qml`, `ControlBar.qml`, `TopBar.qml` (−352), `PlayButton.qml`, `ResumeDialog.qml`, `VolumeWidget.qml`, `systempalette.cpp`, `VLCStyle.qml`, `dialogs_provider.cpp` and `CSDWindowButtonSet.qml`.
- The library branch adds 5 new C++ models/store (`RdLibraryStore` with QSettings, `RdSubfolderModel`, `RdConcatModel`, `RdCollectionModel`, `RdLibraryModel`) and rewrites `MainDisplay.qml`.

**Process.**
- A very heavy, AI-driven project-management layer: `CLAUDE.md` (173 lines), BUILD_PLAN (570), decision logs ("Decision 32"), "web session vs PC session" agents, review passes by subagents, and a perf harness.
- The code itself is careful. It has review-fix commits, explicit rules not to remove VLC features, and it only fixed one upstream bug (a missing import in the toolbar editor).

**Core:** zero changes, which is the best fit for "engine untouched".

**Gaps:**
- The library branch was written by a cloud session. It was only syntax-checked against Qt 6.4 headers and has **never been compiled or run**.
- It branched from an early commit (`67ec8e0347`), so it lacks the sidebars, menus and dialogs and needs a non-trivial merge into `redesign`.
- Settings pages are mostly placeholders.

### Hamido212 — in-place player restyle plus Windows engine fixes

**Changes.**
- Edits `Player.qml`, `ControlBar.qml`, `TopBar.qml`, `SliderBar.qml`, `PlayButton.qml`, `VolumeWidget.qml`, `CSDWindowButtonSet.qml` and `systempalette.cpp` in place.
- New `SettingsPanel.qml` (2,056 lines), `QueuePanel.qml`, `TracksPanel.qml` and `PlayerPanel.qml`.
- `player_controller.cpp` (+415): sleep timer, seek thumbnails (preparser-based), audio filter/EQ preset/video filter setters, subtitle text scale and margin.

**Core and other modules:**
- `src/video_output/video_output.c`: accepts orientation changes without a converter, and restores the display format when filters are removed. This makes flip/rotate work with hardware decoding.
- `modules/video_output/win32/direct3d11.cpp` and `video_filter/transform.c` are the matching Windows-specific D3D11 fixes.
- These are legitimate engine bug fixes, upstreamable, and outside the redesign itself.

**Build.**
- Docker-based Windows and Linux builds (`redesign/container-build*.sh`, `docker-build*.ps1`) and PowerShell screenshot and UI-test scripts.
- `VERIFICATION.md` records what was actually seen working.
- The README is honest: "vibe-coded", English only, can leave `vlc.exe` running.

**`adopt-dsojevic-preferences`:** a single WIP commit that copies dsojevic's preferences window. It builds but does not start on Windows (the Controls-style issue above).

### floklein — process-heavy, invasive in-place evolution

**Changes.**
- Rewrites `systempalette.cpp` (−472) into `ThemeTokens`.
- **Deletes the GTK theme provider** (about 2.3k lines, plus `configure.ac`/meson options) and the `systempalettethemeprovider`.
- Ports the Media Information and Fingerprint QWidgets dialogs to QML (`MediaPropertiesDialog.qml` + `media_properties_model.cpp`, deleting about 1.5k lines of QWidgets code).
- Adds a QML Open Disc dialog, a queue persistence store (`queue_store.cpp`), a play-count ranking model and a DirectComposition video-blur prototype (`compositor_dcomp_videoblur.cpp`, off by default).

**Core:**
- Adds a public `vlc_player_SetPauseAtEnd()` / `vlc_player_IsEnded()` API and symbols, so the player stays on the last frame at playlist end and Play restarts the playlist. The hotkeys module is updated to use it.
- Adds a Win32 `GetProcAddress` static-module loader in `src/modules/bank.c`, needed so its Qt tests run on Windows.

**Quality.**
- The best testing discipline of the group: 2.8k lines of Qt and QML tests.
- The project is run through GitHub issues: 82 issues with grilling, research and prototype tickets, and AGENTS/CLAUDE docs.
- The visible redesign surface is still small.

### floklein research branches — summary of value

Each `research/*` branch adds one doc under `docs/research/`. They are high quality: every claim is backed by a file:line reference.

| Doc | Key findings |
|---|---|
| `playback-feasibility.md` | **Seek thumbnails**: UI-only on the existing preparser thumbnailer (S–M). **Sleep timer**: UI-only. **Audio device switch**: supported (`AudioDeviceModel`; hot-plug refresh gap). **Default sub/audio language**: supported globally (`sub-language`/`audio-language`); per-show presets need storage. **Subtitle timeline**: no cue API; external text subs can be parsed Qt-side with `demux_New` (M), embedded subs L+. **Waveform**: needs a whole-file decode job (M–L). **True reverse playback**: XL, rule it out; "hold to step back" via `vlc_player_PreviousVideoFrame` is S. **OpenSubtitles**: bundled VLSub uses the XML-RPC API, shut down 2026-01-29; REST needs a consumer API key or proxy |
| `persistence-feasibility.md` | Per-show presets and profiles need new storage (QSettings/JSON). Watched state, recent and favorites are supported by the media library. Subtitle-to-episode matches can live in ML external files but need a load hook |
| `library-folders.md` | The ML engine has folders, subfolders, progress, play count and add/remove folder. The Qt UI uses little of it. No parent-folder API, no folder-by-MRL, no last-played or in-progress sort exposed. An ML "Show" is filename-based (`SxxEyy`), so the redesign's "show = folder" must be an ML folder. **The macOS UI already has a Shows model, Qt doesn't** |
| `preferences-structure.md` (583 lines) | 2,078 option declarations, of which 1,647 are GUI-visible, plus 114 hotkey actions. Draft distribution into the 13 Figma categories. About 217 Figma rows mapped to options; about 25 rows are new behavior. Duplicate and wording audit |
| `theme-system.md` | The Qt `SystemPalette`→`ColorContext` + `VLCStyle` can express the design system. Needed extensions: bundled Inter/DM Mono, derived accent ramp, radius tokens, two-tone icons (split glyphs) |
| `backdrop-blur.md` | **No compositor puts video pixels in the Qt scene**, so QML cannot blur video. Over video: tint only. The macOS `platform` compositor is in the same situation |
| `cheap-blur-backdrop.md` | Only Windows DirectComposition can cheaply re-show the video swap chain blurred (size M). Elsewhere, low-res grabs lag 250–500 ms |
| `figma-coverage.md` | Per-surface Full/Partial/Missing in Figma, with node ids (Controls variants, sidebar variants, Miniplayer) |
| `prototype/bar-reveal` | Throwaway HTML prototype of bar reveal timing |

---

## 4. Upstream-mergeability

- **Base age:**
  - dsojevic merged `upstream/master` on 2026-10-14, so it is **0 commits behind**.
  - Hamido is 7 behind (base 2026-09-04 author date).
  - Pyr0zen and floklein are 23 behind (base 2026-10-09).
  - All bases are fresh; the problem is future churn.
- **Upstream churn:** `modules/gui/qt` got **564 upstream commits in the last 180 days** (about 3 per day). How many of those landed on files each fork edits in place:

| Fork | Files edited in place | Upstream commits on those files (180 days) | Files with ≥3 such commits |
|---|---|---|---|
| dsojevic | 22 | 221 | 13 |
| Hamido212 | 36 | 301 | 22 |
| Pyr0zen | 52 | 316 | 25 |
| floklein | 149 | 642 | 62 |

- **Ranking for rebase pain:**
  1. **dsojevic, least painful for the Qt layer.** The UI is additive and selected by one loader switch. However, the 7 core files will conflict with any aout/es_out/actions work, and the core semantics changes (binaural auto-select, wheel mapping) are things a long-lived fork should not carry.
  2. **Pyr0zen.** No core changes, but restyling `Player.qml`/`ControlBar.qml`/`TopBar.qml`/`systempalette.cpp` in place will conflict regularly. The `Rd*` kit and new dialogs are additive and portable.
  3. **Hamido**, similar to Pyr0zen, plus engine fixes that should be upstreamed rather than carried.
  4. **floklein, worst.** It deletes subsystems (GTK provider, QWidgets dialogs), renames and merges library views, adds core API, and changes `configure.ac`/meson options. Its stated goal is "fork-only, no upstreaming, replace in place".
- Trial 3-way merge against current master: Pyr0zen 0 conflicts and floklein 1 conflict today. That is cheap now, but on the files above the conflict count will grow quickly.

---

## 5. Build status and macOS applicability

| Fork | Evidence it builds and runs | OS |
|---|---|---|
| dsojevic | Commits like "avoid duplicate generated About declarations", QML tests and C tests in meson/automake. Hamido confirms it compiles. No CI, screenshots or binaries | Linux (PulseAudio work). Fails at runtime on VLC's static Windows Qt (no Controls styles) |
| Pyr0zen | **GitHub Actions `build-windows`: 8 recent runs green** (VideoLAN win64 docker image); artifacts `vlc-redesign-win64` (about 97 MB) available; `TESTING.md` launcher. `redesign-library`: **never compiled** | Windows only |
| Hamido212 | **Release `redesign-preview-1` (win64 zip, 114 MB)**; screenshots on Windows and Linux (Xvfb in VideoLAN's Debian image) | Windows, Linux |
| floklein | Local win64 (cross) and Linux builds via WSL scripts, tests run there. No CI or binaries | Windows, Linux (X11 + Wayland) |

### Can the VLC 4 Qt UI run on macOS?

Realistic for development, but not the supported shipping path:
- Upstream has a `CompositorPlatform` path for the `cocoa` platform (`compositor.cpp:63`, `compositor_platform.cpp`). meson has darwin framework flags (`meson.build:26`).
- Recent upstream commits target the Qt UI on macOS: "set Basic style on macOS for Qt Quick Controls" (2026-01), Cocoa restrictions, closeEvent.
- But VLC's contrib does **not** build Qt for macOS (`contrib/src/qt/rules.mak`: `#PKGS += qt` is commented out). You would need a Homebrew or official Qt ≥ 6.2 (realistically 6.8) and your own `.app` bundling (macdeployqt-style).
- Official macOS VLC 4 ships the native Cocoa UI in `modules/gui/macosx`.

### What carries over to macOS

- **QML/C++ from any fork** is platform-agnostic Qt and would mostly work on macOS.
  - dsojevic's `QtQuick.Controls` usage is *more* likely to work on macOS (dynamic Qt with styles; upstream forces Basic) than on Windows.
  - Client-side window decorations (all forks) need checking against macOS traffic-light conventions.
- **Video behaviour on macOS:** the video lives in a native child window under a transparent Quick window. So:
  - rounded video corners via an overlay mask work (dsojevic and Pyr0zen draw a BG-colored frame over the video);
  - **blur over video is impossible**, so use tint;
  - in-scene blur over the library and dialogs works.
- **Windows-only parts to ignore:**
  - floklein's DComp blur and Win32 test loader;
  - Hamido's D3D11/transform fixes (the generic `video_output.c` part is portable);
  - Pyr0zen's Windows CI and launcher.
- **Linux-only part to ignore:** dsojevic's `pulse.c`. Its generic aout default-device logic would need CoreAudio (`auhal`) device-ID semantics checked.
- **If the macOS effort goes native** (AppKit/SwiftUI over `modules/gui/macosx`, or over libvlc/VLCKit), no QML is reusable. Still reusable:
  - the Figma data (Pyr0zen, Hamido);
  - the specs and checklists (Pyr0zen FIGMA_FLOWS/VIDEO_INDEX, floklein AUDIT);
  - the settings-row→option mapping (dsojevic catalog, floklein preferences-structure);
  - the engine-feasibility research (floklein, which is about VLC core and therefore platform-agnostic). Note that the native macOS library already has a Shows model.

---

## 6. AI generation, sloppiness, unrelated extras

- **All four are AI-authored.**
  - Pyr0zen: 113/113 commits Claude co-authored; the library branch is authored "Claude".
  - Hamido: 24 commits Claude co-authored; the README says "vibe-coded".
  - floklein: 26 Claude co-authored.
  - dsojevic: no trailers, but 32 commits and 5.2k lines in about 8.5 hours.
- **Pyr0zen:**
  - Large process artifacts (CLAUDE.md, decision logs addressed to "Tony", perf harness, agent-session rules).
  - Commits **copyrighted video frames** (about 38 MB) and the transcript into the repo.
  - Hard-coded local paths (`C:\Users\Prem\...`).
  - The code itself is reasonably disciplined.
- **floklein:**
  - Agent infrastructure (`extras/agents/*`, `AGENTS.md`, `docs/agents/*`) with machine-specific paths (`C:\Users\flo-k.DESKTOP-LHU5KDO\...`).
  - Unrelated extras: removing the GTK theme provider, porting the Media Info and Fingerprint dialogs, Windows blur, the queue "Play rule".
- **dsojevic:**
  - Unrelated or opinionated engine extras: spatial-audio modes, a changed binaural default, PulseAudio volume/device persistence, `qt-titlebar` default flip on Linux and macOS, and a medialibrary unload workaround.
  - Long one-line QML expressions.
  - Hand-invented light theme and filler icons. The comment "the supplied cat is reference footage only" hints at non-committed reference media.
- **Hamido:** small, honest scope. The engine fixes (D3D11 rotation with hardware decoding) are real but unrelated to the design.

---

## 7. Ranking and verdict (for a macOS effort that keeps the engine untouched and tracks upstream)

| Rank | Fork | Reuse verdict |
|---|---|---|
| 1 | **Pyr0zen** (`redesign` + `redesign-library`) | **Take the data wholesale:** `figma_file.json`, `styles.txt`, the 102 Figma PNG exports, 206 SVG icons, `FIGMA_FLOWS.md` (exact component specs and prototype behaviours) and `VIDEO_INDEX.md` (349-row checklist). For a Qt route, the **`Rd*` component kit, `RdEffects`, `RdMenuModel`, `hotkeys_model`, and the library models/QML** are the most complete, core-free implementation. The library must be merged and compiled first. Skip the reference video frames (copyright) and the Windows tooling |
| 2 | **dsojevic** | Best **architecture pattern** (a self-contained `redesign/` QML layer switched in at one point; presentation separated from binding) and the best **Settings window + hotkey editor**. Reuse `RedesignPreferencesCatalog.qml` (Figma row → VLC option map) and `redesign_preferences.cpp`. **Do not take the core changes** (`src/audio_output`, `es_out`, `actions`, `video_window`, `libvlc-module`, `pulse.c`). Drop the rows that need them, or re-implement them in the UI layer. Expect to swap Controls→Templates for Windows; macOS is probably fine |
| 3 | **floklein** (research branches) | **Read the 8 research docs first.** They are the best map of which redesign features are UI-only versus engine work, and they apply to macOS as well. Also worth reading: the `ThemeTokens` design, `AUDIT.md` node-id inventory, and GitHub issue decisions. Do **not** reuse the `feat/redesign` code: too invasive, Windows/Linux-centric, deletes subsystems, adds core API |
| 4 | **Hamido212** | Useful **cross-check data** (`tokens.json`, `figma-nodes.xml`, Figma reference TSX, an icon-font pipeline) and a working reference for wiring the settings sidebar to VLC video and audio filters (`player_controller.cpp` additions, `SettingsPanel.qml`). The vout/D3D11 fixes belong upstream, not in a UI fork |

**Bottom line:**
- No fork is shippable on macOS as-is, none has been built or tested on macOS, and none attempts the hard "NEW" features (subtitle timeline, waveform, presets, Add-Subtitles matching, customization, onboarding).
- For a macOS effort, start from **Pyr0zen's Figma extraction and specs plus floklein's feasibility research**, regardless of UI technology.
- If staying on Qt/QML, combine **dsojevic's additive-layer pattern** (to minimise rebase pain and keep `src/` untouched) with **Pyr0zen's core-free components and library code**, and borrow dsojevic's Settings and hotkey UI minus its core edits.
