export const meta = {
  name: 'final-polish-close',
  description: 'Close the remaining offscreen items (new parity judges, critic P1/P2, verifier minors, decisions that excuse fixable differences) per area, verify independently, integrate and reinstall under both locks (no launch), re-judge parity; runs while a live wave drives the installed app',
  phases: [
    { title: 'Fix', detail: 'Opus medium: one fixer per area' },
    { title: 'Verify', detail: 'Opus medium: independent verifier per area, up to 2 refix rounds' },
    { title: 'Integrate', detail: 'full test runner, generators, native suites, check --all, install-app.sh under native+live locks' },
    { title: 'Parity', detail: 'offscreen re-judge of all screen groups + completeness critic' },
  ],
}

const OPUS = 'claude-opus-5-5'
const ROOT = '.'
const PKG = ROOT + '/modules/gui/macosx_redesign'
const FP = ROOT + '/redesign/research/final-polish'
const RES = FP + '/results/resume'
const E = '../build/evidence/final5/polish'
const LOCK = FP + '/workflows/lock.sh'
const LIVELOCK = '../build/locks/live.lock'
const O = { model: OPUS, effort: 'medium' }

const CTX = `
PROJECT: native macOS interface (Swift/SwiftUI + AppKit, thin ObjC bridge) for VLC 4 reproducing Juxtopposed's VLC redesign 1:1. Figma = visual truth, the video = behaviour/intent, VLC = semantics. The VLC engine (src/, lib/, include/, other modules) stays untouched. GOAL: the final product — full 1:1 match with Figma and the video, everything working end to end, native Mac feel, fast.
CHECKOUT: ${ROOT}, branch claude/final, HEAD ddd9d23a9d ("final-polish: resume the parity wave and apply the first live findings"). Swift package: ${PKG}.
STATE: every area passed independent verification; 505/505 Swift tests, all native suites (audio 10/10), install green; mxr-snapshot check --all PASS 21 · REVIEW 64 · FAIL 31. THIS WAVE closes what is left offscreen. Inputs (read what concerns you): ${RES}/parity.json (8 new parity judges: screens[] with verdict, differences, owner), ${RES}/critic.json (missing[] with priority/owner), ${RES}/areas.json (per area: verdict.open = open minor issues of its last verifier; notesForOthers), ${RES}/area-<area>.json (full reports), ${RES}/integration.json (check --all details, remaining FAILs). Earlier: ${FP}/results/finish/*, ${FP}/HANDOFF.md, ${FP}/findings/<area>.json.
A LIVE WAVE IS RUNNING RIGHT NOW: another agent drives "/Applications/VLC Redesign.app" on this Mac's screen with synthetic input. NEVER launch the app (or any other app), never send synthetic input, never run osascript activate/open, never do anything that puts a window on screen or takes focus — offscreen rendering and headless engine probes only. Put every check that needs the real window into liveChecks (exact steps + expected result).
OWNER DECISIONS: owner-accepted: D041 (bars stay visible while paused), D045 (extensions page per D035, opaque light dialogs, track numbers from 1), C-09 (HDR Auto-only, no Off), D033 amended (relative subtitle Font Size slider with "Auto" in the middle). Every other "accepted (agent, …)" entry — D042, D044, D046–D055 and the agent amendments of D007, D028, D032, D039, D044 — and the D030 product defaults are still waiting for the owner: keep their implementation where they record a real constraint, BUT where an agent decision excuses a difference that can be made to match (the critic names D051's truncated label, D055's subtitles under the compact library, D039's disabled audio-track rows, D053's Light bar tint), make it match and amend the entry. List every decision you add or amend in ownerDecisions.
DECISIONS RULE: a difference from Figma is either fixed or covered by a DECISIONS.md entry with evidence (video frame, VLC capability, macOS convention). If you keep a difference, add or amend the entry (smallest edit, re-read the file right before editing — other agents append too; mark it "accepted (agent, 2026-10-17)"). Never use a decision to excuse something that can be made to match.
MUST READ: AGENTS.md (hard rules), redesign/docs/DECISIONS.md (D021+, especially D033–D055), redesign/docs/PHILOSOPHY.md, redesign/docs/WORKFLOW.md.
DESIGN SOURCES: redesign/design/figma/renders/*.png, figma_file.json, INDEX.md, ICONS.md; redesign/design/tokens/*; redesign/design/spec/spec-part1.md + spec-part2.md; redesign/docs/design/VIDEO_BREAKDOWN.md; redesign/design/SCREENS.md (S-ids); local video key frames ../reference/video/key-frames/ (+INDEX.md) and transcript.txt (never commit reference material).
PARALLEL WORK: up to 10 area agents edit this checkout at once, each owning specific files. Do not edit files you don't own; if a fix truly needs another area's file, make the smallest edit to just those lines, re-read right before editing, and list it in editsOutsideOwnership. Never revert or reformat other agents' work. Do NOT git commit/stash/reset/checkout/restore/clean — the orchestrator commits.
BUILD/TEST: from ${PKG}: \`swift build\` (shared .build; concurrent builds wait — normal; if it fails in a file you don't own, wait 2–3 min and retry). Targeted tests only (\`swift test --filter <Suite>\`); the integrator runs the full runner. If the test target keeps failing to compile in another area's file for >15 min, fix it only if trivial and report it; otherwise run your suites in an isolated copy under ${E}/<your-label>/pkg. Visual tool: \`swift run mxr-snapshot help\` (list/render/ref/compare/check; --engine shipping-window renders the real window composition offscreen; --scheme/--accent work for Window and App entries; documented deviations live in Sources/MXRGalleryCatalog/FigmaDeviation.swift and Entries/SettingsFigmaDeviations.swift). LOOK at renders yourself (Read shows PNGs) next to Figma renders and key frames — numbers alone are not enough. Outputs only under ${E}/<your-label>/ (durable, outside the repo); keep them small and delete intermediate renders.
NATIVE LOCK: \`${LOCK} acquire <your-label>\` … \`${LOCK} release\` (default lock path; do not set MXR_LOCK_DIR) around anything that runs make in ../build/codex-arm64 and around tools/native-tests.py suites. Always release, also on failure; hold ≤ 30 min. Only the integrator installs. Headless engine probes with ../build/codex-arm64/vlc -I dummy on test media in ../build/media/ (60 s S01E01/S01E02, 10 min S01E03, each with .srt) need no lock. NEVER touch /Applications/VLC.app and never create other VLC bundles.
QUALITY BAR: premium Mac app. Tokens only (Theme.*), no literal design values in views. Swift 6 strict-concurrency clean (also in the install build). Fix root causes, prefer deleting broken complexity over adding layers; no masks/threshold tweaks that hide visual differences. Gallery fixtures may match Figma's content but must not override product defaults (D030). Tests must check behaviour or what is drawn, not one-line predicates; a regression test must fail without the fix.
`

const AREAS = [
  { key: 'A-window', owns: 'Sources/MXRUI/MXRAppView.swift; Sources/MXRUI/Player/{PlayerView,PlayerBars,PlayerChrome,PlayerGeometry,PlayerMetrics}.swift; Sources/MXRCore/Models/InterfaceModel.swift; Sources/MXRPlugin/{MXRAppController,MXRNativeWindowServices,MXRVideoHost,MXRLaunchFileOpening,MXRFullscreenMagnification}.swift; Sources/MXRGallery/**; Sources/MXRSnapshot/**; Sources/MXRGalleryCatalog/{GalleryCatalog,FigmaDeviation}.swift and Entries/{PlayerGallery,AppGallery,ShippingGallery,ScaffoldGallery,SettingsFigmaDeviations}.swift; Tests/MXRUISnapshotTests/FigmaDeviationTests.swift; the resume toast (MXRContinueWatchingToast)',
    scope: 'Window chrome and composition, bar reveal/hide, fullscreen, PiP, panel placement over the video, Hide UI, shipping-window snapshot fidelity, the snapshot comparison tool and the documented-deviation mechanism.' },
  { key: 'B-controls', owns: 'Sources/MXRUI/Player/{PlayerControls,NativeSeekProgress,PausedSeekStill,ConeScrollHandler,PlayerPreferences,MXROSDView}.swift; Sources/MXRDesign/Typography/OSDTypography.swift; Sources/MXRDesign/Focus/**; Sources/MXRCore/Models/{AppearanceAndPreviewModels,PlaybackClock,PlayerModel}.swift; Sources/MXRCore/Values/{PlayerValues,VideoClickTiming}.swift; Sources/MXRVLCBackend/VLCThumbnailBackend.swift; module/bridge/{MXRThumbnailServices,MXRAudioServices}.{h,m}; Sources/MXRPlugin/MXRNowPlayingClockGate.swift',
    scope: 'Control bar and seek bar: every control and state vs Figma, scrubbing and thumbnails, waveform, subtitle-timeline mode, paused still, OSD, volume tooltip, focus indication, time labels.' },
  { key: 'C-bridge', owns: 'module/bridge/{MXRServicesBridge.m,MXRPlayerBridge.m,MXRMediaServices.*,MXRSubtitleCueServices.*,MXRDialogServices.*,MXRInterfaceBridge.m,MXRPlatformServices.m,MXREffectsServices.*,MXRHotkeyFeedback.inc}; module/*.m and module/*.h; Sources/MXRVLCBackend/{VLCBackends,VLCBridgeSession,VLCPlayerBackend,VLCQueueBackend,VLCServiceBackends,VLCServiceTransport,VLCShortcutCatalog,VLCTypedServiceWire,VLCSettingsBackend}.swift; Sources/MXRBridgeAPI/**; Sources/MXRCore/Models/{ServiceModels,QueueModel}.swift; Sources/MXRCore/Values/{ServiceValues,QueueValues,MediaDevice}.swift; Sources/MXRCore/Backends/** except QueueAndLibraryBackends.swift; Sources/MXRMockBackend (non-library, non-output parts)',
    scope: 'Engine bridge correctness and performance: command/event flow, shutdown and quit latency, subtitles, Lua extensions, typed service wire, dead bridge paths, the mock backend.' },
  { key: 'D-menus', owns: 'Sources/MXRDesign/Popup/**; Sources/MXRUI/Player/PlayerMenus.swift; Sources/MXRPlugin/{MXRNativeMenus,MXRKeyRouting,MXRRemoteControl,MXRNativeRecents}.swift; Sources/MXRCore/Values/ShortcutValues.swift; Sources/MXRCore/App/AppCommand.swift and the shortcut/command parts of AppModel.swift; Sources/MXRGalleryCatalog/Entries/MenusGallery.swift',
    scope: 'Popup menus, dropdowns, submenus, right-click menus, ⋯ menu, menu bar, shortcuts, media keys, recents, menu accessibility.' },
  { key: 'E-library', owns: 'Sources/MXRUI/Library/**; Sources/MXRUI/Dialogs/LibraryDialogs.swift; module/bridge/{MXRLibraryServices,MXRDiscoveryServices}.{h,m}; Sources/MXRVLCBackend/VLCLibraryBackend.swift; Sources/MXRCore/Models/LibraryModel.swift; Sources/MXRCore/Values/{LibraryValues,MediaItem}.swift; Sources/MXRCore/Backends/QueueAndLibraryBackends.swift; library parts of Sources/MXRMockBackend; Sources/MXRGalleryCatalog/Entries/LibraryGallery.swift; Tests/Native*Library*.m',
    scope: 'Media library: Home, folders + breadcrumb, Music, playlists, selection, context menus, mini player, compact and full layouts, light and dark.' },
  { key: 'F-settings', owns: 'Sources/MXRUI/Settings/**; Sources/MXRUI/Dialogs/{DialogInput,DialogMenu,DialogSupport,MXRDialogHost,MediaInfoDialogs,AddSubtitlesView}.swift; Sources/MXRPlugin/{MXRNativePresentations,MXRNativePreferences}.swift; module/bridge/MXRAudioPreferenceServices.{h,m}; Sources/MXRCore/Settings/**; Sources/MXRCore/Models/SettingsModel.swift; Sources/MXRCore/Values/SettingsValues.swift; Sources/MXRCore/Stores/{AppStores,PresetStore}.swift; Sources/MXRCore/App/AppModel+Preferences.swift; Sources/MXRCore/Resources/settings-map.json5; Sources/MXRGalleryCatalog/Entries/{SettingsGallery,DialogsGallery}.swift',
    scope: 'Settings (every section vs Figma, light/dark, real VLC options only), profiles, keyboard shortcuts editor, extensions page, modal dialog host (centring, scrim, keyboard isolation), dialog buttons, media info, Add Subtitles, confirmations.' },
  { key: 'G-panels', owns: 'Sources/MXRUI/Panels/**; Sources/MXRCore/Models/{EffectsModels,TracksModel}.swift; Sources/MXRCore/Values/Effects.swift; Sources/MXRGalleryCatalog/Entries/PanelsGallery.swift',
    scope: 'Side panels and popovers: Subtitles/Audio/Video/Playback tabs, filter cards, track popover, queue panel, subtitle timeline, presets, metadata overlay.' },
  { key: 'H-design', owns: 'Sources/MXRDesign/{Theme,Generated,Materials,Icons}/** and Sources/MXRDesign/*.swift root files; Sources/MXRDesign/Typography/** except OSDTypography.swift; redesign/design/tokens/**; tools/gen-tokens.py; tools/gen-icons.py; Sources/MXRUI/Customization/**; Sources/MXRPlugin/MXRFirstLaunchOnboarding.swift; Sources/MXRCore/Stores/LayoutStore.swift; Sources/MXRGalleryCatalog/Entries/{CustomizationGallery,DesignAccentsGallery,DesignColorsGallery,DesignGallerySupport,DesignIconsGallery,DesignThemeGallery,DesignTypographyGallery}.swift',
    scope: 'Design system (tokens, icons, materials, accents, accessibility variants), customization mode, onboarding.' },
  { key: 'I-build', owns: 'tools/** except gen-tokens.py and gen-icons.py; Makefile.am; Package.swift; module/tests/**; module/bridge/tests/**; test-runner infrastructure and shared helpers under Tests/; redesign/docs/{BUILD,WORKFLOW}.md; redesign/design/SCREENS.md; redesign/research/final-polish/HANDOFF.md; redesign/research/final-polish/workflows/*.sh; dead code in files no other area owns',
    scope: 'Build, packaging, install, native test gates and their reliability, test runner, docs that describe the build, the screen status and the handoff, dead code.' },
  { key: 'J-media-io', owns: 'Sources/MXRUI/Dialogs/OpenMediaDialogs.swift; Sources/MXRVLCBackend/{VLCOutputBackend,VLCRendererBackend}.swift; Sources/MXRCore/Models/{OutputModel,RendererModel}.swift; Sources/MXRMockBackend/MockOutput.swift; output/renderer parts of module/bridge/MXRMediaServices.m; Sources/MXRDesign output dialog metrics added last wave (OutputDialogMetrics.swift)',
    scope: 'Open Media (file/disc/network/capture), Convert and Stream (profiles, output jobs, states, real output files), renderers.' },
]

const SPECIFIC = {
  'A-window': `MAJOR S67 saved two-row layout in the window (parity group 8): the transport (prev/play/next) is not centred — render play centre x 915 pt vs 960 in Figma customize-7 (2160:8301, 2160:8732) and key frame 19m27.6; fix the layout semantics and the other S67 differences the judge lists. P1 (critic): with a right panel open in a narrow window the compact library is not clamped to its minimum width (MXRAppView.swift ~284; at 480 pt it gets 153 pt vs LibraryGeometry minimum 208) — fix the composition (if library and panel cannot both fit, decide with the video which one yields, test it). Compact library vs picture: the first live run noted that in Figma S72 the picture starts at the library's right edge while ours runs under the library — compare Player - Light 2425:13624, every Figma frame with the compact library open and the video (around 11m57) and match; this also decides D055's "subtitles under the compact library". D051: at 480 pt the resume toast's primary action reads "Continue Watchi…" — make it fit (a shorter label from VLC's own strings, or a compact layout consistent with Figma's toast) instead of excusing it. PiP placeholder in Light: surface #DEDEDE and the bar over it #B1B1B1 break D053/D046 (bands under the Light bars use the dark base) — fix. S01.App/default: use the figmaPlayer6 fixture (gallery only). With --scheme light, S01.Window/shipping draws the video edge to edge with no 10 pt inset frame while dark keeps it — check against the Figma Light frames and fix. Fullscreen strip (D055): your verifier doubts that AppKit posts didMove/didResize/occlusion for the titlebar window during the reveal — make the strip tracking robust (prefer a mechanism you can test offscreen) and list the live check.`,
  'B-controls': `Play button hover switches to Accent/DIm #AB6314 (PlayerControls.swift ~88), ~20 % darker; Figma has no play-hover state and spec-part1:212 infers only ~8 % — match the spec or record it with evidence. Volume cone gradient Δ2 (#8D8A13 vs #8B8A12) at several levels: regenerate the stops from Figma 244:183–244:240 so C.VolumeCone/* pass honestly. S13 OSD: the dark outline on both lines reads heavier than the video's second line — compare with key frame 15m27.1 and VLC's freetype defaults; fix. S34 music control bar bgA4 #191919 vs Figma #171717 — use the right token or record it with evidence. PlayerControls.swift:33 and :504 use a literal 0.4 opacity — use a token (H-design provides it; smallest edit). The jump OSD matches on_seek reports to key presses only by count within 1 s — a chapter key or a seek-bar seek inside that second can take a pending slot; make the matching exact and test it.`,
  'C-bridge': `Subtitle safe inset: re-send it when the backing scale or the screen changes (not only when InterfaceModel.subtitleSafeInset or the video size change); apply it only to the main window's vout, not to secondary vouts; subtract the picture's bottom letterbox if the vout knows it. Remove the stale "plugin rescan" comment (VLCSettingsBackend.swift ~7). The bridge rewrite your verifier saw "deferred to after the parallel wave" (read ${RES}/area-C-bridge.json) — do it now if it is still worth it, with tests. Mock hotkeys: Sources/MXRMockBackend/MockServices.swift ~150–185 uses VLC's NON-Apple hotkeys (stop 's', prev 'p', next 'n', record 'Shift+r', fullscreen 'f', mute 'm', snapshot 'Shift+s'), so the S09 context menu and S71 onboarding galleries show shortcuts the installed app never shows — make the mock report the macOS defaults the real engine reports (check headless against the real engine), so galleries match the product; tell D-menus and H-design in notesForOthers. If PER-02 (blocking subtitle-folder syscall on the MainActor, see F-settings) turns out to be in your files, fix it.`,
  'D-menus': `S08 gallery: AppSubmenuComposition (MenusGallery.swift ~126) places the Open Recent submenu 48 pt too high ((row − 1) only works for Profile, whose index counts the separator) — fix. Swift 6 strict-concurrency warning "main actor-isolated static property 'preferredSize' referenced from a nonisolated context" — fix. After C-bridge fixes the mock hotkeys, check that S09's shortcut column matches what the installed app shows (⌘ shortcuts per D026/D034; "Record ⇧R vs R").`,
  'E-library': `S33/S28 navigation rows (new real difference): Figma draws every navigation row (Music root's Songs/Albums/Artists/Genres, Songs ▸ My Songs, the Videos root's Shows/Films/Anime 848:1997, 'The Wand', 'S01'/'S02', Network's Podcasts/Radio) in Dark FG/A3 #6B6B6B (style 217:229); only media rows and playlist rows use #969696 (247:711) — match, in Light too. S28 MISSING gallery entries: the Videos root (Add + Shows/Films/Anime, '3 items'), Videos ▸ Shows (The Wand) and … ▸ Shows ▸ The Wand (S01/S02), bound to their Figma variants of sidebar 848:1996 — add them and make them pass. Breadcrumb '▶' separators and the '…' slot colours per Figma (2425:13624 Light and the dark frames). S30/S31 "Edit Audio Tracks"/"Add Audio Tracks": the D039 amendment admits this is missing work, not an engine limit (the media library stores soundtrack files per media, VLC_ML_FILE_TYPE_SOUNDTRACK, and inputs load them as slaves) — implement it end to end (bridge parts in your MXRLibraryServices; other areas' files: smallest edits), test it headlessly against the real engine, and amend D039. Mini player transport y: derive it from tokens/geometry, not from the home card's ratio.`,
  'F-settings': `P1 (critic): in Light, secondary DialogButton tiles are invisible in every DialogShell dialog (Convert Choose…/Cancel, Stream, Open Disc, Media Info): the default fill BG/A3 (DialogSupport.swift ~85) equals the opaque Light dialog surface (D045) — use the Figma light button style (find the Figma light dialog/button frames and tokens), check every dialog in Light. MAJOR S25.App Add Subtitles scrim (parity group 7): the product dims the whole window, top bar and control bar included, with BG/B2 Transparent #000 @ 0.8, so the player reads almost black; the video (06m02.47) shows no such dimming — compare Figma's dialog-over-player frames and the video, match, and apply the same to S37/S48 compact modals. Settings toggles: Figma 536:1013 has a 3 pt edge inset and a 3 pt label/knob gap — SettingsToggle uses HStack(spacing: 0) — match on all 14 pages. S54: 'Default playback speed' scale labels must be centred under their ticks (Figma), not spread with Spacers. S56: Replay gain preamp must show '0.0' (the mock decodes 0.0 as an integer — fix the mock: smallest edit in MXRMockBackend). S59: the four disabled caching fields show the Normal preset's values where Figma has them empty — match Figma (value as placeholder) or record it. Narrow Settings (480 pt): 'Always starts at:' wraps onto two lines — keep it on one line. S48.App/settings-compact: check the dialog's top edge in the shipping window. S64: disabled Save fill #1F1F1F@98 % vs Figma #1F1E1D@97 % — match the token. S65 Media Info: the fourth track row is cut at the scroll edge — use a content-fitted height like Disc/Capture. S27 'Choose Files' tile contrast is very low — check against the Figma button styles. PER-02 (audit debt, no owner): a blocking subtitle-folder syscall on the MainActor — find it (Add Subtitles / subtitle folder scan) and move it off the main actor with a test; if it is in another area's file, make the smallest edit and list it.`,
  'G-panels': `Open filter-card sliders with stops draw 2 pt ticks at both track ends (tickFractions includes 0 and 1); Figma 536:1860, 614:1435, 612:1228 show only inner ticks — remove the end ticks everywhere (also Background Opacity, Sepia Intensity). The centred delay-slider fill ends at 200 pt where Figma 763:1986 ends at 204 pt; thumb 125.5–133.5 vs 127–135 — match. The selected tab's orange underline is 61 pt wide where Figma draws 70 pt (S18/S19: the narrow-tab padding is applied to the underline) — fix. S17: Figma 5187:24308 draws a 1 px #212121 line under the tab bar (vectors 5187:24342/24374 at y 51) — add it where Figma has it (check the other tabs' frames). S19 Stereo Widener tick counts follow stereo_widen.c steps (Feedback 8 inner ticks, Figma 6) — derive the stops from Figma or record it in D054; '+10 s' vs Figma's '-10 s' typo — one line in D054. Make S19.Filters/stereoWidener-open and compressor-open fail only on documented D054 differences.`,
  'H-design': `Light bars: #A7A7A7 vs Figma #ABABAA (Δ4) — the product composes BG/A3 over the Dark BG/B2 #090909 base; find Figma's exact layer stack under the Light bars (Player - Light 2425:13624) and match it exactly, offscreen and in the real-window material path, then drop the D053 excuse. S63 dropdown: mxrDropdownList uses .overField(rowOffset:) (MXRDropdown.swift ~146), putting the current option on the field's row; Figma Dropdown 2372:8300, 'sub filename' 6456:13892 and video 17m31.0 all show the list dropping BELOW the field — match Figma unless an owner-accepted decision says otherwise (agent-written ones don't count; check D0xx). S70 onboarding mini player preview draws Windows minimize/maximize buttons — use the macOS chrome per D022. S71: the gallery shows VLC's non-Mac hotkeys (C-bridge fixes the mock) — make sure S71 then matches what the installed app shows. S50 Light Settings: the selected theme segment is pale Light/BG/Accent Bright with accent text where the video's Light frame (17m44.0) has a solid accent fill with white text, and Browse is a grey tile — decide with the Figma tokens vs the video per PHILOSOPHY and fix or record it. Provide a disabled-opacity token for B-controls' literal 0.4. Remaining S66 items from ${RES}/parity.json.`,
  'I-build': `tools: plugins.dat indexing runs only if cache_gen exists and plugins is non-empty — a missing $BUILD/bin/vlc-cache-gen silently skips it; fail loudly. native-tests.py skips the plugin-cache check (critic P2) — fix. SCREENS.md: rerunning gen_screens.py would drop the new preamble and the 'Parity · live' column — port them into the generator so it is the single source, and refresh the parity column from ${RES}/parity.json. HANDOFF: rewrite ${FP}/HANDOFF.md for the current state (it is dated 2026-10-16 19:41): commits fae8f04dc0 → 3c690eb2a0 (WIP after the usage-limit stop) → ddd9d23a9d and this wave; results dirs (results/finish, results/parity, results/resume); durable evidence folders ../build/evidence/final4 and final5; the lost /private/tmp evidence; the locks (MXR_LOCK_DIR; native lock default path, live lock ${LIVELOCK}); the live wave running in parallel (results in ../build/evidence/final5/live); the pending owner decisions (every "accepted (agent, …)" entry and amendment in DECISIONS.md, plus the D030 defaults) and how to continue. Keep it short, in the language HANDOFF.md already uses.`,
  'J-media-io': `Light: secondary DialogButton tiles equal the opaque Light dialog surface — F-settings fixes DialogButton; check Convert/Stream/Open Disc/Capture after it. Sheet heights end in half points (Capture 713×344.5, Stream 713×679.5, from the dialogHint line height 24.5) — make the frames whole points without changing the Figma layout. J-03: test the wiring in OutputMediaForm (the format onChange renames the destination and drops confirmedDestination; it clears on completion), not only the value type. Everything J-media-io owns in parity group 7.`,
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
(a) every screens[] item in ${RES}/parity.json whose owner mentions "${a.key}" and whose verdict is major-diff, minor-diff or missing, plus differences in other groups that your files cause;
(b) every missing[] item in ${RES}/critic.json whose owner mentions ${a.key};
(c) the open issues of your area's last verifier: ${RES}/areas.json, entry "${a.key}", verdict.open, and the items other areas left for you (areas[].notesForOthers / notFixed naming ${a.key});
(d) specifically: ${SPECIFIC[a.key]}`
const howToFix = (a) => `Fix every item at the root cause (majors and P1 first). For a visual item: render before and after, LOOK at both next to the Figma render and the key frame, and keep the evidence under ${E}/${a.key}/. For a difference you keep, make sure a decision covers it (DECISIONS RULE). Add focused tests that fail without the fix. Report every item of the work list: fixed (with evidence path), kept with which decision, or not fixed and why.`

const fixPrompt = (a) => `${CTX}\n${header(a)}\n${workList(a)}\nYou are the FIXER of this area. ${howToFix(a)}`
const verifyPrompt = (a, cur, round) => `${CTX}\n${header(a)}\n${workList(a)}
You are an INDEPENDENT VERIFIER of this area, round ${round} (not its author; do not edit product code, tests or docs; write only under ${E}/${a.key}-verify-r${round}/).
The fixer's latest report: ${JSON.stringify(cur)}
Check EVERY item of the work list, not only the claimed ones: read the code, build, run the targeted tests (and check that new regression tests fail without the fix where feasible — in an isolated copy under your output folder, never by editing the shared tree), render the affected states and LOOK at them next to the Figma renders and key frames. Check each new or amended DECISIONS entry: is the difference really unavoidable, or could it match Figma? Also check: no regressions (re-render a few neighbouring entries), ownership respected, tokens only, Swift 6 clean, engine untouched (\`git diff upstream-base-2026-10-14 -- src lib include modules/gui/macosx\` empty), no masks/thresholds hiding differences, Settings gate not loosened.
pass=false only if a blocker or major remains that code, tests or renders can establish (an unjustified decision that excuses a fixable visual difference is a major). Real-window-only checks go to liveChecks.`
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
1. From ${ROOT}: full runner \`python3 modules/gui/macosx_redesign/tools/run-swift-tests.py modules/gui/macosx_redesign modules/gui/macosx_redesign/.build\` (run it twice), tools/gen-tokens.py --check, tools/gen-icons.py --check, every tools/test-*.py, and under the native lock every native suite of tools/native-tests.py --engine-build ../build/codex-arm64 (run the audio suite 5 times and report the pass count). Fix integration breakages (cross-area compile errors, tests invalidated by intended changes); for a non-trivial failure that belongs to an area, fix it only if the cause is clear and the fix small, otherwise report it with evidence. Confirm \`git diff upstream-base-2026-10-14 -- src lib include modules/gui/macosx\` is empty.
2. \`.build/debug/mxr-snapshot check --all\`: compare with the ddd9d23a9d wave (PASS 21 · REVIEW 64 · FAIL 31; details in ${RES}/integration.json) and list every entry whose verdict changed and every remaining FAIL with its reason (documented deviation, fixture, real difference).
3. Install: acquire the native lock (\`${LOCK} acquire integrate\`), THEN the live lock (\`MXR_LOCK_DIR=${LIVELOCK} ${LOCK} acquire integrate\`) — the live wave holds it while it drives the app, so waiting up to ~45 min is normal; never break a live lock younger than 45 min. Make sure "VLC Redesign" is not running (pgrep -x "VLC Redesign"; if it is, release the live lock and wait 5 min, then retry — never kill it while a live agent may be using it). Then install with tools/install-app.sh (do NOT launch). Check that only /Applications/VLC.app (untouched, modification date 1743527633) and /Applications/VLC Redesign.app exist, the install build has 0 Swift warnings, and the build dir has no leftover VLC.app. Record the new bundle modification time (stat -f %m).
4. Release the live lock, then the native lock (\`MXR_LOCK_DIR=${LIVELOCK} ${LOCK} release\`, \`${LOCK} release\`). Report exact commands, counts and remaining problems. Outputs under ${E}/integration/.`, { label: 'integrate', phase: 'Integrate', ...O, schema: { type: 'object', properties: {
  testsPassed: { type: 'boolean' }, testSummary: { type: 'string' }, nativeSuites: { type: 'string' }, snapshotCheck: { type: 'string' }, installed: { type: 'string' }, bundleMtime: { type: 'string' },
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
The previous judge of this group: ${RES}/parity.json item ${i} — re-check every screen it listed (especially its major-diff, minor-diff and missing items: are they fixed now, or covered by a justified decision?) and anything it missed. Using redesign/design/SCREENS.md, list every S-id / Figma frame in this group. Render each matching gallery entry offscreen (prefer --engine shipping-window where it applies) in the schemes Figma has, and compare with the Figma render and the video key frames — LOOK at them side by side (crop and zoom where needed). Judge strictly: the owner wants a full 1:1 match; a documented decision is not a difference only if it is justified — say which decision covers it and whether you agree. Name the owning area for each difference. Real-window-only aspects: not-checked with what to look at. Integration summary: ${integ ? integ.summary : 'integration failed'}.`, { label: `parity ${i + 1}`, phase: 'Parity', ...O, schema: PARITY })),
  () => agent(`${CTX}
You are the COMPLETENESS CRITIC (read-only; outputs only under ${E}/critic/). Area results: ${JSON.stringify(compact)}\nIntegration: ${JSON.stringify(integ)}\nLive checks collected in this wave: ${JSON.stringify(liveChecks)}\nPrevious critic: ${RES}/critic.json; the live checklist the parallel live wave is running: ${RES}/live-groups.json.
What is still missing for the final product? Previous critic items not closed, audit ids neither fixed nor decided, VIDEO_BREAKDOWN.md MUST rules and SCREENS.md items not working end to end, agent-written decisions that excuse fixable differences, docs out of date. Then list the live checks that must be (re)run after this wave: this wave's live checks plus every check of ${RES}/live-groups.json whose code this wave changed (name the check id and why), deduplicated and grouped so one agent can run a group in 20–30 minutes.`, { label: 'completeness critic', phase: 'Parity', ...O, schema: { type: 'object', properties: {
    missing: { type: 'array', items: { type: 'object', properties: { priority: { type: 'string', enum: ['P0', 'P1', 'P2'] }, item: { type: 'string' }, evidence: { type: 'string' }, owner: { type: 'string' } }, required: ['priority', 'item'] } },
    liveRecheck: { type: 'array', items: { type: 'object', properties: { group: { type: 'string' }, checks: { type: 'array', items: { type: 'object', properties: { id: { type: 'string' }, area: { type: 'string' }, why: { type: 'string' }, steps: { type: 'string' }, expect: { type: 'string' } }, required: ['id', 'steps', 'expect'] } } }, required: ['group', 'checks'] } },
    summary: { type: 'string' },
  }, required: ['missing', 'liveRecheck', 'summary'] } }),
])

return {
  areas: compact,
  areaReports: areaResults.map(r => ({ area: r.area, reports: r.reports, verdict: r.verdict })),
  liveChecks, ownerDecisions,
  integration: integ,
  parity: parity.slice(0, GROUPS.length).map((p, i) => p && { group: GROUPS[i], ...p }),
  critic: parity[GROUPS.length],
}
