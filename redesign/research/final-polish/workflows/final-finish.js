export const meta = {
  name: 'final-polish-finish',
  description: 'Finish the interrupted final-polish wave: complete open fixes (A/C/F refix, I-build fix, D/G/H minors and cross-area notes), independently verify every area (B/E/J for the first time), integrate (full tests, native suites, install), then judge design parity offscreen and list what is still missing; real-window checks are collected for a separate idle-Mac wave',
  phases: [
    { title: 'Fix', detail: 'Opus medium: continue interrupted fixers, minors and cross-area notes' },
    { title: 'Verify', detail: 'Opus medium: independent verifier per area, up to 2 refix rounds' },
    { title: 'Integrate', detail: 'full test runner, generators, native suites, install-app.sh (no launch)' },
    { title: 'Parity', detail: 'offscreen design-parity judges per screen group + completeness critic' },
  ],
}

const OPUS = 'claude-opus-5-5'
const ROOT = '.'
const PKG = ROOT + '/modules/gui/macosx_redesign'
const FP = ROOT + '/redesign/research/final-polish'
const R = FP + '/results'
const OLD = '<scratch>'
const SCR = '<scratch>'
const T = SCR + '/tools'
const O = { model: OPUS, effort: 'medium' }

const CTX = `
PROJECT: native macOS interface (Swift/SwiftUI + AppKit, thin ObjC bridge) for VLC 4 reproducing Juxtopposed's VLC redesign 1:1. Figma = visual truth, the video = behaviour/intent, VLC = semantics. The VLC engine (src/, lib/, include/, other modules) stays untouched. GOAL: bring the product to its final state — full 1:1 match with Figma and the video, everything working end to end, native Mac feel, fast.
CHECKOUT: ${ROOT}, branch claude/final. Swift package: ${PKG}.
STATE: this continues the "final-polish" wave that was stopped at 19:40 on 2026-10-16 (HEAD 4c457baa03 "final-polish: stop for account handoff"). READ ${FP}/HANDOFF.md FIRST (Russian): per-area status, what is open, what Codex did well or badly. Confirmed findings per area: ${FP}/findings/<area>.json (confirmed[]: id, severity, title, evidence, fix, files; codexAssessment = reviewer verdict on Codex's audit fixes). Agent reports of the stopped run: ${R}/wf_*-fix_<area>.json and ${R}/wf_*-verify_<area>_r1.json. Digests of agents stopped mid-work (files edited, narration, last commands): ${R}/interrupted/*.txt. Evidence of the stopped run (renders, probes, logs; may be reused but re-check): ${OLD}/<area>*/ and the earlier digests ${OLD}/prev/<area>.txt. The interrupted agents' uncommitted edits ARE in HEAD: \`git diff 951f073be2 4c457baa03 -- <files>\` shows what they changed after the WIP commit; \`git diff a215064366 4c457baa03 -- <files>\` shows the whole wave.
HISTORY: 5ac081046e = Claude polish wave 1. 3bbac3cb63 = app icon + single-copy install. a215064366 = Codex fixes for audits redesign/research/audits/claude-2026-10-15.md (69/100) and chatgpt-2026-10-15.md (68/100), Codex log redesign/research/AUDIT_FIXES_2026-10-15.md. 951f073be2 = WIP of this wave. 4c457baa03 = stop commit.
MUST READ: AGENTS.md (hard rules), redesign/docs/DECISIONS.md (D021+, especially D033–D047), redesign/docs/PHILOSOPHY.md, redesign/docs/WORKFLOW.md.
DESIGN SOURCES: redesign/design/figma/renders/*.png, figma_file.json, INDEX.md, ICONS.md; redesign/design/tokens/*; redesign/design/spec/spec-part1.md + spec-part2.md; redesign/docs/design/VIDEO_BREAKDOWN.md; redesign/design/SCREENS.md (S-ids); local video key frames ../reference/video/key-frames/ (+INDEX.md) and transcript.txt (never commit reference material).
PARALLEL WORK: up to 10 area agents edit this checkout at once, each owning specific files. Do not edit files you don't own; if a fix truly needs another area's file, make the smallest edit to just those lines, re-read right before editing, and list it in editsOutsideOwnership. Never revert or reformat other agents' work. Do NOT git commit/stash/reset/checkout/restore/clean — the orchestrator commits.
BUILD/TEST: from ${PKG}: \`swift build\` (shared .build; concurrent builds wait — normal; if it fails in a file you don't own, wait 2–3 min and retry). Targeted tests only (\`swift test --filter <Suite>\`); the integrator runs the full runner (tools/run-swift-tests.py). If the test target keeps failing to compile in another area's file for >15 min, fix it only if it is a trivial compile error (missing import, renamed symbol) and report it; otherwise run your suites in an isolated copy under ${SCR}/<your-label>/pkg and say so. Visual tool: \`swift run mxr-snapshot help\` (list/render/ref/compare/check; --engine shipping-window renders the real window composition offscreen). Put outputs only under ${SCR}/<your-label>/. LOOK at renders yourself (Read shows PNGs) next to Figma renders and key frames — numbers alone are not enough.
NO LIVE UI IN THIS WAVE: the owner is using the Mac right now. Do NOT launch "/Applications/VLC Redesign.app", do NOT send synthetic input, do NOT run wait-idle.sh. A dedicated live-acceptance wave will run later on an idle Mac. Put every check that needs the real window (screenshots of the installed app, keyboard/VoiceOver/media keys, CPU, quit latency, drag and drop, fullscreen, PiP) into liveChecks with exact steps and the expected result. Everything else must still be checked by code, tests and offscreen renders. A pending live check is NOT a reason for a failed verdict.
NATIVE LOCK: \`${T}/lock.sh acquire <your-label>\` … \`${T}/lock.sh release\` around anything that runs make in ../build/codex-arm64, around tools/native-tests.py suites, and around tools/install-app.sh (install only by I-build and the integrator; it produces /Applications/VLC Redesign.app — see redesign/docs/BUILD.md; export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" if make cannot find libSystem). Always release, also on failure; hold ≤ 30 min. Headless engine probes with ../build/codex-arm64/vlc -I dummy on test media in ../build/media/ need no lock. NEVER touch /Applications/VLC.app (the owner's official VLC) and never create other VLC bundles.
OWNER DECISIONS PENDING — do not decide them; keep the current implementation and list anything that depends on them in ownerDecisions: D041 pause pin (bars stay visible while paused), D045 (extensions page per D035, opaque light dialogs, track numbers from 1), C-09 HDR "Off" trade-off (D039), relative subtitle font-size slider order (D033, Auto at stop 0 vs Figma stop 3).
QUALITY BAR: premium Mac app. Tokens only (Theme.*), no literal design values in views. Swift 6 strict-concurrency clean. Fix root causes, prefer deleting broken complexity over adding layers; no masks/threshold tweaks that hide visual differences. Gallery fixtures must not override product defaults (D030). Tests must check behaviour or what is drawn, not one-line predicates. Keep what the audits list as done well.
`

const AREAS = [
  { key: 'A-window', owns: 'Sources/MXRUI/MXRAppView.swift; Sources/MXRUI/Player/{PlayerView,PlayerBars,PlayerChrome,PlayerGeometry,PlayerMetrics}.swift; Sources/MXRCore/Models/InterfaceModel.swift; Sources/MXRPlugin/{MXRAppController,MXRNativeWindowServices,MXRVideoHost,MXRLaunchFileOpening,MXRFullscreenMagnification}.swift; Sources/MXRGallery/**; Sources/MXRSnapshot/**; Sources/MXRGalleryCatalog/GalleryCatalog.swift and Entries/{PlayerGallery,AppGallery,ShippingGallery,ScaffoldGallery}.swift; the resume toast (MXRContinueWatchingToast)',
    scope: 'Window chrome and composition: single 40 pt top bar, centred traffic lights, cone placement, bar reveal/hide (top and bottom independent), fullscreen and windowed states, cursor hiding, PiP window behaviour, panel/sidebar/queue placement over the video and their motion, Esc/click-outside dismissal, launch to Home, empty-queue behaviour, Hide UI, shipping-window snapshot fidelity, the snapshot comparison tool.' },
  { key: 'B-controls', owns: 'Sources/MXRUI/Player/{PlayerControls,NativeSeekProgress,PausedSeekStill,ConeScrollHandler,PlayerPreferences,MXROSDView}.swift; Sources/MXRDesign/Typography/OSDTypography.swift; Sources/MXRDesign/Focus/**; Sources/MXRCore/Models/{AppearanceAndPreviewModels,PlaybackClock,PlayerModel}.swift; Sources/MXRCore/Values/{PlayerValues,VideoClickTiming}.swift; Sources/MXRVLCBackend/VLCThumbnailBackend.swift; module/bridge/{MXRThumbnailServices,MXRAudioServices}.{h,m}; Sources/MXRPlugin/MXRNowPlayingClockGate.swift',
    scope: 'Control bar and seek bar: every control and state vs Figma, scrubbing (continuous playhead/label/preview), thumbnails, waveform (off by default), subtitle-timeline mode, paused-seek still (D031), OSD look (two-line action + key), volume tooltip, focus indication (no system focus rings), video click timing, Now Playing clock, CPU with bars visible/hidden/scrubbing.' },
  { key: 'C-bridge', owns: 'module/bridge/{MXRServicesBridge.m,MXRPlayerBridge.m,MXRMediaServices.*,MXRSubtitleCueServices.*,MXRDialogServices.*,MXRInterfaceBridge.m,MXRPlatformServices.m,MXREffectsServices.*,MXRHotkeyFeedback.inc}; module/*.m and module/*.h (MXRIntf, MXRVoutWindow, …); Sources/MXRVLCBackend/{VLCBackends,VLCBridgeSession,VLCPlayerBackend,VLCQueueBackend,VLCServiceBackends,VLCServiceTransport,VLCShortcutCatalog,VLCTypedServiceWire}.swift; Sources/MXRBridgeAPI/**; Sources/MXRCore/Models/{ServiceModels,QueueModel}.swift; Sources/MXRCore/Values/{ServiceValues,QueueValues,MediaDevice}.swift; Sources/MXRCore/Backends/{ServiceBackends,PlayerBackends or other non-library backends}.swift; Sources/MXRMockBackend (non-library parts)',
    scope: 'Engine bridge correctness and performance: command/event flow, open paused/start playing, topic snapshots, no main-thread blocking, device discovery, OSD feed and hotkey names, subtitles (external/sidecar/folder mappings, drop, fullscreen), Lua extensions + dialog provider, HDR/resolution handling, exit latency, typed service wire.' },
  { key: 'D-menus', owns: 'Sources/MXRDesign/Popup/**; Sources/MXRUI/Player/PlayerMenus.swift; Sources/MXRPlugin/{MXRNativeMenus,MXRKeyRouting,MXRRemoteControl,MXRNativeRecents,MXRMenuAccessibility}.swift; Sources/MXRCore/Values/ShortcutValues.swift; Sources/MXRCore/App/AppCommand.swift and the shortcut/command parts of AppModel.swift; Sources/MXRGalleryCatalog/Entries/MenusGallery.swift',
    scope: 'Popup menus, dropdowns, submenus, right-click menus, ⋯ menu, menu bar, shortcuts (⌘ conventions, Mac glyphs), media keys/remote, recents; exact Figma look (rows, icons, shortcut column, ✓, hover, separators, motion, shadow), keyboard navigation, VoiceOver roles for custom menus, pin/anchoring rules.' },
  { key: 'E-library', owns: 'Sources/MXRUI/Library/**; Sources/MXRUI/Dialogs/LibraryDialogs.swift; module/bridge/{MXRLibraryServices,MXRDiscoveryServices}.{h,m}; Sources/MXRVLCBackend/VLCLibraryBackend.swift; Sources/MXRCore/Models/LibraryModel.swift; Sources/MXRCore/Values/{LibraryValues,MediaItem}.swift; Sources/MXRCore/Backends/QueueAndLibraryBackends.swift; library parts of Sources/MXRMockBackend; Sources/MXRGalleryCatalog/Entries/LibraryGallery.swift; Tests/Native*Library*.m',
    scope: 'Media library with real data: Home sections, folders + breadcrumb, Music (songs/albums/artists/genres), playlists (add/remove/sort, duplicates), selection model, Add File, Show all, sorting per kind, network/discovery, mini player, paging/caching, empty/loading states, light and dark.' },
  { key: 'F-settings', owns: 'Sources/MXRUI/Settings/**; Sources/MXRUI/Dialogs/{DialogInput,DialogMenu,DialogSupport,MXRDialogHost,MediaInfoDialogs,AddSubtitlesView}.swift; Sources/MXRPlugin/{MXRNativePresentations,MXRNativePreferences}.swift; Sources/MXRVLCBackend/VLCSettingsBackend.swift; module/bridge/MXRAudioPreferenceServices.{h,m}; Sources/MXRCore/Settings/**; Sources/MXRCore/Models/SettingsModel.swift; Sources/MXRCore/Values/SettingsValues.swift; Sources/MXRCore/Stores/{AppStores,PresetStore}.swift; Sources/MXRCore/App/AppModel+Preferences.swift; Sources/MXRCore/Resources/settings-map.json5; Sources/MXRGalleryCatalog/Entries/{SettingsGallery,DialogsGallery}.swift',
    scope: 'Settings (every section, light/dark, values written in the right units, nothing that does nothing, no raw engine values), window title preference, profiles (switching, migration, no rollback of user state), keyboard shortcuts editor, extensions settings, modal dialog host (centred, scrim, isolation incl. keyboard focus loop, Esc/⌘W), media info, Add Subtitles, confirmations.' },
  { key: 'G-panels', owns: 'Sources/MXRUI/Panels/**; Sources/MXRCore/Models/{EffectsModels,TracksModel}.swift; Sources/MXRCore/Values/Effects.swift; Sources/MXRGalleryCatalog/Entries/PanelsGallery.swift',
    scope: 'Side panels and popovers content: Subtitles/Audio/Video/Playback tabs (exact rows and controls from Figma and the video), track popover, queue panel, subtitle timeline, effects/filters inspector, presets, metadata overlay.' },
  { key: 'H-design', owns: 'Sources/MXRDesign/{Theme,Generated,Materials,Icons}/** and Sources/MXRDesign/*.swift root files; Sources/MXRDesign/Typography/** except OSDTypography.swift; redesign/design/tokens/**; tools/gen-tokens.py; tools/gen-icons.py; Sources/MXRUI/Customization/**; Sources/MXRPlugin/MXRFirstLaunchOnboarding.swift; Sources/MXRCore/Stores/LayoutStore.swift; Sources/MXRGalleryCatalog/Entries/{CustomizationGallery,DesignAccentsGallery,DesignColorsGallery,DesignGallerySupport,DesignIconsGallery,DesignThemeGallery,DesignTypographyGallery}.swift',
    scope: 'Design system: tokens vs Figma (colors incl. light theme and scrims, typography, metrics, materials/backdrop, icons two-tone), accent swatches, Increase Contrast / Differentiate Without Color, customization mode, onboarding.' },
  { key: 'I-build', owns: 'tools/** except gen-tokens.py and gen-icons.py; Makefile.am; Package.swift; module/tests/**; module/bridge/tests/**; test-runner infrastructure and shared helpers under Tests/ (not feature tests owned by areas); redesign/docs/{BUILD,WORKFLOW}.md; dead code in files no other area owns',
    scope: 'Build, packaging, install-app.sh (single copy, rollback, signing order), finalize, native test gates, test runner, schema drift, reproducibility, dead code and junk, over-engineered tooling and tooling tests that are noise.' },
  { key: 'J-media-io', owns: 'Sources/MXRUI/Dialogs/OpenMediaDialogs.swift; Sources/MXRVLCBackend/{VLCOutputBackend,VLCRendererBackend}.swift; Sources/MXRCore/Models/{OutputModel,RendererModel}.swift; Sources/MXRMockBackend/MockOutput.swift; output/renderer parts of module/bridge/MXRMediaServices.m',
    scope: 'Open Media (file/disc/network/capture), Convert and Stream (formats VLC supports, output jobs, partial files, real output file), renderers (Chromecast etc.). Verify outputs for real: convert a test clip headlessly and check the produced file with ffprobe.' },
]

// What each area still needs. mode: fix = fixer continues; refix = verifier r1 failed and its refixer was cut off; verify = fix done, never verified; minors = passed r1, minor issues left.
const PLAN = {
  'A-window':   { mode: 'refix',  fix: R + '/wf_eade8af3-fix_A-window.json', v1: R + '/wf_eade8af3-verify_A-window_r1.json', cut: R + '/interrupted/refix_A-window_r1.txt' },
  'B-controls': { mode: 'verify', fix: R + '/wf_eade8af3-fix_B-controls.json', cut: R + '/interrupted/verify_B-controls_r1.txt' },
  'C-bridge':   { mode: 'refix',  fix: R + '/wf_eade8af3-fix_C-bridge.json', v1: R + '/wf_eade8af3-verify_C-bridge_r1.json', cut: R + '/interrupted/refix_C-bridge_r1.txt' },
  'D-menus':    { mode: 'minors', fix: R + '/wf_eade8af3-fix_D-menus.json', v1: R + '/wf_eade8af3-verify_D-menus_r1.json' },
  'E-library':  { mode: 'verify', fix: R + '/wf_eade8af3-fix_E-library.json', cut: R + '/interrupted/verify_E-library_r1.txt' },
  'F-settings': { mode: 'refix',  fix: R + '/wf_eade8af3-fix_F-settings.json', v1: R + '/wf_eade8af3-verify_F-settings_r1.json', cut: R + '/interrupted/refix_F-settings_r1.txt' },
  'G-panels':   { mode: 'minors', fix: R + '/wf_47458c45-fix_G-panels.json', v1: R + '/wf_eade8af3-verify_G-panels_r1.json' },
  'H-design':   { mode: 'minors', fix: R + '/wf_eade8af3-fix_H-design.json', v1: R + '/wf_eade8af3-verify_H-design_r1.json' },
  'I-build':    { mode: 'fix',    cut: R + '/interrupted/fix_I-build.txt and ' + R + '/interrupted/fix_I-build_attempt1.txt (earlier wave digest: ' + OLD + '/prev/I-build.txt)' },
  'J-media-io': { mode: 'verify', fix: R + '/wf_eade8af3-fix_J-media-io.json', cut: R + '/interrupted/verify_J-media-io_r1.txt' },
}

// Cross-area items reported by other agents, assigned to the owner of the files.
const EXTRA = {
  'A-window': `CROSS-AREA ITEMS ASSIGNED TO YOU: (1) F-06 gate: \`mxr-snapshot check\` FAILs the S48 Settings entries only because of rows removed under D035 and the D030 "Ask" default, so the gate cannot catch real regressions. Add an explicit, documented per-entry deviation mechanism (e.g. compare regions or excluded rects declared on the GalleryEntry with a reason that cites the decision) in the snapshot tool you own, and declare it on the affected Settings entries with the smallest edit in F-settings' SettingsGallery.swift. No global threshold loosening. (2) GalleryRenderTests testShippingWindowMatchesFigmaPlayer6OutsideDocumentedDeviations reports "transport and elapsed time" as review, not pass — find out why and fix the cause (control-bar files belong to B-controls: smallest edit, or report). (3) A-08: the resume toast truncated to "You alr…" at 640 pt with the compact library; the previous refixer was rewriting MXRContinueWatchingToast — check and finish.`,
  'B-controls': `ALSO: the old FAIL of reference C.SeekBar/default — the fixture's playhead sits ~15 pt right of Figma. Decide with evidence whether the fixture's time differs from Figma (then fix the fixture to Figma's values, not product defaults) or the geometry is wrong (then fix the geometry), and make the check pass honestly.`,
  'C-bridge': `ALSO: in the live app Hide UI (⌘\\\\) showed only "Pressed ⌘\\\\" without the action line (B-controls note). The hotkey/OSD action-name feed is yours (MXRHotkeyFeedback.inc, VLCShortcutCatalog): every custom command must produce the two-line action + key OSD.`,
  'D-menus': `CROSS-AREA ITEMS ASSIGNED TO YOU: (1) J-10 renderer wording: PlayerMenus says "Discovering…"/"Discover Renderers" while EffectsSidebars (G-panels file) says "Discovering Destinations…"/"Refresh Destinations". Use the wording Figma/the video shows (else the most Mac-native) in both, with the smallest edit in EffectsSidebars.swift. (2) Lua extension menus: the backend supports menu(forExtension:) and triggerMenu (C-05) but there is no UI entry; add a native View ▸ Extensions submenu in the menu bar if it is straightforward; otherwise explain why not.`,
  'F-settings': `CROSS-AREA ITEMS ASSIGNED TO YOU: C-15 — SettingsExtensionsView lacks Figma's "Advanced Options" bar under "Load add-ons on startup" and shows an ⓘ that Figma does not have; the comment near line 45 ("no Lua extension-dialog provider yet") is stale since C-05 registered the provider.`,
  'G-panels': `CROSS-AREA ITEMS ASSIGNED TO YOU: (1) D-07 remainder: the queue row still uses its own "Add to Playlist…" sheet instead of the shared MXRPlayerMenus.addToPlaylist submenu — share it. (2) S20.Sidebar/subtitles-appearance declares figmaNode 800:1126, which is clipped in renders/Controls.png, so check always FAILs on size — fix the entry so check --all reports no spurious FAIL (without hiding real differences). (3) Make sure the panel test files compile and pass (PanelAuditRegressionTests used the removed MXRPlayerMenus.playlistDestinations; ThemeContrastTests used the removed readableSecondary).`,
  'H-design': `CROSS-AREA ITEM ASSIGNED TO YOU: LibrarySheetView (E-library's LibrarySheets.swift) uses MXRBackdropSurface with D046's darkAqua base inside a native .sheet, so in Light the rename-playlist, rename-stream and failure sheets read as mid grey (~#A8A8A8) instead of a light surface. Fix it the way DialogSupport does (opaque counterpart in Light) or make the base depend on whether the surface sits over video/scrim; smallest edit in LibrarySheets.swift; render it in Light and look.`,
  'I-build': `NOTES FROM OTHER AREAS: install-app.sh failed for B and H at \`codesign --force -s - replacement.app\` (plugins/plugins.dat inside Contents/Frameworks is not code); finalize-app.py was changed afterwards and the 19:40 install passed — confirm the root cause is fixed and covered. Any test that creates an NSWindow and calls close() must set isReleasedWhenClosed = false or xctest crashes with SIGSEGV — fix shared test helpers you own and list offenders. The native "media" suite now needs ffprobe on PATH and previously aborted on the engine assertion pcr_sync.c:268 (J-01 now avoids it with no-forward-pcr) — confirm it runs.`,
}

const RESULT = { type: 'object', properties: {
  status: { type: 'string', enum: ['done', 'partial', 'blocked'] }, summary: { type: 'string' },
  fixed: { type: 'array', items: { type: 'string' } },
  notFixed: { type: 'array', items: { type: 'object', properties: { id: { type: 'string' }, why: { type: 'string' } }, required: ['id', 'why'] } },
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

const areaHeader = (a) => `YOUR AREA: ${a.key}\nYOU OWN (paths relative to ${PKG} unless they start with redesign/): ${a.owns}\nSCOPE: ${a.scope}\nCONFIRMED FINDINGS OF THIS AREA: ${FP}/findings/${a.key}.json (read the "confirmed" array fully).`

const firstPrompt = (a) => {
  const p = PLAN[a.key]
  const extra = EXTRA[a.key] ? `\n${EXTRA[a.key]}` : ''
  if (p.mode === 'fix') return `${CTX}\n${areaHeader(a)}
You are the FIXER of this area. Two earlier attempts were cut off before reporting; digests: ${p.cut}. Their edits are on disk (see git diff a215064366 4c457baa03 -- <your files>). FIRST establish which findings are already done (check the code, not intentions), then fix the rest: all blockers and majors; minors too unless clearly not worth it (say why). Fix root causes, add/adjust focused tests where behaviour changed, run the tooling tests you touch, and run install-app.sh once under the lock to prove the pipeline (do NOT launch the app). Report ids fixed with evidence paths.${extra}`
  if (p.mode === 'refix') return `${CTX}\n${areaHeader(a)}
You are continuing as the FIXER of this area. First fixer's report: ${p.fix}. The independent verifier (round 1) failed the area: ${p.v1} — fix every blocker/major issue in it and the reasonable minor ones. A refixer started on these issues and was stopped at 19:40; digest: ${p.cut}; its edits are in HEAD (git diff 951f073be2 4c457baa03 -- <your files>). FIRST check what it already finished (code, not intentions) and that it is correct, then complete the rest. Prove behaviour with tests that exercise the real path (for bridge/engine behaviour: a headless probe against the real engine build, like ${OLD}/C-bridge-verify-r1/probe/). Real-window checks go to liveChecks.${extra}`
  if (p.mode === 'minors') return `${CTX}\n${areaHeader(a)}
This area PASSED independent verification in round 1 (${p.v1}). You are its FIXER for what is left: every minor issue in that verdict, the notFixed items of the fixer report ${p.fix} that are fixable without the live app, and the cross-area items below. Fix properly, add focused tests where behaviour changes, render and LOOK at visual changes. Live-only items go to liveChecks.${extra}`
  return null
}

const verifyPrompt = (a, cur, round) => {
  const p = PLAN[a.key]
  const prior = [p.v1 && `earlier verdict: ${p.v1}`, p.mode === 'verify' && p.cut && `an earlier verifier was cut off mid-run (digest ${p.cut}; its evidence may be in ${OLD}/${a.key}-verify-r1/ — reuse only after re-checking)`].filter(Boolean).join('; ')
  const extra = EXTRA[a.key] ? `\nCross-area items that were assigned to this area (check them too): ${EXTRA[a.key]}` : ''
  return `${CTX}\n${areaHeader(a)}
You are an INDEPENDENT VERIFIER of this area, round ${round} (not its author; do not edit product code or tests; write only under ${SCR}/${a.key}-verify-r${round}/). ${prior ? 'Context: ' + prior + '.' : ''}
The fixer's latest report: ${typeof cur === 'string' ? cur : JSON.stringify(cur)}
Check EVERY confirmed finding of the area (not only the claimed ones): read the changed code, build, run the targeted tests, render the affected states and LOOK at them next to the Figma renders and key frames; for runtime behaviour trace the code path and, for bridge/engine behaviour, use headless probes against the real engine build. Be skeptical: earlier work in this project often "looked right at first glance but behaved differently from the design", and tests that only pin one-line predicates prove nothing. Also check: no regressions of things listed as done well, ownership respected, tokens only, Swift 6 clean, no engine edits (git diff upstream-base-2026-10-14 -- src lib include modules/gui/macosx must stay empty), no hidden differences via masks/thresholds.${extra}
pass=false only if a blocker or major remains that code, tests or renders can establish. Real-window-only checks go to liveChecks (precise steps + expected result), never into a failed verdict.`
}

const refixPrompt = (a, cur, v) => `${CTX}\n${areaHeader(a)}
You are continuing as the FIXER of this area. Your previous report: ${typeof cur === 'string' ? cur : JSON.stringify(cur)}
An independent verifier found these remaining problems — fix all blocker/major ones and the reasonable minor ones, re-verify, and report:\n${JSON.stringify(v.issues, null, 1)}`

async function runArea(a) {
  const p = PLAN[a.key]
  let cur
  let round
  if (p.mode === 'verify') {
    cur = `the fixer's report is in ${p.fix} (read it)`
    round = 1
  } else {
    cur = await agent(firstPrompt(a), { label: `${p.mode} ${a.key}`, phase: 'Fix', schema: RESULT, ...O })
    if (!cur) return { area: a.key, mode: p.mode, state: 'fixer failed' }
    log(`${a.key}: ${p.mode} ${cur.status} — fixed ${(cur.fixed || []).length}, open ${(cur.notFixed || []).length}`)
    round = p.v1 ? 2 : 1
  }
  const live = [...((cur && cur.liveChecks) || [])]
  const decisions = [...((cur && cur.ownerDecisions) || [])]
  const reports = typeof cur === 'string' ? [] : [cur]
  let last = null
  for (let i = 0; i < 3; i++, round++) {
    const v = await agent(verifyPrompt(a, cur, round), { label: `verify ${a.key} r${round}`, phase: 'Verify', schema: VERDICT, ...O })
    if (!v) return { area: a.key, mode: p.mode, state: 'verifier failed', reports, verdict: last, liveChecks: live, ownerDecisions: decisions }
    last = v
    live.push(...(v.liveChecks || []))
    decisions.push(...(v.ownerDecisions || []))
    log(`${a.key} r${round}: pass=${v.pass} — ${v.summary.slice(0, 160)}`)
    if (v.pass) return { area: a.key, mode: p.mode, state: 'passed', round, reports, verdict: v, liveChecks: live, ownerDecisions: decisions }
    if (i === 2) break
    const next = await agent(refixPrompt(a, cur, v), { label: `refix ${a.key} r${round}`, phase: 'Fix', schema: RESULT, ...O })
    if (!next) return { area: a.key, mode: p.mode, state: 'refixer failed', reports, verdict: v, liveChecks: live, ownerDecisions: decisions }
    cur = next
    reports.push(next)
    live.push(...(next.liveChecks || []))
    decisions.push(...(next.ownerDecisions || []))
  }
  return { area: a.key, mode: p.mode, state: 'not passed after 2 refix rounds', round, reports, verdict: last, liveChecks: live, ownerDecisions: decisions }
}

phase('Fix')
const areaResults = (await pipeline(AREAS, (a) => runArea(a))).filter(Boolean)

const compact = areaResults.map(r => {
  const lastReport = (r.reports || [])[(r.reports || []).length - 1]
  return {
    area: r.area, mode: r.mode, state: r.state,
    fixed: lastReport && lastReport.fixed, notFixed: lastReport && lastReport.notFixed,
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
1. From ${ROOT}: run the full runner \`python3 modules/gui/macosx_redesign/tools/run-swift-tests.py modules/gui/macosx_redesign modules/gui/macosx_redesign/.build\`, tools/gen-tokens.py --check, tools/gen-icons.py --check, every tooling test (tools/test-*.py), and under the lock \`tools/native-tests.py --engine-build ../build/codex-arm64 --suite contracts\` plus the other native suites that exist (list them from native-tests.py; run each). Fix integration breakages (cross-area compile errors, tests invalidated by intended changes, flaky window tests); for a non-trivial failure that belongs to an area, fix it only if the cause is clear and the fix small, otherwise report it with evidence. Confirm \`git diff upstream-base-2026-10-14 -- src lib include modules/gui/macosx\` is empty.
2. Run \`swift run mxr-snapshot check --all\` (or the equivalent the tool offers) and list every FAIL with the entry id and whether it is a documented deviation, a fixture problem or a real difference.
3. Under the lock: build and install with tools/install-app.sh (do NOT launch the app). Then check with mdfind/ls that only /Applications/VLC.app (untouched — compare its modification date with before) and /Applications/VLC Redesign.app exist, and that the build dir has no leftover VLC.app.
4. Release the lock. Report exact commands, pass/fail counts and remaining problems. Outputs under ${SCR}/integration/.`, { label: 'integrate', phase: 'Integrate', ...O, schema: { type: 'object', properties: {
  testsPassed: { type: 'boolean' }, testSummary: { type: 'string' }, nativeSuites: { type: 'string' }, snapshotCheck: { type: 'string' }, installed: { type: 'string' },
  fixesMade: { type: 'array', items: { type: 'string' } }, remainingProblems: { type: 'array', items: { type: 'string' } }, summary: { type: 'string' },
}, required: ['testsPassed', 'testSummary', 'remainingProblems', 'summary'] } })

phase('Parity')
const GROUPS = [
  'Player window: dark, light, Hide UI, fullscreen, windowed thin frame, top bar, traffic lights, cone, PiP placeholder',
  'Control bar and seek bar: every control, hover/pressed states, scrubbing preview, waveform and subtitle-timeline modes, OSD, volume tooltip, resume toast, compact widths',
  'Popups and menus: ⋯ menu, right-click menu and submenus, dropdowns, track popover, speed/HDR/zoom menus, menu bar',
  'Side panels: Subtitles, Audio, Video, Playback tabs, queue, subtitle timeline, effects/filters, presets, metadata overlay',
  'Library: Home, folders and breadcrumb, Music (songs/albums/artists/genres), playlists, search, mini player, empty and loading states, light theme',
  'Settings: every section in dark and light, keyboard shortcuts editor, extensions, profiles',
  'Dialogs: Open Media (file/disc/network/capture), Convert, Stream, Add Subtitles, Media Info, confirmations, modal host',
  'Customization mode, onboarding, design system (icons, accents, typography, colours, materials)',
]
const PARITY = { type: 'object', properties: {
  screens: { type: 'array', items: { type: 'object', properties: { screen: { type: 'string' }, verdict: { type: 'string', enum: ['match', 'minor-diff', 'major-diff', 'missing', 'not-checked'] }, differences: { type: 'string' }, owner: { type: 'string', description: 'area key that owns the fix' }, evidence: { type: 'string' } }, required: ['screen', 'verdict', 'differences'] } },
  summary: { type: 'string' },
}, required: ['screens', 'summary'] }
const parity = await parallel([
  ...GROUPS.map((g, i) => () => agent(`${CTX}
You are a DESIGN-PARITY JUDGE (read-only; outputs only under ${SCR}/parity-${i + 1}/). Screen group: ${g}.
Using redesign/design/SCREENS.md, list every S-id / Figma frame in this group. For each: render the matching gallery entry offscreen (prefer --engine shipping-window where it applies) in the schemes Figma has, and compare with the Figma render and the video key frames — LOOK at them side by side (crop and zoom where needed). Judge strictly: the owner wants a full 1:1 match; a documented decision (DECISIONS.md) is not a difference, but say which decision covers it. For each difference name the owning area (A-window … J-media-io). If something can only be judged in the real window, mark it not-checked and say what to look at. Integration summary: ${integ ? integ.summary : 'integration failed'}.`, { label: `parity ${i + 1}`, phase: 'Parity', ...O, schema: PARITY })),
  () => agent(`${CTX}
You are the COMPLETENESS CRITIC (read-only). Area results: ${JSON.stringify(compact)}\nIntegration: ${JSON.stringify(integ)}\nLive checks collected for the idle-Mac wave: ${JSON.stringify(liveChecks)}
Ask what is still missing for the final product: audit ids neither fixed nor explicitly decided (cross-check both audits and ${FP}/findings/*.json), features from VIDEO_BREAKDOWN.md MUST rules and SCREENS.md that do not exist or do not work end to end, claims nobody verified, important real-window checks missing from the live list, remaining Codex over-engineering or dead code, docs out of date (SCREENS.md statuses, DECISIONS.md, BUILD.md, HANDOFF.md). Produce a prioritized list for the next wave with owners (area keys) and the live checks that must be added.`, { label: 'completeness critic', phase: 'Parity', ...O, schema: { type: 'object', properties: {
    missing: { type: 'array', items: { type: 'object', properties: { priority: { type: 'string', enum: ['P0', 'P1', 'P2'] }, item: { type: 'string' }, evidence: { type: 'string' }, owner: { type: 'string' } }, required: ['priority', 'item'] } },
    addLiveChecks: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
  }, required: ['missing', 'summary'] } }),
])

return {
  areas: compact,
  areaReports: areaResults.map(r => ({ area: r.area, reports: r.reports, verdict: r.verdict })),
  liveChecks, ownerDecisions,
  integration: integ,
  parity: parity.slice(0, GROUPS.length).map((p, i) => p && { group: GROUPS[i], ...p }),
  critic: parity[GROUPS.length],
}
