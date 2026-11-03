import Foundation
import os

/// Where app-side stores (presets, pins, recents, profiles) keep their JSON files.
public enum PersistenceLocation: Sendable, Equatable {
    /// Nothing is read or written (previews, gallery, snapshot tests).
    case inMemory
    /// Files live in this directory (created on first write).
    case directory(URL)

    /// `~/Library/Application Support/<bundle id>/macosx-redesign/`.
    ///
    /// The VLC backend may instead pass `config_GetUserDir(VLC_USERDATA_DIR)/macosx-redesign/`, which
    /// resolves to the same place inside the packaged app (ARCHITECTURE.md §1.4, §5.2).
    public static var applicationSupport: PersistenceLocation {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let bundleID = Bundle.main.bundleIdentifier ?? "org.videolan.vlc-redesign"
        return .directory(base.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("macosx-redesign", isDirectory: true))
    }

    /// The URL of `fileName` in this location, or nil when in memory.
    public func fileURL(_ fileName: String) -> URL? {
        switch self {
        case .inMemory: return nil
        case .directory(let directory): return directory.appendingPathComponent(fileName)
        }
    }
}

/// Loads and saves one Codable value as a JSON file. Used by the app-side stores.
///
/// Writes are atomic and synchronous; the files are a few kilobytes at most.
/// Failures are logged and never thrown to the UI. A file that does not decode is moved aside as
/// `<name>.unreadable-<timestamp>.json` before the store starts empty, so the next save cannot
/// overwrite it; a file whose lists have entries this version cannot read (``LossyArray``,
/// ``LossyDictionary``) is copied aside the same way, the rest is loaded and the stores write those
/// entries back unchanged.
public struct JSONFileStore<Value: Codable>: Sendable {
    /// The file, or nil for an in-memory store that never touches the disk.
    public let fileURL: URL?

    private static var logger: Logger { Logger(subsystem: "org.videolan.vlc-redesign", category: "persistence") }

    /// Creates a store for `fileName` inside `location`.
    public init(location: PersistenceLocation, fileName: String) {
        self.fileURL = location.fileURL(fileName)
    }

    /// Reads the value, or nil when the file is missing, unreadable or in memory.
    public func load() -> Value? {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let dropped = DroppedEntries()
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.userInfo[DroppedEntries.key] = dropped
            let value = try decoder.decode(Value.self, from: data)
            if dropped.count > 0 {
                let copy = setAside(fileURL, move: false)
                Self.logger.error("Skipped \(dropped.count) unreadable entries of \(fileURL.path, privacy: .public); the original is kept at \(copy?.path ?? "nowhere", privacy: .public)")
            }
            return value
        } catch {
            let moved = setAside(fileURL, move: true)
            Self.logger.error("Could not read \(fileURL.path, privacy: .public), kept it at \(moved?.path ?? "the same place", privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Writes the value. Does nothing in memory.
    public func save(_ value: Value) {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(value).write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Could not write \(fileURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// Moves (or copies) `url` to `<name>.unreadable-<timestamp>.<ext>` next to it. Returns the new
    /// URL, or nil when the file system refused. A file already set aside with the same bytes is
    /// reused, so a file that keeps losing the same entries on every launch is kept only once.
    private func setAside(_ url: URL, move: Bool) -> URL? {
        let prefix = url.deletingPathExtension().lastPathComponent + ".unreadable-"
        let ext = url.pathExtension.isEmpty ? "" : "." + url.pathExtension
        let directory = url.deletingLastPathComponent()
        if let data = try? Data(contentsOf: url),
           let siblings = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil),
           let existing = siblings.first(where: {
               $0.lastPathComponent.hasPrefix(prefix) && $0.lastPathComponent.hasSuffix(ext) && (try? Data(contentsOf: $0)) == data
           }) {
            if move { try? FileManager.default.removeItem(at: url) }
            return existing
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stem = prefix + formatter.string(from: Date())
        var target = directory.appendingPathComponent(stem + ext)
        var suffix = 1
        while FileManager.default.fileExists(atPath: target.path) {
            suffix += 1
            target = directory.appendingPathComponent("\(stem)-\(suffix)\(ext)")
        }
        do {
            if move { try FileManager.default.moveItem(at: url, to: target) } else { try FileManager.default.copyItem(at: url, to: target) }
            return target
        } catch {
            return nil
        }
    }
}

/// Counts the entries ``LossyArray`` and ``LossyDictionary`` skipped during one ``JSONFileStore/load()``.
final class DroppedEntries: @unchecked Sendable {
    static let key = CodingUserInfoKey(rawValue: "org.videolan.vlc-redesign.droppedEntries")!
    var count = 0

    static func record(in decoder: any Decoder) { (decoder.userInfo[key] as? DroppedEntries)?.count += 1 }
}

/// Any JSON value, kept as it was read so it can be written back unchanged.
public enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Int64.self) { self = .integer(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let value): try c.encode(value)
        case .integer(let value): try c.encode(value)
        case .number(let value): try c.encode(value)
        case .string(let value): try c.encode(value)
        case .array(let value): try c.encode(value)
        case .object(let value): try c.encode(value)
        }
    }
}

/// An entry of a ``LossyArray`` this version could not read, and where it was in the list.
public struct UnreadableEntry: Hashable, Sendable {
    public var offset: Int
    public var value: JSONValue
}

/// An array persisted as a plain JSON array whose entries decode one by one: an entry that does not
/// decode (an unknown enum case, a missing field written by another version) is skipped instead of
/// failing the whole file. Skipped entries are kept in ``unreadable`` and written back at their place,
/// so a version that cannot read them does not erase them for the version that wrote them.
public struct LossyArray<Element: Codable>: Codable {
    public var elements: [Element]
    public var unreadable: [UnreadableEntry]

    public init(_ elements: [Element], unreadable: [UnreadableEntry] = []) {
        self.elements = elements
        self.unreadable = unreadable
    }

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        var unreadable: [UnreadableEntry] = []
        while !container.isAtEnd {
            let offset = container.currentIndex
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                unreadable.append(UnreadableEntry(offset: offset, value: try container.decode(JSONValue.self)))
                DroppedEntries.record(in: decoder)
            }
        }
        self.elements = elements
        self.unreadable = unreadable
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        var pending = unreadable.sorted { $0.offset < $1.offset }[...]
        for element in elements {
            while let next = pending.first, next.offset <= container.count {
                try container.encode(next.value)
                pending.removeFirst()
            }
            try container.encode(element)
        }
        for entry in pending { try container.encode(entry.value) }
    }
}

/// A string-keyed dictionary persisted as a plain JSON object whose values decode one by one, like
/// ``LossyArray``. Values that do not decode are kept in ``unreadable`` and written back under their
/// key unless ``values`` has that key.
public struct LossyDictionary<Value: Codable>: Codable {
    public var values: [String: Value]
    public var unreadable: [String: JSONValue]

    public init(_ values: [String: Value], unreadable: [String: JSONValue] = [:]) {
        self.values = values
        self.unreadable = unreadable
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        var values: [String: Value] = [:]
        var unreadable: [String: JSONValue] = [:]
        for key in container.allKeys {
            if let value = try? container.decode(Value.self, forKey: key) {
                values[key.stringValue] = value
            } else {
                unreadable[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
                DroppedEntries.record(in: decoder)
            }
        }
        self.values = values
        self.unreadable = unreadable
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for (key, value) in values { try container.encode(value, forKey: Key(stringValue: key)) }
        for (key, value) in unreadable where values[key] == nil { try container.encode(value, forKey: Key(stringValue: key)) }
    }
}

/// Locates resource files of the Core target without relying on SwiftPM's `Bundle.module` in the plugin,
/// where it would `fatalError` (ARCHITECTURE.md §7.6).
public enum MXRResources {
    /// Name of the Core resource bundle produced by SwiftPM.
    public static let coreBundleName = "MacOSXRedesign_MXRCore.bundle"

    /// Set to false by the plugin at startup so `Bundle.module` is never touched there.
    nonisolated(unsafe) public static var allowsBundleModuleFallback = true

    /// Finds `name.ext` in the Core resources: `$MXR_RESOURCES_PATH`, the main bundle's resources,
    /// next to the executable, then `Bundle.module` (Gallery and tests only).
    public static func url(forResource name: String, withExtension ext: String) -> URL? {
        var candidates: [URL] = []
        if let env = ProcessInfo.processInfo.environment["MXR_RESOURCES_PATH"] {
            let root = URL(fileURLWithPath: env, isDirectory: true)
            candidates.append(root.appendingPathComponent(coreBundleName))
            candidates.append(root)
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent(coreBundleName))
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent(coreBundleName))
        if let executable = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(executable.appendingPathComponent(coreBundleName))
        }
        for directory in candidates {
            if let bundle = Bundle(url: directory), let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
            let direct = directory.appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: direct.path) { return direct }
        }
        if allowsBundleModuleFallback {
            return Bundle.module.url(forResource: name, withExtension: ext)
        }
        return nil
    }
}
