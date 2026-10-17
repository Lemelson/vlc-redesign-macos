import Foundation
import MXRCore

/// Scripted backends implementing every MXRCore protocol, for the Gallery, previews and tests.
///
/// ```swift
/// let app = AppModel.mock(.playingEpisode)          // deterministic, frozen clock
/// PlayerWindow().appModel(app)
/// let live = AppModel.mock(.playingMovie, clock: .realtime)  // time advances while playing
/// ```
@MainActor
public final class MockBackend {
    /// Starting states matching the Figma frames.
    public enum Scenario: String, CaseIterable, Sendable {
        /// "The Wand S01E04" playing at 00:02:10 / 00:25:40 (Figma "Player" frames). Queue: E04–E07.
        case playingEpisode
        /// "The Wand S01E11" paused at 00:02:10; queue E11–E14 (Figma Controls queue, Miniplayer).
        case pausedEpisode
        /// "DON’T BLINK" 4K movie playing at 00:02:10: 5 chapters (Winter … Winter (5 Years Later)), 2 bookmarks.
        case playingMovie
        /// "DON’T BLINK" just opened, showing "You’ve watched till 00:45:08 already." (S12).
        case continueWatching
        /// "untangle - juxtopposed" playing at 00:00:10 / 00:01:40 (Figma "Player - Music"). Queue: My Songs.
        case music
        /// A live radio stream (not seekable).
        case stream
        /// Nothing playing, full library ("VLC Media Player", Home).
        case idle
        /// Nothing playing and an empty library (first launch).
        case emptyLibrary
    }

    /// How the mock clock behaves.
    public enum ClockMode: Sendable {
        /// Time only moves on seeks. Use for snapshots.
        case frozen
        /// Time advances every 250 ms while playing; items end and the queue advances.
        case realtime
    }

    public let scenario: Scenario
    public let player: MockPlayer
    public let queue: MockQueue
    public let library: MockLibrary
    public let settings: MockSettings
    public let shortcuts: MockShortcuts
    public let dialogs: MockDialogs
    public let extensions: MockExtensions
    public let thumbnails: MockThumbnails
    public let osd: MockOSD
    public let mediaSources: MockMediaSources
    public let output: MockOutput
    public let renderers: MockRenderers

    /// Builds the backends in the given scenario.
    public init(scenario: Scenario = .playingEpisode, clock: ClockMode = .frozen, settingsCatalog: SettingsCatalog = .bundled) {
        self.scenario = scenario
        let db = scenario == .emptyLibrary ? MockDatabase.makeEmpty() : MockDatabase.make()
        let library = MockLibrary(db: db)
        self.library = library
        player = MockPlayer(clockMode: clock, library: { [weak library] in library?.db ?? MockDatabase() })
        queue = MockQueue(player: player)
        settings = MockSettings(catalog: settingsCatalog)
        osd = MockOSD()
        shortcuts = MockShortcuts(player: player, queue: queue, osd: osd)
        dialogs = MockDialogs()
        extensions = MockExtensions()
        thumbnails = MockThumbnails()
        mediaSources = MockMediaSources()
        output = MockOutput()
        renderers = MockRenderers()
        queue.onMediaFinished = { [weak library] id in
            library?.recordProgress(mediaID: id, progress: 1, finished: true)
        }
        library.addListener(player) { [weak player, weak library] event in
            guard case .mediaUpdated(let ids) = event, let player, let library,
                  let current = player.currentMedia, ids.contains(current.id),
                  let updated = library.mediaItem(id: current.id) else { return }
            player.updateCurrentMedia(updated)
        }
        apply(scenario)
    }

    /// The protocol view of these backends, for `AppModel(backends:)`.
    public var backends: Backends {
        Backends(player: player, clock: player, queue: queue, library: library, mediaSources: mediaSources, settings: settings,
                 shortcuts: shortcuts, dialogs: dialogs, extensions: extensions, thumbnails: thumbnails, osd: osd,
                 capabilities: scenario == .emptyLibrary ? BackendCapabilities.all : .all, output: output, renderers: renderers)
    }

    /// An `AppModel` over these backends, in memory, with app stores seeded like the Figma file
    /// (presets "Anime", "Loud and then Quiet Movies"…, profiles Movies/Shows/Music/Work, recents).
    public func makeAppModel(persistence: PersistenceLocation = .inMemory, clockTicks: Bool = true) -> AppModel {
        let app = AppModel(backends: backends, persistence: persistence, settingsCatalog: settingsCatalogForApp, clockTicks: clockTicks)
        seed(app)
        return app
    }

    private var settingsCatalogForApp: SettingsCatalog { .bundled }

    // MARK: Scenarios

    private func media(_ id: String) -> MediaItem? { library.mediaItem(id: id) }

    private func apply(_ scenario: Scenario) {
        let db = library.db
        switch scenario {
        case .playingEpisode:
            let ids = (4...7).map { MockDatabase.wandID(season: 1, episode: $0) }
            queue.setItems(ids.compactMap(media), current: 0)
            player.load(media(ids[0]), at: .hms(0, 2, 10), state: .playing)
        case .pausedEpisode:
            let ids = (11...14).map { MockDatabase.wandID(season: 1, episode: $0) }
            queue.setItems(ids.compactMap(media), current: 0)
            player.load(media(ids[0]), at: .hms(0, 2, 10), state: .paused)
        case .playingMovie:
            queue.setItems([media(MockDatabase.dontBlinkID)].compactMap { $0 }, current: 0)
            player.load(media(MockDatabase.dontBlinkID), at: .hms(0, 2, 10), state: .playing)
        case .continueWatching:
            queue.setItems([media(MockDatabase.dontBlinkID)].compactMap { $0 }, current: 0)
            player.load(media(MockDatabase.dontBlinkID), at: .zero, state: .playing)
            player.askRestore(at: .hms(0, 45, 8))
        case .music:
            let ids = [MockDatabase.untangleID, MockDatabase.moonlightID, MockDatabase.blackBirdID]
            queue.setItems(ids.compactMap(media), current: 0)
            player.load(media(ids[0]), at: .seconds(10), state: .playing)
        case .stream:
            var radio = MediaItem(url: URL(string: "https://radio.example.com/lofi.mp3")!)
            radio.title = "Lo-fi Radio"
            radio.kind = .stream
            queue.setItems([radio], current: 0)
            player.load(radio, at: .seconds(754), state: .playing)
        case .idle, .emptyLibrary:
            queue.setItems([], current: nil)
            player.load(nil)
        }
        _ = db
    }

    private func seed(_ app: AppModel) {
        guard scenario != .emptyLibrary else { return }
        // Presets (Figma "Setting Preset" + spec "The Wand Subtitle Preset").
        app.presets.save(PlaybackPreset(id: "preset-custom-01", name: "Custom Preset 01", subtitleDelay: .milliseconds(-500)))
        app.presets.save(PlaybackPreset(id: "preset-custom-02", name: "Custom Preset 02", subtitleDelay: .milliseconds(250)))
        var animeStyle = SubtitleStyle.default
        animeStyle.sizeMode = .pixels
        animeStyle.pixelSize = 22
        app.presets.save(PlaybackPreset(id: "preset-anime", name: "Anime", subtitleStyle: animeStyle, subtitleLanguage: "English", audioLanguage: "Japanese"))
        var loud = AudioEffects.default
        loud.compressor.isEnabled = true
        app.presets.save(PlaybackPreset(id: "preset-loud-quiet", name: "Loud and then Quiet Movies", audioEffects: loud))
        var wandStyle = SubtitleStyle.default
        wandStyle.fontFamily = "Inter"
        wandStyle.textColor = RGBColor(red: 0xB8, green: 0xB8, blue: 0xB8)
        wandStyle.outlineColor = RGBColor(red: 0x0C, green: 0x0C, blue: 0x0C)
        let wandPreset = app.presets.save(PlaybackPreset(id: "preset-the-wand", name: "The Wand Subtitle Preset", subtitleDelay: .milliseconds(-4_000), subtitleStyle: wandStyle))
        if let episode = media(MockDatabase.wandID(season: 1, episode: 1)) { app.presets.assign(wandPreset.id, to: episode) }

        app.backends.settings.setValue(.bool(true), for: AppModel.onboardingOption, apply: .nextMedia)

        // Profiles ("Profile (Movies)").
        app.profiles.replaceAll([Profile(id: "movies", name: "Movies"), Profile(id: "shows", name: "Shows"), Profile(id: "music", name: "Music"),
                                 Profile(id: "work", name: "Work")], currentID: "movies")

        // Recents (Open Recent submenu).
        let recentIDs = [MockDatabase.wandID(season: 1, episode: 4), MockDatabase.dontBlinkID, MockDatabase.untangleID,
                         MockDatabase.wandID(season: 1, episode: 3), MockDatabase.wandID(season: 1, episode: 2)]
        app.recents.replaceAll(recentIDs.enumerated().compactMap { index, id in
            media(id).map { RecentEntry(media: $0, date: mockReferenceDate.addingTimeInterval(TimeInterval(-3_600 * index))) }
        })
    }
}

/// Ids of notable mock media, for gallery entries (`mock.library.mediaItem(id:)`).
public enum MockMediaID {
    /// "The_Wand_S<season>E<episode>.mp4" (season 1 or 2, episodes 1...15).
    public static func theWand(season: Int = 1, episode: Int) -> String { MockDatabase.wandID(season: season, episode: episode) }
    /// "DON’T BLINK.mp4": 4K movie with chapters and bookmarks.
    public static let dontBlink = MockDatabase.dontBlinkID
    public static let untangle = MockDatabase.untangleID
    public static let moonlight = MockDatabase.moonlightID
    public static let blackBird = MockDatabase.blackBirdID
    /// Library folder ids: `LibraryLocation.folder(MockMediaID.theWandS01Folder)`.
    public static let theWandS01Folder = MockDatabase.wandS01Folder
    public static let mySongsFolder = MockDatabase.mySongsFolder
    /// The "Shows" entry point (Figma videos2 4778:25847) and its "The Wand" folder (videos3 4778:25957).
    public static let showsFolder = MockDatabase.showsFolder
    public static let theWandFolder = MockDatabase.wandFolder
}

extension AppModel {
    /// A fully wired `AppModel` over the mock backend (in memory, deterministic with `.frozen`).
    @MainActor
    public static func mock(_ scenario: MockBackend.Scenario = .playingEpisode, clock: MockBackend.ClockMode = .frozen) -> AppModel {
        MockBackend(scenario: scenario, clock: clock).makeAppModel(clockTicks: clock == .realtime)
    }
}
