# Core API: how UI code talks to the player

`MXRCore` holds the backend protocols (ARCHITECTURE §2.2), the `@MainActor @Observable` models views bind to,
and app-side stores. `MXRMockBackend` implements every protocol with the Figma content. Views never see a
backend: they read models and call model methods. Source: `modules/gui/macosx_redesign/Sources/MXRCore/`.

## 1. Getting the models

One `AppModel` owns everything. Inject it once at the root; every model is then in the environment:

```swift
let app = AppModel.mock(.playingEpisode)            // gallery/previews; the plugin builds AppModel(backends:)
PlayerWindowView().appModel(app)                     // injects AppModel + every model below

struct ControlBar: View {
    @Environment(PlayerModel.self) private var player
    @Environment(QueueModel.self) private var queue
    @Environment(InterfaceModel.self) private var ui
    var body: some View { … player.togglePlayPause() … queue.next() … ui.toggleTracks(.audio) … }
}
```

Need a binding? `@Bindable var ui = ui` then `$ui.isUIHidden`. Models expose `private(set)` state plus command
methods; state changes come back from the backend (so the UI always shows the engine's truth).

## 2. Which model for which screen

| Screens | Model(s) | Notes |
|---|---|---|
| S01 control bar, S04 volume, S05 fullscreen | `PlayerModel`, `QueueModel` (prev/next, `hasNext`), `PlaybackClock` | `player.isPlaying` drives the play/pause look; `player.volume` is 0…2 (`volumePercent` 0…200); `player.isFullscreen` is what the engine wants — the window observes it and calls `player.setFullscreen(_)` after native transitions. |
| S02 time labels | `PlaybackClock` | Bind labels to `displaySecond`/`displayTime`/`displayRemaining` (≤ 1 change/s). Never read `currentTime` in `body`. Editable time: `MediaTime(parsing:)` → `player.seek(to:)`. Elapsed/remaining: `InterfaceModel.timeDisplay`. |
| S03 seek bar + preview | `PlaybackClock.time(at:)`/`position(at:)` from an `NSView.displayLink` (only while `clock.isRunning` and visible), `SeekPreviewModel.hover(at:)`/`end()` → `image`, `time` | Drag: `player.seek(to:, precision: .fast)`, release: `.precise`. Waveform (S34): `backends.thumbnails.waveform(for:bins:)` if `capabilities.supportsWaveform`. |
| S06 hide UI, S05 bar reveal | `InterfaceModel.isUIHidden`, `areBarsVisible` | |
| S07/S08/S11 menus | `AppCommand.appMenu`, `app.perform(_:)`, `app.canPerform(_:)`, `RecentStore.entries`, `ProfileStore` (`menuTitle` = "Profile (Movies)") | Shortcut text: `shortcuts.primaryBinding(for: command.shortcutActionID)?.displayString`. |
| S09/S10 right-click | `AppCommand.contextMenu` + submenus from `PlayerModel`, `TracksModel`, `VideoEffectsModel`, `AudioEffectsModel` | |
| S12 continue watching | `PlayerModel.restorePrompt` (non-nil = show toast), `resumePlayback()`, `dismissRestorePrompt()` | Auto-dismisses after `restorePromptTimeout` (5 s). Resume marker: `restorePrompt.time / clock.length`. |
| S13 OSD | `OSDModel.message` (`text` = "Crop: 2.35:1", `pressedKeyText` = "Pressed C") | Key presses go through `ShortcutsModel.handle(KeyBinding(event:))`; the model fills the OSD. |
| S14–S16 track popover | `TracksModel` (`embeddedTracks(of:)`, `externalTracks(of:)`, `selectedTrack(of:)`, `select`, `selectNone`, `audioDevices`, `selectAudioDevice`, `refreshAudioDevices`) | External **+** → `ui.request(.addSubtitleFile)` or `ui.present(.addSubtitles(scope:source:))`. "Show Preferences" → `ui.showPreferences(for:)`. |
| S17 sidebar Playback | `PlayerModel` (`rate`/`setRate`, `sleepTimer`/`setSleepTimer`, `audioVisualization`), `InterfaceModel` (`showSubtitleTimeline`, `showStatistics`, `showWaveform`), `player.statistics` | Reverse: hidden unless `capabilities.supportsReversePlayback` (D014). |
| S18 sidebar Video | `VideoEffectsModel.effects` / `update { $0.flip = .horizontal }` | Choices: `VideoEffects.aspectRatioChoices`, `cropChoices`, `VideoZoom/HDRMode/DeinterlaceMode.allCases` with `.title`. |
| S19 sidebar Audio | `TracksModel` (audio track, `audioDelay`, `trackDefaults`), `AudioEffectsModel` (`applyEqualizerPreset`, `setEqualizerBand`, `update`) | EQ preview curves: `EqualizerPreset.builtIn[i].bands`; labels `EqualizerSettings.bandLabels`. Spatializer values are VLC's (×10 in the design). |
| S20 sidebar Subtitles | `TracksModel` (`subtitleDelay`, `nudgeSubtitleDelay(steps:)`, `subtitleFPS`, `subtitleDurationFactor`, `subtitleStyle`/`updateSubtitleStyle`, `trackDefaults`) | Presets: `app.presets.presets`, `app.activePreset`, `app.selectPreset(_)`, `app.createPreset(named:)`. |
| S21 subtitle timeline | `TracksModel.loadSubtitleCues()` → `subtitleCues`; `nudgeSubtitleDelay(steps: ±1)` | Only if `capabilities.supportsSubtitleTimeline`. |
| S22 queue | `QueueModel` (`items`, `isCurrent`, `summary` "4 items - 2h 3m", `move`, `remove`, `selection`/`removeSelection`, `cycleRepeatMode`, `toggleShuffle`, `sort(by:)`, `enqueue`, `insert(_:at:)`) | "+" → `ui.request(.addFilesToQueue)`. Durations: `media.duration?.formatted(.compact)`. |
| S23 bookmarks | `BookmarksModel` (`bookmarks`, `summary` "2 Bookmarks", `addAtCurrentTime()`, `jump(to:)`, `rename`, `remove`) | Time text: `.formatted(.hoursMinutesSecondsMilliseconds)`. |
| S24 chapters | `ChaptersModel` (`chapters`, `currentChapter`, `select(_)`) | |
| S25–S27 add subtitles | `LibraryModel.allMedia(at:)` for the file list, `SubtitleMatcher.match(videos:subtitles:)`, `LibraryBackend.attachSubtitle` via `app.backends.library`, `TracksModel.addExternalTrack` | OpenSubtitles only if `capabilities.supportsOpenSubtitles`. |
| S28–S47 library (compact + full) | `LibraryModel` (`select(_ category)`, `navigate(to:)`, `open(entry)` → returns media to play, `goBack/goForward`, `breadcrumb`, `entries`, `countText`, `addAction`, `homeSections`, `sort`/`setSort`, `availableSorts`, `compactViewMode`/`fullViewMode`, `searchText`, `loadMoreIfNeeded(after:)`) | Play: `app.play(media, context: library.mediaEntries)`. Rail: `LibraryCategory.allCases` + `PinStore`. Top-bar folder chip: `player.media?.folder` → `library.navigate(to: .folder(id))` + `ui.library = .compact`. Mini player: `PlayerModel` + `QueueModel` + `ui.isMiniPlayerQueueExpanded`. Dialogs S36/S39: `library.addNetworkStream(urls:name:)`, `createPlaylist(name:media:)`. |
| S48–S63 settings | `SettingsModel` (`groupedCategories`, `selectedCategory`, `visibleRows(of:)`, `value(for:)`, `bool/double/string(_)`, `setValue(_:for:)`, `choices(for:)`, `selectedChoiceTitle(for:)`, `compositeSelection`/`selectComposite`, `secondaryValue` (stacked choice), `isEnabled(_)`, `info(for:)`, `toggleAdvanced`, `searchResults`, `perform(row)`) | Structure: `Sources/MXRCore/Resources/settings-map.json5` (D013): 13 categories, every Figma row, VLC option names, human choices, Figma values as `mock`. `row.control` picks the control; `basicSections` first, `advancedSections` under "Advanced Options". Theme/accent: `AppearanceModel` (`AccentChoice.rawValue` == `Theme.Accent.rawValue`). |
| S64 keyboard shortcuts | `ShortcutsModel` (`filteredGroups`, `searchText`, `searchField`, `setBinding`, `conflicts`, `saveDraft`, `discardDraft`, `hasChanges`) | |
| S66/S67 customize player | `app.playerLayout` (`PlayerLayout`: `top` row + `bottom` rows of `LayoutItem`; flexible items = seek bar, spacer), `app.beginCustomizing()` / `endCustomizing(save:)`, `LayoutStore.draft`, `updateDraft { $0.move/insert/remove }`, `hasChanges`, `PlayerLayout.availableTiles` | **Build the top bar and control bar from `app.playerLayout`**, not a hard-coded HStack. `PlayerControl.command` gives the action of clickable items. Music media use the `.music` layout (±15 s). |
| S68 profiles, S69–S71 onboarding | `ProfileStore`, `AppearanceModel`, `LibraryModel.addFolder`, `ShortcutsModel.primaryBinding(for:)`, `app.needsOnboarding` / `completeOnboarding()` | |
| engine dialogs | `DialogModel.current` + `submitLogin` / `choose` / `dismiss` | |

**Window state lives in `InterfaceModel`**: `rightPanel` (`.tracks(tab)`, `.sidebar(tab)`, `.queue(tab)` — one at a time;
bar icons are orange when their panel is open), `library` (`.hidden/.compact/.full`), `sheet` (`AppSheet`: settings,
keyboardShortcuts, addSubtitles, openNetworkStream, newPlaylist, about, onboarding, mediaInfo, …), `fileRequest`
(show `NSOpenPanel`, then `app.complete(request, urls:)`), `isCustomizing`, `isUIHidden`.

## 3. Values worth knowing

- `MediaTime`: signed microseconds like `vlc_tick_t`. Integer literals are seconds (`player.jump(by: -10)`).
  `.formatted(.hoursMinutesSeconds | .compact | .summary | .hoursMinutesSecondsMilliseconds | .signedSeconds)`.
- `MediaItem`: `displayTitle` (top bar: "The Wand S01E04", "untangle"), `listTitle` (rows: "The_Wand_S01E05.mp4",
  "untangle - juxtopposed"), `isWatched`, `isInProgress`, `displayProgress` (orange line under thumbnails), `folder`.
- `LibraryEntry` (`.media/.folder/.playlist/.album/.artist/.genre/.show/.stream/.link`): `title`, `destination`.
- Images: `app.backends.thumbnails.artwork(for:maxPixelSize:)` (async) or `cachedArtwork` (sync, use first to avoid a
  blank first frame). Check `app.capabilities` (`BackendCapabilities`) before showing optional features.

## 4. Mock scenarios (gallery entries and tests)

`AppModel.mock(_ scenario, clock: .frozen)` — in memory, deterministic. Every library query is also answered
synchronously, so the first rendered frame is populated. Use `.realtime` only for interactive gallery play.

| Scenario | State |
|---|---|
| `.playingEpisode` (default) | "The Wand S01E04" playing, 00:02:10 / 00:25:40. Queue E04–E07. Subs: English ✓, Japanese, external `The_Wand_S01_EN.srt`. Audio: English, Japanese ✓. Devices: Speakers, Headphones ✓. |
| `.pausedEpisode` | "The Wand S01E11" paused at 00:02:10. Queue E11–E14 (23:06, 24:18, 25:00, 22:35). |
| `.playingMovie` | "DON’T BLINK" (4K) at 00:02:10 / 01:58:20. Chapters Winter 00:02:15 … Winter (5 Years Later) 01:44:10. Bookmarks "DON’T BLINK 1/2". |
| `.continueWatching` | "DON’T BLINK" at 0 with `restorePrompt` 00:45:08. |
| `.music` | "untangle - juxtopposed" at 00:00:10 / 00:01:40; queue = My Songs. |
| `.stream` | Live radio (no seek). |
| `.idle` | Nothing playing ("VLC Media Player"), full library. |
| `.emptyLibrary` | Nothing playing, empty library, no seeded stores. |

Library content (all scenarios but `.emptyLibrary`): Home (110 items; Continue Watching E05–E07 + DON’T BLINK; Listen
Again; Shows/Films/Anime; Fav Episodes/Coolest Songs/Anime Playlist; juxtopposed; TV Channels), Videos ▸ Shows ▸ The
Wand ▸ S01/S02 (S01: E01–E04 watched, sorted unwatched first), Music ▸ Songs ▸ My Songs, Albums/Artists/Genres,
Network (Podcasts, Radio), Playlists (Cool Songs, Anime to Watch). Presets "Custom Preset 01/02", "Anime", "Loud and
then Quiet Movies", "The Wand Subtitle Preset" (assigned to The Wand); profiles Movies ✓/Shows/Music/Work.

Gallery entry with a specific state:

```swift
GalleryEntry(id: "S22.Queue/default", title: "Queue", size: CGSize(width: 400, height: 970), screens: ["S22"]) {
    let app = AppModel.mock(.pausedEpisode)
    app.interface.rightPanel = .queue(.queue)
    return QueuePanel().appModel(app)
}
// Engine-only states: keep the MockBackend to drive it.
let mock = MockBackend(scenario: .idle); let app = mock.makeAppModel()
mock.dialogs.presentSampleLogin(); mock.extensions.seedSamples(); mock.player.askRestore(at: 42)
```

Known Figma inconsistencies the mock does not copy: the Figma queue writes "The Wand_S01E11.mp4" (space) and
"2h 3m" for four ~24 min items; the mock uses the library names and the real sum. Don't chase those text diffs.

## 5. For backend implementers (MXRVLCBackend)

- Implement the protocols in `Backends/`; build a `Backends` value and call `AppModel(backends:)`.
- Events are payload-free (`PlayerEvent.volume`, `QueueEvent.items`, …): after an event the model re-reads the
  backend's properties, so properties must be cheap (cached from callbacks). Use `EventChannel` for `addListener`.
- `PlaybackClockSource.timerPoint.hostTime` is in the `CACurrentMediaTime()` base; nil = do not interpolate.
- Library `cached…` methods are optional fast paths (default nil). `DialogBackend.presenter` is set by `AppModel`.
- App-level options use the `macosx-redesign-` prefix (`AppearanceModel.themeOption`); app shortcut actions use the
  `app-` prefix (`ShortcutsModel.appActionPrefix`) and are run by the UI, not by `key-action`.
- Plugin startup: set `MXRResources.allowsBundleModuleFallback = false` before touching `SettingsCatalog.bundled`.
