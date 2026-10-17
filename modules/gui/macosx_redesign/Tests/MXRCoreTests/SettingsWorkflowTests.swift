import XCTest
@testable import MXRCore
@testable import MXRMockBackend

@MainActor
final class SettingsWorkflowTests: XCTestCase {
    func testOSDPreferencesApplyAtStartupAndClampLiveDuration() {
        let mock = MockBackend(scenario: .idle)
        mock.settings.setValue(.bool(false), for: "osd", apply: .nextMedia)
        mock.settings.setValue(.float(0.5), for: "macosx-redesign-osd-duration", apply: .nextMedia)
        let app = AppModel(backends: mock.backends, persistence: .inMemory, clockTicks: false)
        XCTAssertFalse(app.osd.isFeedbackEnabled)
        XCTAssertEqual(app.osd.duration, .seconds(0.5))
        for (value, expected) in [(5.0, 5.0), (0.1, 0.5), (20.0, 5.0), (Double.nan, 1.5), (Double.infinity, 1.5)] {
            mock.settings.setValue(.float(value), for: "macosx-redesign-osd-duration", apply: .nextMedia)
            XCTAssertEqual(app.osd.duration, .seconds(expected))
        }
        mock.settings.resetValue(for: "osd")
        mock.settings.resetValue(for: "macosx-redesign-osd-duration")
        XCTAssertTrue(app.osd.isFeedbackEnabled)
        XCTAssertEqual(app.osd.duration, .seconds(1.5))
    }

    func testDisablingOSDHidesExistingFeedbackAndDropsDisabledKeys() {
        let mock = MockBackend(scenario: .playingEpisode)
        let app = AppModel(backends: mock.backends, persistence: .inMemory, clockTicks: false)
        app.osd.keyPressed(KeyBinding(key: "c"))
        XCTAssertNotNil(app.osd.message)
        mock.settings.setValue(.bool(false), for: "osd", apply: .nextMedia)
        XCTAssertNil(app.osd.message)
        mock.osd.showMessage("Disabled message")
        app.osd.keyPressed(KeyBinding(key: "x"))
        XCTAssertNil(app.osd.message)
        mock.settings.setValue(.bool(true), for: "osd", apply: .nextMedia)
        mock.osd.showMessage("Enabled message")
        XCTAssertEqual(app.osd.message?.text, "Enabled message")
        XCTAssertNil(app.osd.message?.pressedKey, "A key pressed while feedback was disabled must not leak into a later message.")
        app.osd.keyPressed(KeyBinding(key: "z"))
        XCTAssertNotNil(app.osd.message?.pressedKey)
        mock.settings.setValue(.bool(false), for: "osd", apply: .nextMedia)
        mock.settings.setValue(.bool(true), for: "osd", apply: .nextMedia)
        mock.osd.showMessage("Reenabled without another key")
        XCTAssertNil(app.osd.message?.pressedKey, "Disabling feedback must clear an earlier unpaired key.")
    }

    func testRecentPrivacyPreferencesApplyLiveAndExcludeDecodedFilenames() {
        let mock = MockBackend(scenario: .idle)
        let app = AppModel(backends: mock.backends, persistence: .inMemory, clockTicks: false)
        mock.player.load(MediaItem(url: URL(fileURLWithPath: "/tmp/First.mp4")))
        XCTAssertEqual(app.recents.entries.count, 1)
        mock.settings.setValue(.bool(false), for: "save-recentplay", apply: .nextMedia)
        mock.player.load(MediaItem(url: URL(fileURLWithPath: "/tmp/Second.mp4")))
        XCTAssertFalse(app.recents.isEnabled)
        XCTAssertEqual(app.recents.entries.count, 1)
        mock.settings.setValue(.bool(true), for: "save-recentplay", apply: .nextMedia)
        mock.settings.setValue(.string(" secret , PRIVATE, ,"), for: "macosx-redesign-history-exclude", apply: .nextMedia)
        mock.player.load(MediaItem(id: "excluded", mrl: "file:///tmp/My%20Secret.mp4", title: "Public title", kind: .video))
        mock.player.load(MediaItem(url: URL(fileURLWithPath: "/tmp/private-video.mp4")))
        XCTAssertEqual(app.recents.entries.count, 1)
        mock.player.load(MediaItem(url: URL(fileURLWithPath: "/tmp/Third.mp4")))
        XCTAssertEqual(app.recents.entries.count, 2)
        XCTAssertTrue(app.recents.isEnabled)
    }

    func testRememberPositionDisablesActiveAndFutureExcludedRestorePrompts() {
        let mock = MockBackend(scenario: .playingEpisode)
        let app = AppModel(backends: mock.backends, persistence: .inMemory, clockTicks: false)
        mock.player.askRestore(at: .seconds(90))
        XCTAssertNotNil(app.player.restorePrompt)
        mock.settings.setValue(.bool(false), for: "macosx-redesign-remember-position", apply: .nextMedia)
        XCTAssertNil(app.player.restorePrompt)
        XCTAssertNil(mock.player.restorePrompt)
        XCTAssertEqual(mock.player.commandLog.last, "answerRestorePrompt(false)")
        mock.player.askRestore(at: .seconds(100))
        XCTAssertNil(app.player.restorePrompt)
        mock.settings.setValue(.bool(true), for: "macosx-redesign-remember-position", apply: .nextMedia)
        mock.player.askRestore(at: .seconds(120))
        XCTAssertNotNil(app.player.restorePrompt)
        mock.settings.setValue(.string("wand"), for: "macosx-redesign-history-exclude", apply: .nextMedia)
        XCTAssertNil(app.player.restorePrompt, "Excluded filenames cannot ask to resume even when remembering is enabled.")
    }

    func testVolumePreferencesControlRangeStepAndApplyStartupOnce() {
        let mock = MockBackend(scenario: .idle)
        mock.player.configureVolume(0.7)
        mock.settings.setValue(.bool(false), for: "volume-save", apply: .nextMedia)
        mock.settings.setValue(.integer(150), for: "macosx-redesign-startup-volume", apply: .nextMedia)
        let app = AppModel(backends: mock.backends, persistence: .inMemory, clockTicks: false)
        XCTAssertEqual(app.player.volume, 1.5)
        XCTAssertEqual(app.player.maximumVolume, 2)
        XCTAssertEqual(app.player.volumeStep, 0.01)
        mock.settings.setValue(.integer(5), for: "macosx-redesign-volume-step", apply: .nextMedia)
        app.player.adjustVolume(steps: 1)
        XCTAssertEqual(app.player.volume, 1.55, accuracy: 0.0001)
        mock.settings.setValue(.integer(100), for: "macosx-redesign-max-volume", apply: .nextMedia)
        XCTAssertEqual(app.player.volume, 1)
        app.player.setVolume(2)
        XCTAssertEqual(app.player.volume, 1)
        mock.settings.setValue(.integer(300), for: "macosx-redesign-max-volume", apply: .nextMedia)
        app.player.setVolume(2.5)
        XCTAssertEqual(app.player.volume, 2.5)
        mock.settings.setValue(.integer(20), for: "macosx-redesign-startup-volume", apply: .nextMedia)
        XCTAssertEqual(app.player.volume, 2.5, "Editing startup volume must not reset current playback volume.")
        mock.settings.setValue(.integer(1000), for: "macosx-redesign-volume-step", apply: .nextMedia)
        XCTAssertEqual(app.player.volumeStep, 0.5)
        mock.settings.setValue(.integer(-1), for: "macosx-redesign-max-volume", apply: .nextMedia)
        XCTAssertEqual(app.player.maximumVolume, 1)
        app.player.setVolume(.nan)
        XCTAssertEqual(app.player.volume, 1, "Invalid volume must not reach the audio device.")

        let remembers = MockBackend(scenario: .idle)
        remembers.player.configureVolume(0.7)
        remembers.settings.setValue(.bool(true), for: "volume-save", apply: .nextMedia)
        let rememberedApp = AppModel(backends: remembers.backends, persistence: .inMemory, clockTicks: false)
        XCTAssertEqual(rememberedApp.player.volume, 0.7)
    }

    func testPlayerControlPreferencesHonorAllModesAndFullscreenVisibility() {
        let mock = MockBackend(scenario: .playingEpisode)
        let app = AppModel(backends: mock.backends, persistence: .inMemory, clockTicks: false)
        for (value, windowed, fullscreen) in [("always", true, true), ("fullscreen", false, true), ("never", false, false)] {
            mock.settings.setValue(.string(value), for: "macosx-redesign-autohide", apply: .nextMedia)
            mock.player.setFullscreen(false)
            XCTAssertEqual(app.shouldAutoHideControls, windowed)
            mock.player.setFullscreen(true)
            XCTAssertEqual(app.shouldAutoHideControls, fullscreen)
        }
        mock.settings.setValue(.bool(false), for: "macosx-redesign-fullscreen-controls", apply: .nextMedia)
        XCTAssertFalse(app.controlsAllowed)
        mock.player.setFullscreen(false)
        XCTAssertTrue(app.controlsAllowed)
        app.interface.isUIHidden = true
        XCTAssertFalse(app.controlsAllowed)
    }

    func testPlayerControlDelayClampsAndFallsBackToSchemaDefaults() {
        let mock = MockBackend(scenario: .idle)
        let app = AppModel(backends: mock.backends, persistence: .inMemory, clockTicks: false)
        XCTAssertEqual(app.controlsAutoHideMode, .fullscreen)
        XCTAssertEqual(app.controlsAutoHideDelay, 0.5)
        XCTAssertTrue(app.showsFullscreenControls)
        XCTAssertTrue(app.usesFilenameAsTitle)
        XCTAssertFalse(app.startsInCompactMode)
        for (value, expected) in [(-1.0, 0.0), (12.0, 10.0), (2.5, 2.5), (Double.nan, 0.5), (Double.infinity, 0.5)] {
            mock.settings.setValue(.float(value), for: "macosx-redesign-autohide-delay", apply: .nextMedia)
            XCTAssertEqual(app.controlsAutoHideDelay, expected)
        }
        mock.settings.setValue(.string("unexpected"), for: "macosx-redesign-autohide", apply: .nextMedia)
        XCTAssertEqual(app.controlsAutoHideMode, .fullscreen)
        let revision = app.settings.revision
        mock.settings.setValue(.string("never"), for: "macosx-redesign-autohide", apply: .nextMedia)
        XCTAssertGreaterThan(app.settings.revision, revision)
        XCTAssertEqual(app.controlsAutoHideMode, .never)
    }

    func testCustomizationOverridesFullscreenControlPreferenceUntilSaveOrCancel() {
        let mock = MockBackend(scenario: .playingEpisode)
        let app = AppModel(backends: mock.backends, persistence: .inMemory, clockTicks: false)
        mock.settings.setValue(.bool(false), for: "macosx-redesign-fullscreen-controls", apply: .nextMedia)
        mock.player.setFullscreen(true)
        XCTAssertFalse(app.controlsAllowed)
        for save in [false, true] {
            app.beginCustomizing()
            XCTAssertTrue(app.controlsAllowed, "Fullscreen layout editing must expose editable bars.")
            app.endCustomizing(save: save)
            XCTAssertFalse(app.controlsAllowed, "Playback must honor the preference after editing ends.")
        }
    }

    func testWindowTitleUsesDecodedLocalFilenameAndKeepsNetworkTitle() {
        let mock = MockBackend(scenario: .idle)
        let app = AppModel(backends: mock.backends, persistence: .inMemory, clockTicks: false)
        XCTAssertEqual(app.windowTitle, "VLC Media Player")
        // D042: a clean title, never the extension (Figma 2425:13639, video 09m30.1); the full name stays available.
        mock.player.load(MediaItem(id: "local", mrl: "file:///tmp/My%20Movie.mp4", title: "My Movie.mp4", kind: .video))
        XCTAssertEqual(app.windowTitle, "My Movie")
        XCTAssertEqual(app.windowTitleFileName, "My Movie.mp4")
        mock.player.load(MediaItem(id: "tagged", mrl: "file:///tmp/The_Wand_S01E04.mp4", title: "Pilot", kind: .video))
        XCTAssertEqual(app.windowTitle, "The Wand S01E04", "on: the file name, underscores read as spaces, no extension")
        mock.player.load(MediaItem(id: "local", mrl: "file:///tmp/My%20Movie.mp4", title: "Metadata Movie", kind: .video))
        XCTAssertEqual(app.windowTitle, "My Movie", "on: the file name wins over the media title")
        mock.settings.setValue(.bool(false), for: "macosx-redesign-title-filename", apply: .nextMedia)
        XCTAssertEqual(app.windowTitle, "Metadata Movie", "off: the media title")
        mock.player.load(MediaItem(id: "untagged", mrl: "file:///tmp/My_Movie.mp4", title: "My_Movie.mp4", kind: .video))
        XCTAssertEqual(app.windowTitle, "My_Movie", "off: an untagged file still drops its extension")
        mock.settings.setValue(.bool(true), for: "macosx-redesign-title-filename", apply: .nextMedia)
        mock.player.load(MediaItem(id: "radio", mrl: "https://radio.example/live", title: "Radio Station", kind: .stream))
        XCTAssertEqual(app.windowTitle, "Radio Station")
    }

    func testFreetypeCachedStyleSettingsUseNextMediaWhileDynamicStyleStaysLive() throws {
        let catalog = SettingsCatalog.bundled
        for name in ["freetype-font", "freetype-bold", "freetype-opacity", "freetype-outline-color", "macosx-redesign-sub-shadow", "freetype-shadow-color", "freetype-shadow-distance", "freetype-shadow-angle"] {
            let row = try XCTUnwrap(catalog.allRows.first { $0.option == name })
            XCTAssertEqual(row.apply, .nextMedia, "Freetype reads \(name) when creating its renderer.")
        }
        for name in ["freetype-color", "freetype-outline-thickness", "macosx-redesign-sub-background", "freetype-background-color", "freetype-background-opacity", "sub-text-scale"] {
            let row = try XCTUnwrap(catalog.allRows.first { $0.option == name })
            XCTAssertEqual(row.apply, .live("vout"))
        }
    }

    func testEngineHistoryPreferencesApplyToNextInput() throws {
        let catalog = SettingsCatalog.bundled
        for name in ["save-recentplay", "macosx-redesign-remember-position", "macosx-redesign-history-exclude"] {
            let row = try XCTUnwrap(catalog.allRows.first { $0.option == name })
            XCTAssertEqual(row.apply, .nextMedia, "The engine inherits \(name) when creating its input.")
        }
    }

    func testLibraryOutputActionRetainsSelectedMediaAndClearsForGlobalCommand() {
        let app = AppModel.mock(.playingEpisode)
        let chosen = MediaItem(url: URL(fileURLWithPath: "/tmp/chosen.mp4"))
        app.presentOutput(media: chosen, mode: .convert)
        XCTAssertEqual(app.interface.pendingOutputSource, chosen)
        XCTAssertEqual(app.interface.sheet, .convert)
        XCTAssertNotEqual(app.interface.pendingOutputSource?.id, app.player.media?.id)
        app.interface.dismissSheet()
        app.perform(.stream)
        XCTAssertNil(app.interface.pendingOutputSource)
        XCTAssertEqual(app.interface.sheet, .stream)
    }

    func testDismissingAppErrorDoesNotSendUnknownDialogIDToEngine() throws {
        let mock = MockBackend(scenario: .idle)
        let app = AppModel(backends: mock.backends, persistence: .inMemory, clockTicks: false)
        app.dialogs.presentError(BackendOperationError.invalidInput("Source could not be opened."), title: "Playback failed")
        let request = try XCTUnwrap(app.dialogs.current)
        app.dialogs.dismiss(request)
        XCTAssertTrue(app.dialogs.requests.isEmpty)
        XCTAssertTrue(mock.dialogs.answers.isEmpty)
    }

    func testCurrentProfilePersistsEditsWithoutSwitching() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let backend = MockBackend(scenario: .idle)
        let app = AppModel(backends: backend.backends, persistence: .directory(dir), clockTicks: false)
        let row = try XCTUnwrap(app.settings.catalog.allRows.first { $0.option == AppearanceModel.accentOption })
        app.settings.setValue(.string("red"), for: row)
        let reloaded = ProfileStore(location: .directory(dir))
        XCTAssertEqual(reloaded.current.settings[AppearanceModel.accentOption], .string("red"))
    }

    func testDialogRequestsKeepSelectedLibraryMedia() {
        let app = AppModel.mock(.idle)
        let media = [MediaItem(url: URL(fileURLWithPath: "/tmp/selected.mp4"))]
        app.presentNewPlaylist(media: media)
        XCTAssertEqual(app.interface.pendingPlaylistMedia, media)
        XCTAssertEqual(app.interface.sheet, .newPlaylist)
        app.interface.dismissSheet()
        app.presentAddSubtitles(media: media)
        XCTAssertEqual(app.interface.subtitleTargetMedia, media)
        XCTAssertEqual(app.interface.sheet, .addSubtitles(scope: .file, source: .computer))
    }

    func testProfilesRestoreIndependentSettings() throws {
        let app = AppModel.mock(.idle)
        let row = try XCTUnwrap(app.settings.catalog.allRows.first { $0.option == AppearanceModel.accentOption })
        app.settings.setValue(.string("red"), for: row)
        let second = app.profiles.create(name: "Music settings")
        app.profiles.select(second)
        app.settings.setValue(.string("blue"), for: row)
        let first = try XCTUnwrap(app.profiles.profiles.first { $0.id == "movies" })
        app.profiles.select(first)
        XCTAssertEqual(app.settings.string(row), "red")
        app.profiles.select(second)
        XCTAssertEqual(app.settings.string(row), "blue")
    }

    func testSettingsActionsResetAndExposeEngineSchema() throws {
        let app = AppModel.mock(.idle)
        let accent = try XCTUnwrap(app.settings.catalog.allRows.first { $0.option == AppearanceModel.accentOption })
        app.settings.setValue(.string("blue"), for: accent)
        let reset = try XCTUnwrap(app.settings.catalog.allRows.first { $0.action == "reset-all-settings" })
        app.settings.perform(reset)
        XCTAssertEqual(app.settings.string(accent), "orange")
        let modules = try XCTUnwrap(app.settings.catalog.allRows.first { $0.action == "show-all-modules" })
        app.settings.perform(modules)
        XCTAssertTrue(app.settings.showsAllModules)
        XCTAssertFalse(app.settings.allModuleOptions.isEmpty)
    }

    /// C-15 (Figma 6575:17137): the Extensions page ends with an "Advanced Options" bar that has a
    /// working row outside developer mode, and "Load add-ons on startup" has no ⓘ.
    func testExtensionsPageHasAdvancedOptionsAndNoInfoOnStartupToggle() throws {
        let app = AppModel.mock(.idle)
        let category = try XCTUnwrap(app.settings.catalog.category("extensions"))
        let advanced = category.advancedSections.flatMap { app.settings.visibleRows(of: $0) }
        XCTAssertEqual(advanced.compactMap(\.action), ["open-extensions-folder"], "developer mode off: only the folder row")
        let startup = try XCTUnwrap(category.basicSections.flatMap(\.rows).first { $0.option == "lua" })
        XCTAssertNil(app.settings.info(for: startup))
        // A backend that cannot locate the folder says so instead of doing nothing.
        let folder = try XCTUnwrap(advanced.first)
        app.settings.perform(folder)
        XCTAssertEqual(app.settings.actionMessage, BackendOperationError.unsupported("Opening the extensions folder").localizedDescription)
    }

    /// A restart-only option stays marked until the app restarts; others never are.
    func testRestartOptionsAreMarkedPendingAfterAChange() throws {
        let app = AppModel.mock(.idle)
        let startup = try XCTUnwrap(app.settings.catalog.allRows.first { $0.option == "lua" })
        XCTAssertEqual(startup.apply, .restart)
        XCTAssertFalse(app.settings.needsRestart(startup))
        app.settings.setValue(.bool(false), for: startup)
        XCTAssertTrue(app.settings.needsRestart(startup))
        XCTAssertEqual(app.settings.value(for: startup), .bool(false))
        let live = try XCTUnwrap(app.settings.catalog.allRows.first { $0.option == "playlist-autostart" })
        app.settings.setValue(.bool(false), for: live)
        XCTAssertFalse(app.settings.needsRestart(live))
    }

    func testOpeningOutputOptionsOnUnsupportedBackendFailsWithoutClearingQueue() throws {
        let app = AppModel.mock(.playingEpisode)
        let old = app.queue.items
        XCTAssertThrowsError(try app.open(urls: [URL(fileURLWithPath: "/tmp/a.mp4")], inputOptions: [":sout=#std{access=file}"]))
        XCTAssertEqual(app.queue.items, old)
    }
}
