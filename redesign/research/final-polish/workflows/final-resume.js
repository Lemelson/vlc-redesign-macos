export const meta = {
  name: 'final-polish-resume',
  description: 'Resume the interrupted parity wave: recap the 7 interrupted fixers, finish their work, apply live 1-window findings and cross-area notes, verify every area independently, integrate and reinstall (no launch), re-judge Figma parity offscreen and build the live checklist',
  phases: [
    { title: 'Recap', detail: 'Haiku xhigh: where each interrupted fixer stopped', model: 'claude-haiku-5-5' },
    { title: 'Fix', detail: 'Opus medium: continue or follow up per area' },
    { title: 'Verify', detail: 'Opus medium: independent verifier per area, up to 2 refix rounds' },
    { title: 'Integrate', detail: 'full test runner, generators, native suites, check --all, install-app.sh' },
    { title: 'Parity', detail: 'offscreen re-judge of all screen groups + completeness critic with live groups' },
  ],
}

const OPUS = 'claude-opus-5-5'
const HAIKU = 'claude-haiku-5-5'
const ROOT = '.'
const PKG = ROOT + '/modules/gui/macosx_redesign'
const FP = ROOT + '/redesign/research/final-polish'
const FIN = FP + '/results/finish'
const PAR = FP + '/results/parity'
const E = '../build/evidence/final4'
const DIG = E + '/prev-fixers'
const T = E + '/tools'
const O = { model: OPUS, effort: 'medium' }
const H = { model: HAIKU, effort: 'xhigh' }

const CTX = `
PROJECT: native macOS interface (Swift/SwiftUI + AppKit, thin ObjC bridge) for VLC 4 reproducing Juxtopposed's VLC redesign 1:1. Figma = visual truth, the video = behaviour/intent, VLC = semantics. The VLC engine (src/, lib/, include/, other modules) stays untouched. GOAL: the final product — full 1:1 match with Figma and the video, everything working end to end, native Mac feel, fast.
CHECKOUT: ${ROOT}, branch claude/final, HEAD 3c690eb2a0 (WIP checkpoint). Swift package: ${PKG}.
STATE: at fae8f04dc0 every area had passed independent verification (431/431 Swift tests, native suites, install green). Then a parity wave started and was cut off by a usage limit: fixers A-window, B-controls and H-design finished (their reports: ${PAR}/parity-run-interrupted.json, key areaReports[]), the other seven (C-bridge, D-menus, E-library, F-settings, G-panels, I-build, J-media-io) stopped mid-work — their partial edits are committed in 3c690eb2a0 (\`git diff fae8f04dc0 3c690eb2a0 -- <paths>\`), and a digest of each one's tool log is in ${DIG}/<area>.txt. No verification, integration or install of that wave ran: /Applications/VLC Redesign.app is still the fae8f04dc0 build. A first live group (1-window) ran on that installed build: ${PAR}/live-run-1-window.json (7 PASS, 2 FAIL, 1 NOT-RUN + extra findings). THIS WAVE finishes the parity wave and applies the live findings.
INPUTS OF THE PARITY WAVE (read what concerns you): ${FIN}/parity.json (8 offscreen parity judges: screens[] with verdict, differences, owner), ${FIN}/critic.json (missing[] with priority/owner), ${FIN}/areas.json (per area: verdict.open = open minor issues), ${FIN}/area-<area>.json (full reports of the previous wave), ${FIN}/integration.json. Earlier context: ${FP}/HANDOFF.md, ${FP}/findings/<area>.json.
LOST EVIDENCE: every path under <scratch> (final2, final3, live screenshots) mentioned in old reports was deleted. Re-render what you need. Put your outputs only under ${E}/<your-label>/ (durable; outside the repo). Keep them small (well under 300 MB per agent; delete intermediate renders you no longer need).
OWNER DECISIONS (2026-10-16, in DECISIONS.md): D041 accepted (bars stay visible while paused); D045 accepted (extensions page per D035, opaque light dialogs, track numbers from 1); C-09: HDR stays Auto-only (no Off); D033 amended: the relative subtitle Font Size slider follows Figma 804:1341 with "Auto" in the middle. Still waiting for the owner (keep the implementation, list in ownerDecisions): agent-written D042, D044, D046, D047, D048, D049, D050, D051, D052, the D030 product defaults (Continue "Ask", Play locally OFF, ~/Movies) and any new decision you write.
DECISIONS RULE: a difference from Figma is either fixed or covered by a DECISIONS.md entry with evidence (video frame, VLC capability, macOS convention). If you keep a difference, add or amend the entry (smallest edit, re-read the file right before editing — other agents append too; mark it "accepted (agent, 2026-10-17)" and list it in ownerDecisions). Never use a decision to excuse something that can be made to match.
MUST READ: AGENTS.md (hard rules), redesign/docs/DECISIONS.md (D021+, especially D033–D052), redesign/docs/PHILOSOPHY.md, redesign/docs/WORKFLOW.md.
DESIGN SOURCES: redesign/design/figma/renders/*.png, figma_file.json, INDEX.md, ICONS.md; redesign/design/tokens/*; redesign/design/spec/spec-part1.md + spec-part2.md; redesign/docs/design/VIDEO_BREAKDOWN.md; redesign/design/SCREENS.md (S-ids); local video key frames ../reference/video/key-frames/ (+INDEX.md) and transcript.txt (never commit reference material).
PARALLEL WORK: up to 10 area agents edit this checkout at once, each owning specific files. Do not edit files you don't own; if a fix truly needs another area's file, make the smallest edit to just those lines, re-read right before editing, and list it in editsOutsideOwnership. Never revert or reformat other agents' work. Do NOT git commit/stash/reset/checkout/restore/clean — the orchestrator commits.
BUILD/TEST: from ${PKG}: \`swift build\` (shared .build; concurrent builds wait — normal; if it fails in a file you don't own, wait 2–3 min and retry). Targeted tests only (\`swift test --filter <Suite>\`); the integrator runs the full runner. If the test target keeps failing to compile in another area's file for >15 min, fix it only if trivial and report it; otherwise run your suites in an isolated copy under ${E}/<your-label>/pkg. Visual tool: \`swift run mxr-snapshot help\` (list/render/ref/compare/check; --engine shipping-window renders the real window composition offscreen; --scheme/--accent work for Window and App entries; documented deviations live in Sources/MXRGalleryCatalog/FigmaDeviation.swift and Entries/SettingsFigmaDeviations.swift). LOOK at renders yourself (Read shows PNGs) next to Figma renders and key frames — numbers alone are not enough.
NO LIVE UI IN THIS WAVE: do NOT launch "/Applications/VLC Redesign.app", do NOT send synthetic input, do NOT run wait-idle.sh. A live-acceptance wave runs afterwards on an idle Mac; put every check that needs the real window into liveChecks (exact steps + expected result). A pending live check is never a reason for a failed verdict.
NATIVE LOCK: \`${T}/lock.sh acquire <your-label>\` … \`${T}/lock.sh release\` around anything that runs make in ../build/codex-arm64, around tools/native-tests.py suites, and around tools/install-app.sh (install only by the integrator; see redesign/docs/BUILD.md; export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" if make cannot find libSystem). Always release, also on failure; hold ≤ 30 min. Headless engine probes with ../build/codex-arm64/vlc -I dummy on test media in ../build/media/ (60 s S01E01/S01E02 and a 10 min S01E03, each with .srt) need no lock. NEVER touch /Applications/VLC.app and never create other VLC bundles.
QUALITY BAR: premium Mac app. Tokens only (Theme.*), no literal design values in views. Swift 6 strict-concurrency clean (also in the install build). Fix root causes, prefer deleting broken complexity over adding layers; no masks/threshold tweaks that hide visual differences. Gallery fixtures may match Figma's content but must not override product defaults (D030). Tests must check behaviour or what is drawn, not one-line predicates; a regression test must fail without the fix.
`

const AREAS = [
  { key: 'A-window', owns: 'Sources/MXRUI/MXRAppView.swift; Sources/MXRUI/Player/{PlayerView,PlayerBars,PlayerChrome,PlayerGeometry,PlayerMetrics}.swift; Sources/MXRCore/Models/InterfaceModel.swift; Sources/MXRPlugin/{MXRAppController,MXRNativeWindowServices,MXRVideoHost,MXRLaunchFileOpening,MXRFullscreenMagnification}.swift; Sources/MXRGallery/**; Sources/MXRSnapshot/**; Sources/MXRGalleryCatalog/{GalleryCatalog,FigmaDeviation}.swift and Entries/{PlayerGallery,AppGallery,ShippingGallery,ScaffoldGallery,SettingsFigmaDeviations}.swift; Tests/MXRUISnapshotTests/FigmaDeviationTests.swift; the resume toast (MXRContinueWatchingToast)',
    scope: 'Window chrome and composition, bar reveal/hide, fullscreen, PiP, panel placement over the video, Hide UI, shipping-window snapshot fidelity, the snapshot comparison tool and the documented-deviation mechanism.' },
  { key: 'B-controls', owns: 'Sources/MXRUI/Player/{PlayerControls,NativeSeekProgress,PausedSeekStill,ConeScrollHandler,PlayerPreferences,MXROSDView}.swift; Sources/MXRDesign/Typography/OSDTypography.swift; Sources/MXRDesign/Focus/**; Sources/MXRCore/Models/{AppearanceAndPreviewModels,PlaybackClock,PlayerModel}.swift; Sources/MXRCore/Values/{PlayerValues,VideoClickTiming}.swift; Sources/MXRVLCBackend/VLCThumbnailBackend.swift; module/bridge/{MXRThumbnailServices,MXRAudioServices}.{h,m}; Sources/MXRPlugin/MXRNowPlayingClockGate.swift',
    scope: 'Control bar and seek bar: every control and state vs Figma, scrubbing and thumbnails, waveform, subtitle-timeline mode, paused still, OSD, volume tooltip, focus indication, time labels.' },
  { key: 'C-bridge', owns: 'module/bridge/{MXRServicesBridge.m,MXRPlayerBridge.m,MXRMediaServices.*,MXRSubtitleCueServices.*,MXRDialogServices.*,MXRInterfaceBridge.m,MXRPlatformServices.m,MXREffectsServices.*,MXRHotkeyFeedback.inc}; module/*.m and module/*.h; Sources/MXRVLCBackend/{VLCBackends,VLCBridgeSession,VLCPlayerBackend,VLCQueueBackend,VLCServiceBackends,VLCServiceTransport,VLCShortcutCatalog,VLCTypedServiceWire,VLCSettingsBackend}.swift (VLCSettingsBackend only for the rescanPlugins removal); Sources/MXRBridgeAPI/**; Sources/MXRCore/Models/{ServiceModels,QueueModel}.swift; Sources/MXRCore/Values/{ServiceValues,QueueValues,MediaDevice}.swift; Sources/MXRCore/Backends/** except QueueAndLibraryBackends.swift; Sources/MXRMockBackend (non-library, non-output parts)',
    scope: 'Engine bridge correctness and performance: command/event flow, shutdown and quit latency, subtitles, Lua extensions, typed service wire, dead bridge paths.' },
  { key: 'D-menus', owns: 'Sources/MXRDesign/Popup/**; Sources/MXRUI/Player/PlayerMenus.swift; Sources/MXRPlugin/{MXRNativeMenus,MXRKeyRouting,MXRRemoteControl,MXRNativeRecents}.swift; Sources/MXRCore/Values/ShortcutValues.swift; Sources/MXRCore/App/AppCommand.swift and the shortcut/command parts of AppModel.swift; Sources/MXRGalleryCatalog/Entries/MenusGallery.swift',
    scope: 'Popup menus, dropdowns, submenus, right-click menus, ⋯ menu, menu bar, shortcuts, media keys, recents, menu accessibility.' },
  { key: 'E-library', owns: 'Sources/MXRUI/Library/**; Sources/MXRUI/Dialogs/LibraryDialogs.swift; module/bridge/{MXRLibraryServices,MXRDiscoveryServices}.{h,m}; Sources/MXRVLCBackend/VLCLibraryBackend.swift; Sources/MXRCore/Models/LibraryModel.swift; Sources/MXRCore/Values/{LibraryValues,MediaItem}.swift; Sources/MXRCore/Backends/QueueAndLibraryBackends.swift; library parts of Sources/MXRMockBackend; Sources/MXRGalleryCatalog/Entries/LibraryGallery.swift; Tests/Native*Library*.m',
    scope: 'Media library: Home, folders + breadcrumb, Music, playlists, selection, context menus, mini player, compact and full layouts, light and dark.' },
  { key: 'F-settings', owns: 'Sources/MXRUI/Settings/**; Sources/MXRUI/Dialogs/{DialogInput,DialogMenu,DialogSupport,MXRDialogHost,MediaInfoDialogs,AddSubtitlesView}.swift; Sources/MXRPlugin/{MXRNativePresentations,MXRNativePreferences}.swift; module/bridge/MXRAudioPreferenceServices.{h,m}; Sources/MXRCore/Settings/**; Sources/MXRCore/Models/SettingsModel.swift; Sources/MXRCore/Values/SettingsValues.swift; Sources/MXRCore/Stores/{AppStores,PresetStore}.swift; Sources/MXRCore/App/AppModel+Preferences.swift; Sources/MXRCore/Resources/settings-map.json5; Sources/MXRGalleryCatalog/Entries/{SettingsGallery,DialogsGallery}.swift',
    scope: 'Settings (every section vs Figma, light/dark, real VLC options only), profiles, keyboard shortcuts editor, extensions page, modal dialog host (centring, scrim, keyboard isolation), media info, Add Subtitles, confirmations.' },
  { key: 'G-panels', owns: 'Sources/MXRUI/Panels/**; Sources/MXRCore/Models/{EffectsModels,TracksModel}.swift; Sources/MXRCore/Values/Effects.swift; Sources/MXRGalleryCatalog/Entries/PanelsGallery.swift',
    scope: 'Side panels and popovers: Subtitles/Audio/Video/Playback tabs, filter cards, track popover, queue panel, subtitle timeline, presets, metadata overlay.' },
  { key: 'H-design', owns: 'Sources/MXRDesign/{Theme,Generated,Materials,Icons}/** and Sources/MXRDesign/*.swift root files; Sources/MXRDesign/Typography/** except OSDTypography.swift; redesign/design/tokens/**; tools/gen-tokens.py; tools/gen-icons.py; Sources/MXRUI/Customization/**; Sources/MXRPlugin/MXRFirstLaunchOnboarding.swift; Sources/MXRCore/Stores/LayoutStore.swift; Sources/MXRGalleryCatalog/Entries/{CustomizationGallery,DesignAccentsGallery,DesignColorsGallery,DesignGallerySupport,DesignIconsGallery,DesignThemeGallery,DesignTypographyGallery}.swift',
    scope: 'Design system (tokens, icons, materials, accents, accessibility variants), customization mode, onboarding.' },
  { key: 'I-build', owns: 'tools/** except gen-tokens.py and gen-icons.py; Makefile.am; Package.swift; module/tests/**; module/bridge/tests/**; test-runner infrastructure and shared helpers under Tests/; redesign/docs/{BUILD,WORKFLOW}.md; redesign/design/SCREENS.md; redesign/research/final-polish/workflows/{lock.sh,wait-idle.sh}; dead code in files no other area owns',
    scope: 'Build, packaging, install, native test gates and their reliability, test runner, docs that describe the build and the screen status, dead code.' },
  { key: 'J-media-io', owns: 'Sources/MXRUI/Dialogs/OpenMediaDialogs.swift; Sources/MXRVLCBackend/{VLCOutputBackend,VLCRendererBackend}.swift; Sources/MXRCore/Models/{OutputModel,RendererModel}.swift; Sources/MXRMockBackend/MockOutput.swift; output/renderer parts of module/bridge/MXRMediaServices.m',
    scope: 'Open Media (file/disc/network/capture), Convert and Stream (profiles, output jobs, states, real output files), renderers.' },
]

const SPECIFIC = {
  'A-window': `S66 Customize Player mode in the window (parity group 8, MAJOR): the empty second-row band is missing — Figma (every "Player - customize*" frame), key frame 19m12 and spec-part2 §A always give the edit-mode bottom area two rows (972–1080 pt), the upper one an empty bar-material band with dividers. Modal host in the shipping-window composition (parity group 7, MAJOR): S25.App Add Subtitles sits ~19 pt above the centre, and in a compact window (S37.App/convert-compact) the dialog's top is clipped; the App* entries render without the top bar under --engine shipping-window — fix the tooling trap. Add a Window/App gallery entry for the saved two-row layout. Resume toast below ~400 pt video width must not overflow. Keep the Settings gate strict.`,
  'B-controls': `C.SeekBar/default own fixture time (~00:01:53, Figma 1908:7387) without changing product defaults; bar icon hover per Figma Icon Wrapper 177:99 (glyph stays FG/A2, only the white 6 % radius-4 tile); seek thumbnail card placement vs Figma 2151:9673; B-08: OSD sizing/anchoring from the picture, MXRTimeLabel accessibility value set once. Every B-controls item in parity groups 1 and 2.`,
  'C-bridge': `Native audio suite flake (critic P1, with I-build who owns the test): audio-preferences failed "native engine shuts down cleanly" in 2 of 11 runs (8 s deadline) after the engine log already reached "removing keystore memory"; find the silent step (sample/spindump during a slow shutdown, or signposts on the bridge shutdown path; loop the binary under load) and fix the cause if it is in the bridge (may be the real Cmd-Q latency, C-13/PERF-04). Delete the dead rescanPlugins path end to end (AppModel.swift ~462 → VLCSettingsBackend.swift ~54 → MXRBridgeCommandRescanPlugins with no handler). Headless runtime test for C-02 sidecar names containing ( ) ' (no duplicate track). The extension submenu shows entries from a cached catalog snapshot filled only when the catalog is rebuilt — refresh it when an extension activates or changes its menu (with D-menus). C-01 edge (input_New failure leaves :start-paused on the item) — clean it up if cheap.`,
  'D-menus': `Confirm J-10 renderer wording is identical in PlayerMenus and EffectsSidebars (check the current code). Extension submenu freshness (with C-bridge). Disabled shared-model submenu rows in the menu bar look enabled because AppKit autoenables items with submenus — fix. Everything owned by D-menus in parity group 3 (popups and menus).`,
  'E-library': `Compact library rows show the raw file name "The_Wand_S01E…" while the top bar shows the clean title — apply the same display-name rule (D042) wherever Figma shows clean names. S46.MiniPlayer collapsed/hover/queue FAIL: make the fixture name match Figma, and cover the artist chip by D044 in the entry notes/deviations. S28 narrow panel: the two visible breadcrumbs clip to "Th"/"S0" — collapse them into the "…" menu. S29 file context menu: "Mark as Watched" must use the two-tone check-selected glyph (ICONS.md 4004:12348). S40 compact Home fixture content to Figma (Shows / Films / Anime folders, three playlists) without changing product defaults. S72 light: library rows and the current crumb use the right Light foregrounds. Mixed audio+video import gives no feedback for the audio files — fix. View-level tests for E-07 (arrow-key columns), E-10 (multi-select Remove) and E-11 (id-keyed rows). S30/S31 "Edit/Add Audio Tracks" disabled while Figma shows them enabled — enable when possible or record the capability reason under D039.`,
  'F-settings': `Settings parity (parity group 6 + A-window's openSettingsDifferences): S49 general-advanced ("Show minor warnings", "Additional command line options"), S60 performance (rows below "Drop frames"), S51 interface ("Menu Bar and Notifications" vs Figma "Notifications and System Tray", extra ⓘ on "Remember window size and position"), S61 recording ("~/Movies" vs "~/Videos", "Default (Medium)" vs "Medium", extra ⓘ), S55 video (Figma has ⓘ on Start videos in fullscreen, Stop the screensaver, Play video as desktop wallpaper, Method, Aspect ratio — add the info texts), S56 audio ("Target level" drawn disabled while Figma shows it enabled; missing ⓘ on Speaker setup and Replay gain preamp). For every row: if VLC has a real option behind it, implement it for real; only if it truly cannot work on this Mac, record the exact reason under D035; close the matching openSettingsDifferences entries so the gate stays strict. F-08: DialogKeyLoopGuard decides "inside the dialog" by geometry and its test never exercises the guard (window.sendEvent bypasses the monitor) — make background content truly non-focusable while a dialog is up and write a test that fails without the fix. C-15: the "Takes effect after restarting VLC" note must compare against the value at launch. Media Info: align the value columns. Headless probe for the new userDataDirectory key against the real engine.`,
  'G-panels': `OWNER DECISION (D033 amended): the relative subtitle Font Size slider follows Figma 804:1341 — "Auto" in the middle where Figma draws the thumb (stop 3), smaller sizes left, larger right; the stored value stays VLC's enum. Implement, test the mapping, render it and look. S18 Video and S19 Audio filter cards open (parity group 4, MAJOR): Figma (Essential/Crop/Colors, Compressor Settings) and video 08m49 show the open card as ONE lighter rounded container holding the "Collapse Settings" header with a DOWN chevron and the rows, inset — match Figma exactly, including value text placement. Also: S14 Subtitles tab divider (Figma none, video 06m21.7 has one — decide with evidence), S15 divider 1 pt high, S20 Subtitle Speed slider thumb not at the start at 1.000 fps (range 0…60), preset list "Default Preset" row indentation, S21 timeline elapsed fill vs Figma gap (video agrees with us — record the decision), a test that the queue row menu really contains the shared Add to Playlist submenu.`,
  'H-design': `S72 Light cone uses Light/Accent/Logo; subtitle-file glyph folded corner (S25/S26/S27); S66/S67 two-line tile labels; S70 onboarding alternate-accent frames; Light play button colour; everything owned by H-design in parity groups 1, 2, 7 and 8.`,
  'I-build': `Native audio suite flake (critic P1): you own MXRAudioPreferenceServicesRuntimeTests and native-tests.py — do not just raise the 8 s deadline; add diagnostics that capture what runs after "removing keystore memory" when the deadline is missed, and work with C-bridge (who fixes the cause in the bridge). The NSWindow isReleasedWhenClosed contract must check per window, not per file. Accelerate in Makefile.am LDFLAGS if the plugin link needs it (verify with the real install build under the lock, no install). B-03 no-op make: produce the mtime evidence. Update redesign/design/SCREENS.md (stale since 2026-10-14: cites CODEX_STATUS.md and codex/native-redesign, says S62 Lua activation is unavailable; add a visual-parity status per S-id from ${FIN}/parity.json) and BUILD.md where commands changed. Remove remaining dead code in files nobody else owns (critic P2).`,
  'J-media-io': `After Stop, the player's on_stopping_current_media (reason USER) overwrites the bridge's "stopping" with "finishing" — the hint flips to "Finishing…" and Stop re-enables; fix. Audio-only profiles ("Audio — AAC (M4A)" etc.) keep the source's subtitle track (aac + mov_text seen) — drop it and verify the produced file with ffprobe. S37.Stream/running shows the build machine's host name — make the gallery deterministic via the fixture. J-12: pathFieldWidth token belongs in MXRDesign (H's files: smallest edit) and OutputProgressBar must not use a spacing token as a height. Convert empty state draws a focus ring on Format; Stream address/port/path fields need labels; Open Disc and Open Capture Device have large empty areas — tighten. Tests for the overwrite view logic (J-03: format change renames the destination and loses confirmedDestination; it clears on completion).`,
}

const LIVE = `${PAR}/live-run-1-window.json (screenshots lost; the measurements in the report stand)`
const EXTRA = {
  'A-window': `NEW ITEMS FROM THE FIRST LIVE RUN (${LIVE}): (1) MAJOR fullscreen top-edge reveal: with the pointer at the top edge only the macOS menu bar and a blank native fullscreen title strip (separate titlebar window ~1728×40 with the system traffic lights) appear; the app's own top bar (cone, ⋯, sidebar toggle, chip, title, exit-fullscreen) never appears, because the pointer is over the system strip and nearTop never becomes true (PlayerChrome nearTop zone, pointer monitor in MXRAppView ~113). Make the fullscreen top bar reveal as in S05 / the video while following native fullscreen conventions — the user must never see the empty native strip instead of the app's bar. (2) MAJOR Light theme only: opening the compact library rescales the video (aspect-fill to the full window width, pillarbox gone, subtitle cut by the control bar); Dark keeps the geometry — find the Light-only path and fix it. (3) minor: a "Fullscreen" tooltip stays on screen after the bars auto-hide. (4) minor: turning Hide UI off does not reopen the queue that was open before. (5) minor: when the media ends in fullscreen the window leaves fullscreen by itself — check what VLC's macOS/Qt interfaces do at the end of the playlist and match VLC semantics or record a decision. (6) minor: subtitles render across the full picture and are hidden under the compact library and the revealed fullscreen control bar — check the video/Figma intent and VLC's capabilities (sub-margin, vout display area; C-bridge implements any bridge part) and fix or decide with evidence. (7) The resume toast could not be triggered live with 60 s media — make sure the path works with the 10 min S01E03 (headless where possible) and that the live wave can trigger it.
CROSS-AREA NOTES: B-controls reports PlayerInteractionTests.testEveryControlRowKeepsItsIndependentFigmaHeight fails at the current tree (108 vs 54 for one row while customizing) — reconcile with your S66 band change (fix the code, or update the test for the intended D051 behaviour). S01.Window/shipping still FAILs in the top bar (D022/D042): make its deviations cite the decisions so the remaining verdict is honest, and fix D007's wording about a PiP button in the top bar. H-design: the \`tint: Theme.Color.accentLogo\` passed to MXRIcon(.vlc) in PlayerBars.swift and PlayerView.swift is now redundant — remove it.`,
  'B-controls': `NEW ITEMS: LIVE (${LIVE}): during repeated ← seeks the OSD showed "00:48" while the bar showed 00:38 — the OSD text and the bar are out of step; find which one is wrong and fix. D-menus is fixing "Space does nothing after the end of media": make sure the play/pause control state after EOS is right. Update redesign/docs/design/VIDEO_BREAKDOWN.md (~line 138 still lists bar-icon hover as OPEN; D048 records it) — smallest edit. S34.Player/music: decide solid seek bar vs waveform default under D028 with evidence and make the gallery entry honest.`,
  'H-design': `NEW ITEMS: LIVE (${LIVE}, A-05-S72 FAIL, real window, Light theme): the bars measure #BCBBB8/#BBB7BC vs the expected #ABABAA, and the compact library takes on the colour of the video behind it (#D3B7B4…#E1CDC9 over red, #CEDDCA over green) vs #C2C2C1 (D046) — the Light bar material and the compact-library backdrop are too translucent, or do not use the D046 base, in the real window (offscreen renders draw no NSVisualEffect blur, so read the material code path that only runs in the real window). Fix the root cause in Materials (A-window/E-library call sites: smallest edits). The Customize dim colour over real video (#303030 vs Figma #2D2B29) → liveChecks. "Move to New Row" still appends a row below — decide with the video (19m26→19m27.6) whether it should fill the empty band (D051) and implement. S34.Player/music window background #1B1B1B vs #1D1D1D — check the token.`,
  'E-library': `NEW ITEMS from A-window: (a) S72 compact-library divider draws #ACACAC where Figma has #212121 — adopt Figma or document it in D032/D046 with evidence; (b) at the 480 pt minimum window MXRLibraryView(compact:) draws ~248 pt wide inside its 216 pt column (min(427, 0.45·480)) and runs under the video area — make the compact header fit (or agree a minimum with A-window). LIVE: in Light the compact library is tinted by the video behind it — H-design fixes the material; make sure your backdrop uses it.`,
  'D-menus': `NEW ITEM, LIVE (${LIVE}): after the media reaches its end (play icon shown), Space does nothing (two presses) while the Play button and Playback > Play restart playback — make Space behave like the Play button after EOS (VLC semantics: play at the end restarts the item); add a test.`,
  'C-bridge': `NEW ITEM, LIVE: subtitles are hidden under overlays (compact library, revealed fullscreen control bar). A-window decides the behaviour; if it needs a bridge call (sub-margin, vout display area), implement the bridge part.`,
  'F-settings': `NEW ITEM: the \`tint: Theme.Color.accentLogo\` passed to MXRIcon(.vlc) in MediaInfoDialogs.swift is redundant now (the cone takes Accent/Logo from its icon role) — remove it. The S25.App scrim strength and the blur behind the dialog body need the real window → liveChecks.`,
  'G-panels': ``,
  'I-build': `NEW ITEMS: the lock and idle tools used by waves now live as copies in ${T} (lock path changed by sed). Make redesign/research/final-polish/workflows/lock.sh take its lock directory from an environment variable (MXR_LOCK_DIR) with a sane default, so the next wave does not need to edit it. Add the live results so far (${LIVE}) to SCREENS.md where they change a status.`,
  'J-media-io': ``,
}

const RESULT = { type: 'object', properties: {
  status: { type: 'string', enum: ['done', 'partial', 'blocked'] }, summary: { type: 'string' },
  fixed: { type: 'array', items: { type: 'string' } },
  notFixed: { type: 'array', items: { type: 'object', properties: { id: { type: 'string' }, why: { type: 'string' } }, required: ['id', 'why'] } },
  decisionsWritten: { type: 'array', items: { type: 'string' } },
  filesChanged: { type: 'array', items: { type: 'string' } }, editsOutsideOwnership: { type: 'array', items: { type: 'string' } },
  liveChecks: { type: 'array', items: { type: 'object', properties: { id: { type: 'string' }, steps: { type: 'string' }, expect: { type: 'string' } }, required: ['id', 'steps', 'expect'] } },
  ownerDecisions: { type: 'array', items: { type: 'string' } },
  notesForOthers: { type: 'string' }, evidence: { type: 'array', items: { type: 'string' } },
}, required: ['status', 'summary', 'fixed', 'notFixed', 'filesChanged'] }

const VERDICT = { type: 'object', properties: {
  pass: { type: 'boolean' },
  issues: { type: 'array', items: { type: 'object', properties: { severity: { type: 'string', enum: ['blocker', 'major', 'minor'] }, description: { type: 'string' }, where: { type: 'string' } }, required: ['severity', 'description'] } },
  liveChecks: { type: 'array', items: { type: 'object', properties: { id: { type: 'string' }, steps: { type: 'string' }, expect: { type: 'string' } }, required: ['id', 'steps', 'expect'] } },
  ownerDecisions: { type: 'array', items: { type: 'string' } },
  summary: { type: 'string' },
}, required: ['pass', 'issues', 'summary'] }

const RECAP = { type: 'object', properties: {
  done: { type: 'array', items: { type: 'string' }, description: 'work-list items the predecessor finished (edit made and checked)' },
  inProgress: { type: 'array', items: { type: 'object', properties: { item: { type: 'string' }, state: { type: 'string' }, files: { type: 'array', items: { type: 'string' } } }, required: ['item', 'state'] } },
  notStarted: { type: 'array', items: { type: 'string' } },
  filesTouched: { type: 'array', items: { type: 'string' } },
  testsAdded: { type: 'array', items: { type: 'string' } },
  decisionsWritten: { type: 'array', items: { type: 'string' } },
  risks: { type: 'array', items: { type: 'string' }, description: 'half-done edits, temporary reverts that may not have been restored, failing builds/tests at the moment it stopped' },
  summary: { type: 'string' },
}, required: ['done', 'inProgress', 'notStarted', 'risks', 'summary'] }

const header = (a) => `YOUR AREA: ${a.key}\nYOU OWN (paths relative to ${PKG} unless they start with redesign/): ${a.owns}\nSCOPE: ${a.scope}`
const workList = (a) => `WORK LIST OF ${a.key}:
(a) every screens[] item in ${FIN}/parity.json whose owner is "${a.key}" and verdict is major-diff or minor-diff, plus differences in other groups that your files cause;
(b) every missing[] item in ${FIN}/critic.json whose owner mentions ${a.key};
(c) the open minor issues of your area's last verifier: ${FIN}/areas.json, entry "${a.key}", verdict.open;
(d) specifically: ${SPECIFIC[a.key]}
(e) notes other areas left for you in ${PAR}/parity-run-interrupted.json (areas[].notesForOthers, notFixed[] items naming ${a.key});
(f) ${EXTRA[a.key] || 'no new items beyond (a)–(e).'}`

const howToFix = (a) => `Fix every item at the root cause (majors first). For a visual item: render before and after, LOOK at both next to the Figma render and the key frame, and keep the evidence under ${E}/${a.key}/. For a difference you keep, make sure a decision covers it (DECISIONS RULE). Add focused tests that fail without the fix. Report every item of the work list: fixed (with evidence path), kept with which decision, or not fixed and why.`

const INTERRUPTED = ['C-bridge', 'D-menus', 'E-library', 'F-settings', 'G-panels', 'I-build', 'J-media-io']

const recapPrompt = (a) => `You are summarising where an interrupted coding agent stopped. Read ${DIG}/${a.key}.txt (a digest of its tool log: SAY = its narration, BASH/EDIT/WRITE = actions, RESULT = tool output, times in UTC). Its partial edits are committed in ${ROOT} as 3c690eb2a0; you may run \`git -C ${ROOT} diff --stat fae8f04dc0 3c690eb2a0\` and \`git -C ${ROOT} diff fae8f04dc0 3c690eb2a0 -- <file>\` (read-only: never edit, commit, stash or checkout anything).
Its work list was:\n${workList(a)}
Classify each work-list item as done (edited and checked by a build/test/render), inProgress (with exactly what state it was left in and which files), or notStarted. List files touched, tests added, decisions written, and risks: half-done edits, temporary "revert to prove the test fails" steps that may not have been restored (compare the digest with the committed diff), and builds/tests that were failing when it stopped. Be concrete and short; cite the digest times.`

const continuePrompt = (a, recap) => `${CTX}\n${header(a)}\n${workList(a)}
You are the FIXER of this area, CONTINUING a predecessor that was cut off by a usage limit. Its tool-log digest: ${DIG}/${a.key}.txt; its partial edits are in 3c690eb2a0 (\`git diff fae8f04dc0 3c690eb2a0 -- <your files>\`). Summary of where it stopped (written by a cheaper model — check it against the code): ${recap ? JSON.stringify(recap) : 'unavailable; read the digest yourself'}.
First make its half-done edits coherent: build, run the tests it wrote, restore anything it temporarily reverted, finish or cleanly remove half-done pieces (only its own pieces, never other agents'). Then finish every remaining item of the work list. ${howToFix(a)} Your report covers the whole work list, including the items the predecessor finished (check them briefly).`

const followupPrompt = (a) => `${CTX}\n${header(a)}\n${workList(a)}
You are the FIXER of this area. A previous instance of you already completed items (a)–(d) in this wave; its report is in ${PAR}/parity-run-interrupted.json → areaReports[] entry "${a.key}", reports[0] (read it; its evidence paths under final3 are gone). Nobody has verified it yet. Now handle the items in (e) and (f), and re-check that the earlier fixes still hold on the current tree (other areas kept editing). ${howToFix(a)} Your report must be cumulative: everything fixed in this wave (earlier report + now), everything still not fixed, all decisions written.`

const verifyPrompt = (a, cur, round) => `${CTX}\n${header(a)}\n${workList(a)}
You are an INDEPENDENT VERIFIER of this area, round ${round} (not its author; do not edit product code, tests or docs; write only under ${E}/${a.key}-verify-r${round}/).
The fixer's latest report: ${JSON.stringify(cur)}
Check EVERY item of the work list, not only the claimed ones: read the code, build, run the targeted tests (and check that new regression tests fail without the fix where feasible — in an isolated copy under your output folder, never by editing the shared tree), render the affected states and LOOK at them next to the Figma renders and key frames. Check each new or amended DECISIONS entry: is the difference really unavoidable, or could it match Figma? Also check: no regressions of the previous wave (re-render a few neighbouring entries), ownership respected, tokens only, Swift 6 clean, engine untouched (\`git diff upstream-base-2026-10-14 -- src lib include modules/gui/macosx\` empty), no masks/thresholds hiding differences, Settings gate not loosened.
pass=false only if a blocker or major remains that code, tests or renders can establish (an unjustified decision that excuses a fixable visual difference is a major). Real-window-only checks go to liveChecks.`

const refixPrompt = (a, cur, v) => `${CTX}\n${header(a)}\n${workList(a)}
You are continuing as the FIXER of this area. Your previous report: ${JSON.stringify(cur)}
An independent verifier found these remaining problems — fix all blocker/major ones and the reasonable minor ones, re-verify, and report (cumulatively):\n${JSON.stringify(v.issues, null, 1)}`

async function runArea(a) {
  let cur
  if (INTERRUPTED.includes(a.key)) {
    const recap = await agent(recapPrompt(a), { label: `recap ${a.key}`, phase: 'Recap', schema: RECAP, ...H })
    if (recap) log(`${a.key} recap: done ${recap.done.length}, in progress ${recap.inProgress.length}, not started ${recap.notStarted.length}, risks ${recap.risks.length}`)
    cur = await agent(continuePrompt(a, recap), { label: `fix ${a.key}`, phase: 'Fix', schema: RESULT, ...O })
  } else {
    cur = await agent(followupPrompt(a), { label: `fix ${a.key}`, phase: 'Fix', schema: RESULT, ...O })
  }
  if (!cur) return { area: a.key, state: 'fixer failed' }
  log(`${a.key}: fix ${cur.status} — fixed ${(cur.fixed || []).length}, open ${(cur.notFixed || []).length}`)
  const reports = [cur]
  const live = [...(cur.liveChecks || [])]
  const decisions = [...(cur.ownerDecisions || [])]
  let last = null
  let round = 1
  for (; round <= 3; round++) {
    const v = await agent(verifyPrompt(a, cur, round), { label: `verify ${a.key} r${round}`, phase: 'Verify', schema: VERDICT, ...O })
    if (!v) return { area: a.key, state: 'verifier failed', reports, verdict: last, liveChecks: live, ownerDecisions: decisions }
    last = v
    live.push(...(v.liveChecks || []))
    decisions.push(...(v.ownerDecisions || []))
    log(`${a.key} r${round}: pass=${v.pass} — ${v.summary.slice(0, 160)}`)
    if (v.pass) return { area: a.key, state: 'passed', round, reports, verdict: v, liveChecks: live, ownerDecisions: decisions }
    if (round === 3) break
    const next = await agent(refixPrompt(a, cur, v), { label: `refix ${a.key} r${round}`, phase: 'Fix', schema: RESULT, ...O })
    if (!next) return { area: a.key, state: 'refixer failed', reports, verdict: v, liveChecks: live, ownerDecisions: decisions }
    cur = next
    reports.push(next)
    live.push(...(next.liveChecks || []))
    decisions.push(...(next.ownerDecisions || []))
  }
  return { area: a.key, state: 'not passed after 2 refix rounds', round, reports, verdict: last, liveChecks: live, ownerDecisions: decisions }
}

phase('Fix')
const areaResults = (await pipeline(AREAS, (a) => runArea(a))).filter(Boolean)

const compact = areaResults.map(r => {
  const lastReport = (r.reports || [])[(r.reports || []).length - 1]
  return {
    area: r.area, state: r.state,
    fixed: lastReport && lastReport.fixed, notFixed: lastReport && lastReport.notFixed,
    decisionsWritten: lastReport && lastReport.decisionsWritten,
    notesForOthers: lastReport && lastReport.notesForOthers,
    verdict: r.verdict && { pass: r.verdict.pass, summary: r.verdict.summary, open: r.verdict.issues },
  }
})
const liveChecks = areaResults.flatMap(r => (r.liveChecks || []).map(c => ({ area: r.area, ...c })))
const ownerDecisions = areaResults.flatMap(r => (r.ownerDecisions || []).map(d => `${r.area}: ${d}`))
log(`areas: ${compact.map(c => `${c.area}=${c.state}`).join(', ')}; ${liveChecks.length} live checks collected`)

phase('Integrate')
const integ = await agent(`${CTX}
You are the INTEGRATOR after this wave (all area agents have finished; nobody else edits now). Area results: ${JSON.stringify(compact)}
1. From ${ROOT}: full runner \`python3 modules/gui/macosx_redesign/tools/run-swift-tests.py modules/gui/macosx_redesign modules/gui/macosx_redesign/.build\` (run it twice), tools/gen-tokens.py --check, tools/gen-icons.py --check, every tools/test-*.py, and under the lock every native suite of tools/native-tests.py --engine-build ../build/codex-arm64 (run the audio suite 10 times and report the pass count). Fix integration breakages (cross-area compile errors, tests invalidated by intended changes); for a non-trivial failure that belongs to an area, fix it only if the cause is clear and the fix small, otherwise report it with evidence. Confirm \`git diff upstream-base-2026-10-14 -- src lib include modules/gui/macosx\` is empty.
2. \`.build/debug/mxr-snapshot check --all\`: compare with the fae8f04dc0 wave (PASS 15 · REVIEW 49 · FAIL 43; see ${FIN}/integration.json) and list every entry whose verdict changed and every remaining FAIL with its reason (documented deviation, fixture, real difference).
3. Under the lock: install with tools/install-app.sh (do NOT launch). Check that only /Applications/VLC.app (untouched, modification date 1743527633) and /Applications/VLC Redesign.app exist, the install build has 0 Swift warnings, and the build dir has no leftover VLC.app.
4. Release the lock. Report exact commands, counts and remaining problems. Outputs under ${E}/integration/.`, { label: 'integrate', phase: 'Integrate', ...O, schema: { type: 'object', properties: {
  testsPassed: { type: 'boolean' }, testSummary: { type: 'string' }, nativeSuites: { type: 'string' }, snapshotCheck: { type: 'string' }, installed: { type: 'string' },
  fixesMade: { type: 'array', items: { type: 'string' } }, remainingProblems: { type: 'array', items: { type: 'string' } }, summary: { type: 'string' },
}, required: ['testsPassed', 'testSummary', 'remainingProblems', 'summary'] } })
log(`integration: tests ${integ ? integ.testsPassed : 'agent failed'} — ${integ ? String(integ.summary).slice(0, 200) : ''}`)

phase('Parity')
const GROUPS = [
  'Player window: dark, light, Hide UI, fullscreen, windowed thin frame, top bar, traffic lights, cone, PiP placeholder',
  'Control bar and seek bar: every control, hover/pressed states, scrubbing preview, waveform and subtitle-timeline modes, OSD, volume tooltip, resume toast, compact widths',
  'Popups and menus: ⋯ menu, right-click menu and submenus, dropdowns, track popover, speed/HDR/zoom menus, menu bar',
  'Side panels: Subtitles, Audio, Video, Playback tabs, filter cards open and closed, queue, subtitle timeline, effects/filters, presets, metadata overlay',
  'Library: Home, folders and breadcrumb, Music (songs/albums/artists/genres), playlists, context menus, search, mini player, empty and loading states, light theme',
  'Settings: every section in dark and light, keyboard shortcuts editor, extensions, profiles',
  'Dialogs: Open Media (file/disc/network/capture), Convert, Stream, Add Subtitles, Media Info, confirmations, modal host in normal and compact windows',
  'Customization mode (incl. the two-row band), onboarding, design system (icons, accents, typography, colours, materials)',
]
const PARITY = { type: 'object', properties: {
  screens: { type: 'array', items: { type: 'object', properties: { screen: { type: 'string' }, verdict: { type: 'string', enum: ['match', 'minor-diff', 'major-diff', 'missing', 'not-checked'] }, differences: { type: 'string' }, owner: { type: 'string', description: 'area key that owns the fix' }, evidence: { type: 'string' } }, required: ['screen', 'verdict', 'differences'] } },
  summary: { type: 'string' },
}, required: ['screens', 'summary'] }
const parity = await parallel([
  ...GROUPS.map((g, i) => () => agent(`${CTX}
You are a DESIGN-PARITY JUDGE (read-only; outputs only under ${E}/parity-${i + 1}/). Screen group: ${g}.
The previous judge of this group: ${FIN}/parity.json item ${i} — re-check every screen it listed (especially its major-diff and minor-diff items: are they fixed now, or covered by a justified decision?) and anything it missed. Using redesign/design/SCREENS.md, list every S-id / Figma frame in this group. Render each matching gallery entry offscreen (prefer --engine shipping-window where it applies) in the schemes Figma has, and compare with the Figma render and the video key frames — LOOK at them side by side (crop and zoom where needed). Judge strictly: the owner wants a full 1:1 match; a documented decision is not a difference only if it is justified — say which decision covers it and whether you agree. Name the owning area for each difference. Real-window-only aspects: not-checked with what to look at. Integration summary: ${integ ? integ.summary : 'integration failed'}.`, { label: `parity ${i + 1}`, phase: 'Parity', ...O, schema: PARITY })),
  () => agent(`${CTX}
You are the COMPLETENESS CRITIC (read-only; outputs only under ${E}/critic/). Area results: ${JSON.stringify(compact)}\nIntegration: ${JSON.stringify(integ)}\nLive checks collected in this wave: ${JSON.stringify(liveChecks)}\nPrevious critic: ${FIN}/critic.json; previous live list: ${FIN}/live-checks.json and ${FIN}/live-groups.json; first live run (group 1-window only): ${LIVE}.
What is still missing for the final product? Previous critic items not closed, audit ids neither fixed nor decided, VIDEO_BREAKDOWN.md MUST rules and SCREENS.md items not working end to end, agent-written decisions that excuse fixable differences, docs out of date. Then produce ONE deduplicated, ordered live-acceptance checklist for the idle-Mac wave on the newly installed build. Merge: ${FIN}/live-groups.json groups 2–9 (never run), the FAIL / NOT-RUN checks and extra findings of group 1-window (its PASS checks only where this wave changed the code behind them), this wave's live checks, and the owner's complaints C1–C7 (C1 no focus box around volume/seek; C2 track popover anchored bottom-right above the bar; C3 single 40 pt top bar, traffic lights centred, cone right after them; C4 consistent open/close motion, Esc and click-outside close without pausing; C5 sidebar overlays the video, video not shrunk; C6 scrubbing updates playhead/label/preview continuously; C7 single volume indicator, no VLC core OSD) — mark those with ownerComplaint true. Note for the steps: the display is 1728×1117 pt (no 1920×1080 window possible), test media are in ../build/media/ (60 s S01E01/S01E02; the 10 min S01E03 is for resume and long-seek checks). Group the checks so one agent can run a group in 20–30 minutes.`, { label: 'completeness critic', phase: 'Parity', ...O, schema: { type: 'object', properties: {
    missing: { type: 'array', items: { type: 'object', properties: { priority: { type: 'string', enum: ['P0', 'P1', 'P2'] }, item: { type: 'string' }, evidence: { type: 'string' }, owner: { type: 'string' } }, required: ['priority', 'item'] } },
    liveGroups: { type: 'array', items: { type: 'object', properties: { group: { type: 'string' }, checks: { type: 'array', items: { type: 'object', properties: { id: { type: 'string' }, area: { type: 'string' }, ownerComplaint: { type: 'boolean' }, steps: { type: 'string' }, expect: { type: 'string' } }, required: ['id', 'steps', 'expect'] } } }, required: ['group', 'checks'] } },
    summary: { type: 'string' },
  }, required: ['missing', 'liveGroups', 'summary'] } }),
])

return {
  areas: compact,
  areaReports: areaResults.map(r => ({ area: r.area, reports: r.reports, verdict: r.verdict })),
  liveChecks, ownerDecisions,
  integration: integ,
  parity: parity.slice(0, GROUPS.length).map((p, i) => p && { group: GROUPS[i], ...p }),
  critic: parity[GROUPS.length],
}
