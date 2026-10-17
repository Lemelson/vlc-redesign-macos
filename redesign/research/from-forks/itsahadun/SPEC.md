# VLC Redesign: design spec

Source: Figma `E17x5esiisVGqtS4CB4Hh2` ("VLC Redesign (Community)"), page `0:1`.
Target: VLC 4.x Qt6/QML UI in `modules/gui/qt`.
All measurements are in logical px at 1x (Figma units). Colors are sRGB hex; `#rrggbb/0.xx` means that color at that opacity.

---

## 0. Extraction status and confidence (read first)

The Figma MCP account hit its **Starter-plan tool-call quota** early in extraction ("You've reached the Figma MCP tool call limit on the Starter plan"). Every Figma call failed after that (`get_screenshot`, `get_metadata`, `get_variable_defs`, `use_figma`). As a result:

| Source | What it gave | Confidence |
|---|---|---|
| Plugin API read of local **paint styles** and **effect styles** | The complete Dark and Light color token set and the two blur/shadow effects (section 1.1) | **Exact** |
| Plugin API tree dump of components `Button`, `Toggle`, `Icon Wrapper`, `play`, `volume`, `Values` (x2) | Fills, radii, padding, gaps, font and size for those components (section 3) | **Exact** |
| Pre-existing `meta.xml` (page metadata: node ids, names, positions, sizes; text layer names = text content) | Layout boxes and verbatim strings for Settings, Onboarding, dialogs, menus, Music player, component sets | **Exact for geometry and text**; instance overrides (text inside menu instances, which variant is used) are **not** visible |
| 14 PNG screenshots taken before the quota ran out (`design/reference/`) | Visual reference; pixel-sampled colors and screen measurements | **Approximate** (+/-1-2 px after scaling; antialiased colors) |

**Not done (blocked on Figma quota):**
- SVG export of the 208 icons: only the index and manifest exist (`design/icons/INDEX.md`, `design/icons/manifest.json`).
- `design/assets/` (VLC cone, folder and music placeholders, sample artwork): nothing exported.
- Reference PNGs for 62 of the 76 listed frames. Section 5 lists which ones exist.
- Exact text styles (font weight and line height) for text outside the components above. Sizes in section 1.6 come from text-box heights and are tagged *(derived)*.
- Item lists of menu components that are instance-based: Sorting Options, View Options, context menu, folder/file/playlist context menus, dropdown option lists, and the Controls popups. The two frame-based menus (`right-click menu`, `menu`) are complete.

Items marked **TODO(figma)** need a follow-up pass once quota is available. The one-shot recipe is in section 6.

---

## 1. Design tokens

### 1.1 Color palette (Figma local paint styles; exact)

The Figma file defines **paint styles**, not variables (the only variable collection is empty). The Dark set is complete. The Light set reuses some Dark values (FG/1, FG/2, FG/A3, FG/B1) and has no Light/FG/A... beyond A4.

| Token | Dark | Light | Usage (observed) |
|---|---|---|---|
| FG/1 | `#eaeaea` | `#eaeaea` | Highest-emphasis text: selected settings category label, text on accent |
| FG/2 | `#c6c6c6` | `#c6c6c6` | Section headers in settings, primary titles |
| FG/A1 | `#969696` | `#3c3c3c` | Window/dialog titles, secondary-high text |
| FG/A2 | `#8f8f8f` | `#2e2e2e` | Default icon color, body text, button labels, dropdown values |
| FG/A3 | `#6b6b6b` | `#6b6b6b` | Muted text: unselected segmented/toggle labels, group captions (App/Media/System), button "Default" label |
| FG/A4 | `#404040` | `#3b3b3b` | Toggle OFF knob, placeholder text (search field) |
| FG/B1 | `#161616` | `#161616` | Dark glyph on accent (the play-button icon) |
| Accent/Main | `#d37918` | `#e8851a` | Accent: play button bg, seek handle, active icons, selected text, selected swatch ring |
| Accent/Bright | `#fc9729` | `#ffa13b` | Hover/pressed accent (brighter) |
| Accent/Logo | `#d37918` | `#c2711a` | VLC cone tint in the title bar |
| Accent/DIm *(sic)* | `#ab6314` | `#965916` | Toggle ON knob; dimmed accent |
| BG/Accent Bright | `#371f06` | `#d8ba9a` | Selected background: toggle ON label well, selected segment, seek-bar played part |
| BG/Accent Dark | `#1a1611` | `#c6ab89` | Very subtle accent-tinted background (e.g. watched item highlight); rare |
| BG/A1 | `#222222` | `#ededed` | Selected settings category row; elevated rows |
| BG/A2 | `#1f1f1f` | `#dddddd` | Elevated surface |
| BG/A3 | `#1b1b1b` | `#d5d5d5` | **Title bar and control bar** background, player chrome, miniplayer card |
| BG/A4 | `#191919` | `#b3b3b3` | Nav pane (library), settings sidebar card, dropdown/segment cell bg, buttons (Variant2), "Advanced Options" bar |
| BG/A5 | `#151515` | `#888888` | Search field bg |
| BG/B1 | `#0e0e0e` | `#e7e7e7` | **App/page background** (library content, settings content, side panel) |
| BG/B2 | `#090909` | `#dedede` | Wells and tracks: seek-bar track, toggle/segmented outer track, text-field bg, settings header bar, Button "Default" bg |
| BG/A3 Transparent | `#191919/0.95` | `#d5d5d5/0.75` | Floating panels over video (popups, menus) |
| BG/B1 Transparent | `#0e0e0e/0.95` | `#e7e7e7/0.80` | Floating panels over video |
| BG/B2 Transparent | `#000000/0.80` | (none) | Scrims, overlays over video |
| Divider/Bright | `#373737` | `#9b9b9b` | Strong dividers |
| Divider/Dim | `#222222` | `#acacac` | Regular dividers: list header underline, menu separators |

Non-token colors that appear in components:
- Hover overlay on icon buttons: `#ffffff/0.06` (Icon Wrapper hover).
- Volume bar background "fill" mask: `#262626`.
- Volume gradient (left to right): `#95d318` @0.00, `#b2a918` @0.58, `#d37918` @0.79, `#ff3737` @1.00, with `#000000/0.20` layered on top.
- Component-sheet frame stroke `#8a38f5` is Figma documentation chrome. **Do not implement.**

**Light theme caveats (architect decision needed):** only one Light screen exists (`Player - Light` 2425:13624). In it the window chrome samples at about `#ababaa` and the side panel at about `#c1c1c0`, and neither matches a Light token exactly. Use BG/A4 `#b3b3b3` for chrome and BG/A3 `#d5d5d5` for panels unless told otherwise. The play button in that screen still uses the Dark accent `#d37918`, which is probably an omission in the design. Use Light Accent/Main.

### 1.2 Accent colors (9, in order)

These are the settings "Accent color" swatches and the onboarding color dots, left to right. Values are pixel-sampled from the settings screenshot, where they render at full opacity. Swatch 1 equals Dark Accent/Main exactly.

| # | Hex | Name (suggested) |
|---|---|---|
| 1 | `#d37918` | Orange (default) |
| 2 | `#a13b26` | Red |
| 3 | `#8c721b` | Mustard |
| 4 | `#147528` | Green |
| 5 | `#147a97` | Teal |
| 6 | `#144497` | Blue |
| 7 | `#6631b5` | Purple |
| 8 | `#ab3c80` | Magenta |
| 9 | `#7e7e7e` | Grey |

(+/-2 per channel from antialiasing. Exact fills are TODO(figma) on nodes `3046:9875 ... 3046:9891`, `Rectangle 257`.)

In onboarding, the unselected dots render at about 73% brightness (e.g. `#772f20` for red). Either use opacity 0.72 on the unselected dots or compute `color * 0.72`. The selected dot gets a 64x64 ring; see section 2.4.

Persist in the existing option **`qt-accent-color`** (string; `default` / `system` / `#rrggbb`), already read by `style/systempalette.cpp` and `style/systempalettethemeprovider.cpp`.

### 1.3 Deriving accent tints

These rules are derived from the orange set and reproduce the Dark tokens exactly. Apply them to any of the 9 accents. Work in RGB with channel values 0-255.

| Token | Rule (Dark) | Check (orange) |
|---|---|---|
| Accent/Main | the swatch color `A` | `#d37918` |
| Accent/DIm | `A * 0.81` | `#ab6314` (exact) |
| BG/Accent Bright | `A * 0.26` (equivalently A at 26% over black) | `#371f06` (exact) |
| BG/Accent Dark | `mix(#111111, A, 0.048)` | `#1a1611` (+/-1) |
| Accent/Bright | HSV: `V = min(1, V_A * 1.195)`, `S = S_A * 0.945`, same hue | `#fc9729` (+/-2) |

Light theme (one sample only, so approximate): Main is a lighter variant (orange `#e8851a`, about `A` in HSV with V*1.10). BG/Accent Bright is about `mix(#cfcfcf, A_light, 0.30)` and BG/Accent Dark about `mix(#bdbdbd, A_light, 0.30)`. **Architect decision:** either keep the Light orange as a special case and derive the others, or derive all of them.

Where the accent tints are used:
- **Seek bar:** track BG/B2 `#090909`; played part BG/Accent Bright; handle Accent/Main, about 6x28 rounded rectangle (the handle sits at the end of the played part and is full track height). Light: track `#dedede`, played `#d8ba9a`, handle `#e8851a`.
- **Toggle ON:** label well BG/Accent Bright, label text Accent/Main, knob Accent/DIm.
- **Segmented control selected cell:** BG/Accent Bright, text Accent/Main.
- **Volume bar:** fixed green-yellow-orange-red gradient (section 1.1), **not** accent-derived.
- **Active nav icon / current item text:** Accent/Main.
- **Watched progress** under thumbnails: Accent/Main bar (about 3 px) along the thumbnail bottom.

### 1.4 Effects

| Style | Definition | Used on |
|---|---|---|
| `bg blur` | background blur, radius 50 | Floating panels over video (miniplayer queue, popups) |
| `bg blur + shadow` | background blur 50 + drop shadow `#000000/0.46`, offset (0, 8), blur radius 15, spread 0 | Menus, context menus, dialogs over the player |

QML: `qt-backdrop-blur` and `widgets/qml/FrostedGlassEffect.qml` / `DualKawaseBlur.qml` already exist. Use `DropShadowImage`/`RoundedRectangleShadow` for the shadow (blurRadius 15, yOffset 8, color `#000000` alpha 0.46).

Settings, dialogs and onboarding windows sit on an outer frame `#0e0e0e` with about 8 px of padding and a soft outer shadow (visible as `#292929`/`#272727` halo in the screenshots). Corner radius of the window is about 12 *(derived)*.

### 1.5 Radii, spacing, sizes

**Corner radii (exact where from components):**
| Value | Where |
|---|---|
| 2 | Volume bar fill; small input inside "Values" (Frame 265) |
| 3 | Toggle inner wells and knob |
| 4 | Buttons (Button component), segment cells, Icon Wrapper hover bg, dropdown inner option |
| 6 | Toggle outer track, segmented outer track (Values), play pill |
| about 8 | Cards/thumbnails, nav pane card, miniplayer card, settings sidebar card *(derived)* |
| about 12 | Windows (settings/dialog/onboarding), large music artwork *(derived)* |

**Spacing scale observed:** 2, 4, 6, 8, 10, 12, 14, 16, 20, 24, 28. Key cases:
- Track-to-cell padding in segmented/toggle controls: 2 (Values) / 3 (Toggle).
- Icon-to-label gap in buttons: 6. Settings label to info-icon gap: 10.
- Settings content padding: 24 horizontal, 20 top; section gap 20; row pitch 42 (toggle rows) / 46 (dropdown rows).
- Library content left gutter after nav pane: 28 (nav pane right edge 208, content x 236).
- Window outer padding (title bar icons, nav pane, miniplayer margins): 6-8.

**Sizes:**
| Element | Size |
|---|---|
| Title bar (topbar) | height **40**. Left cluster at (6, 6), 300x28; right window buttons 4 x **36x24** at x = W-306+156.. (rightmost 6 px from edge) |
| Control bar | height **54**, full width, bg BG/A3 |
| Library nav pane, expanded (labels) | x 8, y 48, width **200**, bottom margin 8; bg BG/A4; rounded about 8 |
| Player nav rail, collapsed (icons only) | width about **50** (0..50), bg BG/A4 |
| Player side panel ("sidebar" component) | **427x986** at (0, 40) = rail 50 + panel 377; panel bg BG/B1 |
| Icons | 24 (standard), 18 (settings info icon), 28 (topbar icon buttons 28x28), 141 (onboarding cone) |
| Icon button hit area | 30x32 (Icon Wrapper: 4 px padding around 24 icon); topbar buttons 28x28; window buttons 36x24 |
| Play pill | **54x28**, r6, Accent/Main, icon 24 FG/B1 |
| Time label | 76x28 (Current Time / Duration components) |
| Volume control | **88x28** |
| Toggle | **68x32** |
| Settings control column | x 464 within 784-wide row, width **320**; dropdown/text field height 36; buttons 100x32 |
| Settings category row | 188x40 |
| Menu option row | 257x48 (context menus), 284x48 (right-click menu), 367x48 (main menu); icon 24 at x 14; label at x 48 |
| List row (side panel media/playlist) | 337x32 |
| Video grid card | thumbnail about **316x178** (16:9), column gap **20**, row pitch about 255 (thumb + 2 lines of text); 5 columns at 1920 |
| Music/folder grid card | about **200x200**, gap 20 |
| Miniplayer card | **391x339** (with queue: 391x690), 8 px from the window's right (or left) edge and 8 px from the bottom |
| Seek-preview thumbnail | 272x189 card: 252x142 image at (10, 10) + time label below |
| Settings window | **1048x865** (header 50, sidebar 216, content 832) |
| Dialogs | 1048x800 (Add Subtitles, Keyboard Shortcuts), 1048x631 (Open Network Stream), 713x589 (New Playlist); header 50 (or 96 with a toolbar row), footer 72 with Cancel at (20, 20) and Save at (W-120, 20), both 100x32 |
| Onboarding window | 1090x759 |

### 1.6 Typography

**Family: Inter** (all text). Weights seen in exact component dumps: Regular. Headings look Medium in the screenshots, which is *derived*. Bundle Inter (OFL) or fall back to the system sans. VLC currently uses the system font, so this is an **architect decision**.

| Size / line height | Letter spacing | Where |
|---|---|---|
| 12 / auto (15) | 0 | Toggle ON/OFF labels |
| 14 / auto (17) | 0 | **Default UI text**: settings labels, buttons, menu items, list rows, breadcrumbs, title-bar title, dialog titles, dropdown values, time labels |
| 14 / 25 *(derived, 175%)* | 0 | Dialog helper text ("You can enter multiple links to load."), Keyboard Shortcuts table cells |
| 16 / auto (19) | 0 | Settings section headers ("Appearance"), settings window title ("Global Settings"), onboarding buttons (Next/Back/Finish/Browse) |
| 16 / 28 *(derived)* | 0 | Dialog section titles ("Network URL", "Playlist Details"), onboarding body copy, key caps, "Basic"/"Playback" group titles |
| 24 / auto (29) | 0 | Music player track line ("untangle - juxtopposed") |
| 24 / 42 *(derived)*, Light weight in screenshot | 0 | Onboarding step titles ("Select your preferred theme and color.") |
| 32 / auto (39) | 0 | Onboarding "Welcome to VLC!" |

Text colors: section headers FG/2; labels FG/A2; window titles FG/A1; captions FG/A3; placeholders FG/A4; selected or active text Accent/Main; text on selected settings category FG/1.

---

## 2. Screens

Coordinates are relative to the frame's top-left corner.

### 2.1 Main window / Player (1920x1080)

Common skeleton (all Player frames):
- **Title bar** (0, 0, 1920x40, BG/A3):
  - Left cluster (6, 6), 28 high: VLC cone icon (24, Accent/Logo) in a 38x28 slot; a "more" (`...`) icon button 28x28 (opens the main menu, section 3.9); a sidebar toggle icon button 28x28 (`expand-sidebar`/`collapse-sidebar`); a 1 px divider (24-wide slot); a folder icon 28x28 + current folder label (14px, FG/A2), e.g. "Videos", "S01", "My Songs".
  - Center: media title (14px, FG/A2), centered on the window: "VLC Media Player" when idle, else the media title ("The Wand S01E04", "untangle").
  - Right: minimize, maximize, fullscreen, close icon buttons, each 36x24, at y 8, right edge 6.
- **Video area**: below the title bar, inset about 8 px left/right with a rounded corner (about 8). The background shows through as BG/A3.
- **Control bar** (0, 1026, 1920x54, BG/A3), left to right, vertically centered:
  1. previous (24 icon) at x about 26
  2. play pill 54x28 at x about 59 (Accent/Main, r6, `play` icon in FG/B1; pause state uses bg FG/A3 `#6b6b6b`)
  3. next at x about 125
  4. current time "00:02:10" (14px FG/A2) in a 76x28 slot at about 141
  5. seek bar from x about 256 to 1490: track BG/B2, 28 high (the full slot height, rounded about 4), played BG/Accent Bright, handle Accent/Main about 6 wide
  6. duration "00:25:40" 76x28
  7. volume icon (`volume` with value high/medium/low/none) + volume bar 88x28 at about 1630-1717
  8. icon buttons: waveform/EQ (audio effects), subtitles, settings (playback settings)
  9. queue/playlist icon at x about 1881

  Gaps between groups are about 20; icons are Icon Wrapper (30x32, hover `#ffffff/0.06`).

| Frame | Content |
|---|---|
| **247:445** Player | Plain playback. Title bar shows "Videos" folder and "VLC Media Player". Video fills the area. No side panel. (reference: `player-247-445.png`) |
| **187:328** Player | Playback with the **left side panel open** (sidebar component, 427 wide) on the **Playlists** page. Rail icons top to bottom: home, videos (play icon), music, network, playlists (**active**, accent), recent, add (+). Panel header: back/forward arrows, title "Playlists", `...` and pop-out icons; sub-header "2 items" (14px FG/A3) with sort, view (list), search icons; divider; rows "Create playlist" (+ icon, FG/A3), "Cool Songs", "Anime to Watch" (playlist icon). Video area shrinks to x 427..1912. (`player-187-328.png`) |
| **970:2703** Player | **Library mode, grid**, **miniplayer docked bottom-right**. Expanded nav pane (200 wide) with labels Home, Videos, Music, Network, Playlists, Recent, Add Item. Header row: back/forward, breadcrumb "Videos > Shows > The Wand > **S01**" (last segment bold FG/2), right side "110 items", sort, view-mode (grid), search field ("Search", 32 high, BG/A5), `+`, `...`. Grid of video cards "The_Wand_S01E05.mp4" ... ; watched items (S01E01-E04) show dimmed titles and an accent progress bar under the thumbnail. Title bar shows only the cone, the `...` button and "The Wand S01E04". (`player-970-2703.png`) |
| **970:3308** Player | Same as above in **list (compact) view**: 4 columns of rows (thumbnail 32x24 + name). The current item ("The_Wand_S01E05.mp4") is in Accent/Main with a play glyph on its thumbnail; watched items are dimmed (FG/A3). Miniplayer bottom-right. (`player-970-3308.png`) |
| **970:3792** Player | List view with the **miniplayer docked bottom-left** (over the nav pane, x 8). Shows that the miniplayer can be dragged or docked to either side. (`player-970-3792.png`) |
| **970:4028** Player | Grid view, **no miniplayer** (nothing playing), title "VLC Media Player", "15 items". (`player-970-4028.png`) |
| **6261:15078** Player | **Home** page: breadcrumb "Home". Sections, each with a title (16px, FG/2) and a `>` chevron: "Continue Watching" (video cards with an accent progress bar at the bottom-left of the thumbnail), "Listen Again" (square music cards about 200x200 with title "untangle"/"moonlight"/"black bird" and artist "juxtopposed", FG/A3), "Frequently Visited Folders" (square cards BG/A2 with a centered folder icon). (`player-6261-15078.png`) |
| **4767:23726** Player - Music | Audio playback. The background is the album art enlarged (1952x1952 at (-16, -436)), heavily blurred and darkened. Centered artwork **738x737 at (591, 113)**, rounded about 12. Track line "untangle - juxtopposed" (24px FG/2) centered at y 924. The control bar is the **music variant**: prev, back-15 (`backward-15-sec`), play, forward-15, next; time "00:00:10"; **waveform seek bar** (vertical bars; played bars Accent/Main, unplayed FG/A3); duration "00:01:40"; volume; EQ icon; queue. Side panel hidden (sidebar instance at x -437). A **"continue" toast** (519x52 at (701, 950)): "You’ve watched till 00:45:08 already." + button "Continue Watching" (146x32). It is hidden in the screenshot. Title bar folder "My Songs", title "untangle". (`player-music-4767-23726.png`) |
| **4778:25123** Player - Music | Same as above with the **side panel open** (sidebar at x 0, 427 wide). TODO(figma): screenshot. |
| **3328:11554** Player - hide UI | Video only: no title bar or control bar. The video sits in a rounded rectangle with a thin (about 8 px) BG/A3 frame. Toggled by right-click menu "Hide UI" (Ctrl + \\). (`player-hide-ui-3328-11554.png`) |
| **2425:13624** Player - Light | Light theme version of 187:328 with the side panel showing a **folder listing**: breadcrumb "... ▸ The Wand ▸ S01", "15 items", rows with 24x24 thumbnail + filename; watched rows (E01-E04) at normal text color and unwatched rows dimmed; topbar folder "S01". Seek track `#dedede`, played `#d8ba9a`. (`player-light-2425-13624.png`) |
| **2107:5604, 2160:6137, 2160:6564, 2160:7005, 2160:7437, 2160:7869, 6587:19923, 2160:8301, 2160:8732** Player - customize | **Customize Player** flow (main menu, then "Customize Player"). Every customizable slot in the title bar and control bar gets a dashed outline. A centered modal "Customize Player" (about 1048x655, BG/A3 Transparent with blur) with the close X and the text "Drag items around and out of the box below to re-order them. Drag items into the box to remove them from the player." holds a palette grid (9 columns) of draggable items with icon + label: Spacer, Divider, Playback Speed, Forward 10s, Backward 10s, Forward 15s, Backward 15s, Stop, Repeat, Shuffle, Record, Snapshot, Picture in Picture, HDR, Zoom, Right Sidebar, Quit VLC, VLC Settings, Go Home, Thumbnail, File Name, Artist Name, Folder Name, Playlist Name, Properties, Replay, Chapters, Favorite, Bookmark, Bookmarks, Playlists. Footer: "Cancel" (BG/A4) and "Save" (disabled-looking until there are changes). The 9 frames are successive drag-and-drop steps. TODO(figma): screenshots for the 8 later frames to see each intermediate state. (`player-customize-2107-5604.png` = first step) |

### 2.2 Miniplayer (component 970:3091; `component-miniplayer-970-3091.png`)

Card 391x339, bg BG/A3, radius about 8, 4 px inner padding:
- Video preview (about 383x215, r about 6).
- Progress strip under the video (BG/B2 track, BG/Accent Bright played, about 8 high).
- Title "The_Wand_S01E11.mp4" (14px FG/A2).
- Bottom row: folder icon + "S01", artist icon + "S01", and a queue icon on the right (Accent/Main when the queue is open).

Variants:
| Variant | State |
|---|---|
| Default (970:3090) | Idle display |
| Variant2 (970:3092, 391x690) | **Queue expanded above the card**: header "Queue" (centered), sub-row "4 items · 2h 3m" with sort, `-`, `+`; rows with drag handle (`move`), title, duration right-aligned ("23:00", "24:18", "25:00", "22:35") |
| Variant3 (975:4333) | **Hover**: dark scrim over the video with close `X` (top-left), pop-out (top-right), and centered prev / play / next |
| Variant4 (975:4377) | Hover + queue expanded |
| Variant5 (1919:9515) | **Ended**: centered replay icon instead of play |

### 2.3 Settings window (1048x865)

Layout (all pages):
- **Header bar** (0, 0, 1048x50, BG/B2):
  - Search field (8, 8, 200x34, BG/A5, r about 6): search icon at (8, 5), placeholder "Search" (14px FG/A4).
  - Title at x 240 (16px FG/A1), e.g. "Global Settings".
  - Close Icon Wrapper 32x32 at (1002, 9).
- **Sidebar** (0, 50, 216x815): card (8, 8, 200x799, BG/A4, r about 8). Inside, 6 px padding:
  - Group captions "App", "Media", "System" (14px FG/A3, 33 high, x 10).
  - Category rows ("setting category" component, 188x40, 8 px gap). Row: icon 24 at x 10 + label 14px at x 50. Selected: BG/A1 `#222222`, r about 4, icon Accent/Main (`*-active` icon), label FG/1. Unselected: icon and label FG/A2.
  - **Categories (in order):** App: General (`preferences`), Interface (cursor/`ui`), Privacy (`privacy`), Controls (`hotkeys`). Media: Playback (`playback`), Video (`video`), Audio (`audio`/waveform), Subtitles (`subtitles`), Library (`folder`). System: Network (`streaming`), Performance (`preferences`/sliders), Recording (`record`), Extensions (`plugins`).
- **Content** (216, 50, 832x815, BG/B1), scrollable column at (24, 20) 784 wide:
  - Section header (16px FG/2) in a 39-high slot, then rows. Sections are separated by 20.
  - **Row:** label (14px FG/A2) + optional **info icon** (`info`, 18x18, FG/A3, 10 px after the label; shows the option's long help as a tooltip; the tooltip text is not in the design, so use the VLC option's `_LONGTEXT`). The control is right-aligned at x 464, 320 wide, except Toggle (68x32 at x 716).
  - **Control types:** Toggle; Dropdown (320x36, outer BG/B2 r6 with 2 px padding, inner BG/A4 r4, value 14px FG/A2 at x 14, chevron-down 24 at right); Segmented ("Values", 320x36 or 320x78 two-line variant); Slider (320 wide with tick labels under it, 47-57 high); Text field / spin box (BG/B2, 36 high; "Frame 265"/"Frame 266"); Text field + Browse button (210x36 field + 100x32 button BG/A4, label 14px FG/A2); Button (100x32 or 320x32 BG/A4, e.g. "Reset", "Open", "Clear"); Color field (320x32, shows hex "#FFFFFF").
  - "**Advanced Options**" bar at the end of each page: 784x38, BG/A4, r about 4, centered "Advanced Options" (14px FG/A2) + chevron-right 24. Clicking it reveals the advanced rows below. The second frame of each page pair shows the expanded state.

Each page below lists: label verbatim, then `(i)` when it has an info icon, then the control, the default value shown, and the proposed VLC option. Keys were checked with grep. `NEW` means there is no existing option and one must be added (suggested `qt-` name). `TODO` means unclear.

#### Global / General: 999:5047 (collapsed), 3046:9282 (advanced expanded). Title "Global Settings"
| Section | Label | Control (default) | VLC option |
|---|---|---|---|
| Appearance | Interface language | Dropdown (English) | no vlcrc key: Win32 stores it in the registry `HKCU\Software\VideoLAN\VLC\Lang` (`SPrefsPanel::langChanged`, `language_map` in `simple_preferences.cpp`); other OSes follow the system locale. TODO for non-Windows |
| | Theme | Segmented: Dark / Light / System (Dark selected) | QSettings `MainWindow/color-scheme-index` via `ColorSchemeModel` (not a vlcrc key) |
| | Accent color | 9 swatches (section 1.2); selected cell BG/Accent Bright | `qt-accent-color` |
| Startup | Show confirmation and error dialogs (i) | Toggle (OFF) | `qt-error-dialogs` |
| | Check for updates automatically (i) | Toggle (OFF) | `qt-updates-notif` (+ `qt-updates-days`) |
| Diagnostics | Developer mode (i) | Toggle (OFF) | NEW `qt-developer-mode` (reveals the "Developer" sections) |
| | Save a log (i) | Toggle (ON) | `file-logging` |
| | Log file (i) | Text field + "Browse" | `logfile` |
| | Log details (i) | Dropdown (Errors only) | `log-verbose` (Errors only=0, Warnings=1, Debug=2) |
| Advanced | Show minor warnings (i) | Toggle | `verbose` (>=1) / TODO |
| | Additional command line options (i) | Text field | TODO (no direct key; could map to `extraintf`) |
| | Log format (i) | Dropdown (Plain text) | `logmode` (text/html) |
| | Collect playback statistics (i) | Toggle | `stats` |
| | Open configurations folder (i) | Button "Open" | action (open `config_GetUserDir(VLC_CONFIG_DIR)`) |
| | Reset all settings (i) | Button "Reset" | action (`config_ResetAll` + `config_SaveConfigFile`) |
| Developer Options | Write to the system log (i) | Toggle | `syslog` |
| | Include debug messages in the system log (i) | Toggle | `syslog-debug` |
| | System log identity (i) | Text field | `syslog-ident` |
| | System log facility (i) | Dropdown (User) | `syslog-facility` |

#### Interface: 3046:10057 (collapsed), 3062:11379 (expanded). Title "Interface Settings"
| Section | Label | Control (default) | VLC option |
|---|---|---|---|
| Skin | Use a custom skin (i) | Toggle | `intf` = `skins2` vs `qt` |
| | Skin file (i) | Text field + Browse | `skins2-last` |
| Window | Play video inside main window (i) | Toggle | `embedded-video` |
| | Resize window to fit video (i) | Dropdown (Never) | `qt-video-autoresize` (bool; the design implies Never/Always/...: TODO) |
| | Remember window size and position | Toggle | NEW `qt-remember-geometry` (today QSettings, always on) |
| | Keep window above other windows (i) | Toggle | `video-on-top` |
| | Show window decorations (i) | Toggle | `qt-titlebar` (system title bar vs CSD) / `video-deco` |
| | Show the file name in the title bar (i) | Toggle | `qt-name-in-title` |
| | Open fullscreen on (i) | Dropdown (Current screen) | `qt-fullscreen-screennumber` |
| Playback Controls | Start in compact mode (i) | Toggle | `qt-minimal-view` |
| | Auto-hide the controls (i) | Dropdown (In fullscreen only) | `qt-pin-controls` (inverse) / NEW enum |
| | Hide after | Slider 0 s / 5 s / 10s | `mouse-hide-timeout` (ms) |
| | Show controls in fullscreen (i) | Toggle | `qt-fs-controller` |
| Notifications and System Tray | Show a system tray icon (i) | Toggle | `qt-system-tray` |
| | Start minimized to the tray (i) | Toggle | `qt-start-minimized` |
| | Show a popup when the track changew *(sic: "changes")* (i) | Dropdown (When minimized) | `qt-notification` (0 never, 1 when minimized, 2 always) |
| | Popup duration | Slider 0 s / 5 s / 10s | NEW `qt-notification-duration` |
| Playlist | Show the playlist as a tree (i) | Toggle | `playlist-tree` |
| Advanced | Window opacity | Slider 10% to 100% | `qt-opacity` |
| | Pause video when window is minimized | Toggle | `qt-pause-minimized` |
| | Bring VLC to the front when playback starts (i) | Dropdown (Video) | `qt-auto-raise` (0 never, 1 video, 2 always) |
| | Show cover art in the window when playing audio | Toggle | `qt-bgcone` / TODO |
| | Show the file browser inside the open dialog | Toggle | `qt-embedded-open` |
| | Allow the app icon to change | Toggle | `qt-icon-change` |
| | Fullscreen controls opacity | Slider 10% to 100% | `qt-fs-opacity` |
| | Fullscreen controls sensitivity | Slider Low / Medium / High | `qt-fs-sensitivity` |

#### Privacy: 3062:11911. Title "Privacy Settings"
| Section | Label | Control | VLC option |
|---|---|---|---|
| History | Save recently played items (i) | Toggle | `save-recentplay` |
| | Remember the playback position (i) | Toggle | `restore-playback-pos` (0 never / 1 ask / 2 always; toggle maps to never vs ask/always) |
| | Never remember items matching (i) | Text field | NEW (the old `qt-recentplay-filter` is obsolete) |
| | Clear history now (i) | Button "Clear" | action (clear the recent-media ML list) |
| Network | Fetch titles and cover art from the internet (i) | Toggle | `metadata-network-access` |
| | Submit played tracks to last.fm (i) | Toggle | add `audioscrobbler` to `control` |
| | Last.fm username (i) | Text field | `lastfm-username` |
| | Last.fm username (i) *(duplicate label in the design; should be "Last.fm password")* | Text field (password) | `lastfm-password` |
| | Last.fm submission URL (i) | Text field | `scrobbler-url` |
(No Advanced Options bar on this page.)

#### Controls: 6536:14482. Title "Mouse, Keyboard & Remote Controls"
| Section | Label | Control | VLC option |
|---|---|---|---|
| Keyboard Shortcuts | Defaults | Button 320x32 "Edit Keyboard Shortcuts" | opens the Keyboard Shortcuts dialog (2.6) |
| | Reset all shortcuts | Button "Reset" | action: reset `key-*`/`global-key-*` |
| Skip Amounts | Very short skip | Spin "3 s" | `extrashort-jump-size` |
| | Short skip | Spin "10 s" | `short-jump-size` |
| | Medium skip | Spin "60 s" | `medium-jump-size` |
| | Long skip | Spin "300 s" | `long-jump-size` |
| Mouse | Single click on the video | Dropdown (Play / Pause) | NEW `qt-video-click-action` |
| | Double click on the video | Dropdown (Toggle fullscreen) | NEW `qt-video-dblclick-action` |
| | Scroll wheel | Dropdown (Volume) | `hotkeys-y-wheel-mode` (0 volume, 1 position, 2 none) |
| | Horizontal scroll | Dropdown (Seek) | `hotkeys-x-wheel-mode` |
| | Reverse scroll direction | Toggle | NEW / TODO (`hotkeys-*-wheel-mode` only partly covers it) |
| Remotes | Web remote control | Toggle | add `http` to `extraintf` |
| | Port | Text field | `http-port` |
| | Scroll wheel / Horizontal scroll / Reverse scroll direction | (repeated from Mouse; looks like a copy/paste error in the design) | ignore; architect to confirm |

#### Playback: 3062:12552 (collapsed), 3072:13408 (expanded). Title "Playback Preferences"
| Section | Label | Control (default) | VLC option |
|---|---|---|---|
| Startup | Continue where you left off (i) | Dropdown (Always) | `restore-playback-pos` (Never/Ask/Always) |
| | Start playing as soon as a file opens (i) | Toggle | `start-paused` (inverse) |
| | Default playback speed | Slider with ticks 0.25 0.5 0.75 1 1.25 1.5 1.75 2 | `rate` |
| | Pause when another app uses audio (i) | Toggle | TODO (`role`/OS ducking; no key) |
| Tracks | Preferred video quality (i) | Dropdown (Best available) | `preferred-resolution` |
| | Preferred menu language (i) | Dropdown (English) | `menu-language` |
| | Default audio track (i) | Spin "1" | `audio-track` |
| | Default subtitle track (i) | Spin "1" | `sub-track` |
| Order | Repeat (i) | Dropdown (Off) | `loop` / `repeat` (Off / All / One) |
| | Shuffle (i) | Toggle | `random` |
| | Stop after each item (i) | Toggle | `play-and-stop` |
| | When playback finishes (i) | Dropdown (Stop) | `play-and-exit` / `play-and-pause` (Stop / Pause / Quit) |
| Seeking | Seek precisely (i) | Toggle | `input-fast-seek` (inverse) |
| | Show thumbnail while scrubbing (i) | Toggle | NEW `qt-seek-thumbnail` |
| Files & Discs | Default optical drive (i) | Dropdown (-) | `dvd` (and `vcd`/`cd-audio`) |
| | Repair damaged AVI files (i) | Dropdown (Ask) | `avi-index` |
| | Load matching .mkv files from the same folder (i) | Toggle | `mkv-preload-local-dir` |
| Advanced | Time-shift buffer folder (i) | Text field + Browse | `input-timeshift-path` |
| | Time-shift buffer size (i) | Dropdown (Medium) | `input-timeshift-granularity` |

#### Video: 3073:14187 (collapsed), 3073:15375 (expanded). Title "Video Defaults"
| Section | Label | Control (default) | VLC option |
|---|---|---|---|
| Output | Enable video (i) | Toggle | `video` |
| | Start videos in fullscreen (i) | Toggle | `fullscreen` |
| | Stop the screensaver during playback (i) | Toggle | `disable-screensaver` |
| | Play video as desktop wallpaper (i) | Toggle | `video-wallpaper` |
| Picture | Hue / Brightness / Contrast / Saturation / Gamma | Slider (no ticks, 24 high) | `hue`, `brightness`, `contrast`, `saturation`, `gamma` (adjust filter; enable through `video-filter=adjust`) |
| | Reset picture | Button "Reset" | action |
| Deinterlacing | Deinterlacing (i) | Dropdown (Automatic) | `deinterlace` (-1 auto, 0 off, 1 on) |
| | Method (i) | Dropdown (Automatic) | `deinterlace-mode` |
| Framing | Aspect ratio (i) | Dropdown (Automatic) | `aspect-ratio` |
| | Crop (i) | Dropdown (None) | `crop` |
| | Scale video to the window (i) | Toggle | `autoscale` |
| | Zoom (i) | Dropdown (Fit) | `zoom` |
| | Position in the window (i) | Dropdown (Center) | `align` |
| Snapshots | Save to (i) | Text field + Browse | `snapshot-path` |
| | File name prefix (i) | Text field | `snapshot-prefix` |
| | Format (i) | Dropdown (PNG) | `snapshot-format` |
| | Size (i) | Dropdown (Same as video) | `snapshot-width` / `snapshot-height` |
| | Number files sequentially (i) | Toggle | `snapshot-sequential` |
| | Show a preview after capture (i) | Toggle | `snapshot-preview` |
| Advanced | Custom aspect ratios (i) | Text field | `custom-aspect-ratios` |
| | Custom crop ratios (i) | Text field | `custom-crop-ratios` |
| | Monitor pixel aspect ratio (i) | Text field "1:1" | `monitor-par` |
| | Time-shift buffer size (i) | Dropdown (Medium) | duplicate from Playback; likely a design copy/paste error |

#### Audio: 3073:15879 (collapsed), 3180:17398 (expanded + EQ open). Title "Audio Defaults"
| Section | Label | Control (default) | VLC option |
|---|---|---|---|
| Output | Enable audio (i) | Toggle | `audio` |
| | Output device (i) | Dropdown (System default) | `aout` + per-module device |
| | Speaker setup (i) | Dropdown (Automatic) | `stereo-mode` / `mix-mode` |
| Volume | Maximum volume | Slider ticks 100% 200% 300% | `qt-max-volume` |
| | Startup volume (i) | Two-option list (320x78): "Remember last volume" / "Always starts at:" + field "200%" | `volume-save` + `volume` / `gain` |
| | Volume step (i) | Spin "1" | `volume-step` |
| Loudness | Normalize loudness (i) | Toggle | `audio-filter` += `normvol` (or `ebur128`) |
| | Target level (i) | Spin "1" | `norm-max-level` |
| | Night mode (i) | Toggle | TODO (`compressor` preset) |
| | Replay gain (i) | Dropdown (Off) | `audio-replay-gain-mode` |
| | Replay gain preamp (i) | Spin "0.0" | `audio-replay-gain-preamp` |
| Effects | Equalizer (i) | Toggle | `audio-filter` += `equalizer` |
| | Equalizer preset (i) | EQ component (collapsed 784x36 = preset dropdown; expanded 784x489 = band sliders) | `equalizer-preset`, `equalizer-bands`, `equalizer-preamp` |
| | Two-pass (i) | Toggle | `equalizer-2pass` |
| | Spatial audio (i) | Toggle | `spatialaudio` / `audio-filter` += `spatializer` |
| | Spatial audio mode (i) | Dropdown (Headphone virtualization) | `spatialaudio-headphones` / TODO |
| | Stereo widening (i) | Toggle | `audio-filter` += `stereo_widen` |
| | Compressor (i) | Toggle | `audio-filter` += `compressor` |
| | Pitch shift (i) | Spin "0.00" | `pitch-shift` (scaletempo_pitch) |
| | Chorus/flanger (i) | Toggle | `audio-filter` += `chorus_flanger` |
| | Karaoke (i) | Toggle | `audio-filter` += `karaoke` |
| Tracks | Preferred audio language (i) | Dropdown (System language) | `audio-language` |
| | Audio delay (i) | Spin "0.00" | `audio-desync` |
| Visualization | Visualizer (i) | Audio Visualizer dropdown | `audio-visual` (+ `effect-list`) |
| Advanced | Pass compressed audio to the receiver (i) | Toggle | `spdif` |
| | Detect Dolby Surround (i) | Dropdown (Automatic) | `force-dolby-surround` |
| | Resampling quality (i) | Dropdown (Balanced) | `audio-resampler` / `src-converter-type` |
| | Media role (i) | Dropdown (Video) | `role` |
| | Visualization size (i) | Dropdown (Match window) | `effect-width` / `effect-height` |

#### Subtitles: 3180:17989 (collapsed), 6536:13908 (expanded). Title "Subtitle Defaults"
| Section | Label | Control (default) | VLC option |
|---|---|---|---|
| Tracks & Languages | Enable subtitles (i) | Toggle | `spu` |
| | Preferred language (i) | Dropdown (System language) | `sub-language` |
| | Text encoding (i) | Dropdown (Automatic) | `subsdec-encoding` |
| Loading Subtitles | Load subtitle files automatically (i) | Toggle | `sub-autodetect-file` |
| | File name matching (i) | Dropdown (Title with extra characters) | `sub-autodetect-fuzzy` |
| Appearance | Font (i) | Text field "System, sans-serif" | `freetype-font` |
| | Size values (i) | Segmented (sub filename component; TODO(figma) options) | `freetype-rel-fontsize` vs `freetype-fontsize` |
| | Font size | Dropdown (Automatic) | `freetype-rel-fontsize` |
| | Bold | Toggle | `freetype-bold` |
| | Text color | Color field "#FFFFFF" | `freetype-color` |
| | Text opacity | Slider 0% / 50% / 100% | `freetype-opacity` |
| | Outline thickness | Dropdown (Normal) | `freetype-outline-thickness` |
| | Outline color | Color field "#000000" | `freetype-outline-color` |
| | Shadow | Toggle | `freetype-shadow-opacity` (0 = off) |
| | Shadow color | Color field "#000000" | `freetype-shadow-color` |
| | Shadow distance | Dropdown (Small) | `freetype-shadow-distance` |
| | Background | Dropdown (None) | `freetype-background-opacity` (0 = None) |
| | Background color | Color field "#000000" | `freetype-background-color` |
| | Background opacity | Slider 0% / 50% / 100% | `freetype-background-opacity` |
| | Vertical position | Dropdown (Bottom) | `sub-margin` / `subsdec-align` |
| Timing | Subtitle delay | Slider -5 s / 0 s / +5 s | `sub-delay` |
| On-Screen Messages | Show feedback for shortcuts (i) | Toggle | `osd` |
| | Show feedback for | Slider 0.5 s to 5 s | NEW `qt-osd-duration` (TODO) |
| | Show filename when a video starts (i) | Toggle | `video-title-show` |
| | Show filename for | Slider 1 s to 10 s | `video-title-timeout` |
| Advanced | Load subtitles from these folders (i) | Text field | `sub-autodetect-path` |
| | Ignore styling in ASS and SSA subtitles (i) | Toggle | TODO (libass has no such key; `ssa-*`) |
| | Shadow angle (i) | Spin "0" | `freetype-shadow-angle` |
| | Text direction (i) | Dropdown (Automatic) | `freetype-text-direction` |
| | Monospace font (i) | Text field "System monospace" | `freetype-monofont` |
| | Visualization size (i) | Dropdown (Match window) | copy/paste from Audio; ignore |

#### Library: 6542:15251. Title "Playlists, Folders & Files"
| Section | Label | Control (default) | VLC option |
|---|---|---|---|
| Opening Files | Only allow one VLC window (i) | Toggle | `one-instance` |
| | Apply to files opened from the file manager (i) | Toggle | `one-instance-when-started-from-file` |
| | Add to the playlist instead of replacing it (i) | Toggle | `playlist-enqueue` |
| | When opening a folder (i) | Dropdown (Include subfolders) | `recursive` (none/collapse/expand) |
| | Show hidden files (i) | Toggle | `show-hiddenfiles` |
| Metadata & Artwork | Fetch titles and artwork (i) | Dropdown (From the file only) | `metadata-network-access` (art policy: TODO, no `album-art` key in 4.x) |
| | Use the media library (i) | Toggle | `media-library` |

#### Network: 6543:15649. Title "Network Connections & Security"
| Section | Label | Control | VLC option |
|---|---|---|---|
| Buffering | Buffering (i) | Dropdown (Normal) | preset that writes the four below |
| | Local files | Spin | `file-caching` |
| | Discs | Spin | `disc-caching` |
| | Network streams | Spin | `network-caching` |
| | Live capture | Spin | `live-caching` |
| Proxy | HTTP proxy (i) | Text field "System proxy" | `http-proxy` |
| | HTTP proxy password (i) | Password field | `http-proxy-pwd` |
| Security | Verify certificates against the system trust store (i) | Toggle | `gnutls-system-trust` |
| | Cipher preference (i) | Dropdown (Balanced) | `gnutls-priorities` |

#### Performance: 6571:15958. Title "Performance Settings"
| Section | Label | Control (default) | VLC option |
|---|---|---|---|
| Decoding | Hardware-accelerated decoding (i) | Dropdown (Automatic) | `hw-dec` / `avcodec-hw` |
| | Video post-processing (i) | Dropdown (Off) | `postproc-q` |
| | Skip the H.264 loop filter (i) | Dropdown (Never) | `avcodec-skiploopfilter` |
| | Decoding threads (i) | Spin "0" | `avcodec-threads` |
| Smooth Playback | Drop frames when the system can't keep up | Toggle | `drop-late-frames` (+ `skip-frames`) |
| | Give VLC real-time priority | Toggle | `rt-priority` |
| | Process priority (i) | Spin "0" | `rt-offset` |
| | Rescan plugins | Button 320x32 "Rescan" | `reset-plugins-cache` (action) |
| Developer (shown in advanced) | Encoder (i) | Dropdown (Automatic) | `encoder` |
| | Decoder (i) | Dropdown (Automatic) | `codec` |
| | Clock synchronisation (i) | Dropdown (Default) | `clock-synchro` |
| | Clock jitter (i) | Spin "5000 ms" | `clock-jitter` |
| | Clock reference averaging (i) | Spin "40" | TODO |

#### Recording: 6571:16429. Title "Recording, Casting & Streaming Out"
| Section | Label | Control (default) | VLC option |
|---|---|---|---|
| Recording | Save recordings to (i) | Text field "~/Videos" + Browse | `input-record-path` |
| | Record without re-encoding when possible | Toggle | TODO (`sout-*`; no direct key) |
| Casting | Discover cast devices | Toggle | TODO (renderer discovery `microdns` on/off) |
| | Cast quality (i) | Dropdown (Automatic) | `sout-chromecast-conversion-quality` |
| Streaming | Play locally while streaming | Toggle | `sout-display` |
| | Include audio | Toggle | `sout-audio` |
| | Include video | Toggle | `sout-video` |
| | include subtitles *(sic, lower-case)* | Toggle | `sout-spu` |
| | Encoding preset (i) | Dropdown (Medium) | `sout-x264-preset` |
| | Tuning (i) | Dropdown (None) | `sout-x264-tune` |

#### Extensions: 6575:17137. Title "Add-ons & Scripts"
| Section | Label | Control | VLC option |
|---|---|---|---|
| Add-ons | (search row) | Search field "Find more extensions" (405x32) + buttons "Add", "Remove" | addons manager (`dialogs/plugins`) |
| | Load add-ons on startup | Toggle | `qt-autoload-extensions` |

### 2.4 Onboarding (1090x759 window; 11 frames, in order)

Window: dark (BG/B2 or near-black) with a rounded 12 corner. Bottom-right nav buttons are 100x32 each: "Back" at (820, 671), BG/A4, label 16px FG/A2; "Next" or "Finish" at (928, 671), Accent/Main bg, label 16px semibold FG/B1-ish dark text (screenshot shows dark text on orange).

1. **1899:3055 Welcome**: VLC cone icon 141x141 at (475, 116); "Welcome to VLC!" (32px, centered, y 286); body (16/28, FG/A2, 595 wide at (248, 362), centered): "VLC is a free and open source cross-platform multimedia player and framework that plays most multimedia files as well as DVDs, Audio CDs, VCDs, and various streaming protocols."; "Choose a Media Folder to get started with" (14px) at (248, 500) + text field "~/Videos" (471x36, BG/B2) + "Browse" button (114x35); "Next". No Back. Maps to the `media-library` folder setup (MLFoldersModel). TODO(figma): screenshot.
2. **1902:3670 ... 1902:6465 (9 frames), Theme and color**: a live **mini preview** of the player (1056x594 at (17, 19): title bar, control bar, sidebar) that re-tints with the selection. Title "Select your preferred theme and color." (24/42, centered at y 173). Three theme tiles (116x116 slot, 100x100 rounded about 12 preview inside, label 16px below at +138): "Light" (`#b3b3b3`-ish tile), "Dark" (`#222222`), "System" (diagonal split dark/light). The selected tile has a 4 px Accent/Main ring (r about 16) around the 100 tile. Bottom-left: **9 accent dots** (40x40 circles in 64x64 slots at x 41 + 80*i, y 655); selected = full color with an Accent/Dim ring (64x64 with 4 px gap); others at about 72% brightness. "Back" and "Next". **Each of the 9 frames shows a different accent selected, in swatch order 1..9** (frames ordered by x: 3670, 4020, 4325, 4634, 4940, 5245, 5550, 6160, 6465). Writes `qt-accent-color` and the color scheme. (`onboarding-theme-orange.png`)
3. **1902:6770 Keyboard shortcuts** (last step): title "Learn the basic keyboard shortcuts." (24/42 at y 60); two columns of action labels (16/28) with **key caps** (bordered rounded boxes 42 high, 16/28 text, about 14 px horizontal padding; BG/A3 with Divider/Bright border *(derived)*):
   - Play / Pause: `Space`
   - Seek Backward / Forward: `←` / `→`
   - Previous / Next Item: `<` / `>`
   - Previous / Next Frame: `,` / `.`
   - Cycle Subtitle Track: `V`
   - Cycle Audio Track: `B`
   - Toggle Fullscreen: `F`
   - Increase / Decrease Volume: `↑` / `↓`
   - Show / Hide Queue: `Q`
   - Show / Hide File Browser: `L`
   - Take a Snapshot: `SHIFT` + `S`
   - Record: `SHIFT` + `R`

   Footer: "Find the full list in the menu." (16px, at (62, 671)), "Back", "**Finish**".

Note: these shortcuts differ from current VLC defaults (e.g. Previous/Next item is `p`/`n` today, snapshot is Shift+S, record is Shift+R). **Architect decision:** change the defaults or only show the existing bindings.

Existing counterpart: `dialogs/firstrun/firstrunwizard.cpp/.ui` (Qt Widgets, privacy step). Replace it with a QML onboarding.

### 2.5 Add Subtitles (1048x800; 4 frames)

Header (96 high): title row "Add Subtitles" (14px FG/A1) + close; toolbar row at y 53:
- "**target**" dropdown 200x34 (states: "to this folder" / "to this file", plus open lists `dropdown 1`/`dropdown 2`)
- "**origin**" dropdown 200x34 ("From Computer" / "from opensub", i.e. OpenSubtitles)
- path field 610x34 with folder icon: "Videos / Shows / The Wand / S01"

Footer: "Cancel", "Save".
- **1911:7545 / 3336:11929** (target = folder, origin = From Computer): two panes. Left (519 wide) lists the folder's videos ("The_Wand_S01E01.mp4" ... "The_Wand_S01E15.mp4"), each with a video icon and a dashed/line connector (`Vector 77`, a horizontal line to the right edge) showing which subtitle maps to which file. Right (529 wide) lists 15 "subtitle multiple" rows (479x36; default/hover), one per video. 3336:11929 is the same layout in a different state (TODO(figma)).
- **1919:8707** (origin = from OpenSubtitles?): single-pane list of 6 "subtitle one" rows (1008x36; default/selected) for choosing among downloadable subtitles.
- **1919:9278** (target = file "The Wand S01E01"): adds a language dropdown "English" (200x34) at the right; 2 "subtitle one" results.

Counterpart: none (closest are `dialogs/open` "subtitle" options and the `vlsub` Lua extension). New QML dialog.

### 2.6 Keyboard Shortcuts (2437:14832; 1048x800)

Header: "Keyboard Shortcuts"; toolbar row: search field 820x34 "Search Keyboard Shortcuts..." + filter dropdown 200x34 "All Fields". The table header (14/25, FG/A3) has columns "Action" (x 0, 488 wide), "Hotkey" (x 488), "Global Hotkey" (x 820), then a divider.
- Group "Basic" (16/28 FG/2): Toggle fullscreen `F`; Exit fullscreen / close dialog `esc`; Show playback position and time `T`; Show interface controls in fullscreen `I`.
- Group "Playback": Play / pause `Space`; Stop playback `S`; Next track `N`; Previous track `P`; Next program / Service ID `X`.

Each row is 33 high (14 px gap): the action at x 0 (290 wide); a hotkey cell 270x33 at x 379 with the key centered and an edit/clear icon (24) at the right; a global hotkey cell 270x33 at x 738 (empty + icon). Footer: Cancel / Save.
Counterpart: hotkeys table in `dialogs/preferences/simple_preferences.cpp` (`KeySelectorControl` in `preferences_widgets.cpp`). Options `key-*`, `global-key-*`.

### 2.7 Open Network Stream (6216:13614; 1048x631)

Title "Open Network Stream". "Network URL" (16/28 FG/2) + helper "You can enter multiple links to load." (14/25 FG/A3). Multi-line text area 1008x194 (BG/B2), placeholder "e.g., https://www.example.com/stream.avi". Divider. "Playlist Name (optional)" + helper "The playlist will be saved and displayed with this title." Text field 1008x37 placeholder "e.g., Favorite TV Channels". Footer Cancel / Save.
Counterpart: `dialogs/open/open_net.ui` + `openurl.cpp`. New QML dialog; multiple URLs create an ML playlist when a name is given.

### 2.8 New Playlist (6259:14954; 713x589)

Title "New Playlist". "Playlist Details" + helper "The playlist will be saved and displayed with this title and thumbnail." Text field 541x37 placeholder "e.g., Favorite Videos". Thumbnail picker 112x112 (BG/B2, centered 30x30 add/upload icon) at the right. Divider. "Select Files" + helper "These files will be added to the playlist." Drop zone 673x186 (BG/B2, dashed *(derived)*): "Drag files into the box or click here to select files." + upload icon button 84x30. Footer Cancel / Save.
Counterpart: `dialogs/playlists/playlists.cpp` (widget "Add to playlist"). New QML dialog.

---

## 3. Components

### 3.1 Button (500:3063): exact
- 360x32 in the sheet (hug or fill in practice), r4, horizontal layout, gap 6, centered.
- **Default**: bg BG/B2, icon 20x20 (`settings` in the sample) + label 14px Regular FG/A3. Sample text "Show Advanced Settings".
- **Variant2 (hover)**: bg BG/A4, label FG/A2.
- Footer buttons ("Frame 140"/"Frame 141"): 100x32. Primary (Next/Finish/Save in onboarding) uses Accent/Main bg. Secondary uses BG/A4.

### 3.2 Toggle (536:1014): exact, 68x32
- Track: BG/B2, r6.
- **ON**: left well (3, 3, 33x26, r3) BG/Accent Bright with text "ON" (12px, Accent/Main, centered); knob (39, 3, 26x26, r3) Accent/DIm.
- **OFF**: knob on the **left** (3, 3, 26x26, r3) FG/A4; right well (32, 3, 33x26, r3) BG/A4 with text "OFF" (12px, FG/A3).
- Animate the knob x (3 <-> 39) and the well swap over about 120 ms.

### 3.3 Icon Wrapper (177:98): exact
- 30x32 (or 32x32 for close buttons), padding 4, icon 24. **Default** transparent; **hover** bg `#ffffff/0.06`, r4. Pressed: TODO (suggest `#ffffff/0.10`).

### 3.4 Play button (848:1712): exact, 54x28, r6
- **play**: bg Accent/Main, padding 2/15/2/17, `play` icon 24 in FG/B1.
- **pause**: bg FG/A3 `#6b6b6b`, `pause` icon.

### 3.5 Volume (244:184): exact, 88x28
- Variants 0%, 10%, ... 100%, 150%, 200% (13 states).
- Base shape BG/B2 (a vector: wedge/triangle growing to the right; see the screenshot, where the track is taller at the right).
- Gradient fill rectangle (2, 3, 86x25, r2): linear L to R `#95d318` 0 / `#b2a918` 0.58 / `#d37918` 0.79 / `#ff3737` 1.0, with a `#000000/0.20` overlay.
- Reveal mask `#262626` of width `w = 1 + 87 * (level/200%)`. Pixel widths per state: 1, 7, 14, 20, 26, 33, 41, 48, 53, 58, 63, 75, 88 for 0..100%, 150%, 200%. In effect the gradient is visible from the left up to w and the rest is the base. **Implement as a clip of the gradient to the wedge shape at `level / maxVolume`.**
- Tooltip "audio value" (2245:9805): bubble 121x37 with text "100 %" (14px).

### 3.6 Segmented values (804:1208 and 3176:16556): exact
- Track BG/B2, r6, padding 2, gap 2. Cells r4: unselected BG/A4 + text 14px FG/A3; selected BG/Accent Bright + text Accent/Main.
- 2-option (cells 104x40) and 3-option (cells 68x40) variants. In settings the height is 36 (cells 32).
- **Vertical two-row variant** (3176:16556, 320x78): rows 316x36 (padding 0/12): "Remember last volume" / "Always starts at:" + inline field (182x32, BG/B2, r2, padding 10/18/10/12, text "200%" FG/A2, at 0.40 opacity when its row is not selected).

### 3.7 Settings category (3021:9835)
188x40; selected=no / selected=yes (see 2.3).

### 3.8 Dropdowns (2372:8300 Dropdown, 2372:8834 Setting Preset, 2372:8487 EQ presets, 2372:8639 Audio Visualizer, 2372:8733 HDR Options, 6456:13892 sub filename)
- Each has `state=default` (closed, 364x48 / 362x48 in the sheet; 320x36 in settings) and `state=open` (list below, total heights 369-460).
- Closed: see the Dropdown row in 2.3. Open: popup BG/A3 Transparent + `bg blur + shadow`; option rows (see 3.9).
- **TODO(figma): option lists** (EQ presets presumably list the 18 EQ glyph icons: classical, club, dance, full bass, full bass and treble, full treble, headphones, large hall, live, party, pop, reggae, rock, ska, soft, soft rock, techno, plus a flat/custom entry; HDR Options and Audio Visualizer lists unknown).

### 3.9 Menu option (2107:5935) and menus
Option row: 261x48 (sheet). Icon 24 at x 14, y 12; label 14px FG/A2 at x 48; optional right part: shortcut text (14px FG/A3, right column) **or** chevron-right icon (submenu) at the right edge -38.
States: **Default** (transparent), **hover** (BG/A1 or `#ffffff/0.06`, TODO exact), **selected** (accent text/icon, e.g. the current sort key).
Menus: container padding 4, BG/A3 Transparent + `bg blur + shadow`, r about 8; separators 1 px Divider/Dim spanning the menu width.

**Main menu** ("menu" 6062:13354, 375x585; opened from the title bar `...`), verbatim:
| Icon | Label | Right |
|---|---|---|
| file | Open File(s) | Ctrl + O |
| folder | Open Folder | Ctrl + F |
| link/streaming | Open Network Stream | Ctrl + N |
| disc | Open Disc | Ctrl + D |
| capture-device | Open Capture Device | Ctrl + C |
| (convert) | Convert | Ctrl + R |
| recent | Open Recent | > (submenu) |
| *separator* | | |
| profile | Profile (Movies) | > (submenu: profiles; see "Profiles" 6648:20666 where a 265-wide submenu with 5 options and a separator opens at (386, 337); TODO(figma) item labels) |
| hotkeys | Keyboard Shortcuts | > |
| paint/ui | Customize Player | > |
| settings | Settings | Ctrl + P |
| info/vlc | About VLC | Shift + F1 |

**Right-click menu on the video** ("right-click menu" 6065:13616, 292x683), verbatim:
| Label | Right |
|---|---|
| Play | Space |
| Stop | S |
| Previous Item | P |
| Next Item | N |
| Record | R |
| *separator* | |
| Hide UI | Ctrl + \ |
| *separator* | |
| Playback | > |
| Video | > |
| Audio | > |
| Subtitle | > |
| *separator* | |
| More Settings | > |
| Playlist | > |
| Open Media | > |
| Quit VLC | Ctrl + Q |

**Instance-based menus (labels TODO(figma); sizes exact):**
- Sorting Options (856:2215): 16 options (257x48) in a 265x776 panel. Probably sort keys (Name, Duration, Date added, ... with an ascending/descending pair). Selected = current key.
- View Options (858:3290): 2 options (Grid / List).
- context menu (2107:5903): 6 options. folder context menu (2139:8935): 6 options. file context menu (2404:13340): 12 options. playlist context menu (2459:9389): 8 options.

### 3.10 Time display: Current Time (1904:7238), Duration (1905:7312)
76x28. Current Time states: Default / hover / click (pressed). Duration states: Default / click (toggles elapsed vs remaining, as in VLC today). Text 14px FG/A2 "00:02:10". Hover bg presumably `#ffffff/0.06` r4.

### 3.11 Thumbnail / seek preview (2151:9673)
272x189 card (BG/A3 Transparent, r about 8): image 252x142 at (10, 10) and time "00:02:10" (14px) centered at y 162. Shows above the seek bar on hover (controlled by "Show thumbnail while scrubbing").

### 3.12 Side panel list rows
- **media** (2404:9167), 337x32: watched / unwatched / hover-watched / hover-unwatched. Thumbnail 24x24 + filename 14px. Watched = normal FG/A2 with an accent progress tick on the thumbnail; unwatched = FG/A3 (dimmed). Hover adds the row bg.
- **playlist** (2459:9352), 337x32: unwatched / hover-unwatched (playlist icon + name).

### 3.13 sidebar (848:1996), 427x986 per variant
Variants: Default, home, videos, videos2, videos3, music, music2, music3, network, playlists. Each is the rail (active icon accent) + the panel content for that section (videos/music have 3 drill-down levels). Panel header pattern: back, forward, title or breadcrumb, `...`, pop-out (open in main view); then a count ("N items") + sort, view, search; then a divider (Divider/Dim) at about y 105.

### 3.14 Controls (491:1780), 1920x54 control-bar variants
default, Variant10, waveform (music seek), music, queue, bookmarks, chapters, subtitles, playback, sub timeline, audio, video, video settings, audio settings, subtitle settings. Each non-default variant has a **popup panel above the bar** (that is why the symbols are spaced about 1000 px apart in the sheet): queue = playlist popup; audio/video/subtitles = track pickers; "video settings"/"audio settings"/"subtitle settings" = the effects panels (3.15); playback = speed etc.; bookmarks/chapters = lists; sub timeline = subtitle sync. **TODO(figma): popup contents.**

### 3.15 Effects panels (360 wide; collapsed 48 / expanded)
Audio - Compressor Settings (expanded 590), Audio - Equalizer (1048), Audio - Spatializer Settings (438), Audio - Stereo Widener (362), Video - Essential (666), Video - Crop (152), Video - Colors (755). Collapsed = header row with title + toggle/chevron. Expanded = slider list. TODO(figma): slider labels (map them to `compressor-*`, `equalizer-*`, `spatializer-*`, `stereowiden-*`, `adjust` keys, crop, etc.).

### 3.16 EQ (3178:16769)
Default 784x36 (preset row) / Variant2 784x489 (bands expanded). Bands are presumably 10 (60 Hz ... 16 kHz) plus preamp: TODO(figma).

### 3.17 Subtitle rows, target and origin (Add Subtitles)
"subtitle multiple" 479x36 default/hover; "subtitle one" 479x36 default/selected; "target" 200x34 (to this folder / to this file / dropdown 1 / dropdown 2); "origin" 200x34 (from computer / from opensub / dropdown 1 / dropdown 2).

---

## 4. Mapping: Figma to VLC Qt code

| Figma | Existing VLC implementation | Notes / new files |
|---|---|---|
| Color tokens, accent derivation | `style/systempalette.cpp/.hpp`, `style/systempalettethemeprovider.cpp`, `style/colorcontext.cpp/.hpp`, `style/VLCStyle.qml` | Replace the Day/Night palette values with section 1.1. Derive accent tints per 1.3 from `qt-accent-color`. Add the 9 presets. |
| Typography, radii, sizes | `style/VLCStyle.qml` (`fontSize_*`, `icon_*`, `globalToolbar_height`=40 OK, `controlLayoutHeight` 64 -> **54**, margins) | Inter font: bundle and register in `qt.cpp`/`mainctx` (decision). |
| Icons (208) | `pixmaps/VLCIcons.json` + `VLCIcons.ttf` (icon font built by `pixmaps/makeIconFont.py`), `style/vlcicons.cpp/.hpp` | Feed the exported SVGs into `makeIconFont.py`; keep the `VLCIcons.*` names. Two-tone icons need 2 glyph layers or SVG `Image`. |
| Title bar | `maininterface/qml/MainDisplay.qml`, `LocalTopbar.qml`, `MenuTopbar.qml`, `widgets/qml/CSDWindowButtonSet.qml`, `CSDWindowButton.qml`, `BannerCone.qml`; player: `player/qml/TopBar.qml` | One unified 40 px bar in both library and player. |
| Nav rail / nav pane | `maininterface/qml/SideNavigationPane.qml`, `SideNavigationDelegate.qml`, `maininterface/navigationmodel.cpp` | Collapsed (50, icons) and expanded (200, labels) modes; entries Home, Videos, Music, Network, Playlists, Recent, Add Item. |
| Library pages (Home, grid, list, breadcrumb, sort, view, search) | `medialibrary/qml/HomePage.qml`, `HomeDisplay.qml`, `VideoDisplay.qml`, `VideoAll*.qml`, `VideoGridItem.qml`, `VideoListDisplay.qml`, `MusicDisplay.qml`, `AudioGridItem.qml`, `PlaylistMedia*.qml`; `network/qml/BrowseDisplay.qml`, `NetworkAddressbar.qml`; `widgets/qml/SearchBox.qml`, `SortControl.qml`, `GridSortFilterControls.qml`, `ViewHeader.qml`, `GridItem.qml`, `ExpandGridView.qml`, `ListViewExt.qml`, `VideoProgressBar.qml` | Card sizes and gaps from 1.5; watched dimming + accent progress. |
| Player side panel ("sidebar") | `player/qml/Player.qml` (playlist pane), `playlist/qml/PlaylistPane.qml`, `PlaylistDelegate.qml` | New: a left-docked library browser inside the player (rail + 377 panel). Today the pane is right-docked and playlist-only, so this needs a new `player/qml/PlayerSidePanel.qml` reusing the ML views. |
| Control bar | `player/qml/ControlBar.qml`, `PlayerControlLayout.qml`, `ControlLayout.qml`, `SliderBar.qml`, `controlbarcontrols/*` (`PlayButton`, `VolumeWidget`, `PlaybackSpeedButton`, `SkipBackButton`, `SkipForwardButton`, ...) | Play pill, seek bar, wedge volume, time labels. `HighResolutionTimeWidget` for time. |
| Waveform seek (music) | none | New `player/qml/WaveformSlider.qml`. Needs waveform data (decode peaks; architect decision). |
| Seek preview thumbnail | `widgets/qml/PointingTooltip.qml` + `SliderBar.qml` | New preview needs a thumbnailer (`vlc_preparser` thumbnails). |
| Music player | `player/qml/Player.qml` (audio cover / `PlayCover`), `widgets/qml/BlurEffect`/`FrostedGlassEffect.qml`, `DualKawaseBlur.qml` | Large artwork + blurred backdrop. |
| Continue toast | `player/qml/ResumeDialog.qml` | Restyle to 519x52 pill. |
| Hide UI | `player/qml/PlayerToolbarVisibilityFSM.qml`, `MinimalView.qml` | Ctrl+\ toggles. |
| Miniplayer card | `player/qml/MiniPlayer.qml`, `PIPPlayer.qml` | The current MiniPlayer is a bottom bar. New floating card + queue + dock left/right. |
| Customize Player | `dialogs/toolbar/qml/ToolbarEditorDialog.qml`, `ToolbarEditor.qml`, `EditorDNDView.qml`, `ToolbarEditorButtonList.qml`, `dialogs/toolbar/controlbar_profile*.cpp` | Restyle as an in-window modal with a palette grid; add the new control types (Forward/Backward 10s/15s, Picture in Picture, HDR, Zoom, Right Sidebar, Go Home, Thumbnail, File/Artist/Folder/Playlist Name, Properties, Replay, Chapters, Favorite, Bookmark(s), Playlists, Divider). |
| Main menu (`...`) | `menus/menus.cpp` (`VLCMenuBar`), `menus/qml/Menubar.qml`, `util/qml/NativeMenu.qml`, `menus/qml_menu_wrapper.cpp` | Restyled QML popup menu (new `widgets/qml/MenuExt.qml` / `MenuItemExt.qml`). |
| Right-click menu | `menus/menus.cpp` (`PopupMenu`) | QML version with the item list in 3.9. |
| Context menus (file, folder, playlist), sort/view menus | `medialibrary/qml/MLContextMenu.qml`, `menus/qml_menu_wrapper.cpp` (`*ContextMenu`), `widgets/qml/SortControl.qml` | Items TODO(figma). |
| Settings window | `dialogs/preferences/preferences.cpp`, `simple_preferences.cpp`, `sprefs_*.ui`, `complete_preferences.cpp`, `expert_*` | **No QML counterpart.** New `dialogs/preferences/qml/SettingsDialog.qml`, `SettingsPage*.qml`, plus generic `SettingRow.qml`, `SettingToggle.qml`, `SettingDropdown.qml`, `SettingSlider.qml`, `SettingSegmented.qml`, `SettingPathField.qml`, and a C++ `ConfigModel` bridging `config_*` (pattern: `util/` or `dialogs/preferences/`). Keep `complete_preferences` reachable for the "all options" view. |
| Toggle | `widgets/qml/CheckButton.qml` | Restyle to 68x32 ON/OFF toggle. |
| Dropdown | `widgets/qml/ComboBoxExt.qml` | Restyle. |
| Segmented | none | New `widgets/qml/SegmentedControl.qml`. |
| Slider with ticks | `widgets/qml/SliderExt.qml` | Add tick labels. |
| Spin / text fields | `widgets/qml/SpinBoxExt.qml`, `TextFieldExt.qml` | Restyle. |
| Button | `widgets/qml/ButtonExt.qml`, `TextToolButton.qml` | Default / hover / primary-accent. |
| Icon button (Icon Wrapper) | `widgets/qml/IconToolButton.qml`, `IconButton.qml` | Hover `#ffffff0f`. |
| Tooltip (info icon) | `widgets/qml/ToolTipExt.qml` | Text = option LONGTEXT. |
| Onboarding | `dialogs/firstrun/firstrunwizard.cpp/.ui/.hpp` (Widgets) | Replace with a QML wizard `dialogs/firstrun/qml/Onboarding.qml` (Welcome+folder, Theme+accent with live preview, Shortcuts). Show when `qt-privacy-ask` is true (rename semantics). |
| Add Subtitles | none | New `dialogs/subtitles/qml/AddSubtitlesDialog.qml` + model; OpenSubtitles origin is a new backend (or reuse the vlsub Lua). |
| Keyboard Shortcuts | `dialogs/preferences/preferences_widgets.cpp` (`KeySelectorControl`) | New QML `dialogs/preferences/qml/ShortcutsDialog.qml` with a hotkeys model. |
| Open Network Stream | `dialogs/open/open_net.ui`, `openurl.cpp` | New QML dialog. |
| New Playlist | `dialogs/playlists/playlists.cpp` | New QML dialog using `MLPlaylistListModel`. |
| Effects panels, EQ | `dialogs/extended/extended_panels.cpp`, `equalizer.ui`, `video_effects.ui`; `player/qml/TracksPage*.qml` | New QML panels in control-bar popups. |
| Track popups (audio/subtitle/video, speed) | `player/qml/TracksMenu.qml`, `TracksPage.qml`, `TracksPageAudio.qml`, `TracksPageSubtitle.qml`, `TracksPageSpeed.qml`, `PlaybackSpeed.qml` | Restyle to the Controls variants. |

---

## 5. Reference screenshots

In `design/reference/` (copied from the screenshots taken before the quota ran out; downscaled, see sizes):
| File | Frame | Size |
|---|---|---|
| `player-247-445.png` | 247:445 Player | 1400x788 |
| `player-187-328.png` | 187:328 Player (side panel, playlists) | 1400x788 |
| `player-970-2703.png` | 970:2703 (grid + miniplayer right) | 1000x563 |
| `player-970-3308.png` | 970:3308 (list + miniplayer right) | 1000x563 |
| `player-970-3792.png` | 970:3792 (list + miniplayer left) | 1000x563 |
| `player-970-4028.png` | 970:4028 (grid, no miniplayer) | 1000x563 |
| `player-6261-15078.png` | 6261:15078 (Home) | 1000x563 |
| `player-music-4767-23726.png` | 4767:23726 | 1400x788 |
| `player-hide-ui-3328-11554.png` | 3328:11554 | 1000x563 |
| `player-light-2425-13624.png` | 2425:13624 | 1400x788 |
| `player-customize-2107-5604.png` | 2107:5604 (first customize step; mapping inferred) | 1000x563 |
| `settings-global-999-5047.png` | 999:5047 | 1078x895 (frame + shadow) |
| `onboarding-theme-orange.png` | an onboarding theme frame with orange selected (1902:3670 or 1902:4020) | 1114x783 |
| `component-miniplayer-970-3091.png` | 970:3091 Miniplayer variants | 154x1000 |

The mapping of the p2-p6 screenshots to 970:2703 / 970:3308 / 970:3792 / 970:4028 / 6261:15078 assumes they were captured in list order. Confirm it when re-exporting at maxDimension 1920.

**Missing (TODO(figma)):** 4778:25123; 2160:6137, 2160:6564, 2160:7005, 2160:7437, 2160:7869, 6587:19923, 2160:8301, 2160:8732; all settings pages except 999:5047 (3046:9282, 3046:10057, 3062:11379, 3062:11911, 3062:12552, 3072:13408, 3073:14187, 3073:15375, 3073:15879, 3180:17398, 3180:17989, 6536:13908, 6536:14482, 6542:15251, 6543:15649, 6571:15958, 6571:16429, 6575:17137); all Add Subtitles frames; Keyboard Shortcuts; Open network stream; New playlist; onboarding 1899:3055, 1902:6770 and the remaining accent variants; all component sheets except Miniplayer.

---

## 6. Follow-up extraction recipe (when Figma quota is available)

1. Icons: for each batch of about 12 ids from `design/icons/manifest.json`, run in `use_figma`: `for id of ids: out[id] = await (await figma.getNodeByIdAsync(id)).exportAsync({format:'SVG_STRING'})`. Return values must stay under 20 KB. Write each result to `design/icons/<file>`.
2. Screenshots: `get_screenshot(nodeId, maxDimension=1920)` for 1920x1080 frames; native size for the others. Save as `design/reference/<sanitized-name>-<id>.png`.
3. Instance texts: run a `use_figma` dump that walks `INSTANCE` children and returns `characters` for the menu frames (856:2215, 858:3290, 2107:5903, 2139:8935, 2404:13340, 2459:9389), the dropdown "open" variants (2372:*, 6456:13895), Controls (491:1780) and the effects panels.
4. Assets: `download_assets` on the cone instance in the title bar (e.g. 4767:23731) as SVG, the folder placeholder cards on Home, and the artwork rounded rectangles (4777:24034, 4777:24028) for raw images.
