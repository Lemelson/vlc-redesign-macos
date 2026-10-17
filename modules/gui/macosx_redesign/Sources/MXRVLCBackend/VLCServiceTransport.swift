import Foundation
import MXRCore
import MXRBridgeAPI

/// Main-actor connection to the Objective-C bridge. Foundation values never escape into views.
@MainActor
protocol VLCServiceTransport: AnyObject {
    var capabilities: [String: Any] { get }
    func snapshot(for service: MXRBridgeService) -> [String: Any]
    func perform(_ command: MXRBridgeCommand, service: MXRBridgeService, arguments: [String: Any]) throws
    func request(_ request: MXRBridgeRequest, service: MXRBridgeService, arguments: [String: Any]) async throws -> [String: Any]
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (MXRBridgeService) -> Void)
    func log(_ error: Error)
    /// An operation the user asked for failed: shown as a dialog.
    func report(_ error: Error)
    /// A short-lived message in the redesign OSD (a player command that could not run).
    /// Never a dialog and never the in-video playback-error card (MISS-03, ARC-11).
    func notify(_ message: String)
}

extension VLCServiceTransport {
    func command(_ command: MXRBridgeCommand, service: MXRBridgeService, arguments: [String: Any] = [:]) {
        do { try perform(command, service: service, arguments: arguments) }
        catch { report(error) }
    }
    func notify(_ message: String) { log(BackendOperationError.invalidInput(message)) }
}

/// Typed keys shared with the bridge (MXRBridgeKeys.h): `values[.volume]`, `values.bool(.canSeek)`.
extension Dictionary where Key == String, Value == Any {
    subscript<K: RawRepresentable>(key: K) -> Any? where K.RawValue == String {
        get { self[key.rawValue] }
        set { self[key.rawValue] = newValue }
    }
    func dictionary<K: RawRepresentable>(_ key: K) -> [String: Any] where K.RawValue == String { dictionary(key.rawValue) }
    func dictionaries<K: RawRepresentable>(_ key: K) -> [[String: Any]] where K.RawValue == String { dictionaries(key.rawValue) }
    func string<K: RawRepresentable>(_ key: K) -> String? where K.RawValue == String { string(key.rawValue) }
    func integer<K: RawRepresentable>(_ key: K, default fallback: Int = 0) -> Int where K.RawValue == String { integer(key.rawValue, default: fallback) }
    func int64<K: RawRepresentable>(_ key: K, default fallback: Int64 = 0) -> Int64 where K.RawValue == String { int64(key.rawValue, default: fallback) }
    func double<K: RawRepresentable>(_ key: K, default fallback: Double = 0) -> Double where K.RawValue == String { double(key.rawValue, default: fallback) }
    func bool<K: RawRepresentable>(_ key: K, default fallback: Bool = false) -> Bool where K.RawValue == String { bool(key.rawValue, default: fallback) }
    func url<K: RawRepresentable>(_ key: K) -> URL? where K.RawValue == String { url(key.rawValue) }
}

extension Dictionary where Key == String, Value == Any {
    func dictionary(_ key: String) -> [String: Any] { self[key] as? [String: Any] ?? [:] }
    func dictionaries(_ key: String) -> [[String: Any]] { self[key] as? [[String: Any]] ?? [] }
    func string(_ key: String) -> String? { self[key] as? String }
    func integer(_ key: String, default fallback: Int = 0) -> Int { (self[key] as? NSNumber)?.intValue ?? string(key).flatMap(Int.init) ?? fallback }
    func int64(_ key: String, default fallback: Int64 = 0) -> Int64 { (self[key] as? NSNumber)?.int64Value ?? string(key).flatMap(Int64.init) ?? fallback }
    func double(_ key: String, default fallback: Double = 0) -> Double { (self[key] as? NSNumber)?.doubleValue ?? string(key).flatMap(Double.init) ?? fallback }
    func bool(_ key: String, default fallback: Bool = false) -> Bool { (self[key] as? NSNumber)?.boolValue ?? fallback }
    func url(_ key: String) -> URL? { if let url = self[key] as? URL { return url }; return string(key).flatMap(URL.init(string:)) }
}

enum VLCWire {
    static func capabilities(_ flags: [String: Any]) -> BackendCapabilities {
        BackendCapabilities(hasMediaLibrary: flags.bool("library", default: flags.bool("hasMediaLibrary")),
            hasExtensions: flags.bool("extensions", default: flags.bool("hasExtensions")),
            hasAddonsCatalog: flags.bool("addons", default: flags.bool("hasAddonsCatalog")),
            hasThumbnails: flags.bool("thumbnails", default: flags.bool("hasThumbnails")),
            hasRecording: flags.bool("recording", default: flags.bool("hasRecording")),
            hasRenderers: flags.bool("renderers", default: flags.bool("hasRenderers")),
            pictureInPicture: PictureInPictureSupport(rawValue: flags.string("pictureInPicture") ?? "unsupported") ?? .unsupported,
            supportsReversePlayback: flags.bool("supportsReversePlayback"), supportsWaveform: flags.bool("supportsWaveform"),
            supportsSubtitleTimeline: flags.bool("supportsSubtitleTimeline"), supportsOpenSubtitles: flags.bool("supportsOpenSubtitles"),
            supportsGlobalHotkeys: flags.bool("globalHotkeys", default: flags.bool("supportsGlobalHotkeys")),
            hasStereoTest: flags.bool("stereoTest"))
    }
    static func media(_ value: [String: Any]) -> MediaItem? {
        guard let mrl = value.string("url") ?? value.string("mrl"), !mrl.isEmpty else { return nil }
        let url = URL(string: mrl)
        let length = value.int64("duration", default: -1)
        var item = MediaItem(id: value.string("id") ?? mrl, mrl: mrl,
            title: value.string("title") ?? url?.lastPathComponent ?? mrl,
            fileName: value.string("fileName") ?? (url?.isFileURL == true ? url?.lastPathComponent : nil),
            kind: MediaKind(rawValue: value.string("kind") ?? "unknown") ?? .unknown,
            duration: length >= 0 ? MediaTime(microseconds: length) : nil,
            progress: (value["progress"] as? NSNumber)?.doubleValue,
            playCount: value.integer("playCount"), isFavorite: value.bool("isFavorite"),
            artist: value.string("artist"), album: value.string("album"), genre: value.string("genre"), artworkURL: value.url("artworkURL"))
        if let id = value.dictionary("folder").string("id") {
            item.folder = FolderReference(id: id, name: value.dictionary("folder").string("name") ?? "Folder")
        }
        if let seconds = value["lastPlayedDate"] as? NSNumber, seconds.doubleValue > 0 { item.lastPlayedDate = Date(timeIntervalSince1970: seconds.doubleValue) }
        if let seconds = value["addedDate"] as? NSNumber { item.addedDate = Date(timeIntervalSince1970: seconds.doubleValue) }
        // Album-track metadata (library rows "title - artist", music sorts).
        item.trackNumber = (value["trackNumber"] as? NSNumber)?.intValue
        item.discNumber = (value["discNumber"] as? NSNumber)?.intValue
        item.year = (value["year"] as? NSNumber)?.intValue
        let width = value.double("width"), height = value.double("height")
        if width > 0, height > 0 { item.videoSize = CGSize(width: width, height: height) }
        return item
    }
    static func scalar(_ value: Any?, type: SettingOptionType? = nil) -> SettingValue? {
        if let string = value as? String { return .string(string) }
        guard let number = value as? NSNumber else { return nil }
        if type == .bool || CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
        if type == .float { return .float(number.doubleValue) }
        if type == .integer || type == .color || type == .key { return .integer(number.intValue) }
        return number.doubleValue.rounded() == number.doubleValue ? .integer(number.intValue) : .float(number.doubleValue)
    }
    static func foundation(_ value: SettingValue) -> Any {
        switch value { case .bool(let x): x; case .integer(let x): x; case .float(let x): x; case .string(let x): x }
    }
    static func dictionary<T: Encodable>(_ value: T) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(value), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }
    static func decode<T: Decodable>(_ type: T.Type, from value: [String: Any]) -> T? {
        guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
