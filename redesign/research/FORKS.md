# Community implementations of the redesign (as of 14 Oct 2026)

The video was published on 12 Oct 2026. Within 48 hours, about 20 public
implementations appeared. **All were built with heavy AI assistance in one or two
days, and none targets macOS.** Deep-dive reports are in `analysis/01–03`.
This page is the short version with our verdict on each.

Upstream: [videolan/vlc](https://github.com/videolan/vlc), ~20k ★, 6.3k forks
(GitHub mirror; development happens on [code.videolan.org](https://code.videolan.org/videolan/vlc)).

## How to look at them locally

All VLC forks below are git remotes of this repository (`fork-<owner>`).
Only the redesign branch is fetched, blob-less. Recreate them with
`redesign/tools/add-fork-remotes.sh`.

```sh
git log --oneline upstream/master..fork-Pyr0zen/redesign
git diff $(git merge-base upstream/master fork-dsojevic/juxtopposed-redesign) fork-dsojevic/juxtopposed-redesign --stat
git show fork-Pyr0zen/redesign:redesign/reference/figma/Player.png > /tmp/p.png
```

Standalone (non-fork) projects are cloned locally into `../reference/standalone/`
by `redesign/tools/fetch-reference.sh`.

## VLC 4 forks (Qt/QML interface: Windows/Linux)

Every one of these changes `modules/gui/qt`, VLC 4's Qt interface. VideoLAN does
not ship that interface on macOS: `configure.ac` disables it, and there is no macOS
Qt build in CI. **So none of this code runs as a Mac app.** For us they are
references, sources of extracted data, and a cross-check when the design is
ambiguous.

| Fork | ★ | Branch | Platform tested | Approach | Coverage | Verdict for us |
|---|---|---|---|---|---|---|
| [dsojevic/vlc](https://github.com/dsojevic/vlc) | 27 | `juxtopposed-redesign` | Linux | Separate `player/qml/redesign/` folder with a single switch-in point. **But it also edits the engine** (`src/audio_output`, `es_out.c`, `actions.c`, `libvlc-module.c`) for new settings | Player, settings window, hotkeys editor | Best settings UX. `RedesignPreferencesCatalog.qml` maps each Figma settings row to a VLC option, and we reuse that mapping (copied to `from-forks/dsojevic/`). Don't take its engine changes. |
| [Pyr0zen/vlc](https://github.com/Pyr0zen/vlc) | 23 | `redesign`, `redesign-library` | Windows (CI) | Restyles 52 upstream QML files in place. No engine changes | Widest player coverage: bars, tracks popup, menus, 4-tab sidebar, queue/bookmarks/chapters, dialogs. Library branch never compiled | **Most valuable data source**: full Figma JSON, 4K renders, `FIGMA_FLOWS.md`, `INTERACTIONS.md`, `VIDEO_INDEX.md`. All copied into `redesign/design/figma/` and `from-forks/pyr0zen/`. |
| [Geckostya/vlc-Juxtopposed-redesign](https://github.com/Geckostya/vlc-Juxtopposed-redesign) | 1 | `redesign/stage1` | Windows | **Parallel interface**: a self-contained `VLC.Redesign` QML module in `modules/gui/qt/redesign/` (~100 components), enabled with `--qt-redesign`. Only 13 upstream lines deleted, no engine changes | Broadest: player, library, music, network, playlists, 13 settings categories, shortcuts, onboarding, customize, profiles, EQ, subtitle timeline | **The architecture we copy** (an additive layer behind a switch), applied to macOS. Polish is uneven; built in a day. |
| [Olmo-Gutierrez/VLC-juxtopposed](https://github.com/Olmo-Gutierrez/VLC-juxtopposed) | 1 | `redesign` | Windows | In-place Qt/QML. Project site with a 7-phase roadmap: phases 1–2 in progress, 3–7 not started | Control bar only, matched to Figma at 1920 px | Pixel-accurate control bar is a good cross-check. Its **206 Figma icons and tokens** are our icon base (`design/figma/icons-svg/`). Too little implemented to be a base. |
| [SrDouglax/JuxtopposedVLC](https://github.com/SrDouglax/JuxtopposedVLC) | 2 | `feat/m2` | Linux | Refactors upstream's build manifests, touches `src/player` | Player M1–M2 | Its specs are very good: 103-frame coverage matrix and behavior requirements V01–V16 (`from-forks/srdouglax/`). |
| [Hamido212/vlc](https://github.com/Hamido212/vlc) | 1 | `redesign` | Windows (preview release) | In place | Deep settings sidebar (2k lines), sleep timer, seek thumbnails | Cross-check for sidebar behavior. |
| [ItsAhadun/vlc-redesign](https://github.com/ItsAhadun/vlc-redesign) | 0 | `claude/…` | Linux (headless harness) | In place, touches `src/` | Broad | `SPEC.md` measurements (copied) and an inspiring screenshot-verification harness. |
| [KoalaNalle/vlc-juxtopposed](https://github.com/KoalaNalle/vlc-juxtopposed) | 1 | `juxtopposed-playback-bar` | Windows | In place. Fixes clock/seek bugs in `src/` | Playback bar, queue | Exact queue-panel SVGs (copied). |
| [floklein/jvlc](https://github.com/floklein/jvlc) | 0 | `feat/redesign`, `research/*` | — | Invasive (deletes upstream subsystems) | — | Don't reuse its code. **Its 8 research notes are excellent** (copied to `from-forks/floklein-research/`). |
| [ExPikaPaka/vlc-ui-redesign](https://github.com/ExPikaPaka/vlc-ui-redesign) | 0 | `redesign/08-volume-wedge` | — | Tidy stacked in-place theme | Tokens, top bar, control bar | Fine, small. Ignore its accidental `po/` churn. |
| [Green-Skeleton/vlc-redesign](https://github.com/Green-Skeleton/vlc-redesign) | 0 | `redesign` | Windows | Overwrites stock icons/font | Player chrome | Only fork that merges upstream regularly. |
| [stonepicaxe/vlc](https://github.com/stonepicaxe/vlc) | 0 | `redesign/figma-ui` | Windows | In place | Preferences heavy | Its "macOS installer" ships the stock native UI, not the redesign. |
| [ldl1949/vlc-New-UI](https://github.com/ldl1949/vlc-New-UI) | 0 | `redesign-phase2` | — | In place, edits `modules/control/hotkeys.c` | Sidebar, subtitle timeline (GUI-side cue parser), bookmarks | A subtitle timeline approach worth comparing. |
| [webmaster94/vlc-redesign](https://github.com/webmaster94/vlc-redesign) | 0 | `redesign` | Windows | VLC **3.0** Qt Widgets, rebranded "Reframe", relicensed GPL-3 | Claims everything | Dead end (VLC 3); `doc/redesign/design-inventory.md` only. |
| [lin-ycv/vlc](https://github.com/lin-ycv/vlc) | 0 | `windows-figma-vlc-3.0.24` | Windows | One stylesheet | Cosmetic | Not useful. |
| [mholtzhausen/vlc](https://github.com/mholtzhausen/vlc) | 0 | `master` | — | Plan document only | — | `docs/moth-ui-plan.md`: an 11-phase plan with node ids. |

## Standalone players and skins (not VLC forks)

| Project | ★ | Stack | Platform | Verdict |
|---|---|---|---|---|
| [Sayandeep1013/vlc-skins](https://github.com/Sayandeep1013/vlc-skins) | 3 | C# .NET 8 WPF + LibVLCSharp (~5.8k LOC) | Windows | Half the repo is unrelated "skins": third-party VLC 3 themes (VeLoCity, Materia) copied in earlier. The player is decent: auto-hide bars, seek thumbnails via a hidden second player, waveform, cone volume. Icons are Lucide, not Figma, and colors are approximate. Ideas only. |
| [nagasab221/vlc-redesign](https://github.com/nagasab221/vlc-redesign) | 0 | Python + PyQt5 + python-vlc | Linux | Covers almost the whole video with high fidelity. `prefs.py` has 215 settings rows in 13 categories, each mapped to libVLC. A good checklist. |
| [nirmaljosephukken/pylon-player](https://github.com/nirmaljosephukken/pylon-player) | 0 | Python + PySide6 + python-vlc | Windows | Good behavior ideas: draggable subtitle timeline, per-show presets, S01E02 subtitle matching. Low visual fidelity. |
| [Green-Skeleton/vlc-redesign-skin](https://github.com/Green-Skeleton/vlc-redesign-skin) | 2 | VLC 3 skins2 + Node tools | Win/Linux | Its **`.fig` decoder/renderer** (`tools/figma/decode.js`, `render.js`) can extract *everything*, including vector paths, from a locally saved `.fig`. That's our route to perfect icons. |
| [s1rd0/BettererVLC](https://github.com/s1rd0/BettererVLC) | 2 | skins2 `.vlt` | Windows | A skin, low-res assets. Not useful. |
| Electron/Tauri/mpv projects (furyengi, sudo-Mystic, Joseane772) | — | not VLC | — | Not VLC's engine; out of scope. |

"Skins2" is VLC 3's bitmap skin engine (`.vlt` = XML plus PNGs). It cannot express a
library, settings, side panels or onboarding. Released VLC for macOS has no skins2.

## Why we don't build on any of them

1. **Wrong platform layer.** Qt/QML is not VLC's macOS interface. Porting a Qt
   fork to the Mac means shipping an unsupported toolkit with non-native
   behavior. That is the opposite of goal #3 in `PHILOSOPHY.md`.
2. **Upstream churn.** Upstream made 564 commits to `modules/gui/qt` in 180 days.
   Forks that edit upstream files in place get between 221 and 642 of those commits
   touching their changes. Our separate macOS module avoids that entirely.
3. **They're days old.** Breadth over polish. Several change the engine.

What we *do* take: their extracted Figma data, their specs and research, and
their behavior ideas, with attribution in `from-forks/README.md`. When we're stuck
on a behavior, we look at how Geckostya, Pyr0zen or dsojevic solved it in QML and
re-express it natively.

## Upstream's own direction

VLC 4.0 for desktop is still unreleased (stable is 3.0.24, Sep 2026). Upstream's
macOS GUI is being actively reworked in 2026 (634 commits; Liquid Glass,
centered play button). That is a different direction from Juxtopposed's
design, which is one more reason not to edit `modules/gui/macosx` in place.
