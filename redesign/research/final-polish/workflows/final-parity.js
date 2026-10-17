export const meta = {
  name: 'final-polish-parity',
  description: 'Close the remaining Figma-parity differences and polish items per area (parity judges, completeness critic, verifier minors, owner decisions), verify each area independently, integrate and reinstall, then re-judge parity offscreen; no live UI',
  phases: [
    { title: 'Fix', detail: 'Opus medium: one fixer per area with its parity/critic/minor work list' },
    { title: 'Verify', detail: 'Opus medium: independent verifier per area, up to 2 refix rounds' },
    { title: 'Integrate', detail: 'full test runner, generators, native suites (audio repeated), check --all, install-app.sh' },
    { title: 'Parity', detail: 'offscreen re-judge of all screen groups + completeness critic' },
  ],
}

const OPUS = 'claude-opus-5-5'
const ROOT = '.'
const PKG = ROOT + '/modules/gui/macosx_redesign'
const FP = ROOT + '/redesign/research/final-polish'
const FIN = FP + '/results/finish'
const SCR = '<scratch>'
const PREV = '<scratch>'
const T = PREV + '/tools'
const O = { model: OPUS, effort: 'medium' }

const CTX = `
PROJECT: native macOS interface (Swift/SwiftUI + AppKit, thin ObjC bridge) for VLC 4 reproducing Juxtopposed's VLC redesign 1:1. Figma = visual truth, the video = behaviour/intent, VLC = semantics. The VLC engine (src/, lib/, include/, other modules) stays untouched. GOAL: the final product — full 1:1 match with Figma and the video, everything working end to end, native Mac feel, fast.
CHECKOUT: ${ROOT}, branch claude/final, HEAD fae8f04dc0 ("final-polish: finish the interrupted wave"). Swift package: ${PKG}.
STATE: every area passed independent verification in the previous wave; 431/431 Swift tests, native suites and install are green. THIS WAVE closes what is left: Figma-parity differences found by 8 offscreen parity judges, the completeness critic's list and the verifiers' open minor issues. Results of the previous wave (read what concerns you): ${FIN}/parity.json (per screen group: screens[] with verdict, differences, owner, evidence), ${FIN}/critic.json (missing[] with priority/owner), ${FIN}/areas.json (per area: verdict.open = open minor issues), ${FIN}/area-<area>.json (full fixer reports and verdicts), ${FIN}/integration.json (test/install/check --all status; check --all logs in ${PREV}/integration/). Evidence renders of that wave: ${PREV}/<label>/ and ${PREV}/parity-<n>/. Earlier context: ${FP}/HANDOFF.md, ${FP}/findings/<area>.json.
OWNER DECISIONS (2026-10-16, already in DECISIONS.md): D041 accepted (bars stay visible while paused); D045 accepted (extensions page per D035, opaque light dialogs, track numbers from 1); C-09: HDR stays Auto-only (no Off); D033 amended: the relative subtitle Font Size slider follows Figma 804:1341 with "Auto" in the middle (G-panels implements it). Still waiting for the owner (keep the implementation, list in ownerDecisions): agent-written D042, D044, D046, D047, the D030 product defaults (Continue "Ask", Play locally OFF, ~/Movies) and any new decision you write.
DECISIONS RULE: a difference from Figma is either fixed or covered by a DECISIONS.md entry with evidence (video frame, VLC capability, macOS convention). If you keep a difference, add or amend the entry (smallest edit, re-read the file right before editing — other agents append too; mark it "accepted (agent, 2026-10-17)" and list it in ownerDecisions). Never use a decision to excuse something that can be made to match.
HISTORY: 5ac081046e wave 1; a215064366 Codex audit fixes (audits in redesign/research/audits/); 951f073be2/4c457baa03/fae8f04dc0 final-polish.
MUST READ: AGENTS.md (hard rules), redesign/docs/DECISIONS.md (D021+, especially D033–D047), redesign/docs/PHILOSOPHY.md, redesign/docs/WORKFLOW.md.
DESIGN SOURCES: redesign/design/figma/renders/*.png, figma_file.json, INDEX.md, ICONS.md; redesign/design/tokens/*; redesign/design/spec/spec-part1.md + spec-part2.md; redesign/docs/design/VIDEO_BREAKDOWN.md; redesign/design/SCREENS.md (S-ids); local video key frames ../reference/video/key-frames/ (+INDEX.md) and transcript.txt (never commit reference material).
PARALLEL WORK: up to 10 area agents edit this checkout at once, each owning specific files. Do not edit files you don't own; if a fix truly needs another area's file, make the smallest edit to just those lines, re-read right before editing, and list it in editsOutsideOwnership. Never revert or reformat other agents' work. Do NOT git commit/stash/reset/checkout/restore/clean — the orchestrator commits.
BUILD/TEST: from ${PKG}: \`swift build\` (shared .build; concurrent builds wait — normal; if it fails in a file you don't own, wait 2–3 min and retry). Targeted tests only (\`swift test --filter <Suite>\`); the integrator runs the full runner. If the test target keeps failing to compile in another area's file for >15 min, fix it only if trivial and report it; otherwise run your suites in an isolated copy under ${SCR}/<your-label>/pkg. Visual tool: \`swift run mxr-snapshot help\` (list/render/ref/compare/check; --engine shipping-window renders the real window composition offscreen; documented deviations live in Sources/MXRGalleryCatalog/FigmaDeviation.swift and Entries/SettingsFigmaDeviations.swift). Put outputs only under ${SCR}/<your-label>/. LOOK at renders yourself (Read shows PNGs) next to Figma renders and key frames — numbers alone are not enough.
NO LIVE UI IN THIS WAVE: do NOT launch "/Applications/VLC Redesign.app", do NOT send synthetic input, do NOT run wait-idle.sh. A live-acceptance wave runs afterwards on an idle Mac; put every check that needs the real window into liveChecks (exact steps + expected result). A pending live check is never a reason for a failed verdict.
NATIVE LOCK: \`${T}/lock.sh acquire <your-label>\` … \`${T}/lock.sh release\` around anything that runs make in ../build/codex-arm64, around tools/native-tests.py suites, and around tools/install-app.sh (install only by the integrator; see redesign/docs/BUILD.md; export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" if make cannot find libSystem). Always release, also on failure; hold ≤ 30 min. Headless engine probes with ../build/codex-arm64/vlc -I dummy on test media in ../build/media/ need no lock. NEVER touch /Applications/VLC.app and never create other VLC bundles.
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
  { key: 'I-build', owns: 'tools/** except gen-tokens.py and gen-icons.py; Makefile.am; Package.swift; module/tests/**; module/bridge/tests/**; test-runner infrastructure and shared helpers under Tests/; redesign/docs/{BUILD,WORKFLOW}.md; redesign/design/SCREENS.md; dead code in files no other area owns',
    scope: 'Build, packaging, install, native test gates and their reliability, test runner, docs that describe the build and the screen status, dead code.' },
  { key: 'J-media-io', owns: 'Sources/MXRUI/Dialogs/OpenMediaDialogs.swift; Sources/MXRVLCBackend/{VLCOutputBackend,VLCRendererBackend}.swift; Sources/MXRCore/Models/{OutputModel,RendererModel}.swift; Sources/MXRMockBackend/MockOutput.swift; output/renderer parts of module/bridge/MXRMediaServices.m',
    scope: 'Open Media (file/disc/network/capture), Convert and Stream (profiles, output jobs, states, real output files), renderers.' },
]

const SPECIFIC = {
  'A-window': `S66 Customize Player mode in the window (parity group 8, MAJOR): the empty second-row band is missing — Figma (every "Player - customize*" frame), key frame 19m12 and spec-part2 §A always give the edit-mode bottom area two rows (972–1080 pt), the upper one an empty bar-material band with dividers. Modal host in the shipping-window composition (parity group 7, MAJOR, owner listed as F-settings): S25.App Add Subtitles sits ~19 pt above the centre, and in a compact window (S37.App/convert-compact) the dialog's top is clipped (-20…520 instead of 20…520) — find whether the cause is the window composition/snapshot engine (yours) or MXRDialogHost/MXRDialogFrame (F's; smallest edit) and fix the cause; the App* entries (S66.App/customization, S72.App/light, S68.App/manage-profiles) render without the top bar under --engine shipping-window — fix the tooling trap. Add a Window/App gallery entry for the saved two-row layout (S67 result: full-width seek row, centred transport). Resume toast below ~400 pt video width must not overflow. Keep the Settings gate strict: when F-settings closes a Settings difference, remove its openSettingsDifferences entry.`,
  'B-controls': `C.SeekBar/default: give the bar-only entry its own fixture time at the position Figma draws (~00:01:53, progress 0.0734 per Figma 1908:7387) so it passes honestly; product defaults and the S01 label entries stay unchanged; no geometry change, no mask. Bar icon hover (Figma Icon Wrapper 177:99): the glyph stays FG/A2 and only the white 6 % radius-4 tile appears — the product brightens the glyph to fg1; match Figma. Seek thumbnail card placement (PlayerControls ~441 offsets by seekThumbnail.height + gap10; check against Figma 2151:9673 and fix). B-08 loose ends: the OSD sizes from the full window width and anchors to the information rect, not the pillarboxed picture; MXRTimeLabel sets its accessibility value twice. Check every B-controls item in parity groups 1 and 2.`,
  'C-bridge': `Native audio suite flake (critic P1, together with I-build who owns the test): audio-preferences failed "native engine shuts down cleanly" in 2 of 11 runs (8 s deadline) after the engine log already reached "removing keystore memory"; find the silent step (sample/spindump the process during a slow shutdown, or signposts on the bridge shutdown path; run the binary in a loop under load) and fix the cause if it is in the bridge (this may be the real Cmd-Q latency, C-13/PERF-04). Delete the dead rescanPlugins path end to end (AppModel.swift ~462 → VLCSettingsBackend.swift ~54 → MXRBridgeCommandRescanPlugins with no handler). Add a headless runtime test for C-02 sidecar names containing ( ) ' (no duplicate track). The extension submenu shows entries from a cached catalog snapshot that is filled only when the catalog is rebuilt — refresh it when an extension activates or changes its menu (coordinate with D-menus). C-01 edge (input_New failure leaves :start-paused on the item) — clean it up if cheap.`,
  'D-menus': `Confirm J-10 renderer wording is now identical in PlayerMenus and EffectsSidebars (the J verifier still saw the old wording — check the current code). Extension submenu freshness (with C-bridge). Disabled shared-model submenu rows in the menu bar look enabled because AppKit autoenables items with submenus — fix. Everything owned by D-menus in parity group 3 (popups and menus).`,
  'E-library': `Compact library rows show the raw file name "The_Wand_S01E…" while the top bar shows the clean title — apply the same display-name rule (D042) wherever Figma shows clean names. S46.MiniPlayer collapsed/hover/queue FAIL: make the fixture name match Figma, and cover the artist chip by D044 in the entry notes/deviations. S28 narrow panel: the two visible breadcrumbs clip to "Th"/"S0" — collapse them into the "…" menu. S29 file context menu: "Mark as Watched" must use the two-tone check-selected glyph (ICONS.md 4004:12348), not the empty check. S40 compact Home fixture content to Figma (Shows / Films / Anime folders, three playlists) without changing product defaults. S72 light: library rows and the current crumb use the right Light foregrounds. Mixed audio+video import gives no feedback for the audio files — fix. View-level tests for E-07 (arrow-key columns), E-10 (multi-select Remove) and E-11 (id-keyed rows). S30/S31 "Edit/Add Audio Tracks" disabled while Figma shows them enabled — enable when possible or record the capability reason under D039.`,
  'F-settings': `Settings parity (parity group 6 + A-window's openSettingsDifferences): S49 general-advanced ("Show minor warnings", "Additional command line options" — removed in wave 1 without a decision), S60 performance (rows below "Drop frames"), S51 interface ("Menu Bar and Notifications" vs Figma "Notifications and System Tray", extra ⓘ on "Remember window size and position"), S61 recording ("~/Movies" vs "~/Videos", "Default (Medium)" vs "Medium", extra ⓘ), S55 video (Figma has ⓘ on Start videos in fullscreen, Stop the screensaver, Play video as desktop wallpaper, Method, Aspect ratio — add the info texts), S56 audio ("Target level" drawn disabled while Figma shows it enabled; missing ⓘ on Speaker setup and Replay gain preamp). For every row: if VLC has a real option behind it, implement it for real (Figma is the visual truth); only if it truly cannot work on this Mac, record the exact reason under D035; then close the matching openSettingsDifferences entries (A-window's FigmaDeviationTests.swift / SettingsFigmaDeviations.swift: smallest edit) so the gate is strict again. F-08: DialogKeyLoopGuard decides "inside the dialog" by geometry and its test never exercises the guard (window.sendEvent bypasses the monitor) — make background content truly non-focusable while a dialog is up and write a test that fails without the fix. C-15: the "Takes effect after restarting VLC" note must compare against the value at launch. Media Info: align the value columns. Headless probe for the new userDataDirectory key against the real engine.`,
  'G-panels': `OWNER DECISION (D033 amended): the relative subtitle Font Size slider follows Figma 804:1341 — "Auto" in the middle where Figma draws the thumb (stop 3), smaller sizes left, larger right; the stored value stays VLC's enum. Implement, test the mapping, render it and look. S18 Video and S19 Audio filter cards open (parity group 4, MAJOR): Figma (536:… Essential/Crop/Colors, Compressor Settings) and video 08m49 show the open card as ONE lighter rounded container holding the "Collapse Settings" header with a DOWN chevron and the rows, inset — PanelExpand (PanelControls.swift) keeps the dark bgB2 header with an UP chevron and loose rows below; match Figma exactly, including value text placement. Also: S14 Subtitles tab divider (Figma none, video 06m21.7 has one — decide with evidence), S15 divider 1 pt high, S20 Subtitle Speed slider thumb not at the start at 1.000 fps (range 0…60), preset list "Default Preset" row indentation, S21 timeline elapsed fill vs Figma gap (video agrees with us — record the decision), a test that the queue row menu really contains the shared Add to Playlist submenu.`,
  'H-design': `S72 Light cone (parity group 8, real bug): the VLC cone draws Light/Accent/Main #E8851A while Figma 2425:13629 uses Light/Accent/Logo #C2711A — Generated/Icons.swift gives "vlc" a single tint; fix generation/tint so each scheme uses the Figma token. Subtitle-file glyph lacks the folded top-left corner (S25/S26/S27, Figma "subtitle" 1911:8286). S66/S67 two-line tile labels (Forward/Backward 15s, last row) sit ~2 pt low. S70 onboarding alternate-accent frames differences. Light play button #E8851A vs the Figma frame's #D37918 — decide with the tokens/INDEX evidence and fix or document. Everything owned by H-design in parity groups 1, 2, 7 and 8.`,
  'I-build': `Native audio suite flake (critic P1): you own MXRAudioPreferenceServicesRuntimeTests and native-tests.py — do not just raise the 8 s deadline; add diagnostics that capture what runs after "removing keystore memory" when the deadline is missed, and work with C-bridge (who fixes the cause in the bridge). The NSWindow isReleasedWhenClosed contract must check per window, not per file. Accelerate in Makefile.am LDFLAGS if the plugin link needs it (verify with the real install build under the lock, no install). B-03 no-op make: produce the mtime evidence. Update redesign/design/SCREENS.md (stale since 2026-10-14: cites CODEX_STATUS.md and codex/native-redesign, says S62 Lua activation is unavailable; add a visual-parity status per S-id from ${FIN}/parity.json) and BUILD.md where commands changed. Remove remaining dead code in files nobody else owns (critic P2).`,
  'J-media-io': `After Stop, the player's on_stopping_current_media (reason USER) overwrites the bridge's "stopping" with "finishing" — the hint flips to "Finishing…" and Stop re-enables; fix. Audio-only profiles ("Audio — AAC (M4A)" etc.) keep the source's subtitle track (aac + mov_text seen) — drop it and verify the produced file with ffprobe. S37.Stream/running shows the build machine's host name — make the gallery deterministic via the fixture. J-12: pathFieldWidth token belongs in MXRDesign (H's files: smallest edit) and OutputProgressBar must not use a spacing token as a height. Convert empty state draws a focus ring on Format; Stream address/port/path fields need labels; Open Disc and Open Capture Device have large empty areas — tighten. Tests for the overwrite view logic (J-03: format change renames the destination and loses confirmedDestination; it clears on completion).`,
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
(a) every screens[] item in ${FIN}/parity.json whose owner is "${a.key}" and verdict is major-diff or minor-diff, plus differences in other groups that your files cause;
(b) every missing[] item in ${FIN}/critic.json whose owner mentions ${a.key};
(c) the open minor issues of your area's last verifier: ${FIN}/areas.json, entry "${a.key}", verdict.open;
(d) specifically: ${SPECIFIC[a.key]}`

const fixPrompt = (a) => `${CTX}\n${header(a)}\n${workList(a)}
You are the FIXER of this area. Fix every item at the root cause (majors first). For a visual item: render before and after, LOOK at both next to the Figma render and the key frame, and keep the evidence under ${SCR}/${a.key}/. For a difference you keep, make sure a decision covers it (DECISIONS RULE). Add focused tests that fail without the fix. Report every item: fixed (with evidence path), kept with which decision, or not fixed and why.`

const verifyPrompt = (a, cur, round) => `${CTX}\n${header(a)}\n${workList(a)}
You are an INDEPENDENT VERIFIER of this area, round ${round} (not its author; do not edit product code, tests or docs; write only under ${SCR}/${a.key}-verify-r${round}/).
The fixer's latest report: ${JSON.stringify(cur)}
Check EVERY item of the work list, not only the claimed ones: read the code, build, run the targeted tests (and check that new regression tests fail without the fix where feasible), render the affected states and LOOK at them next to the Figma renders and key frames. Check each new or amended DECISIONS entry: is the difference really unavoidable, or could it match Figma? Also check: no regressions of the previous wave (re-render a few neighbouring entries), ownership respected, tokens only, Swift 6 clean, engine untouched (git diff upstream-base-2026-10-14 -- src lib include modules/gui/macosx empty), no masks/thresholds hiding differences, Settings gate not loosened.
pass=false only if a blocker or major remains that code, tests or renders can establish (an unjustified decision that excuses a fixable visual difference is a major). Real-window-only checks go to liveChecks.`

const refixPrompt = (a, cur, v) => `${CTX}\n${header(a)}\n${workList(a)}
You are continuing as the FIXER of this area. Your previous report: ${JSON.stringify(cur)}
An independent verifier found these remaining problems — fix all blocker/major ones and the reasonable minor ones, re-verify, and report:\n${JSON.stringify(v.issues, null, 1)}`

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
2. \`.build/debug/mxr-snapshot check --all\`: compare with the previous wave (PASS 15 · REVIEW 49 · FAIL 43, logs in ${PREV}/integration/check-all-2*) and list every entry whose verdict changed and every remaining FAIL with its reason (documented deviation, fixture, real difference).
3. Under the lock: install with tools/install-app.sh (do NOT launch). Check that only /Applications/VLC.app (untouched, modification date 1743527633) and /Applications/VLC Redesign.app exist, the install build has 0 Swift warnings, and the build dir has no leftover VLC.app.
4. Release the lock. Report exact commands, counts and remaining problems. Outputs under ${SCR}/integration/.`, { label: 'integrate', phase: 'Integrate', ...O, schema: { type: 'object', properties: {
  testsPassed: { type: 'boolean' }, testSummary: { type: 'string' }, nativeSuites: { type: 'string' }, snapshotCheck: { type: 'string' }, installed: { type: 'string' },
  fixesMade: { type: 'array', items: { type: 'string' } }, remainingProblems: { type: 'array', items: { type: 'string' } }, summary: { type: 'string' },
}, required: ['testsPassed', 'testSummary', 'remainingProblems', 'summary'] } })

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
You are a DESIGN-PARITY JUDGE (read-only; outputs only under ${SCR}/parity-${i + 1}/). Screen group: ${g}.
The previous judge of this group: ${FIN}/parity.json item ${i} — re-check every screen it listed (especially its major-diff and minor-diff items: are they fixed now, or covered by a justified decision?) and anything it missed. Using redesign/design/SCREENS.md, list every S-id / Figma frame in this group. Render each matching gallery entry offscreen (prefer --engine shipping-window where it applies) in the schemes Figma has, and compare with the Figma render and the video key frames — LOOK at them side by side (crop and zoom where needed). Judge strictly: the owner wants a full 1:1 match; a documented decision is not a difference only if it is justified — say which decision covers it and whether you agree. Name the owning area for each difference. Real-window-only aspects: not-checked with what to look at. Integration summary: ${integ ? integ.summary : 'integration failed'}.`, { label: `parity ${i + 1}`, phase: 'Parity', ...O, schema: PARITY })),
  () => agent(`${CTX}
You are the COMPLETENESS CRITIC (read-only). Area results: ${JSON.stringify(compact)}\nIntegration: ${JSON.stringify(integ)}\nLive checks collected in this wave: ${JSON.stringify(liveChecks)}\nPrevious critic: ${FIN}/critic.json; previous live list: ${FIN}/live-checks.json.
What is still missing for the final product? Previous critic items not closed, audit ids neither fixed nor decided, VIDEO_BREAKDOWN.md MUST rules and SCREENS.md items not working end to end, agent-written decisions that excuse fixable differences, docs out of date. Then produce ONE deduplicated, ordered live-acceptance checklist for the idle-Mac wave that merges the previous live list, this wave's live checks and the owner's complaints C1–C7 (C1 no focus box around volume/seek; C2 track popover anchored bottom-right above the bar; C3 single 40 pt top bar, traffic lights centred, cone right after them; C4 consistent open/close motion, Esc and click-outside close without pausing; C5 sidebar overlays the video, video not shrunk; C6 scrubbing updates playhead/label/preview continuously; C7 single volume indicator, no VLC core OSD), grouped so one agent can run a group in 20–30 minutes.`, { label: 'completeness critic', phase: 'Parity', ...O, schema: { type: 'object', properties: {
    missing: { type: 'array', items: { type: 'object', properties: { priority: { type: 'string', enum: ['P0', 'P1', 'P2'] }, item: { type: 'string' }, evidence: { type: 'string' }, owner: { type: 'string' } }, required: ['priority', 'item'] } },
    liveGroups: { type: 'array', items: { type: 'object', properties: { group: { type: 'string' }, checks: { type: 'array', items: { type: 'object', properties: { id: { type: 'string' }, area: { type: 'string' }, steps: { type: 'string' }, expect: { type: 'string' } }, required: ['id', 'steps', 'expect'] } } }, required: ['group', 'checks'] } },
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
