# Review of the Codex implementation (2026-10-14)

Eight independent reviewers (window/top bar, control bar, popovers/sidebar/menus, library, settings/dialogs, native runtime, engineering, completeness), each checked by a skeptical verifier. Full verified findings with design evidence, code locations and fixes: `codex-review-findings.json`. Decisions taken from it: `docs/DECISIONS.md` D021–D032.

## Grades (0–100)

| Area | Completeness | Fidelity | Code quality | Findings (crit/major/minor) |
|---|---|---|---|---|
| completeness | 66 | 55 | 62 | 2/21/16 |
| popovers-sidebar-menus | 68 | 45 | 50 | 2/9/11 |
| window-topbar | 58 | 42 | 52 | 2/14/9 |
| engineering | 50 | n/a | 45 | 1/14/8 |
| settings-dialogs | 62 | 50 | 55 | 3/18/11 |
| control-bar | 72 | 55 | 48 | 3/9/7 |
| library | 42 | 55 | 48 | 3/19/15 |
| native-runtime | 55 | 38 | 40 | 2/15/5 |

## Verdict

- Breadth is real: all 72 screens exist (42 done, 29 partial, 1 stub); 68 of 108 video rules are implemented correctly, 12 differently, 25 partially, 2 missing.
- Isolated components match Figma closely **in the gallery**, but the gallery used mock-only compositions and fixtures that override product defaults, so the shipped window diverges: two-row header, centred track popover, sidebar pushing the video, NSPopover bubbles, waveform ticks on video, system focus rings, two OSDs.
- Real-data library is the weakest area (flat lists, no folders, Music not split, generic breadcrumb).
- Performance: per-frame SwiftUI work in the seek bar (25–34 % CPU with bars visible, 50–57 % while scrubbing); every command rebuilds the full player snapshot on main.
- Engine: three `src/` files patched (paused seek). The bug is real upstream; moved to a quarantined patch series (D031).

## Critical findings

- **CMP-01** (completeness) Every local video gets a waveform 'tick-mark' seek bar instead of the thick solid bar (Show Waveform defaults ON and applies to video)
- **CMP-02** (completeness) Real window shows two rows: an empty titlebar strip with the traffic lights, then the 40 pt top bar with the cone indented by an unused 76 pt reserve
- **P1** (popovers-sidebar-menus) Track popover is vertically centered on the right edge instead of anchored 20 pt above the control bar
- **P2** (popovers-sidebar-menus) Settings sidebar and queue panel push and shrink the video into a separate docked column instead of floating over it
- **WT-01** (window-topbar) Real window has two header rows (traffic-light strip plus 40pt top bar) and the cone is indented ~96pt
- **WT-08** (window-topbar) Launch with nothing to resume shows the blank cone screen instead of Home; the 'Start in compact mode' preference is never read
- **ARC-01** (engineering) Visual verification checks a mock gallery composition, not the window that ships, so defects pass review ('looks right, behaves differently')
- **SD-01** (settings-dialogs) Real Keyboard Shortcuts dialog lists raw VLC action ids ('vol-up') instead of human action names
- **SD-02** (settings-dialogs) Customize Player edit mode breaks both bars: seek bar collapses to a stub, right-hand groups float mid-bar
- **SD-03** (settings-dialogs) Light theme makes section headings, the selected category, dialog headings and shortcut names invisible
- **BB-01** (control-bar) Scrubbing: the thumbnail preview stops updating while the pointer moves; requests are cancelled before they are sent, are not cancellable once sent, and are slow and uncached
- **BB-02** (control-bar) Each seek or volume drag event runs two or more full player-state snapshots on the main thread (all tracks, titles, effects variables, audio devices), and VLC callbacks add more
- **BB-04** (control-bar) Waveform is on by default and drawn on the seek bar of normal videos (the dense tick marks in the owner's screenshot) instead of the solid thick bar
- **L01** (library) Real backend flattens the library: no folders, a single generic breadcrumb, and the top-bar folder chip always says 'Videos'
- **L02** (library) The Music category is a flat file list: Songs/Albums/Artists/Genres are unreachable and songs show file names instead of 'title - artist'
- **L03** (library) Launch shows the blank-cone start screen she explicitly replaced; pressing Play then shows a raw engine error with a system 'Retry Playback' button
- **R1** (native-runtime) Top bar is pushed below the titlebar safe area: traffic lights get their own 32-pt row and the cone is indented by an empty 76-pt reserve (also in fullscreen)
- **R2** (native-runtime) Visible control bar costs ~22-30% CPU continuously during playback (scrubbing 50-57%); whole seek bar re-evaluated every display frame

## Owner complaints → root causes

| # | Complaint | Root cause (finding ids) |
|---|---|---|
| C1 | Square outline around the volume % box | default SwiftUI focus effect on focusable controls (BB-05, ARC-06, R4, SD-14) |
| C2 | Track popover floats mid-right | `.overlay(alignment: .trailing)` instead of bottom-trailing anchoring (P1, BB-07, R5) |
| C3 | Cone indented, two header rows | titlebar safe area not ignored + 76 pt reserve borrowed from a time-label token (WT-01, CMP-02, R1) |
| C4 | Inconsistent animations, unclear dismissal | ⋯ is an NSPopover, other panels swap the view tree without transition, no Esc/click-outside (P3–P6, BB-08, R6) |
| C5 | Sidebar looks like a window inside a window | sidebar/queue laid out in an HStack column that shrinks the video (P2, CMP-04, R7) |
| C6 | Scrubbing updates every few seconds | unthrottled per-event seeks + full state snapshots on main, thumbnail requests cancelled before sent (BB-01, BB-02, BB-03, ARC-02/03, R3) |
| C7 | Volume OSD out of sync | VLC core OSD left on alongside the redesign tooltip (CMP-06, ARC-04, BB-06, R8) |
