import CoreGraphics
import Foundation
import ImageIO
import MXRCore

// MARK: - Settings

/// In-memory configuration seeded from the settings catalog's `mock` values (what the Figma
/// renders show). Option metadata is synthesized from the catalog rows.
@MainActor
public final class MockSettings: SettingsBackend {
    private var values: [String: SettingValue] = [:]
    private var options: [String: SettingOption] = [:]
    private let events = EventChannel<SettingsEvent>()
    /// Deterministic hardware capabilities; mocks never query the host.
    public var deviceFixtures: [MediaDeviceKind: [MediaDevice]] = [:] { didSet { events.send(.devicesChanged) } }
    public private(set) var deviceQueries: [MediaDeviceKind] = []
    public func availableDevices(for kind: MediaDeviceKind) async -> [MediaDevice] {
        deviceQueries.append(kind)
        return deviceFixtures[kind] ?? []
    }

    /// Number of `save()` calls (tests).
    public private(set) var saveCount = 0

    init(catalog: SettingsCatalog) {
        for row in catalog.allRows {
            guard let name = row.option else {
                for choice in row.composite ?? [] {
                    for (name, value) in choice.values where options[name] == nil {
                        register(SettingOption(name: name, type: Self.type(of: value), defaultValue: value))
                    }
                }
                if let first = row.composite?.first, row.mock == nil {
                    for (name, value) in first.values where values[name] == nil { values[name] = value }
                }
                continue
            }
            if let secondary = row.secondaryOption {
                let value = row.secondaryMock ?? .integer(0)
                register(SettingOption(name: secondary, type: Self.type(of: value), defaultValue: value))
            }
            let defaultValue = row.mock ?? Self.fallback(for: row)
            let range: ClosedRange<Double>? = (row.min != nil && row.max != nil) ? row.min!...row.max! : nil
            register(SettingOption(name: name, type: Self.type(for: row, value: defaultValue), defaultValue: defaultValue, range: range,
                                   choices: row.choices ?? [], text: row.label, longText: row.info))
        }
        // App options read by Core models.
        for (name, value) in [(AppearanceModel.themeOption, SettingValue.string("dark")), (AppearanceModel.accentOption, .string("orange"))]
        where options[name] == nil {
            register(SettingOption(name: name, type: .string, defaultValue: value))
        }
    }

    private func register(_ option: SettingOption) {
        options[option.name] = option
        if values[option.name] == nil { values[option.name] = option.defaultValue }
    }

    public func option(named name: String) -> SettingOption? { options[name] }
    public func value(for name: String) -> SettingValue? { values[name] }

    public func setValue(_ value: SettingValue, for name: String, apply: SettingsApply) {
        if options[name] == nil { register(SettingOption(name: name, type: Self.type(of: value), defaultValue: value)) }
        values[name] = value
        events.send(.valueChanged(name))
    }

    public func resetValue(for name: String) {
        guard let option = options[name] else { return }
        values[name] = option.defaultValue
        events.send(.valueChanged(name))
    }

    public func resetAll() {
        for (name, option) in options { values[name] = option.defaultValue }
        events.send(.reloaded)
    }

    public func save() { saveCount += 1 }

    public func dynamicChoices(for name: String) async -> [SettingChoice] { options[name]?.choices ?? [] }

    public var allOptionNames: [String] { options.keys.sorted() }

    public func addListener(_ owner: AnyObject, handler: @escaping @MainActor (SettingsEvent) -> Void) {
        events.add(owner, handler: handler)
    }

    private static func type(of value: SettingValue) -> SettingOptionType {
        switch value {
        case .bool: .bool
        case .integer: .integer
        case .float: .float
        case .string: .string
        }
    }

    private static func type(for row: SettingsRow, value: SettingValue) -> SettingOptionType {
        switch row.control {
        case .toggle: .bool
        case .color: .color
        case .file: .loadFile
        case .directory: .directory
        case .key: .key
        // JSON reads a float mock such as 0.0 as an integer; a fractional step marks VLC's float option.
        case .number where row.step.map { $0.rounded() != $0 } ?? false: .float
        default: type(of: value)
        }
    }

    private static func fallback(for row: SettingsRow) -> SettingValue {
        switch row.control {
        case .toggle: .bool(false)
        case .slider, .number: .float(row.min ?? 0)
        case .color: .integer(0)
        case .dropdown, .segmented: row.choices?.first?.value ?? .string("")
        default: .string("")
        }
    }
}

// MARK: - Shortcuts

/// Hotkeys as the real engine reports them on the Mac (see `defaultActions`). Triggering an action
/// changes the mock player and posts the engine OSD text ("Crop: 2.35:1").
@MainActor
public final class MockShortcuts: ShortcutsBackend {
    public private(set) var actions: [ShortcutAction]
    /// Triggered action ids, newest last (tests).
    public private(set) var triggered: [String] = []

    private let defaults: [ShortcutAction]
    private weak var player: MockPlayer?
    private weak var queue: MockQueue?
    private let osd: MockOSD
    private var cropIndex = 0
    private var aspectIndex = 0
    private let changes = EventChannel<Void>()

    init(player: MockPlayer, queue: MockQueue, osd: MockOSD) {
        self.player = player
        self.queue = queue
        self.osd = osd
        defaults = Self.defaultActions
        actions = defaults
    }

    /// VLC's macOS engine defaults (src/libvlc-module.c `__APPLE__` block, D026), as the real
    /// engine reports them, so galleries show the keys the app shows (D030).
    static let defaultActions: [ShortcutAction] = {
        func key(_ text: String) -> [KeyBinding] { KeyBinding(vlcString: text).map { [$0] } ?? [] }
        return [
            // Basic (Figma dialog)
            ShortcutAction(id: "toggle-fullscreen", title: "Toggle fullscreen", group: .basic, hotkeys: key("Command+f")),
            ShortcutAction(id: "leave-fullscreen", title: "Exit fullscreen / close dialog", group: .basic, hotkeys: key("Esc")),
            ShortcutAction(id: "position", title: "Show playback position and time", group: .basic, hotkeys: key("t")),
            ShortcutAction(id: "intf-show", title: "Show interface controls in fullscreen", group: .basic, hotkeys: key("i")),
            // Playback (Figma dialog)
            ShortcutAction(id: "play-pause", title: "Play / pause", group: .playback, hotkeys: key("Space")),
            ShortcutAction(id: "stop", title: "Stop playback", group: .playback, hotkeys: key("Command+.")),
            ShortcutAction(id: "next", title: "Next track", group: .playback, hotkeys: key("Command+Right")),
            ShortcutAction(id: "prev", title: "Previous track", group: .playback, hotkeys: key("Command+Left")),
            ShortcutAction(id: "program-sid-next", title: "Next program / Service ID", group: .playback, hotkeys: key("x")),
            ShortcutAction(id: "jump-short", title: "Seek backward", group: .playback, hotkeys: key("Command+Alt+Left")),
            ShortcutAction(id: "jump+short", title: "Seek forward", group: .playback, hotkeys: key("Command+Alt+Right")),
            ShortcutAction(id: "frame-previous", title: "Previous frame", group: .playback, hotkeys: key("Shift+e")),
            ShortcutAction(id: "frame-next", title: "Next frame", group: .playback, hotkeys: key("e")),
            ShortcutAction(id: "faster", title: "Faster", group: .playback, hotkeys: key("Command+=")),
            ShortcutAction(id: "slower", title: "Slower", group: .playback, hotkeys: key("Command+-")),
            ShortcutAction(id: "rate-normal", title: "Normal rate", group: .playback, hotkeys: []),
            ShortcutAction(id: "record", title: "Record", group: .playback, hotkeys: key("Command+Shift+r")),
            // Audio
            ShortcutAction(id: "vol-up", title: "Increase volume", group: .audio, hotkeys: key("Command+Up")),
            ShortcutAction(id: "vol-down", title: "Decrease volume", group: .audio, hotkeys: key("Command+Down")),
            ShortcutAction(id: "vol-mute", title: "Mute", group: .audio, hotkeys: key("Command+Alt+Down")),
            ShortcutAction(id: "audio-track", title: "Cycle audio track", group: .audio, hotkeys: key("l")),
            ShortcutAction(id: "audiodelay-up", title: "Audio delay up", group: .audio, hotkeys: key("g")),
            ShortcutAction(id: "audiodelay-down", title: "Audio delay down", group: .audio, hotkeys: key("f")),
            // Video
            ShortcutAction(id: "crop", title: "Cycle crop", group: .video, hotkeys: key("c")),
            ShortcutAction(id: "aspect-ratio", title: "Cycle aspect ratio", group: .video, hotkeys: key("a")),
            ShortcutAction(id: "snapshot", title: "Take a snapshot", group: .video, hotkeys: key("Command+Alt+s")),
            ShortcutAction(id: "deinterlace", title: "Toggle deinterlacing", group: .video, hotkeys: key("d")),
            // Subtitles
            ShortcutAction(id: "subtitle-track", title: "Cycle subtitle track", group: .subtitles, hotkeys: key("s")),
            ShortcutAction(id: "subdelay-up", title: "Subtitle delay up", group: .subtitles, hotkeys: key("j")),
            ShortcutAction(id: "subdelay-down", title: "Subtitle delay down", group: .subtitles, hotkeys: key("h")),
            // Other (VLC for Mac's engine default; the right-click menu shows "⌘Q", D026)
            ShortcutAction(id: "quit", title: "Quit", group: .other, hotkeys: key("Command+q")),
        ] + ShortcutAction.appActions
    }()

    public func trigger(actionID: String) {
        triggered.append(actionID)
        guard let player else { return }
        switch actionID {
        case "play-pause":
            player.togglePause()
            osd.showMessage(player.state == .paused ? "Pause" : "Play")
        case "stop": player.stop()
        case "next": queue?.next()
        case "prev": queue?.previous()
        case "toggle-fullscreen": player.setFullscreen(!player.isFullscreen)
        case "leave-fullscreen": player.setFullscreen(false)
        case "position":
            let length = player.currentMedia?.duration ?? .zero
            osd.showMessage("\(player.time.formatted(.hoursMinutesSeconds)) / \(length.formatted(.hoursMinutesSeconds))")
        case "jump-short":
            player.jump(by: -10)
            osd.showMessage("Jump -10 s")
        case "jump+short":
            player.jump(by: 10)
            osd.showMessage("Jump +10 s")
        case "frame-next": player.nextFrame()
        case "faster": player.setRate(min(player.rate * 1.5, 4)); osd.showMessage(String(format: "Speed: %.2fx", player.rate))
        case "slower": player.setRate(max(player.rate / 1.5, 0.25)); osd.showMessage(String(format: "Speed: %.2fx", player.rate))
        case "rate-normal": player.setRate(1); osd.showMessage("Speed: 1.00x")
        case "record": player.setRecording(!player.isRecording)
        case "vol-up":
            player.setVolume(player.volume + 0.05)
            osd.showMessage("Volume \(Int((player.volume * 100).rounded())) %")
        case "vol-down":
            player.setVolume(player.volume - 0.05)
            osd.showMessage("Volume \(Int((player.volume * 100).rounded())) %")
        case "vol-mute":
            player.setMuted(!player.isMuted)
            osd.showMessage(player.isMuted ? "Mute" : "Volume \(Int((player.volume * 100).rounded())) %")
        case "audio-track", "subtitle-track":
            let kind: TrackKind = actionID == "audio-track" ? .audio : .subtitle
            let list = player.tracks(of: kind)
            guard !list.isEmpty else { return }
            if let index = list.firstIndex(where: \.isSelected), index + 1 < list.count {
                player.selectTrack(id: list[index + 1].id, exclusive: true)
                osd.showMessage("\(kind == .audio ? "Audio" : "Subtitle") track: \(list[index + 1].name)")
            } else if list.contains(where: \.isSelected) {
                player.unselectTracks(of: kind)
                osd.showMessage("\(kind == .audio ? "Audio" : "Subtitle") track: Disabled")
            } else {
                player.selectTrack(id: list[0].id, exclusive: true)
                osd.showMessage("\(kind == .audio ? "Audio" : "Subtitle") track: \(list[0].name)")
            }
        case "crop":
            let choices = VideoEffects.cropChoices
            cropIndex = (cropIndex + 1) % choices.count
            var effects = player.videoEffects
            effects.crop = choices[cropIndex]
            player.setVideoEffects(effects)
            osd.showMessage("Crop: \(choices[cropIndex] ?? "Default")")
        case "aspect-ratio":
            let choices = VideoEffects.aspectRatioChoices
            aspectIndex = (aspectIndex + 1) % choices.count
            var effects = player.videoEffects
            effects.aspectRatio = choices[aspectIndex]
            player.setVideoEffects(effects)
            osd.showMessage("Aspect ratio: \(choices[aspectIndex] ?? "Default")")
        case "snapshot": player.takeSnapshot()
        case "subdelay-up", "subdelay-down":
            player.setSubtitleDelay(player.subtitleDelay + .milliseconds(actionID == "subdelay-up" ? 50 : -50))
            osd.showMessage("Subtitle delay \(player.subtitleDelay.milliseconds) ms")
        case "audiodelay-up", "audiodelay-down":
            player.setAudioDelay(player.audioDelay + .milliseconds(actionID == "audiodelay-up" ? 50 : -50))
            osd.showMessage("Audio delay \(player.audioDelay.milliseconds) ms")
        default: break
        }
    }

    public func setBindings(_ hotkeys: [KeyBinding], global: [KeyBinding], forAction actionID: String) {
        guard let index = actions.firstIndex(where: { $0.id == actionID }) else { return }
        actions[index].hotkeys = hotkeys
        actions[index].globalHotkeys = global
    }

    public func resetAllBindings() {
        actions = defaults
        changes.send(())
    }

    public func save() { changes.send(()) }

    public func addListener(_ owner: AnyObject, handler: @escaping @MainActor () -> Void) {
        changes.add(owner) { _ in handler() }
    }
}

// MARK: - OSD

/// Records engine OSD messages and forwards them to listeners (the OSD model).
@MainActor
public final class MockOSD: OSDBackend {
    /// Messages shown, newest last.
    public private(set) var messages: [String] = []
    private let events = EventChannel<String>()

    init() {}

    public func showMessage(_ text: String) {
        messages.append(text)
        events.send(text)
    }

    public func addListener(_ owner: AnyObject, handler: @escaping @MainActor (String) -> Void) {
        events.add(owner, handler: handler)
    }
}

// MARK: - Dialogs

/// Engine dialogs: call ``present(_:)`` from a gallery entry to show one.
@MainActor
public final class MockDialogs: DialogBackend {
    public weak var presenter: (any DialogPresenter)?
    /// Answers received, newest last (tests): "login:<id>:<user>", "action:<id>:<n>", "dismiss:<id>".
    public private(set) var answers: [String] = []
    private var nextID: UInt64 = 1

    init() {}

    /// Sends a request to the presenter as the engine would.
    @discardableResult
    public func present(title: String, text: String, kind: DialogRequest.Kind) -> DialogRequest {
        let request = DialogRequest(id: nextID, title: title, text: text, kind: kind)
        nextID += 1
        presenter?.present(request)
        return request
    }

    /// A sample login request (SMB share).
    @discardableResult
    public func presentSampleLogin() -> DialogRequest {
        present(title: "Authentication required", text: "Please enter your credentials for smb://nas.local/Media.",
                kind: .login(defaultUsername: "", canStore: true))
    }

    /// A sample question (broken AVI index).
    @discardableResult
    public func presentSampleQuestion() -> DialogRequest {
        present(title: "Broken or missing index", text: "This file has a broken or missing index. Repair it before playing?",
                kind: .question(severity: .warning, action1: "Build Index then Play", action2: "Play as is", cancel: "Do not play"))
    }

    public func postLogin(id: UInt64, username: String, password: String, store: Bool) { answers.append("login:\(id):\(username)") }
    public func postAction(id: UInt64, action: Int) { answers.append("action:\(id):\(action)") }
    public func dismiss(id: UInt64) { answers.append("dismiss:\(id)") }
}

// MARK: - Extensions

/// Extensions list (empty by default, like the Figma Settings ▸ Extensions render) and an add-ons catalog.
@MainActor
public final class MockExtensions: ExtensionsBackend, ExtensionsAvailabilityBackend, LocalExtensionRemovalBackend {
    public private(set) var extensions: [ExtensionInfo] = []
    private let events = EventChannel<ExtensionsEvent>()

    /// Example extensions for list states.
    public static let samples: [ExtensionInfo] = [
        ExtensionInfo(id: "vlsub", title: "VLsub", summary: "Download subtitles from OpenSubtitles.", author: "guillaume", version: "0.11.1", hasMenu: true),
        ExtensionInfo(id: "lyrics", title: "Lyrics Finder", summary: "Shows lyrics of the current song.", author: "community", version: "1.2"),
        ExtensionInfo(id: "playlist-export", title: "Playlist Exporter", summary: "Exports the queue as M3U or XSPF.", author: "community", version: "0.4", isActivated: true),
    ]

    init() {}

    public func availability(for operation: ExtensionOperation, extensionID: String?) -> ExtensionAvailability {
        operation == .run ? .unavailable(operation.unavailableReason) : .available
    }

    /// Fills the list with ``samples``.
    public func seedSamples() {
        extensions = Self.samples
        events.send(.listChanged)
    }

    public func activate(id: String) { setActivated(true, id) }
    public func deactivate(id: String) { setActivated(false, id) }

    private func setActivated(_ value: Bool, _ id: String) {
        guard let index = extensions.firstIndex(where: { $0.id == id }) else { return }
        extensions[index].isActivated = value
        events.send(.activationChanged(id))
    }

    public func menu(forExtension id: String) -> [ExtensionMenuItem] {
        id == "vlsub" ? [ExtensionMenuItem(id: 1, title: "Search subtitles…"), ExtensionMenuItem(id: 2, title: "Settings")] : []
    }

    public func triggerMenu(extensionID: String, itemID: UInt16) {}

    public func searchAddons(_ text: String) async throws -> [AddonInfo] {
        let all = [
            AddonInfo(id: "addon-skins", name: "Retro Skins", summary: "A set of classic skins."),
            AddonInfo(id: "addon-radio", name: "Radio Directory", summary: "Thousands of internet radio stations."),
            AddonInfo(id: "addon-lyrics", name: "Lyrics Finder", summary: "Shows lyrics of the current song.", isInstalled: extensions.contains { $0.id == "lyrics" }),
        ]
        let query = text.lowercased()
        return query.isEmpty ? all : all.filter { $0.name.lowercased().contains(query) || $0.summary.lowercased().contains(query) }
    }

    public func installAddon(id: String) async throws {
        guard !extensions.contains(where: { $0.id == id }) else { return }
        extensions.append(ExtensionInfo(id: id, title: id.replacingOccurrences(of: "addon-", with: "").capitalized))
        events.send(.listChanged)
    }

    public func removeAddon(id: String) async throws {
        extensions.removeAll { $0.id == id }
        events.send(.listChanged)
    }

    public func installExtension(fileURL: URL) async throws {
        let id = fileURL.deletingPathExtension().lastPathComponent
        extensions.append(ExtensionInfo(id: id, title: id))
        events.send(.listChanged)
    }

    public func removeExtension(id: String) async throws {
        guard extensions.contains(where: { $0.id == id }) else { throw BackendOperationError.invalidInput("Select an installed extension to remove.") }
        extensions.removeAll { $0.id == id }
        events.send(.listChanged)
    }

    public func addListener(_ owner: AnyObject, handler: @escaping @MainActor (ExtensionsEvent) -> Void) {
        events.add(owner, handler: handler)
    }
}

// MARK: - Media sources

/// LAN browsing with a couple of fake shares.
@MainActor
public final class MockMediaSources: MediaSourceBackend {
    init() {}

    public func sources(in category: MediaSourceCategory) -> [MediaSourceInfo] {
        switch category {
        case .localNetwork: [MediaSourceInfo(id: "upnp", title: "Universal Plug'n'Play", category: .localNetwork),
                             MediaSourceInfo(id: "smb", title: "SMB / Windows shares", category: .localNetwork)]
        case .internet: [MediaSourceInfo(id: "podcast", title: "Podcasts", category: .internet)]
        case .devices: [MediaSourceInfo(id: "disc", title: "Discs", category: .devices)]
        case .myComputer: []
        }
    }

    public func children(of node: MediaSourceNode?, in source: MediaSourceInfo) async throws -> [MediaSourceNode] {
        guard node == nil else {
            return [MediaSourceNode(id: (node?.id ?? "") + "/movie", title: "Holiday 2025.mp4", mrl: "smb://nas.local/Media/Holiday%202025.mp4", isContainer: false)]
        }
        return [MediaSourceNode(id: source.id + ":nas", title: "nas.local", mrl: "smb://nas.local/", isContainer: true)]
    }
}

// MARK: - Thumbnails

/// Figma media-only artwork for the named gallery media, with deterministic procedural images
/// for the rest of the database. Waveforms and arbitrary seek frames remain seeded fixtures.
@MainActor
public final class MockThumbnails: ThumbnailBackend {
    private var cache: [String: CGImage] = [:]
    /// The Home reference uses different image framing from the video grid.
    /// Gallery scenes opt in; normal mock queries retain the shared media artwork.
    public var usesFigmaHomeArtwork = false {
        didSet { if oldValue != usesFigmaHomeArtwork { cache.removeAll() } }
    }
    /// Image-only square crops used by canonical list and compact-library fixtures.
    public var usesFigmaListArtwork = false {
        didSet { if oldValue != usesFigmaListArtwork { cache.removeAll() } }
    }
    /// Number of seek-preview requests that completed (tests).
    public private(set) var seekPreviewRequests = 0

    init() {}

    public func artwork(for media: MediaItem, maxPixelSize: CGSize) async -> CGImage? {
        cachedArtwork(for: media, maxPixelSize: maxPixelSize)
    }

    public func cachedArtwork(for media: MediaItem, maxPixelSize: CGSize) -> CGImage? {
        let size = Self.fitted(maxPixelSize, aspect: media.kind == .audio ? 1 : 16.0 / 9.0)
        let key = "\(media.id)@\(Int(size.width))x\(Int(size.height))"
        if let image = cache[key] { return image }
        let homeNames = ["ml:wand-s01e05": "home-wand-e05", "ml:wand-s01e06": "home-wand-e06", "ml:wand-s01e07": "home-wand-e07"]
        let homeImage = usesFigmaHomeArtwork ? homeNames[media.id].flatMap { MockArtwork.image(named: $0, maxPixelSize: size) } : nil
        let listName = media.id.hasPrefix("ml:wand-s01e") ? media.id.replacingOccurrences(of: "ml:wand-s01e", with: "list-wand-e") : nil
        let listImage = usesFigmaListArtwork && size.height <= 64 ? listName.flatMap { MockArtwork.image(named: $0, maxPixelSize: size) } : nil
        let image = listImage ?? homeImage ?? MockArtwork.image(for: media.id, maxPixelSize: size)
            ?? Self.render(seed: media.id, size: size, variant: 0)
        if cache.count > 400 { cache.removeAll() }
        cache[key] = image
        return image
    }

    public func seekPreview(for media: MediaItem, at time: MediaTime, maxPixelSize: CGSize) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        seekPreviewRequests += 1
        if media.id.hasPrefix("ml:wand-s01e") || media.id == "ml:film-dont-blink",
           let frame = MockArtwork.image(named: "seek-preview", maxPixelSize: maxPixelSize) {
            return frame
        }
        let size = Self.fitted(maxPixelSize, aspect: 16.0 / 9.0)
        return Self.render(seed: media.id, size: size, variant: Int(time.seconds / 2))
    }

    /// Figma node 4778:26191: bar heights, left to right, normalized by its 24 pt height.
    /// This is the canonical mock song fixture; production waveforms come from decoded audio.
    private static let figmaUntangleWaveform: [Float] = [
        0.083333, 0.166667, 0.25, 0.166667, 0.25, 0.083333, 0.166667, 0.25, 0.25, 0.083333, 0.583333, 0.5,
        0.416667, 0.583333, 0.5, 0.416667, 0.583333, 0.25, 0.583333, 0.333333, 0.583333, 0.083333, 0.583333, 0.25,
        0.583333, 0.583333, 0.583333, 0.25, 0.583333, 0.333333, 0.583333, 0.25, 0.583333, 0.416667, 0.333333, 0.583333,
        0.333333, 0.166667, 0.583333, 0.083333, 0.583333, 0.083333, 0.583333, 0.583333, 0.333333, 0.583333, 0.583333, 0.333333,
        0.333333, 0.583333, 0.583333, 0.583333, 0.333333, 0.333333, 0.583333, 0.583333, 0.583333, 0.333333, 0.583333, 0.333333,
        0.583333, 0.583333, 0.583333, 0.25, 0.083333, 0.25, 0.416667, 0.416667, 0.583333, 0.416667, 0.333333, 0.583333,
        0.083333, 0.583333, 0.583333, 0.25, 0.583333, 0.583333, 0.333333, 0.083333, 0.583333, 0.583333, 0.583333, 0.25,
        0.333333, 0.333333, 0.583333, 0.583333, 0.083333, 0.583333, 0.583333, 0.333333, 0.083333, 0.583333, 0.583333, 0.583333,
        0.083333, 0.583333, 0.583333, 0.583333, 0.583333, 0.333333, 0.583333, 0.333333, 0.583333, 0.166667, 0.083333, 0.583333,
        0.083333, 0.583333, 0.416667, 0.583333, 0.166667, 0.583333, 0.333333, 0.583333, 0.083333, 0.583333, 0.083333, 0.583333,
        0.333333, 0.583333, 0.583333, 0.083333, 0.583333, 0.333333, 0.583333, 0.083333, 0.583333, 0.333333, 0.25, 0.083333,
        0.583333, 0.583333, 0.083333, 0.583333, 0.333333, 0.583333, 0.333333, 0.583333, 0.583333, 0.25, 0.583333, 0.333333,
        0.583333, 0.583333, 0.083333, 0.333333, 0.583333, 0.083333, 0.583333, 0.416667, 0.416667, 0.083333, 0.583333, 0.583333,
        0.083333, 0.583333, 0.583333, 0.333333, 0.583333, 0.333333, 0.583333, 0.583333, 0.583333, 0.083333, 0.083333, 0.083333,
        0.416667, 0.416667, 0.583333, 0.583333, 0.583333, 0.083333, 0.333333, 0.583333, 0.333333, 0.583333, 0.333333, 0.416667,
        0.25, 0.166667, 0.583333, 0.583333, 0.333333, 0.583333, 0.583333, 0.083333, 0.583333, 0.083333, 0.583333, 0.583333,
        0.333333, 0.583333, 0.583333, 0.333333, 0.583333, 0.333333, 0.583333, 0.083333, 0.583333, 0.583333, 0.083333, 0.583333,
        0.25, 0.583333, 0.583333, 0.583333, 0.083333, 0.583333, 0.333333, 0.583333, 0.333333, 0.583333, 0.416667, 0.416667,
        0.083333, 0.583333, 0.583333, 0.333333, 0.583333, 0.333333, 0.416667, 0.083333, 0.583333, 0.583333, 0.083333, 0.583333,
        0.333333, 0.583333, 0.583333, 0.583333, 0.333333, 0.583333, 0.166667, 0.583333, 0.583333, 0.083333, 0.416667, 0.25,
        0.583333, 0.583333, 0.25, 0.583333,
    ]

    public func waveform(for media: MediaItem, bins: Int) async -> [Float]? {
        guard bins > 0 else { return [] }
        if media.id == MockDatabase.untangleID {
            let samples = Self.figmaUntangleWaveform
            if bins == samples.count { return samples }
            if bins == 1 { return [samples[0]] }
            return (0..<bins).map { index in
                let position = Double(index) * Double(samples.count - 1) / Double(bins - 1)
                let lower = Int(position)
                let upper = min(lower + 1, samples.count - 1)
                let fraction = Float(position - Double(lower))
                return samples[lower] + (samples[upper] - samples[lower]) * fraction
            }
        }
        var generator = SeededGenerator(seed: stableHash("wave:" + media.id))
        var values: [Float] = []
        values.reserveCapacity(bins)
        var level: Float = 0.5
        for index in 0..<bins {
            let noise = Float(generator.next() % 1_000) / 1_000
            level = max(0.12, min(1, level * 0.6 + noise * 0.55))
            let envelope = Float(sin(Double(index) / Double(bins) * .pi)) * 0.35 + 0.65
            values.append(level * envelope)
        }
        return values
    }

    private static func fitted(_ size: CGSize, aspect: Double) -> CGSize {
        let width = max(16, size.width > 0 ? size.width : 320)
        let height = max(16, size.height > 0 ? size.height : width / aspect)
        if width / height > aspect { return CGSize(width: (height * aspect).rounded(), height: height.rounded()) }
        return CGSize(width: width.rounded(), height: (width / aspect).rounded())
    }

    /// A two-color diagonal gradient with a soft disc, seeded by `seed` and shifted by `variant`.
    static func render(seed: String, size: CGSize, variant: Int) -> CGImage? {
        let width = Int(size.width), height = Int(size.height)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        var generator = SeededGenerator(seed: stableHash(seed))
        func component() -> CGFloat { CGFloat(generator.next() % 1_000) / 1_000 }
        let hue = component()
        let shift = CGFloat(variant % 60) / 60 * 0.15
        let first = hsb(hue + shift, 0.55, 0.45)
        let second = hsb(hue + 0.12 + shift, 0.65, 0.18)
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [first, second] as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        }
        let radius = CGFloat(min(width, height)) * (0.25 + component() * 0.2)
        let center = CGPoint(x: CGFloat(width) * (0.25 + component() * 0.5 + shift), y: CGFloat(height) * (0.3 + component() * 0.4))
        context.setFillColor(hsb(hue + 0.5, 0.35, 0.75, alpha: 0.35))
        context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        return context.makeImage()
    }

    private static func hsb(_ h: CGFloat, _ s: CGFloat, _ b: CGFloat, alpha: CGFloat = 1) -> CGColor {
        let hue = h - floor(h)
        let i = Int(hue * 6) % 6
        let f = hue * 6 - floor(hue * 6)
        let p = b * (1 - s), q = b * (1 - f * s), t = b * (1 - (1 - f) * s)
        let (r, g, bl): (CGFloat, CGFloat, CGFloat)
        switch i {
        case 0: (r, g, bl) = (b, t, p)
        case 1: (r, g, bl) = (q, b, p)
        case 2: (r, g, bl) = (p, b, t)
        case 3: (r, g, bl) = (p, q, b)
        case 4: (r, g, bl) = (t, p, b)
        default: (r, g, bl) = (b, p, q)
        }
        return CGColor(srgbRed: r, green: g, blue: bl, alpha: alpha)
    }
}

/// Licensed Figma media-image crops used only by the mock backend and gallery fixtures.
/// No view or application chrome is encoded here; see Resources/Artwork/provenance.json.
public enum MockArtwork {
    /// Looks up a named mock media's artwork. Unknown media use MockThumbnails' procedural fallback.
    public static func image(for mediaID: String, maxPixelSize: CGSize) -> CGImage? {
        let name: String
        switch mediaID {
        case "ml:song-untangle": name = "untangle"
        case "ml:song-moonlight": name = "moonlight"
        case "ml:song-black-bird": name = "black-bird"
        case "ml:film-dont-blink": name = "dont-blink"
        default:
            guard mediaID.hasPrefix("ml:wand-s01e"),
                  let episode = Int(mediaID.suffix(2)), (1...15).contains(episode) else { return nil }
            name = "wand-s01e" + String(format: "%02d", episode)
        }
        return image(named: name, maxPixelSize: maxPixelSize)
    }

    /// Media-only gallery assets such as `player-cat` and `seek-preview` can be supplied to a
    /// player canvas by the gallery host. The production UI has no dependency on mock resources.
    public static func image(named name: String, maxPixelSize: CGSize) -> CGImage? {
        let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Artwork")
            ?? Bundle.module.url(forResource: name, withExtension: "png")
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let maximum = max(maxPixelSize.width, maxPixelSize.height)
        guard maximum.isFinite, maximum > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maximum.rounded(.up)),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
