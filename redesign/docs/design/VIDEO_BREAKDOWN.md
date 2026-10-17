# VIDEO_BREAKDOWN: Juxtopposed, "I Redesigned VLC After 25 Years"

The design bible for the native macOS VLC interface. It walks through the source video section by section and turns each design decision into rules you can implement. Pixel values, colors and full item lists are in the specs ([spec-part1](../../design/spec/spec-part1.md), [spec-part2](../../design/spec/spec-part2.md)), so this document does not repeat them. It explains **what** is built, **why**, and **where to look**.

## About the source

- **Video:** Juxtopposed, *I Redesigned VLC After 25 Years*, YouTube, published 2026-10-12, 21:00 long. https://www.youtube.com/watch?v=ERFeOgqk324
- **Design file:** Figma community file, https://www.figma.com/community/file/1691465999134370980. The design is licensed **CC BY 4.0**, so credit Juxtopposed in the About box and the README.
- **The video and its frames are copyrighted and are never committed.** They live outside the repo at `../reference/video/` (relative to the repo root `vlc-redesign-macos/`):
  - `juxtopposed-vlc-redesign-1080p.mp4`: the video at 1080p.
  - `transcript.txt`: the transcript in timestamped blocks of about 30 s.
  - `audio.srt`: word-level timings. Use it to find exact moments.
  - `frames/NN-topic/MMmSS.SSs.jpg`: 714 scene-change frames in 16 topic folders, plus `_sponsor-skip` and `_outro`. The spec files cite frames by these folder and file names. Their old prefix `research/video/frames/` now means `../reference/video/frames/`.
  - `key-frames/`: the 100 frames linked from this document, renamed `<topic>__<what>__<MMmSS.Ss>.jpg`. Captions for all of them are in [`key-frames/INDEX.md`](../../../../reference/video/key-frames/INDEX.md).
- **Regenerating the local material:** run `redesign/tools/fetch-reference.sh`. Another agent maintains that script. If `../reference/video/` is missing, run it first. The key-frame links below only work once the material exists locally.
- **Figma renders** (committed, 2x PNG) are in [`redesign/design/figma/renders/`](../../design/figma/renders/). Token values are in `renders/styles.txt` and `design/figma/palette/`.

## How to read this document

- There is one section per video chapter, in video order. Each section has: **time range** · **problem → decision** (her reasoning, paraphrased) · **rules** · **key frames** · **Figma renders** · **spec link** · **phase**.
- Rule keywords:
  - **MUST**: shown or stated in the video or Figma. Do not deviate without a recorded decision.
  - **SHOULD**: strongly implied, or a sensible macOS adaptation.
  - **OPEN**: not shown anywhere. Follow [Design principles distilled](#design-principles-distilled).
- Frame status words, in captions and in the specs:
  - **native**: the window fills the 1920x1080 frame at 1:1, so measurements are valid.
  - **interim**: a step she later replaced.
  - **OLD** (`00-old-vlc__*`): current VLC, for contrast only.
- **The video shows iterations. When the video and Figma disagree:** take the look (sizes, colors, final wording of menus) from Figma, because Figma holds the final screens. Take behavior and relations (what opens what, what is remembered) from the video narration. Either way, the last version shown in the video beats earlier ones.
- **Phases:**
  - **P1**: player shell and controls
  - **P2**: side panels and subtitles
  - **P3**: library, music, streams, playlists
  - **P4**: settings and hotkeys
  - **P5**: customization, onboarding, profiles

## Contents

| # | Section | Time | Phase |
|---|---|---|---|
| 01 | [Identity: colors, icons, shape](#01-identity-colors-icons-shape) | 00:00–01:32 | P1 |
| 02 | [Control bar, seek bar, volume, queue](#02-control-bar-seek-bar-volume-queue) | 01:32–03:30 | P1 (queue panel P2) |
| 03 | [Top bar, fullscreen, hover reveal](#03-top-bar-fullscreen-hover-reveal) | 03:30–04:04 | P1 |
| 04 | [Subtitle and audio buttons, track popover](#04-subtitle-and-audio-buttons-track-popover) | 04:04–05:00 | P2 |
| 05 | [Menus: app menu, right-click, hide UI](#05-menus-app-menu-right-click-hide-ui) | 05:00–05:30 | P1 |
| 06 | [Add Subtitles dialog](#06-add-subtitles-dialog) | 05:30–06:30 | P2 |
| 07 | [Settings sidebar and subtitle timeline](#07-settings-sidebar-and-subtitle-timeline) | 06:30–09:20 | P2 |
| 08 | [Media library, compact library, mini player](#08-media-library-compact-library-mini-player) | 09:20–12:00 | P3 |
| 09 | [Music](#09-music) | 12:00–12:20 | P3 |
| 10 | [Network streams and open dialogs](#10-network-streams-and-open-dialogs) | 12:20–13:15 | P3 |
| 11 | [Playlists, pins, recent, home](#11-playlists-pins-recent-home) | 13:15–14:00 | P3 |
| 12 | [Continue-watching prompt](#12-continue-watching-prompt) | 14:00–14:12 | P1 |
| 13 | [Bookmarks, chapters, OSD](#13-bookmarks-chapters-osd) | 14:45–15:28 | P2 (OSD P1) |
| 14 | [Settings window and hotkeys](#14-settings-window-and-hotkeys) | 15:28–18:45 | P4 |
| 15 | [Customization, profiles, onboarding](#15-customization-profiles-onboarding) | 18:45–20:00 | P5 |
| 16 | [Final showcase](#16-final-showcase) | 20:00–20:46 | (no new screens) |
| | [Design principles distilled](#design-principles-distilled) · [Cross-reference table](#cross-reference-video-section--figma-renders--spec--phase) · [Spec corrections](#corrections-to-the-specs-found-while-making-this-breakdown) | | |

The sponsor segment (14:12–14:45) and the outro (20:46–21:00) contain no design content.

---

## 01 Identity: colors, icons, shape

**Time:** 00:00–01:32. Intro and survey (00:00–00:34), then the "styles" and "colors" chapter cards.

**Problem → decision.**
- **Problem.** People call VLC old. She argues its real problems are hidden functions and scattered menus, not age. She surveyed about 1.4k viewers and asked VLC's creator for his priorities: main UI (toolbars, sidebar), media library, player menus and playback.
- **Cone and orange.** She keeps the traffic cone and the orange, and adds only neutral grays and near-blacks.
- **Icons.** She keeps VLC's two-tone gray-and-orange icon style, modernized and made consistent. It is reserved for **non-clickable** menu icons. A separate **monochrome** set is used for everything clickable.
- **Shape.** Other players are round. VLC's sharp, rectangular look is its personality, so it stays **rectangular, just a little less sharp**.

**Rules.**
- MUST: The palette is the cone orange (plus its tints and shades), 4 neutral grays, and 4 near-black surfaces. Nothing else. Take the values from the Figma tokens (`styles.txt`), not from sampled video pixels.
- MUST: Every orange in the UI comes from one **accent** token. Section 14 lets the user change the accent color, so no orange may be hard-coded.
- MUST: The logo is the flat, glossless orange cone with transparent stripe gaps. It also appears small at the far left of the top bar.
- MUST: Two icon systems:
  - **Decorative:** two-tone, gray stroke plus an orange part, used for menu rows and other non-interactive glyphs.
  - **Clickable:** monochrome gray, same geometry. Some shapes simplify; for example, the folder tab becomes part of the outline.
- MUST: The active, toggled or open state of a clickable icon is **orange**, and many icons switch to a **filled** variant (subtitles, gear, rail categories, settings categories).
- MUST: Shapes are rectangles with modest radii. The play button is a wide rounded rectangle, about 2:1. Pills and circles are not used, except for the slider and seek **handles**, which are capsules.
- SHOULD: Use Inter as the UI font (it is what the Figma file uses) or SF Pro. Her chapter cards use IBM Plex Sans, which is video styling, not UI.

**Key frames.**
- [`01-identity__palette-cone-orange-gray-black__00m58.4s.jpg`](../../../../reference/video/key-frames/01-identity__palette-cone-orange-gray-black__00m58.4s.jpg): Palette slide: flat cone, main orange + 4 oranges, 4 grays, 4 near-blacks with hairline outlines.
- [`01-identity__decorative-vs-clickable-icon-sets__01m14.5s.jpg`](../../../../reference/video/key-frames/01-identity__decorative-vs-clickable-icon-sets__01m14.5s.jpg): Two icon sets: "decorative" two-tone gray+orange (menus, not clickable) above "clickable" monochrome.
- [`01-identity__play-button-sharp-square__01m27.0s.jpg`](../../../../reference/video/key-frames/01-identity__play-button-sharp-square__01m27.0s.jpg): Play button morph, step 1: sharp square orange tile with a rounded dark triangle.
- [`01-identity__play-button-rounded-rect-final__01m31.0s.jpg`](../../../../reference/video/key-frames/01-identity__play-button-rounded-rect-final__01m31.0s.jpg): Play button morph, end: wide rounded rectangle (~2:1), "rectangular but a little less sharp".

**Figma renders.** [`Icon.png`](../../design/figma/renders/Icon.png) (the full icon sheet: gray, two-tone and solid-orange variants) · [`Icon Wrapper.png`](../../design/figma/renders/Icon%20Wrapper.png) · [`Button.png`](../../design/figma/renders/Button.png) · [`play.png`](../../design/figma/renders/play.png) · [`Components.png`](../../design/figma/renders/Components.png) · [`Designs.png`](../../design/figma/renders/Designs.png) · tokens in [`styles.txt`](../../design/figma/renders/styles.txt).

**Spec.** [spec-part1 §0 Design tokens](../../design/spec/spec-part1.md#0-design-tokens-global) · [§0.6 Principles](../../design/spec/spec-part1.md#06-principles-her-stated-reasoning-paraphrased) · [§01](../../design/spec/spec-part1.md#01--intro-colors-icons-00000130). **Phase:** P1 (tokens and icons are needed by every phase).

---

## 02 Control bar, seek bar, volume, queue

**Time:** 01:32–03:30.

**Problem → decision.**
- **Goal.** Most people want to click a video and get a quiet bar that does its job. VLC's bar is quiet but useless.
- **Play stays left.** She rejects the centered play button (VLC 4's work in progress, other players). It is less unique and makes the bar huge, and most people (87%) play and pause from the keyboard. Play stays at the **left**, a bit bigger, with prev and next around it.
- **Right side.** Fullscreen and settings move to the **right**, as in most players.
- **Queue.** "Toggle playlist" is really a **queue**: the queue plays things automatically, while playlists are saved collections. The button becomes a queue icon on the right, opening a panel you drag files into.
- **Volume.** The odd triangle "looks like a deformed cone", so it becomes a full **cone** in VLC's colors.
- **Seek bar.** It drops into the same row and becomes **thick** ("trust the process").
- **Result.** One thin row that does not disrupt the video, plus a **thumbnail preview while seeking**.

**Rules.**
- MUST: One bottom row, final default order from left to right:
  - prev · **play/pause** · next
  - elapsed time · **seek bar** (fills the free width) · total time
  - speaker (mute) · **volume cone**
  - **audio tracks** · **subtitle tracks** · **playback-settings gear** · **queue**
- MUST: Fullscreen is not in the default bottom bar. It is in the top bar (section 03).
- MUST: The play button keeps its fixed place at the left.
  - **Paused:** orange background with a dark ▶.
  - **Playing:** gray background with a dark ⏸ (04m06.7 vs 04m10.9; Figma `play.png`).
- MUST: There is no Stop button in the default bar. Stop remains in the right-click menu, as a Customize tile, and on its shortcut.
- MUST: Repeat and shuffle leave the bar and live in the queue header.
- MUST: The seek bar is **thick** (about 28 px tall at 1080p): black track, dark accent-tinted elapsed fill, and an orange **capsule handle** about as tall as the bar. No hairline sliders anywhere.
- MUST: Hovering anywhere on the seek bar shows a floating **preview card** above the pointer: frame thumbnail plus timestamp. While dragging, the elapsed label follows.
- MUST: Volume is a horizontal **cone**: rounded tip on the left, wide end on the right.
  - The fill grows from the tip, with a green→amber gradient mapped over the full length.
  - No knob and no % label in the final design.
  - Click or drag inside the cone sets the level.
  - Keep VLC's boost above 100% (the gradient reaching amber signals it).
- MUST: The queue button toggles a floating **queue panel** at the right of the video. The button is orange while the panel is open.
  - Header: "N items - total duration", then icon buttons sort · repeat · shuffle · remove (−) · add (+).
  - Rows: drag handle, filename, right-aligned duration. The current item shows an orange ▶ and an orange name.
  - Drag files from Finder or the library into the panel, and drag rows to reorder.
  - Section 13 turns this panel into the **Queue tab** of the right sidebar.
- SHOULD: Time labels are `hh:mm:ss` with tabular digits.
- SHOULD (Figma only, not in the video):
  - `Current Time.png` shows the elapsed time turning into an **editable field** (hover background, then a caret), meaning click it to type a time and jump.
  - `Duration.png` shows the total time toggling to **remaining** (`-00:23:30`).
- SHOULD: For audio files the bar gains **−15 s / +15 s** buttons around play, and the seek bar can become a waveform (section 09).
- DECIDED (not in the video): bar-icon hover is the white 6 % radius-4 tile of Icon Wrapper 177:99 with the glyph kept FG/A2 (D048); pressing adds no highlight or focus ring (D028); the wheel over the cone changes the volume (D047); mute keeps the speaker glyph in its active (accent) state with an empty cone. See spec-part1 §02 open questions.

**Key frames.**
- [`02-control-bar__prev-play-next-around-play-interim__02m15.1s.jpg`](../../../../reference/video/key-frames/02-control-bar__prev-play-next-around-play-interim__02m15.1s.jpg): Interim: play stays left, a bit bigger, prev/next placed around it, stop removed.
- [`02-control-bar__queue-panel-first-look__02m50.1s.jpg`](../../../../reference/video/key-frames/02-control-bar__queue-panel-first-look__02m50.1s.jpg): First queue panel: "2 items - 48m", sort/repeat/shuffle/-/+, drag handles and durations.
- [`02-control-bar__seek-thumbnail-preview__03m29.3s.jpg`](../../../../reference/video/key-frames/02-control-bar__seek-thumbnail-preview__03m29.3s.jpg): Seek preview card: frame thumbnail + timestamp above the thick seek bar while hovering.
- [`02-control-bar__final-bar-playing-state-native__04m06.7s.jpg`](../../../../reference/video/key-frames/02-control-bar__final-bar-playing-state-native__04m06.7s.jpg): Native 1:1 player while playing: play button turns gray (pause glyph); no track icons yet.
- [`02-control-bar__final-bar-paused-native__04m10.9s.jpg`](../../../../reference/video/key-frames/02-control-bar__final-bar-paused-native__04m10.9s.jpg): Native 1:1 player paused: orange play, time, thick seek bar, duration, speaker, cone, gear, queue.
- [`02-control-bar__volume-cone-gradient-closeup__04m30.4s.jpg`](../../../../reference/video/key-frames/02-control-bar__volume-cone-gradient-closeup__04m30.4s.jpg): Close-up: duration, speaker, volume cone (green to amber gradient), gear-with-play, queue icon.
- [`02-control-bar__final-layout-with-track-icons-native__06m24.4s.jpg`](../../../../reference/video/key-frames/02-control-bar__final-layout-with-track-icons-native__06m24.4s.jpg): Native 1:1 FINAL default layout: top bar (cone, ..., title, min/max/fullscreen/close) and bottom bar with audio + subtitle icons.
- [`02-control-bar__play-button-closeup__20m23.6s.jpg`](../../../../reference/video/key-frames/02-control-bar__play-button-closeup__20m23.6s.jpg): Showcase close-up of the play button: orange rounded rect, dark rounded triangle.
- OLD, for contrast: [`00-old-vlc__default-control-bar-quiet-useless__01m37.5s.jpg`](../../../../reference/video/key-frames/00-old-vlc__default-control-bar-quiet-useless__01m37.5s.jpg): VLC 3 playing video.mp4: tiny buttons, thin blue seek bar. The "quiet but kinda useless" bar she starts from.
- OLD, for contrast: [`00-old-vlc__vlc4-wip-centered-play-rejected__01m56.8s.jpg`](../../../../reference/video/key-frames/00-old-vlc__vlc4-wip-centered-play-rejected__01m56.8s.jpg): VLC 4 work-in-progress bar with a centered round play button. She rejects the centered play.
- OLD, for contrast: [`00-old-vlc__volume-triangle-percent__03m02.4s.jpg`](../../../../reference/video/key-frames/00-old-vlc__volume-triangle-percent__03m02.4s.jpg): VLC 3 volume: a triangle with a % label. It becomes the volume cone.

**Figma renders.** [`Controls.png`](../../design/figma/renders/Controls.png) · [`Player-6.png`](../../design/figma/renders/Player-6.png) (player with bars) · [`play.png`](../../design/figma/renders/play.png) · [`Current Time.png`](../../design/figma/renders/Current%20Time.png) · [`Duration.png`](../../design/figma/renders/Duration.png) · [`volume.png`](../../design/figma/renders/volume.png) (cone fill levels) · [`audio value.png`](../../design/figma/renders/audio%20value.png) (volume value chip) · [`thumbnail.png`](../../design/figma/renders/thumbnail.png) (seek preview) · [`playlist.png`](../../design/figma/renders/playlist.png).

**Spec.** [spec-part1 §02](../../design/spec/spec-part1.md#02--control-bar-seek-bar-volume-01300330) · [Appendix A cheat-sheet](../../design/spec/spec-part1.md#appendix-a--measured-native-layout-cheat-sheet-1920x1080) · [Appendix B states](../../design/spec/spec-part1.md#appendix-b--state-summary). **Phase:** P1 (queue panel P2).

---

## 03 Top bar, fullscreen, hover reveal

**Time:** 03:30–04:04.

**Problem → decision.**
- **Problem.** VLC hides the title in fullscreen, yet 86.8% of surveyed users look at the **top** for the title. Leaving fullscreen just to read it is absurd.
- **Decision.** Keep **both** bars, top and bottom, in fullscreen. Show each when you **hover near it** and hide it **immediately** when you move away.
- **Restyle.** The top row gets the new style.
- **Fullscreen and PiP.** She likes a fullscreen icon (and maybe picture-in-picture) up in the top bar and asks viewers to choose. The final frames keep **fullscreen** in the top bar, and PiP is a Customize tile.

**Rules.**
- MUST: One thin top row, in the same dark chrome as the bottom bar.
  - **Left:** cone logo · `⋯` app menu (section 05) · [when a library folder is known: sidebar-toggle icon · divider · folder icon + folder name, see section 08].
  - **Center:** media title, or "VLC Media Player" when nothing is playing.
  - **Right:** window controls and **fullscreen**.
- MUST: Bars show and hide **independently**. The pointer near the top reveals the top bar only (03m51.0), and near the bottom reveals the control bar only (03m53.0). They hide right after the pointer leaves the zone. This applies in fullscreen, and in a window when bars are not pinned.
- MUST: In the bars-hidden state in a window, only the rounded video remains, inside a thin frame of chrome color. In fullscreen there is no frame.
- MUST: The bars overlay the video in fullscreen. The video must not jump when they appear.
- SHOULD (macOS): use the native traffic lights for close, minimize and zoom in a full-size-content title bar, and keep her flat **fullscreen** (and optional PiP) glyphs at the right. The top bar is the window drag region.
- OPEN: exact hover zone size and fade timing. Suggestion in spec-part1 §03: about one bar height, 120–150 ms fade.

**Key frames.**
- [`03-top-bar__both-bars-on-hover-interim__03m47.6s.jpg`](../../../../reference/video/key-frames/03-top-bar__both-bars-on-hover-interim__03m47.6s.jpg): Interim window with both bars visible (still the text menu bar at top-left).
- [`03-top-bar__hover-top-bar-only__03m51.0s.jpg`](../../../../reference/video/key-frames/03-top-bar__hover-top-bar-only__03m51.0s.jpg): Hover reveal: pointer near the top shows only the top bar (title + window controls).
- [`03-top-bar__hover-bottom-bar-only__03m53.0s.jpg`](../../../../reference/video/key-frames/03-top-bar__hover-bottom-bar-only__03m53.0s.jpg): Hover reveal: pointer near the bottom shows only the control bar.
- [`03-top-bar__bars-hidden-thin-frame__03m53.6s.jpg`](../../../../reference/video/key-frames/03-top-bar__bars-hidden-thin-frame__03m53.6s.jpg): Bars hidden: only the video, inside a thin dark frame in windowed mode.
- [`03-top-bar__window-controls-pip-fullscreen-option__04m00.7s.jpg`](../../../../reference/video/key-frames/03-top-bar__window-controls-pip-fullscreen-option__04m00.7s.jpg): Window-control option: minimize, picture-in-picture, maximize, fullscreen, close (she polls viewers).

**Figma renders.** [`Player-6.png`](../../design/figma/renders/Player-6.png) · [`Player - hide UI.png`](../../design/figma/renders/Player%20-%20hide%20UI.png) (bars hidden) · [`Player.png`](../../design/figma/renders/Player.png) (top bar with library chip).

**Spec.** [spec-part1 §03](../../design/spec/spec-part1.md#03--top-bar-fullscreen-hover-behavior-03300400). **Phase:** P1.

---

## 04 Subtitle and audio buttons, track popover

**Time:** 04:04–05:00.

**Problem → decision.**
- **Problem.** Switching subtitles takes right-click → Subtitle → Sub Track, and the menus keep closing. VLC 4 puts a tracks icon at the bottom **left**, but 80.8% of surveyed users look for it at the bottom **right**.
- **Subtitles button.** A **subtitles** button on the right lists subtitle tracks.
- **Audio button.** Next to it, an **audio** button lists audio tracks **and the audio output device** (speakers or headphones), so you never leave VLC to switch output.
- **Video tracks.** They get a third tab, but no bar icon, because most people rarely change them. They remain reachable through the tab and the right-click menu.

**Rules.**
- MUST: The bar has an **audio** button (waveform icon) and a **subtitles** button (caption-box icon) to the left of the gear.
- MUST: Each button opens the same floating **track popover**, anchored at the bottom right above the bar, with its tab preselected.
  - The tabs are **Video · Audio · Subtitles**.
  - The active tab has an orange icon and a 2 px orange underline.
- MUST: Tab contents:
  - **Audio:** Embedded Tracks (None plus each track) · divider · **Output Device** list with a refresh button.
  - **Subtitles:** Embedded Tracks · divider · **External Tracks** with edit (pencil) and **add (+)**. The + opens the Add Subtitles dialog (section 06).
  - **Video:** Embedded Tracks.
  - Every tab ends with a full-width **Show Preferences** button, which opens the settings sidebar (section 07) on the matching tab.
- MUST: The selected row shows an orange ✓. Picking a row **does not close** the popover.
- MUST: While its popover is open, the bar icon is orange. Subtitles turns into a filled orange caption box.
- SHOULD: Clicking outside or pressing Esc closes the popover. A short fade/slide is fine (not shown).
- SHOULD (macOS): map Output Device to CoreAudio devices through VLC's audio output device list, and refresh on device change notifications.

**Key frames.**
- [`04-track-popover__audio-tab-tracks-output-device__04m42.4s.jpg`](../../../../reference/video/key-frames/04-track-popover__audio-tab-tracks-output-device__04m42.4s.jpg): Track popover, Audio tab: Embedded Tracks, Output Device (Speakers/Headphones) with refresh, Show Preferences.
- [`04-track-popover__bar-icons-audio-subs-gear-queue__04m48.4s.jpg`](../../../../reference/video/key-frames/04-track-popover__bar-icons-audio-subs-gear-queue__04m48.4s.jpg): Close-up of the right cluster: speaker, cone, audio (waveform), subtitles, gear, queue.
- [`04-track-popover__video-tab__04m54.8s.jpg`](../../../../reference/video/key-frames/04-track-popover__video-tab__04m54.8s.jpg): Video tab added to the popover (no bar icon for it); old right-click path shown at left.
- [`04-track-popover__subtitles-tab-external-tracks-native__06m21.7s.jpg`](../../../../reference/video/key-frames/04-track-popover__subtitles-tab-external-tracks-native__06m21.7s.jpg): Native: Subtitles tab with Embedded Tracks and External Tracks (pencil + add), subtitle icon filled orange.
- OLD, for contrast: [`00-old-vlc__right-click-subtitle-sub-track__04m15.9s.jpg`](../../../../reference/video/key-frames/00-old-vlc__right-click-subtitle-sub-track__04m15.9s.jpg): VLC 3 right-click > Subtitle > Sub Track: too many clicks to switch subtitles.

**Figma renders.** [`Player-6.png`](../../design/figma/renders/Player-6.png) · [`Dropdown.png`](../../design/figma/renders/Dropdown.png) · [`option.png`](../../design/figma/renders/option.png) (row states). No dedicated popover render was identified, so build it from the video frames and the spec.

**Spec.** [spec-part1 §04](../../design/spec/spec-part1.md#04--subtitle-and-audio-buttons-track-popover-04000500). **Phase:** P2.

---

## 05 Menus: app menu, right-click, hide UI

**Time:** 05:00–05:30.

**Problem → decision.**
- **No duplicate menus.** The old top menu bar repeats the right-click menu item for item. She removes it and keeps **one `⋯` menu icon** for media-related actions and extra settings.
- **Right-click stays.** Users reflexively right-click for settings, so the context menu is kept, cleaned up and restyled.
- **Hide UI.** She adds an option to **hide the UI completely**, also available by shortcut (Ctrl + \\).

**Rules.**
- MUST: The `⋯` button in the top bar opens the **app menu**.
  - Rows: two-tone decorative icon, label, and the shortcut right-aligned in dim text, or a chevron for a submenu. Dividers group the rows.
  - The final item list is the one in section 15 (19m29.4) and Figma `menu.png` / `Profiles.png`, not the first version shown here.
- MUST: The **right-click menu** has these groups:
  - transport (Play, Stop, Previous, Next, Record)
  - submenus Playback › Video › Audio › Subtitle ›
  - More Settings › · Playlist › · Open Media ›
  - Quit
  - Figma `right-click menu.png` also adds **Hide UI**. Implement that list.
- MUST: **Hide UI** removes all chrome, leaving only the video. A shortcut toggles it back.
- SHOULD (macOS):
  - Map Ctrl to ⌘ in displayed shortcuts.
  - Mirror the app-menu actions in the **native macOS menu bar**, which is required on macOS and harmless because it is not on screen.
  - Hide UI is ⌘\\, and it must also be reachable from the menu bar so the user can always recover.
- OPEN: submenu contents are not shown, so take them from VLC's existing menus, cleaned up. Hover row styling is shown only in later frames (16m02.8, 19m35.4).

**Key frames.**
- [`05-menus__app-menu-first-version__05m09.0s.jpg`](../../../../reference/video/key-frames/05-menus__app-menu-first-version__05m09.0s.jpg): First "..." app menu replacing the menu bar (later cleaned up, see 10 and 15).
- [`05-menus__player-near-final-layout__05m15.0s.jpg`](../../../../reference/video/key-frames/05-menus__player-near-final-layout__05m15.0s.jpg): Player with the "..." menu button, title centered, four window controls; near-final layout.
- [`05-menus__right-click-menu-cleaned__05m23.0s.jpg`](../../../../reference/video/key-frames/05-menus__right-click-menu-cleaned__05m23.0s.jpg): Cleaned right-click menu with two-tone icons, shortcuts and submenus.
- [`05-menus__hide-ui-ctrl-backslash__05m29.0s.jpg`](../../../../reference/video/key-frames/05-menus__hide-ui-ctrl-backslash__05m29.0s.jpg): Keycaps CTRL + \ : shortcut to hide the whole UI.
- OLD, for contrast: [`00-old-vlc__menubar-duplicates-right-click__05m03.0s.jpg`](../../../../reference/video/key-frames/00-old-vlc__menubar-duplicates-right-click__05m03.0s.jpg): VLC 3 menu bar and right-click menu side by side: same items twice.

**Figma renders.** [`menu.png`](../../design/figma/renders/menu.png) (final app menu) · [`right-click menu.png`](../../design/figma/renders/right-click%20menu.png) · [`context menu.png`](../../design/figma/renders/context%20menu.png) (generic menu rows) · [`Profiles.png`](../../design/figma/renders/Profiles.png).

**Spec.** [spec-part1 §05](../../design/spec/spec-part1.md#05--menus--app-menu-and-right-click-menu-05000530) · final menu list in [spec-part2 §10 B](../../design/spec/spec-part2.md#10-network-streams-and-open-dialogs). **Phase:** P1.

---

## 06 Add Subtitles dialog

**Time:** 05:30–06:30. The "player settings" chapter card is at 05:36.

**Problem → decision.**
- **Problem.** Third-party subtitles mean downloading a zip, extracting it, and then the names do not match. VLC matches similar names, but you often end up dragging a subtitle onto every single episode.
- **Decision.** **Add (+)** in the subtitles popover opens a dialog with:
  - **scope:** this file / this folder / this playlist
  - **source:** this computer / a website such as OpenSubtitles
- **Matching.** Subtitles are **auto-matched** to every episode, or matched manually per row, and the result is **saved for all future episodes**.

**Rules.**
- MUST: The modal dialog "Add Subtitles" is centered over the player.
  - Toolbar: **scope dropdown** (To This File / To This Folder / To This Playlist) · **source dropdown** (From Computer / From OpenSubtitles; Figma `origin.png` adds **From Link…**) · **search field** (prefilled with the show and season) · **language dropdown**.
- MUST: The body is a two-column mapping: video file on the left, matched subtitle file on the right, joined by a dashed connector.
  - Hovering a row highlights it and shows a **swap** icon to pick a different file manually.
  - Figma `subtitle one.png` and `subtitle multiple.png` show the selected-match states.
- MUST: The footer has **Cancel** (secondary) and **Save** (primary: accent-tinted background, orange label).
- MUST: After Save, the files appear under **External Tracks** in the popover (06m21.7), and the mapping persists for that folder or playlist.
- SHOULD: Matching runs automatically as soon as scope and source are set. Unmatched rows show an empty right cell with the swap action.
- OPEN: OpenSubtitles requires an account and an API key. It needs a product decision before shipping, so ship From Computer first.

**Key frames.**
- [`06-add-subtitles__dialog-empty-native__06m02.5s.jpg`](../../../../reference/video/key-frames/06-add-subtitles__dialog-empty-native__06m02.5s.jpg): Native: empty Add Subtitles dialog over the player (geometry reference).
- [`06-add-subtitles__scope-dropdown-file-folder-playlist__06m08.5s.jpg`](../../../../reference/video/key-frames/06-add-subtitles__scope-dropdown-file-folder-playlist__06m08.5s.jpg): Scope dropdown: To This File / To This Folder / To This Playlist.
- [`06-add-subtitles__auto-matched-episode-list__06m14.5s.jpg`](../../../../reference/video/key-frames/06-add-subtitles__auto-matched-episode-list__06m14.5s.jpg): Populated: scope, source "From OpenSubtitles", search, language; every episode matched to a .srt.
- [`06-add-subtitles__row-hover-swap-icon__06m20.5s.jpg`](../../../../reference/video/key-frames/06-add-subtitles__row-hover-swap-icon__06m20.5s.jpg): Row hover: highlighted match with a swap icon to pick a different file manually; Cancel/Save.

**Figma renders.** [`Add Subtitles to Playlist/Folder.png`](../../design/figma/renders/Add%20Subtitles%20to%20Playlist/Folder.png) · [`Add Subtitles to Playlist/Folder-1.png`](../../design/figma/renders/Add%20Subtitles%20to%20Playlist/Folder-1.png) · [`Add Subtitles to Playlist/Folder-2.png`](../../design/figma/renders/Add%20Subtitles%20to%20Playlist/Folder-2.png) · [`Add Subtitles to Playlist/Folder-3.png`](../../design/figma/renders/Add%20Subtitles%20to%20Playlist/Folder-3.png) · [`target.png`](../../design/figma/renders/target.png) (scope dropdown) · [`origin.png`](../../design/figma/renders/origin.png) (source dropdown) · [`subtitle one.png`](../../design/figma/renders/subtitle%20one.png) · [`subtitle multiple.png`](../../design/figma/renders/subtitle%20multiple.png).

**Spec.** [spec-part1 §06](../../design/spec/spec-part1.md#06--subtitle-import-dialog-05300625). **Phase:** P2.

---

## 07 Settings sidebar and subtitle timeline

**Time:** 06:30–09:20.

**Problem → decision.**
- **Problem.** The old "Adjustments and Effects" window (behind the sliders icon) holds half of the in-playback settings, subtitle timing included, and covers half the screen. You use it, close it, rewind, and repeat ten times.
- **Subtitle timeline.** A **subtitle timeline in the seek bar** shows when each line appears: pause on the audio and nudge the subtitles into place.
- **Sidebar.** All these preferences move into a **right sidebar with four tabs**.
- **Sliders and sizes.** Typed values get **sliders**. Subtitle font, size, outline and position are adjustable while watching, with **Relative or Pixels** sizes. Precise sizes already exist in VLC but are buried.
- **Presets per show.** Settings are saved as **presets per show** and reselected later.
- **Defaults.** A **default subtitle track and language** are set right here instead of deep in Input/Codecs.
- **Audio.** Same treatment: default track and delay, plus expandable filters. The equalizer is for experts, and friendly **presets with preview icons** are for everyone else.
- **Video.** Same treatment for filters (with previews), plus flip, rotate, zoom, HDR, resolution, aspect ratio and crop.
- **Playback tab.** Speed, reverse, sleep timer, show subtitle timeline, show waveform on seek bar, show metadata.

**Rules.**
- MUST: The **gear** in the bar toggles a floating right **settings sidebar**, the same width and position as the popover and queue.
  - The gear turns filled orange while it is open.
  - Tabs, in the final order: **Playback · Video · Audio · Subtitles** (09m17.5).
  - "Show Preferences" in the track popover opens it on the matching tab.
- MUST: Every numeric setting is a **typed value with its unit plus a slider**. Bipolar values (delays, EQ bands) use a slider centered on 0, with the fill running from the center.
- MUST: The sidebar shows section headers (Defaults, Synchronization, Appearance, Filters) separated by dividers. Expandable groups use an "Expand Settings ›" / "Collapse Settings" row.
- MUST: **Subtitles tab:**
  - **Defaults:** Subtitle Track, Subtitle Language.
  - **Synchronization:** Track Delay, Speed, Duration Factor, each with a slider.
  - **Appearance:** Embedded Sub Format toggle, Font, Text Color, Outline Color, Offset, **Size Values Relative | Pixels**, Font Size, Outline Thickness, Background Opacity. Relative mode shows word sliders (Auto, Normal); Pixels mode shows exact px fields.
- MUST: **Presets.** At the bottom of the sidebar, a preset selector (Figma `Setting Preset.png`: a "Default Preset ⌃" dropdown) opens a list:
  - "+ New Preset/New Custom Preset" first
  - then the saved presets, each with a `⋯` menu, the current one checked.
  - A preset stores the captured **Subtitles, Audio and Video** sections and their default tracks, and is meant to be per show. The Playback tab has no preset footer in Figma `5187:24308` (D033). The former "all four tabs" wording was an internal extrapolation, not a verified quotation from the video; do not add a Playback preset merely to satisfy it.
  - The footer link is "⚙ Open Advanced Settings" (opens section 14).
- MUST: **Audio tab:**
  - **Defaults:** Audio Track, Audio Language, Stereo Mode with a Test button.
  - **Synchronization:** Audio Track Delay.
  - **Filters:** Equalizer dropdown with **preset preview icons** (tiny EQ curves) and an expandable band editor (Preamp plus bands); Stereo Widener toggle plus expand. Figma adds Compressor and Spatializer cards.
- MUST: **Video tab:**
  - **Defaults:** Flip (None / Horizontal / Vertical), Rotate, Zoom, HDR, Resolution, Aspect Ratio, Crop, Render.
  - **Filters:** cards such as Essential, Colors, Crop, with previews.
- MUST: **Playback tab** (complete list, 09m17.5): Show Subtitle Timeline on Seekbar · Show Waveform on Seekbar · Show Metadata · Reverse · Sleep Timer · Audio Visualizer (Figma: Disabled / Spectrometer / Scope / Spectrum / Waveform) · Speed (typed value plus slider with ticks 0.25 to 2).
- MUST: **Subtitle timeline mode** is turned on by "Show Subtitle Timeline on Seekbar".
  - The seek bar becomes a zoomed time window, with the range labels marked `*`.
  - Each subtitle cue is drawn as a block as long as the cue, dimmed differently before and after the playhead.
  - Small orange buttons sit at the bar ends: **‹ −** on the left, **+ ›**. **− / +** shift the subtitle delay (same as the `[` / `]` hotkeys), and **‹ / ›** scroll the window.
- SHOULD: The sidebar overlays the right side of the video, as in every frame. It does not push or shrink the video. The body scrolls.
- OPEN: toggle ON state (use Figma `Toggle.png`), video filter preview thumbnails, Show Metadata content (suggestion: a file-info panel).

**Key frames.**
- [`07-sidebar__subtitle-timeline-closeup__06m58.2s.jpg`](../../../../reference/video/key-frames/07-sidebar__subtitle-timeline-closeup__06m58.2s.jpg): Subtitle timeline in the seek bar: cue blocks, playhead, orange nudge buttons at both ends.
- [`07-sidebar__subtitle-timeline-native__07m04.2s.jpg`](../../../../reference/video/key-frames/07-sidebar__subtitle-timeline-native__07m04.2s.jpg): Native: subtitle timeline mode with range labels marked "*".
- [`07-sidebar__subtitles-sync-sliders-appearance__07m47.9s.jpg`](../../../../reference/video/key-frames/07-sidebar__subtitles-sync-sliders-appearance__07m47.9s.jpg): Subtitles tab: sync values each with a slider (delay is bipolar), Appearance section below.
- [`07-sidebar__subtitles-appearance-pixels-mode__07m52.9s.jpg`](../../../../reference/video/key-frames/07-sidebar__subtitles-appearance-pixels-mode__07m52.9s.jpg): Appearance in Pixels mode: Relative/Pixels segmented control, exact px fields.
- [`07-sidebar__subtitles-presets-list__07m58.9s.jpg`](../../../../reference/video/key-frames/07-sidebar__subtitles-presets-list__07m58.9s.jpg): Preset list: + New Custom Preset, named presets with "..." menus, current preset checked.
- [`07-sidebar__subtitles-defaults-track-language__08m37.0s.jpg`](../../../../reference/video/key-frames/07-sidebar__subtitles-defaults-track-language__08m37.0s.jpg): Defaults section: Subtitle Track and Subtitle Language right in the sidebar.
- [`07-sidebar__audio-tab-defaults-sync__08m43.0s.jpg`](../../../../reference/video/key-frames/07-sidebar__audio-tab-defaults-sync__08m43.0s.jpg): Audio tab: default track/language, Stereo Mode + Test, audio delay slider, Filters.
- [`07-sidebar__audio-equalizer-expanded__08m49.0s.jpg`](../../../../reference/video/key-frames/07-sidebar__audio-equalizer-expanded__08m49.0s.jpg): Equalizer expanded ("Collapse Settings"): preamp and band values with sliders.
- [`07-sidebar__audio-eq-presets-preview-icons__08m55.0s.jpg`](../../../../reference/video/key-frames/07-sidebar__audio-eq-presets-preview-icons__08m55.0s.jpg): Equalizer presets dropdown with small curve preview icons; Stereo Widener below.
- [`07-sidebar__video-tab-flip-rotate-zoom__09m01.0s.jpg`](../../../../reference/video/key-frames/07-sidebar__video-tab-flip-rotate-zoom__09m01.0s.jpg): Video tab: Flip segmented, Rotate, Zoom, HDR, Resolution, Aspect Ratio, Crop.
- [`07-sidebar__playback-tab-full-toggles__09m17.5s.jpg`](../../../../reference/video/key-frames/07-sidebar__playback-tab-full-toggles__09m17.5s.jpg): Playback tab, complete: Show Subtitle Timeline, Show Waveform, Show Metadata, Reverse, Sleep Timer, Audio Visualizer, Speed.
- OLD, for contrast: [`00-old-vlc__input-codecs-default-subtitle-track__08m16.9s.jpg`](../../../../reference/video/key-frames/00-old-vlc__input-codecs-default-subtitle-track__08m16.9s.jpg): VLC 3 Advanced Preferences > Input/Codecs: where the default subtitle track hides today.

**Figma renders.**
- [`sidebar.png`](../../design/figma/renders/sidebar.png) (all sidebar states side by side)
- [`Setting Preset.png`](../../design/figma/renders/Setting%20Preset.png) · [`EQ presets.png`](../../design/figma/renders/EQ%20presets.png) · [`EQ.png`](../../design/figma/renders/EQ.png)
- [`Audio - Equalizer.png`](../../design/figma/renders/Audio%20-%20Equalizer.png) · [`Audio - Compressor Settings.png`](../../design/figma/renders/Audio%20-%20Compressor%20Settings.png) · [`Audio - Spatializer Settings.png`](../../design/figma/renders/Audio%20-%20Spatializer%20Settings.png) · [`Audio - Stereo Widener.png`](../../design/figma/renders/Audio%20-%20Stereo%20Widener.png)
- [`Video - Essential.png`](../../design/figma/renders/Video%20-%20Essential.png) · [`Video - Colors.png`](../../design/figma/renders/Video%20-%20Colors.png) · [`Video - Crop.png`](../../design/figma/renders/Video%20-%20Crop.png) · [`HDR Options.png`](../../design/figma/renders/HDR%20Options.png)
- [`Audio Visualizer.png`](../../design/figma/renders/Audio%20Visualizer.png) · [`Values.png`](../../design/figma/renders/Values.png) (segmented controls) · [`Toggle.png`](../../design/figma/renders/Toggle.png) · [`Button.png`](../../design/figma/renders/Button.png) (Show Advanced Settings).

**Spec.** [spec-part1 §07](../../design/spec/spec-part1.md#07--settings-sidebar-subtitles-audio-video-playback-tabs-06250920). **Phase:** P2.

---

## 08 Media library, compact library, mini player

**Time:** 09:20–12:00. The "library" chapter card is at 09:19.

**Problem → decision.**
- **Problem.** The fastest way to the next episode is a library, but VLC hides it. VLC 3 lumps all files together regardless of folder. VLC 4 sends you through "Browse" (with a Wi-Fi icon) and an internal file explorer, and back with a back button.
- **Cleaned-up library.**
  - Categories **Videos, Music, Network, Playlists**.
  - **Back/forward** buttons plus a **clickable address line** (breadcrumb).
  - Standard **sort, view-mode and search** controls in the header. Sorting used to exist only in the right-click menu, and it gains **Unwatched First / Watched First**.
  - A **⋯ more** menu with Add File, Add Folder and so on.
- **Opening it from the player.** She rejects a back icon, a home icon and a vague library icon. Instead the top bar shows the **name of the current folder** (e.g. "S01"), the most recognizable thing, with a **sidebar icon** next to it so it reads as something that opens.
- **Never leave the video.** The library opens in **compact mode beside the video**, and you **drag items into the queue**. A full-window library still exists, with a **draggable mini player** and its queue.

**Rules.**
- MUST: Top bar, left cluster when playing from a library folder: sidebar-toggle icon · divider · folder icon + **current folder name**.
  - Clicking either opens or closes the **compact library** at the current folder.
- MUST: The **compact library** is a narrow icon **rail** plus a panel at the left of the video.
  - **Rail:** category icons; the active one filled orange; it grows in section 11.
  - **Panel row 1:** ← → · breadcrumb (collapses ancestors to "…") · `⋯` more · open-full-library (↗).
  - **Panel row 2:** "N items" · sort · view mode · search.
  - **Rows:** 32 px thumbnail + name.
- MUST: Item states, everywhere in the library:
  - **now playing:** orange name and a ▶ over the thumbnail
  - **watched:** dimmed name and an orange progress line along the thumbnail bottom, whose length is the fraction watched
  - **hover:** shows `⋯` at the row end
- MUST: Drag a row from the library into the queue to append it (or insert at the placeholder, see 13). This is the primary flow.
- MUST: **Sort menu:** Unwatched First, Watched First, Newest First, Oldest First, Title A–Z, Title Z–A, with the current one checked. Figma `Sorting Options.png` extends it for music (artist, album, track number…).
- MUST: **View mode:** grid / list (Figma `View Options.png`). The video also mentions detail view.
- MUST: **More (⋯) menu:** Add File, Add Folder, Edit Subtitle Tracks, Edit Audio Tracks, Resync, Info. Figma `folder context menu.png` has the same list.
- MUST: The **full-window library** has its own layout:
  - floating nav panel on the left: Home, categories, Recent, + (section 11)
  - header: ← → · breadcrumb (current crumb bold) · count · sort · view · search field · ⋯
  - 16:9 thumbnail grid, or list
- MUST: The **mini player** floats over the full library: video preview, thin progress bar, title, folder chip, queue button.
  - The queue button expands a Queue section above the preview.
  - The card is **draggable** to any corner.
- MUST: The file context menu follows Figma `file context menu.png`: Play, Mark as Watched, Favorite, Stream, Convert, Add to Queue, **Add to Playlist**, Show in File Explorer (Finder on macOS), Go to Source, Add Subtitle/Audio Tracks, Properties & Metadata.
- SHOULD: Thumbnails come from VLC's media-library thumbnailer, and watched progress from the media library's playback state.
- OPEN: detail view, search results and the empty state are not shown.

**Key frames.**
- [`08-library__queue-panel-native__09m30.1s.jpg`](../../../../reference/video/key-frames/08-library__queue-panel-native__09m30.1s.jpg): Native: queue panel floating at the right of the video; queue icon orange.
- [`08-library__sort-menu-watched-unwatched__10m49.5s.jpg`](../../../../reference/video/key-frames/08-library__sort-menu-watched-unwatched__10m49.5s.jpg): Library sort menu: Unwatched First, Watched First, Newest, Oldest, Title A-Z, Z-A.
- [`08-library__more-menu-add-file-folder__10m55.5s.jpg`](../../../../reference/video/key-frames/08-library__more-menu-add-file-folder__10m55.5s.jpg): Library "..." menu: Add File, Add Folder, Edit Subtitle/Audio Tracks, Resync, Info.
- [`08-library__full-window-grid-native__10m57.6s.jpg`](../../../../reference/video/key-frames/08-library__full-window-grid-native__10m57.6s.jpg): Native: full-window library grid with nav panel, back/forward, breadcrumb, count, sort, view, search.
- [`08-library__drag-library-row-to-queue__11m45.8s.jpg`](../../../../reference/video/key-frames/08-library__drag-library-row-to-queue__11m45.8s.jpg): Dragging an episode from the compact library into the queue.
- [`08-library__full-window-list-mini-player__11m48.3s.jpg`](../../../../reference/video/key-frames/08-library__full-window-list-mini-player__11m48.3s.jpg): Full-window list view with the floating mini player at bottom right.
- [`08-library__mini-player-queue-expanded__11m54.3s.jpg`](../../../../reference/video/key-frames/08-library__mini-player-queue-expanded__11m54.3s.jpg): Mini player moved to bottom left with its queue expanded.
- [`08-library__compact-library-plus-queue-native__11m57.0s.jpg`](../../../../reference/video/key-frames/08-library__compact-library-plus-queue-native__11m57.0s.jpg): Native FINAL primary flow: rail + compact library at left, video, queue at right; folder chip "S01" in the top bar.
- OLD, for contrast: [`00-old-vlc__vlc4-browse-wifi-icon-folders__09m57.0s.jpg`](../../../../reference/video/key-frames/00-old-vlc__vlc4-browse-wifi-icon-folders__09m57.0s.jpg): VLC 4 library: Browse (Wi-Fi icon) > Folders. Criticized: hides the library and its folders.

**Figma renders.**
- [`Player.png`](../../design/figma/renders/Player.png) (compact library) · [`Player-1.png`](../../design/figma/renders/Player-1.png) · [`Player-2.png`](../../design/figma/renders/Player-2.png) · [`Player-3.png`](../../design/figma/renders/Player-3.png) · [`Player-4.png`](../../design/figma/renders/Player-4.png) (full window, list/grid, mini player) · [`Miniplayer.png`](../../design/figma/renders/Miniplayer.png)
- [`Sorting Options.png`](../../design/figma/renders/Sorting%20Options.png) · [`View Options.png`](../../design/figma/renders/View%20Options.png) · [`media.png`](../../design/figma/renders/media.png) (row states) · [`file context menu.png`](../../design/figma/renders/file%20context%20menu.png) · [`folder context menu.png`](../../design/figma/renders/folder%20context%20menu.png).

**Spec.** [spec-part1 §08](../../design/spec/spec-part1.md#08--media-library-09201200). **Phase:** P3.

---

## 09 Music

**Time:** 12:00–12:20.

**Problem → decision.**
- **Same library, music categories.** Music lives in the same compact library. The Music category splits into **Songs, Albums, Artists, Genres**, so you can play a whole folder back to back.
- **Different player look.** A playing song looks completely different from a video: a **massive cover art** over a blurred, enlarged copy of it, and the **waveform seek bar** if enabled.

**Rules.**
- MUST: The Music category root lists + Add · Songs · Albums · Artists · Genres. Folder views show square art thumbnails with "title - artist".
- MUST: Audio now-playing view:
  - The video area shows the cover art large and centered.
  - The background is the same art scaled up, blurred and darkened.
  - The title and artist sit under the art.
- MUST: When "Show Waveform on Seekbar" is on, the seek bar draws the audio waveform as vertical bars: played part orange, rest gray.
- MUST: The music layout shows **−15 s / +15 s** buttons on each side of play (12m56.6).
- SHOULD: When there is no cover art, use the generic music art (green note on dark green, as in Home "Listen Again").
- OPEN: Albums, Artists and Genres pages are not shown. Use a grid of square art following the Home cards (section 11).

**Key frames.**
- [`09-music__music-root-songs-albums-artists-genres__12m12.4s.jpg`](../../../../reference/video/key-frames/09-music__music-root-songs-albums-artists-genres__12m12.4s.jpg): Music category: Add, Songs, Albums, Artists, Genres; rail Music icon filled orange.
- [`09-music__now-playing-cover-art-native__12m18.4s.jpg`](../../../../reference/video/key-frames/09-music__now-playing-cover-art-native__12m18.4s.jpg): Native: song playing with big centered cover art over a blurred background.
- [`09-music__waveform-seekbar-skip15-native__12m56.6s.jpg`](../../../../reference/video/key-frames/09-music__waveform-seekbar-skip15-native__12m56.6s.jpg): Native: waveform seek bar and -15/+15 s buttons around play (music layout).

**Figma renders.** [`Player - Music.png`](../../design/figma/renders/Player%20-%20Music.png) · [`Player - Music-1.png`](../../design/figma/renders/Player%20-%20Music-1.png).

**Spec.** [spec-part2 §09](../../design/spec/spec-part2.md#09-music). **Phase:** P3.

---

## 10 Network streams and open dialogs

**Time:** 12:20–13:15.

**Problem → decision.**
- **Network category.** It ships with some saved streams plus an "Add Network Stream" button.
- **Split up Open Media.** The old Open Media dialog is an "all-in-one media factory": File/Disc/Network/Capture tabs, with Play/Enqueue/Stream/Convert behind a split button. Enqueue is pointless next to a real queue, and Stream and Convert are too important to hide.
- **One dialog per action.** The `⋯` menu already lists Open File, Open Folder, Network Stream, Capture Device, Clipboard, Recent, Convert and Stream, so each becomes **its own small dialog**.
- **IPTV demo.** Pasting a public IPTV `.m3u` link turns it into an **automatic playlist** of channels.

**Rules.**
- MUST: **Network category:**
  - "+ Add Network Stream" first, then saved streams with the broadcast icon.
  - The defaults include Podcasts and Radio.
  - The rail's Network icon is orange when active.
- MUST: There is no all-in-one Open Media dialog and no "Enqueue" action anywhere.
- MUST: **Open Network Stream** dialog:
  - multi-line URL field ("You can enter multiple links to load")
  - optional **Playlist Name** ("saved and displayed with this title")
  - Cancel / Save. Save stays disabled until a URL is entered.
  - Saving adds the stream, or the expanded m3u playlist, to the Network category.
- MUST: The app menu after cleanup offers each action separately (13m08.6). The final list is in section 15 and Figma `menu.png`.
- SHOULD: Open File(s) and Open Folder use the native macOS open panel.
- OPEN: Open Disc, Open Capture Device, Convert and Stream dialogs are not shown. Reuse the Open Network Stream dialog chrome: header, sections with heading plus helper text, Cancel/Save footer.

**Key frames.**
- [`10-network-open__network-category-default-streams__12m28.4s.jpg`](../../../../reference/video/key-frames/10-network-open__network-category-default-streams__12m28.4s.jpg): Network category: + Add Network Stream, saved Podcasts and Radio.
- [`10-network-open__app-menu-after-cleanup__13m08.6s.jpg`](../../../../reference/video/key-frames/10-network-open__app-menu-after-cleanup__13m08.6s.jpg): App menu after cleanup: each open/convert/stream action is its own entry.
- [`10-network-open__open-network-stream-dialog__13m17.8s.jpg`](../../../../reference/video/key-frames/10-network-open__open-network-stream-dialog__13m17.8s.jpg): Open Network Stream dialog: multi-line URL box, optional playlist name, Cancel/Save.

**Figma renders.** [`Open network stream.png`](../../design/figma/renders/Open%20network%20stream.png) · [`menu.png`](../../design/figma/renders/menu.png).

**Spec.** [spec-part2 §10](../../design/spec/spec-part2.md#10-network-streams-and-open-dialogs). **Phase:** P3.

---

## 11 Playlists, pins, recent, home

**Time:** 13:15–14:00.

**Problem → decision.**
- **Playlists.** Creating a playlist is simple: click Create, name it, select files. From anywhere else, you can right-click a file and choose "add to playlist".
- **Rail additions.** The rail is "long and empty", so it gets three things:
  - **pins**: favorite playlists, folders, anything
  - a **Recent** tab
  - a **Home** page with the latest files, playlists and streams
- **Home replaces the start screen.** Instead of the blank cone, reopening VLC shows a full library ready to continue where you left off.

**Rules.**
- MUST: The **Playlists category** shows "+ Create playlist" first, then the playlists with the playlist icon.
- MUST: **New Playlist** dialog:
  - name field and a square **thumbnail picker**
  - a **drop zone** ("Drag files into the box or click here to select files") with a + button
  - Cancel / Save
- MUST: "Add to Playlist" is available from the file context menu everywhere (library rows, queue rows, player right-click › Playlist).
- MUST: The **rail order** is Home · Videos · Music · Network · Playlists · Recent · *pins* · **+**.
  - A pinned file or playlist shows as its thumbnail in a rounded square; a pinned folder shows a folder icon.
  - **+** adds a pin.
- MUST: **Home** (compact and full window):
  - sections **Continue Watching ›** (16:9 cards with a progress line), **Listen Again ›** (square art with title and artist), **Frequently Visited Folders ›** (folder tiles)
  - Section titles with › open the full list.
- MUST: When there is nothing to resume, launching VLC opens the **full-window library on Home**, never a blank cone screen.
- MUST: The full library sidebar lists Home, Videos, Music, Network, Playlists, Recent and "+ Add item". The selected row has a filled orange icon and a brighter label.
- SHOULD: Recent lists items by last played. It is not shown, so use the list-row style.
- OPEN: Recent page layout and pin management (reorder, unpin) are not shown. Use a context menu on the pin.

**Key frames.**
- [`11-playlists-home__playlists-category__13m24.7s.jpg`](../../../../reference/video/key-frames/11-playlists-home__playlists-category__13m24.7s.jpg): Playlists category: + Create playlist, Cool Songs, Anime to Watch.
- [`11-playlists-home__new-playlist-dialog__13m26.1s.jpg`](../../../../reference/video/key-frames/11-playlists-home__new-playlist-dialog__13m26.1s.jpg): New Playlist dialog: name + thumbnail picker, drop zone for files.
- [`11-playlists-home__rail-pins-recent-add__13m41.2s.jpg`](../../../../reference/video/key-frames/11-playlists-home__rail-pins-recent-add__13m41.2s.jpg): Icon rail grown: Home, categories, Recent, pinned items (thumbnail, folder) and +.
- [`11-playlists-home__home-compact-panel__13m47.2s.jpg`](../../../../reference/video/key-frames/11-playlists-home__home-compact-panel__13m47.2s.jpg): Home in the compact panel: Continue Watching (with progress), Listen Again.
- [`11-playlists-home__home-full-window-native__13m57.3s.jpg`](../../../../reference/video/key-frames/11-playlists-home__home-full-window-native__13m57.3s.jpg): Native: full-window Home with Continue Watching, Listen Again, Frequently Visited Folders.
- [`11-playlists-home__folder-grid-unwatched-first__20m14.8s.jpg`](../../../../reference/video/key-frames/11-playlists-home__folder-grid-unwatched-first__20m14.8s.jpg): Showcase: folder grid sorted unwatched first; watched episodes last with full progress bars.

**Figma renders.** [`new playlist.png`](../../design/figma/renders/new%20playlist.png) · [`playlist.png`](../../design/figma/renders/playlist.png) · [`playlist context menu.png`](../../design/figma/renders/playlist%20context%20menu.png) · [`Player-5.png`](../../design/figma/renders/Player-5.png) (Home, full window) · [`file context menu.png`](../../design/figma/renders/file%20context%20menu.png).

**Spec.** [spec-part2 §11](../../design/spec/spec-part2.md#11-playlists-pins-recent-home). **Phase:** P3.

---

## 12 Continue-watching prompt

**Time:** 14:00–14:12. The sponsor segment that follows (14:12–14:45) is skipped.

**Problem → decision.** VLC's "restart where you left off?" prompt is a thin strip at the top-left, with the Continue button far away at the top-right, and it vanishes after a few seconds. She barely noticed it. It should sit **near the playback controls, centered**, where the eye already is.

**Rules.**
- MUST: A **resume toast** sits horizontally centered just above the control bar.
  - Text: "You already watched till **hh:mm:ss**", with the time in bold.
  - A primary **Continue Watching** button: orange, dark label.
  - A small ✕ button.
- MUST: While the toast is visible, the seek bar previews the resume point: a tinted span from 0 to the saved time, plus a faint marker.
- MUST: Continue jumps to the saved time. ✕ or a timeout dismisses the toast and playback continues from the start.
- SHOULD: The timeout is about 5 s ("I have like five seconds to respond"). Hovering the toast pauses the timeout.
- SHOULD: Tie it to VLC's existing "continue playback" preference (Settings › Playback › "Continue where you left off": Always/Ask/Never). Show the toast only for "Ask".

**Key frames.**
- [`12-continue-watching__resume-toast-native__14m09.8s.jpg`](../../../../reference/video/key-frames/12-continue-watching__resume-toast-native__14m09.8s.jpg): Native: centered resume toast above the control bar ("You already watched till ..." + Continue Watching).

**Figma renders.** None identified. Build from the frame and spec-part2 §12.

**Spec.** [spec-part2 §12](../../design/spec/spec-part2.md#12-continue-watching-prompt). **Phase:** P1.

---

## 13 Bookmarks, chapters, OSD

**Time:** 14:45–15:28.

**Problem → decision.**
- **Bookmarks.** They hide behind Playback › Custom Bookmarks › Manage, which opens a table ("this is an Excel"). **Ctrl+B** should create a bookmark instantly, and the bookmark list belongs in the **right sidebar**, together with the movie **chapters**.
- **OSD.** When a shortcut is pressed by accident, the OSD should show **which key** was pressed, not only the action.

**Rules.**
- MUST: The queue button opens a **tabbed right sidebar**: **Queue · Bookmarks · Chapters**. The tab style is the same as the track popover: icon plus label, orange underline.
  - The Queue tab is the queue panel from section 02, including the "⋯" **insertion placeholder** while dragging (20m21.4).
- MUST: **Chapters tab:** rows show the number in orange, the title, and the timestamp right-aligned. Clicking a row seeks to it.
- MUST: **Bookmarks tab:** the list of bookmarks (name, time). Clicking one seeks to it.
- MUST: **Create Bookmark** at the current time is one shortcut (she proposes Ctrl+B; on macOS ⌘B) with no dialog.
- MUST: **OSD feedback for shortcuts** shows two lines: the action (e.g. "Crop: 2.35:1"), then "Pressed C".
  - It is controlled by Settings › Subtitles › On-Screen Messages ("Show feedback for shortcuts", duration slider).
- OPEN: the Bookmarks tab layout, the Ctrl+B confirmation feedback and chapter markers on the seek bar are not shown. Suggestion: rows like Chapters with an editable name, plus/minus in the tab header like the queue, and a brief OSD "Bookmark added".

**Key frames.**
- [`13-bookmarks-chapters-osd__chapters-tab-native__15m16.7s.jpg`](../../../../reference/video/key-frames/13-bookmarks-chapters-osd__chapters-tab-native__15m16.7s.jpg): Native: right sidebar with Queue / Bookmarks / Chapters tabs, Chapters active.
- [`13-bookmarks-chapters-osd__osd-shows-pressed-key__15m27.1s.jpg`](../../../../reference/video/key-frames/13-bookmarks-chapters-osd__osd-shows-pressed-key__15m27.1s.jpg): OSD shows the action and the key: "Crop: 2.35:1 / Pressed C".
- [`13-bookmarks-chapters-osd__queue-tab-drag-insert-placeholder__20m21.4s.jpg`](../../../../reference/video/key-frames/13-bookmarks-chapters-osd__queue-tab-drag-insert-placeholder__20m21.4s.jpg): Queue tab close-up: header controls, current item orange, "..." insert placeholder while dragging.
- OLD, for contrast: [`00-old-vlc__edit-bookmarks-dialog__15m02.1s.jpg`](../../../../reference/video/key-frames/00-old-vlc__edit-bookmarks-dialog__15m02.1s.jpg): VLC 3 Edit Bookmarks table ("this is an Excel"). Replaced by the Bookmarks tab in the right sidebar.

**Figma renders.** None dedicated. The Queue tab matches [`playlist.png`](../../design/figma/renders/playlist.png) and the queue in [`Player-1.png`](../../design/figma/renders/Player-1.png).

**Spec.** [spec-part2 §13](../../design/spec/spec-part2.md#13-bookmarks-chapters-osd). **Phase:** P2 (OSD text: P1).

---

## 14 Settings window and hotkeys

**Time:** 15:28–18:45. The "settings" chapter card is at 15:32.

**Problem → decision.**
- **Problem.** Old settings are an "airplane cockpit":
  - Simple vs All modes where Simple is not simple
  - settings repeated up to five times, the same thing worded differently
  - subcategories holding a single setting
  - explanations hidden in hover tooltips
  - numeric codes, e.g. subtitle fuzziness 0–4
- **Hotkeys.** They get **their own dialog** with a direct menu entry.
- **Basic, then advanced.** Each category shows its **basic settings first**, then the **advanced ones below** in the same place (scroll down), instead of a separate Advanced tree.
- **Plain words and info icons.** Every setting gets an **info icon**. Numbers become **human words** in dropdowns.
- **Categories.** She went through every setting and sorted them into categories:
  - General (theme light/dark, plus an **accent color** to replace the orange)
  - Interface · Privacy · Controls · Playback · Video · Audio
  - Subtitles (including OSD messages)
  - Library · Network · Performance
  - Recording (streaming and casting)
  - Extensions (installable add-ons). VLC's internal **plugins** move under advanced.

**Rules.**
- MUST: **Settings** is a large centered window.
  - Header: **search field** · page title · ✕.
  - Left sidebar card: groups **App** (General, Interface, Privacy, Controls), **Media** (Playback, Video, Audio, Subtitles, Library), **System** (Network, Performance, Recording, Extensions). The selected category has a highlighted row and a filled orange icon.
  - The content pane scrolls.
- MUST: Every category page has titled sections of rows.
  - Each row: label · optional **ⓘ info icon** · control right-aligned.
  - Controls are dropdown, toggle (her square ON/OFF style), segmented, slider with ticks and scale labels, text field, color field, and secondary button.
- MUST: The page ends with an **"Advanced Options ›"** bar that expands advanced rows **below it** on the same page (chevron points down when open).
- MUST: There are no numeric codes. Use dropdowns of plain options, e.g. Off / Any title / Contains title / Title with extra characters / Exact title match.
- MUST: The **ⓘ** icon shows the setting's explanation on click, not on hover delay.
- MUST: **General:** Interface language, **Theme Dark | Light | System**, **Accent color** (9 swatches), Startup, Diagnostics.
  - Changing the theme or accent recolors the whole UI live (17m44.0 shows the Light theme).
- MUST: **Dependent rows** are visibly disabled until their parent is enabled (Library page; Network buffering when not Custom).
- MUST: **Extensions:** list of installed extensions, search, "Find more extensions" / Add / Remove, "Load extensions on startup".
- MUST: **Keyboard Shortcuts** has its own dialog, opened from the app menu ("Keyboard Shortcuts") and from Settings › Controls › "Edit Keyboard Shortcuts".
  - Search plus an "All Fields" filter.
  - Columns Action · Hotkey · Global Hotkey, grouped (Basic, Playback, …).
  - Each key cell has an edit pencil. Cancel / Save.
- MUST: The category pages and their rows follow the Figma `Settings - *.png` renders and [spec-part2 §14 B](../../design/spec/spec-part2.md#14-settings-and-hotkeys). **Every category appears in the video** (17m40–18m27); see the corrections at the end.
- SHOULD (macOS):
  - Settings is a separate window (⌘, opens it) styled as in the video, not a native tabbed preferences pane.
  - Keep VLC's own preference keys underneath; this is a presentation layer.
  - "Show in File Explorer" becomes "Show in Finder".
- OPEN: the ⓘ popover style, search behavior (filter categories vs rows) and scrollbar style are not shown.

**Key frames.**
- [`14-settings__app-menu-keyboard-shortcuts-entry__16m02.8s.jpg`](../../../../reference/video/key-frames/14-settings__app-menu-keyboard-shortcuts-entry__16m02.8s.jpg): App menu gains a direct "Keyboard Shortcuts" entry (hover state visible).
- [`14-settings__dropdown-human-words__17m31.0s.jpg`](../../../../reference/video/key-frames/14-settings__dropdown-human-words__17m31.0s.jpg): Dropdown in human words: Off / Any title / Contains title / Title with extra characters / Exact title match.
- [`14-settings__general-native__17m40.9s.jpg`](../../../../reference/video/key-frames/14-settings__general-native__17m40.9s.jpg): Native: Settings modal, General ("Global Settings"): search, grouped categories, Advanced Options bar.
- [`14-settings__general-light-theme__17m44.0s.jpg`](../../../../reference/video/key-frames/14-settings__general-light-theme__17m44.0s.jpg): Same page switched to the Light theme.
- [`14-settings__general-accent-color__17m50.1s.jpg`](../../../../reference/video/key-frames/14-settings__general-accent-color__17m50.1s.jpg): General with the Accent color row (9 swatches).
- [`14-settings__interface__17m51.5s.jpg`](../../../../reference/video/key-frames/14-settings__interface__17m51.5s.jpg): Interface Settings: Skin, Window, Playback Controls (auto-hide, hide-after slider).
- [`14-settings__privacy__17m56.1s.jpg`](../../../../reference/video/key-frames/14-settings__privacy__17m56.1s.jpg): Privacy Settings: History, Network (metadata, last.fm).
- [`14-settings__controls__17m57.5s.jpg`](../../../../reference/video/key-frames/14-settings__controls__17m57.5s.jpg): Mouse, Keyboard & Remote Controls: shortcuts buttons, skip amounts, mouse actions, remotes.
- [`14-settings__playback__18m00.5s.jpg`](../../../../reference/video/key-frames/14-settings__playback__18m00.5s.jpg): Playback Preferences: Startup, Tracks, Order, Seeking.
- [`14-settings__video-defaults__18m02.1s.jpg`](../../../../reference/video/key-frames/14-settings__video-defaults__18m02.1s.jpg): Video Defaults: Output, Picture sliders, Deinterlacing, Framing.
- [`14-settings__audio-inline-equalizer__18m08.1s.jpg`](../../../../reference/video/key-frames/14-settings__audio-inline-equalizer__18m08.1s.jpg): Audio Defaults with the inline 11-band vertical equalizer.
- [`14-settings__subtitles-osd__18m14.1s.jpg`](../../../../reference/video/key-frames/14-settings__subtitles-osd__18m14.1s.jpg): Subtitle Defaults lower half: Timing, On-Screen Messages (shortcut feedback).
- [`14-settings__library__18m16.5s.jpg`](../../../../reference/video/key-frames/14-settings__library__18m16.5s.jpg): Playlists, Folders & Files: Opening Files (dependent rows disabled), Metadata & Artwork.
- [`14-settings__network__18m18.5s.jpg`](../../../../reference/video/key-frames/14-settings__network__18m18.5s.jpg): Network Connections & Security: Buffering, Proxy, Security.
- [`14-settings__performance-advanced-expanded__18m20.1s.jpg`](../../../../reference/video/key-frames/14-settings__performance-advanced-expanded__18m20.1s.jpg): Performance Settings with Advanced Options expanded (Developer section).
- [`14-settings__recording__18m24.0s.jpg`](../../../../reference/video/key-frames/14-settings__recording__18m24.0s.jpg): Recording, Casting & Streaming Out.
- [`14-settings__extensions-scripts__18m26.1s.jpg`](../../../../reference/video/key-frames/14-settings__extensions-scripts__18m26.1s.jpg): Extensions & Scripts: list box, search, Find more extensions / Add / Remove.
- [`14-settings__general-advanced-expanded__18m51.1s.jpg`](../../../../reference/video/key-frames/14-settings__general-advanced-expanded__18m51.1s.jpg): General with Advanced Options expanded below the bar.
- OLD, for contrast: [`00-old-vlc__subtitle-fuzziness-numeric-codes__17m25.0s.jpg`](../../../../reference/video/key-frames/00-old-vlc__subtitle-fuzziness-numeric-codes__17m25.0s.jpg): VLC 3 subtitle autodetection fuzziness as numbers 0-4. Replaced by a dropdown of human words.

**Figma renders.**
- All `Settings - *.png`: [`Settings - global.png`](../../design/figma/renders/Settings%20-%20global.png) · [`Settings - global-1.png`](../../design/figma/renders/Settings%20-%20global-1.png) · [`Settings - interface.png`](../../design/figma/renders/Settings%20-%20interface.png) · [`Settings - interface-1.png`](../../design/figma/renders/Settings%20-%20interface-1.png) · [`Settings - privacy.png`](../../design/figma/renders/Settings%20-%20privacy.png) · [`Settings - controls.png`](../../design/figma/renders/Settings%20-%20controls.png) · [`Settings - playback.png`](../../design/figma/renders/Settings%20-%20playback.png) · [`Settings - playback-1.png`](../../design/figma/renders/Settings%20-%20playback-1.png) · [`Settings - video.png`](../../design/figma/renders/Settings%20-%20video.png) · [`Settings - video-1.png`](../../design/figma/renders/Settings%20-%20video-1.png) · [`Settings - audio.png`](../../design/figma/renders/Settings%20-%20audio.png) · [`Settings - audio-1.png`](../../design/figma/renders/Settings%20-%20audio-1.png) · [`Settings - subtitles.png`](../../design/figma/renders/Settings%20-%20subtitles.png) · [`Settings - subtitles-1.png`](../../design/figma/renders/Settings%20-%20subtitles-1.png) · [`Settings - library.png`](../../design/figma/renders/Settings%20-%20library.png) · [`Settings - network.png`](../../design/figma/renders/Settings%20-%20network.png) · [`Settings - performance.png`](../../design/figma/renders/Settings%20-%20performance.png) · [`Settings - recording.png`](../../design/figma/renders/Settings%20-%20recording.png) · [`Settings - extensions.png`](../../design/figma/renders/Settings%20-%20extensions.png)
- [`Keyboard Shortcuts.png`](../../design/figma/renders/Keyboard%20Shortcuts.png) · [`setting category.png`](../../design/figma/renders/setting%20category.png) (sidebar row states) · [`sub filename.png`](../../design/figma/renders/sub%20filename.png) (human-word dropdown) · [`Toggle.png`](../../design/figma/renders/Toggle.png) · [`Values.png`](../../design/figma/renders/Values.png) · [`Values-1.png`](../../design/figma/renders/Values-1.png) (startup volume selector) · [`Dropdown.png`](../../design/figma/renders/Dropdown.png) · [`option.png`](../../design/figma/renders/option.png) · [`EQ.png`](../../design/figma/renders/EQ.png) · [`Player - Light.png`](../../design/figma/renders/Player%20-%20Light.png).

**Spec.** [spec-part2 §14](../../design/spec/spec-part2.md#14-settings-and-hotkeys). **Phase:** P4.

---

## 15 Customization, profiles, onboarding

**Time:** 18:45–20:00. The "customization" chapter card is at 18:55.

**Problem → decision.**
- **Customize Player.** She did not want customization to be her own redesign, but VLC already has a toolbar editor and it is hard to use. The fix is **one big frame in the center of VLC full of buttons and icons**, with **outlines showing what can move**. Drag things in and out of the bars to make the player yours. An alternate layout demonstrates it.
- **Profiles.** Layouts are saved under **profiles**, and all settings switch with the profile.
- **Onboarding.** Most users want to customize, but about half want only minimal changes. An **onboarding** flow with theme options and a **basic shortcuts** screen covers them.

**Rules.**
- MUST: **Customize Player** (from the app menu) puts the player into edit mode.
  - The paused video stays visible behind the translucent dialog; nothing dims it (Player - customize uses the normal video fill; 19m12.4, D053).
  - Every element in the top and bottom bars gets a **dashed outline** to show it is draggable. Groups (e.g. time + seek bar + duration) share one outline.
- MUST: The centered **Customize Player** dialog contains:
  - Header and helper text: "Drag items around and out of the box below to re-order them. Drag items into the box to remove them from the player."
  - A grid of dashed **tiles** (icon plus label): Spacer, Divider, Playback Speed, ±10 s, ±15 s, Stop, Repeat, Shuffle, Record, Snapshot, Picture in Picture, HDR, Zoom, Right Sidebar, Quit VLC, VLC Settings, Go Home, Thumbnail, File/Artist/Folder/Playlist Name, Properties, Replay, Chapters, Favorite, Bookmark, Bookmarks, Playlists. The full list is in spec-part2 §15 A.
- MUST: Drag behavior:
  - Dragging a tile into a bar adds the element, and its tile disappears from the grid.
  - Dragging an element out of a bar into the box removes it.
  - Elements can be reordered within and between bars.
  - **Save** turns primary once something changed. **Cancel** reverts.
- MUST: The layout model must express at least her alternate layout:
  - top bar with logo and window controls only
  - bottom area in **two rows**: a full-width seek row, then ⋯ / sidebar / folder chip / title / favorite on the left, centered prev-play-next, and volume / tracks / gear / queue / fullscreen on the right
- MUST: **Profiles.** The app menu has "Profile (<current>) ›", a submenu of profiles with a ✓ on the current one, and "+ New".
  - A profile stores the **layout and all settings**. Switching applies them.
- MUST: **Onboarding** on first run:
  1. **Welcome**: logo, short description, "Choose a Media Folder" (path plus Browse), Next.
  2. **Theme and accent**: Light / Dark / System tiles plus 9 accent swatches, recoloring a live preview. Figma only, but it covers the "theme options" she describes.
  3. **Basic keyboard shortcuts**: keycap rows, "Find the full list in the menu.", Back / Finish.
- MUST: The final **app menu** (19m29.4, Figma `Profiles.png` / `menu.png`), in order:
  - Open File(s)
  - Open Folder
  - Open Network Stream
  - Open Disc
  - Open Capture Device
  - Convert
  - Open Recent ›
  - divider
  - Profile (…) ›
  - Keyboard Shortcuts
  - Customize Player
  - Settings
  - About VLC
- SHOULD (macOS): Onboarding is a first-run window. On macOS the shortcuts screen shows ⌘-based keys where VLC for macOS uses them.
- OPEN: drag ghost and drop indicator styling, a "new profile" naming dialog, whether the side areas are drop targets.

**Key frames.**
- [`15-customize-onboarding__customize-edit-mode-native__19m12.4s.jpg`](../../../../reference/video/key-frames/15-customize-onboarding__customize-edit-mode-native__19m12.4s.jpg): Native: Customize Player mode, every bar element dashed-outlined, tile grid dialog in the center.
- [`15-customize-onboarding__customize-tiles-closeup__19m18.4s.jpg`](../../../../reference/video/key-frames/15-customize-onboarding__customize-tiles-closeup__19m18.4s.jpg): Close-up of tiles: dashed icon boxes with labels (PiP, HDR, Zoom, Right Sidebar, File Name...).
- [`15-customize-onboarding__customize-item-dragged-save-enabled__19m26.3s.jpg`](../../../../reference/video/key-frames/15-customize-onboarding__customize-item-dragged-save-enabled__19m26.3s.jpg): Alternate layout being built; a dragged tile leaves the grid; Save turns orange.
- [`15-customize-onboarding__alternate-two-row-layout__19m27.6s.jpg`](../../../../reference/video/key-frames/15-customize-onboarding__alternate-two-row-layout__19m27.6s.jpg): Result: alternate two-row layout (full-width seek row, centered transport).
- [`15-customize-onboarding__app-menu-final-with-profile__19m29.4s.jpg`](../../../../reference/video/key-frames/15-customize-onboarding__app-menu-final-with-profile__19m29.4s.jpg): Final app menu including Profile (Movies), Keyboard Shortcuts, Customize Player.
- [`15-customize-onboarding__profile-submenu__19m35.4s.jpg`](../../../../reference/video/key-frames/15-customize-onboarding__profile-submenu__19m35.4s.jpg): Profile submenu: Movies (checked), Shows, Music, Work, + New.
- [`15-customize-onboarding__onboarding-welcome__19m46.7s.jpg`](../../../../reference/video/key-frames/15-customize-onboarding__onboarding-welcome__19m46.7s.jpg): Onboarding step 1: Welcome to VLC, media folder picker, Next.
- [`15-customize-onboarding__onboarding-shortcuts__19m52.7s.jpg`](../../../../reference/video/key-frames/15-customize-onboarding__onboarding-shortcuts__19m52.7s.jpg): Onboarding last step: basic keyboard shortcuts with keycaps, Back / Finish.
- OLD, for contrast: [`00-old-vlc__toolbars-editor__19m02.8s.jpg`](../../../../reference/video/key-frames/00-old-vlc__toolbars-editor__19m02.8s.jpg): VLC 3 Toolbars Editor. Replaced by the Customize Player drag-and-drop mode.

**Figma renders.**
- [`Player - customize.png`](../../design/figma/renders/Player%20-%20customize.png) · [`Player - customize-1.png`](../../design/figma/renders/Player%20-%20customize-1.png) · [`Player - customize-2.png`](../../design/figma/renders/Player%20-%20customize-2.png) · [`Player - customize-3.png`](../../design/figma/renders/Player%20-%20customize-3.png) · [`Player - customize-4.png`](../../design/figma/renders/Player%20-%20customize-4.png) · [`Player - customize-5.png`](../../design/figma/renders/Player%20-%20customize-5.png) · [`Player - customize-6.png`](../../design/figma/renders/Player%20-%20customize-6.png) · [`Player - customize-7.png`](../../design/figma/renders/Player%20-%20customize-7.png) · [`Player - customize-8.png`](../../design/figma/renders/Player%20-%20customize-8.png)
- [`Profiles.png`](../../design/figma/renders/Profiles.png) · [`menu.png`](../../design/figma/renders/menu.png)
- [`Onboarding.png`](../../design/figma/renders/Onboarding.png) · [`Onboarding-1.png`](../../design/figma/renders/Onboarding-1.png) … [`Onboarding-10.png`](../../design/figma/renders/Onboarding-10.png) (accent color variants) · [`Onboarding-2.png`](../../design/figma/renders/Onboarding-2.png) (shortcuts) · [`Player - Light.png`](../../design/figma/renders/Player%20-%20Light.png).

**Spec.** [spec-part2 §15](../../design/spec/spec-part2.md#15-customization-editor-profiles-onboarding). **Phase:** P5.

---

## 16 Final showcase

**Time:** 20:00–20:46. Before it: an open-source and donation note at 19:54–20:05, and a Dragon Ball GIF.

**What it is.** A recap montage: the refreshed library (folder grid, unwatched first), the rail with Playlists, dragging into the queue, the play button and seek handle close-ups, "Settings Re-imagined", "Everything is customizable. Yep, even that."

**Rules.** No new screens. Its close-ups confirm details already listed:
- the play glyph is **dark on orange**, never white
- the seek handle is a tall orange capsule over a dark-orange fill
- watched episodes sort last with a full progress line

**Key frames.** Showcase frames are filed under their topics: `02-control-bar__play-button-closeup__20m23.6s.jpg`, `11-playlists-home__folder-grid-unwatched-first__20m14.8s.jpg`, `13-bookmarks-chapters-osd__queue-tab-drag-insert-placeholder__20m21.4s.jpg`.

**Spec.** [spec-part2 §16](../../design/spec/spec-part2.md#16-final-showcase-screens-and-details-not-seen-elsewhere) · [screen inventory](../../design/spec/spec-part2.md#full-screen--dialog--panel-inventory-implementation-list).

---

## Design principles distilled

Use these when a screen, state or interaction is not shown in the video or Figma. They are her stated reasoning, generalized.

1. **Keep VLC's identity.** Cone, orange accent, near-black neutrals, rectangular shapes with modest radii. Never pills or circles, except slider and seek handles. The player must not look like every other player.
2. **Quiet by default, powerful on demand.** The default view is the video plus thin bars. Everything else (panels, library, settings) appears on request and goes away cleanly.
3. **Put things where people look.** Title and window actions go at the top. Track and settings controls go at the bottom right. Play stays at the left. Feedback appears near the controls the user is already looking at (resume toast, OSD).
4. **Fewer clicks for frequent tasks.** A frequent action is one click from the bar or one shortcut. Pickers stay open while you pick. No menu chains three levels deep for everyday tasks.
5. **Never leave the video.** Panels overlay the side of the video: library on the left; queue, tracks and settings sidebar on the right. Modal windows are reserved for rare tasks (Settings, dialogs, Customize).
6. **One place per function, no duplicates.** If two surfaces would show the same list, keep one, and make the others open it.
7. **Expose hidden features, in human words.**
   - Defaults, sorting, library and subtitle timing are in plain view.
   - No numeric codes or jargon in labels.
   - Explanations come from a clickable ⓘ, not hover delays.
8. **Precise and easy at the same time.** Every number has a typed field (with unit) **and** a slider. Sizes offer relative and absolute modes.
9. **Remember the user's context.** Per-show presets, profiles, default tracks, resume position, watched state, recent items and pins. Set it once, never redo it per episode.
10. **Basic first, advanced below.** Advanced options live on the same page under a collapsible bar, not in a separate tree.
11. **Two icon systems, one state language.**
    - Two-tone icons are decoration, used in menus.
    - Monochrome icons are interactive.
    - **Orange means active, current or primary:** pressed toggle, open panel, active tab underline, selected ✓, now-playing item, primary button, playhead.
    - Everything else stays neutral gray.
12. **Queue vs playlist.** The queue is temporary and plays automatically. Playlists are saved collections. Never use "playlist" for the queue.
13. **Drag and drop is a first-class input.** Files into the queue, library to queue, reordering, customization tiles. Every drop target shows where the item will land.
14. **Respect keyboard users.** Shortcuts are printed in menus, the OSD names the pressed key, and onboarding teaches the basics.
15. **Customization is optional.** The default must be great with zero setup. Customization (layout, theme, accent, profiles) is offered, never required.
16. **Everything follows the accent and theme.** No hard-coded orange or dark colors. Light theme and any of the 9 accents must work for every new component.
17. **The final version wins.** The video shows iterations. Use the last version shown, and Figma for the final look.

---

## Cross-reference: video section → Figma renders → spec → phase

| Video section | Time | Figma renders (`redesign/design/figma/renders/`) | Spec section | Phase |
|---|---|---|---|---|
| 01 Identity: colors, icons, shape | 00:00–01:32 | Icon, Icon Wrapper, Button, play, Components, Designs, styles.txt | [part1 §0](../../design/spec/spec-part1.md#0-design-tokens-global), [§0.6](../../design/spec/spec-part1.md#06-principles-her-stated-reasoning-paraphrased), [§01](../../design/spec/spec-part1.md#01--intro-colors-icons-00000130) | P1 |
| 02 Control bar, seek, volume, queue | 01:32–03:30 | Controls, Player-6, play, Current Time, Duration, volume, audio value, thumbnail, playlist | [part1 §02](../../design/spec/spec-part1.md#02--control-bar-seek-bar-volume-01300330), [App. A](../../design/spec/spec-part1.md#appendix-a--measured-native-layout-cheat-sheet-1920x1080), [App. B](../../design/spec/spec-part1.md#appendix-b--state-summary) | P1 (queue panel P2) |
| 03 Top bar, fullscreen, hover | 03:30–04:04 | Player-6, Player - hide UI, Player | [part1 §03](../../design/spec/spec-part1.md#03--top-bar-fullscreen-hover-behavior-03300400) | P1 |
| 04 Track buttons and popover | 04:04–05:00 | Player-6, Dropdown, option | [part1 §04](../../design/spec/spec-part1.md#04--subtitle-and-audio-buttons-track-popover-04000500) | P2 |
| 05 App menu, right-click, hide UI | 05:00–05:30 | menu, right-click menu, context menu, Profiles | [part1 §05](../../design/spec/spec-part1.md#05--menus--app-menu-and-right-click-menu-05000530), [part2 §10 B](../../design/spec/spec-part2.md#10-network-streams-and-open-dialogs) | P1 |
| 06 Add Subtitles dialog | 05:30–06:30 | Add Subtitles to Playlist/Folder(-1..3), target, origin, subtitle one, subtitle multiple | [part1 §06](../../design/spec/spec-part1.md#06--subtitle-import-dialog-05300625) | P2 |
| 07 Settings sidebar, subtitle timeline | 06:30–09:20 | sidebar, Setting Preset, EQ presets, EQ, Audio - * (4), Video - * (3), HDR Options, Audio Visualizer, Values, Toggle, Button | [part1 §07](../../design/spec/spec-part1.md#07--settings-sidebar-subtitles-audio-video-playback-tabs-06250920) | P2 |
| 08 Library, compact library, mini player | 09:20–12:00 | Player, Player-1..4, Miniplayer, Sorting Options, View Options, media, file context menu, folder context menu | [part1 §08](../../design/spec/spec-part1.md#08--media-library-09201200) | P3 |
| 09 Music | 12:00–12:20 | Player - Music, Player - Music-1 | [part2 §09](../../design/spec/spec-part2.md#09-music) | P3 |
| 10 Network streams, open dialogs | 12:20–13:15 | Open network stream, menu | [part2 §10](../../design/spec/spec-part2.md#10-network-streams-and-open-dialogs) | P3 |
| 11 Playlists, pins, recent, home | 13:15–14:00 | new playlist, playlist, playlist context menu, Player-5, file context menu | [part2 §11](../../design/spec/spec-part2.md#11-playlists-pins-recent-home) | P3 |
| 12 Continue-watching prompt | 14:00–14:12 | (none) | [part2 §12](../../design/spec/spec-part2.md#12-continue-watching-prompt) | P1 |
| 13 Bookmarks, chapters, OSD | 14:45–15:28 | (none dedicated; playlist, Player-1 for the queue) | [part2 §13](../../design/spec/spec-part2.md#13-bookmarks-chapters-osd) | P2 (OSD P1) |
| 14 Settings window, hotkeys | 15:28–18:45 | Settings - * (19), Keyboard Shortcuts, setting category, sub filename, Toggle, Values, Values-1, Dropdown, option, EQ, Player - Light | [part2 §14](../../design/spec/spec-part2.md#14-settings-and-hotkeys) | P4 |
| 15 Customization, profiles, onboarding | 18:45–20:00 | Player - customize (9), Profiles, menu, Onboarding (11), Player - Light | [part2 §15](../../design/spec/spec-part2.md#15-customization-editor-profiles-onboarding) | P5 |
| 16 Final showcase | 20:00–20:46 | (recap) | [part2 §16](../../design/spec/spec-part2.md#16-final-showcase-screens-and-details-not-seen-elsewhere), [inventory](../../design/spec/spec-part2.md#full-screen--dialog--panel-inventory-implementation-list) | n/a |

---

## Corrections to the specs found while making this breakdown

These come from frames the specs did not look at. They override the specs until the specs are updated.

1. **Playback tab is fully visible.** spec-part1 §07 says the Playback-tab toggles are "described but not visible". At **09m17.5s** the complete tab is shown, in this order:
   - Show Subtitle Timeline on Seekbar
   - Show Waveform on Seekbar
   - Show Metadata
   - Reverse
   - Sleep Timer
   - **Audio Visualizer** (Disabled), which is not in the spec
   - Speed

   Frame: `07-sidebar__playback-tab-full-toggles__09m17.5s.jpg`.
2. **Sidebar tab order is Playback · Video · Audio · Subtitles** (09m17.5). The early Subtitles-tab frames show placeholder "Tab" labels.
3. **Every Settings category is in the video.** spec-part2 §14 marks Interface, Controls, Playback, Library, Network and Recording as "Figma only / not in video". The video pages through all 13 categories between **17m40s and 18m27s**: General 17m40, Interface 17m51.5, Privacy 17m53–56, Controls 17m57.5, Playback 18m00.5, Video 18m02–05, Audio 18m06–08, Subtitles 18m09–14, Library 18m16.5, Network 18m18.5, Performance 18m20–22, Recording 18m24, Extensions 18m26. The frames are in `key-frames/14-settings__*`. Use Figma for exact rows; the video confirms them.
4. **The clickable icon set is shown** under "decorative" at **01m14s** (`01-identity__decorative-vs-clickable-icon-sets__01m14.5s.jpg`). spec-part1 §01 says it is never shown as a slide.
5. **Bars hide independently** in the hover demo: top only at 03m51.0, bottom only at 03m53.0. spec-part1 §03 did not have these frames.
6. **The preset selector trigger exists in Figma** (`Setting Preset.png`: a "Default Preset" dropdown that opens upward). This answers the spec-part1 §07 open question.
7. **The elapsed time is editable and the total time toggles to remaining** in Figma (`Current Time.png`, `Duration.png`). They are not in the video or the spec.
