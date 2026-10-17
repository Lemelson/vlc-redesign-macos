import XCTest
@testable import MXRCore
@testable import MXRMockBackend

@MainActor
final class LibraryModelTests: XCTestCase {
    /// Home is derived from the history by the VLC backend's rules (MXRLibraryServices.m `homeSections`).
    func testHomeSectionsFollowHistory() {
        let app = AppModel.mock(.playingEpisode)
        XCTAssertEqual(app.library.location, .home)
        XCTAssertEqual(app.library.countText, "110 items")
        XCTAssertEqual(app.library.homeSections.map(\.title), [
            "Continue Watching", "Listen Again", "Frequently Visited Folders", "Frequently Visited Playlists",
            "Frequently Listened Artists", "Latest Streams",
        ])
        XCTAssertEqual(app.library.homeSections[0].entries.map(\.title), ["The_Wand_S01E05.mp4", "The_Wand_S01E06.mp4", "The_Wand_S01E07.mp4", "DON’T BLINK.mp4"])
        XCTAssertEqual(app.library.homeSections[1].entries.map(\.title), ["untangle - juxtopposed", "moonlight - juxtopposed", "black bird - juxtopposed"])
        XCTAssertEqual(app.library.homeSections[2].entries.map(\.title), ["S01", "Kaze no Tabi", "My Songs", "Films"],
                       "ranked by plays (Kaze no Tabi E01–E06 were watched, so they carry a last-played date: L04)")
        XCTAssertEqual(app.library.homeSections[3].entries.map(\.title), ["Cool Songs"])
        XCTAssertEqual(app.library.homeSections[5].entries.map(\.title), ["TV Channels"], "seeded defaults wait until played")
        XCTAssertTrue(app.library.homeSections.allSatisfy { $0.destination != nil && !$0.entries.isEmpty })
    }

    func testFolderNavigationSortAndBreadcrumb() {
        let app = AppModel.mock(.playingEpisode)
        let library = app.library
        library.select(.videos)
        XCTAssertEqual(library.entries.map(\.title), ["Shows", "Films", "Anime"])
        XCTAssertEqual(library.addAction, .add)
        XCTAssertEqual(library.countText, "3 items")
        library.open(library.entries[0])
        XCTAssertEqual(library.entries.map(\.title), ["The Wand"])
        library.open(library.entries[0])
        XCTAssertEqual(library.entries.map(\.title), ["S01", "S02"])
        library.open(library.entries[0])
        XCTAssertEqual(library.breadcrumb.map(\.title), ["Videos", "Shows", "The Wand", "S01"])
        XCTAssertEqual(library.title, "S01")
        XCTAssertEqual(library.category, .videos)
        XCTAssertNil(library.addAction)
        XCTAssertEqual(library.countText, "15 items")
        // Unwatched first: E05–E15, then E01–E04 (Figma sidebar panel).
        XCTAssertEqual(library.entries.prefix(2).map(\.title), ["The_Wand_S01E05.mp4", "The_Wand_S01E06.mp4"])
        XCTAssertEqual(library.entries.suffix(4).map(\.title), ["The_Wand_S01E01.mp4", "The_Wand_S01E02.mp4", "The_Wand_S01E03.mp4", "The_Wand_S01E04.mp4"])
        XCTAssertTrue(library.entries.suffix(4).allSatisfy { $0.media?.isWatched == true })

        library.setSort(.titleAscending)
        XCTAssertEqual(library.entries.first?.title, "The_Wand_S01E01.mp4")
        XCTAssertEqual(library.sort, .titleAscending)

        library.goBack()
        XCTAssertEqual(library.title, "The Wand")
        XCTAssertTrue(library.canGoForward)
        library.goForward()
        XCTAssertEqual(library.title, "S01")
        library.navigate(to: .home)
        XCTAssertFalse(library.canGoForward)
    }

    func testMusicNetworkPlaylists() {
        let app = AppModel.mock(.music)
        let library = app.library
        library.select(.music)
        XCTAssertEqual(library.entries.map(\.title), ["Songs", "Albums", "Artists", "Genres"])
        XCTAssertEqual(library.countText, "4 items")
        library.open(library.entries[0])
        XCTAssertEqual(library.entries.map(\.title), ["My Songs"])
        XCTAssertEqual(library.countText, "1 item")
        library.open(library.entries[0])
        XCTAssertEqual(library.breadcrumb.map(\.title), ["Music", "Songs", "My Songs"])
        XCTAssertEqual(library.category, .music)
        XCTAssertEqual(library.entries.map(\.title), ["untangle - juxtopposed", "moonlight - juxtopposed", "black bird - juxtopposed"])
        XCTAssertEqual(library.addAction, .add)

        library.select(.network)
        XCTAssertEqual(library.entries.map(\.title), ["Podcasts", "Radio", "TV Channels"])
        XCTAssertEqual(library.addAction, .addNetworkStream)
        library.select(.playlists)
        XCTAssertEqual(library.entries.map(\.title), ["Cool Songs", "Anime to Watch"])
        XCTAssertEqual(library.addAction?.title, "Create playlist")
    }

    func testSearchAndPaging() async throws {
        let app = AppModel.mock(.idle)
        let library = app.library
        library.pageSize = 10
        library.searchDebounce = .milliseconds(1)
        library.navigate(to: .folder("anime-kaze"))
        XCTAssertEqual(library.entries.count, 10)
        XCTAssertEqual(library.totalCount, 24)
        XCTAssertTrue(library.hasMore)
        library.loadMoreIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(library.entries.count, 20)
        library.loadMoreIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(library.entries.count, 24)
        XCTAssertFalse(library.hasMore)

        library.searchText = "E07"
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(library.entries.map(\.title), ["Kaze_no_Tabi_E07.mkv"])
    }

    func testMutationsAndPlaylists() async throws {
        let app = AppModel.mock(.idle)
        let library = app.library
        library.navigate(to: .folder(MockDatabase.wandS01Folder))
        let e05 = try XCTUnwrap(library.mediaEntries.first)
        library.setWatched(true, for: [e05])
        XCTAssertEqual(library.entries.last?.media?.id, e05.id, "now watched, sorted last")

        let playlist = try await library.createPlaylist(name: "Weekend", media: [e05])
        XCTAssertEqual(playlist.itemCount, 1)
        library.select(.playlists)
        XCTAssertEqual(library.entries.map(\.title), ["Cool Songs", "Anime to Watch", "Weekend"])
        let stream = try await library.addNetworkStream(urls: [URL(string: "https://iptv.example.com/index.m3u")!], name: "Index")
        XCTAssertEqual(stream.name, "Index")
        library.select(.network)
        XCTAssertEqual(library.entries.map(\.title), ["Podcasts", "Radio", "TV Channels", "Index"])
        XCTAssertEqual(stream.urls.count, 12, "an m3u is saved expanded into its entries")
        XCTAssertEqual(library.entries.last?.destination, .stream(stream.id))

        let all = await library.allMedia(at: .folder("wand"))
        XCTAssertEqual(all.count, 30)
    }

    func testEmptyLibrary() {
        let app = AppModel.mock(.emptyLibrary)
        XCTAssertEqual(app.library.countText, "0 items")
        XCTAssertTrue(app.library.homeSections.isEmpty, "a fresh library shows the empty state, not orphan headings")
        app.library.select(.videos)
        XCTAssertTrue(app.library.entries.isEmpty)
        XCTAssertEqual(app.library.addAction, .add)
        app.library.select(.network)
        XCTAssertEqual(app.library.entries.map(\.title), ["Podcasts", "Radio"], "first launch seeds the default streams")
    }

    func testPlayFromLibraryWithContext() async {
        let app = AppModel.mock(.idle)
        app.library.navigate(to: .folder(MockDatabase.wandS01Folder))
        let episodes = await app.library.allMediaHere()
        let e06 = episodes.first { $0.episode?.episode == 6 }!
        app.play(e06, context: episodes)
        XCTAssertEqual(app.player.media?.id, e06.id)
        XCTAssertEqual(app.queue.items.count, 15)
        XCTAssertEqual(app.queue.currentItem?.media.id, e06.id)
        XCTAssertEqual(app.recents.entries.first?.media.id, e06.id)
    }
}

@MainActor
final class StoreTests: XCTestCase {
    nonisolated private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mxr-tests-\(UUID().uuidString)", isDirectory: true)

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testPresetPersistenceRoundTrip() throws {
        let location = PersistenceLocation.directory(directory)
        let store = PresetStore(location: location)
        XCTAssertEqual(store.presets.map(\.name), ["Default Preset"])
        var style = SubtitleStyle.default
        style.bold = true
        style.textColor = RGBColor(red: 0xB8, green: 0xB8, blue: 0xB8)
        let preset = store.save(PlaybackPreset(name: "Anime", subtitleDelay: .milliseconds(-2_000), subtitleStyle: style, audioLanguage: "Japanese"))
        let episode = MediaItem(id: "ml:x", mrl: "file:///x.mp4", title: "x", kind: .video, episode: EpisodeInfo(showName: "The Wand", season: 1, episode: 2))
        store.assign(preset.id, to: episode)

        let reloaded = PresetStore(location: location)
        XCTAssertEqual(reloaded.presets.map(\.name), ["Default Preset", "Anime"])
        XCTAssertEqual(reloaded.preset(id: preset.id), preset)
        XCTAssertEqual(reloaded.preset(for: episode)?.name, "Anime")
        var other = episode
        other.id = "ml:y"
        other.episode?.episode = 9
        XCTAssertEqual(reloaded.preset(for: other)?.name, "Anime", "presets apply per show, not per file")

        reloaded.rename(id: preset.id, to: "Anime 2")
        reloaded.delete(id: PlaybackPreset.defaultID)
        XCTAssertEqual(PresetStore(location: location).presets.map(\.name), ["Default Preset", "Anime 2"])
        reloaded.delete(id: preset.id)
        let final = PresetStore(location: location)
        XCTAssertEqual(final.presets.count, 1)
        XCTAssertNil(final.preset(for: episode))
    }

    func testPresetCaptureApplyAndAutoApply() {
        let app = AppModel.mock(.playingEpisode)
        XCTAssertEqual(app.activePreset.name, "The Wand Subtitle Preset", "seeded for The Wand")
        app.tracks.setSubtitleDelay(.milliseconds(750))
        app.audioEffects.update { $0.pitch = 2 }
        let preset = app.createPreset(named: "Mine")
        XCTAssertEqual(preset.subtitleDelay, .milliseconds(750))
        XCTAssertEqual(preset.audioEffects?.pitch, 2)
        XCTAssertEqual(app.activePreset.id, preset.id)

        app.selectPreset(.default)
        XCTAssertEqual(app.tracks.subtitleDelay, .zero)
        XCTAssertEqual(app.audioEffects.effects.pitch, 0)
        XCTAssertEqual(app.activePreset.id, PlaybackPreset.defaultID)

        // Auto-apply when another episode of the show starts.
        app.presets.assign(preset.id, to: app.player.media!)
        app.queue.next()
        XCTAssertEqual(app.tracks.subtitleDelay, .milliseconds(750))
        XCTAssertEqual(app.audioEffects.effects.pitch, 2)
    }

    func testRecentAndPinPersistence() {
        let location = PersistenceLocation.directory(directory)
        let recents = RecentStore(location: location)
        let a = MediaItem(url: URL(fileURLWithPath: "/tmp/a.mp4"))
        let b = MediaItem(url: URL(fileURLWithPath: "/tmp/b.mp4"))
        recents.record(a)
        recents.record(b)
        recents.record(a)
        XCTAssertEqual(RecentStore(location: location).entries.map(\.media.fileName), ["a.mp4", "b.mp4"])
        recents.isEnabled = false
        recents.record(MediaItem(url: URL(fileURLWithPath: "/tmp/c.mp4")))
        XCTAssertEqual(recents.entries.count, 2)
        recents.clear()
        XCTAssertTrue(RecentStore(location: location).entries.isEmpty)

        let pins = PinStore(location: location)
        pins.pin(.location(.folder("wand-s01")), title: "S01")
        pins.pin(.location(.playlist("pl-cool-songs")), title: "Cool Songs")
        pins.pin(.media(a), title: "a.mp4")
        pins.pin(.location(.folder("wand-s01")), title: "dup")
        XCTAssertEqual(pins.pins.count, 3)
        pins.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        let reloaded = PinStore(location: location)
        XCTAssertEqual(reloaded.pins.map(\.title), ["a.mp4", "S01", "Cool Songs"])
        XCTAssertTrue(reloaded.isPinned(.location(.playlist("pl-cool-songs"))))
        reloaded.unpin(.media(a))
        XCTAssertEqual(PinStore(location: location).pins.map(\.title), ["S01", "Cool Songs"])
    }

    func testProfiles() {
        let location = PersistenceLocation.directory(directory)
        let profiles = ProfileStore(location: location)
        XCTAssertEqual(profiles.menuTitle, "Profile (Default)")
        let movies = profiles.create(name: "Movies")
        profiles.select(movies)
        XCTAssertEqual(ProfileStore(location: location).menuTitle, "Profile (Movies)")
        XCTAssertEqual(AppModel.mock(.idle).profiles.menuTitle, "Profile (Movies)")
    }

    func testRecentClearHookRunsAfterPersistenceForMenuAndSettings() throws {
        let location = PersistenceLocation.directory(directory)
        let mock = MockBackend(scenario: .idle)
        let app = AppModel(backends: mock.backends, persistence: location, clockTicks: false)
        let media = MediaItem(url: URL(fileURLWithPath: "/tmp/history-test.mp4"))
        var clears = 0
        app.recents.onCleared = {
            clears += 1
            XCTAssertTrue(app.recents.entries.isEmpty)
            XCTAssertTrue(RecentStore(location: location).entries.isEmpty, "The host must observe already persisted app history.")
        }
        app.recents.record(media)
        app.recents.clear()
        XCTAssertEqual(clears, 1)
        app.recents.record(media)
        let row = try XCTUnwrap(app.settings.catalog.allRows.first { $0.action == "clear-history" })
        app.settings.perform(row)
        XCTAssertEqual(clears, 2, "Settings must use the same native-clear hook as Clear Menu.")
        app.recents.onCleared = nil
        app.recents.record(media)
        app.recents.clear()
        XCTAssertEqual(clears, 2, "Stopping the host disconnects the hook.")
    }

    func testLayoutEditingAndPersistence() throws {
        let location = PersistenceLocation.directory(directory)
        let store = LayoutStore(location: location)
        XCTAssertEqual(store.layout(profileID: "movies", kind: .video), .video)
        XCTAssertEqual(PlayerLayout.video.bottom[0].map(\.control), [
            .previous, .playPause, .next, .currentTime, .seekBar, .duration, .volume, .audioTracks, .subtitleTracks, .playbackSettings, .queue,
        ])
        XCTAssertEqual(PlayerControl.tiles.count, 31)
        XCTAssertTrue(PlayerLayout.video.availableTiles.contains(.favorite))
        XCTAssertFalse(PlayerLayout.twoRowExample.availableTiles.contains(.favorite))
        XCTAssertTrue(PlayerLayout.twoRowExample.availableTiles.contains(.divider), "divider is repeatable")

        store.beginEditing(profileID: "movies", kind: .video)
        XCTAssertFalse(store.hasChanges)
        store.updateDraft { $0.insert(LayoutItem(.favorite), in: .bottom(0), at: 3) }
        XCTAssertTrue(store.hasChanges)
        let seek = try XCTUnwrap(store.draft?.bottom[0].first { $0.control == .seekBar })
        store.updateDraft { $0.move(seek.id, to: .bottom(1), at: 0) }
        XCTAssertEqual(store.draft?.bottom.count, 2)
        XCTAssertEqual(store.draft?.bottom[1].map(\.control), [.seekBar])
        store.commit()
        XCTAssertNil(store.draft)

        let reloaded = LayoutStore(location: location)
        let saved = reloaded.layout(profileID: "movies", kind: .video)
        XCTAssertEqual(saved.bottom[0][3].control, .favorite)
        XCTAssertEqual(saved.bottom[1].map(\.control), [.seekBar])
        XCTAssertEqual(reloaded.layout(profileID: "shows", kind: .video), .video, "layouts are per profile")
        reloaded.reset(profileID: "movies", kind: .video)
        XCTAssertEqual(LayoutStore(location: location).layout(profileID: "movies", kind: .video), .video)
    }

    func testRepeatedCustomizationPreservesDraftAndExposesDropTargets() {
        let app = AppModel.mock(.playingEpisode)
        app.interface.isUIHidden = true
        app.beginCustomizing()
        XCTAssertFalse(app.interface.isUIHidden, "Customization must expose the bars that accept dropped controls.")
        app.layouts.updateDraft { layout in
            layout.insert(LayoutItem(.favorite), in: .bottom(0), at: 0)
        }
        let edited = app.layouts.draft
        app.beginCustomizing()
        XCTAssertEqual(app.layouts.draft, edited, "A repeated Customize command must preserve unsaved edits.")
        XCTAssertTrue(app.layouts.hasChanges)
        app.endCustomizing(save: true)
        XCTAssertEqual(app.playerLayout, edited)
        XCTAssertFalse(app.interface.isCustomizing)
        app.beginCustomizing()
        XCTAssertEqual(app.layouts.draft, edited, "A new edit session starts from the saved layout.")
        app.endCustomizing(save: false)
    }

    func testCustomizationExposesBarsFromEveryLibraryPresentation() {
        let mock = MockBackend(scenario: .playingEpisode)
        let app = AppModel(backends: mock.backends, persistence: .inMemory, clockTicks: false)
        for presentation in [LibraryPresentation.full, .compact] {
            app.interface.library = presentation
            app.interface.areBarsVisible = false
            app.beginCustomizing()
            XCTAssertEqual(app.interface.library, .hidden, "Library content must not cover layout drop targets.")
            XCTAssertTrue(app.interface.areBarsVisible)
            app.endCustomizing(save: false)
        }
    }

    func testCustomizationBlocksCommandsThatHideDraftAndPreservesSaveOrCancel() {
        let mock = MockBackend(scenario: .playingEpisode)
        let app = AppModel(backends: mock.backends, persistence: .inMemory, clockTicks: false)
        let blocked: [AppCommand] = [.hideUI, .toggleLibrary, .showFullLibrary]
        for save in [false, true] {
            let original = app.playerLayout
            app.beginCustomizing()
            app.layouts.updateDraft { $0.insert(LayoutItem(.favorite), in: .bottom(0), at: 0) }
            let edited = app.layouts.draft
            for command in blocked {
                XCTAssertFalse(app.canPerform(command))
                app.perform(command)
                XCTAssertFalse(app.interface.isUIHidden)
                XCTAssertEqual(app.interface.library, .hidden)
                XCTAssertEqual(app.layouts.draft, edited)
                XCTAssertTrue(app.interface.isCustomizing)
            }
            app.endCustomizing(save: save)
            XCTAssertEqual(app.playerLayout, save ? edited : original)
            XCTAssertTrue(blocked.allSatisfy(app.canPerform))
        }
        app.perform(.showFullLibrary)
        XCTAssertEqual(app.interface.library, .full)
        app.perform(.hideUI)
        XCTAssertTrue(app.interface.isUIHidden)
    }

    func testAppCustomizingAndOnboarding() {
        let app = AppModel.mock(.music)
        XCTAssertEqual(app.layoutKind, .music)
        XCTAssertTrue(app.playerLayout.bottom[0].contains { $0.control == .backward15 })
        app.perform(.customizePlayer)
        XCTAssertTrue(app.interface.isCustomizing)
        app.layouts.updateDraft { layout in layout.remove(layout.bottom[0][1].id) }
        XCTAssertFalse(app.playerLayout.bottom[0].contains { $0.control == .backward15 }, "draft is shown while editing")
        app.endCustomizing(save: false)
        XCTAssertTrue(app.playerLayout.bottom[0].contains { $0.control == .backward15 })
        XCTAssertFalse(app.interface.isCustomizing)

        XCTAssertFalse(app.needsOnboarding)
        let first = AppModel.mock(.emptyLibrary)
        XCTAssertTrue(first.needsOnboarding)
        first.completeOnboarding()
        XCTAssertFalse(first.needsOnboarding)
    }

    func testInMemoryWritesNothing() {
        let store = PresetStore(location: .inMemory)
        store.save(PlaybackPreset(name: "x"))
        XCTAssertNil(JSONFileStore<[String]>(location: .inMemory, fileName: "presets.json").fileURL)
    }
}
