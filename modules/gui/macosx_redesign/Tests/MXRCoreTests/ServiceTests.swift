import XCTest
@testable import MXRCore
@testable import MXRMockBackend

@MainActor
final class ShortcutsAndOSDTests: XCTestCase {
    func testOSDAnnouncesVisibleTextAndHonorsFeedbackPreference() {
        let backend = MockBackend(scenario: .idle)
        let osd = OSDModel(backend: backend.osd)
        var announcements: [String] = []
        osd.announce = { announcements.append($0) }
        osd.show("Volume: 50%", pressedKey: "Up")
        XCTAssertEqual(announcements, ["Volume: 50%"])
        osd.isFeedbackEnabled = false
        osd.show("Suppressed")
        osd.showNotice("Playback failed")
        XCTAssertEqual(announcements, ["Volume: 50%", "Playback failed"])
        osd.hide()
    }

    func testDispatchShowsPressedKeyAndEngineText() async throws {
        let backend = MockBackend(scenario: .playingMovie)
        let app = backend.makeAppModel(clockTicks: false)
        let c = try XCTUnwrap(KeyBinding(vlcString: "c"))
        XCTAssertEqual(app.shortcuts.action(for: c)?.id, "crop")
        XCTAssertTrue(app.shortcuts.handle(c))
        XCTAssertEqual(backend.shortcuts.triggered, ["crop"])
        XCTAssertEqual(app.videoEffects.effects.crop, "16:10")
        XCTAssertEqual(app.osd.message?.text, "Crop: 16:10")
        XCTAssertEqual(app.osd.message?.pressedKeyText, "Pressed C")
        XCTAssertFalse(app.shortcuts.handle(KeyBinding(key: "y")))

        app.osd.duration = .milliseconds(30)
        app.osd.show("Hello")
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertNil(app.osd.message)
    }

    func testAppActionsRunCommands() throws {
        let app = AppModel.mock(.playingEpisode)
        XCTAssertNil(app.interface.rightPanel)
        XCTAssertTrue(app.shortcuts.handle(try XCTUnwrap(KeyBinding(vlcString: "q"))))
        XCTAssertEqual(app.interface.rightPanel, .queue(.queue))
        // D026: Hide UI is ⌘\ on the Mac.
        XCTAssertTrue(app.shortcuts.handle(try XCTUnwrap(KeyBinding(vlcString: "Command+\\"))))
        XCTAssertTrue(app.interface.isUIHidden)
        XCTAssertEqual(app.osd.message?.pressedKey, "⌘\\")
    }

    func testDraftEditingAndConflicts() throws {
        let app = AppModel.mock(.idle)
        let shortcuts = app.shortcuts
        let f = try XCTUnwrap(KeyBinding(vlcString: "Command+f"))
        XCTAssertEqual(shortcuts.conflicts(for: f, excluding: "stop").map(\.id), ["toggle-fullscreen"])
        shortcuts.setBinding(f, for: "stop")
        XCTAssertTrue(shortcuts.hasChanges)
        XCTAssertNil(shortcuts.action(for: f).map { $0.id == "stop" ? $0 : nil } ?? nil, "draft is not live before Save")
        shortcuts.discardDraft()
        XCTAssertFalse(shortcuts.hasChanges)

        let k = try XCTUnwrap(KeyBinding(vlcString: "Command+k"))
        shortcuts.setBinding(k, for: "stop")
        shortcuts.saveDraft()
        XCTAssertEqual(shortcuts.action(for: k)?.id, "stop")
        XCTAssertEqual(shortcuts.primaryBinding(for: "stop"), k)
        shortcuts.resetAll()
        XCTAssertEqual(shortcuts.primaryBinding(for: "stop")?.vlcString, "Command+.")
    }

    func testDialogFiltering() {
        let app = AppModel.mock(.idle)
        let groups = app.shortcuts.filteredGroups
        XCTAssertEqual(groups.first?.group.title, "Basic")
        XCTAssertEqual(groups.first?.actions.prefix(4).map(\.title), [
            "Toggle fullscreen", "Exit fullscreen / close dialog", "Show playback position and time", "Show interface controls in fullscreen",
        ])
        app.shortcuts.searchText = "space"
        app.shortcuts.searchField = .hotkey
        XCTAssertEqual(app.shortcuts.filteredGroups.flatMap(\.actions).map(\.id), ["play-pause"])
        app.shortcuts.searchField = .action
        XCTAssertTrue(app.shortcuts.filteredGroups.isEmpty)
    }
}

@MainActor
final class SettingsTests: XCTestCase {
    private let catalogText = """
    // comment allowed (JSON5)
    {
      version: 1,
      categories: [
        { id: "subtitles", group: "media", sidebar: "Subtitles", title: "Subtitle Defaults", icon: "settings-subtitles",
          sections: [
            { title: "Loading Subtitles", rows: [
              { option: "sub-autodetect-file", control: "toggle", label: "Load subtitle files automatically", info: "Looks next to the video.", mock: true },
              { option: "sub-autodetect-fuzzy", control: "dropdown", label: "File name matching",
                choices: [[0, "Off"], [1, "Any title"], [2, "Contains title"], [3, "Title with extra characters"], [4, "Exact title match"]], mock: 3 },
            ]},
            { title: "Advanced Options", advanced: true, rows: [
              { option: "sub-margin", control: "number", label: "Subtitle offset", unit: "px", min: -100, max: 100, mock: 0,
                enabledWhen: { option: "sub-autodetect-file", equals: true } },
            ]},
          ]},
        { id: "network", group: "system", sidebar: "Network", title: "Network Connections & Security", icon: "settings-network",
          sections: [ { title: "Buffering", rows: [
              { id: "buffering", control: "dropdown", label: "Buffering", apply: "restart", composite: [
                { title: "Normal", values: { "file-caching": 1000, "network-caching": 1000 } },
                { title: "Large", values: { "file-caching": 3000, "network-caching": 5000 } },
              ]},
              { action: "clear-history", control: "button", label: "Clear history now", buttonTitle: "Clear" },
          ]}]},
      ],
    }
    """

    func testCatalogDecodesAndModelWorks() throws {
        let catalog = try SettingsCatalog.decode(json5: Data(catalogText.utf8))
        XCTAssertEqual(catalog.categories.map(\.id), ["subtitles", "network"])
        XCTAssertEqual(catalog.category("subtitles")?.advancedSections.count, 1)
        XCTAssertEqual(catalog.referencedOptions, ["sub-autodetect-file", "sub-autodetect-fuzzy", "sub-margin", "file-caching", "network-caching"])

        let backend = MockBackend(scenario: .idle, settingsCatalog: catalog)
        let app = AppModel(backends: backend.backends, persistence: .inMemory, settingsCatalog: catalog, clockTicks: false)
        let settings = app.settings
        XCTAssertEqual(settings.groupedCategories.map(\.group), [.media, .system])
        let rows = try XCTUnwrap(catalog.category("subtitles")).sections.flatMap(\.rows)
        let autodetect = rows[0], fuzzy = rows[1], margin = rows[2]
        XCTAssertTrue(settings.bool(autodetect))
        XCTAssertEqual(settings.selectedChoiceTitle(for: fuzzy), "Title with extra characters")
        settings.setValue(.integer(1), for: fuzzy)
        XCTAssertEqual(settings.selectedChoiceTitle(for: fuzzy), "Any title")
        XCTAssertTrue(settings.isEnabled(margin))
        settings.setValue(.bool(false), for: autodetect)
        XCTAssertFalse(settings.isEnabled(margin))
        XCTAssertEqual(settings.info(for: autodetect), "Looks next to the video.")

        let buffering = try XCTUnwrap(catalog.category("network")).sections[0].rows[0]
        XCTAssertEqual(settings.compositeSelection(for: buffering), 0)
        settings.selectComposite(1, for: buffering)
        XCTAssertEqual(settings.selectedChoiceTitle(for: buffering), "Large")
        XCTAssertEqual(backend.settings.value(for: "network-caching"), .integer(5000))

        settings.searchText = "matching"
        XCTAssertEqual(settings.searchResults.first?.rows.map(\.label), ["File name matching"])

        settings.resetCategory("subtitles")
        XCTAssertEqual(settings.selectedChoiceTitle(for: fuzzy), "Title with extra characters")
        settings.saveNow()
        XCTAssertGreaterThan(backend.settings.saveCount, 0)

        app.recents.record(MediaItem(url: URL(fileURLWithPath: "/tmp/a.mp4")))
        settings.perform(catalog.category("network")!.sections[0].rows[1])
        XCTAssertTrue(app.recents.entries.isEmpty)
    }

    func testBundledCatalogLoads() throws {
        let url = try XCTUnwrap(MXRResources.url(forResource: "settings-map", withExtension: "json5"))
        let catalog = try SettingsCatalog.decode(json5: Data(contentsOf: url))
        XCTAssertEqual(catalog.categories.map(\.sidebar), [
            "General", "Interface", "Privacy", "Controls", "Playback", "Video", "Audio", "Subtitles", "Library",
            "Network", "Performance", "Recording", "Extensions",
        ])
        XCTAssertEqual(catalog.categories.map(\.title), [
            "Global Settings", "Interface Settings", "Privacy Settings", "Mouse, Keyboard & Remote Controls", "Playback Preferences",
            "Video Defaults", "Audio Defaults", "Subtitle Defaults", "Playlists, Folders & Files", "Network Connections & Security",
            "Performance Settings", "Recording, Casting & Streaming Out", "Add-ons & Scripts",
        ])
        var ids = Set<String>()
        for category in catalog.categories {
            XCTAssertFalse(category.basicSections.isEmpty, category.id)
            for row in category.sections.flatMap(\.rows) {
                XCTAssertTrue(ids.insert(category.id + "/" + row.id).inserted, "duplicate row id \(row.id)")
                switch row.control {
                case .button: XCTAssertNotNil(row.action, row.id)
                case .extensionList: break
                case .dropdown, .segmented, .swatches:
                    XCTAssertTrue(row.choices != nil || row.composite != nil, "\(row.id) needs choices")
                default: XCTAssertNotNil(row.option, row.id)
                }
                if let choices = row.choices, let mock = row.mock {
                    XCTAssertTrue(choices.contains { $0.value.isEquivalent(to: mock) }, "\(row.id): mock \(mock) is not a choice")
                }
            }
        }
        // The mock backend starts from the Figma values.
        let app = AppModel(backends: MockBackend(scenario: .idle, settingsCatalog: catalog).backends, persistence: .inMemory,
                           settingsCatalog: catalog, clockTicks: false)
        let subtitles = try XCTUnwrap(catalog.category("subtitles"))
        let fuzzy = try XCTUnwrap(subtitles.sections.flatMap(\.rows).first { $0.option == "sub-autodetect-fuzzy" })
        XCTAssertEqual(app.settings.selectedChoiceTitle(for: fuzzy), "Title with extra characters")
        let sizeRows = subtitles.sections.flatMap(\.rows).filter { $0.label == "Font size" }
        XCTAssertEqual(sizeRows.filter(app.settings.isVisible).map(\.option), ["sub-text-scale"])
        let buffering = try XCTUnwrap(catalog.category("network")?.sections[0].rows[0])
        XCTAssertEqual(app.settings.selectedChoiceTitle(for: buffering), "Normal")
        let precise = try XCTUnwrap(catalog.allRows.first { $0.option == "input-fast-seek" })
        XCTAssertTrue(app.settings.bool(precise), "inverted toggle reads ON for input-fast-seek=false")
        app.settings.setValue(.bool(false), for: precise)
        XCTAssertEqual(app.backends.settings.value(for: "input-fast-seek"), .bool(true))
        let startup = try XCTUnwrap(catalog.allRows.first { $0.option == "volume-save" })
        XCTAssertEqual(app.settings.secondaryValue(for: startup), .integer(200))
        XCTAssertEqual(app.settings.selectedChoiceTitle(for: startup), "Remember last volume")
        XCTAssertEqual(SettingsCatalog.bundled.categories.count, 13)
    }

    func testAppearance() {
        let app = AppModel.mock(.idle)
        XCTAssertEqual(app.appearance.theme, .dark)
        app.appearance.setTheme(.light)
        app.appearance.setAccent(.pink)
        XCTAssertEqual(app.backends.settings.value(for: AppearanceModel.themeOption), .string("light"))
        XCTAssertEqual(AppearanceModel(settings: app.backends.settings).accent, .pink)
    }
}

@MainActor
final class InterfaceAndDialogTests: XCTestCase {
    func testPanelToggling() {
        let ui = InterfaceModel()
        ui.toggleTracks(.audio)
        XCTAssertEqual(ui.rightPanel, .tracks(.audio))
        XCTAssertTrue(ui.isTracksPanelOpen)
        ui.toggleTracks(.subtitles)
        XCTAssertEqual(ui.rightPanel, .tracks(.subtitles))
        ui.toggleTracks(.subtitles)
        XCTAssertNil(ui.rightPanel)
        ui.toggleSidebar(.audio)
        ui.toggleSidebar()
        XCTAssertNil(ui.rightPanel)
        ui.toggleSidebar()
        XCTAssertEqual(ui.rightPanel, .sidebar(.audio), "remembers the last sidebar tab")
        ui.showPreferences(for: .subtitles)
        XCTAssertEqual(ui.rightPanel, .sidebar(.subtitles))
        ui.toggleQueuePanel(.chapters)
        XCTAssertEqual(ui.rightPanel, .queue(.chapters))
        ui.toggleQueuePanel()
        XCTAssertNil(ui.rightPanel)
        ui.toggleCompactLibrary()
        XCTAssertEqual(ui.library, .compact)
        ui.toggleTimeDisplay()
        XCTAssertEqual(ui.timeDisplay, .remaining)
    }

    func testCommands() {
        let app = AppModel.mock(.playingEpisode)
        XCTAssertEqual(app.player.media?.isFavorite, false)
        app.perform(.favoriteCurrent)
        XCTAssertEqual(app.player.media?.isFavorite, true)
        app.perform(.favoriteCurrent)
        XCTAssertEqual(app.player.media?.isFavorite, false)
        app.perform(.openNetworkStream)
        XCTAssertEqual(app.interface.sheet, .openNetworkStream)
        XCTAssertFalse(app.canPerform(.openFiles))
        app.perform(.openFiles)
        XCTAssertNil(app.interface.fileRequest)
        XCTAssertEqual(app.interface.sheet, .openNetworkStream)
        app.interface.dismissSheet()
        app.perform(.openFiles)
        XCTAssertEqual(app.interface.fileRequest, .openFiles)
        app.complete(.openFiles, urls: [URL(fileURLWithPath: "/tmp/z.mkv")])
        XCTAssertNil(app.interface.fileRequest)
        XCTAssertEqual(app.player.media?.fileName, "z.mkv")
        XCTAssertFalse(app.canPerform(.previous))
        app.perform(.toggleFullscreen)
        XCTAssertTrue(app.player.isFullscreen)
        XCTAssertEqual(AppCommand.appMenu.compactMap { $0?.title }, [
            "Open File(s)", "Open Folder", "Open Network Stream", "Open Disc", "Open Capture Device", "Convert",
            "Keyboard Shortcuts", "Customize Player", "Settings", "About VLC",
        ])
    }

    func testDialogs() {
        let backend = MockBackend(scenario: .idle)
        let app = backend.makeAppModel(clockTicks: false)
        let login = backend.dialogs.presentSampleLogin()
        let question = backend.dialogs.presentSampleQuestion()
        XCTAssertEqual(app.dialogs.current?.id, login.id)
        app.dialogs.submitLogin(login, username: "me", password: "secret", store: false)
        XCTAssertEqual(app.dialogs.current?.id, question.id)
        app.dialogs.choose(question, action: 2)
        XCTAssertNil(app.dialogs.current)
        XCTAssertEqual(backend.dialogs.answers, ["login:\(login.id):me", "action:\(question.id):2"])

        let progress = backend.dialogs.present(title: "Indexing", text: "…", kind: .progress(isIndeterminate: false, value: 0, cancel: "Cancel"))
        app.dialogs.updateProgress(id: progress.id, value: 0.5, text: "Half")
        XCTAssertEqual(app.dialogs.current?.kind, .progress(isIndeterminate: false, value: 0.5, cancel: "Cancel"))
        app.dialogs.cancel(id: progress.id)
        XCTAssertNil(app.dialogs.current)
    }

    func testSeekPreviewQuantizesAndLoads() async throws {
        let backend = MockBackend(scenario: .playingEpisode)
        let app = backend.makeAppModel(clockTicks: false)
        XCTAssertEqual(SeekPreviewModel.quantum(for: .hms(0, 25, 40)), .seconds(5.133333))
        XCTAssertEqual(SeekPreviewModel.quantum(for: .seconds(100)), .seconds(2))
        app.seekPreview.debounce = .milliseconds(5)
        app.seekPreview.hover(at: .seconds(130))
        app.seekPreview.hover(at: .seconds(131))
        XCTAssertEqual(app.seekPreview.time, .seconds(131))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNotNil(app.seekPreview.image)
        XCTAssertEqual(backend.thumbnails.seekPreviewRequests, 1, "same slot is requested once")
        app.seekPreview.end()
        XCTAssertNil(app.seekPreview.image)
        XCTAssertNil(app.seekPreview.time)
    }

    func testThumbnailsAndWaveformAreDeterministic() async throws {
        let backend = MockBackend(scenario: .music)
        let song = try XCTUnwrap(backend.library.mediaItem(id: MockDatabase.untangleID))
        let a = await backend.thumbnails.waveform(for: song, bins: 64)
        let b = await MockBackend(scenario: .music).thumbnails.waveform(for: song, bins: 64)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a?.count, 64)
        XCTAssertTrue(a?.allSatisfy { $0 > 0 && $0 <= 1 } ?? false)
        let image = backend.thumbnails.cachedArtwork(for: song, maxPixelSize: CGSize(width: 64, height: 64))
        XCTAssertEqual(image?.width, 64)
        XCTAssertEqual(image?.height, 64)
    }
}
