# Architecture: the native macOS redesign

Implementation map, 2026-10-15. This document describes the checked-in module;
requirements and unverified acceptance checks are called out separately. The
original design study is available in Git at `3bbac3cb63:redesign/docs/ARCHITECTURE.md`.
The engine base is `upstream-base-2026-10-14` (`4ca4eb0c3e`).

## 0. Boundaries

`modules/gui/macosx_redesign/` implements the interface, video-window provider,
Swift models, adapters, gallery and local build tools. `redesign/` contains its
specification and evidence. The engine, codecs, outputs, and stock macOS GUI are
upstream code. The three build integration points are listed in §6.

The plugin is `libmacosx_redesign_plugin.dylib`, selected with
`--intf macosx_redesign` (shortcut `mxr`). Its interface score is220 and its
video-window score is150. The build disables the stock macOS interface; the
packaged app rejects a second stock GUI plugin. The minimum interface OS is
macOS14; VLC and contribs retain their upstream deployment targets.

Engine corrections from D020 are optional patches under
`redesign/patches/engine/`. D031 applies them only to a separate source copy when
`MXR_ENGINE_PATCHES=1`; ordinary builds leave `src/`, `lib/` and `include/` unchanged.

## 1. Identity and resources

The installed development app is `/Applications/VLC Redesign.app`, identity
`org.example.vlc-redesign.codex`. The personal `/Applications/VLC.app` must never
be launched, replaced, or used for data. VLC's Darwin directories derive from the
running bundle ID: preferences, media-library data and caches are therefore
separate. A build-tree launcher can use the stock pseudo-bundle: do not use it
for a user-data smoke test.

`tools/app-bundle-hook.sh` receives four arguments: app, build directory, bundle
ID and app name. It validates the GUI plugin/resources, installs the own icon,
rewrites identity/minimum OS, and removes stock nib and update-feed keys.
`tools/install-app.sh` is the supported build/install entry point. Resource
lookup in the plugin disables `Bundle.module` fallback and reads the packaged
`MacOSXRedesign_MXRCore.bundle` and `MacOSXRedesign_MXRDesign.bundle`.

## 2. Layers

```
VLC engine (C APIs; upstream)
    │
module/*.m, module/bridge/*.m     owns callbacks, locks and workers
    │ MXRBridgeAPI headers (Foundation/AppKit/CoreGraphics; no VLC headers)
MXRVLCBackend                    adapts snapshots/commands to Core protocols
    │
MXRCore                          values, models, stores, commands, clock
    │
MXRDesign + MXRUI                 tokens, controls, window content
    ├── MXRPlugin                AppKit lifecycle, menus, video host, OS services
    └── MXRGalleryCatalog        MockBackend + same UI, offscreen verification
```

### 2.1 Concrete files

All following paths are relative to `modules/gui/macosx_redesign/`.

| Responsibility | Implementation |
|---|---|
| VLC registration/bootstrap/window ops | `module/module.c`, `MXRIntf.m`, `MXRVoutWindow.m` |
| Interface lifetime/logging | `module/bridge/MXRInterfaceBridge.m` |
| Player timer/listener bridge | `module/bridge/MXRPlayerBridge.m` |
| Service snapshots, settings, hotkeys, queue | `module/bridge/MXRServicesBridge.m` |
| Media library, import, playlists | `module/bridge/MXRLibraryServices.m` |
| Core dialogs | `module/bridge/MXRDialogServices.m` |
| Subtitle cues and thumbnails | `module/bridge/MXRSubtitleCueServices.m`, `MXRThumbnailServices.m` |
| Output and extensions | `module/bridge/MXRMediaServices.m` |
| Effects and audio preferences | `module/bridge/MXREffectsServices.m`, `MXRAudioServices.m`, `MXRAudioPreferenceServices.m` |
| Discovery and PiP | `module/bridge/MXRDiscoveryServices.m`, `MXRPlatformServices.m` |
| Public Objective-C boundary | `Sources/MXRBridgeAPI/include/` |
| Session and adapters | `Sources/MXRVLCBackend/` |
| Application assembly/state | `Sources/MXRCore/App/`, `Models/`, `Stores/`, `Backends/`, `Values/` |
| Actual AppKit lifecycle/menus/video host | `Sources/MXRPlugin/` |
| UI and design system | `Sources/MXRUI/`, `Sources/MXRDesign/` |
| Mock and rendering tools | `Sources/MXRMockBackend/`, `MXRGalleryCatalog/`, `MXRGallery/`, `MXRSnapshot/` |

There is no `module/shim`, `module/vendor`, `MXRCore.m`, `MXRConfigBridge.m`, or
`sync-upstream-model.sh`. Those were proposed in the initial study and were never
implemented. The bridge calls VLC's C APIs directly (§4).

### 2.2 Protocol and wire boundary

`MXRCore/Backends` defines `@MainActor` protocols for player/clock, queue,
library, settings, shortcuts, output, extensions, sources, thumbnails and OSD.
The UI depends on those protocols. `MXRMockBackend` implements them without VLC.

The native wire uses typed service, command and request names in
`MXRServicesBridge.h` and `VLCServiceTransport`, backed by shared `MXRBridgeKeys`
constants. The explicit `settingOption(_:)` factory handles dynamic settings
services. Native payloads remain Foundation dictionaries; field/value DTOs are
not yet fully typed. Do not describe this as a fully typed per-service API.
Snapshot keys represent actual missing values as unavailable, never invented data.

Core still imports AppKit for shortcut/platform conveniences. Hardware discovery
now crosses a typed Sendable backend API: native enumeration runs off-main,
settings choices load lazily, and mocks provide deterministic fixtures. UI no
longer imports CoreAudio/AVFoundation to enumerate devices. A mock without an
injected quit handler never terminates its host process.

### 2.3 Threading and lifetime rules

1. VLC player/listener callbacks can hold player/playlist locks. Copy/retain the
   payload under that lock, then enqueue to main; never synchronously wait for main.
2. Public bridge sinks/completions run on main (`NS_SWIFT_UI_ACTOR`). Swift models
   are `@MainActor @Observable`; the UI must not receive engine callbacks directly.
3. Commands acquire engine locks only around the relevant C call. Filesystem,
   library queries, decoding, config saves and discovery belong to owned workers.
   `Task {}` on a main-isolated function does not itself move blocking I/O off main.
4. Vout `enable` may synchronously request its native view on main. Main must never
   wait for the vout/decoder while holding player locks. Other window ops enqueue.
5. Size and pointer reports use an owned serial queue. Never call a size report
   inline from `NSView.layout()` into the display lock.
6. Clock interpolation is separate from PlayerModel. Per-frame seek rendering
   must not invalidate or lay out the full SwiftUI window tree.
7. Shutdown detaches Swift sinks/callbacks on main, rejects new requests, cancels
   preparsers and services, then joins accepted workers on the interface thread.
   Every accepted worker must be registered before dispatch; a raw preparser
   pointer must not outlive its owner even before submission. Main remains able to
   service late vout detach callbacks until libvlc finishes.

### 2.4 Startup and shutdown

`MXROpenIntf` schedules setup on the main CFRunLoop and waits for setup completion.
`MXRApplication` routes Quit to `libvlc_Quit`. `MXRInterfaceBridge` owns player and
service bridges. `MXRSwiftStart` assembles `VLCBackends`, `AppModel` and
`MXRAppController`; it disables package-resource fallback, then starts the window.

`MXRSwiftStop` stops the controller and invalidates adapters. `MXRCloseIntf`
detaches services on main, stops the AppKit loop, and calls `finishShutdown` on the
interface thread before returning. Successful construction is not proof of clean
exit; queued-I/O shutdown and cancellation require separate tests.

## 3. Video and window composition

### 3.1 Engine video

Our `vout window` provides a layer-backed `NSView` through
`VLC_WINDOW_TYPE_NSOBJECT`. Upstream sample-buffer display adds its video and
subtitle subviews. Controls are sibling overlays, never children of those display
views. Do not replace the renderer, add opacity/masks to its video layer, or infer
HDR correctness from a static screenshot.

### 3.2 Input and native window

`MXRAppController` owns the real titled, transparent-titlebar,
`fullSizeContentView` window. Its traffic lights are AppKit's controls; the shared
bar is40pt per D022. Fullscreen synchronizes the AppKit delegate and VLC state.
The UI routes ordinary clicks/scroll according to configured actions. Interactive
DVD/menu/filter pointer input must reach `vlc_window_ReportMouse*` separately.

### 3.3 Actual hierarchy and performance boundary

The current shell is one persistent `NSHostingView<MXRAppView>` containing the
video representable, player bars, panels, library, dialogs and overlays (D021).
The original plan for one small hosting view per overlay was not implemented.
It remains a possible optimization, not an existing fact. High-frequency seek
progress must be isolated inside the renderer rather than full-window SwiftUI
state updates. Every performance claim needs visible/hidden playback measurements.

Panels overlay video without shrinking it. Full library and its mini-player use
the retained surface. Hide UI must hide all chrome/metadata interceptors, while
preserving the video. Popup hit testing must correspond to a visible popup.

### 3.4 Fullscreen and PiP

Fullscreen uses native Spaces and vout state; Hide UI is independent. PiP uses
`MXRPictureInPictureController` in `MXRPlatformServices.m`, following the stock
runtime `PIPViewController` route. Its private API is a compatibility risk.
Move/restore the existing surface, validate availability and state, and suppress
redundant now-playing/PiP refreshes. AVKit sample-buffer PiP was considered but is
not this implementation. Hardware HDR/EDR and PiP subtitles require actual tests.

## 4. Upstream code reuse

No stock GUI implementation files are compiled into the plugin. Its native
source list in `Makefile.am` contains our `module/` files. Existing VLC sources
and headers remain reference material and C API providers; there is no shim
substitution of `VLCMain` or reuse-in-place of stock model classes. The stock GUI
stays unchanged and disabled in our build.

## 5. Service semantics

### 5.1 Player and queue

Adapters separate player changes from the interpolated clock. Queue identity is
an occurrence in the current queue, not a media-library ID. Error paths must not
clear an existing queue before validating/allocating replacement items. Per-input
trusted options implement scoped Open behavior without changing global defaults.

### 5.2 Settings, presets and profiles

`settings-map.json5` maps Figma rows to VLC names, control types and apply targets.
Published engine schema determines row availability (D013/D035). Presence in a
schema does not prove a setting reaches its consumer. Check units, queue state,
config vs object variables, existing-player inheritance, save failures, and the
next-input boundary. A next-media preference must not unexpectedly alter current
playback. User data requires a migration path and disk-save error feedback.

VLC's config is authoritative at startup. A saved profile must not replay a full
engine-schema snapshot and overwrite values VLC saved itself; explicit profile
selection applies only intentional profile settings. Presets distinguish an
uncaptured section from an explicit Automatic/reset selection.

### 5.3 Hotkeys and dialogs

App actions use D026/D034 Mac defaults; engine keys retain VLC semantics. Commands
behind a modal must not discard its draft. Edit, Quit and modal Close remain
available. Esc cancels a key recording; actual AppKit event ordering must be
covered separately from directly calling a handler.

### 5.4 Extensions and core dialogs

VLC core login/question/error/progress dialogs use `MXRDialogServices` and Core
models. Lua extension dialogs are a separate API and currently lack a provider.
Do not advertise activation that can silently request an unsupported dialog.
Online catalogs/OpenSubtitles and unsupported codecs remain limited by D014/D036.

### 5.5 Library and sources

Media identity, playlist occurrence identity and displayed row index are distinct.
Filtering/sorting/paging cannot change which stored occurrence Remove affects.
Use native paging where supported; unsupported upstream playlist query parameters
need explicit adapter behavior. Do not infer dates from media IDs.

Discovery should begin when the user browses a relevant source category; avoid
starting all network discovery at app launch. Shutdown must still detach listeners
and join workers before releasing the engine. Network permission text belongs in
the packaged Info.plist, not an engine edit.

### 5.6 Output and subtitle rules

Output jobs use their own playlist/player. Fresh config values must reach each
new job rather than stale inherited player variables. Caller options cannot
replace the trusted generated sout chain. Conversion must finalize its file;
stream keep applies only to compatible successive streaming jobs. Round-trip file
and receiver tests remain necessary after syntax/unit checks.

Saved external subtitle rules must survive Codable migration, preserve multiple
explicit selections, avoid filename-only deduplication, and work independently
of automatic subtitle discovery. Directory enumeration/stat/matching run off main
and return only if the request/media generation is still current.

### 5.7 Seek previews and paused stills

`MXRThumbnailServices` uses VLC's thumbnail input/decoder; software decode is
intentional upstream behavior (thumbnail decoder's get-device returnsNULL).
Changing a hw_dec flag alone cannot create a VideoToolbox device. Requests are
cancellable/coalesced and cached; subtitle timeline and mini-player scrubbing must
also coalesce fast seeks and send one precise final seek.

D031's exact-time raw thumbnail is a mitigation for an upstream paused-seek bug,
not an equivalent processed vout frame. Active filters/subtitles can invalidate
that equivalence; a safe guard must not show a misleading processed frame. Full
paused-seek parity with the unpatched engine remains an explicit limitation.

## 6. Upstream touch budget

| Existing integration file | Purpose |
|---|---|
| `configure.ac` | include our configure fragment |
| `modules/gui/Makefile.am` | include our Automake fragment |
| `extras/package/macosx/package.mak` | conditional redesign packaging hook |

Project instruction/landing files are documented exceptions (see DECISIONS).
Other upstream files, especially `src/`, `lib/`, `include/` and stock GUI, remain
read-only. Engine changes require a decision before any implementation.

## 7. Build and test graph

`Package.swift` is the target graph. `MXRPlugin` is a static product linked into
the Objective-C plugin with force-load. `MXRGallery` and `mxr-snapshot` use the
same Core/UI plus mocks. Tools strip VLC compiler environment before SwiftPM;
resources and compiled asset catalogs are copied to the app.

Automake must account for deleted inputs as well as mtimes, distribute every
required icon/header/helper, and run generator/schema/native contracts. Swift
suites must not register/activate a GUI app in the test runner. Native tests that
need audio/video/network are separately identified, never called a headless pass.
Exact commands and current run evidence are in BUILD and the repair ledger.

## 8. Performance and verification

Budgets remain PHILOSOPHY's: idle under1%CPU, responsive overlays, no playback
frame loss and startup comparable to stock VLC. A successful build or removal of
TimelineView is not a CPU measurement. Compare same media/window/theme/output,
visible vs hidden chrome, scrub and PiP, with repeated bounded samples.

Gallery checks are offscreen component/composition evidence. A titled gallery
window is closer to shipping geometry but still uses mocks. Actual installed
window screenshots, source/binary provenance, input/AX traces and performance
measurements are separate acceptance evidence (D030). Never transfer a gallery
PASS to the real app.

## 9. Remaining acceptance boundaries

Run the package/native/script checks, source-dist/deletion contracts, real output
round trips, modal/data-loss scenarios, playlist search/sort/duplicates, fresh
profile migrations, raw AX/VoiceOver/keyboard navigation, light/contrast states,
actual Figma-window comparisons, sustained playback/scrub and clean shutdown.
Hardware/network/authentication limitations must be named. Tests and audit reports
are evidence for their exact scope, not a whole-product completion certificate.
