export const meta = {
  name: 'final-polish-livefix',
  description: 'Fix what the second live run found (2 crashes, 10 majors, minors) plus the close-wave critic and parity items per area, verify independently, integrate and reinstall (no launch), re-judge parity offscreen, and plan the live recheck groups',
  phases: [
    { title: 'Fix', detail: 'Opus medium: one fixer per area' },
    { title: 'Verify', detail: 'Opus medium: independent verifier per area, up to 2 refix rounds' },
    { title: 'Integrate', detail: 'full test runner, generators, native suites, check --all, install-app.sh under native+live locks' },
    { title: 'Parity', detail: 'offscreen re-judge + completeness critic + live recheck planner' },
  ],
}

const OPUS = 'claude-opus-5-5'
const ROOT = '.'
const PKG = ROOT + '/modules/gui/macosx_redesign'
const FP = ROOT + '/redesign/research/final-polish'
const CL = FP + '/results/close'
const LV = FP + '/results/live2'
const RS = FP + '/results/resume'
const LIVEEV = '../build/evidence/final5/live'
const E = '../build/evidence/final6/fix'
const LOCK = FP + '/workflows/lock.sh'
const LIVELOCK = '../build/locks/live.lock'
const O = { model: OPUS, effort: 'medium' }

const CTX = `
PROJECT: native macOS interface (Swift/SwiftUI + AppKit, thin ObjC bridge) for VLC 4 reproducing Juxtopposed's VLC redesign 1:1. Figma = visual truth, the video = behaviour/intent, VLC = semantics. The VLC engine (src/, lib/, include/, other modules) stays untouched. GOAL: the final product — full 1:1 match with Figma and the video, everything working end to end, native Mac feel, fast, no crashes.
CHECKOUT: ${ROOT}, branch claude/final, HEAD 37f35b8a5c. Swift package: ${PKG}.
STATE: offscreen, every area passed verification (561/561 Swift tests, all native suites, mxr-snapshot check --all PASS 26 · REVIEW 70 · FAIL 23). The app installed at 05:41 (this tree) was driven in the REAL WINDOW by a live wave: ${LV}/triage.json (per-area fix list: 2 crash blockers, 10 majors, minors; each with observed/expected/evidence/cause/recheck) and ${LV}/results.json (every check of every group; screenshots and crash reports under ${LIVEEV}/<group>/). THIS WAVE fixes those, plus the close wave's open items: ${CL}/critic.json (missing[] P1/P2 with owner), ${CL}/parity.json (8 judges: screens[] with verdict/owner), ${CL}/areas.json (verdict.open of each area's last verifier, notesForOthers), ${CL}/integration.json (remaining FAILs and warnings). Earlier: ${RS}/*, ${FP}/HANDOFF.md.
LIVE BUGS FIRST: a crash or a broken real-window behaviour outranks any pixel difference. Reproduce each live defect yourself as far as possible without the real window — read the code path, read the crash report (.ips under ${LIVEEV}/ or ~/Library/Logs/DiagnosticReports/VLC Redesign*), drive the model/backend headlessly against the real engine (../build/codex-arm64/vlc and the native test harness) or in an offscreen hosting test — and add a regression test that fails without the fix. Put the real-window recheck into liveChecks.
NO LIVE UI IN THIS WAVE: do NOT launch "/Applications/VLC Redesign.app" or any other app, do NOT send synthetic input, never run osascript activate/open or anything that puts a window on screen or takes focus (the owner may be using the Mac). Offscreen rendering and headless engine probes only.
OWNER DECISIONS: owner-accepted: D041, D045, C-09 (HDR Auto-only), D033 amendment (Font Size "Auto" in the middle). Waiting for the owner (keep the implementation unless it excuses something that can be made to match — then fix it and amend the entry): D042, D044, D046–D057 and every "accepted (agent, …)" amendment, the D030 defaults, and two open design questions the owner must decide — the dialog scrim (no dimming as in the video vs a moderate scrim, D035) and the Customize dialog body opacity (#10 vs Figma #18). Do not change those two; list them in ownerDecisions if you touch the area.
DECISIONS RULE: a difference from Figma is either fixed or covered by a DECISIONS.md entry with evidence. If you keep one, add or amend the entry (smallest edit, re-read the file right before editing — other agents append too; mark it "accepted (agent, 2026-10-17)" and list it in ownerDecisions). Never use a decision to excuse something that can be made to match.
MUST READ: AGENTS.md (hard rules), redesign/docs/DECISIONS.md (D021+, especially D033–D057), redesign/docs/PHILOSOPHY.md, redesign/docs/WORKFLOW.md.
DESIGN SOURCES: redesign/design/figma/renders/*.png, figma_file.json, INDEX.md, ICONS.md; redesign/design/tokens/*; redesign/design/spec/spec-part1.md + spec-part2.md; redesign/docs/design/VIDEO_BREAKDOWN.md; redesign/design/SCREENS.md; local video key frames ../reference/video/key-frames/ (+INDEX.md) and transcript.txt (never commit reference material).
PARALLEL WORK: up to 10 area agents edit this checkout at once, each owning specific files. Do not edit files you don't own; if a fix truly needs another area's file, make the smallest edit to just those lines, re-read right before editing, and list it in editsOutsideOwnership. Never revert or reformat other agents' work. Do NOT git commit/stash/reset/checkout/restore/clean — the orchestrator commits.
BUILD/TEST: from ${PKG}: \`swift build\` (shared .build; concurrent builds wait — normal; if it fails in a file you don't own, wait 2–3 min and retry). Targeted tests only (\`swift test --filter <Suite>\`); the integrator runs the full runner. If the test target keeps failing to compile in another area's file for >15 min, fix it only if trivial and report it; otherwise run your suites in an isolated copy under ${E}/<your-label>/pkg. Visual tool: \`swift run mxr-snapshot help\`. LOOK at renders yourself next to Figma renders and key frames. Outputs only under ${E}/<your-label>/ (durable, outside the repo); keep them small.
NATIVE LOCK: \`${LOCK} acquire <your-label>\` … \`${LOCK} release\` (default lock path) around anything that runs make in ../build/codex-arm64 and around tools/native-tests.py suites. Always release, also on failure; hold ≤ 30 min. Only the integrator installs. Headless engine probes with ../build/codex-arm64/vlc -I dummy on ../build/media/ (60 s S01E01/S01E02, 10 min S01E03, with .srt) need no lock. NEVER touch /Applications/VLC.app and never create other VLC bundles.
QUALITY BAR: premium Mac app. Tokens only (Theme.*), no literal design values in views. Swift 6 strict-concurrency clean (product, install build and test target). Fix root causes, prefer deleting broken complexity over adding layers; no masks/threshold tweaks that hide differences. Gallery fixtures must not override product defaults (D030). Tests must check behaviour or what is drawn; a regression test must fail without the fix — check that yourself in an isolated copy.
`

const AREAS = [
  { key: 'A-window', owns: 'Sources/MXRUI/MXRAppView.swift; Sources/MXRUI/Player/{PlayerView,PlayerBars,PlayerChrome,PlayerGeometry,PlayerMetrics}.swift; Sources/MXRCore/Models/InterfaceModel.swift; Sources/MXRPlugin/{MXRAppController,MXRNativeWindowServices,MXRVideoHost,MXRLaunchFileOpening,MXRFullscreenMagnification}.swift; Sources/MXRGallery/**; Sources/MXRSnapshot/**; Sources/MXRGalleryCatalog/{GalleryCatalog,FigmaDeviation}.swift and Entries/{PlayerGallery,AppGallery,ShippingGallery,ScaffoldGallery,SettingsFigmaDeviations}.swift; Tests/MXRUISnapshotTests/FigmaDeviationTests.swift; the resume toast (MXRContinueWatchingToast)',
    scope: 'Window chrome and composition, minimum size, bar reveal/hide, fullscreen, PiP, panel placement and transitions over the video, Hide UI, shipping-window snapshot fidelity, the snapshot tool and the documented-deviation mechanism.' },
  { key: 'B-controls', owns: 'Sources/MXRUI/Player/{PlayerControls,NativeSeekProgress,PausedSeekStill,ConeScrollHandler,PlayerPreferences,MXROSDView}.swift; Sources/MXRDesign/Typography/OSDTypography.swift; Sources/MXRDesign/Focus/**; Sources/MXRCore/Models/{AppearanceAndPreviewModels,PlaybackClock,PlayerModel}.swift; Sources/MXRCore/Values/{PlayerValues,VideoClickTiming}.swift; Sources/MXRVLCBackend/VLCThumbnailBackend.swift; module/bridge/{MXRThumbnailServices,MXRAudioServices}.{h,m}; Sources/MXRPlugin/MXRNowPlayingClockGate.swift',
    scope: 'Control bar and seek bar: every control and state, repeat/shuffle state, scrubbing and thumbnails, waveform, subtitle-timeline mode, paused still, OSD, volume, focus indication, time labels.' },
  { key: 'C-bridge', owns: 'module/bridge/{MXRServicesBridge.m,MXRPlayerBridge.m,MXRMediaServices.*,MXRSubtitleCueServices.*,MXRDialogServices.*,MXRInterfaceBridge.m,MXRPlatformServices.m,MXREffectsServices.*,MXRHotkeyFeedback.inc}; module/*.m and module/*.h; Sources/MXRVLCBackend/{VLCBackends,VLCBridgeSession,VLCPlayerBackend,VLCQueueBackend,VLCServiceBackends,VLCServiceTransport,VLCShortcutCatalog,VLCTypedServiceWire,VLCSettingsBackend,VLCSubtitleSafeInsetFeed}.swift; Sources/MXRBridgeAPI/**; Sources/MXRCore/Models/{ServiceModels,QueueModel}.swift; Sources/MXRCore/Values/{ServiceValues,QueueValues,MediaDevice}.swift; Sources/MXRCore/Backends/** except QueueAndLibraryBackends.swift; Sources/MXRMockBackend (non-library, non-output parts)',
    scope: 'Engine bridge correctness, thread safety and performance: command/event flow, effects/filter writes, repeat/queue modes, shutdown and quit latency, subtitles, Lua extensions, typed service wire, the mock backend.' },
  { key: 'D-menus', owns: 'Sources/MXRDesign/Popup/**; Sources/MXRUI/Player/PlayerMenus.swift; Sources/MXRPlugin/{MXRNativeMenus,MXRKeyRouting,MXRRemoteControl,MXRNativeRecents}.swift; Sources/MXRCore/Values/ShortcutValues.swift; Sources/MXRCore/App/AppCommand.swift and the shortcut/command parts of AppModel.swift; Sources/MXRGalleryCatalog/Entries/MenusGallery.swift',
    scope: 'Popup menus, dropdowns, submenus, right-click menus, ⋯ menu, menu bar and its enabled states, shortcuts and key routing, media keys, recents, menu accessibility.' },
  { key: 'E-library', owns: 'Sources/MXRUI/Library/**; Sources/MXRUI/Dialogs/LibraryDialogs.swift; module/bridge/{MXRLibraryServices,MXRDiscoveryServices}.{h,m}; Sources/MXRVLCBackend/VLCLibraryBackend.swift; Sources/MXRCore/Models/LibraryModel.swift; Sources/MXRCore/Values/{LibraryValues,MediaItem}.swift; Sources/MXRCore/Backends/QueueAndLibraryBackends.swift; library parts of Sources/MXRMockBackend; Sources/MXRGalleryCatalog/Entries/LibraryGallery.swift; Tests/Native*Library*.m',
    scope: 'Media library: Home, folders + breadcrumb, Music, Network, playlists, selection and keyboard navigation, context menus, mini player, compact and full layouts, light and dark.' },
  { key: 'F-settings', owns: 'Sources/MXRUI/Settings/**; Sources/MXRUI/Dialogs/{DialogInput,DialogMenu,DialogSupport,MXRDialogHost,MediaInfoDialogs,AddSubtitlesView}.swift; Sources/MXRPlugin/{MXRNativePresentations,MXRNativePreferences}.swift; module/bridge/MXRAudioPreferenceServices.{h,m}; Sources/MXRCore/Settings/**; Sources/MXRCore/Models/SettingsModel.swift; Sources/MXRCore/Values/SettingsValues.swift; Sources/MXRCore/Stores/{AppStores,PresetStore}.swift; Sources/MXRCore/App/AppModel+Preferences.swift; Sources/MXRCore/Resources/settings-map.json5; Sources/MXRGalleryCatalog/Entries/{SettingsGallery,DialogsGallery}.swift',
    scope: 'Settings, profiles, keyboard shortcuts editor, extensions page, modal dialog host, dialog buttons, media info, Add Subtitles, confirmations.' },
  { key: 'G-panels', owns: 'Sources/MXRUI/Panels/**; Sources/MXRCore/Models/{EffectsModels,TracksModel}.swift; Sources/MXRCore/Values/Effects.swift; Sources/MXRGalleryCatalog/Entries/PanelsGallery.swift',
    scope: 'Side panels and popovers and their open/close motion: Subtitles/Audio/Video/Playback tabs, filter cards and sliders, track popover, queue panel (drops, keyboard), bookmarks, subtitle timeline, presets, metadata overlay.' },
  { key: 'H-design', owns: 'Sources/MXRDesign/{Theme,Generated,Materials,Icons}/** and Sources/MXRDesign/*.swift root files; Sources/MXRDesign/Typography/** except OSDTypography.swift; redesign/design/tokens/**; tools/gen-tokens.py; tools/gen-icons.py; Sources/MXRUI/Customization/**; Sources/MXRPlugin/MXRFirstLaunchOnboarding.swift; Sources/MXRCore/Stores/LayoutStore.swift; Sources/MXRGalleryCatalog/Entries/{CustomizationGallery,DesignAccentsGallery,DesignColorsGallery,DesignGallerySupport,DesignIconsGallery,DesignThemeGallery,DesignTypographyGallery}.swift',
    scope: 'Design system (tokens, icons, materials, accents, window controls), customization mode (Esc, undo, video framing), onboarding.' },
  { key: 'I-build', owns: 'tools/** except gen-tokens.py and gen-icons.py; Makefile.am; Package.swift; module/tests/**; module/bridge/tests/**; test-runner infrastructure and shared helpers under Tests/; redesign/docs/{BUILD,WORKFLOW}.md; redesign/design/SCREENS.md; redesign/research/final-polish/HANDOFF.md; redesign/research/audits/**; redesign/research/final-polish/workflows/*.sh; dead code in files no other area owns',
    scope: 'Build, packaging, install, native test gates, test runner and test-target warnings, the snapshot reference crops, docs that describe the build, the screen status, the audits and the handoff, dead code.' },
  { key: 'J-media-io', owns: 'Sources/MXRUI/Dialogs/OpenMediaDialogs.swift; Sources/MXRVLCBackend/{VLCOutputBackend,VLCRendererBackend}.swift; Sources/MXRCore/Models/{OutputModel,RendererModel}.swift; Sources/MXRMockBackend/MockOutput.swift; output/renderer parts of module/bridge/MXRMediaServices.m; Sources/MXRDesign output dialog metrics (OutputDialogMetrics.swift)',
    scope: 'Open Media (file/disc/network/capture), Convert and Stream (profiles, output jobs, overwrite flow, pacing, states, real output files), renderers.' },
]

const SPECIFIC = {
  'A-window': `LIVE MAJOR: the 480×270 minimum window size is not enforced — enforce it at the NSWindow level and test. LIVE minors: the video rect shifts and stretches after a Hide UI round trip; Light and Dark place the picture differently (Dark's 10 pt frame starts 1 pt lower, picture ~2.5 pt narrower) — make them identical per Figma; Customize switches the paused video to aspect-fill and crops it (with H-design — find which side owns the switch and fix it there). With G-panels: right panels and the track popover close instantly with no fade-out while menus and dialogs fade (owner complaint C4) — if the panel host transition lives in MXRAppView it is yours: one consistent open/close motion for every overlay, timed from the video. CRITIC: P1 S72.Window/light and S72.App/light FAIL on the playing E04 row with no deviation — add the honest D051 deviation or fix; P1 regression tests that do not fail without their fix (WindowFinalPolishTests.testNarrowResumeToastUsesTheShortLabelInsteadOfTruncating; the onChange reconcile wiring) — make them real; P2 Hide UI loses a library that yielded to a panel (D057 says it comes back) — fix; ContinueButtonStyle changes only on isPressed while video 14m09.8 shows it darkened on hover — fix.`,
  'B-controls': `LIVE MAJOR (with C-bridge): Repeat One does not loop a single item — make the UI state and the command right end to end (C-bridge fixes the backend part). CRITIC P2: D056's music-bar tint bullet probably excuses a fixable difference (the backdrop above the bar is black in both Figma and the render; style 1702:4100 at 95 % over black) — fix and amend D056; PlayerMenus text menus (speed, HDR, zoom) and the compact overflow '⋯' still use .buttonStyle(.plain) press dimming — use the Figma hover/press states (D-menus owns PlayerMenus.swift: coordinate, smallest edit); Player - Light draws the gear with Dark/FG/A2 (partial conversion) — record it like D049 or match; arrow presses the demux handles (DVD NAV, 360° viewpoint) leave a pending OSD slot — fix.`,
  'C-bridge': `LIVE BLOCKER: crash on a fast Brightness drag in the Essential card — stack MXREffectsServices writeOptions → var_SetChecked → TriggerFilterCallback (crash reports under ${LIVEEV}/6-panels/ and ~/Library/Logs/DiagnosticReports/). Find the root cause (writes from the wrong thread, missing hold on the vout/filter, racing filter-chain rebuilds) and fix it in the bridge; add a headless stress test against the real engine (rapid writes while playing) that crashes or fails without the fix. LIVE MAJOR: Repeat One does not loop a single item — fix the queue/player playback mode path and test it headless against the real engine (with B-controls for the UI). LIVE minor: a subtitle font-size change does not re-render the cue already on screen — check what VLC can do (re-applying text renderer options) and fix or record it. CRITIC: the deferred MXRServicesBridge.m rewrite — do it now only if it clearly pays off; the wrong chapter-key OSD comment; make your ObjC files warning-free (unused 'stop' at MXRServicesBridge.m ~602, the older ones in MXRDialogServices.m); review the MockSettings fractional-step change in your file.`,
  'D-menus': `LIVE minors: "Keyboard Shortcuts…" stays enabled in the menu bar while Settings is open (other modal items disable) — fix; the renderer wording differs ("This Mac" vs "Local") — use one, VLC's own string. With E-library: in the compact library list ↓ lowered the player volume instead of moving the selection — key routing must give arrow keys to the focused library list/grid (test with real NSEvents in a hosting test). CRITIC: the repo-marker search loop never ends at '/' (deletingLastPathComponent) — fix; tests that read src/libvlc-module.c and module/MXRAppOptions.inc through #filePath fail in an isolated copy — make them robust.`,
  'E-library': `LIVE BLOCKER: crash when playing an http Network item from its card — SwiftUI TooltipBridge hit-test on a freed responder (crash reports under ${LIVEEV}/7-library/ and ~/Library/Logs/DiagnosticReports/): find which view's tooltip (.help) outlives its responder (a card torn down while hovered when playback starts), fix the root cause and add a test. LIVE MAJORS: arrow keys never move the library selection in the full-library grid or the compact list (↓ even lowered the volume; Shift+↓ works) — fix with D-menus' key routing and add view-level tests that send real key events; the full-library mini player does not scale with the window — fix per Figma. PARITY MAJOR (${CL}/parity.json): S46 mini player hover in Light — the over-video controls (× close, pop-out, ⏮ ▶ ⏭) are tinted fg1, near-black in Light, over the dark video, so they are invisible; Figma draws them white — fix. LIVE minors: the breadcrumb at ~680 pt shows only '…' and drops the current folder (the code comment intends a truncated current crumb); Light compact library current crumb FG/A2 instead of FG/1; the library polish items in the triage. With G-panels: dragging a library row onto the queue replaced the queue and played the row — check your drag payload. With J-media-io: Convert/Stream jobs mark the source as played — the library must not record watch state for output jobs. CRITIC P2: D039 says songs take no audio track but the file menu's Add Audio Tracks is enabled for every file — make code and decision agree; libraryHeaderDarkStyle also applies in the full-window library in Light — check against Figma.`,
  'F-settings': `LIVE minors: Additional command line options "--sub-margin 40" is applied but has no visible effect — find how the extra args reach VLC and make them work (or say in the UI when they take effect); compact dialogs sit flush under the top bar in the real window (no panelInset) although the offscreen render had 20 pt — find the real-window difference and fix. OWNER QUESTION (do not change): the dialog scrim (D035). CRITIC: S54 '0.5'/'1.75' labels ~1.5 pt off (Figma spreads 26 pt label boxes space-between) — match exactly, and make the S54 label test guard drawn pixels; Settings › General accent swatches draw the dark #D37918 in Light while onboarding uses Light/Accent/Main — unify per D049; at 480 pt keeping 'Always starts at:' on one line made the 'Startup volume' label wrap — fix both; regression tests in your area that do not fail without their fix.`,
  'G-panels': `LIVE MAJOR (owner complaint C4): the track popover, the settings sidebar and the queue close instantly with no fade-out while menus and dialogs fade — give every panel and popover the same open/close motion as the video (with A-window if the transition is in MXRAppView); test the transition (e.g. the view stays in the tree during the exit animation). LIVE MAJORS: bookmarks silently fail for media not in the media library (⌘B on a file opened directly) — make them work for any media or show why, and test; dragging a library row onto the queue replaced the queue and played the row instead of inserting at the drop point — fix the drop handler and test it. With C-bridge: the Essential card crash on a fast Brightness drag — also coalesce slider writes on the UI side (the root-cause fix is in the bridge). LIVE minors: the panel/menu polish items in the triage. CRITIC: Equalizer Preamp thumb position vs Figma (fix or a D054 line); D054 deviations that leave out whole slider rows (25 % of the compressor entry) — narrow them; Light screen-blend tick colour; the −4 s thumb 0.5 pt.`,
  'H-design': `LIVE: Customize — Esc does not close it and there is no undo (the video shows Cancel/Save; make Esc = Cancel and support ⌘Z inside the editor if the video or macOS convention calls for it); Customize switches the paused picture to aspect-fill and crops it (with A-window). OWNER QUESTION (do not change): the Customize dialog body opacity (#10 vs Figma #18). CRITIC: S71 mixes two keycap styles on one screen — use one; Light accent swatches (with F-settings); the traffic-light colours and geometry are hand-written constants in a Theme file — generate them from the tokens JSON; the 11 onboarding FAILs that come only from a 1090×7 pt strip at the bottom frame edge (Figma crop edge alpha) — fix with I-build in the mxr-snapshot reference handling so the verdicts are honest.`,
  'I-build': `CRITIC: the onboarding FAILs from the 1090×7 pt bottom strip — fix the mxr-snapshot reference crop/alpha handling (with H-design) so these entries are judged on content; make the test target warning-free (28 warnings: accessibilitySetValue deprecated ×8, unused lets ×17, ?? on a non-optional, 'mutated after capture by sendable closure' ×3 — smallest edits in other areas' test files are fine, list them); the frozen-tree no-op make re-measure (make twice on the committed tree under the native lock); the tools test whose name claims no command runs — make it assert that; SCREENS.md 'Parity · live' must come from the newest results (${CL}/parity.json and ${LV}) — update the generator inputs and regenerate; redesign/research/audits: update the status of every audit id in AUDIT_FIXES_2026-10-15.md (fixed / decided / open) from the code and DECISIONS; HANDOFF.md: add the close wave (37f35b8a5c), the live2 results, this wave, and the full pending-owner list (D042, D044, D046–D057, every agent amendment, the D030 defaults, the scrim and Customize-opacity questions).`,
  'J-media-io': `LIVE MAJORS: the Convert "already exists" alert's Replace does nothing — the isPresented setter calls keepExistingFile() before the Replace action runs (OpenMediaDialogs.swift ~530 with replace() ~450) — fix and add a test that fails without the fix; the HTTP stream is not paced to real time (the output runs as fast as it can) — find how VLC's own Stream dialog paces an http output (sout chain / input options) and do the same, verify headless with the real engine; Convert and Stream jobs mark the source as played in the media library — output jobs must not change watch state (with E-library). With E-library: the crash when playing an http Network item from its card. LIVE minors: the media I/O polish items in the triage. CRITIC: the preferredSize test is not @MainActor; no test covers "Replace is not undone afterwards"; disabled dropdown text FG/A4 on the well; Light segmented controls in dialogs use the Settings well — check against Figma.`,
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

const header = (a) => `YOUR AREA: ${a.key}\nYOU OWN (paths relative to ${PKG} unless they start with redesign/): ${a.owns}\nSCOPE: ${a.scope}`
const workList = (a) => `WORK LIST OF ${a.key}:
(a) every fixes[] item in ${LV}/triage.json whose area mentions "${a.key}" (blockers and majors first), and every FAIL in ${LV}/results.json whose area or suspected cause is yours;
(b) every missing[] item in ${CL}/critic.json whose owner mentions ${a.key};
(c) every screens[] item in ${CL}/parity.json whose owner mentions "${a.key}" with verdict major-diff, minor-diff or missing;
(d) the open issues of your area's last verifier (${CL}/areas.json, entry "${a.key}", verdict.open) and items other areas left for you (notesForOthers / notFixed naming ${a.key});
(e) specifically: ${SPECIFIC[a.key]}`
const howToFix = (a) => `Fix every item at the root cause (crashes, then live majors, then the rest). For a live defect: reproduce it headlessly or offscreen first where you can, then fix, then show the regression test fails without the fix. For a visual item: render before and after and LOOK next to the Figma render and the key frame; evidence under ${E}/${a.key}/. For a difference you keep, make sure a decision covers it. Report every item of the work list: fixed (with evidence), kept with which decision, or not fixed and why; put the real-window recheck of every live item into liveChecks.`

const fixPrompt = (a) => `${CTX}\n${header(a)}\n${workList(a)}\nYou are the FIXER of this area. ${howToFix(a)}`
const verifyPrompt = (a, cur, round) => `${CTX}\n${header(a)}\n${workList(a)}
You are an INDEPENDENT VERIFIER of this area, round ${round} (not its author; do not edit product code, tests or docs; write only under ${E}/${a.key}-verify-r${round}/).
The fixer's latest report: ${JSON.stringify(cur)}
Check EVERY item of the work list, not only the claimed ones. For each live defect: read the crash report or the live evidence, read the fix, and confirm the regression test reproduces the original failure (revert the fix in an isolated copy under your folder — never in the shared tree — and watch the test fail). Build, run the targeted tests, render the affected states and LOOK at them next to Figma. Check each new or amended DECISIONS entry. Also: no regressions (re-render neighbouring entries, rerun neighbouring suites), ownership respected, tokens only, Swift 6 clean, engine untouched (\`git diff upstream-base-2026-10-14 -- src lib include modules/gui/macosx\` empty), no masks/thresholds hiding differences.
pass=false only if a blocker or major remains that code, tests or renders can establish (a crash fix without proof, or a decision that excuses a fixable difference, is a major). Real-window-only checks go to liveChecks.`
const refixPrompt = (a, cur, v) => `${CTX}\n${header(a)}\n${workList(a)}
You are continuing as the FIXER of this area. Your previous report: ${JSON.stringify(cur)}
An independent verifier found these remaining problems — fix all blocker/major ones and the reasonable minor ones, re-verify, and report (cumulatively):\n${JSON.stringify(v.issues, null, 1)}`

async function runArea(a) {
  let cur = await agent(fixPrompt(a), { label: `fix ${a.key}`, phase: 'Fix', schema: RESULT, ...O })
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
    filesChanged: lastReport && lastReport.filesChanged,
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
1. From ${ROOT}: full runner \`python3 modules/gui/macosx_redesign/tools/run-swift-tests.py modules/gui/macosx_redesign modules/gui/macosx_redesign/.build\` (run it twice), tools/gen-tokens.py --check, tools/gen-icons.py --check, every tools/test-*.py, and under the native lock every native suite of tools/native-tests.py --engine-build ../build/codex-arm64 (audio 5 times; report pass counts) including any new crash/stress tests. Fix integration breakages; for a non-trivial failure that belongs to an area, fix it only if the cause is clear and the fix small, otherwise report it with evidence. Count compiler warnings in the product, the install build and the test target. Confirm \`git diff upstream-base-2026-10-14 -- src lib include modules/gui/macosx\` is empty.
2. \`.build/debug/mxr-snapshot check --all\`: compare with the 37f35b8a5c wave (PASS 26 · REVIEW 70 · FAIL 23; ${CL}/integration.json) and list every changed verdict and every remaining FAIL with its reason.
3. Install: acquire the native lock (\`${LOCK} acquire integrate\`), THEN the live lock (\`MXR_LOCK_DIR=${LIVELOCK} ${LOCK} acquire integrate\`). Make sure "VLC Redesign" is not running (pgrep -x "VLC Redesign"; if it is, do not kill it — release the live lock, wait 5 min, retry; after 30 min report it). Install with tools/install-app.sh (do NOT launch). Check only /Applications/VLC.app (untouched, mtime 1743527633) and /Applications/VLC Redesign.app exist, 0 Swift warnings in the install build, no leftover VLC.app in the build dir. Record the new bundle mtime (stat -f %m).
4. Release the live lock, then the native lock. Report exact commands, counts and remaining problems. Outputs under ${E}/integration/.`, { label: 'integrate', phase: 'Integrate', ...O, schema: { type: 'object', properties: {
  testsPassed: { type: 'boolean' }, testSummary: { type: 'string' }, nativeSuites: { type: 'string' }, warnings: { type: 'string' }, snapshotCheck: { type: 'string' }, installed: { type: 'string' }, bundleMtime: { type: 'string' },
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
const LIVEGROUPS = { type: 'object', properties: {
  liveGroups: { type: 'array', items: { type: 'object', properties: { group: { type: 'string' }, checks: { type: 'array', items: { type: 'object', properties: { id: { type: 'string' }, area: { type: 'string' }, ownerComplaint: { type: 'boolean' }, why: { type: 'string' }, steps: { type: 'string' }, expect: { type: 'string' } }, required: ['id', 'steps', 'expect'] } } }, required: ['group', 'checks'] } },
  ownerSteps: { type: 'array', items: { type: 'string' } },
  summary: { type: 'string' },
}, required: ['liveGroups', 'summary'] }
const parity = await parallel([
  ...GROUPS.map((g, i) => () => agent(`${CTX}
You are a DESIGN-PARITY JUDGE (read-only; outputs only under ${E}/parity-${i + 1}/). Screen group: ${g}.
The previous judge of this group: ${CL}/parity.json item ${i} — re-check every screen it listed (especially its major-diff, minor-diff and missing items) and anything it missed. Render each matching gallery entry offscreen (prefer --engine shipping-window where it applies) in the schemes Figma has, and compare with the Figma render and the video key frames — LOOK at them side by side. Judge strictly; a documented decision is not a difference only if it is justified — say which decision and whether you agree. Name the owning area for each difference. Real-window-only aspects: not-checked with what to look at. Integration summary: ${integ ? integ.summary : 'integration failed'}.`, { label: `parity ${i + 1}`, phase: 'Parity', ...O, schema: PARITY })),
  () => agent(`${CTX}
You are the COMPLETENESS CRITIC (read-only; outputs only under ${E}/critic/). Area results: ${JSON.stringify(compact)}\nIntegration: ${JSON.stringify(integ)}\nPrevious critic: ${CL}/critic.json. Live triage: ${LV}/triage.json.
What is still missing for the final product? Live defects not fixed or fixed without proof, previous critic items not closed, audit ids neither fixed nor decided, VIDEO_BREAKDOWN.md MUST rules not working end to end, agent decisions that excuse fixable differences, docs out of date, anything that would embarrass the project when it is published (crashes, broken core flows, missing build instructions).`, { label: 'completeness critic', phase: 'Parity', ...O, schema: { type: 'object', properties: {
    missing: { type: 'array', items: { type: 'object', properties: { priority: { type: 'string', enum: ['P0', 'P1', 'P2'] }, item: { type: 'string' }, evidence: { type: 'string' }, owner: { type: 'string' } }, required: ['priority', 'item'] } },
    summary: { type: 'string' },
  }, required: ['missing', 'summary'] } }),
  () => agent(`You are the LIVE RECHECK PLANNER (read-only; write only under ${E}/live-plan/). Repo ${ROOT} (read AGENTS.md). Build ONE deduplicated, ordered live checklist for the next real-window wave on the build this wave installs. Merge:
(1) ${CL}/live-recheck.json (groups R0–R11, planned after the close wave; most never ran),
(2) every fix in ${LV}/triage.json (use its "recheck" steps) and its notRun list,
(3) the checks of ${RS}/live-groups.json groups 3, 4 and 5 (never run) and the NOT-RUN checks of groups 0, 1 and 2 in ${LV}/results.json (group 1 holds the owner complaint A-fs-exit-windowed and the fullscreen top-edge checks — high priority),
(4) the live checks this wave collected: ${JSON.stringify(liveChecks)}.
Drop checks that already PASSED in ${LV}/results.json on the 05:41 build when nothing in this wave touched their code (area results: ${JSON.stringify(compact.map(c => ({ area: c.area, filesChanged: c.filesChanged })))}). Put the owner's complaints C1–C7 (C1 no focus box around volume/seek; C2 track popover anchored bottom-right above the bar; C3 single 40 pt top bar, traffic lights centred, cone right after them; C4 consistent open/close motion, Esc and click-outside close without pausing; C5 sidebar overlays the video, not shrunk; C6 scrubbing updates playhead/label/preview continuously; C7 single volume indicator, no VLC core OSD) first with ownerComplaint true, then the crash and major rechecks, then the rest. Facts for the steps: display 1728×1117 pt; media in ../build/media/ (60 s S01E01/S01E02, 10 min S01E03, with .srt); never change macOS system settings (those checks go to ownerSteps); never move or delete the owner's folders or data. Group so one agent can run a group in 20–30 minutes; at most 12 groups.`, { label: 'live planner', phase: 'Parity', ...O, schema: LIVEGROUPS }),
])

return {
  areas: compact,
  areaReports: areaResults.map(r => ({ area: r.area, reports: r.reports, verdict: r.verdict })),
  liveChecks, ownerDecisions,
  integration: integ,
  parity: parity.slice(0, GROUPS.length).map((p, i) => p && { group: GROUPS[i], ...p }),
  critic: parity[GROUPS.length],
  livePlan: parity[GROUPS.length + 1],
}
