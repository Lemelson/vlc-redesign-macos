export const meta = {
  name: 'final-polish',
  description: 'Review Codex audit fixes and the whole redesign per area, verify findings, fix with independent verification, then integrate, install, accept in the real window and judge design parity screen by screen',
  phases: [
    { title: 'Brief', detail: 'Haiku xhigh: per-area items from both audits, Codex fix log and old review', model: 'claude-haiku-5-5' },
    { title: 'Review', detail: 'Opus medium: critical area review incl. Codex changes and design parity' },
    { title: 'Triage', detail: 'Opus medium: skeptical check of every review finding' },
    { title: 'Fix', detail: 'Opus medium: area fixers with disjoint file ownership' },
    { title: 'Verify', detail: 'Opus medium: independent verifier, up to 2 refix rounds' },
    { title: 'Integrate', detail: 'full tests, install-app.sh, real-window acceptance, CPU' },
    { title: 'Parity', detail: 'design-parity judges per screen group + completeness critic' },
  ],
}

const OPUS = 'claude-opus-5-5'
const HAIKU = 'claude-haiku-5-5'
const ROOT = '.'
const PKG = ROOT + '/modules/gui/macosx_redesign'
const SCR = '<scratch>'
const T = SCR + '/tools'
const O = { model: OPUS, effort: 'medium' }

const CTX = `
PROJECT: native macOS interface (Swift/SwiftUI + AppKit, thin ObjC bridge) for VLC 4 reproducing Juxtopposed's VLC redesign 1:1. Figma = visual truth, the video = behaviour/intent, VLC = semantics. The VLC engine (src/, lib/, include/, other modules) stays untouched. GOAL OF THIS WAVE: bring the product to its final state — full 1:1 match with Figma and the video, everything working end to end in the real app, native Mac feel, fast.
CHECKOUT: ${ROOT}, branch claude/final. Swift package: ${PKG}. History you must know:
- 5ac081046e = Claude polish wave 1 (fixes of redesign/research/CODEX_REVIEW.md + codex-review-findings.json, each area independently verified).
- 3bbac3cb63 = app icon + single-copy install.
- a215064366 = Codex (GPT-6.1 Sol) fixes for two independent audits: redesign/research/audits/claude-2026-10-15.md (69/100) and chatgpt-2026-10-15.md (68/100); Codex's own mapping/claims: redesign/research/AUDIT_FIXES_2026-10-15.md. The owner does NOT trust these yet: they may be incorrect, superficial, over-engineered, may hide differences instead of fixing them, or may have regressed wave-1 work. Judge them critically (git show a215064366 -- <paths>; git diff 5ac081046e a215064366 -- <paths>).
MUST READ: AGENTS.md (hard rules), redesign/docs/DECISIONS.md (incl. D021+ and any Codex D033+; if a Codex decision contradicts Figma/video, report it with evidence instead of silently overriding), redesign/docs/PHILOSOPHY.md, redesign/docs/WORKFLOW.md.
DESIGN SOURCES: redesign/design/figma/renders/*.png, figma_file.json, INDEX.md, ICONS.md; redesign/design/tokens/*; redesign/design/spec/spec-part1.md + spec-part2.md; redesign/docs/design/VIDEO_BREAKDOWN.md; redesign/design/SCREENS.md (S-ids); local video key frames ../reference/video/key-frames/ (+INDEX.md) and transcript.txt (never commit reference material).
PARALLEL WORK: 10 area agents edit this checkout at once, each owning specific files. Do not edit files you don't own; if a fix truly needs another area's file, make the smallest edit to just those lines, re-read right before editing, and list it in editsOutsideOwnership. Never revert or reformat other agents' work. Do NOT git commit/stash/reset/checkout/clean — the orchestrator commits.
BUILD/TEST: from ${PKG}: \`swift build\` (shared .build; concurrent builds wait — normal; if it fails in a file you don't own, wait 2 min and retry). Targeted tests only (\`swift test --filter <Suite>\`); the integrator runs the full runner (tools/run-swift-tests.py). Visual tool: \`swift run mxr-snapshot help\` (list/render/ref/compare/check; --engine shipping-window renders the real window composition offscreen). Put outputs only under ${SCR}/<your-label>/. LOOK at renders yourself (Read shows PNGs) next to Figma renders and key frames — numbers alone are not enough.
REAL APP: one shared lock for native build/install/launch: \`${T}/lock.sh acquire <your-label>\` … \`${T}/lock.sh release\` (always release, also on failure; hold ≤ 30 min). Build+install ONLY with \`${PKG}/tools/install-app.sh\` (produces /Applications/VLC Redesign.app; see redesign/docs/BUILD.md; export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" if make cannot find libSystem). Launch only "/Applications/VLC Redesign.app"; NEVER launch or touch /Applications/VLC.app (owner's official VLC) or create other VLC bundles. Test media: ../build/media/. Before driving the window with synthetic input run \`${T}/wait-idle.sh 900\` (waits until nobody touched the Mac for 2 min); if it exits 1 the owner is using the Mac — skip the live part and say so. Capture with \`screencapture -l <windowId>\`; input via CGEvent/AppleScript (see redesign/tools/test-native-host.swift). Quit the app when done.
QUALITY BAR: premium Mac app. Tokens only (Theme.*), no literal design values in views. Swift 6 strict-concurrency clean. Fix root causes, prefer deleting broken complexity over adding layers; no masks/threshold tweaks that hide visual differences. Gallery fixtures must not override product defaults (D030). Keep what the audits list as done well.
`

const AREAS = [
  { key: 'A-window', owns: 'Sources/MXRUI/MXRAppView.swift; Sources/MXRUI/Player/{PlayerView,PlayerBars,PlayerChrome,PlayerGeometry,PlayerMetrics}.swift; Sources/MXRCore/Models/InterfaceModel.swift; Sources/MXRPlugin/{MXRAppController,MXRNativeWindowServices,MXRVideoHost,MXRLaunchFileOpening,MXRFullscreenMagnification}.swift; Sources/MXRGallery/**; Sources/MXRSnapshot/**; Sources/MXRGalleryCatalog/Entries/{PlayerGallery,AppGallery,ShippingGallery,ScaffoldGallery}.swift',
    scope: 'Window chrome and composition: single 40 pt top bar, centred traffic lights, cone placement, bar reveal/hide (top and bottom independent), fullscreen and windowed states, cursor hiding, PiP window behaviour, panel/sidebar/queue placement over the video and their motion, Esc/click-outside dismissal, launch to Home, empty-queue behaviour, Hide UI, shipping-window snapshot fidelity. Audit ids typically WIN-*, PLAYER-* (window/bars), TST-02, CODE-04/COMP-12, COMP-15, D-decisions about pause pin.' },
  { key: 'B-controls', owns: 'Sources/MXRUI/Player/{PlayerControls,NativeSeekProgress,PausedSeekStill,ConeScrollHandler,PlayerPreferences,MXROSDView}.swift; Sources/MXRDesign/Typography/OSDTypography.swift; Sources/MXRDesign/Focus/**; Sources/MXRCore/Models/{AppearanceAndPreviewModels,PlaybackClock,PlayerModel}.swift; Sources/MXRCore/Values/{PlayerValues,VideoClickTiming}.swift; Sources/MXRVLCBackend/VLCThumbnailBackend.swift; module/bridge/{MXRThumbnailServices,MXRAudioServices}.{h,m}; Sources/MXRPlugin/MXRNowPlayingClockGate.swift',
    scope: 'Control bar and seek bar: every control and state vs Figma, scrubbing (continuous playhead/label/preview), thumbnails, waveform (off by default), subtitle-timeline mode, paused-seek still (D031), resume toast, OSD look (two-line action + key), volume tooltip, focus indication (no system focus rings), video click timing, Now Playing clock, CPU with bars visible/hidden/scrubbing (measure in the real app). Audit ids typically CTL-*, PERF-01, NAT-04, COMP-11, A11Y-06.' },
  { key: 'C-bridge', owns: 'module/bridge/{MXRServicesBridge.m,MXRPlayerBridge.m,MXRMediaServices.*,MXRSubtitleCueServices.*,MXRDialogServices.*,MXRInterfaceBridge.m,MXRPlatformServices.m,MXREffectsServices.*,MXRHotkeyFeedback.inc}; module/*.m and module/*.h (MXRIntf, MXRVoutWindow, …); Sources/MXRVLCBackend/{VLCBackends,VLCBridgeSession,VLCPlayerBackend,VLCQueueBackend,VLCServiceBackends,VLCServiceTransport,VLCShortcutCatalog,VLCTypedServiceWire}.swift; Sources/MXRBridgeAPI/**; Sources/MXRCore/Models/{ServiceModels,QueueModel}.swift; Sources/MXRCore/Values/{ServiceValues,QueueValues,MediaDevice}.swift; Sources/MXRCore/Backends/{ServiceBackends,PlayerBackends or other non-library backends}.swift; Sources/MXRMockBackend (non-library parts)',
    scope: 'Engine bridge correctness and performance: command/event flow, topic snapshots, no main-thread blocking, device discovery, OSD feed and hotkey names, subtitles (external/sidecar/folder mappings, drop, fullscreen), Lua extensions + dialog provider, HDR/resolution handling, exit latency, typed service wire (judge whether Codex typing is real value or ceremony). Audit ids typically CODE-02, CODE-06, PER-02, PERF-04, NAT-*, COMP-05, COMP-10, COMP-18.' },
  { key: 'D-menus', owns: 'Sources/MXRDesign/Popup/**; Sources/MXRUI/Player/PlayerMenus.swift; Sources/MXRPlugin/{MXRNativeMenus,MXRKeyRouting,MXRRemoteControl,MXRNativeRecents}.swift; Sources/MXRCore/Values/ShortcutValues.swift; Sources/MXRCore/App/AppCommand.swift and the shortcut/command parts of AppModel.swift; Sources/MXRGalleryCatalog/Entries/MenusGallery.swift',
    scope: 'Popup menus, dropdowns, submenus, right-click menus, ⋯ menu, menu bar, shortcuts (⌘ conventions, Mac glyphs), media keys/remote, recents; exact Figma look (rows, icons, shortcut column, ✓, hover, separators, motion), keyboard navigation, VoiceOver roles for custom menus, pin/anchoring rules. Audit ids typically PLAYER-07, PLAYER-13, PNL-03 and popup-related items.' },
  { key: 'E-library', owns: 'Sources/MXRUI/Library/**; Sources/MXRUI/Dialogs/LibraryDialogs.swift; module/bridge/{MXRLibraryServices,MXRDiscoveryServices}.{h,m}; Sources/MXRVLCBackend/VLCLibraryBackend.swift; Sources/MXRCore/Models/LibraryModel.swift; Sources/MXRCore/Values/{LibraryValues,MediaItem}.swift; Sources/MXRCore/Backends/QueueAndLibraryBackends.swift; library parts of Sources/MXRMockBackend; Sources/MXRGalleryCatalog/Entries/LibraryGallery.swift; Tests/Native*Library*.m',
    scope: 'Media library with real data: Home sections, folders + breadcrumb, Music (songs/albums/artists/genres), playlists (add/remove/sort, duplicates), selection model, Add File, Show all, sorting per kind, network/discovery, mini player, paging/caching, empty/loading states, light and dark. Audit ids typically LIB-*, LIBSET-02.' },
  { key: 'F-settings', owns: 'Sources/MXRUI/Settings/**; Sources/MXRUI/Dialogs/{DialogInput,DialogMenu,DialogSupport,MXRDialogHost,MediaInfoDialogs,AddSubtitlesView}.swift; Sources/MXRPlugin/{MXRNativePresentations,MXRNativePreferences}.swift; Sources/MXRVLCBackend/VLCSettingsBackend.swift; module/bridge/MXRAudioPreferenceServices.{h,m}; Sources/MXRCore/Settings/**; Sources/MXRCore/Models/SettingsModel.swift; Sources/MXRCore/Values/SettingsValues.swift; Sources/MXRCore/Stores/{AppStores,PresetStore}.swift; Sources/MXRCore/App/AppModel+Preferences.swift; Sources/MXRCore/Resources/settings-map.json5; Sources/MXRGalleryCatalog/Entries/{SettingsGallery,DialogsGallery}.swift',
    scope: 'Settings (every section, light/dark, values written in the right units, nothing that does nothing, no raw engine values), profiles (switching, migration, no rollback of user state), keyboard shortcuts editor, extensions settings, modal dialog host (centred, scrim, isolation, Esc/⌘W), media info, Add Subtitles, confirmations. Audit ids typically SET-* (except SET-04 streaming), LIBSET-05, profile items.' },
  { key: 'G-panels', owns: 'Sources/MXRUI/Panels/**; Sources/MXRCore/Models/{EffectsModels,TracksModel}.swift; Sources/MXRCore/Values/Effects.swift; Sources/MXRGalleryCatalog/Entries/PanelsGallery.swift',
    scope: 'Side panels and popovers content: Subtitles/Audio/Video/Playback tabs (exact rows and controls from Figma and the video), track popover, queue panel, subtitle timeline, effects/filters inspector, presets, metadata overlay (incl. Hide UI behaviour together with A). Audit ids typically PNL-*, COMP-08, WIN-01 (metadata).' },
  { key: 'H-design', owns: 'Sources/MXRDesign/{Theme,Generated,Materials,Icons}/** and Sources/MXRDesign/*.swift root files; Sources/MXRDesign/Typography/** except OSDTypography.swift; redesign/design/tokens/**; tools/gen-tokens.py; tools/gen-icons.py; Sources/MXRUI/Customization/**; Sources/MXRPlugin/MXRFirstLaunchOnboarding.swift; Sources/MXRCore/Stores/LayoutStore.swift; Sources/MXRGalleryCatalog/Entries/{CustomizationGallery,DesignAccentsGallery,DesignColorsGallery,DesignGallerySupport,DesignIconsGallery,DesignThemeGallery,DesignTypographyGallery}.swift',
    scope: 'Design system: tokens vs Figma (colors incl. light theme and scrims, typography, metrics, materials/backdrop, icons two-tone), accent swatches, Increase Contrast / Differentiate Without Color, customization mode (layout drag, palette, profiles view), onboarding (clean first launch with the user media library). Audit ids typically A11Y-02, CODE-09, LIBSET-04, LIBSET-09 and design-token items.' },
  { key: 'I-build', owns: 'tools/** except gen-tokens.py and gen-icons.py; Makefile.am; Package.swift; module/tests/**; module/bridge/tests/**; test-runner infrastructure under Tests/ (not feature tests owned by areas); redesign/docs/{BUILD,WORKFLOW}.md; dead code in files no other area owns',
    scope: 'Build, packaging, install-app.sh (single copy, rollback, signing order), finalize, native test gates, test runner, schema drift, reproducibility, dead code and junk (audit section "Мёртвый код и мусор"), over-engineering Codex added to tooling (judge whether 26 tooling tests are useful or noise). Audit ids typically TST-*, CODE-05, CODE-08 (only plan the decomposition of huge files and do it only for files nobody else owns), packaging items.' },
  { key: 'J-media-io', owns: 'Sources/MXRUI/Dialogs/OpenMediaDialogs.swift; Sources/MXRVLCBackend/{VLCOutputBackend,VLCRendererBackend}.swift; Sources/MXRCore/Models/{OutputModel,RendererModel}.swift',
    scope: 'Open Media (file/disc/network/capture), Convert and Stream (formats VLC supports, output jobs, real output file), renderers (Chromecast etc.), playback order semantics if in these files. Verify outputs for real: convert a test clip and check the produced file. Audit ids typically SET-04, COMP-* about convert/stream/open.' },
]

const BRIEF = { type: 'object', properties: {
  briefPath: { type: 'string' }, auditItems: { type: 'number' }, codexClaimedFixed: { type: 'number' }, codexPartialOrOpen: { type: 'number' }, notes: { type: 'string' },
}, required: ['briefPath', 'auditItems', 'notes'] }

const FINDINGS = { type: 'object', properties: {
  codexAssessment: { type: 'string', description: 'how good Codex fixes in this area are, with concrete examples (correct / superficial / wrong / regressions)' },
  findings: { type: 'array', items: { type: 'object', properties: {
    id: { type: 'string', description: 'area-prefixed id, e.g. A-01; mention audit ids it relates to in title' },
    severity: { type: 'string', enum: ['blocker', 'major', 'minor'] },
    kind: { type: 'string', enum: ['codex-fix-wrong', 'codex-regression', 'audit-unfixed', 'design-mismatch', 'bug', 'perf', 'a11y', 'quality'] },
    title: { type: 'string' }, evidence: { type: 'string' }, fix: { type: 'string' }, files: { type: 'array', items: { type: 'string' } },
  }, required: ['id', 'severity', 'kind', 'title', 'evidence', 'fix'] } },
}, required: ['codexAssessment', 'findings'] }

const TRIAGE = { type: 'object', properties: {
  confirmed: { type: 'array', items: { type: 'object', properties: { id: { type: 'string' }, severity: { type: 'string', enum: ['blocker', 'major', 'minor'] }, title: { type: 'string' }, evidence: { type: 'string' }, fix: { type: 'string' }, files: { type: 'array', items: { type: 'string' } } }, required: ['id', 'severity', 'title', 'fix'] } },
  rejected: { type: 'array', items: { type: 'object', properties: { id: { type: 'string' }, why: { type: 'string' } }, required: ['id', 'why'] } },
}, required: ['confirmed', 'rejected'] }

const RESULT = { type: 'object', properties: {
  status: { type: 'string', enum: ['done', 'partial', 'blocked'] }, summary: { type: 'string' },
  fixed: { type: 'array', items: { type: 'string' } },
  notFixed: { type: 'array', items: { type: 'object', properties: { id: { type: 'string' }, why: { type: 'string' } }, required: ['id', 'why'] } },
  filesChanged: { type: 'array', items: { type: 'string' } }, editsOutsideOwnership: { type: 'array', items: { type: 'string' } },
  notesForOthers: { type: 'string' }, evidence: { type: 'array', items: { type: 'string' } },
}, required: ['status', 'summary', 'fixed', 'notFixed', 'filesChanged'] }

const VERDICT = { type: 'object', properties: {
  pass: { type: 'boolean' },
  issues: { type: 'array', items: { type: 'object', properties: { severity: { type: 'string', enum: ['blocker', 'major', 'minor'] }, description: { type: 'string' }, where: { type: 'string' } }, required: ['severity', 'description'] } },
  summary: { type: 'string' },
}, required: ['pass', 'issues', 'summary'] }

const areaHeader = (a) => `YOUR AREA: ${a.key}\nYOU OWN (paths relative to ${PKG} unless they start with redesign/): ${a.owns}\nSCOPE: ${a.scope}`

const areaResults = await pipeline(
  AREAS,
  // 1. Haiku xhigh: collect everything relevant to this area into one brief
  (a) => agent(`You prepare a review brief. Do NOT edit any repository file; write only ${SCR}/${a.key}/brief.md (mkdir -p first).
Repo: ${ROOT} (branch claude/final). ${areaHeader(a)}
Collect into the brief, with exact ids and line references:
1. Every finding in redesign/research/audits/claude-2026-10-15.md and redesign/research/audits/chatgpt-2026-10-15.md that belongs to this scope (id, severity, one-paragraph summary, the audit's proposed fix). Read both audits fully; when unsure whether an item belongs here, include it under "borderline".
2. For each of those ids, Codex's status letter (И/Ч/О/Н) and claim from redesign/research/AUDIT_FIXES_2026-10-15.md (both mapping tables, the "seven defects" section and "Что остаётся до приёмки").
3. Items of redesign/research/codex-review-findings.json (old review) in this scope that the later audits still mention as open.
4. Output of: cd ${ROOT} && git diff --stat 3bbac3cb63 a215064366 -- modules/gui/macosx_redesign (keep only files of this area) and the list of new files Codex added in this area.
5. Relevant audit sections "Что сделано хорошо (не сломать)" for this scope.
Be complete and literal — a stronger model will rely on this brief. Return the brief path and counts.`, { label: `brief ${a.key}`, phase: 'Brief', schema: BRIEF, model: HAIKU, effort: 'xhigh' }),

  // 2. Opus: critical review of the area
  (brief, a) => agent(`${CTX}\n${areaHeader(a)}
You are the REVIEWER of this area (read-only: do not edit repository files; renders/screenshots only under ${SCR}/${a.key}-review/). Brief prepared by a cheap model (spot-check it): ${brief ? brief.briefPath : SCR + '/' + a.key + '/brief.md'}.
Review the CURRENT code of the area (branch claude/final) along four lines and report concrete findings:
1. Codex's fixes (a215064366): for every audit id in the brief marked И, check the fix is real, correct, minimal and matches design/video intent — not a test that asserts the bug away, not a disabled feature presented as fixed, not over-engineering. For Ч/Н items decide what must still be done to finish them.
2. Regressions: anything wave 1 (5ac081046e) fixed that Codex's changes broke or weakened.
3. Design parity: render this area's gallery entries (mxr-snapshot check/render, incl. --engine shipping-window and --scheme light where relevant) and compare against the Figma renders and video key frames; LOOK at them. Every visible difference (size, spacing, colour, font, icon, state, motion, missing element) is a finding unless DECISIONS.md explicitly accepts it.
4. Behaviour/bugs/perf/a11y in the real flows of this area (trace code; use the real app under the lock + idle rule when runtime behaviour matters).
Give each finding a severity (blocker = broken/visibly wrong in the main flow; major = clear deviation from design/video or real bug; minor = polish) and a concrete fix. Also give an honest codexAssessment for this area.`, { label: `review ${a.key}`, phase: 'Review', schema: FINDINGS, ...O }),

  // 3. Opus: skeptical triage
  (rev, a) => {
    if (!rev) return null
    if (!rev.findings.length) return { review: rev, triage: { confirmed: [], rejected: [] } }
    return agent(`${CTX}\n${areaHeader(a)}
You are a SKEPTICAL TRIAGER (read-only). Another reviewer reported these findings for this area:\n${JSON.stringify(rev.findings, null, 1)}
For each finding, check the evidence yourself in the code, renders (mxr-snapshot, outputs under ${SCR}/${a.key}-triage/), Figma renders, video key frames and DECISIONS.md. Reject findings that are wrong, already fixed, contradicted by an accepted decision, or pure taste with no design evidence. Confirm real ones, correcting severity and sharpening the fix (exact files/lines, design values from tokens/Figma). Do not drop real issues just because they are hard.`, { label: `triage ${a.key}`, phase: 'Triage', schema: TRIAGE, ...O }).then(t => t && { review: rev, triage: t })
  },

  // 4. Opus: fix, then independent verify loop
  async (rt, a) => {
    if (!rt) return { area: a.key, error: 'review or triage failed' }
    const todo = rt.triage.confirmed
    log(`${a.key}: ${todo.length} confirmed, ${rt.triage.rejected.length} rejected`)
    if (!todo.length) return { area: a.key, codexAssessment: rt.review.codexAssessment, confirmed: [], result: null, verdict: 'nothing to fix' }
    let cur = await agent(`${CTX}\n${areaHeader(a)}
You are the FIXER of this area. Confirmed findings to fix (all blockers and majors; minors too unless clearly not worth it — say why):\n${JSON.stringify(todo, null, 1)}
Codex assessment of this area from the reviewer: ${rt.review.codexAssessment}
Fix each properly at the root cause, add/adjust focused tests where behaviour changed (no tests that just pin the current output), verify visually against Figma/key frames (renders under ${SCR}/${a.key}/) and in the real app under the lock + idle rule where it is runtime behaviour. Report ids fixed with evidence paths.${a.key === 'G-panels' ? '' : `
RESUMED: a previous fixer of this area was cut off by an account usage limit after 25–35 minutes of work. Its partial edits are on disk and checkpointed in WIP commit 951f073be2 (see them with: git diff a215064366 951f073be2 -- <your files>). Digest of its transcript (files edited, narration, last tool calls): ${SCR}/prev/${a.key}.txt; raw transcript for grep only: ${SCR}/prev/${a.key}-full.jsonl. CONTINUE from that work — do not redo or revert it; first establish which findings it already finished (check the code, not its intentions) and whether swift build is currently broken in your files (other areas were cut off mid-edit too; fix only your own files and wait/retry for others).`}`, { label: `fix ${a.key}`, phase: 'Fix', schema: RESULT, ...O })
    for (let round = 1; round <= 2; round++) {
      if (!cur) break
      const v = await agent(`${CTX}\n${areaHeader(a)}
You are an INDEPENDENT VERIFIER of this area (not its author; read-only). Findings that had to be fixed:\n${JSON.stringify(todo, null, 1)}\nThe fixer's report: ${JSON.stringify(cur)}
Check every claimed fix against the design evidence: read the changed code, build, run the targeted tests, render the affected states and LOOK at them next to Figma renders and key frames; for runtime behaviour trace the code path and use the real app under the lock + idle rule. Be skeptical: earlier work in this project often "looked right at first glance but behaved differently from the design". Also check: no regressions of things listed as done well, ownership respected, tokens only, Swift 6 clean, no engine edits, no hidden differences via masks/thresholds. pass=false if any blocker/major remains. Outputs only under ${SCR}/${a.key}-verify-r${round}/.`, { label: `verify ${a.key} r${round}`, phase: 'Verify', schema: VERDICT, ...O })
      if (!v) break
      log(`${a.key} r${round}: pass=${v.pass} — ${v.summary.slice(0, 160)}`)
      if (v.pass) return { area: a.key, codexAssessment: rt.review.codexAssessment, confirmed: todo.map(f => f.id + ' ' + f.title), result: cur, verdict: v }
      cur = await agent(`${CTX}\n${areaHeader(a)}
You are continuing as the FIXER of this area. Findings: ${JSON.stringify(todo.map(f => ({ id: f.id, title: f.title })))}\nYour previous report: ${JSON.stringify(cur)}
An independent verifier found these remaining problems — fix all blocker/major ones and reasonable minor ones, re-verify, and report:\n${JSON.stringify(v.issues, null, 1)}`, { label: `refix ${a.key} r${round}`, phase: 'Fix', schema: RESULT, ...O })
    }
    return { area: a.key, codexAssessment: rt.review.codexAssessment, confirmed: todo.map(f => f.id + ' ' + f.title), result: cur, verdict: 'not passed after 2 rounds' }
  },
)

const compact = areaResults.filter(Boolean).map(r => ({ area: r.area, codex: r.codexAssessment, confirmed: r.confirmed, status: r.result && r.result.status, fixed: r.result && r.result.fixed, notFixed: r.result && r.result.notFixed, verdict: typeof r.verdict === 'string' ? r.verdict : (r.verdict && { pass: r.verdict.pass, open: r.verdict.issues }), notesForOthers: r.result && r.result.notesForOthers, error: r.error }))

phase('Integrate')
const integ = await agent(`${CTX}
You are the INTEGRATOR after this wave. Area results: ${JSON.stringify(compact)}
1. From ${ROOT}: run the full runner \`python3 modules/gui/macosx_redesign/tools/run-swift-tests.py modules/gui/macosx_redesign modules/gui/macosx_redesign/.build\`, tools/gen-tokens.py --check, gen-icons.py --check, the tooling tests (tools/test-*.py) and \`tools/native-tests.py --engine-build ../build/codex-arm64 --suite contracts\`. Fix trivial integration breakages (cross-area compile errors, tests invalidated by intended changes); report anything non-trivial. Confirm \`git diff upstream-base-2026-10-14 -- src lib include modules/gui/macosx\` is empty.
2. Under the lock: build and install with tools/install-app.sh. Then \`mdfind "kMDItemCFBundleIdentifier == '*vlc*'"\`-style check that only /Applications/VLC.app (untouched) and /Applications/VLC Redesign.app exist.
3. Real-window acceptance under the lock (wait-idle first; if the Mac stays in use, retry wait-idle up to 3 times, then report the live part as not run): launch "/Applications/VLC Redesign.app" with a test episode, capture screenshots and check PASS/FAIL with evidence: the owner's complaints C1 no focus box around volume/seek; C2 track popover anchored bottom-right above the bar; C3 single 40 pt top bar, traffic lights centred, cone right after them; C4 consistent open/close motion, Esc and click-outside close without pausing; C5 sidebar overlays the video, video not shrunk; C6 scrubbing updates playhead/label/preview continuously; C7 single volume indicator, no VLC core OSD; plus launch-to-Home, library with real folders, ⋯ menu and right-click menu as Figma cards, settings readable in light theme, dialogs centred with scrim, fullscreen bar reveal, and CPU (top -l) idle-playing with bars visible, hidden and while scrubbing. Compare the main window screenshot with Figma Player-6.png and the library with its Figma render. Save everything under ${SCR}/integration/.
4. Quit the app, release the lock. Report.`, { label: 'integrate + acceptance', phase: 'Integrate', ...O, schema: { type: 'object', properties: {
  testsPassed: { type: 'boolean' }, testSummary: { type: 'string' }, installed: { type: 'string' },
  acceptance: { type: 'array', items: { type: 'object', properties: { check: { type: 'string' }, pass: { type: 'boolean' }, evidence: { type: 'string' } }, required: ['check', 'pass', 'evidence'] } },
  cpu: { type: 'string' }, remainingProblems: { type: 'array', items: { type: 'string' } }, summary: { type: 'string' },
}, required: ['testsPassed', 'acceptance', 'remainingProblems', 'summary'] } })

phase('Parity')
const GROUPS = [
  'Player window: dark, light, Hide UI, fullscreen, windowed thin frame, top bar, traffic lights, cone, PiP',
  'Control bar and seek bar: every control, hover/pressed states, scrubbing preview, waveform and subtitle-timeline modes, OSD, volume tooltip, resume toast, compact widths',
  'Popups and menus: ⋯ menu, right-click menu and submenus, dropdowns, track popover, speed/HDR/zoom menus, menu bar',
  'Side panels: Subtitles, Audio, Video, Playback tabs, queue, subtitle timeline, effects/filters, presets, metadata overlay',
  'Library: Home, folders and breadcrumb, Music (songs/albums/artists/genres), playlists, search, mini player, empty and loading states, light theme',
  'Settings: every section in dark and light, keyboard shortcuts editor, extensions, profiles',
  'Dialogs: Open Media (file/disc/network/capture), Convert, Stream, Add Subtitles, Media Info, confirmations, modal host',
  'Customization mode, onboarding, design system (icons, accents, typography, colours, materials)',
]
const parity = await parallel([
  ...GROUPS.map((g, i) => () => agent(`${CTX}
You are a DESIGN-PARITY JUDGE (read-only; outputs only under ${SCR}/parity-${i + 1}/). Screen group: ${g}.
Using redesign/design/SCREENS.md, list every S-id / Figma frame in this group. For each: render the matching gallery entry (prefer --engine shipping-window), and where the installed app can show it, a real screenshot (lock + idle rule; integration screenshots may already exist in ${SCR}/integration/). Compare with the Figma render and the video key frames — LOOK at them side by side. Judge strictly: the owner wants a full 1:1 match. Integration summary: ${integ ? integ.summary : 'integration failed'}.`, { label: `parity ${i + 1}`, phase: 'Parity', ...O, schema: { type: 'object', properties: {
    screens: { type: 'array', items: { type: 'object', properties: { screen: { type: 'string' }, verdict: { type: 'string', enum: ['match', 'minor-diff', 'major-diff', 'missing', 'not-checked'] }, differences: { type: 'string' }, evidence: { type: 'string' } }, required: ['screen', 'verdict', 'differences'] } },
    summary: { type: 'string' },
  }, required: ['screens', 'summary'] } })),
  () => agent(`${CTX}
You are the COMPLETENESS CRITIC (read-only). Area results: ${JSON.stringify(compact)}\nIntegration: ${JSON.stringify(integ)}
Ask what is still missing for the final product: audit ids neither fixed nor explicitly decided, features from VIDEO_BREAKDOWN.md MUST rules and SCREENS.md that do not exist or do not work end to end, claims nobody verified in the real app, remaining Codex over-engineering or dead code, docs (SCREENS.md statuses, DECISIONS.md) out of date. Produce a prioritized list for the next wave with owners (area keys above or new areas).`, { label: 'completeness critic', phase: 'Parity', ...O, schema: { type: 'object', properties: {
    missing: { type: 'array', items: { type: 'object', properties: { priority: { type: 'string', enum: ['P0', 'P1', 'P2'] }, item: { type: 'string' }, evidence: { type: 'string' }, owner: { type: 'string' } }, required: ['priority', 'item'] } },
    summary: { type: 'string' },
  }, required: ['missing', 'summary'] } }),
])

return { areas: compact, integration: integ, parity: parity.slice(0, GROUPS.length).map((p, i) => p && { group: GROUPS[i], ...p }), critic: parity[GROUPS.length] }
