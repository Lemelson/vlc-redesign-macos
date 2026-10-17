# VLC Redesign (Juxtopposed): UI spec, part 2 (video sections 09–16)

Source: keyframes in `../reference/video/frames/09-music` … `16-final-showcase` (1920×1080 JPEG), plus `../reference/video/transcript.txt`.
Frame paths below are relative to `../reference/video/frames/`.

## Conventions and caveats (read first)

- **"Native" frames** show the app window filling exactly 1920×1080: title bar y=0–37 and control bar y≈1028–1080. Pixel measurements from these are 1:1. Many other frames are **camera-zoomed**, and their sizes have been divided by the zoom factor (noted per item). Every px value is an estimate (±2 px at native, ±10% at zoomed) unless it says "Figma".
- **Color sampling.** H.264 compression darkens and desaturates thin strokes and text, so the sampled hex is listed next to the nearest **Figma paint-style token**. The tokens come from `research/figma/palette/tokens.json` / `research/figma/renders/styles.txt`, which hold the designer's own Figma file. Build with the token values; the sampled values only confirm which token is used where.
  - Example: the play button samples as `#D16204`/`#CB610D`, which is token `Dark/Accent/Main #D37918`. The toggle knob samples as `#A54E01`, which is closest to `Dark/Accent/Dim #AB6314`.
- **Font.** The Figma file uses **Inter** (3187 text nodes; DM Mono in 9 places, likely keycaps or hex fields). Sizes: 14 px dominant, 16 px for headings, 12 px for small text, plus 15/20/24/32. Weights are mostly 400, with 500/600 for headings and buttons. Frame text matches Inter at these sizes.
- **Figma renders.** These are 2× PNGs in `research/figma/renders/`. Several screens that appear only briefly or partially in the video exist there as clean renders. They are cited as **[Figma: name.png]**, and anything taken only from Figma is labeled that way.
- **OLD vs NEW.** The video intercuts old VLC 3.x Qt UI (grey Fusion widgets, cone-icon tab bars, "Simple/All" prefs). Those frames are listed as OLD and are **not** part of the spec.

### Token quick-reference (Figma, Dark theme)

| Token | Hex | Observed usage in these sections |
|---|---|---|
| FG/1 | #EAEAEA | selected sidebar label, dialog headings, keycap text |
| FG/2 | #C6C6C6 | section headings in settings, selected library row label |
| FG/A1 | #969696 | primary row labels, menu items, titles (samples #949494–#9F9F9F) |
| FG/A2 | #8F8F8F | icons (monochrome set) |
| FG/A3 | #6B6B6B | secondary text: item counts, shortcut hints, artist lines, helper text |
| FG/A4 | #404040 | placeholders, disabled text (samples #383838–#434343) |
| Accent/Main | #D37918 | play button, active icons, slider thumb, toggle ON knob, primary button |
| Accent/Bright | #FC9729 | hover/pressed accent (estimate; not clearly visible) |
| Accent/Dim | #AB6314 | toggle knob / pressed button (sampled #A54E01, #874302 on hovered "Continue Watching") |
| BG/Accent Bright | #371F06 | slider filled track, selected segment bg, ON-label cell, enabled "Save" bg (samples #301B00–#3F2A15) |
| BG/Accent Dark | #1A1611 | accent-tinted dark surface (selected swatch frame, sampled #342000 is lighter, so estimate) |
| BG/A1 | #222222 | dropdown popups, context menus (Figma Profiles render) |
| BG/A2 | #1F1F1F | |
| BG/A3 | #1B1B1B | selected sidebar row, hover row, keycap face, folder tiles |
| BG/A4 | #191919 | |
| BG/A5 | #151515 | search field, small "+" button bg |
| BG/B1 | #0E0E0E | library panel, settings content pane, dialog body (samples #0D0D0D–#101010) |
| BG/B2 | #090909 | dialog header bar, text inputs, unfilled slider track, chapter/queue tab header |
| BG/B2 Transparent | #000 @ 80% | likely modal scrim |
| Divider/Bright | #373737 | |
| Divider/Dim | #222222 | header dividers in library/dialogs (samples #151515–#1A1A1A) |
| Effect "bg blur + shadow" | blur 50, shadow #000 46% y8 blur15 | menus/dialogs |

Window chrome measured in native frames (shared with part 1): title bar `#161616`–`#181818`, 38 px tall. The left nav rail (`#161616`/`#171717`) is 47 px wide (x 0–46). The video area is `#000` and inset 7 px from the window edges. The control bar is ~52 px tall (`#161616`–`#181818`).

---

## 09 Music

**Reasoning (transcript 11:58–12:20).** Music lives in the same compact library sidebar as video. The Music category is subdivided into Songs, Albums, Artists, Genres, so a user can listen to a whole folder back to back. A playing song looks completely different from a video: a **massive cover art** centered over a blurred, enlarged version of the art. The **waveform seek bar** is available and shown here.

### Screens

**A. Music root (compact library panel)**: `09-music/12m12.39s.jpg` (zoomed ~2.8×).
- The panel header row has back arrow ←, forward arrow → (dimmed when unavailable), title "Music" (FG/A1, ~16 px), then on the right "⋯" (more) and "open in full window" (square-with-arrow ↗ icon).
- The second row has "4 items" (FG/A3, 14 px) on the left. On the right are three icon buttons: Sort (↓↑), View mode (list icon with bullets), and Search (magnifier).
- A 1 px divider (Divider/Dim) follows, then the list rows:
  - "+ Add" (plus icon; label FG/A3, dimmer than the item rows).
  - "♪ Songs" (single note).
  - "Albums" (square-with-note, top line).
  - "Artists" (person + note).
  - "Genres" (speaker icon).
- Rows: icon ~24 px at x+20, label at x+60, row pitch ≈42 px native (derived from 125 px at 2.8×).
- The rail's Music icon is active: a **solid orange rounded-square folder** with a dark note glyph (filled variant of the folder-note icon). Inactive rail icons are outline FG/A2.

**B. Folder view inside Music ("Songs ▸ My Songs" / "… ▸ juxtopposed")**: `09-music/12m06.39s.jpg` (zoomed), `09-music/12m18.39s.jpg` (**native**).
- Breadcrumb: "… ▸ Songs ▸ My Songs". The separators are small filled right-pointing triangles ▸ (FG/A4). The leading "…" collapses ancestor levels, and the last crumb is brightest.
- "3 items". Rows: "+ Add", then file rows with a **32×32 thumbnail** (album art; generic art is a green double-note on `#223522`), then "title - artist" (FG/A3/A1 ~14 px).
- **Native measurements (12m18.39):**
  - Rail x 0–46 (`#161616`); library panel x 48–425 (**378 px wide**), bg `#0D0D0D` (BG/B1), starting just under the title bar (y 38).
  - Header row baseline y≈70; count row y≈115; divider y 143–144.
  - First row "+ Add" y≈180. File rows at y 222 / 264 / 306 (**pitch 42 px**). Thumbs at x 67–98 (32 px), label x≈109.
  - Header icons: ⋯ at x≈357, ↗ at x≈393. Sort / View / Search at x≈320 / 356 / 393.
- The title-bar breadcrumb shows a folder icon + "My Songs" (current folder name; this is the "library opener" from part 1). The window title center shows "untangle".

**C. Music now-playing (audio file playing in player)**: `09-music/12m18.39s.jpg` (native).
- Video area: blurred, scaled-up cover art fills the whole area, darkened heavily. A **centered square cover art** sits at x 590–1330, y 112–851 (**~740×740**, radius ≈16 px estimate).
- Below the art: "untangle - juxtopposed", centered at y≈940, ~24 px, FG/A1 (`#505050` sampled through the dim overlay, so the color is uncertain).
- The control bar shows the **waveform seek bar** (vertical bars). The played portion is orange (Accent/Main) and the unplayed portion is gray `#383838`-ish bars, between times "00:00:10" and "00:01:40".
- The ±15 s skip buttons are visible here (part 1 covers the control bar).

### Open questions (09)
- Albums / Artists / Genres sub-pages (grid of album art?) are not shown.
- No music-specific grid or detail view is shown.
- [Figma: Player - Music.png, Player - Music-1.png] exist and should be used for exact art size and blur.

---

## 10 Network streams and open dialogs

**Reasoning (12:20–13:15).**
- Network streams form a library category that ships with some default saved streams plus an "Add Network Stream" button.
- The old "Open Media" dialog is an "all-in-one media factory": File/Disc/Network/Capture tabs, with Play/Enqueue/Stream/Convert behind a split button. The designer calls it too complex. Enqueue is pointless when a queue exists, and Stream/Convert are important enough to be separate, not hidden.
- The "⋯" app menu already lists Open File, Open Directory, Network Stream, Capture Device, Clipboard, Recent, Convert, Stream, so **each becomes its own small dialog**.
- Demo: pasting the iptv-org GitHub m3u URL turns it into an automatic playlist of channels.

OLD frames, not to build: `12m33.04`–`12m52.37` (Qt "Open Media" dialog), `13m12.87`–`13m14.97` and `11/13m15.01`–`13m16.24` (GitHub IPTV page + macOS VLC "Open Source" dialog).

### A. Network category (compact panel)
Frames: `10-network-streams-open-dialogs/12m28.36s.jpg` (zoomed ~3×), `11-playlists-pins-recent-home/13m18.66s.jpg` (zoomed ~1.9×).
- Title "Network", "2 items" (the designer forgot to update the count after adding "Index", so show the real count).
- Rows: "+ Add Network Stream", then saved streams, each with a **broadcast icon ((•))**: "Index" (newly added m3u), "Podcasts", "Radio".
- The rail's Network icon is active: the broadcast glyph is drawn in **orange stroke** (no filled tile, because the glyph has no enclosing shape).
- Hover: pointer cursor over the "Add Network Stream" row. No hover background is visible.

### B. "⋯" app menu (the main menu that replaces the menubar)
Frames: before cleanup `10-…/13m02.59s.jpg`, after cleanup `10-…/13m08.59s.jpg` (both zoomed ~1.28× relative to native). Later versions: `14-settings-hotkeys/16m02.76s.jpg` (adds Keyboard Shortcuts) and `15-…/19m29.39s.jpg` / `19m35.39s.jpg` (adds Profile). **Final version: [Figma: Profiles.png]**.

- **Placement.** Drops from the title-bar "⋯" button. Left edge ≈34 px from the window edge, top ≈ y 47 (9 px under the title bar). **Width ≈375 px** (Figma: 750/2). **Row pitch 48 px** (Figma: 96/2; frame 62/1.28). Corner radius ≈12 px. bg BG/A1 `#222222` per Figma (frames sample `#161616`–`#1C1C1C` because of video dimming). Drop shadow from "bg blur + shadow".
- **Row anatomy.**
  - Two-tone icon (~22–24 px), 20 px from the menu's left edge. These are the "menu icon set": gray outline FG/A2 with **orange accent parts**. For example, Open File has an orange corner, Convert has an orange lower arrow, Customize has an orange brush tip, Settings has an orange gear center, and the keyboard has an orange space bar.
  - Label at x≈62 px: FG/A1, 14–15 px.
  - Shortcut right-aligned 20 px from the right edge: FG/A3, formatted "Ctrl + O" with spaces around "+".
  - Submenu items show a chevron ›.
  - A 1 px divider (Divider/Dim) separates groups.
- **Hover row:** full-width rounded rect (radius ≈8) inset ~6 px, bg ≈`#1C1C1C` against a menu sampled at `#161616` (in Figma terms BG/A2–A3 on BG/A1). See `14-…/16m02.76s.jpg` and the "Profile (Movies)" row in `19m35.39s.jpg`.
- **Final item list (Figma Profiles.png, matches 19m29/19m35):**
  1. Open File(s), Ctrl + O
  2. Open Folder, Ctrl + F (named "Open Folder(s)" in 13m08)
  3. Open Network Stream, Ctrl + N
  4. Open Disc, Ctrl + D
  5. Open Capture Device, Ctrl + C
  6. Convert, Ctrl + R
  7. Open Recent ›
  8. Divider
  9. Profile (Movies) › (current profile in parentheses)
  10. Keyboard Shortcuts
  11. Customize Player
  12. Settings, Ctrl + P
  13. About VLC, Shift + F1
- **Intermediate versions in the video:**
  - 13m08 (after cleanup): Open File(s), Open Folder(s), Open Disc, Open Network Stream, Open Capture Device, Open from Clipboard (Ctrl + V), Convert, Stream (Ctrl + S, upload icon), Open Recent ›, divider, Customize Player, Plugins & Extensions ›, Settings, About VLC.
  - 13m02 (before cleanup): Open File, Open Multiple Files (Ctrl + Shift + O), Open Directory, Open Disc, Open Network Stream, Open Capture Device, Open Location from Clipboard, Open Recent ›, Save Playlist to File (Ctrl + Y), Convert / Save, Stream, Customize Player, Plugins & Extensions ›, Settings, About VLC.
  - 16m02: … Convert, Stream, Open Recent ›, Keyboard Shortcuts (hovered), Customize Player, Plugins & Extensions ›, Settings, About VLC.
- **Open question:** the final list drops "Open from Clipboard", "Stream" and "Plugins & Extensions" (Extensions moved to Settings). Confirm whether Stream and Clipboard should stay. Implement the Figma list and treat Stream/Clipboard as optional.

### C. Open Network Stream dialog (NEW)
Frame: `11-playlists-pins-recent-home/13m17.76s.jpg` (zoomed so the dialog fills ~1700 px). **[Figma: Open network stream.png] gives a native size of ≈1050×633** (2156×1322 @2× minus shadow padding).
- **Header bar:** bg BG/B2 `#090909`, ~40 px native. Title "Open Network Stream" on the left (FG/A1, 14 px) and close ✕ on the right (FG/A1). A ~1 px darker line separates it from the body.
- **Body:** bg `#161616` sampled (≈BG/A5/A4; the Figma render should decide).
  - Section 1:
    - Heading "Network URL" (FG/1-ish `#DFDFDF`, 16 px).
    - Helper "You can enter multiple links to load." (FG/A3, 14 px).
    - **Multi-line textarea**, full width, ~150 px tall native, bg BG/B2 `#090909`, radius ≈4. Placeholder "e.g., https://www.example.com/stream.avi" in FG/A4.
  - Divider (Divider/Dim).
  - Section 2:
    - Heading "Playlist Name" + "(optional)" in FG/A3.
    - Helper "The playlist will be saved and displayed with this title."
    - Single-line input ~26–32 px tall, bg BG/B2, placeholder "e.g., Favorite TV Channels".
- **Footer:**
  - "Cancel" button bottom-left: bg `#181818`, text FG/A1 `#969696`, weight 500–600, ~80×34 native.
  - "Save" bottom-right: **disabled** state, bg `#1B1B1B`, text `#505050`. Enabled Save is orange text on BG/Accent Bright (see 15 Customize "Save").
- **Behavior:** Save adds the stream, or the m3u expanded into an automatic playlist, to the Network category ("Index" in 13m18.66).

### Open questions (10)
- The other separate dialogs (Open Disc, Open Capture Device, Convert, Stream, Open from Clipboard) are **not shown**. Reuse the same dialog chrome. No Figma render is named for them.
- Open File(s) and Open Folder presumably use the native OS file picker.

---

## 11 Playlists, pins, recent, home

**Reasoning (13:15–14:00).**
- Creating a playlist should be simple: click Create, name it, select files. Alternatively, right-click a file anywhere and choose "add to playlist".
- The rail is "long and empty", so it gains three things: **pins** (favorite playlists or folders), a **Recent** tab, and a **Home** page with the latest files, playlists and streams.
- Home replaces the old blank-cone start screen, so reopening VLC lands on a full library that continues where you left off.

### A. Playlists category (compact)
Frames: `11-…/13m24.66s.jpg` (zoomed ~1.9×), `16-final-showcase/20m20.84s.jpg` (zoomed).
- Title "Playlists", "2 items". Rows: "+ Create playlist", then "Cool Songs" and "Anime to Watch", each with the **playlist icon** (three lines + play triangle).
- The rail's Playlists icon is active in orange stroke.

### B. New Playlist dialog
Frame: `11-…/13m26.14s.jpg` (zoomed). **[Figma: new playlist.png] gives ≈715×590 native** (1486×1238 @2× minus shadow).
- **Header:** BG/B2, title "New Playlist", ✕.
- **Section "Playlist Details":**
  - Heading (FG/1-ish) and helper "The playlist will be saved and displayed with this title and thumbnail."
  - Text input with placeholder "e.g., Favorite Videos", ~60% width.
  - On the right, a **square thumbnail picker** (~95×95 native) with bg BG/B2 and a centered small "+" button (bg BG/A5 `#151515`, radius 4).
- Divider.
- **Section "Select Files":**
  - Helper "These files will be added to the playlist."
  - **Drop zone:** full width, ~160 px tall native, bg BG/B2, **dashed 1 px border** (`#282828` sampled; dash ≈4/4), radius ≈4.
  - Centered text "Drag files into the box or click here to select files." (FG/A4) and a centered "+" button (~75×26, bg BG/A5).
- **Footer:** Cancel (left) and Save (right, disabled until valid). Same styles as the Network dialog.

### C. Rail with pins
Frames: `11-…/13m41.17s.jpg` (zoomed ~2.4×), `11-…/13m47.17s.jpg`.
- **Final rail order, top to bottom:**
  1. **Home** (house icon)
  2. Videos (folder + play)
  3. Music (folder + note)
  4. Network ((•))
  5. Playlists (lines + ▶)
  6. **Recent** (clock with counter-clockwise arrow)
  7. **Pins**: a pinned video/playlist appears as its **thumbnail image** in a rounded square (~32 px native, radius ≈6); a pinned folder appears as a folder outline icon
  8. **"+"** (add pin) at the bottom of the list
- Rail item pitch ≈46–48 px native (113 px at 2.4×). Active Home icon: **filled orange house** with a dark door.
- Pins accept any playlist, folder or file per the transcript.

### D. Home (compact panel)
Frame: `11-…/13m47.17s.jpg` (zoomed ~2.4×).
- Title "Home", "110 items". Sections with headers in FG/A1, ~16 px: **"Continue Watching ›"** and **"Listen Again ›"**. The chevron sits right-aligned in the compact panel (it is inline after the text in full view).
- Continue Watching rows show a thumbnail (~32 px) with a **thin orange progress bar** (Accent/Main, ~2 px tall, ~6 px long, i.e. the percent watched) along the thumbnail's bottom-left, followed by the filename.

### E. Home (full-window library)
Frame: `11-…/13m57.34s.jpg` (**native**). **This is the reference for full library mode.**
- **Title bar:** logo + ⋯ on the left (no sidebar toggle or folder crumb in full library mode), centered title "VLC Media Player" (FG/A1 `#8E8E8E`, 14 px), window controls on the right.
- **Library sidebar (not the icon rail):**
  - Floating card x 5–206 (**202 px**), y 46 → bottom, bg `#171717`–`#181818`, radius ≈8. The window bg around it is `#0F0F0F`.
  - Rows (icon 18–20 px + label 14 px): **Home** (y 75), Videos (121), Music (167), Network (213), Playlists (259), Recent (305), **+ Add item** (351). **Row pitch 46 px.**
  - Selected row: orange filled icon, label FG/2 `#C6C6C6`, very subtle bg `#191919`. Unselected labels are FG/A1 `#8A8A8A`.
  - Icon x≈36, label x≈59.
- **Content header (y≈75):**
  - ← at x 246 and → at x 283 (→ dimmed), breadcrumb "Home" at x 305 (FG/A1).
  - Right side: "110 items" (FG/A3, 12–13 px) ending x≈1424; Sort icon x 1456; view-mode **grid icon** x 1500.
  - **Search field** x 1533–1858 (~325×32): bg `#141414` (BG/A5), magnifier icon, placeholder "Search" in FG/A4.
  - "⋯" at x 1890.
  - Divider at y≈108.
- **Section "Continue Watching ›"** (heading at y 159, ~18 px, FG/A1 `#9F9F9F`, chevron inline after the text, 8 px gap):
  - Cards **317×178 (16:9)** at x 235, 572, 909, 1246 (**gap 20 px**), top y 191, radius ≈8.
  - Orange progress bar at the bottom edge of each thumbnail, from the left; its length is the watched fraction.
  - Filename below at y 398 (14 px, FG/A1).
  - Hover shows a pointer cursor; no hover overlay is captured.
- **Section "Listen Again ›"** (y 497): square cards **200×200** at x 235, 456, 677 (gap 21), radius ≈6.
  - Title (14 px FG/A1) at y 760, then artist "juxtopposed" (FG/A3 `#676767`) at y 789.
  - The generic music art is a green pixel double-note on `#2A372D`.
- **Section "Frequently Visited Folders ›"** (y 887): tiles **200 px wide** at the same x positions, bg BG/A3 `#1B1B1B`, radius ≈6, with a centered folder outline icon (~36 px, FG/A2).
- Left content margin: 235 − 207 = 28 px from the sidebar.

### F. Full-window folder grid (final showcase)
Frame: `16-final-showcase/20m14.84s.jpg` (window scaled ~0.78×).
- Breadcrumb "Videos ▸ Shows ▸ The Wand ▸ **S01**" (last crumb bold/bright). "15 items", sort, grid icon, search, ⋯.
- **5-column grid** of 16:9 thumbnails (~317×178 native) with filename below.
- **Sort "unwatched first"**: E05–E15 appear first. E01–E04 come last with a **full-width orange progress bar** (fully watched) and **dimmed filename text** (FG/A3), which marks them as watched.

### G. Old start screen (OLD)
`11-…/13m49.61s.jpg` (blank cone) and the crossfade `13m51.34s.jpg`.

### Open questions (11)
- The Recent page content is not shown (presumably a list sorted by last played).
- The "Add item" flow in the full sidebar is not shown; it probably mirrors the rail's "+ add pin".
- The context menu "Add to playlist" is not shown here. Check [Figma: file context menu.png, playlist context menu.png, folder context menu.png].

---

## 12 Continue-watching prompt

**Reasoning (14:00–14:12).** Old VLC shows "Do you want to restart the playback where left off?" as a thin bar at the top-left with a "Continue" button far away at the top-right, and it disappears after a few seconds. The designer barely noticed it and wants it **near the playback controls, centered**, where the eye already is.

- **OLD (as rendered inside the new skin):** `11-…/13m57.81s.jpg` and `12-continue-watching/14m03.81s.jpg`. A strip under the title bar with a "?" orange circle, the question text, and "Continue" + "X" on the far right. Do not build.
- **NEW toast:** `12-continue-watching/14m09.81s.jpg` (**native**); crop at `scratchpad/crops2/toast.png`.
  - **Position:** horizontally centered (x 686–1234, **548 px wide**), y 952–1002 (**50 px tall**), bottom edge **~25 px above the control bar** (which starts at y 1027).
  - **Container:** bg `#101010`–`#141414` (≈BG/B1, maybe the 95% transparent variant), **radius ≈10 px**, no visible border.
  - **Text:** "You already watched till " (FG/A1 `#979797`, 14 px) + **"00:00:02"** (bold 600, FG/2). Left padding 20 px.
  - **Primary button "Continue Watching":** x 1024–1172 (**148×32**), radius ≈5. bg is orange: `#874302` sampled while **hovered/pressed**, so the normal state is presumably Accent/Main `#D37918` and hover is Accent/Dim. Label is **dark (#161616 / FG/B1), weight 600, 14 px**.
  - **Close ✕:** a ~32×32 square button right after the primary (gap ~8), bg `#171717` (BG/A4), glyph FG/A3, radius ≈5. Right padding ≈10.
  - **Seek bar hint at the same time:** the playhead is at 0 (orange pill at x≈255). The span from 0 to the resume point (x 262–299) is tinted dark orange `#150900`, and a **faint resume marker** sits at x 300–307 (`#322212`). In other words, the bar previews where "continue" will jump.
  - **Behavior (implied):** the toast appears when opening a partially watched file and auto-dismisses after ~5 s (the transcript says "I have like five seconds to respond"). Continue jumps to the saved time; ✕ dismisses.
- Frames 12m14.xx–14m57 are the sponsor segment (blurred button collages). Ignore them.

### Open questions (12)
- The non-hover button color isn't captured; use Accent/Main.
- Enter/exit animation, timeout length and a countdown indicator are not shown.

---

## 13 Bookmarks, chapters, OSD

**Reasoning (14:45–15:30).**
- Old bookmarks live behind Playback ▸ Custom Bookmarks ▸ Manage, which opens an "Edit Bookmarks" table ("This is an Excel").
- Ctrl+B should create a bookmark instantly, so the bookmark timeline moves into the **right sidebar**, and movie **chapters** fit there too.
- When a shortcut is pressed by accident, the OSD message should also show **which key was pressed**, not just the action.

OLD frames: `13-…/14m57.42s.jpg` (old context menu), `14m58.61s.jpg`, `15m02.14s.jpg` (Edit Bookmarks dialog), `15m09.09s.jpg`. `15m03.09s.jpg` is just "CTRL"/"B" editorial keycaps, not UI.

### A. Right sidebar: Queue / Bookmarks / Chapters
Frames: `13-…/15m15.09s.jpg` (zoomed ~2.6×), `13-…/15m16.67s.jpg` (**native**), Queue tab in `16-final-showcase/20m21.37s.jpg` (zoomed ~3.5×).
- **Panel (native 15m16.67):**
  - Floating over the video on the right: x **1502–1903 (~400 px wide)**, y 48 → 1018. That leaves 10 px under the title bar, ~10 px from the right window edge and ~10 px above the control bar.
  - bg ≈`#0B0B0B`–`#0E0E0E` (BG/B1, possibly B1 Transparent 95%), radius ≈10.
  - It opens when the control-bar **queue/list button** (rightmost, x≈1888) is toggled, and that button turns **orange** while the panel is open.
- **Tab header:** y 48–98 (~50 px), bg BG/B2 `#090909`. Three equal tabs, each with a 16 px icon + label (14 px):
  - "Queue" (stacked-lines icon)
  - "Bookmarks" (bookmark ribbon)
  - "Chapters" (▸☰, a play triangle + list; the triangle is orange when active)
  - Active tab label FG/1-ish `#7F7F7F`→brighter, inactive FG/A3 `#5B5B5B`–`#6B6B6B`.
  - **Active underline:** 2 px **orange** (Accent/Main) spanning the tab width (x 1776–1888) at y 97–98.
- **Chapters list:** rows at y 137, 181, 225, 269, 313 (**pitch 44 px**).
  - Number in **orange** (Accent/Main, 14 px) at x≈1530.
  - Chapter title FG/A1 at x≈1570.
  - Timestamp right-aligned at x≈1879, FG/A3, "00:02:15" format.
  - Content: 1 Winter 00:02:15 · 2 Spring 00:29:45 · 3 Summer 00:51:30 · 4 Fall 01:13:50 · 5 Winter (5 Years Later) 01:44:10.
- **Queue tab** (20m21.37, zoomed):
  - Header row: "1 item - 23m" (count + total duration, FG/A3, 14 px). On the right are icon buttons: Sort ↓↑, **Repeat** ⟲, **Shuffle** ⤨, **Remove** −, **Add** +.
  - Current item row: orange outline ▷ play icon + filename in **orange** + duration "23:06" right-aligned (FG/A3).
  - **Drag-and-drop:** a file being dragged from the library ("The_Wand_S01E06.mp4") shows a **"⋯" three-dot insertion placeholder** where it will drop.
- **Bookmarks tab:** **not shown in any frame.** Presumably a list of bookmark rows (name + time) with an add button, created via Ctrl+B. Check Figma for a render; none is obviously named.

### B. OSD message with pressed key
Frame: `14-settings-hotkeys/15m27.09s.jpg` (zoomed; the video is cropped to 2.35:1).
- Two left-aligned lines in the top-right area of the video (local key frame15m27.09; corrected after independent audit):
  - Action: "**Crop: 2.35:1**" (large, white, VLC's classic OSD font with soft shadow).
  - New line below: "**Pressed C**" (same color, slightly smaller).
- Native size is unknown (the classic OSD is ~5% of video height).
- Settings → Subtitles → "On-Screen Messages" controls this: "Show feedback for shortcuts" toggle, "Show feedback for" slider 0.5–5 s (see §14).

### C. Seek bar observation
`15m16.67`/`15m21.09` (native): when the played portion is long, the filled part of the thick seek bar is a dark orange `#331900`–`#3A1D00` (BG/Accent Bright), the playhead is a vertical orange pill (Accent/Main, ~8×28), and the remainder is `#000`/BG/B2.

### Open questions (13)
- Bookmarks tab layout, the Ctrl+B creation feedback, and chapter markers on the seek bar are all unshown.
- Whether the sidebar pushes or overlays the video: it **overlays** in every frame.

---

## 14 Settings and hotkeys

**Reasoning (15:30–18:45).**
- Old settings are an "airplane cockpit": Simple vs All modes, duplicated settings, inconsistent wording, single-setting subcategories, tooltips hidden behind hover delay, and numeric codes such as subtitle fuzziness 0–4.
- Hotkeys come out into **their own dialog** with a fresh look and a **direct menu entry** ("Keyboard Shortcuts").
- Each settings category shows **basic settings first, then a collapsible "Advanced Options"** section at the bottom.
- Every setting gets an **ⓘ info icon** instead of a hover tooltip. Numbers become human words in dropdowns: "Off / Any title / Contains title / Title with extra characters / Exact title match".
- There are 12 categories:
  - General: theme light/dark/system + **accent color**
  - Interface
  - Privacy
  - Controls
  - Playback
  - Video
  - Audio
  - Subtitles (incl. OSD)
  - Library
  - Network
  - Performance
  - Recording (streaming/casting)
  - Extensions (plugins move to advanced)

OLD frames (do not build): `15m29.66`–`15m56.76`, `16m03.31`–`17m24.96` (Qt Simple/Advanced Preferences, Toolbars, the designer's settings spreadsheet `16m42.84`, filters), `18m28.14`–`18m41.34` (old Plugins and extensions dialog).

### A. Settings window: chrome
Reference: `14-…/17m40.87s.jpg` (**native**, centered over the player); zoomed ~1.18× copies at `17m50.07`–`18m26.07`. **[Figma: Settings - *.png] at 2× gives 1078×895 including shadow, so ≈1050×867.**
- **Modal** centered in the window: x 435–1485 (**1050 px**), y 94–961 (**867 px**). Outer radius ≈10.
  - Outer frame color BG/B1 `#0E0E0E` with a big soft shadow ("bg blur + shadow" effect).
  - The player behind it is visibly lightened/greyed (`#1D1D1D`), probably a scrim, though the control bar keeps full color. Treat it as BG/B2 Transparent or similar.
- **Header strip** y 94–143 (**50 px**), bg BG/B2 `#090909`, spanning the full width:
  - **Search field** in the sidebar column: x 443–641 (198×34), bg BG/A5 `#151515`, radius ≈4, magnifier icon FG/A3 at x 461, placeholder "Search" in FG/A4.
  - Page title at x 675: e.g. "Global Settings", FG/A1 `#999`, 16 px.
  - Close ✕ at x 1455 (FG/A1).
- **Sidebar card:** x 443–641 (**198 px**), y 152 → 952, bg `#171717` (between BG/A4 and BG/A5), radius ≈6, inset 8 px from the outer frame.
  - **Group labels** (FG/A3 `#636363`, 14 px): "App" (y 175), "Media" (408), "System" (690).
  - **Items** (icon 18–20 px at x 468, label 14 px FG/A1 `#8D8D8D` at x 493), **pitch 48 px**:
    - App: General (219), Interface (267), Privacy (315), Controls (363)
    - Media: Playback (453), Video (501), Audio (549), Subtitles (597), Library (645)
    - System: Network (735), Performance (783), Recording (831), Extensions (879)
  - **Selected item:** row bg BG/A3 `#1B1B1B` from x 448 to 636 (h 40, radius ≈6). Label FG/1 `#EBEBEB`. The icon switches to the **filled orange variant**: General = orange sliders, Privacy = filled orange shield, Controls = filled orange keyboard, Playback = filled orange ▶, Video = filled orange clapper, Audio = orange waveform, Subtitles = filled orange caption box, Library = filled orange folder, Network = orange ((•)), Performance = orange sliders, Recording = orange ◉, Extensions = filled orange puzzle piece.
  - **Icons:** General = 3 vertical sliders; Interface = cursor arrow; Privacy = shield; Controls = keyboard; Playback = ▷; Video = clapper/calendar-like box; Audio = waveform bars; Subtitles = caption box; Library = folder; Network = ((•)); **Performance = the same sliders icon as General** (the designer reused it); Recording = ◉ in a ring; Extensions = puzzle piece.
- **Content pane:** x 644–1480, bg `#0F0F0F`/`#101010` (BG/B1), scrolls vertically with no visible scrollbar.
  - Left padding 31 px (labels at x 675). Controls are right-aligned to x 1460.
  - **Section heading:** FG/2 `#D6D6D6`, 16 px, weight 500 (e.g. "Appearance" at y 183).
  - **Rows:** label FG/A1 `#878787`, 14 px at x 675. The optional **ⓘ icon** (14 px circle-i, FG/A4 `#393939`) sits ~12 px after the label.
  - **Row pitch ≈44–46 px.** Gap from section heading to first row ≈43. Gap between sections ≈60.
- **Controls (right column, width 318 px: x 1142–1460):**
  - **Dropdown:** 318×32, bg `#171717` (BG/A4–A5), radius ≈4. Value text FG/A1 14 px at +15 px. Chevron ∨ at the right (FG/A1).
  - **Dropdown open state** (`17m30.96s.jpg`, zoomed ~2.2×): the field stays, with the popup list directly below (4 px gap), same width, bg `#252525`/BG/A1, radius ≈6. Options are 14 px FG/A1 with **row pitch ≈58 px at 2.2× (≈26–28 px native)**. The selected option has a row bg `#2B2B2B` (BG/A1+, rounded, inset) and an **orange ✓** at the right. Popup shadow per effect style.
  - **Segmented control (Theme):** three equal segments (~104×32, 3 px gaps): "Dark", "Light", "System". Selected = bg BG/Accent Bright `#371F06` (sampled `#271A09`–`#301B00`) with orange text (Accent/Main). Unselected = bg `#161616`/BG/A5 with FG/A3 text `#5F5F5F`. Radius ≈4. Also used for "Relative / Pixels" in Subtitles.
  - **Toggle (unique VLC style; square, not a pill):** ~64×28 total, made of two cells.
    - OFF: **gray square knob** (~26×26, `#3D3D3D`, radius ≈3) on the left, then a cell with "OFF" text (11–12 px, FG/A3 `#5D5D5D`) on bg `#141414`.
    - ON: a left cell with "**ON**" in orange text on BG/Accent Bright `#311900`/`#371F06`, then an **orange square knob on the right** (Accent/Main, sampled `#A35203`).
    - Crops: `scratchpad/crops2/toggleon.png`, `toggles.png`.
  - **Text input:** bg BG/B2 `#090909` (some sampled `#0A0A0A`), 1 px border slightly lighter (`#1C1C1C`), radius ≈4, height 34. Value FG/A1. For example, "Log file" input is 208 px wide followed by a "Browse" button.
  - **Secondary button ("Browse", "Clear", "Reset", "Rescan", "Add", "Remove", "Find more extensions", "Edit Keyboard Shortcuts"):** bg `#181818`–`#1B1B1B` (BG/A3), label **FG/A1 weight 600, 14 px** (`#919191`), radius ≈4, height 34. Width is ~100 px, or the full control width (Rescan, Edit Keyboard Shortcuts).
  - **Slider:** track ~13 px tall (16 px at 1.18×), radius = half the height.
    - Filled part BG/Accent Bright `#371F06`; unfilled BG/B2 `#090909`.
    - **Tick marks:** 1 px vertical lines, 6 px tall, lighter (`#1D1D1D` on dark; orange-ish on fill), evenly spaced (8–20 ticks).
    - **Thumb:** vertical **orange pill ~7×22** (Accent/Main) with a 1 px darker outline.
    - Scale labels below (FG/A3, 12 px): start / middle / end, e.g. "0%  50%  100%", "-5 s  0 s  +5 s".
    - Crop: `scratchpad/crops2/slider.png` (from `18m14.07s.jpg`).
  - **Color field:** an input showing hex "#000000" (DM Mono?) with a **color swatch square** (~20 px, 1 px border) at the right end.
  - **Accent color picker:** 9 square swatches (~19×19 native, radius 2, pitch ≈36): **orange `#CE6006`/`#D37918`, red `#961E1A`, olive `#7F6702`, green `#0A7919`, teal `#0A7989`, blue `#033B89`, purple `#5F18A9`, magenta `#A31773`, gray `#707070`** (sampled; desaturated by video, so read the exact values from the Figma onboarding/accent renders). The selected swatch has a ~32 px BG/Accent Dark/BG/Accent Bright square frame behind it. Frame `14-…/17m50.07s.jpg`.
  - **"Advanced Options ›" bar:** full content width (x 675–1460), height ~38, bg `#161616` (BG/A5), radius ≈4. Centered label "Advanced Options" (FG/A1 `#888`, 14 px) + chevron ›. When expanded the chevron points down ∨ and the advanced rows appear **below the bar** (`15-customization-onboarding/18m51.06s.jpg`, `14-…/18m20.07s.jpg`).
  - **Info icon ⓘ:** shows more info about the setting (the transcript says "every setting has an info icon that shows more information"). The popover style is not shown.

### B. Settings categories: every readable row
Defaults are shown where visible. ⓘ means an info icon is present.

**1. General**: page title "**Global Settings**". `14-…/17m40.87s.jpg` (native), `17m50.07s.jpg` (with Accent color), `15-…/18m51.06s.jpg` (Advanced expanded), Figma `Settings - global.png`, `-1`.
- *Appearance*: Interface language [dropdown: English] · Theme [segmented Dark/Light/System; Dark] · **Accent color** [9 swatches; orange] (only in 17m50, missing in 17m40)
- *Startup*: Show confirmation and error dialogs ⓘ [toggle OFF] · Check for updates automatically ⓘ [OFF]
- *Diagnostics*: Developer mode ⓘ [OFF] · Save a log ⓘ [ON] · Log file ⓘ [input + Browse] · Log details ⓘ [dropdown: Errors only]
- [Advanced Options]: Show minor warnings ⓘ [OFF] · Additional command line options ⓘ [input] · Log format ⓘ [dropdown: Plain text] · (more rows cut off)
- **Light theme:** the crossfade frames `14-…/17m42.54`–`17m44.01` show the same dialog in **Light** (Light segment selected, orange). Light tokens: BG/B1 `#E7E7E7`, BG/A1 `#EDEDED`, FG/A1 `#3C3C3C`. Figma `Player - Light.png` exists.

**2. Interface**: "**Interface Settings**". Not in frames; [Figma: Settings - interface.png].
- *Skin*: Use a custom skin ⓘ [ON] · Skin file ⓘ [input + Browse]
- *Window*: Play video inside main window ⓘ [ON] · Resize window to fit video ⓘ [Never] · Remember window size and position [ON] · Keep window above other windows ⓘ [OFF] · Show window decorations ⓘ [ON] · Show the file name in the title bar ⓘ [ON] · Open fullscreen on ⓘ [Current screen]
- *Playback Controls*: Start in compact mode ⓘ [OFF] · Auto-hide the controls ⓘ [In fullscreen only] · Hide after [slider 0 s / 5 s / 10s, ~0.5 s] · Show controls in fullscreen ⓘ [ON]
- *Notifications and System Tray*: (rows below the fold; see `Settings - interface-1.png`, which rendered identically, so the scrolled content is unknown)

**3. Privacy**: "**Privacy Settings**". `14-…/17m56.07s.jpg`.
- *History*: Save recently played items ⓘ [ON] · Remember the playback position ⓘ [ON] · Never remember items matching ⓘ [input] · Clear history now ⓘ [button "Clear"]
- *Network*: Fetch titles and cover art from the internet ⓘ [OFF] · Submit played tracks to last.fm ⓘ [OFF] · Last.fm username ⓘ [input] · Last.fm username ⓘ [input] (**duplicate in design; the second is likely "Last.fm password"**) · Last.fm submission URL ⓘ [input]

**4. Controls**: "**Mouse, Keyboard & Remote Controls**". [Figma: Settings - controls.png] only.
- *Keyboard Shortcuts*: Defaults [full-width button "Edit Keyboard Shortcuts"] · Reset all shortcuts [full-width button "Reset"]
- *Skip Amounts*: Very short skip [3 s] · Short skip [10 s] · Medium skip [60 s] · Long skip [300 s] (text inputs)
- *Mouse*: Single click on the video [Play / Pause] · Double click on the video [Toggle fullscreen] · Scroll wheel [Volume] · Horizontal scroll [Seek] · Reverse scroll direction [OFF]
- *Remotes*: Web remote control [OFF] · Port [input] · (more below the fold)

**5. Playback**: "**Playback Preferences**". Ghosted in `14-…/18m02.07s.jpg`; [Figma: Settings - playback.png].
- *Startup*: Continue where you left off ⓘ [Always] · Start playing as soon as a file opens ⓘ [ON] · Default playback speed [slider with labels 0.25 0.5 0.75 1 1.25 1.5 1.75 2; at 1] · Pause when another app uses audio ⓘ [ON]
- *Tracks*: Preferred video quality ⓘ [Best available] · Preferred menu language ⓘ [English] · Default audio track ⓘ [input 1] · Default subtitle track ⓘ [input 1]
- *Order*: Repeat ⓘ [Off] · Shuffle ⓘ [ON] · Stop after each item ⓘ [ON] · When playback finishes ⓘ [Stop]
- *Seeking*: Seek precisely ⓘ [ON] · (more below; see `Settings - playback-1.png`)

**6. Video**: "**Video Defaults**". `14-…/18m02.07s.jpg` (crossfade); [Figma: Settings - video.png].
- *Output*: Enable video ⓘ [ON] · Start videos in fullscreen ⓘ [OFF] · Stop the screensaver during playback ⓘ [ON] · Play video as desktop wallpaper ⓘ [OFF]
- *Picture*: Hue [slider, mid] · Brightness [slider, mid] · Contrast [slider, mid] · Saturation [slider ~1/3] · Gamma [slider near min, ticks] · Reset picture [button "Reset"]
- *Deinterlacing*: Deinterlacing ⓘ [Automatic] · Method ⓘ [Automatic]
- *Framing*: Aspect ratio ⓘ [Automatic] · Crop ⓘ [None] · (more; see `Settings - video-1.png`)

**7. Audio**: "**Audio Defaults**". `14-…/18m08.07s.jpg` (EQ open), `16-…/20m36.74s.jpg` (bottom rows); [Figma: Settings - audio.png, -1].
- *Output*: Enable audio ⓘ [ON] · Output device ⓘ [System default] · Speaker setup ⓘ [Automatic]
- *Volume*: Maximum volume [slider 100% / 200% / 300%, at 200%] · Startup volume ⓘ [two-option stacked selector: "**Remember last volume**" (selected, orange text on BG/Accent Bright) / "Always starts at: [200%]" (inline input)] · Volume step ⓘ [input 1]
- *Loudness*: Normalize loudness ⓘ [OFF] · Target level ⓘ [input 1] · Night mode ⓘ [OFF] · Replay gain ⓘ [Off] · Replay gain preamp ⓘ [input 0.0]
- *Effects*:
  - Equalizer ⓘ [OFF]
  - Equalizer preset ⓘ [None]
  - **Inline equalizer panel**: full content width, bg `#161616`, radius ≈4.
    - Header: centered toggle link "Close Equalizer ∨".
    - **11 vertical sliders**: Preamp, 60 Hz, 170 Hz, 310 Hz, 600 Hz, 1 KHz, 3 KHz, 6 KHz, 12 KHz, 14 KHz, 16 KHz.
    - Each track is ~8 px wide and ~320 px tall (native ≈270), bg BG/B2. The fill runs from the bottom in BG/Accent Bright, and the thumb is a **horizontal orange pill ~24×8**.
    - Band labels below (FG/A3, 13 px), then a **value chip** per band ("12.0 dB", "0.0 dB"; ~58×30, bg `#161616`/BG/A5, radius 4, FG/A1 12 px).
  - Two-pass ⓘ [OFF] · Spatial audio ⓘ [OFF] · Spatial audio mode ⓘ [Headphone virtualization] · Stereo widening ⓘ [OFF]
- The EQ preset-with-preview UX from part 1 (sidebar) is separate. Figma `EQ presets.png`, `EQ.png`.

**8. Subtitles**: "**Subtitle Defaults**". `14-…/18m14.07s.jpg` (lower half); [Figma: Settings - subtitles.png, -1].
- *Tracks & Languages*: Enable subtitles ⓘ [ON] · Preferred language ⓘ [System language] · Text encoding ⓘ [Automatic]
- *Loading Subtitles*: Load subtitle files automatically ⓘ [ON] · File name matching ⓘ [dropdown **Title with extra characters**; options: Off / Any title / Contains title / Title with extra characters (✓) / Exact title match; see `17m30.96s.jpg`]
- *Appearance*: Font ⓘ [input "System, sans-serif"] · Size values ⓘ [segmented **Relative** / Pixels] · Font size [Automatic] · Bold [OFF] · Text color [color field #FFFFFF + white swatch] · Text opacity [slider 0% / 50% / 100%] · Outline thickness [Normal] · Outline color [#000000] · Shadow [ON] · Shadow color [#000000] · Shadow distance [Small] · Background [None] · Background color [#000000] · Background opacity [slider 0% / 50% / 100%, at 50%] · Vertical position [Bottom]
- *Timing*: Subtitle delay [slider −5 s / 0 s / +5 s, centered]
- *On-Screen Messages*: Show feedback for shortcuts ⓘ [ON] · Show feedback for [slider 0.5 s … 5 s] · Show filename when a video starts ⓘ [ON] · Show filename for [slider 1 s … 10 s]
- [Advanced Options ›]

**9. Library**: "**Playlists, Folders & Files**". [Figma: Settings - library.png] only.
- *Opening Files*: Only allow one VLC window ⓘ [OFF] · Apply to files opened from the file manager ⓘ [OFF, **disabled/greyed**, dependent on the previous] · Add to the playlist instead of replacing it ⓘ [OFF, disabled] · When opening a folder ⓘ [Include subfolders] · Show hidden files ⓘ [OFF]
- *Metadata & Artwork*: Fetch titles and artwork ⓘ [From the file only] · Use the media library ⓘ [ON]
- [Advanced Options ›]
- **Disabled-row style:** label and toggle drop to ~40% opacity (FG/A4).

**10. Network**: "**Network Connections & Security**". [Figma: Settings - network.png] only.
- *Buffering*: Buffering ⓘ [Normal] · Local files [input, disabled] · Discs [disabled] · Network streams [disabled] · Live capture [disabled] (enabled when Buffering = Custom, presumably)
- *Proxy*: HTTP proxy ⓘ [input "System proxy"] · HTTP proxy password ⓘ [input]
- *Security*: Verify certificates against the system trust store ⓘ [ON] · Cipher preference ⓘ [Balanced]
- [Advanced Options ›]

**11. Performance**: "**Performance Settings**". `14-…/18m20.07s.jpg`.
- *Decoding*: Hardware-accelerated decoding ⓘ [Automatic] · Video post-processing ⓘ [Off] · Skip the H.264 loop filter ⓘ [Never] · Decoding threads ⓘ [input 0]
- *Smooth Playback*: Drop frames when the system can't keep up [ON] · Give VLC real-time priority [OFF] · Process priority ⓘ [input 0] · Rescan plugins [full-width button "Rescan"]
- [Advanced Options ∨] (expanded) → *Developer*: Encoder ⓘ [Automatic] · Decoder ⓘ [Automatic] · Clock synchronisation ⓘ [Default] · Clock jitter ⓘ [input "5000 ms"] · Clock reference averaging ⓘ [input 40] · (more)

**12. Recording**: "**Recording, Casting & Streaming Out**". [Figma: Settings - recording.png] only.
- *Recording*: Save recordings to ⓘ [input "~/Videos" + Browse] · Record without re-encoding when possible [ON]
- *Casting*: Discover cast devices [ON] · Cast quality ⓘ [Automatic]
- *Streaming*: Play locally while streaming [ON] · Include audio [ON] · Include video [ON] · include subtitles [ON] (lowercase "i" in the design) · Encoding preset ⓘ [Medium] · Tuning ⓘ [None]
- [Advanced Options ›]

**13. Extensions**: "**Extensions & Scripts**". `14-…/18m26.07s.jpg`.
- *Extensions*: an empty **list box** (full width, ~230 px tall native, bg BG/B2, 1 px border `#1C1C1C`, radius 4).
- Below it: a small Search input (~245×34) on the left, then buttons on the right: "Find more extensions", "Add", "Remove".
- Load extensions on startup [ON].
- Plugins (VLC internal modules) belong under Advanced, per the transcript.

### C. Keyboard Shortcuts dialog (NEW)
Only the menu entry is in the frames (`14-…/16m02.76s.jpg`); the dialog itself appears **only in [Figma: Keyboard Shortcuts.png]** (2156×1660 @2× ≈ **1050×800** native).
- **Header** BG/B2: title "Keyboard Shortcuts" + ✕.
- Second header row: a full-width search field "Search Keyboard Shortcuts…" (magnifier) and a dropdown "All Fields ∨" (~185 px) on the right.
- **Body** bg BG/A1 `#222222`.
  - Column headers (FG/A3): "Action", "Hotkey" (centered over column 2), "Global Hotkey".
  - Group headings (FG/A1, 16 px): "Basic", "Playback", …
  - Rows (pitch ≈44): action label (FG/1-ish, 14 px) on the left. Two **key fields** (~250×30, bg BG/B2 near-black, radius 4) show the key centered ("F", "esc", "T", "I", "Space", "S", "N", "P", "X") with a **pencil edit icon** at the right of each field. The Global column is empty with only a pencil.
  - Basic: Toggle fullscreen (F) · Exit fullscreen / close dialog (esc) · Show playback position and time (T) · Show interface controls in fullscreen (I)
  - Playback: Play / pause (Space) · Stop playback (S) · Next track (N) · Previous track (P) · Next program / Service ID (X) · …
- **Footer:** Cancel (left, secondary) and Save (right, disabled until a change).

### D. Old hotkeys (OLD)
`14-…/15m56.76s.jpg` (Qt "Configure Hotkeys" table). Use it only for the full action list: Fullscreen f, Exit fullscreen Esc, Play/Pause Space, Pause only, Play only, Faster +, Slower -, Normal rate =, Faster (fine) ], Slower (fine) [, Next n, …; plus Mouse wheel vertical = Volume control, horizontal = Position control.

### Open questions (14)
- ⓘ popover/tooltip style.
- Search behavior (filtering categories vs rows).
- Scrollbar style.
- The "Advanced Options" expanded content for most categories.
- Notifications and System Tray rows in Interface.
- Light-theme details of every control.
- Whether the settings modal is a separate window on macOS. In the frames it is an in-window modal sheet centered over the player.

---

## 15 Customization editor, profiles, onboarding

**Reasoning (18:45–20:00).**
- The old Toolbars Editor is hard to use (OLD: `15-…/19m02.82s.jpg`, `19m07.01s.jpg`).
- The new one is "one big frame in the center of VLC filled with buttons and icons, and outlines showing you that you can move things". You drag elements in and out of the player's bars. An alternate layout demonstrates this.
- Layouts are saved under **profiles**, so all settings switch per profile.
- Since about half of users want minimal customization, add an **onboarding** with theme options plus a shortcuts screen.

### A. Customize Player mode
Frames: `15-…/19m12.39s.jpg` (**native**, default layout), `19m20.29s.jpg`, `19m26.29s.jpg` (**native**, alternate layout while editing; Save enabled), `19m18.39s.jpg` (zoomed tiles), `16-…/20m41.42s.jpg` (zoomed tile hover). Crops: `scratchpad/crops2/cust_cb_left.png`, `cust_tiles.png`. Figma `Player - customize*.png` (9 states).

- **Player in edit mode:**
  - The video stays as it is: the dark warm gray (`#272622`/`#22211D`) is the paused video frame itself, not a scrim. Player - customize uses the same video fill as Player, and 19m12.4 reads the same as normal playback with the video visible through the dialog (D053).
  - **Every element in the title bar and control bar gets a 1 px dashed outline** (FG/A4 `#404040`-ish, dash ≈3/3) marking it as draggable. Outlined elements include the ⋯ menu button, sidebar toggle, folder crumb "S01", the centered title, window-control group, prev/play/next buttons, the time + seek bar group, the volume group, and the right-side icon buttons.
  - Groups get one outline around the group, e.g. time + seek bar + duration form one box.
  - The control bar area gets a slightly lighter band (y 975–1035, `#1A1A1A`).
- **Customize Player dialog** (native 19m12.39):
  - Centered: x 435–1485 (**1050 px**, same as Settings), y 189–845 (**~656 px**), radius ≈10.
  - **Header** (BG/B2): title "Customize Player" (14 px FG/A1) at x 453, y 213, with ✕ at the right. Below it, still on the dark header band (y≈258): "Drag items around and out of the box below to re-order them. Drag items into the box to remove them from the player." (FG/A3, 13–14 px). The header band ends at y≈282.
  - **Body** bg BG/B1 with a **9-column tile grid**. Column centers x = 511, 621, 732, 842, 953, 1063, 1173, 1284, 1394 (**pitch ≈110**). Row centers y ≈ 333, 453, 572, 690 (**pitch ≈119**).
  - **Tile:** a dashed-outline box (~30×34) around a monochrome 20–24 px icon (FG/A2), with the label centered below (FG/A1, 14 px, wraps to 2 lines).
  - **Tile inventory, in order:**
    1. Spacer (empty dashed box)
    2. Divider (vertical line)
    3. Playback Speed (gauge)
    4. Forward 10s
    5. Backward 10s
    6. Forward 15s
    7. Backward 15s (circular arrows with numbers)
    8. Stop (■)
    9. Repeat
    10. Shuffle
    11. Record (◉)
    12. Snapshot (camera-frame)
    13. Picture in Picture
    14. HDR (HDR badge)
    15. Zoom (magnifier +)
    16. Right Sidebar (panel icon)
    17. Quit VLC (exit arrow)
    18. VLC Settings (gear)
    19. Go Home (house)
    20. Thumbnail (filled gray square)
    21. File Name ⓘ
    22. Artist Name ⓘ
    23. Folder Name ⓘ
    24. Playlist Name ⓘ
    25. Properties ⓘ
    26. Replay (↺)
    27. Chapters (▸☰)
    28. Favorite (♡)
    29. Bookmark (bookmark +)
    30. Bookmarks (bookmark)
    31. Playlists (playlist icon)
  - When an item is dragged into the player (e.g. Favorite in 19m26.29), its tile **disappears** from the grid.
  - **Footer:**
    - "Cancel" bottom-left (x 455–555, y 793–826, bg `#181818`, FG/A1 600).
    - "Save" bottom-right (x 1365–1465). **Disabled** = BG/A3 with FG/A4 text. **Enabled** = bg BG/Accent Bright `#2C1C05`/`#371F06` with **orange label** (Accent/Main, 600).
- **Alternate layout result** (`15-…/19m27.56s.jpg`, native):
  - The title bar keeps only the logo (left) and minimize/maximize/close (right). The fullscreen button and the centered title moved out.
  - **Two-row bottom bar:**
    - Row 1 (y 973–1014): current time "00:02:10" at the left (x≈55), a **full-width thick seek bar** (x 103–1818, ~27 px tall, bg `#0A0A0A`, orange playhead pill), and duration "00:25:40" at the right.
    - Row 2 (y 1015–1079, bg `#181818`):
      - Left: ⋯ menu, sidebar toggle, a divider, folder icon + "S01", title "The Wand S01E11", ♡ favorite.
      - **Center:** ⏮ prev, play (orange, ~50×28), ⏭ next.
      - Right: volume icon + cone slider, audio-tracks icon, subtitles icon, settings gear, a divider, queue list icon, **fullscreen** icon.
  - The Figma customize-8 render shows this alternate layout with the compact library panel open.

### B. Profiles
Frames: `15-…/19m29.39s.jpg`, `19m35.39s.jpg` (zoomed ~2.6×); [Figma: Profiles.png] (exact).
- Menu item "**Profile (Movies)**" (person icon with an orange head, ›) opens a **submenu** to the right (gap ~10 px, ~265 px wide, same style as the main menu, radius ≈12).
  - Items: "✓ Movies" (orange check, selected row highlighted BG/A2), "Shows", "Music", "Work", a divider, then "+ New".
  - Labels are indented to align past the check column (~52 px).
- Each profile stores the layout and all settings (transcript).

### C. Onboarding
Frames: `15-…/19m46.67s.jpg` (welcome), `19m52.67s.jpg` (shortcuts); both zoomed. **[Figma: Onboarding.png … Onboarding-10.png]** (2228×1566 @2× ≈ **1100×770** native, including the theme/color step that is **not in the video**).
- **Container:** a large rounded panel (radius ≈16), bg BG/B1 `#0F0F0F`, on black. It is presumably a first-run modal window.
- **Step 1, Welcome:**
  - Centered VLC cone logo (orange, ~70 px native).
  - "Welcome to VLC!" (FG/1 `#FFF`-ish, ~24 px, weight 300–400).
  - A paragraph (FG/A1 `#A3A3A3`, 14 px, line-height ~1.6, left-aligned in a ~400 px column): "VLC is a free and open source cross-platform multimedia player and framework that plays most multimedia files as well as DVDs, Audio CDs, VCDs, and various streaming protocols."
  - Label "Choose a Media Folder to get started with" (FG/A1).
  - Input "~/Videos" (bg BG/B2, FG/1 text) + "Browse" secondary button.
  - "**Next**" primary button bottom-right: orange Accent/Main bg, **dark label** (FG/B1 `#161616`), weight 600, ~66×21 native, radius 4.
- **Step 2, Theme and color (Figma only):**
  - "Select your preferred theme and color." centered.
  - Three theme tiles (~44×44 rounded squares): **Light** (light gray), **Dark** (dark; selected = 2 px accent-colored ring), **System** (diagonal split).
  - A live mini player preview strip.
  - A row of **9 circular accent swatches** at the bottom-left. The selected one gets a ring, and the whole UI (play button, seek fill, Next button, selected ring) recolors live.
  - Back / Next buttons. The swatch order matches Settings: orange, red, yellow-olive, green, teal/cyan, blue, purple, pink, gray.
- **Step 3, "Learn the basic keyboard shortcuts.":**
  - Title centered (FG/A1, ~16 px).
  - Two columns of rows (pitch ≈54 native). Each row has a label (FG/A1, 13 px) and **keycaps**: bg BG/A3 `#181818`/`#1B1B1B`, 1 px lighter border `#303030`, a **thicker bottom edge** (3D key, `#2D2D2D`), radius ≈5, key text FG/1 `#F3F3F3`, 13 px. "/" separators sit between alternative keys.
    - Left column: Play / Pause [Space] · Seek Backward / Forward [←] / [→] · Previous / Next Item [<] / [>] · Previous / Next Frame [,] / [.] · Cycle Subtitle Track [V] · Cycle Audio Track [B]
    - Right column: Toggle Fullscreen [F] · Increase / Decrease Volume [↑] / [↓] · Show / Hide Queue [Q] · Show / Hide File Browser [L] · Take a Snapshot [SHIFT][S] · Record [SHIFT][R]
  - Footer: "Find the full list in the menu." (FG/A3) on the left. On the right are "Back" (secondary: BG/A3, FG/A1 600) and "**Finish**" (primary orange, dark label).

### Open questions (15)
- Drag affordances: no drop-indicator or ghost styling is captured during a drag.
- Whether multiple bars (top/bottom/side) are all droppable.
- The "New profile" flow (name dialog?).
- Onboarding window size and position on macOS.
- Onboarding step count. The Figma set shows Welcome → Theme/Color → Shortcuts.

---

## 16 Final showcase: screens and details not seen elsewhere

`16-final-showcase/`:
- `20m00.54`–`20m03.86`: VideoLAN website and an outro slide. Not UI.
- `20m05.64`–`20m08.84`: Dragon Ball GIF. Not UI.
- **`20m14.84s.jpg`**: full-window **Videos folder grid** (5 columns, breadcrumb Videos ▸ Shows ▸ The Wand ▸ S01, watched items last with full orange bars and dimmed titles). See §11F.
- **`20m20.84s.jpg`**: compact panel with the rail showing Home, Videos, Music, Network, **Playlists (active orange)**, **Recent**, + (pins not shown).
- **`20m21.37s.jpg`**: **Queue tab** with header controls (sort / repeat / shuffle / − / +), the current item in orange, and the drag-insertion "⋯" placeholder. See §13A.
- `20m23.61s.jpg`: zoomed **play button**: orange rounded rect (aspect ~1.9:1, radius ≈25% of height), with the ▶ glyph in **dark FG/B1** (not white).
- `20m24.74s.jpg`: zoomed **seek playhead**: a tall rounded pill (orange) over the dark-orange filled track and black remainder. Track ends are rounded.
- `20m30.74s.jpg`: "Settings Re-imagined" title card.
- `20m36.74s.jpg`: Audio settings (bottom rows; §14 Audio).
- `20m40.52s.jpg`: "Even That." title card.
- `20m41.42s.jpg`: zoomed Favorite / Bookmark customize tiles (hover shows the arrow cursor; no highlight).

Nothing new beyond the above: no fullscreen, mini-player or light-theme library frames appear in 16.

---

## Full screen / dialog / panel inventory (implementation list)

Frame paths are relative to `research/video/frames/`. "(part 1)" items are covered in spec-part1, with frames in folders 01–08. They are listed here for completeness only where these sections also show them.

| # | Screen / dialog / panel | Best reference | Notes |
|---|---|---|---|
| 1 | Player window, video playing (default layout) | `10-…/12m56.59s.jpg` (native) | title bar + control bar (part 1) |
| 2 | Player, music now-playing (big cover art + blurred bg, waveform seek) | `09-music/12m18.39s.jpg` | Figma Player - Music.png |
| 3 | Compact library panel: Music root (Songs/Albums/Artists/Genres) | `09-music/12m12.39s.jpg` | zoomed |
| 4 | Compact library panel: folder/file list with thumbs + breadcrumb | `09-music/12m18.39s.jpg`, `11-…/13m29.17s.jpg` | |
| 5 | Compact library panel: Network category | `11-…/13m18.66s.jpg` | |
| 6 | Compact library panel: Playlists category | `11-…/13m24.66s.jpg`, `16-…/20m20.84s.jpg` | |
| 7 | Compact library panel: Home (Continue Watching / Listen Again) | `11-…/13m47.17s.jpg` | |
| 8 | Compact library panel: Recent | none | not shown |
| 9 | Library icon rail with Home/Recent/pins/+ | `11-…/13m41.17s.jpg`, `13m47.17s.jpg` | |
| 10 | Full-window library: Home (sections grid) | `11-…/13m57.34s.jpg` (native) | |
| 11 | Full-window library: folder grid view (watched states, unwatched-first) | `16-…/20m14.84s.jpg` | |
| 12 | "⋯" app menu (final, with Profile/Keyboard Shortcuts) | `15-…/19m29.39s.jpg`; Figma Profiles.png | |
| 13 | Profile submenu (Movies/Shows/Music/Work/+New) | `15-…/19m35.39s.jpg` | |
| 14 | Open Recent submenu | none | not shown |
| 15 | Open Network Stream dialog | `11-…/13m17.76s.jpg`; Figma Open network stream.png | |
| 16 | Open Disc / Open Capture Device / Convert / Stream / Open from Clipboard dialogs | none | not shown; reuse dialog chrome |
| 17 | New Playlist dialog | `11-…/13m26.14s.jpg`; Figma new playlist.png | |
| 18 | Continue-watching toast (bottom-center) + resume marker on seek bar | `12-continue-watching/14m09.81s.jpg` (native) | |
| 19 | Right sidebar: Queue tab (header controls, drag insert) | `16-…/20m21.37s.jpg` | |
| 20 | Right sidebar: Chapters tab | `13-…/15m16.67s.jpg` (native) | |
| 21 | Right sidebar: Bookmarks tab | none | not shown |
| 22 | OSD message with pressed key ("Crop: 2.35:1 / Pressed C") | `14-…/15m27.09s.jpg` | |
| 23 | Settings: General (incl. Accent color, Advanced expanded) | `14-…/17m40.87s.jpg`, `17m50.07s.jpg`, `15-…/18m51.06s.jpg` | |
| 24 | Settings: General in Light theme | `14-…/17m42.54s.jpg`–`17m44.01s.jpg` (crossfades) | |
| 25 | Settings: Interface | Figma Settings - interface.png | not in video |
| 26 | Settings: Privacy | `14-…/17m56.07s.jpg` | |
| 27 | Settings: Controls | Figma Settings - controls.png | not in video |
| 28 | Settings: Playback | `14-…/18m02.07s.jpg` (ghost); Figma Settings - playback.png | |
| 29 | Settings: Video | `14-…/18m02.07s.jpg`; Figma Settings - video.png | |
| 30 | Settings: Audio (with inline Equalizer) | `14-…/18m08.07s.jpg`, `16-…/20m36.74s.jpg` | |
| 31 | Settings: Subtitles (incl. On-Screen Messages) | `14-…/18m14.07s.jpg`; Figma Settings - subtitles.png | |
| 32 | Settings: Library | Figma Settings - library.png | not in video |
| 33 | Settings: Network | Figma Settings - network.png | not in video |
| 34 | Settings: Performance (Advanced expanded) | `14-…/18m20.07s.jpg` | |
| 35 | Settings: Recording | Figma Settings - recording.png | not in video |
| 36 | Settings: Extensions & Scripts | `14-…/18m26.07s.jpg` | |
| 37 | Settings dropdown popup (with ✓) | `14-…/17m30.96s.jpg` | |
| 38 | Keyboard Shortcuts dialog | Figma Keyboard Shortcuts.png | only the menu entry is in video (`16m02.76`) |
| 39 | Customize Player mode (dashed outlines + tile dialog) | `15-…/19m12.39s.jpg` (native) | |
| 40 | Customize Player, alternate two-row layout (editing / result) | `15-…/19m26.29s.jpg`, `19m27.56s.jpg` | |
| 41 | Onboarding 1: Welcome + media folder | `15-…/19m46.67s.jpg` | |
| 42 | Onboarding 2: Theme + accent color | Figma Onboarding-1.png … -10.png | not in video |
| 43 | Onboarding 3: Basic keyboard shortcuts | `15-…/19m52.67s.jpg` | |
| 44 | About VLC | none | not shown |
| 45 | Context menus: file / folder / playlist ("Add to playlist") | none here; Figma file/folder/playlist context menu.png | |

OLD UI frames to ignore: `10-…/12m33.04`–`12m52.37`, `13m12.87`–`13m14.97`, `11-…/13m15.01`–`13m16.24`, `13m49.61`, `13m51.34`, `11-…/13m57.81`, `12-…/14m03.81`, `13-…/14m57.42`–`15m09.09`, `14-…/15m29.66`–`15m56.76`, `16m03.31`–`17m24.96`, `18m28.14`–`18m41.34`, `15-…/19m02.82`, `19m07.01`.

## Global open questions
1. Exact text and icon colors: frames run 5–15% darker than the Figma tokens. Use the tokens.
2. Hover, pressed and focus states are captured only for menu rows (BG/A3 rounded), the toast button (Accent/Dim), and tiles (no highlight).
3. No animation timing is visible (panels and toasts appear in a cut).
4. macOS adaptation: the design shows Windows-style controls (– □ ⛶ ✕) on the right. Decide whether to use traffic lights.
5. Light theme is shown only for Settings General (crossfade) and in Figma `Player - Light.png`.
