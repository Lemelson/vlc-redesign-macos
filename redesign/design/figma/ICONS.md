# Icon catalog (Figma component set `Icon`, node 42:356)

Generated from `figma_file.json` (component set children, their vector paints, and every INSTANCE of them in the 104 other top-level frames) and `icons-svg/index.json`. Design: VLC Redesign by Juxtopposed, Figma community file https://www.figma.com/community/file/1691465999134370980, CC BY 4.0.

- Variants in Figma: **208** (all 24×24 COMPONENTs). SVGs in `icons-svg/`: **206** (index.json `count` = 206). Variants used by at least one visible instance: **159**; unused: **49**.
- Variant axes in Figma: `name`, `direction` (left/right/up/down), `state` (default / active / selected), `value` (volume or thumbnail level), `EQ` (equalizer preset curve), `two-tone` (yes/no).
- **mono** = functional, clickable icon: strokes `Dark/FG/A2` #8F8F8F, 1.5 px. **active** = orange `Dark/Accent/Main` (often filled, 2 px strokes). **two-tone** = decorative menu icon: gray `FG/A2` strokes + accent part in `Dark/Accent/DIm` #AB6314 (not Accent/Main). **selected** = variant used for the current item in the library rail / menus.
- *Shape* is computed from the vectors: outline = strokes only, filled = fills only, outline+fill = both. *Colors* lists the styles (or raw hex) painted.
- *Used in* lists top-level frames that contain a visible instance (×N = number of frames with that name); `[Name]` = only inside that component set definition (and therefore everywhere that component is placed). Frame ids: see `INDEX.md`.
- File names follow `icons-svg/index.json`; when two variants share a name and props, the second file carries the node id (e.g. `album-6206-13653.svg`).

## Missing from icons-svg

| Icon | Node | Used in | Note |
|---|---|---|---|
| check | 494:2400 | Profiles, Sorting Options, View Options, context menu, file context menu, folder context menu, menu, playlist context menu, [Controls], [option], [origin], [sub filename], [target] | Plain (unselected) check glyph. It is the trailing slot of the `option` menu row component, so it appears in every menu/dropdown; it is drawn in Dark/FG/A2. Export it (only `check-active`, `check-selected`, `check-selected-two-tone` exist as SVG). |
| 0 | 2107:6596 | Player - customize ×9, Profiles, context menu, [Audio Visualizer], [Dropdown], [EQ presets], [HDR Options], [Setting Preset], [option], [sub filename] | Empty 24×24 placeholder (no artwork). Used as the blank leading/trailing slot in menu rows, dropdown options and Customize tiles. Implement as an empty spacer; no SVG needed. |

No other icon artwork is referenced outside the `Icon` set: a scan for loose vectors (6–48 px, outside any INSTANCE) in all screens found none. The VLC cone in the top bar is the `vlc` variant; thumbnails use the `thumbnail` variants. Note that some product imagery (cover art, video stills, cat placeholder) are IMAGE fills, not icons.

## All variants

| Icon | Tone | Variant | Shape | Colors | SVG file | Node | Used in |
|---|---|---|---|---|---|---|---|
| 0 | mono | default | empty |  | **MISSING** | 2107:6596 | Player - customize ×9, Profiles, context menu, [Audio Visualizer], [Dropdown], [EQ presets], [HDR Options], [Setting Preset], [option], [sub filename] |
| accessibility | mono | default | outline+fill | FG/A2 | `accessibility.svg` | 999:4914 | — |
| add | mono | default | outline | FG/A2 | `add.svg` | 463:550 | Onboarding ×9, Player ×7, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI, Profiles, folder context menu, new playlist, [Controls], [Miniplayer], [Setting Preset], [sidebar] |
| album | mono | default | outline+fill | FG/A2 | `album.svg` | 6206:13629 | [sidebar] |
| album | mono | default | outline+fill | Accent/DIm, FG/A2 | `album-6206-13653.svg` | 6206:13653 | — |
| arrow | mono | direction=down | outline | FG/A2 | `arrow-down.svg` | 71:881 | — |
| arrow | two-tone | direction=down | outline | Accent/DIm, FG/A2 | `arrow-down-two-tone.svg` | 2461:9739 | — |
| arrow | mono | direction=up | outline | FG/A2 | `arrow-up.svg` | 71:884 | — |
| arrow | two-tone | direction=up | outline | Accent/DIm, FG/A2 | `arrow-up-two-tone.svg` | 2461:9744 | — |
| arrow | mono | direction=right | outline | FG/A2 | `arrow-right.svg` | 71:887 | Onboarding ×9, Player ×7, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI, [sidebar] |
| arrow | two-tone | direction=right | outline | Accent/DIm, FG/A2 | `arrow-right-two-tone.svg` | 2461:9749 | file context menu |
| arrow | mono | direction=left | outline | FG/A2 | `arrow-left.svg` | 71:890 | Onboarding ×9, Player ×7, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI, [sidebar] |
| arrow | two-tone | direction=left | outline | Accent/DIm, FG/A2 | `arrow-left-two-tone.svg` | 2461:9754 | — |
| artist | mono | default | outline+fill | FG/A2 | `artist.svg` | 858:5155 | Player ×3, [Miniplayer], [sidebar] |
| artist | mono | state=active | outline+fill | Accent/Main | `artist-active.svg` | 858:5164 | — |
| audio | mono | default | outline | FG/A2 | `audio.svg` | 44:407 | Onboarding ×9, Player ×2, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI, Settings - controls, Settings - extensions, Settings - global ×2, Settings - interface ×2, Settings - library, Settings - network, Settings - performance, Settings - playback ×2, Settings - privacy, Settings - recording, Settings - subtitles ×2, Settings - video ×2, [Controls] |
| audio | two-tone | default | outline | Accent/DIm, FG/A2 | `audio-two-tone.svg` | 2461:9697 | file context menu, folder context menu, playlist context menu, right-click menu, [Controls] |
| audio | mono | state=active | outline | Accent/Main | `audio-active.svg` | 496:2439 | Settings - audio ×2, [Controls] |
| backward-10-sec | mono | default | outline+fill | FG/A2 | `backward-10-sec.svg` | 45:28 | Player - customize ×7 |
| backward-15-sec | mono | default | outline+fill | FG/A2 | `backward-15-sec.svg` | 45:36 | Player - Music ×2, Player - customize ×7, [Controls] |
| bookmark | mono | default | outline | FG/A2 | `bookmark.svg` | 2127:7779 | Player - customize ×7 |
| bookmarks | mono | default | outline | FG/A2 | `bookmarks.svg` | 2127:7548 | Player - customize ×7, [Controls] |
| bookmarks | two-tone | default | outline | Accent/DIm, FG/A2 | `bookmarks-two-tone.svg` | 6320:13921 | [Controls] |
| capture-device | mono | default | outline | FG/A2 | `capture-device.svg` | 2493:9307 | — |
| capture-device | two-tone | default | outline | Accent/DIm, FG/A2 | `capture-device-two-tone.svg` | 2493:9342 | Profiles, menu |
| chapters | mono | default | outline+fill | FG/A2 | `chapters.svg` | 2127:7531 | Player - customize ×7, [Controls] |
| chapters | two-tone | default | outline+fill | Accent/DIm, FG/A2 | `chapters-two-tone.svg` | 6321:14144 | [Controls] |
| check | mono | state=active | outline | Accent/Main | `check-active.svg` | 494:2394 | Add Subtitles to Playlist/Folder ×2, Profiles, Sorting Options, View Options, [Audio Visualizer], [Controls], [Dropdown], [EQ presets], [HDR Options], [Setting Preset], [option], [origin], [sub filename], [subtitle one], [target] |
| check | mono | state=selected | outline | FG/A2 | `check-selected.svg` | 2428:14606 | — |
| check | two-tone | state=selected | outline | Accent/DIm, FG/A2 | `check-selected-two-tone.svg` | 4004:12348 | file context menu |
| check | mono | default | empty |  | **MISSING** | 494:2400 | Profiles, Sorting Options, View Options, context menu, file context menu, folder context menu, menu, playlist context menu, [Controls], [option], [origin], [sub filename], [target] |
| chevron | mono | direction=down | outline | FG/A2 | `chevron-down.svg` | 71:868 | Add Subtitles to Playlist/Folder ×4, Keyboard Shortcuts, Settings - audio ×2, Settings - controls, Settings - global ×2, Settings - interface ×2, Settings - library, Settings - network, Settings - performance, Settings - playback ×2, Settings - recording, Settings - subtitles ×2, Settings - video ×2, [Audio - Compressor Settings], [Audio - Equalizer], [Audio - Spatializer Settings], [Audio - Stereo Widener], [Audio Visualizer], [Controls], [Dropdown], [EQ], [EQ presets], [HDR Options], [Video - Colors], [Video - Crop], [Video - Essential], [origin], [sub filename], [target] |
| chevron | mono | direction=up | outline | FG/A2 | `chevron-up.svg` | 71:872 | [Controls], [Setting Preset] |
| chevron | mono | direction=right | outline | FG/A2 | `chevron-right.svg` | 71:875 | Player, Profiles, Settings - audio, Settings - controls, Settings - extensions, Settings - global, Settings - interface, Settings - library, Settings - network, Settings - playback, Settings - recording, Settings - subtitles, Settings - video, menu, right-click menu, [Audio - Compressor Settings], [Audio - Equalizer], [Audio - Spatializer Settings], [Audio - Stereo Widener], [Controls], [Video - Colors], [Video - Crop], [Video - Essential], [sidebar] |
| chevron | mono | direction=left | outline | FG/A2 | `chevron-left.svg` | 71:878 | — |
| close | mono | value=medium | outline | FG/A2 | `close-medium.svg` | 182:187 | — |
| close | mono | value=low | outline | FG/A2 | `close-low.svg` | 182:193 | — |
| close | mono | value=none | outline | FG/A2 | `close-none.svg` | 182:198 | — |
| close | mono | default | outline | FG/A2 | `close.svg` | 45:40 | Add Subtitles to Playlist/Folder ×4, Keyboard Shortcuts, Onboarding ×9, Open network stream, Player ×7, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI, Settings - audio ×2, Settings - controls, Settings - extensions, Settings - global ×2, Settings - interface ×2, Settings - library, Settings - network, Settings - performance, Settings - playback ×2, Settings - privacy, Settings - recording, Settings - subtitles ×2, Settings - video ×2, new playlist, [Miniplayer] |
| collapse-sidebar | mono | default | outline+fill | FG/A2 | `collapse-sidebar.svg` | 858:5703 | — |
| disc | two-tone | default | outline+fill | Accent/DIm, FG/A2 | `disc-two-tone.svg` | 2460:9552 | Profiles, menu |
| disc | mono | default | outline+fill | FG/A2 | `disc.svg` | 5884:24330 | — |
| divider | mono | default | outline | #373737 | `divider.svg` | 71:863 | Player ×2, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI |
| edit | mono | default | outline | FG/A2 | `edit.svg` | 2437:14888 | Keyboard Shortcuts, [Controls] |
| EQ | mono | default | outline | FG/A2 | `eq.svg` | 2372:8559 | [EQ presets] |
| EQ | mono | EQ=classical | outline+fill | Accent/Main, FG/A2 | `eq-classical.svg` | 2372:8571 | [EQ presets] |
| EQ | mono | EQ=club | outline+fill | Accent/Main, FG/A2 | `eq-club.svg` | 2372:8578 | [EQ presets] |
| EQ | mono | EQ=dance | outline+fill | Accent/Main, FG/A2 | `eq-dance.svg` | 2372:8588 | [EQ presets] |
| EQ | mono | EQ=full bass | outline+fill | Accent/Main, FG/A2 | `eq-full-bass.svg` | 6114:13932 | [EQ presets] |
| EQ | mono | EQ=full bass and treble | outline+fill | Accent/Main, FG/A2 | `eq-full-bass-and-treble.svg` | 6114:13938 | [EQ presets] |
| EQ | mono | EQ=full treble | outline+fill | Accent/Main, FG/A2 | `eq-full-treble.svg` | 6114:13944 | [EQ presets] |
| EQ | mono | EQ=headphones | outline+fill | Accent/Main, FG/A2 | `eq-headphones.svg` | 6114:13955 | [EQ presets] |
| EQ | mono | EQ=rock | outline+fill | Accent/Main, FG/A2 | `eq-rock.svg` | 6114:13996 | [EQ presets] |
| EQ | mono | EQ=ska | outline+fill | Accent/Main, FG/A2 | `eq-ska.svg` | 6114:14002 | [EQ presets] |
| EQ | mono | EQ=soft | outline+fill | Accent/Main, FG/A2 | `eq-soft.svg` | 6114:14008 | [EQ presets] |
| EQ | mono | EQ=techno | outline+fill | Accent/Main, FG/A2 | `eq-techno.svg` | 6114:14021 | [EQ presets] |
| EQ | mono | EQ=soft rock | outline+fill | Accent/Main, FG/A2 | `eq-soft-rock.svg` | 6114:14014 | [EQ presets] |
| EQ | mono | EQ=large hall | outline+fill | Accent/Main, FG/A2 | `eq-large-hall.svg` | 6114:13961 | [EQ presets] |
| EQ | mono | EQ=reggae | outline+fill | #D37918, FG/A2 | `eq-reggae.svg` | 6114:13967 | [EQ presets] |
| EQ | mono | EQ=pop | outline+fill | #D37918, Accent/Main, FG/A2 | `eq-pop.svg` | 6114:13985 | [EQ presets] |
| EQ | mono | EQ=party | outline+fill | Accent/Main, FG/A2 | `eq-party.svg` | 6114:13979 | [EQ presets] |
| EQ | mono | EQ=live | outline+fill | Accent/Main, FG/A2 | `eq-live.svg` | 6114:13973 | [EQ presets] |
| expand-sidebar | mono | default | outline+fill | FG/A2 | `expand-sidebar.svg` | 858:5697 | — |
| favorite | mono | default | outline | FG/A2 | `favorite.svg` | 2430:14629 | Player - customize ×8 |
| favorite | two-tone | default | outline | Accent/DIm | `favorite-two-tone.svg` | 2511:9352 | file context menu, playlist context menu |
| favorite | mono | state=active | outline+fill | Accent/Main | `favorite-active.svg` | 2430:14666 | — |
| file | mono | default | outline | FG/A2 | `file.svg` | 2107:6307 | — |
| file | two-tone | default | outline+fill | Accent/DIm, FG/A2 | `file-two-tone.svg` | 2461:9644 | Profiles, menu, right-click menu |
| folder | mono | default | outline | FG/A2 | `folder.svg` | 51:808 | Add Subtitles to Playlist/Folder ×3, Player ×6, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI, Settings - audio ×2, Settings - controls, Settings - extensions, Settings - global ×2, Settings - interface ×2, Settings - network, Settings - performance, Settings - playback ×2, Settings - privacy, Settings - recording, Settings - subtitles ×2, Settings - video ×2, [Miniplayer], [sidebar] |
| folder | two-tone | default | outline | Accent/DIm, FG/A2 | `folder-two-tone.svg` | 2461:9734 | Profiles, file context menu, menu |
| folder | mono | state=active | outline+fill | Accent/Main | `folder-active.svg` | 87:1031 | Settings - library |
| folder | mono | state=selected | outline+fill | FG/A2 | `folder-selected.svg` | 467:502 | — |
| forward-10-sec | mono | default | outline+fill | FG/A2 | `forward-10-sec.svg` | 45:22 | Player - customize ×7 |
| forward-15-sec | mono | default | outline+fill | FG/A2 | `forward-15-sec.svg` | 45:32 | Player - Music ×2, Player - customize ×7, [Controls] |
| fullscreen | mono | default | outline | FG/A2 | `fullscreen.svg` | 48:54 | Onboarding ×9, Player ×7, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI |
| fullscreen | mono | state=active | outline | FG/A2 | `fullscreen-active.svg` | 6031:13553 | — |
| genre | mono | default | outline+fill | FG/A2 | `genre.svg` | 6191:13585 | [sidebar] |
| genre | two-tone | default | outline+fill | Accent/DIm, FG/A2 | `genre-two-tone.svg` | 6202:13602 | — |
| grid | mono | default | outline | FG/A2 | `grid.svg` | 2107:6523 | Player ×3, View Options |
| HDR | mono | default | outline+fill | FG/A2 | `hdr.svg` | 2146:9032 | Player - customize ×7 |
| home | mono | default | outline+fill | FG/A2 | `home.svg` | 70:828 | Onboarding ×9, Player ×6, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI, [sidebar] |
| home | mono | state=active | outline+fill | #8F8F8F, #D37918, Accent/Main | `home-active.svg` | 87:1026 | Player, [sidebar] |
| home | mono | state=selected | outline+fill | #8F8F8F, #D37918, FG/A2 | `home-selected.svg` | 470:597 | — |
| hotkeys | mono | default | outline | FG/A2 | `hotkeys.svg` | 1089:4450 | Settings - audio ×2, Settings - extensions, Settings - global ×2, Settings - interface ×2, Settings - library, Settings - network, Settings - performance, Settings - playback ×2, Settings - privacy, Settings - recording, Settings - subtitles ×2, Settings - video ×2 |
| hotkeys | two-tone | default | outline | Accent/DIm, FG/A2 | `hotkeys-two-tone.svg` | 2493:9253 | Profiles, menu |
| hotkeys | mono | state=active | outline+fill | Accent/Main, FG/A2 | `hotkeys-active.svg` | 1089:4464 | Settings - controls |
| info | mono | default | outline | FG/A2 | `info.svg` | 2139:8985 | Player - customize ×7, Settings - audio ×2, Settings - global ×2, Settings - interface ×2, Settings - library, Settings - network, Settings - performance, Settings - playback ×2, Settings - privacy, Settings - recording, Settings - subtitles ×2, Settings - video ×2 |
| info | two-tone | default | outline | Accent/DIm, FG/A2 | `info-two-tone.svg` | 2461:9651 | Profiles, file context menu, folder context menu, menu, playlist context menu |
| interface | mono | default | outline | FG/A2 | `interface.svg` | 999:4960 | Settings - audio ×2, Settings - controls, Settings - extensions, Settings - global ×2, Settings - library, Settings - network, Settings - performance, Settings - playback ×2, Settings - privacy, Settings - recording, Settings - subtitles ×2, Settings - video ×2, [setting category] |
| interface | mono | state=active | outline+fill | Accent/Main | `interface-active.svg` | 1088:4044 | Settings - interface ×2, [setting category] |
| link | mono | default | outline | FG/A2 | `link.svg` | 774:1038 | [Video - Crop] |
| link | mono | state=active | outline | Accent/Main | `link-active.svg` | 774:1075 | — |
| link | two-tone | default | outline | Accent/Main, FG/A2 | `link-two-tone.svg` | 6063:13611 | — |
| list | mono | default | outline | FG/A2 | `list.svg` | 2107:6531 | Onboarding ×9, Player ×4, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI, View Options, [sidebar] |
| lists | mono | default | outline | FG/A2 | `lists.svg` | 217:191 | Onboarding ×9, Player ×5, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI, [Controls], [Miniplayer] |
| lists | mono | state=active | outline | Accent/Main | `lists-active.svg` | 467:492 | [Controls], [Miniplayer] |
| maximize | mono | default | outline | FG/A2 | `maximize.svg` | 48:51 | Onboarding ×9, Player ×7, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI |
| minimize | mono | default | outline | FG/A2 | `minimize.svg` | 48:46 | Onboarding ×9, Player ×7, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI |
| more | mono | default | outline | FG/A2 | `more.svg` | 247:418 | Onboarding ×9, Player ×7, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI, [Setting Preset], [media], [playlist], [sidebar] |
| move | mono | default | outline | FG/A2 | `move.svg` | 463:417 | [Controls], [Miniplayer] |
| music | mono | default | outline | FG/A2 | `music.svg` | 999:4806 | [sidebar] |
| new folder | mono | default | outline | FG/A2 | `new-folder.svg` | 2139:9022 | — |
| new folder | two-tone | default | outline | Accent/DIm, FG/A2 | `new-folder-two-tone.svg` | 2461:9779 | folder context menu |
| next | mono | default | outline+fill | FG/A2 | `next.svg` | 45:12 | Onboarding ×9, Player ×2, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI, [Controls], [Miniplayer] |
| next | two-tone | default | outline | Accent/DIm | `next-two-tone.svg` | 6073:13875 | right-click menu |
| open | mono | default | outline | FG/A2 | `open.svg` | 330:267 | Onboarding ×9, Player ×2, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI, [Miniplayer], [sidebar] |
| paint | mono | default | outline | FG/A2 | `paint.svg` | 2150:9212 | — |
| paint | two-tone | default | outline | Accent/DIm, FG/A2 | `paint-two-tone.svg` | 2493:9283 | Profiles, menu |
| paint | mono | state=active | outline+fill | Accent/Main | `paint-active.svg` | 2150:9248 | — |
| pause | mono | default | outline+fill | FG/A2 | `pause.svg` | 44:427 | [play] |
| PiP | mono | default | outline+fill | FG/A2 | `pip.svg` | 2139:8439 | Player - customize ×7 |
| play | mono | default | outline+fill | FG/A2 | `play.svg` | 44:419 | Onboarding ×9, Player ×2, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI, [Controls], [Miniplayer], [play] |
| playback | mono | default | outline | FG/A2 | `playback.svg` | 999:4802 | Player ×2, Settings - audio ×2, Settings - controls, Settings - extensions, Settings - global ×2, Settings - interface ×2, Settings - library, Settings - network, Settings - performance, Settings - privacy, Settings - recording, Settings - subtitles ×2, Settings - video ×2 |
| playback | two-tone | state=selected | outline | Accent/DIm, FG/A2 | `playback-selected-two-tone.svg` | 6073:13944 | right-click menu, [Controls] |
| playback | two-tone | default | outline | Accent/DIm | `playback-two-tone.svg` | 4004:12338 | file context menu, playlist context menu, right-click menu |
| playback | mono | state=active | outline+fill | Accent/Main | `playback-active.svg` | 3180:17978 | Settings - playback ×2 |
| playback settings | mono | default | outline+fill | FG/A2 | `playback-settings.svg` | 2230:9222 | Onboarding, Player ×2, Player - Light, Player - hide UI, [Controls] |
| playback settings | mono | state=active | outline+fill | Accent/Main, FG/A2 | `playback-settings-active.svg` | 2238:9232 | [Controls] |
| playlist | mono | default | outline+fill | FG/A2 | `playlist.svg` | 42:357 | Onboarding ×9, Player ×7, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI, [playlist], [sidebar] |
| playlist | two-tone | default | outline+fill | Accent/DIm, FG/A2 | `playlist-two-tone.svg` | 2461:9719 | file context menu, right-click menu |
| playlist | mono | state=active | outline+fill | Accent/Main | `playlist-active.svg` | 858:5098 | Player, [sidebar] |
| plugins | mono | default | outline | FG/A2 | `plugins.svg` | 2516:9369 | Settings - audio ×2, Settings - controls, Settings - global ×2, Settings - interface ×2, Settings - library, Settings - network, Settings - performance, Settings - playback ×2, Settings - privacy, Settings - recording, Settings - subtitles ×2, Settings - video ×2 |
| plugins | two-tone | default | outline | Accent/DIm, FG/A2 | `plugins-two-tone.svg` | 2516:9378 | — |
| plugins | mono | state=active | outline+fill | Accent/Main | `plugins-active.svg` | 2516:9375 | Settings - extensions |
| preferences | mono | default | outline | FG/A2 | `preferences.svg` | 1803:2957 | Settings - audio ×2, Settings - controls, Settings - extensions, Settings - global ×2, Settings - interface ×2, Settings - library, Settings - network, Settings - performance, Settings - playback ×2, Settings - privacy, Settings - recording, Settings - subtitles ×2, Settings - video ×2 |
| preferences | mono | state=active | outline | Accent/Main | `preferences-active.svg` | 1803:2965 | Settings - global ×2, Settings - performance |
| previous | mono | default | outline+fill | FG/A2 | `previous.svg` | 45:18 | Onboarding ×9, Player ×2, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI, [Controls], [Miniplayer] |
| previous | two-tone | default | outline | Accent/DIm | `previous-two-tone.svg` | 6073:13879 | right-click menu |
| privacy | mono | default | outline | FG/A2 | `privacy.svg` | 3046:10386 | Settings - audio ×2, Settings - controls, Settings - extensions, Settings - global ×2, Settings - interface ×2, Settings - library, Settings - network, Settings - performance, Settings - playback ×2, Settings - recording, Settings - subtitles ×2, Settings - video ×2 |
| privacy | two-tone | default | outline | Accent/DIm, FG/A2 | `privacy-two-tone.svg` | 3050:10420 | — |
| privacy | mono | state=active | outline+fill | Accent/DIm, Accent/Main | `privacy-active.svg` | 3050:10424 | Settings - privacy |
| profile | mono | default | outline | FG/A2 | `profile.svg` | 2437:14784 | — |
| profile | two-tone | default | outline | Accent/DIm, FG/A2 | `profile-two-tone.svg` | 2493:9300 | Profiles, menu |
| queue | mono | default | outline | FG/A2 | `queue.svg` | 2127:7523 | [Controls] |
| queue | two-tone | default | outline | Accent/DIm, FG/A2 | `queue-two-tone.svg` | 2461:9714 | file context menu, playlist context menu, [Controls] |
| quit | mono | default | outline | FG/A2 | `quit.svg` | 6073:14046 | Player - customize ×7 |
| quit | two-tone | default | outline | Accent/DIm, FG/A2 | `quit-two-tone.svg` | 6073:14054 | right-click menu |
| recent | mono | default | outline | FG/A2 | `recent.svg` | 2154:9699 | Onboarding ×9, Player ×7, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI, [sidebar] |
| recent | two-tone | default | outline | Accent/DIm, FG/A2 | `recent-two-tone.svg` | 2493:9246 | Profiles, menu |
| record | mono | default | outline+fill | FG/A2 | `record.svg` | 2115:7482 | Player - customize ×7, Settings - audio ×2, Settings - controls, Settings - extensions, Settings - global ×2, Settings - interface ×2, Settings - library, Settings - network, Settings - performance, Settings - playback ×2, Settings - privacy, Settings - subtitles ×2, Settings - video ×2 |
| record | mono | state=active | outline+fill | Accent/Main | `record-active.svg` | 6571:16751 | Settings - recording |
| record | two-tone | default | outline+fill | Accent/DIm | `record-two-tone.svg` | 6073:13901 | right-click menu |
| refresh | mono | default | outline | FG/A2 | `refresh.svg` | 1622:3137 | [Controls] |
| refresh | two-tone | default | outline | Accent/DIm, FG/A2 | `refresh-two-tone.svg` | 2461:9784 | folder context menu |
| remove | mono | default | outline | FG/A2 | `remove.svg` | 463:560 | [Controls], [Miniplayer] |
| repeat | mono | direction=right | outline | FG/A2 | `repeat-right.svg` | 187:470 | Player - customize ×7, [Controls] |
| repeat | two-tone | direction=right | outline | Accent/DIm, FG/A2 | `repeat-right-two-tone.svg` | 2460:9614 | — |
| replay | mono | default | outline | FG/A2 | `replay.svg` | 1919:9572 | Player - customize ×7, [Miniplayer] |
| save | mono | default | outline | FG/A2 | `save.svg` | 2459:9542 | — |
| save | two-tone | default | outline+fill | Accent/DIm, FG/A2 | `save-two-tone.svg` | 2459:9548 | playlist context menu |
| scope | two-tone | default | outline | Accent/DIm, FG/A2 | `scope-two-tone.svg` | 2139:8064 | [Audio Visualizer] |
| search | mono | default | outline | FG/A2 | `search.svg` | 856:2147 | Add Subtitles to Playlist/Folder, Keyboard Shortcuts, Onboarding ×9, Player ×7, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI, Settings - audio ×2, Settings - controls, Settings - extensions, Settings - global ×2, Settings - interface ×2, Settings - library, Settings - network, Settings - performance, Settings - playback ×2, Settings - privacy, Settings - recording, Settings - subtitles ×2, Settings - video ×2, [sidebar] |
| settings | mono | default | outline | FG/A2 | `settings.svg` | 42:355 | Onboarding ×8, Player - customize ×9, [Button], [Controls], [Icon Wrapper] |
| settings | two-tone | default | outline | Accent/DIm, FG/A2 | `settings-two-tone.svg` | 2493:9293 | Profiles, menu, right-click menu |
| settings | mono | state=active | outline+fill | Accent/Main, FG/A2 | `settings-active.svg` | 470:507 | — |
| shuffle | mono | direction=right | outline | FG/A2 | `shuffle-right.svg` | 187:474 | Player - customize ×7, [Controls] |
| shuffle | two-tone | direction=right | outline | Accent/DIm, FG/A2 | `shuffle-right-two-tone.svg` | 2461:9618 | playlist context menu |
| sidebar | mono | direction=left | outline+fill | FG/A2 | `sidebar-left.svg` | 69:814 | Player, Player - Light, Player - Music, Player - customize ×8, Player - hide UI |
| sidebar | mono | direction=right | outline+fill | FG/A2 | `sidebar-right.svg` | 6586:17393 | Player - customize ×7 |
| sidebar | mono | state=active | outline+fill | FG/A2 | `sidebar-active.svg` | 87:1041 | Player, Player - Music, Player - customize |
| snapshot | mono | default | outline | FG/A2 | `snapshot.svg` | 2115:7492 | Player - customize ×7 |
| songs | mono | default | outline+fill | FG/A2 | `songs.svg` | 71:851 | Onboarding ×9, Player ×7, Player - Light, Player - Music, Player - customize ×9, Player - hide UI, [sidebar] |
| songs | mono | state=active | outline+fill | #8F8F8F, #D37918, Accent/Main | `songs-active.svg` | 87:1009 | [sidebar] |
| songs | mono | state=selected | outline+fill | #8F8F8F, #D37918, FG/A2 | `songs-selected.svg` | 470:592 | Player - Music, [sidebar] |
| sort | mono | default | outline | FG/A2 | `sort.svg` | 463:564 | Player ×3, Player - Music, [Controls], [Miniplayer], [sidebar] |
| sort | mono | state=active | outline+fill | Accent/Main, FG/A2 | `sort-active.svg` | 856:2206 | Onboarding ×9, Player ×4, Player - Light, Player - Music, Player - customize ×9, Player - hide UI, [sidebar] |
| spectometer | two-tone | default | outline | Accent/DIm, FG/A2 | `spectometer-two-tone.svg` | 2138:8026 | [Audio Visualizer] |
| spectrum | two-tone | default | outline | Accent/DIm, FG/A2 | `spectrum-two-tone.svg` | 2139:8048 | [Audio Visualizer] |
| speed | mono | default | outline+fill | FG/A2 | `speed.svg` | 2115:7386 | Player - customize ×7 |
| speed | mono | state=active | outline+fill | Accent/Main | `speed-active.svg` | 2115:7391 | — |
| stop | mono | default | outline+fill | FG/A2 | `stop.svg` | 187:322 | Player - customize ×7 |
| stop | two-tone | default | outline | Accent/DIm | `stop-two-tone.svg` | 6072:13836 | right-click menu |
| streaming | mono | default | outline+fill | FG/A2 | `streaming.svg` | 70:833 | Onboarding ×9, Player ×7, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI, Settings - audio ×2, Settings - controls, Settings - extensions, Settings - global ×2, Settings - interface ×2, Settings - library, Settings - performance, Settings - playback ×2, Settings - privacy, Settings - recording, Settings - subtitles ×2, Settings - video ×2, [sidebar] |
| streaming | two-tone | default | outline+fill | Accent/DIm, FG/A2 | `streaming-two-tone.svg` | 2461:9672 | Profiles, file context menu, menu |
| streaming | mono | state=active | outline+fill | Accent/Main | `streaming-active.svg` | 477:1202 | Settings - network, [sidebar] |
| streaming | mono | state=selected | outline+fill | FG/A2 | `streaming-selected.svg` | 477:1208 | — |
| subtitle | mono | default | outline | FG/A2 | `subtitle.svg` | 1911:8286 | Add Subtitles to Playlist/Folder ×4, [subtitle multiple], [subtitle one] |
| subtitle | mono | default | outline | Accent/DIm, FG/A2 | `subtitle-2461-9663.svg` | 2461:9663 | — |
| subtitles | mono | default | outline | FG/A2 | `subtitles.svg` | 42:398 | Onboarding ×9, Player ×2, Player - Light, Player - customize ×9, Player - hide UI, Settings - audio ×2, Settings - controls, Settings - extensions, Settings - global ×2, Settings - interface ×2, Settings - library, Settings - network, Settings - performance, Settings - playback ×2, Settings - privacy, Settings - recording, Settings - video ×2, [Controls] |
| subtitles | two-tone | default | outline | Accent/DIm, FG/A2 | `subtitles-two-tone.svg` | 2461:9635 | file context menu, folder context menu, playlist context menu, right-click menu, [Controls] |
| subtitles | mono | state=active | outline+fill | Accent/Main, FG/A2 | `subtitles-active.svg` | 467:497 | Settings - subtitles ×2, [Controls] |
| swap | mono | default | outline | FG/A2 | `swap.svg` | 1915:8362 | [subtitle multiple] |
| swap | two-tone | default | outline | Accent/DIm, FG/A2 | `swap-two-tone.svg` | 2461:9628 | Profiles, file context menu, menu |
| thumbnail | mono | default | filled | #303030 | `thumbnail.svg` | 2404:9198 | Onboarding ×9, Player ×3, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI, [media], [sidebar] |
| thumbnail | mono | value=high | filled | #303030, Accent/Main | `thumbnail-high.svg` | 2404:9204 | — |
| thumbnail | mono | value=medium | filled | #303030, Accent/Main | `thumbnail-medium.svg` | 2404:9211 | Onboarding ×9, Player ×3, Player - Light, Player - Music, Player - customize ×9, Player - hide UI, [media], [sidebar] |
| thumbnail | mono | value=low | filled | #303030, Accent/Main | `thumbnail-low.svg` | 2404:9215 | — |
| tv | mono | default | outline+fill | FG/A2 | `tv.svg` | 477:1096 | — |
| tv | mono | state=active | outline+fill | #8F8F8F, #D37918, Accent/Main | `tv-active.svg` | 477:1101 | — |
| tv | mono | state=selected | outline+fill | #8F8F8F, #D37918, FG/A2 | `tv-selected.svg` | 477:1107 | — |
| ui | mono | default | outline | Accent/DIm, FG/A2 | `ui.svg` | 6075:14088 | right-click menu |
| ui | two-tone | default | outline | Accent/DIm, FG/A2 | `ui-two-tone.svg` | 6075:14095 | — |
| upload | two-tone | direction=up | outline | Accent/DIm, FG/A2 | `upload-up-two-tone.svg` | 6215:13606 | — |
| video | mono | default | outline | FG/A2 | `video.svg` | 999:4810 | Add Subtitles to Playlist/Folder ×2, Settings - audio ×2, Settings - controls, Settings - extensions, Settings - global ×2, Settings - interface ×2, Settings - library, Settings - network, Settings - performance, Settings - playback ×2, Settings - privacy, Settings - recording, Settings - subtitles ×2, [Controls] |
| video | two-tone | default | outline+fill | Accent/Main, FG/A2 | `video-two-tone.svg` | 5886:24408 | right-click menu, [Controls] |
| video | mono | state=active | outline+fill | Accent/Main, FG/A2 | `video-active.svg` | 1102:5055 | Settings - video ×2 |
| videos | mono | default | outline+fill | FG/A2 | `videos.svg` | 71:857 | Player ×2, Player - Music, [sidebar] |
| videos | mono | state=active | outline+fill | #8F8F8F, #D37918, Accent/Main | `videos-active.svg` | 87:1015 | [sidebar] |
| videos | mono | state=selected | outline+fill | #8F8F8F, #D37918, FG/A2 | `videos-selected.svg` | 470:587 | Onboarding ×9, Player ×5, Player - Light, Player - Music, Player - customize ×9, Player - hide UI, [sidebar] |
| view | mono | default | outline | FG/A2 | `view.svg` | 856:3212 | — |
| view | mono | state=active | outline+fill | Accent/Main, FG/A2 | `view-active.svg` | 856:3220 | — |
| vlc | mono | default | filled | #D37918 | `vlc.svg` | 48:57 | Onboarding ×10, Player ×7, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI |
| volume | mono | value=high | outline | FG/A2 | `volume-high.svg` | 182:179 | Onboarding ×9, Player ×2, Player - Light, Player - Music ×2, Player - customize ×9, Player - hide UI, [Controls] |
| waveform | two-tone | default | outline | Accent/DIm, FG/A2 | `waveform-two-tone.svg` | 2139:8078 | [Audio Visualizer] |
| window | mono | default | outline | FG/A2 | `window.svg` | 2107:6312 | — |
| window | two-tone | default | outline+fill | Accent/DIm, FG/A2 | `window-two-tone.svg` | 2461:9640 | — |
| wrench | mono | default | outline | FG/A2 | `wrench.svg` | 2107:6319 | — |
| zoom | mono | default | outline | FG/A2 | `zoom.svg` | 2154:9680 | Player - customize ×7 |

## Unused variants (49)

Defined in the set but never instanced in any frame (still exported as SVG where available): settings [state=active] (470:507), close [value=medium] (182:187), close [value=low] (182:193), close [value=none] (182:198), fullscreen [state=active] (6031:13553), new folder (2139:9022), folder [state=selected] (467:502), album (6206:13653), expand-sidebar (858:5697), collapse-sidebar (858:5703), streaming [state=selected] (477:1208), tv (477:1096), tv [state=active] (477:1101), tv [state=selected] (477:1107), home [state=selected] (470:597), arrow [direction=down] (71:881), arrow [direction=down] (2461:9739), arrow [direction=up] (71:884), arrow [direction=up] (2461:9744), upload [direction=up] (6215:13606), arrow [direction=left] (2461:9754), repeat [direction=right] (2460:9614), chevron [direction=left] (71:878), view (856:3212), view [state=active] (856:3220), link [state=active] (774:1075), link (6063:13611), check [state=selected] (2428:14606), profile (2437:14784), artist [state=active] (858:5164), accessibility (999:4914), subtitle (2461:9663), file (2107:6307), window (2107:6312), window (2461:9640), wrench (2107:6319), paint (2150:9212), paint [state=active] (2150:9248), speed [state=active] (2115:7391), thumbnail [value=high] (2404:9204), thumbnail [value=low] (2404:9215), favorite [state=active] (2430:14666), save (2459:9542), disc (5884:24330), capture-device (2493:9307), plugins (2516:9378), privacy (3050:10420), ui (6075:14095), genre (6202:13602).

## Notes and inconsistencies

- `icons-svg/index.json` names its source as Figma file `B7ifd32zHbliiZs9q00JG3`; `figma_file.json` was fetched from another copy of the same community file. Node ids match 1:1 (206/208 found; the 2 missing are listed above).
- `subtitle` and `album` each have two variants with identical properties (different artwork); check the SVG before using either.
- Several "active" variants mix raw hex #D37918/#8F8F8F with styled paints; treat raw #D37918 as `Accent/Main` and raw #8F8F8F as `FG/A2` so accent recoloring works.
- Settings categories reuse icons: General and Performance both use `preferences` (sliders), per spec-part2 §14.
