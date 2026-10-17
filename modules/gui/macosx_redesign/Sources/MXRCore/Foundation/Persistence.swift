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
/// Failures are logged and never thrown to the UI.
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
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            Self.logger.error("Could not read \(fileURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
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
