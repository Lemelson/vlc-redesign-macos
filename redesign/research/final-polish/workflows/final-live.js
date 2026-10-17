export const meta = {
  name: 'final-polish-live',
  description: 'Live acceptance of the installed VLC Redesign app on an idle Mac: run the grouped real-window checklist (owner complaints C1–C7 first) one group at a time under the native lock, then triage failures into a per-area fix list; no code edits',
  phases: [
    { title: 'Live', detail: 'Opus medium: one agent per check group, sequential (one Mac, one screen)' },
    { title: 'Triage', detail: 'Opus medium: dedupe failures into a per-area fix list and owner-only steps' },
  ],
}

const OPUS = 'claude-opus-5-5'
const ROOT = '.'
const PKG = ROOT + '/modules/gui/macosx_redesign'
const FIN = ROOT + '/redesign/research/final-polish/results/finish'
const SCR = '<scratch>'
const T = '<scratch>'
const LOCKDIR = '<scratch>'
const O = { model: OPUS, effort: 'medium' }

const GROUPS = ['1-window', '2-controls', '3-menus-keys', '4-panels', '5-library', '6-settings-dialogs', '7-design', '8-bridge-build', '9-media-io']

const CTX = `
PROJECT: native macOS interface for VLC 4 reproducing Juxtopposed's VLC redesign 1:1 (repo ${ROOT}, branch claude/final; read AGENTS.md hard rules). Figma = visual truth (redesign/design/figma/renders/*.png, INDEX.md), the video = behaviour (key frames ../reference/video/key-frames/ + INDEX.md, redesign/docs/design/VIDEO_BREAKDOWN.md), decisions in redesign/docs/DECISIONS.md (D041 pause pin and D045 are accepted by the owner).
THIS IS THE LIVE-ACCEPTANCE WAVE: nobody has ever checked this build in the real window. The owner has stepped away from the Mac and is not touching it; the display is kept awake by caffeinate. You drive the INSTALLED app "/Applications/VLC Redesign.app" with synthetic input and screenshots. Record the bundle's modification time at the start (another wave may reinstall a newer build between groups; that is fine, just record which build you tested).
DO NOT EDIT CODE, TESTS OR DOCS: another agent wave is editing the source right now. Write only under ${SCR}/<your-group>/.
LOCK: \`${T}/lock.sh acquire live-<group>\` before launching the app, \`${T}/lock.sh release\` at the end (also on failure). Other agents hold this lock for native test suites up to 30 min — waiting is normal. While you hold it, run \`touch ${LOCKDIR}\` at least every 10 minutes (a lock untouched for 45 min is treated as stale). Aim to finish your group within ~35 minutes.
IDLE: run \`${T}/wait-idle.sh 600\` once before your first synthetic input (it waits for 2 min without HID input; the previous group's own synthetic input resets it — normal). If it exits 1 the owner is using the Mac: mark the whole group NOT-RUN and stop.
INPUT AND CAPTURE: see redesign/tools/test-native-host.swift for CGEvent/AppleScript helpers used before; you may write small Swift/Python helpers in your output folder (CGEvent for mouse/keys/scroll/media keys, AXUIElement queries for accessibility structure, CGWindowListCopyWindowInfo for window ids). Capture with \`screencapture -l <windowId>\` (or -R for a region). Before every input make sure "VLC Redesign" is frontmost (osascript); test processes of the other wave may briefly take focus — re-activate and retry. LOOK at every screenshot yourself (Read shows PNGs) and compare with the Figma render / key frame named in the check; measure pixels where the check is about geometry or colour.
MEDIA: test media in ../build/media/ (Test Show S01E01.mp4 + .srt, S01E02 …). Open files with \`open -a "/Applications/VLC Redesign.app" <file>\` or the app's own UI.
SAFETY: NEVER launch or touch /Applications/VLC.app. Do NOT change macOS system settings (accessibility display options, Full Keyboard Access, VoiceOver, keyboard, display, sound devices, login items); a check that needs one is NEEDS-OWNER with exact steps for the owner — but first check whether the setting is already on (defaults read, read-only) and run the check if it is. You MAY change the app's own settings to run a check, but record each original value first and restore all of them before you finish. Never delete or rename the owner's media library entries, playlists, profiles, presets or recents; create test playlists/presets with a "zz-live-" prefix and remove only those. If a check needs a pristine first launch, do it only with a temporary HOME passed to the app binary directly and only if that cannot touch the owner's data; otherwise NEEDS-OWNER.
LOAD: another wave builds and tests in parallel, so the machine may be busy. For CPU use per-process numbers (top -pid / ps) and record \`uptime\` load next to them; for smoothness checks (scrubbing, animations) retry once if load is high and say so instead of failing on jank caused by load.
END: quit the app (⌘Q; if it hangs >10 s record that as a finding with the time, then kill it), restore app settings, release the lock.
REPORT every check of your group: PASS / FAIL / NOT-RUN / NEEDS-OWNER, with evidence paths; for FAIL give observed vs expected, the screenshot, and the suspected cause (file and area key A-window … J-media-io). Add any other defect you notice while driving the app as extra findings.
`

const RESULT = { type: 'object', properties: {
  group: { type: 'string' }, build: { type: 'string', description: 'installed bundle modification time you tested' },
  checks: { type: 'array', items: { type: 'object', properties: {
    id: { type: 'string' }, area: { type: 'string' }, result: { type: 'string', enum: ['PASS', 'FAIL', 'NOT-RUN', 'NEEDS-OWNER'] },
    observed: { type: 'string' }, expected: { type: 'string' }, evidence: { type: 'string' }, suspectedCause: { type: 'string' },
  }, required: ['id', 'result', 'observed'] } },
  extraFindings: { type: 'array', items: { type: 'object', properties: { area: { type: 'string' }, severity: { type: 'string', enum: ['blocker', 'major', 'minor'] }, description: { type: 'string' }, evidence: { type: 'string' } }, required: ['severity', 'description'] } },
  settingsRestored: { type: 'boolean' }, summary: { type: 'string' },
}, required: ['group', 'checks', 'summary'] }

phase('Live')
const results = []
for (const g of GROUPS) {
  const r = await agent(`${CTX}
YOUR GROUP: ${g}. The checks are in ${FIN}/live-groups.json (the entry whose "group" is "${g}"); entries marked ownerComplaint are the owner's own complaints — do them first and with the most care. For checks taken from the critic, the steps are in the text.`, { label: `live ${g}`, phase: 'Live', schema: RESULT, ...O })
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
1. Look at the evidence of every FAIL (screenshots under ${SCR}/) and confirm it is a real product defect, not a harness or load artefact; re-classify where the evidence says otherwise.
2. Deduplicate and produce a fix list per area (A-window … J-media-io) with severity, observed vs expected, evidence, suspected cause (file) and how to re-check it live.
3. Produce the list of checks that only the owner can do (NEEDS-OWNER), in plain short steps.
4. List NOT-RUN checks and why, and whether a later live run can do them.`, { label: 'triage', phase: 'Triage', ...O, schema: { type: 'object', properties: {
  fixes: { type: 'array', items: { type: 'object', properties: { area: { type: 'string' }, severity: { type: 'string', enum: ['blocker', 'major', 'minor'] }, title: { type: 'string' }, observed: { type: 'string' }, expected: { type: 'string' }, evidence: { type: 'string' }, cause: { type: 'string' }, recheck: { type: 'string' } }, required: ['area', 'severity', 'title', 'observed'] } },
  ownerSteps: { type: 'array', items: { type: 'string' } },
  notRun: { type: 'array', items: { type: 'string' } },
  passedHighlights: { type: 'array', items: { type: 'string' } },
  summary: { type: 'string' },
}, required: ['fixes', 'summary'] } })

return { results, triage }
