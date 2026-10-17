export const meta = {
  name: 'final-polish-live2',
  description: 'Live acceptance of the installed VLC Redesign app on the idle Mac: a cheap idle gate before each of the 12 check groups, then one Opus agent per group driving the real window under the live lock (owner complaints first), then triage into a per-area fix list; no code edits',
  phases: [
    { title: 'Live', detail: 'Haiku idle gate + Opus medium live agent per group, sequential (one Mac, one screen)' },
    { title: 'Triage', detail: 'Opus medium: confirm failures, dedupe into a per-area fix list and owner-only steps' },
  ],
}

const OPUS = 'claude-opus-5-5'
const HAIKU = 'claude-haiku-5-5'
const ROOT = '.'
const FP = ROOT + '/redesign/research/final-polish'
const RES = FP + '/results/resume'
const PAR = FP + '/results/parity'
const E5 = '../build/evidence/final5'
const SCR = E5 + '/live'
const LOCK = FP + '/workflows/lock.sh'
const LIVELOCK = '../build/locks/live.lock'
const WAIT = E5 + '/tools/wait-idle.sh'
const O = { model: OPUS, effort: 'medium' }
const H = { model: HAIKU, effort: 'xhigh' }

const GROUPS = ['0-install-gate', '1-window-fullscreen', '2-light-theme', '3-resume-and-subtitles', '4-controls-seek', '5-volume-focus-music-cpu', '6-panels', '7-library', '8-settings-dialogs', '9-design-customize-onboarding', '10-menus-osd-engine', '11-media-io']

const CTX = `
PROJECT: native macOS interface for VLC 4 reproducing Juxtopposed's VLC redesign 1:1 (repo ${ROOT}, branch claude/final, HEAD ddd9d23a9d; read AGENTS.md hard rules). Figma = visual truth (redesign/design/figma/renders/*.png, INDEX.md), the video = behaviour (key frames ../reference/video/key-frames/ + INDEX.md, redesign/docs/design/VIDEO_BREAKDOWN.md), decisions in redesign/docs/DECISIONS.md (D041 pause pin and D045 are accepted by the owner; D048–D055 are agent-written and describe the intended behaviour of this build).
THIS IS THE LIVE-ACCEPTANCE WAVE: "/Applications/VLC Redesign.app" was installed at 03:24 from ddd9d23a9d. Only one earlier live group ever ran, on an older build: ${PAR}/live-run-1-window.json (its two FAILs were fixed offscreen since). An idle gate has just confirmed that nobody touched the Mac for at least 5 minutes; the display is kept awake by caffeinate. You drive the installed app with synthetic input and screenshots. The display is 1728×1117 pt (Retina), so a 1920×1080 window is impossible — measure at the sizes you can.
A POLISH WAVE EDITS THE SOURCE IN PARALLEL and will reinstall the app once, holding the live lock (so never during your group). Record the bundle's modification time (stat -f %m "/Applications/VLC Redesign.app") at the start and at the end of your group, and say which build you tested.
DO NOT EDIT CODE, TESTS OR DOCS. Write only under ${SCR}/<your-group>/ (checks that mention ${E5}/sidecar, ${E5}/home, ${E5}/verify.mp4 etc. may create those under ${E5}).
LOCKS: \`MXR_LOCK_DIR=${LIVELOCK} ${LOCK} acquire live-<group>\` before launching the app, \`MXR_LOCK_DIR=${LIVELOCK} ${LOCK} release\` at the end (also on failure). While holding it, run \`touch ${LIVELOCK}\` at least every 10 minutes. A check that runs make, tools/native-tests.py or tools/install-app.sh also needs the native lock (\`${LOCK} acquire live-<group>-native\` … \`${LOCK} release\`, default path, hold ≤ 30 min; the polish wave uses it for builds — waiting is normal). Never run install-app.sh unless a check explicitly asks for it.
IDLE: run \`${WAIT} 300 120\` right before your first synthetic input (it waits for 2 min without input; the previous group's synthetic input resets the counter — normal). If it exits 1 the owner is back: stop at once, quit the app, restore settings, mark the remaining checks NOT-RUN.
INPUT AND CAPTURE: see modules/gui/macosx_redesign/tools/test-native-host.swift and redesign/tools for CGEvent/AppleScript helpers used before; you may write small Swift/Python helpers in your output folder (CGEvent for mouse/keys/scroll/media keys, AXUIElement for accessibility structure, CGWindowListCopyWindowInfo for window ids). Capture with \`screencapture -l <windowId>\` or -R for the region a check needs; avoid capturing other apps, and never describe other apps' content. Before every input make sure "VLC Redesign" is frontmost (osascript) — test processes of the polish wave may briefly take focus; re-activate and retry. LOOK at every screenshot yourself (Read shows PNGs) and compare with the Figma render / key frame named in the check; measure pixels where the check is about geometry or colour.
MEDIA: ../build/media/ — Test Show S01E01.mp4 and S01E02.mp4 (60 s, with .srt), Test Show S01E03.mp4 (10 min, with .srt; use it for resume, long seeks, CPU). Open files with \`open -a "/Applications/VLC Redesign.app" <file>\` or the app's own UI.
SAFETY: NEVER launch or touch /Applications/VLC.app. Do NOT change macOS system settings (accessibility display options, Full Keyboard Access, VoiceOver, Reduce Motion, Increase Contrast, natural scrolling, keyboard, display, sound devices, login items); a check that needs one is NEEDS-OWNER with exact steps for the owner — but first check read-only (defaults read) whether it is already on and run the check if it is. Before your first change, back up the app's own preferences, vlcrc and media-library database (find them under ~/Library/Preferences and ~/Library/Application Support for the app's bundle id) into ${SCR}/<your-group>/backup/; you MAY change the app's own settings to run a check; at the end quit the app and restore every backed-up file. Never delete or rename the owner's media library entries, playlists, profiles, presets or recents; create test playlists/presets with a "zz-live-" prefix and remove only those. Do not download anything from the internet. A pristine first launch only with a temporary HOME passed to the app binary directly, and only if that cannot touch the owner's data; otherwise NEEDS-OWNER.
LOAD: the polish wave builds and tests in parallel, so the machine may be busy. For CPU use per-process numbers (top -pid / ps) and record \`uptime\` load next to them; for smoothness checks (scrubbing, animations) retry once if load is high and say so instead of failing on jank caused by load.
END: quit the app (⌘Q; if it hangs >10 s record that as a finding with the time, then kill it), restore the backups, release the lock(s). Aim to finish the group within ~35 minutes.
REPORT every check of your group: PASS / FAIL / NOT-RUN / NEEDS-OWNER, with evidence paths; for FAIL give observed vs expected, the screenshot, and the suspected cause (file and area key A-window … J-media-io). Add any other defect you notice while driving the app as extra findings.
`

const RESULT = { type: 'object', properties: {
  group: { type: 'string' }, build: { type: 'string', description: 'installed bundle modification time(s) you tested' },
  checks: { type: 'array', items: { type: 'object', properties: {
    id: { type: 'string' }, area: { type: 'string' }, result: { type: 'string', enum: ['PASS', 'FAIL', 'NOT-RUN', 'NEEDS-OWNER'] },
    observed: { type: 'string' }, expected: { type: 'string' }, evidence: { type: 'string' }, suspectedCause: { type: 'string' },
  }, required: ['id', 'result', 'observed'] } },
  extraFindings: { type: 'array', items: { type: 'object', properties: { area: { type: 'string' }, severity: { type: 'string', enum: ['blocker', 'major', 'minor'] }, description: { type: 'string' }, evidence: { type: 'string' } }, required: ['severity', 'description'] } },
  settingsRestored: { type: 'boolean' }, summary: { type: 'string' },
}, required: ['group', 'checks', 'summary'] }

const GATE = { type: 'object', properties: { idle: { type: 'boolean' }, waitedMinutes: { type: 'number' }, lastIdleSeconds: { type: 'number' } }, required: ['idle'] }

phase('Live')
const results = []
let patience = 240
for (const g of GROUPS) {
  const gate = await agent(`You are an idle gate (do nothing else). Run \`${WAIT} 540 300\` with the Bash tool (timeout 600000 ms) again and again until it exits 0 or about ${patience} minutes have passed in total. It waits until nobody has touched the Mac's keyboard or mouse for 5 minutes. Do not touch any other file, app or setting. Return idle=true if it exited 0, with the minutes you waited and the last idle seconds it printed.`, { label: `gate ${g}`, phase: 'Live', schema: GATE, ...H })
  if (!gate || !gate.idle) {
    results.push({ group: g, checks: [], summary: `NOT-RUN: the Mac was in use (gate waited ${gate ? gate.waitedMinutes : '?'} min)` })
    log(`${g}: NOT-RUN — Mac in use`)
    patience = 30
    continue
  }
  patience = 60
  const r = await agent(`${CTX}
YOUR GROUP: ${g}. The checks are in ${RES}/live-groups.json (the entry whose "group" starts with "${g}"); checks with ownerComplaint true are the owner's own complaints — do them first and with the most care.`, { label: `live ${g}`, phase: 'Live', schema: RESULT, ...O })
  if (r) {
    results.push(r)
    const c = (r.checks || []).reduce((m, x) => { m[x.result] = (m[x.result] || 0) + 1; return m }, {})
    log(`${g}: ${JSON.stringify(c)} — ${String(r.summary).slice(0, 140)}`)
  } else {
    results.push({ group: g, checks: [], summary: 'agent failed' })
    log(`${g}: agent failed`)
  }
}

phase('Triage')
const triage = await agent(`You are the TRIAGE agent for the live-acceptance wave of the VLC Redesign app (repo ${ROOT}; read AGENTS.md; read-only; write only under ${SCR}/triage/).
Live results of all groups: ${JSON.stringify(results)}
Note: a polish wave edited the source in parallel and reinstalled the app once; each group reports the bundle modification time it tested.
1. Look at the evidence of every FAIL (screenshots under ${SCR}/) and confirm it is a real product defect, not a harness or load artefact; re-classify where the evidence says otherwise.
2. Deduplicate and produce a fix list per area (A-window … J-media-io) with severity, observed vs expected, evidence, suspected cause (file), the build it was seen on, and how to re-check it live.
3. Produce the list of checks that only the owner can do (NEEDS-OWNER), in plain short steps.
4. List NOT-RUN checks and why, and whether a later live run can do them.`, { label: 'triage', phase: 'Triage', ...O, schema: { type: 'object', properties: {
  fixes: { type: 'array', items: { type: 'object', properties: { area: { type: 'string' }, severity: { type: 'string', enum: ['blocker', 'major', 'minor'] }, title: { type: 'string' }, observed: { type: 'string' }, expected: { type: 'string' }, evidence: { type: 'string' }, cause: { type: 'string' }, build: { type: 'string' }, recheck: { type: 'string' } }, required: ['area', 'severity', 'title', 'observed'] } },
  ownerSteps: { type: 'array', items: { type: 'string' } },
  notRun: { type: 'array', items: { type: 'string' } },
  passedHighlights: { type: 'array', items: { type: 'string' } },
  summary: { type: 'string' },
}, required: ['fixes', 'summary'] } })

return { results, triage }
