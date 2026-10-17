import Foundation
import Observation

/// One entry of the app-side recent list ("Open Recent" submenu, S08).
public struct RecentEntry: Identifiable, Hashable, Sendable, Codable {
    public var media: MediaItem
    public var date: Date

    public var id: String { media.id }

    public init(media: MediaItem, date: Date) {
        self.media = media
        self.date = date
    }
}

/// Recently opened media, newest first, persisted to `recents.json`. Honors Settings ▸ Privacy
/// "Save recently played items" through ``isEnabled``.
@MainActor
@Observable
public final class RecentStore {
    public private(set) var entries: [RecentEntry] = []
    /// When false, nothing is recorded.
    public var isEnabled = true
    /// Maximum number of entries kept.
    @ObservationIgnored public var limit = 30
    /// Hosts clear their native recent-document history after the app list is persisted.
    @ObservationIgnored public var onCleared: (@MainActor () -> Void)?
    @ObservationIgnored private let file: JSONFileStore<[RecentEntry]>

    public init(location: PersistenceLocation) {
        file = JSONFileStore(location: location, fileName: "recents.json")
        entries = file.load() ?? []
    }

    /// Records that `media` was opened now (moves it to the top).
    public func record(_ media: MediaItem, at date: Date = Date()) {
        guard isEnabled else { return }
        entries.removeAll { $0.media.id == media.id }
        entries.insert(RecentEntry(media: media, date: date), at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        file.save(entries)
    }

    public func remove(_ entry: RecentEntry) {
        entries.removeAll { $0.id == entry.id }
        file.save(entries)
    }

    /// "Clear history now" / "Clear Menu".
    public func clear() {
        entries = []
        file.save(entries)
        onCleared?()
    }

    /// Replaces the list (mock seeding).
    public func replaceAll(_ entries: [RecentEntry]) {
        self.entries = Array(entries.prefix(limit))
        file.save(self.entries)
    }
}

/// What a rail pin points to.
public enum PinTarget: Hashable, Sendable, Codable {
    /// A folder, playlist, album, stream… shown as a folder/playlist icon.
    case location(LibraryLocation)
    /// A single media, shown as its thumbnail.
    case media(MediaItem)
}

/// A pin in the library rail (S42): pinned folder, playlist or file.
public struct Pin: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var title: String
    public var target: PinTarget

    public init(id: String = UUID().uuidString, title: String, target: PinTarget) {
        self.id = id
        self.title = title
        self.target = target
    }
}

/// Rail pins, in order, persisted to `pins.json`.
@MainActor
@Observable
public final class PinStore {
    public private(set) var pins: [Pin] = []
    @ObservationIgnored private let file: JSONFileStore<[Pin]>

    public init(location: PersistenceLocation) {
        file = JSONFileStore(location: location, fileName: "pins.json")
        pins = file.load() ?? []
    }

    public func isPinned(_ target: PinTarget) -> Bool { pins.contains { $0.target == target } }

    /// Pins a target (no-op when already pinned).
    @discardableResult
    public func pin(_ target: PinTarget, title: String) -> Pin {
        if let existing = pins.first(where: { $0.target == target }) { return existing }
        let pin = Pin(title: title, target: target)
        pins.append(pin)
        file.save(pins)
        return pin
    }

    /// Pins a library entry (folder, playlist, media…).
    @discardableResult
    public func pin(_ entry: LibraryEntry) -> Pin? {
        if let media = entry.media { return pin(.media(media), title: media.listTitle) }
        guard let destination = entry.destination else { return nil }
        return pin(.location(destination), title: entry.title)
    }

    public func unpin(_ pin: Pin) {
        pins.removeAll { $0.id == pin.id }
        file.save(pins)
    }

    public func unpin(_ target: PinTarget) {
        pins.removeAll { $0.target == target }
        file.save(pins)
    }

    /// Reorders by drag.
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var copy = pins
        let moving = source.sorted().map { copy[$0] }
        for index in source.sorted(by: >) { copy.remove(at: index) }
        let insertAt = destination - source.filter { $0 < destination }.count
        copy.insert(contentsOf: moving, at: max(0, min(insertAt, copy.count)))
        pins = copy
        file.save(pins)
    }
}

/// A settings profile (S68): "Movies", "Shows", "Music", "Work".
public struct Profile: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var name: String
    public var settings: [String: SettingValue]

    public init(id: String = UUID().uuidString, name: String, settings: [String: SettingValue] = [:]) {
        self.id = id
        self.name = name
        self.settings = settings
    }
    private enum CodingKeys: String, CodingKey { case id, name, settings }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        settings = try c.decodeIfPresent([String: SettingValue].self, forKey: .settings) ?? [:]
    }
}

/// Profiles and the current one, persisted to `profiles.json`. Explicit selection applies catalog
/// settings; layouts are stored separately by profile ID in `LayoutStore`.
@MainActor
@Observable
public final class ProfileStore {
    public private(set) var profiles: [Profile]
    public private(set) var currentID: String

    @ObservationIgnored private let file: JSONFileStore<Snapshot>

    /// Engine-maintained state and application shortcuts must not become profile overrides.
    private static let optionNames = SettingsCatalog.bundled.referencedOptions.filter {
        !$0.hasPrefix("macosx-redesign-key-")
    }

    private static func profileSettings(_ values: [String: SettingValue]) -> [String: SettingValue] {
        values.filter { optionNames.contains($0.key) }
    }

    private struct Snapshot: Codable {
        var profiles: [Profile]
        var currentID: String
    }

    public init(location: PersistenceLocation) {
        file = JSONFileStore(location: location, fileName: "profiles.json")
        if let snapshot = file.load(), !snapshot.profiles.isEmpty {
            profiles = snapshot.profiles.map {
                var profile = $0
                profile.settings = Self.profileSettings(profile.settings)
                return profile
            }
            currentID = snapshot.profiles.contains { $0.id == snapshot.currentID } ? snapshot.currentID : snapshot.profiles[0].id
        } else {
            let initial = Profile(id: "default", name: "Default")
            profiles = [initial]
            currentID = initial.id
        }
        // Migrate oversized legacy snapshots without touching the engine or profile/layout IDs.
        persist()
    }

    public var current: Profile { profiles.first { $0.id == currentID } ?? profiles[0] }

    /// "Profile (Movies)" menu title.
    public var menuTitle: String { "Profile (\(current.name))" }

    @ObservationIgnored private var snapshotProvider: (@MainActor () -> [String: SettingValue])?
    @ObservationIgnored private var isApplying = false
    @ObservationIgnored private var applyHandler: (@MainActor ([String: SettingValue]) -> Void)?

    /// Connects explicit profile switches to the engine. On startup the engine is authoritative:
    /// it may have saved volume or migrated shortcuts independently since the previous session.
    public func connect(snapshot: @escaping @MainActor () -> [String: SettingValue], apply: @escaping @MainActor ([String: SettingValue]) -> Void) {
        snapshotProvider = snapshot
        applyHandler = apply
        guard let index = profiles.firstIndex(where: { $0.id == currentID }) else { return }
        profiles[index].settings = Self.profileSettings(snapshot())
        persist()
    }

    public func select(_ profile: Profile) {
        guard profile.id != currentID, let target = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        if let source = profiles.firstIndex(where: { $0.id == currentID }), let snapshotProvider { profiles[source].settings = Self.profileSettings(snapshotProvider()) }
        if profiles[target].settings.isEmpty { profiles[target].settings = Self.profileSettings(snapshotProvider?() ?? [:]) }
        currentID = profile.id
        isApplying = true
        applyHandler?(profiles[target].settings)
        isApplying = false
        persist()
    }

    public func captureCurrentSettings() {
        guard !isApplying, let snapshotProvider, let index = profiles.firstIndex(where: { $0.id == currentID }) else { return }
        profiles[index].settings = Self.profileSettings(snapshotProvider())
        persist()
    }

    /// Records live changes even when the user never switches away from the current profile.
    public func recordSetting(_ value: SettingValue?, name: String) {
        guard !isApplying, Self.optionNames.contains(name), let index = profiles.firstIndex(where: { $0.id == currentID }), profiles[index].settings[name] != value else { return }
        profiles[index].settings[name] = value
        persist()
    }

    /// "+ New".
    @discardableResult
    public func create(name: String) -> Profile {
        let profile = Profile(name: name, settings: Self.profileSettings(snapshotProvider?() ?? [:]))
        profiles.append(profile)
        persist()
        return profile
    }

    public func rename(_ profile: Profile, to name: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index].name = name
        persist()
    }

    public func delete(_ profile: Profile) {
        guard profiles.count > 1 else { return }
        if currentID == profile.id, let replacement = profiles.first(where: { $0.id != profile.id }) { select(replacement) }
        profiles.removeAll { $0.id == profile.id }
        persist()
    }

    /// Replaces the list (mock seeding).
    public func replaceAll(_ profiles: [Profile], currentID: String) {
        guard !profiles.isEmpty else { return }
        self.profiles = profiles.map {
            var profile = $0
            profile.settings = Self.profileSettings(profile.settings)
            return profile
        }
        self.currentID = profiles.contains { $0.id == currentID } ? currentID : profiles[0].id
        persist()
    }

    private func persist() { file.save(Snapshot(profiles: profiles, currentID: currentID)) }
}
