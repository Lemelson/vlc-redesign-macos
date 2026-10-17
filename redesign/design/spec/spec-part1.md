# VLC Redesign (Juxtopposed, "I Redesigned VLC After 25 Years") — UI Spec, Part 1 (sections 01–08)

Source: 1080p keyframes in `../reference/video/frames/01-…08-…` and `transcript.txt`. Frame paths are relative to `../reference/video/frames/` (local-only, outside the repo; see `redesign/tools/fetch-reference.sh`).
All pixel values are measured at 1920x1080. A frame is **native** when the app window fills the 1920x1080 frame at 1:1. Native frames: `04m06.72s`, `04m10.91s`, `06m02.47s`, `06m21.67s`, `06m24.41s`, `07m04.19s`, `09m30.06s`, `10m57.64s`, `11m45.76s`, `11m48.27s`, `11m54.27s`, `11m56.96s`. Other frames are zoomed. For those, the zoom factor is estimated and the native size is derived (marked **est.**).
Colors were sampled from JPEG frames as 3x3 averages. They can be off by about ±6 per channel, and fine strokes and text are darker than their true color because of anti-aliasing. Hex values are **sampled**. Where several samples were taken, a representative value is given.

Legend: **[NEW]** = her final design · **[INTERIM]** = an intermediate mockup she later replaced · **[OLD]** = current VLC 3.x, or the upcoming VLC 4 design she critiques. Do not copy [OLD] items.

---

## 0. Design tokens (global)

### 0.1 Palette

The palette slide is `01-intro-colors-icons/00m58.42s.jpg`: one large orange swatch, four orange or brown swatches, four grays, and four near-black swatches, each with a 1px lighter outline.

| Token | Hex (sampled) | Where seen |
|---|---|---|
| `orange.brand` (palette main / cone) | `#C8771B` | palette big swatch and flat cone (00m58.42) |
| `orange.light` | `#F1942D` | palette |
| `orange.mid` (decorative icon accent) | `#A36117` | palette, and the orange half of the two-tone menu icons (01m11.74) |
| `orange.dark` | `#603A0D` | palette |
| `orange.darkest` | `#402708` | palette |
| `accent` (as rendered on UI controls) | `#CE6607` to `#D16206` (use about **`#CF650A`**) | play button, seek handle, checkmarks, active tab underline (`#AE6930` to `#C36C29` when thin) |
| `accent.text` (orange text on dark) | `#C66D2D` / `#AD682B` | Save button label, active segmented label, now-playing filename |
| `accent.tint` (orange at about 20% on black) | `#301B00` to `#341C06` | seek-bar elapsed fill, primary-button bg, active-segment bg, slider fill |
| `accent.btn.small` (timeline nudge buttons) | `#9F4E00` to `#A75002` | subtitle-timeline `‹ − + ›` buttons, slider handles in the sidebar |
| `gray.200` | `#C6C6C6` | palette |
| `gray.400` | `#8F8F8F` | palette, and the gray half of the decorative icons (`#918F92`) |
| `gray.500` | `#6B6B6B` | palette |
| `gray.700` | `#3B3B3B` | palette |
| `black.1` | `#1B1B1B` | palette (outlined `#333333`) |
| `black.2` | `#151515` | palette (outlined `#2B2B2B`) |
| `black.3` | `#0E0E0E` | palette (outlined `#2B2B2B`) |
| `black.4` | `#000000` | palette (outlined `#292929`) |

UI surface colors (measured in native frames):

| Surface | Hex |
|---|---|
| Window chrome: top bar, bottom bar, and the 6–8px frame around the video | `#181818` (bottom bar reads `#161616`–`#171717`) |
| Video canvas | `#000000` |
| Floating panels (queue, track popover, settings sidebar card, dialog body) | `#0E0E0E`–`#101010` |
| Library window background | `#0F0F0F` |
| Library nav panel | `#141414` |
| Compact-library panel | `#111111` |
| Mini-player card | `#171717`–`#181818` |
| Menus (`⋯` menu, right-click menu, sort and more menus) | `#141414`–`#171717` (zoomed samples; about `#161616`) |
| Menu divider | `#1B1B1B`–`#1F1F1F` (1px) |
| Panel divider | `#171717` (1–2px) |
| Text input bg | `#000000` (1px border about `#171717`–`#1A1A1A`) |
| Dropdown (select) bg | `#131313`, with a 1–2px darker border `#030303` (inset look) |
| Search field bg | `#141414`–`#151515` |
| Secondary button bg ("Cancel") | `#181818` |
| Full-width utility button bg ("Show Preferences") | `#000000`–`#040404` |
| Seek and slider track | `#000000` (reads `#030000`–`#0E0000`) |
| Volume-cone empty part | `#020202`–`#050505` |
| Volume-cone fill gradient | green `#66AF06` → olive `#7B8D05` → amber `#906902`. The gradient is mapped across the cone's full length, so higher volume shows more amber. |

Text colors (dark theme):

| Role | Hex |
|---|---|
| Primary label, list item, filename | `#888888`–`#9A9A9A` (menu items `#888`, popover items `#9A9A9A`, library filenames `#898989`) |
| Value text in inputs | `#8D8D8D` |
| Section header ("Synchronization", "Appearance", "Defaults") | `#9A9A9A`, medium weight |
| Secondary label (setting names, "Embedded Tracks", "Output Device") | `#666666`–`#6B6B6B` |
| Tertiary (keyboard shortcuts, durations, counts, "15 items") | `#555555`–`#626262` |
| Disabled or watched items | `#5D5D5D`–`#626262` |
| Search placeholder | `#2B2B2B` (very dim) |
| Window title | `#747474`–`#808080` |
| Bar time labels | `#7E7E7E`–`#878787` |
| Monochrome (clickable) icons | `#787878`–`#8A8A8A`. Inactive tab icons `#606060`. |

### 0.2 Typography (est.)

- **UI typeface:** a neutral grotesque, most likely **Inter** (double-storey a, flat-cut t, straight-leg R). Menu-bar mnemonic underlines appear only in the interim Windows-style menu bar. For the macOS app, use **Inter**, or SF Pro if a system font is preferred. The designer's video captions use IBM Plex Sans, which is not part of the UI.
- Sizes at native 1920 (est. from cap heights; Inter cap height ≈ 0.73 em):
  - Window title: about 14px regular (cap height 11px).
  - Bar time labels: about 14px regular, tabular figures ("00:00:00", 64px wide).
  - List rows, menu items, popover items: about 13–14px regular (cap height 9.5–10px).
  - Library breadcrumb: about 15px. The current crumb is semibold.
  - Section headers in the sidebar: about 14–15px medium.
  - Setting labels: about 13px regular.
  - Tab labels: about 12–13px regular.
  - Slider tick labels: about 11px.
  - Dialog title ("Add Subtitles"): about 13px regular `#888`.
- Weights: regular almost everywhere. Medium or semibold only for section headers and the current breadcrumb.

### 0.3 Radii ("rectangular but less sharp")

Rounding stays subtle on purpose and is never pill-shaped, with one exception: the seek and slider handle is a capsule.

| Element | Radius (est., native) |
|---|---|
| Play/pause button (55x29) | 4–5px |
| Seek-bar track (28px tall) | about 4px |
| Seek and slider handle (8x25) | 4px (full capsule) |
| Video canvas inset inside the window frame | about 4px |
| Floating panels (queue, popover, sidebar card, mini player, nav panel) | 6–8px |
| Dialog (Add Subtitles) | about 8px |
| Menus | about 6–8px |
| Inputs, dropdowns, segmented controls, buttons | 3–4px |
| Seek-preview tooltip card | about 11px |
| Library thumbnails | about 4–6px |
| Volume cone | the tip is rounded, and the wide end has about 3px corner radius |
| Palette swatches on the presentation slide | about 22%. Illustrative only; do not apply to UI. |

### 0.4 Spacing and sizing (native, est.)

- Top bar height **38px**. Bottom control bar height **52px** (y 1028–1079). The video canvas is inset **6px** left, **8px** right, and about 0–1px top and bottom inside the chrome.
- Standard row height in menus, popovers, and queue: **44px**. Compact-library rows: 42px. Library nav rows: 46px.
- Sidebar and popover setting rows: about 53px pitch. Inputs are **32px** tall and about 137px wide, right-aligned. Dropdowns are wider (about 218px).
- Panel inner padding: about 20–24px horizontal.
- Floating panels sit about 10–12px from the video edge and about 12–22px above the control bar.
- Icon sizes: control bar 16–20px. Top bar 14px (window controls) and 19px (cone and sidebar icons). Menu icons about 20px.

### 0.5 Icon styles

- **Decorative, non-clickable (menus):** two-tone line icons. The stroke is gray `#8F8F8F`; one sub-shape or fill is orange `#A36117`. Line weight is about 2px at 24px, with rounded joins and caps. The reference set at `01-intro-colors-icons/01m11.74s.jpg` shows: disc, gear, subtitles (rounded rect with dashed lines, the dashes orange), broadcast "((•))" with orange inner arcs, folder with orange tab, floppy/save with orange blocks, playlist (lines plus orange play triangle), and capture card with an orange play. These are used in the `⋯` menu, the right-click menu, the library "more" menu, and the equalizer presets.
- **Functional, clickable (everywhere else):** monochrome gray line icons in the same geometric family (`#787878`–`#8A8A8A`), about 1.5px stroke. Transport icons (prev/next/play/pause) are **filled** glyphs.
- **Active/open state:** the clickable icon turns **orange** (accent), and some switch to a filled variant. Examples: the subtitles icon becomes a filled orange block and the gear becomes a filled orange gear when their panels are open.
- The cone logo is the flat two-color cone: orange `#C8771B` with black stripes. It also appears small at the far left of the top bar.

---

## 0.6 Principles (her stated reasoning, paraphrased)

1. **Keep VLC's identity:** the traffic cone, the orange, and the rectangular look. She modernizes it but keeps it rectangular and only "a little less sharp", because rounded controls would make VLC look like every other player.
2. **Simple by default.** Most people want to click a video, have it play, and see a quiet little bar that does its job.
3. **The play button is not centered.** A centered button makes the control bar massive and generic, and most people use the keyboard to play and pause. Keep it at the left, make it slightly bigger, and put prev/next on either side of it.
4. **Use one thin row.** Everything sits in one slim bar so the video is not disrupted. The seek bar moves into that row and becomes **thick** (28px), not a hairline.
5. **Put things where people look.** Title and window controls go at the top (her survey: 86.8% look toward the top for the title). Subtitle and track controls go at the bottom right (80.8% expect them there). Fullscreen and settings go on the right.
6. **Hover reveal.** The top and bottom bars both persist in fullscreen. They show when the pointer is near them and disappear immediately when it moves away.
7. **Fewer clicks.** Subtitle and audio tracks are one click from the bar. Settings you use while watching go in a sidebar, not a modal that covers half the screen. Menus should not keep closing.
8. **No duplicate menus.** The old top menu bar duplicated the right-click menu, so she collapses it to one `⋯` menu for media and app options. The right-click menu stays because users expect it, and she cleans it up.
9. **Keep the spirit of quirky VLC controls.** The volume "deformed triangle" becomes a full **cone**, in VLC's green-to-orange colors.
10. **Queue vs playlist.** The queue plays things automatically. Playlists are saved collections. The old "toggle playlist" button becomes a **queue** button.
11. **Precise values plus easy controls.** Every numeric field gets both a typed value and a slider. Font sizes have Relative or Pixels modes. Settings can be saved as **presets** (per show).
12. **Expose hidden features.** Default subtitle and audio track, subtitle timeline, library, and sorting are moved into plain view.
13. **Never leave the video.** The library opens in a compact panel beside the video. You drag from the library to the queue.
14. **Two icon systems:** two-tone gray and orange for non-clickable menu decoration, and monochrome for clickable controls.

---

## 01 — Intro, colors, icons (00:00–01:30)

**Purpose and reasoning.** She describes VLC as the "goat" of media players but says its UI has worse problems than looking old. She ran a community survey, which got about 1.4k responses, and she emailed Jean-Baptiste Kempf, who named the priorities: the main UI (toolbars and sidebar), the media library, and the player menus and playback. Her decisions: keep the cone and the orange, and add neutral grays and blacks. Keep VLC's detailed two-tone gray and orange icon style but modernize it and make it consistent, using it for non-clickable menu icons, with a separate monochrome set for everything else. Keep things rectangular but less sharp.

**NEW elements**
- **Palette slide** (`00m58.42s.jpg`). Flat cone at left (about 370px wide). The grid has one 340x340 swatch, four 155x155 swatches in two rows, a row of four grays, and a row of four near-blacks with 3px outlines. The colors are in §0.1.
- **Decorative icon set** (`01m11.74s.jpg`, captioned "decorative"). Eight icons at about 140px display size: disc, gear, subtitles, broadcast, folder, save, playlist-play, capture card. The stroke is gray `#8F8F8F` with orange `#A36117` accents and rounded caps.
- **Play button preview** (`01m27.02s.jpg`). A square orange tile (`#985415` in this dimmed slide) with a rounded-corner near-black play triangle `#111111` whose corners are rounded. It previews the play glyph: rounded triangle, filled, dark on orange.

**OLD (for contrast only):** `00m59.74s`, `01m05.74s` (VLC 3 sidebar and glossy icons), `01m17.99s` (VLC 3 gray square buttons), `01m22.99s` and `01m25.52s` (VLC 3 Windows window with menu bar), and `01m20.47s` (another player shown for comparison).

**Best reference frames:** `01-intro-colors-icons/00m58.42s.jpg` (palette), `01m11.74s.jpg` (decorative icons), `01m27.02s.jpg` (play glyph).

**Open questions:** The full monochrome icon set is never shown as a slide; infer it from the bar and menus in later sections. Exact hex values may be shifted by video encoding: the palette's "main orange" `#C8771B` is warmer than the rendered control orange `#CF650A`. Treat `#C8771B` as the brand color and `#CF650A` as the control fill, or reconcile them in the Figma file if one is available.

---

## 02 — Control bar, seek bar, volume (01:30–03:30)

**Purpose and reasoning.** She rejects the centered play button: it is less unique, makes the bar huge, and most people use the keyboard. The play button stays at the left, slightly bigger, with prev and next on either side of it. Fullscreen and settings move to the right, where most players put them. "Toggle playlist" becomes a **queue** icon, also on the right. The queue is something you drag files into or add to with the + icon. The volume slider is kept as a full cone in VLC colors. The seek bar moves into the same row and becomes much thicker ("trust the process"). The result is a thin single row that does not disrupt the video. She adds **thumbnail preview while seeking**.

### NEW: final control bar (as seen in native frames from 04:06 on)
Reference: `04-subtitle-audio-buttons/04m10.91s.jpg` (paused, without the track icons), `06-subtitle-import-dialog/06m24.41s.jpg` and `08-media-library/09m30.06s.jpg` (final, with the audio and subtitle icons).

Bar: y 1028–1079 (52px), bg `#171717`. Measured left to right; content is vertically centered at y≈1054.

| # | Element | x range (px) | Size | Details |
|---|---|---|---|---|
| 1 | Previous | 27–37 | 11x12 | Filled skip-back glyph (bar plus triangle), `#787878` |
| 2 | Play/Pause button | 54–109 | **55x29** | Radius about 4–5px. **Paused:** bg accent `#CF650A`, near-black play triangle `#161614` with rounded corners. **Playing:** bg gray `#5E5E5E`, near-black pause bars. So orange means "press to play". (`04m06.72s` playing vs `04m10.91s` paused.) |
| 3 | Next | 128–137 | 10x12 | Filled skip-forward glyph |
| 4 | Elapsed time | 172/176–235 | about 14px text | "00:06:30", `#808080`, HH:MM:SS |
| 5 | Seek bar | about 250 → 1492 (to 1577 when the track icons are absent) | **28px tall** (y 1041–1068) | Track `#000`, radius about 4. Elapsed fill `accent.tint` `#301B00`–`#341C06`. Handle: orange capsule **8x25** `#D46206`, inset about 1–2px vertically. Flexible width. |
| 6 | Total time | 1507/1508–1571 | about 14px | "00:25:40" |
| 7 | Mute/speaker | 1600–1620 | 20x16 | Outline speaker with two sound bars, `#888`. Clicking toggles mute (inferred). |
| 8 | **Volume cone** | 1630/1631–1718 | about 88 wide, about 8px tall at the tip to about 26px at the base | A horizontal cone (trapezoid) pointing left. The tip is rounded and the right end has small radii. Empty part `#020202`. Fill grows from the tip, with a green-to-amber gradient mapped over the full length: `#66AF06` → `#7B8D05` → `#906902` at about 70%. There is no separate knob. |
| 9 | Audio tracks | 1744–1761 | 18x19 | Waveform icon (five vertical bars). Orange when its popover is open. |
| 10 | Subtitle tracks | 1784–1805 | 22x16 | Rounded rect with dashed caption lines. When the popover is open it becomes a filled orange block (`06m21.67s`). |
| 11 | Playback settings | 1829–1846 | 18x19 | Gear with a play triangle inside. Opens the settings sidebar (section 07) and turns into a filled orange gear while open. |
| 12 | Queue | 1879–1896 | 18x13 | Bulleted-list icon. Orange `#9D4B0F` while the queue panel is open (`09m30.06s`). |

Spacing (est.): about 18px between icons on the right, about 20px between groups, and about 14px between a time label and the seek bar. Before the track icons were added (`04m06.72s`), the right side was time, mute, cone, gear, queue, with no fullscreen icon in the bar. **Fullscreen moved to the top bar** (section 03).

### NEW: seek thumbnail preview
Reference: `02-control-bar-seekbar-volume/03m29.34s.jpg` (about 3.5x zoom).
- A card above the pointer and handle, centered horizontally on the hover x. Est. about 295x206px native, radius about 11px, bg `#181818`.
- Inside: a frame thumbnail with about 11px inset and a small radius, then the timestamp "00:02:10" (about 14px, `#888`) centered below.
- Shown while hovering or dragging on the seek bar.

### NEW: queue panel (introduced here, final look in 08)
Reference: `02m53.87s.jpg` (zoomed) and `08-media-library/09m30.06s.jpg` (native).
- Native: a floating card at the right of the video, x 1503–1900 (about **398 wide**), y about 50–1015. Bg `#0F0F0F`, radius about 6px.
- Header row (y≈83): "11 items - 4h 12m" (`#5A5A5A`, about 13px) at left. At right, five icons spaced about 40px apart: **sort** (↓↑), **repeat**, **shuffle**, **remove** (−), **add** (+), in gray `#666`.
- Rows: 44px pitch, starting at y≈134. Each row has a drag handle "=" at left (`#888`), the filename (`#909090`, about 13–14px) at x≈1564, and the duration right-aligned (`#575757`).
- The now-playing row replaces the handle with an **orange ▶** and shows its filename in orange (`11m56.96s`).
- Behavior: drag to reorder. Drag files from Finder or the library into the panel. + opens a file picker, and − removes the selection.

### INTERIM / OLD frames in this section (do not copy)
- `01m56.77s`, `02m02.77s`, `02m07.64s`: [OLD] VLC 4 upcoming design with a centered white round play button. She rejects it.
- `02m09.11s`: [OLD] YouTube-style example.
- `02m21.81s`, `02m27.64s`, `02m44.14s`, `02m55.31s`: [INTERIM] VLC 3 bar reskinned step by step: orange play button, then queue/repeat/shuffle moved right, then a wedge volume with "0%".
- `03m02.39s`, `03m08.39s`, `03m14.39s`: development of the cone volume. `03m14.67s` and `03m20.67s`: [INTERIM] one-row bar with the cone volume and a fullscreen icon at the far right. `03m25.52s`: "trust the process", the bar at its intermediate stage (play button `#D36206`).

**Best reference frames:** `04-subtitle-audio-buttons/04m10.91s.jpg` (paused bar, native), `04m06.72s.jpg` (playing state), `06-subtitle-import-dialog/06m24.41s.jpg` (final bar with track icons), `02-control-bar-seekbar-volume/03m08.39s.jpg` (cone close-up), `04m30.41s.jpg` (cone gradient close-up), `03m29.34s.jpg` (seek preview), `08-media-library/09m30.06s.jpg` (queue, native).

**Open questions:**
- Hover and pressed states for bar icons and the play button are not shown. Infer: icon brightens toward `#B0B0B0` on hover, and the play button lightens or darkens about 8% when pressed.
- Whether the cone also shows a numeric %: the interim design showed "0%", the final shows none.
- Whether scroll-wheel volume is supported is not stated.
- The mute state glyph is not shown.
- The handle hover size is not shown.
- Elapsed vs remaining time toggle: an asterisk variant appears in subtitle-timeline mode (section 07).
- The waveform-in-seek-bar option is mentioned (section 07) but not shown here.

---

## 03 — Top bar, fullscreen, hover behavior (03:30–04:00)

**Purpose and reasoning.** Old VLC hides the title in fullscreen, yet most people look at the top for the title (survey: 86.8% "toward the top"). So **both the top and bottom bars stay available in fullscreen**: they appear when hovering near them and disappear immediately when the pointer moves away. She likes putting **fullscreen** (and maybe **picture-in-picture**) icons in the top bar and asks viewers which they prefer.

### NEW: top bar (final form)
Reference: `06-subtitle-import-dialog/06m24.41s.jpg` (playing), `08-media-library/11m56.96s.jpg` (with library controls).
- Height 38px (y 0–37), bg `#181818`, spanning the full window width.
- **Left cluster:**
  - Cone logo: x 13–31, about 19x22px, orange and black.
  - `⋯` menu button: x 55–69, three dots, `#888`. It opens the app/media menu (section 05).
  - From section 08 on: sidebar-toggle icon (x 91–109), a 1px divider (`#1F1F1F`, x≈126), a folder icon (x 143–161), and the folder name "S01" (`#7B7B7B`, about 14px). The folder chip opens the library.
- **Center:** the media title ("The Wand S01E04"), `#7C7C7C`–`#808080`, about 14px, centered on the window. With no media or in the library it reads "VLC Media Player".
- **Right cluster:** window controls at x≈1784–1904, spaced about 36px apart, each about 14x14 with a thin 1.5px gray stroke:
  - **minimize** (—)
  - **maximize** (□)
  - **fullscreen** (corner brackets ⛶)
  - **close** (✕)
- The option she showed at `04m00.66s` adds **picture-in-picture** (a square with a filled lower-right inner square) between minimize and maximize. That makes five icons; her final frames use four.
- macOS adaptation: replace minimize, maximize, and close with the native traffic lights, or keep her flat glyphs in a custom title bar. Keep fullscreen (and optionally PiP) as custom icons at the right.

### NEW: video canvas and window frame
- The video canvas is inset inside the `#181818` chrome by about 6px left, 8px right, and 0–1px against the bars, with about 4px rounded corners (`04m10.91s`).
- **Hidden-bars state** (`03m53.56s.jpg`): the bars are hidden and the video expands. In windowed mode only a thin `#181818` frame of about 8px remains around the rounded video. In fullscreen, assume no frame.

### Behavior
- Show the top and bottom bars when the pointer approaches within about 1 bar-height of the top or bottom edge. The threshold is est.; she says "hover near them".
- Hide them **immediately** when the pointer leaves that zone. No long timeout is described. Use a short fade of about 120–150ms (inferred).
- The same applies in fullscreen. The bars overlay the video rather than resizing it (inferred, because in fullscreen the video must not jump).
- There is also a full-hide-UI option: the right-click menu item plus the **Ctrl+\\** shortcut (section 05).

### INTERIM
`03m31.29s` (empty), `03m37.29s` (VLC 3 fullscreen with the bar only), `03m47.56s.jpg`: an interim window that still has the Windows-style text menu bar ("Media Playback Audio Video Subtitle Tools View Help") and the video title centered. That bar is the same height, and its controls are play, seek, volume cone, gear, queue, and an exit-fullscreen icon. Replaced in section 05 by the `⋯` menu.

**Best reference frames:** `03-top-bar-fullscreen-hover/03m47.56s.jpg` (interim, but shows the hover layout), `03m53.56s.jpg` (bars hidden), `03m45.12s.jpg` (survey), `03m54.66s.jpg` and `04-subtitle-audio-buttons/04m00.66s.jpg` (window-control icon designs), `06-subtitle-import-dialog/06m24.41s.jpg` (final top bar).

**Open questions:** Exact hover zone, fade timing, and whether the cursor auto-hides with the bars are not shown. Whether the top bar is draggable is not stated (it should be the window drag region). Whether PiP made the final cut is undecided; she left it as a poll.

---

## 04 — Subtitle and audio buttons, track popover (04:00–05:00)

**Purpose and reasoning.** Picking a subtitle track in old VLC takes right-click → Subtitle → Sub Track, and the menus keep closing. The upcoming VLC 4 has a tracks icon at the bottom left, but 80.8% of her respondents expect it at the bottom right. So a **subtitle icon** on the right opens a list of subtitle tracks. Next to it, an **audio icon** shows both audio tracks and **audio output device** (headphones or speakers) so you never leave VLC to switch. A **Video** tab is added to the same popover, but without its own bar icon, because few people change video tracks. It is reachable through the tabs or the right-click menu.

### NEW: track popover
References:
- `04-subtitle-audio-buttons/04m36.41s.jpg` and `04m42.41s.jpg`: Audio tab, zoom about 1.65x, early two-tab version (Audio | Subtitles).
- `04m54.76s.jpg`: three tabs, Video active (right side).
- `06-subtitle-import-dialog/06m21.67s.jpg`: **native**, Subtitles tab with External Tracks.

Geometry (native, `06m21.67s`):
- The card spans x 1503–1900 (**about 398 wide**) and y about 485 to 1005, so it is anchored at the bottom right of the video, about 12px from the right edge and about 22px above the bar.
- **Tab strip** at the top, about 46px tall, bg near-black `#010101`. Three equal tabs: **Video** (film/calendar icon), **Audio** (waveform), **Subtitles** (caption box), each a 16px icon plus about 12–13px label.
  - Active tab: orange icon, label `#858585`, and a **2px orange underline** spanning about the tab width (112px), sitting on the strip's bottom edge.
  - Inactive tabs: icon and label `#606060`.
- **Body** bg `#101010`, radius about 6–8px at the bottom corners.
- **Section header** ("Embedded Tracks", "Output Device", "External Tracks"): about 13px, `#666`, at x+26px. A header may carry trailing icon buttons at the right edge:
  - Output Device: a **refresh** (circular arrows) icon.
  - External Tracks: a **pencil** (edit) icon and **+** (add) icon.
- **Rows:** 44px (est.), label `#9A9A9A` about 13–14px at x+60px. The selected row shows an **orange check ✓** at x+26px. Rows: "None", "Track 1 - English", and external items such as "The_Wand_S01E04 [English]".
- **Divider** between sections: `#171717`, 2px, full width.
- **Footer button** "Show Preferences": full width minus about 18px insets, **32px tall**, bg `#000000`/`#040404`, label centered `#696969`, radius about 3–4px, about 18px from the bottom. It opens the settings sidebar (section 07).

Tab contents:
- **Audio:** Embedded Tracks (None, ✓ Track 1 - English), then a divider, then Output Device with refresh (Speakers, ✓ Headphones), then Show Preferences.
- **Subtitles:** Embedded Tracks (None, ✓ Track 1 - English), then a divider, then External Tracks with pencil and + (list of loaded subtitle files), then Show Preferences. **+** opens the Add Subtitles dialog (section 06).
- **Video:** Embedded Tracks (None, ✓ Track 1 - English), then Show Preferences.

Behavior:
- Clicking the bar icon toggles the popover with that tab selected, and the bar icon turns orange (filled for subtitles).
- The popover stays open while you pick, so it does not close like old menus (inferred from her complaint). Clicking outside or pressing Escape closes it (inferred).

**Survey frames:** `04m28.11s.jpg` (bottom right 80.8%), `04m48.76s.jpg` (how often people change video tracks).

**OLD:** `04m09.81s`–`04m18.14s` (VLC 3 right-click menus), `04m20.62s` (VLC 3 bar with a record button), `04m22.61s` (VLC 4 bottom-left tracks icon). In `04m54.76s`, the left side shows the [OLD] right-click menu Video → Video Track.

**Best reference frames:** `06-subtitle-import-dialog/06m21.67s.jpg` (native), `04-subtitle-audio-buttons/04m42.41s.jpg` (clean zoomed), `04m54.76s.jpg` (Video tab), `04m48.41s.jpg` (bar icons zoom: audio waveform, subtitles, gear, queue).

**Open questions:**
- Popover open and close animation is not shown (suggest a fade plus 6–8px upward slide, about 150ms).
- Row hover state is not shown (suggest bg `#161616`).
- The "Video" tab icon resembles a calendar or clapper; its exact glyph should be taken from the zoomed frame `04m54.76s`.
- What "Show Preferences" opens exactly: almost certainly the section-07 sidebar on the matching tab.

---

## 05 — Menus: `⋯` app menu and right-click menu (05:00–05:30)

**Purpose and reasoning.** The old top menu bar repeats the right-click menu. She removes the duplicate and replaces the menu bar with **one `⋯` menu icon** containing media-related options and extra settings. The right-click menu is essential, since users reflexively right-click for settings, so she keeps it, cleans it up, restyles it, and adds an option to **hide the UI completely**, also available by a keyboard shortcut (shown: **Ctrl + \\**).

### NEW: `⋯` menu (top-bar menu)
Reference: `05-menus-right-click/05m08.96s.jpg` (about 1.49x zoom).
- Drops from the `⋯` button, left-aligned just under the top bar. Est. native width about **345px**. Row pitch about **44px**. Bg `#161616`, radius about 8px.
- Each row: two-tone decorative icon (about 20px) at left, label (`#888888`, about 13px), and the shortcut right-aligned (`#5F5F5F`), or a chevron › for submenus.
- Items, in order:
  1. Open File — Ctrl + O (file icon with an orange corner)
  2. Open Multiple Files — Ctrl + Shift + O
  3. Open Directory — Ctrl + F (folder)
  4. Open Disc — Ctrl + D (disc with orange arcs)
  5. Open Network Stream — Ctrl + N (broadcast "((•))")
  6. Open Capture Device — Ctrl + C (capture card)
  7. Open Location from Clipboard — Ctrl + V (link)
  8. Open Recent › (clock with arrow)
  9. *divider* (`#1B1B1B`)
  10. Save Playlist to File — Ctrl + Y (orange down arrow)
  11. Convert / Save — Ctrl + R (swap arrows)
  12. Stream — Ctrl + S (broadcast)
  13. Customize Player (brush)
  14. Plugins & Extensions › (puzzle piece)
  15. Settings — Ctrl + p (gear)
  16. About VLC — Shift + F1 (info circle)
- On macOS, map Ctrl to ⌘. Mirror these items in the native macOS menu bar as well; this is a platform requirement and is not in the video.

### NEW: right-click (context) menu
Reference: `05-menus-right-click/05m23.01s.jpg` (about 1.6x zoom).
- Est. native width about **275px**, rows about 44px. Bg `#171717`, radius about 8px, dividers `#1F1F1F` 1px.
- Items:
  1. Play — Space (orange play outline)
  2. Stop — S (orange square)
  3. Previous Item — P
  4. Next Item — N
  5. Record — R (orange record ring)
  6. *divider*
  7. Playback ›
  8. Video › (film icon with orange top)
  9. Audio › (waveform, orange)
  10. Subtitle › (caption box)
  11. *divider*
  12. More Settings › (gear)
  13. Playlist › (list plus orange play)
  14. Open Media › (file)
  15. Quit VLC — Ctrl + Q (exit arrow)
- Shortcut text `#5F5F5F`. Submenu chevrons `#888`.

### NEW: Hide UI
`05m29.01s.jpg` shows the keycaps **CTRL + \\** (rounded dark keycaps with a lighter rim, presentation graphic). Behavior: toggles all chrome off, leaving only the video.

### Interim player
`05m14.96s.jpg` (window at about 0.94 scale) shows the top bar now with cone + `⋯` and four window controls, and the bottom bar with the audio and subtitle icons. This is the near-final layout.

**OLD:** `05m00.21s` (VLC 3 View menu), `05m02.96s` (VLC 3 menu bar vs right-click duplication).

**Best reference frames:** `05-menus-right-click/05m08.96s.jpg`, `05m23.01s.jpg`, `05m14.96s.jpg`, `05m29.01s.jpg`.

**Open questions:**
- The "hide UI" item is not visible in the right-click menu frame. It may sit inside More Settings or have been omitted from the mockup; add it, e.g. "Hide Interface — Ctrl + \\".
- Submenu contents (Playback › / Video › / Audio › / Subtitle › / More Settings › / Playlist › / Open Media ›) are not shown. Infer them from VLC's existing menus, cleaned up.
- Menu hover row is not shown. Infer bg about `#1E1E1E`, label brightened to `#B0B0B0`. The sort menu in section 08 shows the selected row at `#1C1C1C`.
- Keyboard-focus styling is not shown.

---

## 06 — Subtitle import dialog (05:30–06:25)

**Purpose and reasoning.** Getting third-party subtitles is painful: you download a zip, extract it, and the names do not match. VLC matches similar names, but you often have to drag a subtitle onto every episode. Her fix: in the subtitle section, **Add (+)** opens a dialog where you choose the scope (**this file, this folder, or this playlist**) and the source (**this computer or a website like OpenSubtitles**). Subtitles are then auto-matched to every episode, or matched manually, and saved for all future episodes.

### NEW: "Add Subtitles" dialog
References:
- `06-subtitle-import-dialog/06m02.47s.jpg`: **native**, empty state.
- `06m08.47s.jpg`: scope dropdown open, zoomed.
- `06m14.47s.jpg`: populated, about 1.8x zoom.
- `06m20.47s.jpg`: populated, near-native, with the row hover state.

Geometry (native, `06m02.47s`):
- Modal centered over the video area: x 436–1482 (**about 1046 wide**), y about 140–940 (**about 800 tall**), radius about 8px.
- **Header** (y 140 to about 234): bg `#000000`. Title "Add Subtitles" at top left (about 13px, `#888`, x+17, y≈164). Close ✕ at top right (`#888`, about 12px glyph).
- **Toolbar** row inside the header (from `06m20.47s`, y≈190), four controls about 34px tall, bg `#141414`–`#1E1E1E`, radius about 3px:
  1. Scope dropdown "To This Folder ⌄" (about 205 wide).
  2. Source dropdown "From OpenSubtitles ⌄" (about 205 wide).
  3. Search field with magnifier + "The Wand S01" (flex, about 410 wide).
  4. Language dropdown "English ⌄" (about 205 wide).
- Scope dropdown menu (`06m08.47s`): options "To This File" ✓ (orange check), "To This Folder", "To This Playlist". Bg `#1A1A1A`, rows about 44px. It opens directly under the label "Add Subtitles", replacing the toolbar position in that state.
- **Body** bg `#0F0F0F`. A two-column mapping list:
  - Left: video file (film icon + "The_Wand_S01E01.mp4"), then a **dashed connector line** (`#2A2A2A` dashes) running to mid-width.
  - Right: matched subtitle (doc icon + "The_Wand_S01E01.srt").
  - Rows about 41px pitch, text `#8A8A8A` about 13px, icons gray.
  - **Hover** on a match row: row bg `#000000` (full right-column width, radius about 3px), and a **swap ⇆ icon** appears at the far right for choosing a different file manually (`06m20.47s`, row E12).
- **Footer** (about 50px):
  - **Cancel** at left: bg `#181818`, label `#888`, about 100x32, radius about 3px.
  - **Save** at right: bg `accent.tint` `#301B00`, label orange `#C66D2D`, about 100x32. This is the primary-button style.

Flow: Subtitles popover → External Tracks **+** → dialog → Save. The loaded file then appears under External Tracks ("The_Wand_S01E04 [English]", `06m21.67s`).

**OLD:** `05m31.44s`–`05m48.64s` (the browser, zip, file manager workflow), `05m51.56s`–`05m58.87s` (dragging .srt files onto VLC 3).

**Best reference frames:** `06-subtitle-import-dialog/06m02.47s.jpg` (geometry), `06m20.47s.jpg` (populated plus hover), `06m14.47s.jpg` (legible detail), `06m08.47s.jpg` (scope options).

**Open questions:**
- Source dropdown options: "From This Computer" is implied by the transcript but not shown.
- Behavior when there are unmatched files (empty right cell?) is not shown.
- Whether the dialog dims the video behind it: no visible scrim in the frames; the video stays visible. Consider a 40% black scrim on macOS, or a sheet.
- Search results and auto-match indicator are not shown.
- Language list contents are not shown.

---

## 07 — Settings sidebar: Subtitles, Audio, Video, Playback tabs (06:25–09:20)

**Purpose and reasoning.** The old "Adjustments and Effects" window (opened by the gear-like icon) holds half the in-playback settings, including subtitle timing, and covers half the screen. You use it, close it, rewind, and repeat. Her fixes:
- A **subtitle timeline** in the seek bar shows when each line appears, so you can pause and nudge the subtitles into sync.
- All these preferences move to the right as a **sidebar with four tabs**.
- Typed values get **sliders**.
- Font, size, outline, and position can be changed while watching, with **Relative or Precise (Pixels)** size modes. VLC already supports precise sizes, but they are buried in advanced settings.
- Settings can be saved as **presets** per show.
- A **default subtitle track and language** is set right in the sidebar instead of in Input/Codecs.
- Audio gets the same treatment (default track, delay), plus expandable filters: an equalizer for experts, and friendly presets **with preview icons** for everyone else.
- Video filters get the same, plus flip, rotate, zoom, HDR, resolution, aspect ratio, and similar.
- A **Playback** tab holds speed, reverse, sleep timer, show subtitle timeline, show waveform on seek bar, and show metadata.

### NEW: subtitle timeline mode (seek bar)
References: `07-sidebar-subs-audio-video-playback/06m58.19s.jpg` (zoom), `07m04.19s.jpg` (**native**).
- The seek bar turns into a zoomed timeline window (time labels become range bounds with an asterisk: "00:06:00*" … "00:07:00*").
- Inside the 28px bar, each subtitle cue is a block 24px tall (2px inset), as wide as the cue's duration.
  - Past or elapsed side: block `#4B3722` on elapsed bg `#301D05`.
  - Future side: block `#212121` on `#000`.
- The orange handle is the playhead.
- At the bar's left end there are two small orange buttons, **‹** and **−**; at the right end, **+** and **›**. Each is about 20x28, bg `#9F4E00`–`#A75002`, dark glyph, radius about 3.
  - **−/+** shift the subtitle delay (equivalent to the `[` and `]` hotkeys, `06m52.19s`).
  - **‹/›** scroll the timeline window (est.).
- This mode is toggled from the Playback tab, "show subtitle timeline" (per transcript).

### NEW: settings sidebar
Container:
- Same width as the track popover, **about 398–400px**, anchored at the right of the video above the bar.
- Opened by the gear icon in the bar (the gear turns filled orange) or by "Show Preferences".
- The tab strip sits on black, the body card is `#0F0F0F`–`#101010`, and the body scrolls.
- Est. from zoomed frames (factor about 1.82–1.84): left padding about 21px, label column left, value column right-aligned, row pitch about 53px, inputs **32px tall × about 137px**, dropdowns about 218px wide.

Tabs (left to right, `09m12.97s`): **Playback** (play-triangle icon), **Video** (film icon), **Audio** (waveform), **Subtitles** (caption box). Active tab: orange icon + lighter label + 2px orange underline. Early mock frames show placeholder "Tab" labels for the other three.

Shared controls:
- **Section header:** e.g. "Synchronization", about 14–15px medium `#9A9A9A`, with about 30px top padding. Sections are separated by a full-width 1–2px divider `#171717`–`#1B1B1B`.
- **Label:** `#666666` about 13px.
- **Text/number input:** bg `#000`, about 1px border `#171717`, radius about 3px, value `#8D8D8D` about 13px with a unit suffix ("-2.000 s", "1.000 fps", "0px", "18px").
- **Slider:** a full-width row under its input.
  - Track 16px tall (est.), `#000`, radius about 4.
  - Fill `accent.tint` `#321800`. For bipolar values like delay, the fill runs from 0 (center) to the value.
  - Handle orange capsule `#A75002`, about 8x24.
  - Optional tick labels below (`#555`, about 11px): "-10 s" / "0 s" / "+10 s". The speed slider has tick marks inside the track plus labels 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2.
- **Toggle:** two-segment pill about 66x32 (est.), a dark track `#1E1E1E` with a square knob `#333333` on the left and an "OFF" label `#686868` on the right. The ON state is not shown; infer knob on the right in accent with an "ON" label.
- **Segmented control:** e.g. "Relative | Pixels" or "None | Horizontal | Vertical".
  - Container with a 1px black border.
  - Inactive segment: bg `#151515`, text `#656565`.
  - Active segment: bg `#301B00`, text orange `#AD682B`.
  - Radius about 3–4px. About 177x32 (2 segments) or full width (3 segments).
- **Dropdown:** bg `#131313`, 1–2px dark border `#030303`, value text `#8D8D8D`, chevron ⌄ at the right, about 40px tall (est.; video tab).
- **Color field:** an input showing the hex ("#B8B8B8") plus a 20x20 swatch square at its right end.
- **Small accent button:** "Test" (Audio → Stereo Mode): bg `accent.tint`, orange text.
- **Expand/Collapse row:** "Expand Settings ›" is a full-width 40px row on `#000` bg with a chevron. When expanded, the header reads "Collapse Settings" with a chevron up.

**Subtitles tab** (`07m47.87s`, `07m52.89s`, `07m58.89s`, `08m30.97s`, `08m36.97s`):
- **Defaults:**
  - Subtitle Track (input "1")
  - Subtitle Language (input "English")
- **Synchronization:**
  - Subtitle Track Delay (input "-2.000 s", bipolar slider -10 s…0 s…+10 s)
  - Subtitle Speed (input "1.000 fps" plus slider)
  - Subtitle Duration Factor (input "0.000" plus slider)
- **Appearance:**
  - Embedded Sub Format (toggle OFF)
  - Subtitle Font (input "Helvetica")
  - Text Color (#B8B8B8 plus swatch)
  - Outline Color (#0C0C0C plus swatch)
  - Subtitle Offset ("0px")
  - Size Values (segmented **Relative / Pixels**, Pixels active)
  - Font Size ("18px")
  - Outline Thickness ("2px")
  - Background Opacity ("0%")
  - In **Relative** mode (`07m26.11s`, `07m34.81s`): Font Size becomes a slider labeled "Auto", Outline Thickness becomes a slider labeled "Normal", and Background Opacity reads "0 %".
- **Presets** (`07m58.89s`): a popup list anchored near the bottom of the panel, bg `#141414`.
  - First row "+ New Custom Preset" (`#666`).
  - Then presets, each with a leading "⋯" (more) icon: Default Preset, Custom Preset 01, Custom Preset 02, Anime, Loud and then Quiet Movies, The Wand Subtitle Preset ✓ (selected: orange check, row bg `#1A1A1A`).
- **Footer link:** "⚙ Open Advanced Settings" centered, `#5C5C5C`.

**Audio tab** (`08m42.97s`, `08m48.97s`, `08m54.97s`):
- **Defaults:**
  - Audio Track ("1")
  - Audio Language ("English")
  - Stereo Mode (with an orange **Test** button), then a full-width dropdown "Mono"
- **Synchronization:** Audio Track Delay ("0.000 s", bipolar slider; the frame shows "-10 s / 0 s / -10 s", a typo for +10 s)
- **Filters:**
  - Equalizer: dropdown "None". Its option list shows presets with tiny two-tone **EQ-curve preview icons**: None ✓, Live, Party, Pop, Reggae, Rock, Ska, and more.
  - "Expand Settings ›" opens "Collapse Settings" with Preamp ("12.0 dB" plus slider) and band sliders 60 Hz, 170 Hz, 310 Hz, 600 Hz, … (each "0.0 dB" plus a bipolar slider centered).
  - Stereo Widener (toggle OFF plus "Expand Settings ›").

**Video tab** (`09m00.97s` zoom, `09m06.97s`):
- **Defaults:**
  - Flip (3-segment None / Horizontal / Vertical, None active orange)
  - Rotate (input "0 deg")
  - Zoom (dropdown "1:1 Original")
  - HDR ("Auto")
  - Resolution ("Best Available")
  - Aspect Ratio ("Default")
  - Crop ("Default")
  - Render ("Local")
- **Filters** → "Essential" … (the list continues off-frame; per transcript, filters with preview thumbnails).

**Playback tab** (`09m12.97s`):
- Reverse (toggle OFF)
- Sleep Timer (dropdown "Off")
- Speed (input "1x" plus ticked slider 0.25–2, handle at 1)

**OLD:** `06m34.21s`–`06m46.19s` and `07m05.17s` (VLC 3 Adjustments and Effects window), `07m26.11s`–`07m41.87s` and `08m07.21s` (VLC 3 Advanced Preferences, "Freetype2 font renderer"), `08m08.44s`–`08m13.71s` (Google and Reddit searches), `08m16.87s` (Input/Codecs), `08m22.54s` and `08m24.19s` (memes).

**Best reference frames:** `07m04.19s.jpg` (native timeline), `07m47.87s.jpg` (sync plus appearance controls, clearest), `07m52.89s.jpg` (Appearance in Pixels mode), `07m58.89s.jpg` (presets list and footer link), `08m36.97s.jpg` (Defaults), `08m42.97s.jpg`, `08m48.97s.jpg`, `08m54.97s.jpg` (Audio, EQ), `09m00.97s.jpg` and `09m06.97s.jpg` (Video), `09m12.97s.jpg` (Playback tab strip, all four tab icons).

**Open questions:**
- The Playback-tab toggles "Show subtitle timeline", "Show waveform on seek bar", and "Show metadata" are described but not visible. Add them as toggles below Speed.
- The waveform-on-seek-bar visual appears in the music section (part 2).
- The exact location of the preset selector trigger is not shown; the list appears to pop up from a row just above "Open Advanced Settings". Infer a "Preset: <name> ⌄" dropdown row at the panel bottom.
- Video filter preview thumbnails are not visible in these frames.
- Whether the sidebar overlays or pushes the video: frames show it overlaying the right side of the video (like the popover).
- Toggle ON state and slider hover state are not shown.
- Whether the sidebar is resizable is not shown.

---

## 08 — Media library (09:20–12:00)

**Purpose and reasoning.** The fastest way to watch the next episode is a library, but VLC hides it. VLC 3 lumps files together regardless of folder. VLC 4 makes you go through "Browse" (with a Wi-Fi icon) and an internal file explorer, and you return to the library with a back button. She cleans up the current library:
- Categories **Videos, Music, Network (streams), Playlists**.
- Back and forward buttons, plus a **clickable address line** (breadcrumb) to move up and down folders.
- Standard **sort**, **view mode** (grid, list, detail), and **search** controls in the header. Previously, sorting existed only in the right-click menu.
- Sorting adds **Unwatched First and Watched First**.
- A **⋯ more** menu with Add File, Add Folder, and so on.

To open the library from the player she rejected a back icon, a home icon, and a vague library icon. Instead, the top bar shows the **name of the current folder** (e.g. "S01"), the most recognizable thing. A **sidebar icon** next to it signals that it opens something, and the library opens in **compact mode** next to the video. You drag from the library to the queue. A full-window library is still available, with a **mini player** and a draggable queue. Her idea is that you never have to leave the video.

### NEW: full library window
Reference: `08-media-library/10m57.64s.jpg` (**native**, grid), `11m48.27s.jpg` (list view plus mini player), `11m54.27s.jpg` (mini player with queue expanded).
- **Top bar:** same 38px chrome, with cone and `⋯` at left and the title "**VLC Media Player**" centered. Window controls at right.
- **Window bg:** `#0F0F0F`.
- **Nav panel (left):** x 5–206 (**202 wide**), y about 47–1073, bg `#141414`, radius about 8px.
  - Items at 46px pitch, starting about y 75: icon (20px) at x≈26 and label at x≈59, about 14px, `#7C7C7C`.
  - Items: **Videos** (folder-play icon), **Music** (folder-note), **Network** ("((•))"), **Playlists** (list with play).
  - **Active item:** shown with a **filled** icon (Videos). There is no highlight bg in this frame.
- **Header row** (y≈75, height about 62):
  - ← and → arrows (`#6D6D6D`) at x 236–290.
  - **Breadcrumb** "Videos ▸ Shows ▸ The Wand ▸ **S01**": about 15px, parents `#8C8C8C`, current crumb semibold `#909090`, small ▸ separators `#4A4A4A`. Each crumb is clickable.
  - At right: "15 items" (`#595959`), **sort** icon (↓↑), **view-mode** icon (grid ⊞ or list, cycling grid → list → detail), **search field** (x 1533–1869, about 336x34, bg `#141414`, magnifier + placeholder "Search" `#2B2B2B`, radius about 4), and **⋯ more** (x≈1890).
  - A divider line `#171717` 1px at y 109, spanning the content width (x 235 to about 1900).
- **Grid view:**
  - Five columns at 1920 width.
  - Thumbnails **317x178** (16:9), radius about 4–6px. Column pitch 337 (20px gap). Row pitch about 258.
  - First thumbnail at x 235, y 130.
  - Filename below the thumbnail (y +30), about 14px `#898989`.
  - **Watched items:** filename dimmed `#626262`, with a 3px **orange progress line** along the thumbnail bottom (inset about 3px) showing the amount watched.
  - The current sort in the frame lists unwatched first and watched last (E05–E15, then E01–E04).
- **List view** (`11m48.27s`):
  - Four columns of compact rows at 42px pitch.
  - Each row: 32x32 thumbnail plus filename (about 14px).
  - The now-playing item is orange text with a ▶ overlay on its thumbnail. Watched items are dimmed with an orange underline on the thumbnail.
- **Sort menu** (`10m49.49s`, zoomed, interim lighter bg):
  - Options: Unwatched First, Watched First ✓, Newest First, Oldest First, Title A-Z, Title Z-A.
  - Rows about 44px, selected row bg `#1C1C1C` with an orange ✓, menu bg `#181818`.
- **More menu (⋯)** (`10m55.49s`), with two-tone icons:
  - + Add File
  - Add Folder
  - Edit Subtitle Tracks
  - Edit Audio Tracks
  - Resync (orange refresh)
  - Info
- **Mini player** (`11m48.27s`):
  - A floating card at the bottom right, x about 1525–1916, y about 736–1075 (about **390x340**), bg `#171717`, radius about 8.
  - Contents: video preview (about 376x211, black); a progress bar about 15px (track `#000`, fill `#301C07`, radius about 3); the title "The_Wand_S01E05.mp4" (`#939393`, about 14px); and a bottom row with a folder icon + "S01" at left and a **queue icon** at right.
  - Clicking the queue icon (it turns orange) **expands a Queue section above the video**, with a "Queue" title and the queue list with header controls (`11m54.27s`).
  - The card is **draggable**: it was moved to the bottom left in `11m54.27s`.

### NEW: player with compact library (the primary flow)
Reference: `08-media-library/11m45.76s.jpg` (dragging an item to the queue), `11m56.96s.jpg` (**native**, final).
- **Top bar left:** cone, ⋯, **sidebar-toggle icon** (rectangle with a left pane), 1px divider, **folder icon + current folder name "S01"**. The title is centered ("The Wand S01E05").
- **Icon rail:** x 0–46 (47 wide), bg `#171717` (continuous with the chrome). Four category icons stacked at 46px pitch from y≈62: Videos (filled when active), Music, Network, Playlists, each 20px `#878787`/`#555`.
- **Compact library panel:** x 47–424 (**378 wide**), bg `#111111`, full height between the bars.
  - **Row 1** (y≈70): ← and → (→ dimmed when unavailable), breadcrumb "… ▸ The Wand ▸ S01" (about 15px, `#8A8A8A`), then ⋯ more and an **open-full-library icon** (square with an arrow ↗) at the right.
  - **Row 2** (y≈115): "15 items" (`#646464`) at left; sort (↓↑), view-mode (list), and **search** (magnifier) icons at right.
  - Divider at about y 145.
  - **Rows:** 42px pitch from y≈180. Each row: 32x32 thumbnail + filename about 13–14px.
    - Now playing: thumbnail shows an orange ▶ overlay and the name is orange (`#A66857`).
    - Normal: `#909090`.
    - Watched: dimmed `#5D5D5D` with an orange bar under the thumbnail.
    - Hover: a "⋯" appears at the row's right end (`11m45.76s`, row E06).
- **Video** occupies x 426–1500.
- **Queue panel** at the right: x 1502–1902 (**401 wide**), bg `#0F0F0F`, y about 48–1016, radius about 6. The header reads "2 items - 47m" with sort, repeat, shuffle, −, + icons. Rows show an orange ▶ on the current item, otherwise the "=" drag handle and a duration. The bar's queue icon is orange while it is open.
- **Drag and drop** (`11m45.76s`): dragging a library row shows a ghost (thumbnail + name) under the cursor, and dropping into the queue panel appends it. The drop indicator is not visible; infer a 2px orange insertion line.

### INTERIM (her intermediate library styling, superseded)
`10m21.06s` (nav "Videos / Music / Network" with the cone and ⋯) and `10m27.06s`, `10m43.49s`–`10m57.24s` show a lighter content background (`#292929`) and dark header. The final frames use `#0F0F0F` content with a `#141414` nav panel.

### OLD (critiqued, do not copy)
`09m35.39s`–`09m44.64s` (VLC 3 media library and file dialog), `09m50.06s`–`10m12.49s` (VLC 4 Home / Video / Music / Browse / Discover with the Wi-Fi icon, Folders grid, back button), `10m13.27s` and `10m18.76s` (VLC 3 playlist sidebar), `10m30.32s`–`10m40.09s` (VLC 3 view-mode icon cycling and right-click-only Sort by). `11m00.39s`–`11m24.61s` show rejected top-bar ideas: a back arrow, a home icon, and a "library" icon (play-in-square with lines, `11m12.39s`), shown and dismissed. `11m14.12s` is VLC 3.

**Best reference frames:**
- `08-media-library/10m57.64s.jpg`: full library grid, native.
- `11m48.27s.jpg`: list plus mini player.
- `11m54.27s.jpg`: mini player expanded with the queue.
- `11m56.96s.jpg`: compact library plus queue, native, final.
- `11m45.76s.jpg`: drag to queue.
- `10m49.49s.jpg`: sort options.
- `10m55.49s.jpg`: more menu.
- `09m30.06s.jpg`: queue, native.

**Open questions:**
- Detail view (the third view mode) is not shown.
- The search-results state is not shown.
- Nav-item hover and active backgrounds are not shown (only the filled icon marks active).
- Thumbnail hover (play overlay?) is not shown.
- Breadcrumb overflow ("…") behavior is implied in compact mode only.
- The compact panel width may be resizable; this is not shown.
- What the sidebar-toggle icon does vs the folder chip: both appear to toggle the compact library. Treat the folder chip as "open library at the current folder" and the sidebar icon as "toggle compact library".
- The Network and Playlists categories, Home, Recent, and Pins are covered in later sections (part 2).
- Thumbnail generation is assumed to take a frame from the video.

---

## Appendix A — Measured native layout cheat-sheet (1920x1080)

```
Top bar (y 0–37, #181818)
  cone 13–31 | ⋯ 55–69 | [sidebar 91–109] | divider 126 | [folder 143–161 + "S01" 172–192]
  title centered (~14px #7C7C7C)
  — 1784–1797 | □ 1820–1833 | ⛶ 1856–1869 | ✕ 1893–1904

Video canvas: x 6–1912, y 38–1027, #000, radius ~4

Bottom bar (y 1028–1079, #171717)
  ⏮ 27–37 | ▶ 54–109 (55x29, r≈4.5) | ⏭ 128–137 | 00:00:00 176–235
  | seek 250–1492 (28h, handle 8x25) | 00:25:40 1508–1570
  | 🔈 1601–1620 | cone 1631–1718 | audio 1744–1761 | subs 1784–1805 | gear 1829–1846 | queue 1879–1896

Right floating panel (popover / sidebar / queue): x ~1502–1902 (≈400w), 10–12px from right, r≈6–8
```

## Appendix B — State summary

| Control | Default | Hover (inferred unless noted) | Active/open | Notes |
|---|---|---|---|---|
| Play button | paused: orange bg plus dark ▶; playing: gray `#5E5E5E` bg plus dark ⏸ | slight lighten | — | measured states |
| Bar icons | `#888` | `#B0B0B0` | orange; subtitles and gear become filled orange | active measured |
| Tabs | `#606060` | `#808080` | orange icon, light label, 2px orange underline | measured |
| List or menu row | transparent | `#1C1C1C`–`#1E1E1E` | selected: orange ✓ | sort menu selected bg measured |
| Mapping row (subtitle dialog) | transparent | `#000` bg plus ⇆ swap icon | — | measured |
| Library item | `#898989` | — | now playing: orange text plus ▶ overlay; watched: `#626262` plus orange progress line | measured |
| Primary button | `#301B00` bg, orange text | — | — | Save |
| Secondary button | `#181818` bg, `#888` text | — | — | Cancel |
| Toggle | OFF: gray knob left, "OFF" | — | ON: not shown | |
| Segmented | `#151515` / `#656565` | — | `#301B00` / orange text | measured |
