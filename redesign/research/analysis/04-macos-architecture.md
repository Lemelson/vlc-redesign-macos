# 04 — macOS architecture options for a native rebuild of the Juxtopposed VLC redesign

Date: 2026-10-14. Sources: upstream VLC master at `4ca4eb0c3e` (2026-10-13), VLCKit master at `2e0868f` (2026-10-01, tag `4.0.0-a25`), LePips/VLCUI `84dccff`, the video transcript, and the keyframes.
All paths are relative to `the repo root` unless stated otherwise. Estimates are labelled as estimates.

---

## TL;DR

- **Recommendation: Option D.** Build a new in-tree interface plugin (`modules/gui/<name>/`) in a VLC fork. Keep the libvlc/vlc_player/vlc_playlist/vlc_medialibrary/config engine and the `VLCSampleBufferDisplay` video output untouched.
  - Write the UI as a **Swift/SwiftUI + AppKit package behind a backend protocol**. A small Objective-C glue layer adapts the VLC internal C APIs and reuses upstream's `modules/gui/macosx` model classes.
  - The only upstream files you touch are about 5 small glue files. Upstream's `modules/gui/macosx` (634 commits in 2026) stays untouched, so you keep pulling upstream VLC with almost no conflicts.
- **Video performance is the same in all four options.** On macOS every option ends up on the same vout: `VLCSampleBufferDisplay`, score 600, backed by `AVSampleBufferDisplayLayer`, fed an `NSView` through `VLC_WINDOW_TYPE_NSOBJECT`. The UI toolkit only affects overlay and idle cost, not decoding or rendering.
- **Option C (a standalone app on VLCKit/libvlc) cannot do the redesign's settings screen.** Neither libvlc nor VLCKit has an API to:
  - list or read/write VLC's config tree;
  - set object variables live;
  - use the media library;
  - run Lua extensions or addons;
  - use the hotkeys engine.
  On top of that, prebuilt VLCKit 4 is built with `--disable-lua --disable-medialibrary --disable-gpl` and strips about 60 filter modules. C is fine for a "lite / App Store" spin-off, not for 1:1 feature parity.
- **Option B (Qt/QML on macOS) is buildable but not supported.**
  - `configure.ac:4267` forces `enable_qt="no"` on darwin.
  - `contrib/src/qt/rules.mak:7-8` comments out Qt for `HAVE_MACOSX`.
  - CI has no macOS Qt job.
  - Meson will build it against a Homebrew Qt 6, and there is a `CompositorPlatform` path for cocoa.
  - It is the best way to share QML with the Windows community forks, but it is the worst Mac-native result.
- **Option A (restyle `modules/gui/macosx` in place)** means rebasing against the busiest directory in VLC: 634 commits in 2026, 442 of them by one maintainer, mostly in `library/` and the XIBs. That is a permanent merge-conflict tax, and XIB conflicts are close to unmergeable.

---

## 1. Facts established from the code

### 1.1 How the macOS VLC.app is put together today

- `bin/darwinvlc.m` is the executable.
  - It calls `libvlc_new()` with `--no-ignore-config --media-library` (lines 226-227).
  - It then calls the **internal** `libvlc_InternalAddIntf(vlc->p_libvlc_int, NULL)` (line ~293). This loads the highest-scoring `interface` plugin.
- The macOS GUI is the `macosx` plugin. `modules/gui/macosx/main/macosx.m` registers:
  - `set_capability("interface", 200)` with license `VLC_LICENSE_GPL_2_PLUS`;
  - a `vout window` submodule with score 100. Its `WindowOpen()` in `windows/video/VLCVideoOutputProvider.m:171` fails cleanly when the macosx interface isn't running. A different interface plugin can therefore provide its own vout window without fighting it.
- Size of the GUI plugin:
  - about 94k lines of ObjC: 78.8k in `.m` files, 49 XIBs in `UI/`, no Swift at all;
  - there is not one Swift-related commit in VLC history.
- Build system:
  - **Autotools only**: `modules/gui/macosx/Makefile.am`. It already has custom rules for `actool` (asset catalogs), `ibtool` (XIB to NIB) and `metal`/`metallib`.
  - Meson does **not** build the macOS GUI. `meson_options.txt:856` says `# TODO: Missing macosx`. Only `minimal_macosx` is in `modules/gui/meson.build`.
  - `extras/package/macosx/VLC.xcodeproj` is a convenience project with 2 native targets, not the real build.
- Packaging:
  - `extras/package/macosx/package.mak` copies `modules/gui/macosx/UI/*.nib`, `Assets.car`, `Shaders.metallib` and `share/Info.plist.in` into `VLC.app`.
  - `Info.plist` sets `CFBundleIdentifier org.videolan.vlc`, `SUFeedURL https://update.videolan.org/vlc/sparkle/...` and VideoLAN's Sparkle `SUPublicEDKey`. A fork **must** change all three.
- Minimum OS is macOS 10.13: `extras/package/macosx/env.build.sh:4` and `NEWS`. Upstream uses `@available(macOS 26.0, *)` with `NSGlassEffectView` (Liquid Glass) in several library views, for example `library/VLCLibraryHeaderView.m:117` and `library/VLCLibraryWindowPlayQueueSidebarViewController.m:167`.

### 1.2 Architecture of `modules/gui/macosx` (relevant for A and D)

| Layer | Key files | Notes |
|---|---|---|
| Bootstrap | `main/macosx.m`, `main/VLCMain.m` (`OpenIntf`), `main/VLCApplication.m` | Creates `NSApplication`, the `VLCMain` singleton, the controllers, `MainMenu.xib`, and Sparkle (`VLCMain+Sparkle.m`) |
| Player model | `playqueue/VLCPlayerController.[hm]` (2,213 lines) | Wraps `vlc_player_t`. Re-broadcasts about 45 `NSNotification`s (`VLCPlayerTimeAndPositionChanged`, `VLCPlayerTrackListChanged`, `VLCPlayerSubtitlesDelayChanged`, …). Exposes tracks, delays, `subtitleTextScalingFactor`, A-B loop, teletext, programs, titles/chapters, recording, renderer, OSD (`vlc_player_osd_Message`), volume/mute, fullscreen, PiP and snapshot |
| Play queue | `playqueue/VLCPlayQueueController.m`, `VLCPlayQueueModel.m`, `VLCPlayQueueItem.m` | Wraps `vlc_playlist_t` |
| Library model | `library/VLCLibraryController.m`, `VLCLibraryModel.m` (2,527 lines), `VLCLibraryDataTypes.m` (2,150 lines), `VLCLibraryImageCache.m`, `VLCInputItem.m`, `library/media-source/VLCMediaSource*.m` | Wraps `vlc_medialibrary` (`vlc_ml_*`) and `vlc_media_source` (local/network browsing). Most active churn: 835 file-touches in `library/` in 2026 |
| Main window | `library/VLCLibraryWindow.[hm]` + `UI/VLCLibraryWindow.xib` | VLC 4 merged the library and the video into one window (`VLCFullVideoViewWindow` subclass) with split views, a sidebar (`VLCLibraryWindowNavigationSidebarViewController`, play queue, chapters, titles) and segments (home, video, audio, playlists, favorites, groups, browse, streams) |
| Video view | `windows/video/VLCMainVideoViewController.m` + `UI/VLCMainVideoView.xib`, `VLCVoutView.m`, `VLCVideoOutputProvider.m`, `VLCVideoWindowCommon.m` | Overlay controls with a centered play-button stack ("central controls"), fake title bar, return-to-library button, autohide |
| Control bars | `windows/controlsbar/VLCControlsBarCommon.m`, `VLCMainVideoViewControlsBar.m`, `VLCMainWindowControlsBar.m`; views `views/VLCPlaybackProgressSlider*.m`, `views/VLCVolumeSlider*.m` | IBOutlet-driven, XIB-coupled |
| Panels | `panels/VLCAudioEffectsWindowController.m` (1,322), `VLCVideoEffectsWindowController.m` (1,390), `VLCTrackSynchronizationWindowController.m`, `VLCBookmarksWindowController.m`, `VLCInformationWindowController.m` | These hold the logic for the redesign's sidebar tabs (EQ, filters, sync), mixed with UI code |
| Preferences | `preferences/prefs.m` (736), `prefs_widgets.m` (2,053), `VLCSimplePrefsController.m` (1,680) | The full tree is built from `module_list_get()`, `module_config_get()` and `vlc_config_cat_*`. Saved with `config_SaveConfigFile()` (`prefs.m:220,470,493,568`) |
| Hotkeys | `coreinteraction/VLCHotkeysController.m` | Turns `NSEvent`s into VLC key codes and sets `"key-pressed"` on the intf/vout. The **core** `hotkeys` module then runs the action and shows the OSD |
| Extensions | `windows/extensions/VLCExtensionsManager.m`, `VLCExtensionsDialogProvider.m` | Lua extensions through `vlc_extensions.h`. This is how the VLSub subtitle downloader runs |
| Core dialogs | `panels/dialogs/VLCCoreDialogProvider.m` | `vlc_dialog_provider_set_callbacks` |

Core headers used across the module (counted by `#import`): `vlc_configuration.h` (22 files), `vlc_media_library.h` (18), `vlc_interface.h` (12), `vlc_modules.h` (10), `vlc_actions.h` (8), `vlc_player.h`/`vlc_playlist.h`/`vlc_dialog.h` (4 each), `vlc_extensions.h`, `vlc_config_cat.h`, `vlc_addons.h`, `vlc_media_source.h`, `vlc_renderer_discovery.h`.

Coupling of the model layer is moderate. For example, `VLCPlayerController.m` imports `main/VLCMain.h` and 3 UI headers (`windows/video/VLCMainVideoViewController.h`, `VLCVoutView.h`, `VLCVideoWindowCommon.h`). `VLCPlayQueueModel.m` and `VLCLibraryModel.m` import no UI. Model plus glue is about 20k lines that can be reused (section 3 has the strategy).

### 1.3 Video output path on macOS (performance)

- The vout display modules and their scores:
  - `modules/video_output/apple/VLCSampleBufferDisplay.m:1484`: `set_callback_display(Open, 600)`. Its help text says "This is the default display for Apple platforms". It accepts only `VLC_WINDOW_TYPE_NSOBJECT` (line ~888) and adds a `VLCSampleBufferDisplayView` (`AVSampleBufferDisplayLayer`) plus a separate subpicture view to the provided view.
  - Fallbacks: `caopengllayer.m` (300), `macosx.m` (290), `opengl/display.c` (265/270).
  - PiP: `apple/VLCPictureInPictureController.m` (`pictureinpicture`, 100).
- Where the `NSView` comes from in each case:
  - The macosx GUI provides it via its `vout window` submodule.
  - libvlc/VLCKit: `libvlc_media_player_set_nsobject()` (`lib/media_player.c:1288`) sets `drawable-nsobject`. `modules/video_output/window_macosx.m:757` (`EmbedOpen`, score 10) then puts a content view into that `NSView`.
  - Qt: `modules/gui/qt/maininterface/compositor_platform.cpp:148-152` passes `m_videoWindow->winId()` as `VLC_WINDOW_TYPE_NSOBJECT`.
- **Conclusion:** A, B, C and D all render video through the same zero-copy `CVPixelBuffer` → `AVSampleBufferDisplayLayer` path. Any performance difference comes from the UI layer only:
  - idle redraws;
  - translucent materials over video;
  - how often the time label and seek bar update;
  - app memory and footprint (Qt adds the most).

### 1.4 What libvlc / VLCKit 4 can and cannot reach

**Public libvlc 4 headers** (`include/vlc/`):
- `libvlc.h`, `libvlc_media.h`, `libvlc_media_player.h` (163 exported functions), `libvlc_media_list*.h`
- `libvlc_media_discoverer.h`, `libvlc_renderer_discoverer.h`, `libvlc_dialog.h`
- `libvlc_parser.h` (parse plus `libvlc_parser_task_new_thumbnail`)
- `libvlc_picture.h`
- `libvlc_downloader.h` (new in 2026)

There is **no** media library, config, variables, modules, extensions, addons or hotkeys API.

Also relevant:
- `src/libvlc-module.c:2867`: `ignore-config` defaults to **true**, so a libvlc app doesn't even read `vlcrc` unless it passes `--no-ignore-config`, as `darwinvlc.m` does.
- `libvlccore` (`src/libvlccore.sym`) does export the internal APIs: `config_Get*/Put*`, `config_SaveConfigFile`, `module_list_get`, `module_config_get`, `vlc_config_cat_*`, `var_*`, 130 `vlc_player_*`, 44 `vlc_playlist_*`, 27 `vlc_ml_*`, `vlc_extension_VaControl`, `vlc_dialog_*`. They can only be used in-process with VLC's internal headers. That is exactly what an interface plugin (A/D) does.

| Redesign feature | In-tree (A/B/D) | libvlc / VLCKit 4 (C) |
|---|---|---|
| Play/pause/seek/rate/volume, chapters, titles, programs, A-B loop, record, snapshot | `vlc_player_*` | Yes (`libvlc_media_player_*`, `VLCMediaPlayer`) |
| Audio/sub/video track lists, multi-sub, delays, sub text scale | Yes | Yes (`libvlc_media_player_get_tracklist`, `select_tracks`, `libvlc_audio_set_delay`, `libvlc_video_set_spu_delay`, `libvlc_video_set_spu_text_scale`) |
| Audio output device list and switch (redesign's audio menu) | Yes | Yes (`libvlc_audio_output_device_enum/set`) |
| Equalizer presets/bands | Yes | Yes (`libvlc_audio_equalizer_*`, `VLCAudioEqualizer`) |
| Video adjust (brightness etc.), aspect, crop, deinterlace, logo/marquee | Yes | Yes |
| Arbitrary video/audio filter chains (flip/rotate/sharpen/…) live | Yes (`video-filter` vars + `vout` restart, as `coreinteraction/VLCVideoFilterHelper.m` does) | **No live API.** Only `libvlc_new` args or `libvlc_media_add_option(":video-filter=…")` per media. Prebuilt VLCKit strips `sharpen, grain, posterize, mirror, wave, sepia, invert, gaussianblur, …` (`extras/package/apple/build.conf:193-250`) |
| Live subtitle styling (colour, outline, opacity, shadow) | Yes. `freetype` re-reads `var_Inherit*("freetype-color", …)` on every render (`modules/text_renderer/freetype/freetype.c:715-756`), so `var_Set` on the player/instance works live. Font face is read only at open (line 1301) | **No** (no var API). Only text scale |
| Default subtitle/audio language (`sub-language`, `audio-language`), per-show presets | `config_PutPsz` + player vars | Only at `libvlc_new()` time or per media (`:sub-language=…`). Presets must live in the app |
| **Full preference tree** (the redesign's re-categorised Settings with "advanced" per category) | Yes. `module_list_get` + `module_config_get` + `vlc_config_cat_*` + `config_Put*` + `config_SaveConfigFile`, exactly as `preferences/prefs.m` does | **No.** Workaround: generate a JSON schema of all options at build time (a small tool linked against libvlccore, or parse `vlc -H --advanced`), write `vlcrc` yourself, and restart the libvlc instance. Fragile, and many options then can't be applied live |
| Hotkeys (about 100 actions, OSD feedback, configurable) | Yes. Core `hotkeys` module via `"key-pressed"` plus `vlc_actions` | **No.** VLCKit removes the `hotkeys` module (`build.conf` removal list). You reimplement every action and the OSD yourself |
| OSD messages ("show the shortcut you just pressed") | `vlc_player_osd_Message` | Marquee hack, or draw your own overlay (fine for a custom UI) |
| Media library (videos/music/albums/artists/genres, history/continue-watching, playlists, folders, favorites) | Yes, `vlc_medialibrary` (`VLCLibraryModel`) | **No libvlc API.** Prebuilt VLCKit has `--disable-medialibrary`. You'd need VideoLAN's separate VLCMediaLibraryKit (used by VLC-iOS; not in this workspace) or your own DB |
| Network browsing / UPnP / SMB / services discovery | `vlc_media_source` | Partly (`libvlc_media_discoverer`, `VLCMediaDiscoverer`) |
| Chromecast/renderers | Yes | Yes (`libvlc_renderer_discoverer`) |
| Login/question/progress dialogs | Yes | Yes (`libvlc_dialog_*`, `VLCDialogProvider`) |
| Lua extensions (VLSub = OpenSubtitles download), Lua playlist scripts (e.g. YouTube), addons manager | Yes (`vlc_extensions.h`, `vlc_addons.h`) | **No.** Prebuilt VLCKit uses `--disable-lua` (`build.conf:59,133`). Subtitle download must be written natively against the OpenSubtitles REST API |
| Seek-bar thumbnails | `vlc_preparser` thumbnailer | `libvlc_parser_task_new_thumbnail` |
| Convert/stream | sout chain | `VLCTranscoder`/`VLCStreamSession` (VLCKit) |

**Needs work in any option (not exposed by the engine):**
- reverse playback (no negative-rate support in `vlc_player`);
- an audio-waveform seek bar (needs a separate decode pass);
- a subtitle timeline (no cue-list API, so parse SRT/ASS/VTT in the UI for external subs);
- sleep timer, folder/playlist-wide subtitle matching rules, per-show presets (app-level logic).

### 1.5 VLCKit 4.0 status (`(VLCKit clone, removed: https://github.com/videolan/vlckit)`)

- Still alpha. Weekly-to-monthly tags: `4.0.0a20` (2026-07-06) through `4.0.0-a25` (2026-09-30), 50 commits in 2026. `NEWS` "Version 4.0.0" lists the new track API, PiP on macOS, a new clock, and "fully exposed libvlc C API".
- Distributed as a binary xcframework:
  - SPM: `Package.swift` → `https://download.videolan.org/cocoapods/unstable/VLCKit-4.0-20260929-1631.zip`
  - CocoaPods: `Packaging/podspecs/VLCKit.podspec` (`4.0.0a25`, LGPL-2.1)
  - Minimum macOS 10.13.
- Pins libvlc `005e69e67` (2026-09-29; `compileAndBuildVLCKit.sh:33`), 164 commits behind current master, plus 12 patches in `libvlc/patches/`.
- Built through `vlc/extras/package/apple/build.sh` with `build.conf`. It disables GPL contribs, Lua, medialibrary, DVD/Blu-ray, VLM, NLS and the addon manager, and removes about 60 modules. You can rebuild it against your own VLC tree (`compileAndBuildVLCKit.sh -x -e <vlc path>`) after editing `build.conf`.
- `VLCVideoView` (an `NSView`) and `VLCVideoLayer` (a `CALayer`) just call `libvlc_media_player_set_nsobject` (`Sources/Playback/VLCMediaPlayer.m:849-854`).
- LePips/VLCUI is a 1.7k-line SwiftUI wrapper (`NSViewRepresentable` around a drawable). Its README marks it **unmaintained** and it imports VLCKit 3-era module names (`MobileVLCKit`/`TVVLCKit`). Use it as a reference only.

### 1.6 Qt/QML on macOS (option B)

- Off by default:
  - `configure.ac:4264-4269`: `AS_IF([test "${SYS}" = "darwin"], [enable_qt="no"])`.
  - `contrib/src/qt/rules.mak:7-8`: `ifdef HAVE_MACOSX  #PKGS += qt`, so the contribs never build Qt for macOS.
  - The macOS CI jobs (`extras/ci/gitlab-ci.yml:498-562`) build only the native GUI.
- Code paths do exist:
  - `compositor_platform.cpp:66-69` accepts the `cocoa` platform;
  - `compositor.cpp:63` registers "platform" for `__APPLE__`;
  - 2024-26 commits: "qt: setup startup for Darwin", "qt: set Basic style on macOS for Qt Quick Controls", "qt: meson: fix path to Darwin frameworks", "meson: fix build on darwin when qt can't be found".
  - Meson's `qt` option is `auto` (`meson_options.txt:153`), so `meson setup` with a Homebrew/official Qt ≥ 6.2 builds it.
- The macOS compositor uses a root `QWindow` holding a child video `QWindow` (an `NSView`) and a transparent, frameless `QQuickView` on top (`compositor_platform.cpp:75-118`). Video goes through the same `AVSampleBufferDisplayLayer` path. The UI is a second Metal (RHI) surface composited above it.
- The community forks are Qt-only. In this clone's remotes the redesign branches touch only `modules/gui/qt`, for example:
  - `fork-floklein/feat/redesign`: 451 qt files
  - `Geckostya…/redesign/stage1`: 341
  - `fork-Pyr0zen/redesign`: 337
  - `fork-dsojevic/juxtopposed-redesign`: 43
  - `fork-Hamido212/redesign`: 124

  None touches `modules/gui/macosx`. The one exception is `TheFenrisLycaon_vlc/heimdall/rename` (625 macosx files), which is a scripted VLC→"Heimdall" rebrand, not a redesign. It is relevant only as a precedent for trademark-driven renaming.

### 1.7 Upstream churn (merge-risk evidence; `git log --since=2026-01-01`)

| Path | Commits in 2026 |
|---|---|
| `modules/gui/macosx` | **634** (658 in 2025). Authors: Claudio Cambra 442, Serhii Bykov 113, Felix Paul Kühne 39 |
| `modules/gui/qt` | 789 |
| Hottest macosx areas (file-touches) | `library/` 835, `UI/` (XIBs) 178, `windows/` 91, `views/` 64, `Makefile.am` 45 |
| `include/vlc` (public libvlc) | 53 |
| `include/vlc_player.h` / `vlc_playlist.h` / `vlc_media_library.h` / `vlc_configuration.h` / `vlc_modules.h` | 5 / 0 / 2 / 0 / 0 |
| Glue files a new module touches: `modules/gui/Makefile.am`, `extras/package/macosx/package.mak`, `share/Info.plist.in`, `extras/package/macosx/build.sh`, `configure.ac` | 2, 6, 4, 4, 71 (but only one `AC_ARG_ENABLE` line is needed) |

The internal player/playlist/config/module APIs are nearly frozen. The macOS UI code is the most volatile part of the tree.

Upstream's design direction also **diverges** from the Juxtopposed design:
- Upstream: centered play stack (`VLCMainVideoViewController.h: centralControlsStackView`), Liquid Glass (`NSGlassEffectView`), hero views.
- Juxtopposed: left-aligned small play button, thick seek bar, cone volume, flat neutral greys, custom-drawn rectangular-but-rounded controls.

So upstream's macOS changes will keep landing in the exact places a restyle would rewrite.

---

## 2. The four options

### A) Fork VLC and restyle/rewrite `modules/gui/macosx` in place

- **Stack:** ObjC/AppKit, XIBs, autotools. Swift is not supported by the build. You'd add custom `swiftc` rules to `Makefile.am`, the same way it already invokes `actool`/`ibtool`/`metal`. Swift↔ObjC interop is possible: ObjC→Swift through a bridging header that must not pull in `vlc_common.h` macros/atomics directly; Swift→ObjC through the generated `-Swift.h`.
- **What you'd change:** `VLCMainVideoView.xib`, `VLCLibraryWindow.xib`, `controlsbar/*`, `views/*` (sliders), `library/*` (navigation, segments), `panels/*` (rebuilt as sidebar tabs), `preferences/*` (re-categorised). The redesign is a structural rewrite, not a theme:
  - a new top bar with title/library button/fullscreen/PiP;
  - a 4-tab right sidebar replacing 4 floating panels;
  - a split Open dialog;
  - settings reorganised into 10+ categories, each with basic and advanced sections;
  - a layout customiser;
  - onboarding.
- **Performance:** identical to stock.
- **Upstream story: poor.**
  - About 50 upstream commits a month land in the same files. Hand-merging XIB XML is error-prone.
  - Every upstream refactor of the library caches, data sources or controls bar becomes a conflict.
  - Expect 2–5 days of rebase work a month, rising over time. Realistically you'd freeze on a VLC 4.0 tag and cherry-pick.
- **Effort (estimate):** 50–70 person-weeks for the full scope, plus ongoing rebase cost. You save some by reusing existing panels' logic and lose some by working around XIB/IBOutlet coupling.
- **Licence:** GPLv2+ (derivative of a GPL module).
- **When it makes sense:** only if the goal is to **upstream** the redesign as VLC's official Mac UI. That is a social and design negotiation with VideoLAN, not a fork.

### B) VLC 4 Qt/QML interface on macOS, reusing a community QML fork

- **Stack:** C++/QML (Qt 6 ≥ 6.2), Meson or autotools with `--enable-qt` forced; Qt frameworks bundled into `VLC.app`.
- **Buildability:** yes with Meson plus an external Qt 6. It is not shipped or tested by VideoLAN on macOS. You'd need to:
  - re-enable `PKGS += qt` (plus qtdeclarative, qtshadertools, qtsvg) for macOS contribs, or vendor Qt;
  - bundle and sign about 15–25 Qt frameworks and QML plugins (`macdeployqt`-style);
  - fix macOS-specific bugs yourself: global menu bar, native fullscreen Spaces, trackpad momentum scrolling, Retina text, IME, accessibility, Services, Dock menu, AppleScript and media keys. The native GUI has `os-integration/*` for the last few, and Qt doesn't.
- **Look and feel:** the redesign is fully custom-drawn, so QML can match the visuals well. The *behaviour* won't feel native: window chrome, the menu bar, scroll physics, focus rings and the context menu (the redesign wants a restyled right-click menu, which QML would draw itself). On macOS 26, native apps get Liquid Glass for free and a QML app looks foreign next to them.
- **Performance:** video is the same. The UI is a second Metal surface (QQuickView) composited over the video `NSView`, which costs more GPU/energy when animating than CoreAnimation layers. Expect a larger RAM footprint (+80–150 MB is typical for Qt Quick apps; estimate) and a bundle bigger by about 60–100 MB (estimate).
- **Upstream story:** better than A if the community fork sits on a stable QML component layer. But `modules/gui/qt` churns even more than macosx (789 commits in 2026), and the forks rewrite the same QML files.
- **Effort (estimate):**
  - 4–6 weeks to get a signed, notarised Qt-based macOS bundle building in CI;
  - plus 25–45 weeks to finish and maintain the redesign scope, depending on how complete the chosen fork is (see `02-other-qt-forks.md`);
  - plus ongoing macOS-specific fixes.
- **Licence:** GPLv2+ (the Qt GUI module) plus Qt LGPLv3 (dynamic linking, relinkable).
- **When it makes sense:** if the goal is one cross-platform UI codebase shared with Windows/Linux and Mac polish is secondary.

### C) Separate native Swift/SwiftUI app on VLCKit 4 or libvlc

- **Stack:** Swift 6 / SwiftUI + AppKit, Xcode project, VLCKit xcframework via SPM. Alternatively a custom-built libvlc (`libvlc.dylib` + `libvlccore.dylib` + plugins, built with `extras/package/macosx/build.sh`) used through its C API.
- **Video:** `VLCVideoView` / `libvlc_media_player_set_nsobject(view)` inside an `NSViewRepresentable`. Same vout as stock, so the same performance. SwiftUI overhead stays negligible if:
  - the video `NSView` is never re-created by SwiftUI diffing (keep it in a stable `NSViewRepresentable` with an identity owned by the player model);
  - time/position updates (`libvlc_media_player_watch_time`) update only the seek bar and time label (use the `@Observable` macro with fine-grained properties, not a big `ObservableObject`);
  - full-screen blur materials over playing video are avoided or kept small. The design uses solid dark bars, which is good.
- **Gaps:** section 1.4. Settings tree, media library, live var changes, hotkeys engine, Lua extensions/VLSub, addons. To be complete you'd also need to:
  - build your own VLCKit/libvlc with Lua, medialibrary and GPL contribs re-enabled;
  - use or port VLCMediaLibraryKit (not in this workspace);
  - write a vlcrc schema/writer and restart libvlc on settings changes;
  - write a hotkey engine and a native OpenSubtitles client.

  A stopgap exists: an external app *can* `#include` VLC's internal headers and call exported `libvlccore` symbols, the way `darwinvlc.m` calls `libvlc_InternalAddIntf`. That is unsupported ABI, and at that point you have rebuilt option D without the plugin structure.
- **Upstream story: best.** The public libvlc API is stable (`LIBVLC_ABI_MAJOR=12`, 53 header commits in 2026, mostly additive). You can update VLCKit binaries without touching UI code. But VLCKit 4 is still alpha.
- **Effort (estimate):** the UI work is about the same as D (45–60 weeks), plus 20–30 weeks to rebuild backend features that VLC already has. Total 65–90 person-weeks, with a lower feature ceiling (no extensions, partial settings).
- **Licence:** VLCKit/libvlc are LGPL-2.1+, so the app can be closed source or permissively licensed. A libvlc build with GPL modules (x264, Lua scripts with GPL bits, some filters) makes the distributed combination GPL. Only a pure-LGPL build allows **Mac App Store** distribution, which is impossible for A/B/D because of GPL.
- **When it makes sense:** a "lite" App Store edition, or as a secondary backend for the same SwiftUI package (see D).

### D) Hybrid: a new in-tree interface plugin (`modules/gui/<name>/`) with its own UI code (**recommended**)

**What it is:** a VLC fork that adds one new directory. Upstream's `modules/gui/macosx` is left as is and not shipped in your bundle. The plugin:
- registers `set_capability("interface", 250)`, which beats macosx's 200 (or select it with `--intf=<name>` in `darwinvlc.m`'s argv);
- provides its own `vout window` submodule handing out the player view's `NSView` (`VLC_WINDOW_TYPE_NSOBJECT`);
- has full in-process access to `vlc_player`, `vlc_playlist`, `vlc_medialibrary`, `vlc_media_source`, `config_*`/`module_*`/`vlc_config_cat_*`, `var_*`, `vlc_actions`/the hotkeys module, `vlc_extensions`, `vlc_addons`, `vlc_dialog`, `vlc_renderer_discovery`, `vlc_preparser`.

Precedent: `modules/gui/minimal_macosx/` is a complete 496-line Cocoa interface plugin wired up with about 10 lines in `modules/gui/Makefile.am:24-32` and `configure.ac:4849`.

**Proposed layout:**

```
modules/gui/<name>/
  Makefile.am                 # included from modules/gui/Makefile.am (1 line)
  module.m                    # vlc_module_begin: interface + vout window submodule + own config section
  core/                       # ObjC glue ("facade") – the ONLY code that includes <vlc_*.h>
    JXCore.{h,m}              # owns intf_thread_t, player, playlist, ML handles
    JXPlayerFacade.{h,m}      # Swift-friendly: NS types only, KVO/blocks, no vlc_tick_t in headers
    JXPrefsSchema.{h,m}       # walks module_list_get/module_config_get → NSArray<JXPrefItem>
    JXHotkeys.{h,m}, JXExtensions.{h,m}, JXDialogs.{h,m}, JXLibraryFacade.{h,m}
    reuse/                    # see "reuse strategy" below
  ui/                         # Swift package "JuxtUI" (SwiftUI + AppKit), no VLC headers at all
    Package.swift
    Sources/JuxtUI/{DesignSystem,Player,Sidebar,Library,Settings,Dialogs}/...
    Sources/JuxtUI/Backend/PlayerBackend.swift   # protocols the UI depends on
    Sources/JuxtUIPreview/MockBackend.swift      # mocks for Xcode previews / snapshot tests
  Resources/                  # Assets.xcassets (two icon sets), fonts, Localizable
```

**Swift in the VLC build: how.** Neither autotools nor the macOS meson path supports Swift today. Two workable routes:
1. Recommended. A `Makefile.am` rule runs `xcrun swift build -c release --arch arm64 --arch x86_64 --package-path gui/<name>/ui`, producing a static `libJuxtUI.a` with an `@objc` entry point (`JXUIBootstrap`). It is linked into `lib<name>_plugin.dylib` with:
   - `-L$(xcrun --show-sdk-path)/usr/lib/swift -Wl,-rpath,/usr/lib/swift`
   - `-framework SwiftUI -framework AppKit`

   This is the same pattern `Makefile.am` already uses for `ACTOOL`, `XIB` and `METAL`. Raise the fork's minimum to macOS 14 (for `@Observable`), or 13 at the least.
2. Fallback. Write the UI in ObjC/AppKit with custom-drawn `NSView`s. There is no build risk, but iteration is 2–3× slower for this very custom visual language.

Keep **all** `<vlc_*.h>` includes in ObjC `.m` files. Swift's ClangImporter would otherwise have to digest `vlc_common.h` (macros, `_Generic`, C11 atomics, `config.h` dependence), which is a known pain point.

**Reuse strategy for upstream's macosx model code (so upstream bug fixes still flow):**
- **Compile in place, unmodified.** Add `gui/macosx/playqueue/VLCPlayQueueModel.m`, `library/VLCLibraryModel.m`, `library/VLCLibraryDataTypes.m`, `library/VLCInputItem.m`, `library/VLCLibraryImageCache.m`, `extensions/NSString+Helpers.m`, etc. to your plugin's `_SOURCES` by path. Upstream fixes arrive for free; API breaks show up as compile errors.
- **Shim the singletons.** Those files `#import "main/VLCMain.h"`. Put a `<name>/shim/main/VLCMain.h` earlier on the include path that exposes the same selectors (`sharedInstance`, `playQueueController`, `libraryController`, `p_intf`) backed by `JXCore`.
- **Vendor with tracking** for files that import UI classes, such as `VLCPlayerController.m` (imports `VLCMainVideoViewController.h`) and `VLCHotkeysController.m`. Copy them into `reuse/` and record the upstream commit in a header comment. A `tools/sync-macosx-model.sh` script runs `git diff <recorded>..origin/master -- <paths>` on each upstream merge so you can port relevant fixes.
- **Never ship `libmacosx_plugin.dylib`** in the bundle. Exclude it in `package.mak` or configure with `--disable-macosx` while still compiling the shared sources into your plugin. Otherwise both plugins define the same ObjC classes (`VLCPlayerController` etc.), and loading both gives "Class X is implemented in both" undefined behaviour.

**Upstream-touch surface (the whole conflict budget):**

| File | Change |
|---|---|
| `modules/gui/Makefile.am` | `include gui/<name>/Makefile.am` (1 line) |
| `configure.ac` | `AC_ARG_ENABLE([<name>])` plus a darwin check (about 6 lines, copied from `minimal_macosx` at :4849) |
| `extras/package/macosx/package.mak` | copy your NIBs/`Assets.car`, skip macosx's (about 10 lines) |
| `share/Info.plist.in` (or your own plist) | bundle id, name, icon, `SUFeedURL`, `SUPublicEDKey`, `LSMinimumSystemVersion` |
| `extras/package/macosx/configure.sh` | `--enable-<name> --disable-macosx` (optional) |

Each of these changes 2–6 times a year upstream (section 1.7), so conflicts are trivial. The internal headers you code against changed 0–5 times in 2026.

**Performance:**
- Same vout as stock.
- Hotkeys go through the core `hotkeys` module, so they are identical to stock including OSD.
- The library uses the same `medialibrary` engine and thumbnailer.
- Keep SwiftUI work off the hot path:
  - throttle the time label to 4–10 Hz; use `vlc_player` timer callbacks (`vlc_player_AddTimer`) rather than polling;
  - use `NSTableView`/`NSCollectionView` via representables for libraries with more than 5k items if `LazyVGrid` stutters;
  - host the video `NSView` as the window's base layer, with SwiftUI chrome as sibling layer-backed views above it, not inside a SwiftUI `ZStack` that re-lays out on every tick.

**Effort (estimate, one senior macOS engineer plus design support; for the full transcript scope):**

| Work package | Person-weeks |
|---|---|
| Fork, build/CI, plugin skeleton, Swift-in-autotools, signing/notarisation, Sparkle feed | 3–4 |
| Design system: tokens, two icon sets (two-tone menu icons and mono UI icons), components (thick seek bar with thumbnail preview, cone volume slider, toggle with ON/OFF label, dropdown, segmented tabs with orange underline, info-icon tooltips), light/dark mode plus accent colour | 4–5 |
| Player window: full-size content, top bar (title as library button, fullscreen, PiP), bottom bar, hover-reveal/autohide in window and fullscreen, right-click menu (custom `NSPanel`, since `NSMenu` can't take this styling), "hide UI" mode, OSD showing the pressed shortcut, continue-watching prompt near the centre | 5–7 |
| Subtitle/audio quick menus (tracks, audio output device), video-track tab | 2 |
| Right sidebar, 4 tabs: subtitles (delay sliders, font, size relative/precise, outline, position, default track/language, presets per show); audio (tracks, delay, EQ with friendly presets, filters); video (filters with previews, flip/rotate/zoom/aspect/crop/deinterlace); playback (speed, sleep timer, subtitle timeline toggle, waveform toggle, metadata; reverse = research item) | 6–8 |
| Subtitle import dialog (file/folder/playlist scope, auto-match plus manual mapping saved for future episodes, OpenSubtitles via native API or VLSub), subtitle timeline editor | 5–7 |
| Queue panel, compact in-player library sidebar, drag-to-queue, bookmarks and chapters in the sidebar | 3–4 |
| Library: home (recent, continue watching), videos with folder grouping and address bar, music (songs/albums/artists/genres) with big-cover audio player and waveform seek, network streams (M3U/IPTV URL import), playlists, pins, recents, sort/view/search incl. watched/unwatched | 9–12 |
| Split Open dialogs (file, directory, network, capture, clipboard, recent, convert, stream) | 3–4 |
| Settings: map every `module_config_get` item into the 10+ new categories (General, Interface, Privacy, Controls, Playback, Video, Audio, Subtitles/OSD, Library, Network, Performance, Recording, Extensions) with basic and advanced sections, human-language dropdowns, info icons; hotkeys dialog; plugins/extensions/addons separation | 7–10 |
| Customisation drag-and-drop layout editor, profiles, onboarding (theme and shortcuts) | 4–6 |
| Localisation plumbing, accessibility, performance pass, QA, regression versus stock | 4–6 |
| **Total** | **55–75** (MVP below ≈ 16–22) |

The OpenSubtitles API needs your own API key and user agent.

**Upstream story:**
- Monthly `git merge origin/master` with conflicts only in the glue files.
- CI compiles the reused macosx model sources, so upstream API changes show up immediately.
- The sync script surfaces fixes in vendored files.
- You inherit all engine, codec and security fixes, which is the main reason to stay in-tree.

**Licence:** GPLv2+ for the plugin and the distributed app, because you reuse GPL macosx code and ship GPL modules. Publish the source, which matches Juxtopposed's "open source" intent. No Mac App Store.

**Optional bonus:** because `JuxtUI` only knows the `PlayerBackend` protocols, you can later add a `VLCKitBackend` (option C) for an App Store "lite" build that shares about 70% of the UI. Features without a backend (settings tree, extensions) are hidden by capability flags.

---

## 3. Side-by-side comparison

| | A: restyle macosx | B: Qt/QML on Mac | C: SwiftUI app on VLCKit/libvlc | D: new in-tree plugin (Swift UI + ObjC glue) |
|---|---|---|---|---|
| Language | ObjC/AppKit/XIB | C++/QML | Swift/SwiftUI/AppKit | Swift/SwiftUI/AppKit UI + ObjC core glue |
| Visual 1:1 feasibility | Medium (fighting XIBs/Glass) | High (QML custom drawing) | High | High |
| Mac-native behaviour | High | **Low** | High | High |
| Feature parity with VLC (settings tree, ML, extensions, hotkeys) | Full | Full | **Partial** | Full |
| Video perf | Stock | Stock video, heavier UI | Stock | Stock |
| Upstream merges | **Painful** (634 commits a year in the same files) | Medium-painful (Qt churn 789 a year, fork churn) | Easy (public API), but VLCKit is alpha | **Easy** (about 5 glue files, internal APIs nearly frozen) |
| Build complexity | Stock | Plus Qt for Mac (unsupported) | Lowest (SPM binary) unless you need a custom VLCKit | Stock plus a Swift rule |
| Effort, full scope (pw, est.) | 50–70 + rebase tax | 30–50 + Mac-fix tax | 65–90 | 55–75 |
| Licence | GPLv2+ | GPLv2+ & Qt LGPLv3 | LGPL possible → App Store possible | GPLv2+ |
| Upstreamable to VideoLAN later | Directly | Partially (QML) | No | Possibly as an alternative intf |

---

## 4. Building, signing and distribution on Apple Silicon

**Toolchain:** Xcode 26 (CI uses the `macos-xcode26` runner tag, `gitlab-ci.yml:535`). `NEWS` lists the Metal toolchain component as a requirement. VLC's `extras/tools` bootstraps autotools, meson, etc.

**Build command:**
```
extras/package/macosx/build.sh -a arm64 -j$(sysctl -n hw.ncpu)
```
`-c` builds contribs from source; `-x` uses `--enable-extra-checks`.
- By default it tries `make prebuilt`, which downloads `https://download.videolan.org/pub/videolan/contrib/$(HOST)/vlc-contrib-$(HOST)-latest.tar.zst` (`contrib/src/main.mak:764`).
- CI pins the exact tarball through `extras/ci/get-contrib-sha.sh`: `https://artifacts.videolan.org/vlc/<job>/vlc-contrib-<triplet>-<sha>.tar.zst` (`gitlab-ci.yml:7-8`). Use the same SHA logic so your fork's contrib tree matches.

**Build times (estimates on an M2/M3 Pro-class Mac, not measured here):**
- prebuilt contribs: 2–5 min download;
- VLC core plus all modules: about 10–20 min clean;
- rebuilding your GUI plugin: under 1 min;
- contribs from source: about 1–2.5 h;
- a VLCKit macOS-only build (`compileAndBuildVLCKit.sh -x -a aarch64`) on top: about 30–60 min.

For a universal binary, build arm64 and x86_64 separately and `lipo`. The macOS CI already builds both.

**Prebuilt VLCKit (only for C or a "lite" backend):** SPM `https://download.videolan.org/cocoapods/unstable/VLCKit-4.0-20260929-1631.zip` or the CocoaPods `VLCKit 4.0.0a25`. Remember its reduced module set.

**Signing and notarisation:**
- `extras/package/macosx/codesign.sh` signs every dylib and plugin with `--options runtime --entitlements vlc-hardening.entitlements`. Those entitlements are `allow-jit`, `disable-library-validation`, `audio-input`, `camera` and `apple-events`.
- Reuse the script with your own Developer ID, then `xcrun notarytool submit --wait` and `xcrun stapler staple` on the DMG (`extras/package/macosx/dmg/`).
- Change the bundle id from `org.videolan.vlc` so you don't clash with an installed VLC's prefs or Sparkle.
- `vlcrc` lives under the VLC config dir (`CONFIG_FILE "vlcrc"`, `src/config/configuration.h:83`). Decide deliberately whether to share it with stock VLC or isolate it, for example with `--config=<path>` (`src/libvlc-module.c:2878`) in `darwinvlc.m`'s argv.

**Updates:** host your own Sparkle appcast and EdDSA key, and replace `SUFeedURL`/`SUPublicEDKey` in `share/Info.plist.in:60-65`. Also disable or repoint VLC's own update check (`--disable-update-check` at configure time) so users are never offered VideoLAN's build.

**Trademark:**
- "VLC" and the cone are VideoLAN trademarks. VideoLAN's legal page allows forks of the code but not presenting them as the official VLC.
- Ship under a different product name ("<Name>, powered by VLC"), a distinct bundle id, and a modified icon. Ask VideoLAN (Jean-Baptiste Kempf engaged with Juxtopposed in the video) before using the cone or the "VLC" name.
- The `TheFenrisLycaon_vlc/heimdall/rename` branch shows the community already planning scripted rebrands.

---

## 5. Recommendation and phased plan

**Go with D.** Fork VLC master (or VLC 4.0 once tagged). Add `modules/gui/<name>/` with an ObjC core facade plus a Swift/SwiftUI `JuxtUI` package. Leave the engine and `modules/gui/macosx` untouched and unshipped. Merge upstream monthly.

**Phase 0: foundations (3–4 pw)**
- Fork, CI (GitHub Actions on a macOS 15/26 arm64 runner using prebuilt contribs), and the plugin skeleton. Start from `minimal_macosx` and register an interface with score 250 plus a vout-window submodule.
- The Swift build rule, then a signed and notarised DMG with your own bundle id and Sparkle feed.
- The JuxtUI package with `PlayerBackend` protocols and a mock backend, so all UI work happens in Xcode previews and snapshot tests without building VLC.

**Phase 1: MVP, the "watch a video" experience (about 13–18 pw)**
1. Player window: borderless/full-size-content `NSWindow`, video `NSView` as the base layer.
2. Bottom bar: left play button with prev/next around it; thick seek bar with hover time and thumbnail preview (`vlc_preparser` thumbnailer); time; on the right the queue, subtitle, audio, fullscreen and settings buttons; cone volume slider.
3. Top bar: menu button, title (clickable, opens the library), PiP and fullscreen. Hover-reveal with immediate hide in both windowed and fullscreen modes.
4. Subtitle and audio popovers: track lists, plus audio output device in the audio popover (via `vlc_player`/aout).
5. Right-click menu, restyled, with "hide UI".
6. Right sidebar, 4 tabs (Subtitles, Audio, Video, Playback), wired to player vars and config. Includes live subtitle style via `var_Set` and default languages via `config_PutPsz`. Presets are stored per folder or show in your own store.
7. Hotkeys through the core module, plus an OSD showing the key.
8. Queue panel with drag-and-drop.

Exit criteria:
- pixel-diff against keyframes `02-…`, `03-…`, `04-…`, `05-…` and `07-…` within tolerance;
- CPU/GPU/energy within ±5% of stock VLC on a 4K HEVC and a 1080p H.264 sample (Instruments: Energy Log, Core Animation FPS).

**Phase 2: Library (about 14–18 pw)**
- The compact in-player library sidebar, then the full library: home/continue watching, videos with folder address bar, music (songs/albums/artists/genres), network streams with M3U import, playlists, pins and recents.
- Sort/view/search with watched/unwatched, built on reused `VLCLibraryModel`/`VLCLibraryDataTypes` and `vlc_media_source`.
- Split Open dialogs, the subtitle import dialog with folder/playlist matching, and OpenSubtitles.
- Bookmarks and chapters in the sidebar.

**Phase 3: Settings and customisation (about 15–20 pw)**
- `JXPrefsSchema` walks the full config tree. A checked-in mapping file (`settings-map.yaml`: module/option → new category, basic/advanced, human label, enum labels for numeric options such as `sub-autodetect-fuzzy`) drives the SwiftUI settings.
- A unit test fails CI when upstream adds an option that isn't mapped, which keeps future VLC updates honest.
- Hotkeys dialog; extensions/addons/plugins split; theme (light/dark) and accent colour; layout customiser and profiles; onboarding.

**Research spikes, time-boxed, in parallel:**
- waveform seek bar (separate audio decode pass via a second `vlc_preparser` or AVFoundation for common formats);
- subtitle timeline (parse external SRT/ASS/VTT in the UI);
- reverse playback (likely out of scope, since the engine doesn't support it).

---

## 6. What the AGENTS.md "design bible" project should contain

Put it at the fork root (`AGENTS.md`) with linked files in `design/`. It should be authoritative for both humans and coding agents.

1. **Scope and non-goals.**
   - Never modify the engine: `src/`, `lib/`, `modules/` except `modules/gui/<name>/`.
   - Never modify `modules/gui/macosx/`.
   - The whitelist of upstream glue files (section 2D table) is the only exception.
   - Feature list with transcript timestamps: `research/video/transcript.txt` lines `[1:00]`–`[20:30]`.
2. **Architecture rules.**
   - Only `core/*.m` may include `<vlc_*.h>`.
   - Swift sees NS/Swift types only.
   - The UI depends on `PlayerBackend`/`LibraryBackend`/`PrefsBackend` protocols.
   - All main-thread hops are explicit, because `vlc_player` callbacks arrive on core threads.
   - Lock rules: `vlc_player_Lock` is never held across UI calls.
   - List of reused upstream files (in place, shimmed, vendored at commit X) and the sync procedure.
3. **Design tokens** (`design/tokens.json`, generated into Swift and the asset catalog):
   - neutrals and black backgrounds, VLC orange accent (user-overridable), semantic roles (surface, surface-raised, track-empty, track-fill-dim, track-fill, text-primary/secondary/disabled);
   - light and dark values; corner radii ("rectangular but less sharp", for example 4/6/10 pt); spacing scale; type scale (font family, weights, tabular digits for times); stroke widths; shadow (mostly none); motion (hover-reveal delay, hide delay, durations, easing).
   - Sample the colours from frames such as `frames/02-control-bar-seekbar-volume/03m29.34s.jpg` (1920×1080) and `07-…/09m12.97s.jpg`.
4. **Iconography.** Two sets: two-tone grey/orange "menu" icons (non-clickable, in menus) and monochrome UI icons. Specify grid, stroke, naming, SF Symbols fallback policy (none if 1:1 is the goal), and source SVGs in `design/icons/`.
5. **Component specs with reference crops.**
   - thick seek bar (dimensions, hover preview card, chapter ticks, waveform variant);
   - cone volume slider;
   - play button size;
   - toggle with ON/OFF label;
   - dropdown;
   - slider with tick labels (speed 0.25–2);
   - tab bar with orange underline;
   - sidebar section;
   - info-icon tooltip;
   - popover track list;
   - context menu;
   - OSD toast;
   - dialogs.

   Each spec states every state (rest, hover, pressed, focused, disabled, dragging), its size, and the keyframe it comes from.
6. **Screen inventory.** One page per screen (player idle, playing, hover, fullscreen, audio-only, each sidebar tab, popovers, library views, open dialogs, settings categories, hotkeys, customiser, onboarding). Each page lists the frame paths (`research/video/frames/NN-…/MMmSS.ss.jpg`), the layout grid, and the behaviour→backend mapping (which `vlc_player_*` / `config` key / `vlc_ml_*` call).
7. **Settings map** (`design/settings-map.yaml`): every VLC option mapped to its new category, its basic/advanced placement and its human wording, with enum labels replacing magic numbers. The CI check is described in Phase 3.
8. **Interaction rules.**
   - Hover zones and timings; keyboard shortcuts table; drag-and-drop targets.
   - Right-click menu contents; what the native macOS menu bar keeps (HIG-required menus: App, File, Edit, View, Playback, Window, Help), versus the in-window menu button.
   - Native fullscreen versus in-window "hide UI"; PiP.
9. **Performance budgets and how to measure them.** Idle CPU while playing, under 1% above stock. No SwiftUI body re-evaluation outside the seek bar/time label on time ticks. 120 Hz hover animations. Startup time. Memory. Use the Instruments templates with fixed sample media.
10. **Verification.**
    - Snapshot tests: SwiftUI views rendered at 1920×1080 with the mock backend and compared to cropped keyframes, with tolerance thresholds.
    - Functional smoke tests: play, seek, track switch, sidebar settings persistence.
    - An upstream-merge checklist.
11. **Branding and licence.** Product name, bundle id, icon rules (cone usage pending VideoLAN approval), GPLv2+ headers in new files, attribution to Juxtopposed for the design, OpenSubtitles API key handling (never commit it).
12. **Open questions log.** Reverse playback, waveform source, per-show preset storage (`vlc_ml` labels or own SQLite), and whether to keep a `VLCKitBackend` lite target.
