import AppKit
import Foundation
import Observation

/// The root object: every model, built once from a ``Backends`` set and injected into SwiftUI with
/// ``SwiftUI/View/appModel(_:)``. Also coordinates cross-model behavior (presets per show, recents,
/// OSD "Pressed C", sleep timer) and performs ``AppCommand``s.
@MainActor
@Observable
public final class AppModel {
    @ObservationIgnored public let backends: Backends
    public var capabilities: BackendCapabilities { backends.capabilities }

    public let player: PlayerModel
    public let clock: PlaybackClock
    public let queue: QueueModel
    public let tracks: TracksModel
    public let videoEffects: VideoEffectsModel
    public let audioEffects: AudioEffectsModel
    public let chapters: ChaptersModel
    public let bookmarks: BookmarksModel
    public let library: LibraryModel
    public let settings: SettingsModel
    public let shortcuts: ShortcutsModel
    public let output: OutputModel
    public let renderers: RendererModel
    public let osd: OSDModel
    public let dialogs: DialogModel
    public let extensions: ExtensionsModel
    public let seekPreview: SeekPreviewModel
    public let interface: InterfaceModel
    public let appearance: AppearanceModel
    public let presets: PresetStore
    public let recents: RecentStore
    public let pins: PinStore
    public let profiles: ProfileStore
    public let layouts: LayoutStore

    /// Apply the show's preset automatically when an episode of an assigned show starts.
    @ObservationIgnored public var appliesPresetsAutomatically = true
    @ObservationIgnored private var lastMediaID: String?

    /// Builds every model.
    /// - Parameters:
    ///   - backends: the engine (VLC) or the mock.
    ///   - persistence: where app-side stores live; `.inMemory` for previews and snapshots.
    ///   - settingsCatalog: the settings UI structure (defaults to the bundled mapping file).
    ///   - clockTicks: let ``PlaybackClock`` wake itself each second (false in tests).
    public init(backends: Backends, persistence: PersistenceLocation = .applicationSupport,
                settingsCatalog: SettingsCatalog = .bundled, clockTicks: Bool = true) {
        self.backends = backends
        player = PlayerModel(backend: backends.player)
        clock = PlaybackClock(source: backends.clock, schedulesTicks: clockTicks)
        queue = QueueModel(backend: backends.queue)
        tracks = TracksModel(backend: backends.player)
        videoEffects = VideoEffectsModel(backend: backends.player)
        audioEffects = AudioEffectsModel(backend: backends.player)
        chapters = ChaptersModel(backend: backends.player)
        bookmarks = BookmarksModel(player: backends.player, library: backends.library, clock: clock)
        library = LibraryModel(backend: backends.library)
        settings = SettingsModel(backend: backends.settings, catalog: settingsCatalog)
        shortcuts = ShortcutsModel(backend: backends.shortcuts)
        output = OutputModel(backend: backends.output)
        renderers = RendererModel(backend: backends.renderers)
        osd = OSDModel(backend: backends.osd)
        dialogs = DialogModel(backend: backends.dialogs)
        extensions = ExtensionsModel(backend: backends.extensions)
        seekPreview = SeekPreviewModel(thumbnails: backends.thumbnails, player: backends.player)
        interface = InterfaceModel(persistence: persistence)
        appearance = AppearanceModel(settings: backends.settings)
        presets = PresetStore(location: persistence)
        recents = RecentStore(location: persistence)
        pins = PinStore(location: persistence)
        profiles = ProfileStore(location: persistence)
        layouts = LayoutStore(location: persistence)
        wire()
        applyPlaybackPreferences(atStartup: true)
    }

    // MARK: Opening media

    /// Plays files or URLs now (Open File(s), Finder, Dock drop), replacing the queue.
    public func open(urls: [URL]) {
        guard !urls.isEmpty else { return }
        if opensPaused {
            do { try open(urls: urls, inputOptions: []) }
            catch { dialogs.presentError(error, title: "Unable to open media") }
        } else {
            queue.playNow(urls.map(MediaItem.init(url:)))
        }
    }

    /// Opens inputs with VLC access/output options; failures leave the current queue intact.
    public func open(urls: [URL], inputOptions: [String]) throws {
        guard let backend = backends.queue as? any QueueInputOptionsBackend else { throw BackendOperationError.unsupported("Opening media with input options") }
        try backend.playNow(urls.map(MediaItem.init(url:)), startAt: 0, inputOptions: inputOptions, startPaused: opensPaused)
    }

    private var opensPaused: Bool { !(backends.settings.value(for: "playlist-autostart")?.boolValue ?? true) }

    /// Adds files or URLs to the end of the queue.
    public func enqueue(urls: [URL]) { queue.enqueue(urls.map(MediaItem.init(url:))) }

    /// Plays a library media. With `context` (the folder's media), the queue becomes the context
    /// starting at the media, so "next" continues with the following episode.
    public func play(_ media: MediaItem, context: [MediaItem]? = nil) {
        if let context, let index = context.firstIndex(where: { $0.id == media.id }) {
            queue.playNow(context, startAt: index)
        } else {
            queue.playNow([media])
        }
    }

    /// Handles the result of an ``InterfaceModel/fileRequest`` open panel.
    public func complete(_ request: FileRequest, urls: [URL]) {
        interface.fileRequest = nil
        let audioTrackTargets = request == .addAudioFile ? library.audioTrackTargets : []
        if request == .addAudioFile { library.audioTrackTargets = [] }
        guard !urls.isEmpty else { return }
        switch request {
        case .openFiles, .openFolder: open(urls: urls)
        case .addFilesToQueue: enqueue(urls: urls)
        case .addLibraryFiles:
            Task { [weak self] in
                guard let self else { return }
                do { try await library.importFiles(urls: urls) }
                catch { dialogs.presentError(error, title: "Unable to import media") }
            }
        case .addSubtitleFile: urls.forEach { tracks.addExternalTrack(url: $0, kind: .subtitle) }
        case .addAudioFile: completeAddAudioFile(urls, targets: audioTrackTargets)
        case .addLibraryFolder: urls.forEach { library.addFolder($0) }
        }
    }

    public func presentOutput(media: MediaItem?, mode: OutputMode) {
        guard interface.sheet == nil, interface.fileRequest == nil else { return }
        interface.pendingOutputSource = media
        interface.present(mode == .convert ? .convert : .stream)
    }

    public func presentNewPlaylist(media: [MediaItem]) {
        guard interface.sheet == nil, interface.fileRequest == nil else { return }
        interface.pendingPlaylistMedia = media
        interface.present(.newPlaylist)
    }
    public func presentAddSubtitles(media: [MediaItem], scope: AddSubtitlesScope = .file, source: AddSubtitlesSource = .computer) {
        guard interface.sheet == nil, interface.fileRequest == nil else { return }
        interface.subtitleTargetMedia = media
        interface.present(.addSubtitles(scope: scope, source: source))
    }

    // MARK: Layout and onboarding

    /// The layout kind for the current media (music uses the ±15 s layout).
    public var layoutKind: LayoutStore.Kind { player.isAudioOnly ? .music : .video }

    /// The bars to draw: the draft while customizing, else the saved layout of the current profile.
    public var playerLayout: PlayerLayout {
        layouts.draft ?? layouts.layout(profileID: profiles.currentID, kind: layoutKind)
    }

    /// "Customize Player": enters edit mode on the current layout.
    public func beginCustomizing() {
        guard !interface.isCustomizing else { return }
        interface.isUIHidden = false
        interface.library = .hidden
        interface.areBarsVisible = true
        layouts.beginEditing(profileID: profiles.currentID, kind: layoutKind)
        interface.rightPanel = nil
        interface.isCustomizing = true
    }

    /// Customize dialog "Save" (true) or "Cancel" (false).
    public func endCustomizing(save: Bool) {
        if save { layouts.commit() } else { layouts.cancelEditing() }
        interface.isCustomizing = false
    }

    /// App option remembering that onboarding was completed.
    public static let onboardingOption = "macosx-redesign-onboarding-completed"

    /// True until the onboarding (S69–S71) has been finished once.
    public var needsOnboarding: Bool {
        !(backends.settings.value(for: Self.onboardingOption)?.boolValue ?? false)
    }

    /// Onboarding "Finish".
    public func completeOnboarding() {
        backends.settings.setValue(.bool(true), for: Self.onboardingOption, apply: .nextMedia)
        backends.settings.save()
        if interface.sheet == .onboarding { interface.dismissSheet() }
    }

    // MARK: Presets

    /// The preset in effect for the current media (sidebar preset dropdown ✓).
    public var activePreset: PlaybackPreset {
        guard let media = player.media, let preset = presets.preset(for: media) else { return .default }
        return preset
    }

    /// Picks a preset in the sidebar: applies it and remembers it for the current show/folder.
    public func selectPreset(_ preset: PlaybackPreset) {
        presets.apply(preset, tracks: tracks, audio: audioEffects, video: videoEffects)
        if let media = player.media {
            presets.assign(preset.id == PlaybackPreset.defaultID ? nil : preset.id, to: media)
        }
    }

    /// "New Preset": captures the current state and assigns it to the current show.
    @discardableResult
    public func createPreset(named name: String, sections: PresetSections = .all) -> PlaybackPreset {
        let preset = presets.capture(name: name, sections: sections, tracks: tracks, audio: audioEffects, video: videoEffects)
        if let media = player.media { presets.assign(preset.id, to: media) }
        return preset
    }

    // MARK: Commands

    /// Whether a command can run now (menu item enabled state). `source` is ``CommandSource/ui`` for
    /// the window, its keys and the menu bar: behind a dialog or file panel only Quit (and Keyboard
    /// Shortcuts from Settings) run, so a command never replaces a draft (D040). System transport
    /// (media keys, Control Center, the status item) keeps working behind a dialog (D026).
    public func canPerform(_ command: AppCommand) -> Bool { canPerform(command, from: .ui) }

    /// A dialog or file panel is open: window and menu-bar actions wait (D040).
    public var isBehindModal: Bool { interface.sheet != nil || interface.fileRequest != nil }

    /// ``canPerform(_:)`` for a command from `source`.
    public func canPerform(_ command: AppCommand, from source: CommandSource) -> Bool {
        guard !blocksCustomization(command) else { return false }
        if isBehindModal {
            if command == .quit { return true }
            if command == .keyboardShortcuts, case .settings = interface.sheet { return true }
            guard source == .system, command.isTransport else { return false }
            // With nothing loaded, Play would open the library behind the dialog.
            if command == .playPause { return player.media != nil || !queue.items.isEmpty }
        }
        // The right panels do not exist over the full library (COMP-01, A-13): their commands are off there.
        if interface.library == .full,
           [.toggleQueue, .toggleSettingsSidebar, .showSubtitleTracks, .showAudioTracks].contains(command) { return false }
        return switch command {
        case .previous: queue.hasPrevious
        case .next: queue.hasNext
        case .stop, .record, .snapshot, .nextFrame, .toggleABLoop, .addBookmark, .favoriteCurrent, .addSubtitleFile:
            player.media != nil
        case .jumpBackward10, .jumpForward10, .jumpBackward15, .jumpForward15: player.canSeek
        case .faster, .slower, .normalRate: player.canChangeRate
        case .convert, .stream, .openDisc, .openCaptureDevice: true
        default: true
        }
    }

    /// Play / Space / the Play button. With nothing queued there is nothing to start: open the
    /// library on Home instead of asking the engine to fail (D029, WT-09).
    public func playOrOpenLibrary() {
        guard player.media == nil, queue.items.isEmpty, !interface.isCustomizing else { player.togglePlayPause(); return }
        library.select(.home)
        if interface.library == .hidden { interface.library = .full }
    }

    /// Runs a command when ``canPerform(_:from:)`` allows it.
    public func perform(_ command: AppCommand) { perform(command, from: .ui) }

    /// ``perform(_:)`` for a command from `source` (``CommandSource/system`` for media keys and the
    /// status item).
    public func perform(_ command: AppCommand, from source: CommandSource) {
        guard canPerform(command, from: source) else { return }
        switch command {
        case .openFiles: interface.request(.openFiles)
        case .openFolder: interface.request(.openFolder)
        case .openNetworkStream: interface.present(.openNetworkStream)
        case .openDisc: interface.present(.openDisc)
        case .openCaptureDevice: interface.present(.openCaptureDevice)
        case .convert: presentOutput(media: nil, mode: .convert)
        case .stream: presentOutput(media: nil, mode: .stream)
        case .openFromClipboard:
            let text = NSPasteboard.general.string(forType: .string) ?? ""
            let urls = text.split(whereSeparator: \.isNewline).compactMap { URL(string: String($0).trimmingCharacters(in: .whitespaces)) }
            if !urls.isEmpty { open(urls: urls) }
        case .keyboardShortcuts:
            if case .settings = interface.sheet {
                interface.sheet = .settings(categoryID: settings.selectedCategoryID)
            }
            interface.present(.keyboardShortcuts)
        case .customizePlayer: beginCustomizing()
        case .manageProfiles: interface.present(.profiles)
        case .settings: interface.present(.settings(categoryID: nil))
        case .about: interface.present(.about)
        case .playPause: playOrOpenLibrary()
        case .stop: player.stop()
        case .previous: queue.previous()
        case .next: queue.next()
        case .record: player.toggleRecording()
        case .hideUI: interface.toggleUIHidden()
        case .jumpBackward10: player.jump(by: -10)
        case .jumpForward10: player.jump(by: 10)
        case .jumpBackward15: player.jump(by: -15)
        case .jumpForward15: player.jump(by: 15)
        case .faster: player.setRate(Self.nextRate(after: player.rate, faster: true))
        case .slower: player.setRate(Self.nextRate(after: player.rate, faster: false))
        case .normalRate: player.setRate(1)
        case .nextFrame: player.nextFrame()
        case .snapshot: player.takeSnapshot()
        case .toggleABLoop: player.toggleABLoop()
        case .toggleFullscreen: player.setFullscreen(!player.isFullscreen)
        case .toggleMute: player.toggleMute()
        case .volumeUp: player.adjustVolume(steps: 1)
        case .volumeDown: player.adjustVolume(steps: -1)
        case .toggleRepeat: queue.cycleRepeatMode()
        case .toggleShuffle: queue.toggleShuffle()
        case .toggleQueue: interface.toggleQueuePanel()
        case .toggleLibrary:
            if interface.library != .compact { library.reveal(player.media) }
            interface.toggleCompactLibrary()
        case .showFullLibrary: interface.showFullLibrary()
        case .toggleSettingsSidebar: interface.toggleSidebar()
        case .showSubtitleTracks: interface.toggleTracks(.subtitles)
        case .showAudioTracks: interface.toggleTracks(.audio)
        case .addBookmark: bookmarks.addAtCurrentTime()
        case .addSubtitleFile: interface.request(.addSubtitleFile)
        case .favoriteCurrent:
            if let media = player.media { library.setFavorite(!media.isFavorite, for: [media]) }
        case .quit: backends.quitHandler?()
        }
    }

    private func blocksCustomization(_ command: AppCommand) -> Bool {
        interface.isCustomizing && [.hideUI, .toggleLibrary, .showFullLibrary].contains(command)
    }

    /// The OSD line of an app action run from a key: what is now true for the toggles, the
    /// command's name for the rest.
    private func keyFeedback(after command: AppCommand) -> String {
        switch command {
        case .hideUI: interface.isUIHidden ? "Hide UI" : "Show UI"
        case .toggleQueue: interface.isQueuePanelOpen ? "Show Queue" : "Hide Queue"
        case .toggleLibrary: interface.library == .compact ? "Show Library" : "Hide Library"
        case .toggleSettingsSidebar: interface.isSidebarOpen ? "Show Sidebar" : "Hide Sidebar"
        case .addBookmark: "Bookmark added"
        default: command.title
        }
    }

    /// Speed steps of the sidebar slider (0.25…2) extended to VLC's 4×.
    public static let rateSteps: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 3, 4]

    static func nextRate(after rate: Double, faster: Bool) -> Double {
        if faster { return rateSteps.first { $0 > rate + 0.001 } ?? rateSteps.last! }
        return rateSteps.last { $0 < rate - 0.001 } ?? rateSteps.first!
    }

    /// App-level shortcut actions (``ShortcutsModel/appActionPrefix``) and the commands they run.
    public static let appShortcutCommands: [String: AppCommand] = Dictionary(
        AppCommand.allCases.compactMap { command in
            command.shortcutActionID.flatMap { $0.hasPrefix(ShortcutsModel.appActionPrefix) ? ($0, command) : nil }
        },
        uniquingKeysWith: { first, _ in first })

    /// The binding shown next to a menu item, if the command has a bound action.
    public func keyBinding(for command: AppCommand) -> KeyBinding? {
        command.shortcutActionID.flatMap(shortcuts.primaryBinding(for:))
    }

    /// The shortcut as menus show it on the Mac ("⌘O", "⇧⌘O", "Space"), or nil (D026).
    public func shortcutText(for command: AppCommand) -> String? { keyBinding(for: command)?.displayString }

    // MARK: Wiring

    private func wire() {
        backends.player.addListener(self) { [weak self] event in
            if event == .media {
                self?.applyPlaybackPreferences()
                self?.mediaChanged()
            }
        }
        queue.errorHandler = { [weak self] error in self?.dialogs.presentError(error, title: "Unable to play media") }
        player.endOfItemHook = { [weak self] pause in
            self?.queue.setMediaStoppedAction(pause ? .pause : .continue)
        }
        shortcuts.onTriggered = { [weak self] _, binding in
            self?.osd.keyPressed(binding)
        }
        shortcuts.appActionHandler = { [weak self] actionID, keyed in
            guard let self, let command = AppModel.appShortcutCommands[actionID] else { return }
            let runs = self.canPerform(command)
            self.perform(command)
            // D027: from a key, an app action's result pairs with "Pressed <key>" like an engine action's.
            if keyed, runs { self.osd.actionPerformed(self.keyFeedback(after: command)) }
        }
        shortcuts.engineActionOverride = { [weak self] actionID, keyed in
            // VLC's play-pause hotkey only pauses or resumes, so at the end of the media (stopped,
            // item still current) Space would do nothing while the Play button restarts the item.
            guard let self, actionID == "play-pause", self.player.isStopped,
                  self.player.media != nil || !self.queue.items.isEmpty else { return false }
            self.player.togglePlayPause()
            if keyed { self.osd.actionPerformed(AppCommand.playPause.title) }
            return true
        }
        settings.actionHandler = { [weak self] action in
            self?.performSettingsAction(action)
        }
        profiles.connect(snapshot: { [weak self] in
            guard let self else { return [:] }
            return Dictionary(uniqueKeysWithValues: self.settings.catalog.referencedOptions.filter { !$0.hasPrefix("macosx-redesign-key-") }.compactMap { name in self.backends.settings.value(for: name).map { (name, $0) } })
        }, apply: { [weak self] values in
            guard let self else { return }
            for (name, value) in values.sorted(by: { $0.key < $1.key }) {
                guard let option = self.backends.settings.option(named: name), self.backends.settings.value(for: name)?.isEquivalent(to: value) != true else { continue }
                // A stale profile value outside the option's current range would be rejected by VLC.
                if let range = option.range, let number = value.doubleValue, !range.contains(number) { continue }
                let apply = self.settings.catalog.allRows.first { $0.optionNames.contains(name) }?.apply ?? .nextMedia
                self.backends.settings.setValue(value, for: name, apply: apply)
            }
            self.backends.settings.save()
        })
        backends.settings.addListener(self) { [weak self] event in
            guard let self else { return }
            switch event {
            case .valueChanged(let name):
                self.applyPlaybackPreferences()
                self.profiles.recordSetting(self.backends.settings.value(for: name), name: name)
            case .reloaded:
                self.applyPlaybackPreferences()
                self.profiles.captureCurrentSettings()
            case .devicesChanged: break // A hot-plug changes no setting: nothing to apply or capture.
            }
        }
        lastMediaID = player.media?.id
    }

    private func mediaChanged() {
        guard let media = backends.player.currentMedia else {
            lastMediaID = nil
            return
        }
        guard media.id != lastMediaID else { return }
        lastMediaID = media.id
        if !excludesFromHistory(media) { recents.record(media) }
        if appliesPresetsAutomatically, let preset = presets.preset(for: media) {
            presets.apply(preset, tracks: tracks, audio: audioEffects, video: videoEffects)
        }
    }

    private func performSettingsAction(_ action: String) {
        switch action {
        case "clear-history":
            recents.clear()
            backends.library.clearHistory()
        case "edit-shortcuts": perform(.keyboardShortcuts)
        case "reset-shortcuts": shortcuts.resetAll()
        case "reset-picture": videoEffects.update { $0.essential = EssentialVideoFilters() }
        case "open-config-folder":
            guard let backend = backends.settings as? any SettingsMaintenanceBackend, let url = backend.configurationDirectory else { settings.actionMessage = BackendOperationError.unsupported("Opening the configuration folder").localizedDescription; return }
            settings.actionMessage = NSWorkspace.shared.open(url) ? "Configuration folder opened." : "The configuration folder could not be opened."
        case "open-extensions-folder":
            // Where VLC loads user Lua extensions from and where "Add" copies them (lua/extensions).
            guard let backend = backends.settings as? any SettingsMaintenanceBackend, let base = backend.userDataDirectory else { settings.actionMessage = BackendOperationError.unsupported("Opening the extensions folder").localizedDescription; return }
            let folder = base.appending(path: "lua/extensions", directoryHint: .isDirectory)
            let ready = (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])) != nil
            settings.actionMessage = ready && NSWorkspace.shared.open(folder) ? "Extensions folder opened." : "The extensions folder could not be opened."
        case "reset-all-settings":
            backends.settings.resetAll()
            settings.saveNow()
            settings.actionMessage = "Settings restored to their defaults."
        case "rescan-library":
            guard capabilities.hasMediaLibrary else { settings.actionMessage = BackendOperationError.unsupported("The media library").localizedDescription; return }
            backends.library.rescan(folderID: nil)
            settings.actionMessage = "Library scan requested."
        case "show-all-modules":
            settings.allModuleOptions = backends.settings.allOptionNames.sorted().compactMap { backends.settings.option(named: $0) }
            settings.showsAllModules = true
        default: settings.actionMessage = BackendOperationError.unsupported(action).localizedDescription
        }
    }
}
