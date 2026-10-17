import Foundation
import MXRCore
import Observation
import SwiftUI

enum DialogInputError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { message } else { nil } }
}

enum DiscKind: String, CaseIterable {
    case dvd, bluray, cdda
    var title: String { switch self { case .dvd: "DVD"; case .bluray: "Blu-ray"; case .cdda: "Audio CD" } }
}

enum DialogInput {
    private static let networkSchemes: Set<String> = ["http", "https", "rtsp", "rtmp", "rtp", "udp", "srt", "ftp", "mms", "mmsh", "smb", "nfs"]

    static func networkURLs(_ text: String) throws -> [URL] {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { throw DialogInputError.invalid("Enter at least one network URL.") }
        return try lines.map { line in
            guard !line.contains(where: \.isWhitespace), let url = URL(string: line),
                  let scheme = url.scheme?.lowercased(), networkSchemes.contains(scheme),
                  url.port.map({ (1...65535).contains($0) }) ?? true else {
                throw DialogInputError.invalid("Invalid network URL: \(line)")
            }
            let wildcardListener = ["udp", "rtp"].contains(scheme) && url.user == "" && url.password == nil && url.port != nil
            guard let host = url.host, !host.isEmpty || wildcardListener else {
                throw DialogInputError.invalid("Invalid network URL: \(line)")
            }
            return url
        }
    }

    static func subtitleURL(_ text: String) throws -> URL {
        let urls = try networkURLs(text)
        guard urls.count == 1, let url = urls.first,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              SubtitleMatcher.subtitleExtensions.contains(url.pathExtension.lowercased()) else {
            throw DialogInputError.invalid("Enter a direct HTTP or HTTPS link to a subtitle file.")
        }
        return url
    }

    static func discURL(kind: DiscKind, path: String) throws -> URL {
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/"), !path.contains("\n"), !path.contains("\0") else {
            throw DialogInputError.invalid("Select a mounted disc or enter its absolute device path.")
        }
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: kind.rawValue + "://" + encoded) else {
            throw DialogInputError.invalid("The disc path is invalid.")
        }
        return url
    }

    static func captureURL(deviceID: String) throws -> URL {
        let id = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !id.contains(where: \.isWhitespace), !id.contains("/"), !id.contains("?"), !id.contains("#"),
              let url = URL(string: "avcapture://" + id) else {
            throw DialogInputError.invalid("Choose a camera.")
        }
        return url
    }

    static func conversionDestination(_ destination: URL, fileExtension: String = "mp4") throws -> URL {
        guard destination.isFileURL, destination.pathExtension.lowercased() == fileExtension.lowercased() else {
            throw DialogInputError.invalid("Save the file with the .\(fileExtension) extension.")
        }
        guard !destination.path.contains("\0"), !destination.path.contains("\n"), !destination.path.contains("\r") else {
            throw DialogInputError.invalid("The destination contains an unsupported control character.")
        }
        return destination
    }

    /// A stream destination from its parts (Stream dialog): HTTP listens on the address, UDP and RTP send to it.
    static func streamURL(kind: StreamDestination, host: String, port: String, path: String = "") throws -> URL {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !host.contains(where: { $0.isWhitespace || "/?#@".contains($0) }) else {
            throw DialogInputError.invalid("Enter the address to stream to, such as 0.0.0.0 or 239.255.0.1.")
        }
        guard let number = Int(port.trimmingCharacters(in: .whitespaces)), (1...65535).contains(number) else {
            throw DialogInputError.invalid("Enter a port from 1 to 65535.")
        }
        var components = URLComponents()
        components.scheme = kind.rawValue
        components.host = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        components.port = number
        if kind == .http {
            let trimmed = path.trimmingCharacters(in: .whitespaces)
            components.path = trimmed.isEmpty ? "" : (trimmed.hasPrefix("/") ? trimmed : "/" + trimmed)
        }
        guard let url = components.url else { throw DialogInputError.invalid("The stream address is invalid.") }
        return url
    }

    static func streamURL(_ endpoint: String) throws -> URL {
        let urls = try networkURLs(endpoint)
        guard urls.count == 1, let url = urls.first, url.scheme?.lowercased() == "http", url.port != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw DialogInputError.invalid("Enter an HTTP listening URL with an explicit port, such as http://127.0.0.1:8080/live.")
        }
        return url
    }
}

/// Subtitle and folder lookups read the file system synchronously (Foundation cannot interrupt a
/// directory read), so they run one at a time on a private serial queue instead of blocking a thread
/// of Swift's cooperative pool. A lookup cancelled while queued skips its I/O; a lookup cancelled
/// while running has its result dropped.
private enum SubtitleFilesystemLookup {
    private static let queue = DispatchQueue(label: "org.videolan.vlc.redesign.subtitle-lookup", qos: .userInitiated)

    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }

    static func run<Value: Sendable>(cancelled: Value, operation: @escaping @Sendable () -> Value) async -> Value {
        let cancellation = Cancellation()
        let value = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Value, Never>) in
                queue.async { continuation.resume(returning: cancellation.isCancelled ? cancelled : operation()) }
            }
        } onCancel: { cancellation.cancel() }
        return Task.isCancelled ? cancelled : value
    }
}

@MainActor @Observable
final class SubtitleImportDraft {
    var scope: AddSubtitlesScope {
        didSet {
            guard scope != oldValue else { return }
            generation += 1
            media = []
            assignments = [:]
            error = nil
            loading = true
        }
    }
    var source: AddSubtitlesSource
    var media: [MediaItem]
    var subtitles: [URL]
    var selected: Set<URL>
    var assignments: [String: URL] = [:]
    var locationTitle: String
    var link = ""
    var search = ""
    var language = "English"
    var error: String?
    var loading = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let initialScope: AddSubtitlesScope
    @ObservationIgnored private let initialMedia: [MediaItem]
    @ObservationIgnored private var context: SubtitleTargetContext?
    @ObservationIgnored private let listVideos: @Sendable (URL) -> [URL]

    init(scope: AddSubtitlesScope, source: AddSubtitlesSource, media: [MediaItem] = [], subtitles: [URL] = [],
         selected: Set<URL>? = nil, locationTitle: String = "",
         listVideos: @escaping @Sendable (URL) -> [URL] = { SubtitleFolderRules.videos(in: $0) }) {
        self.scope = scope
        self.source = source
        self.media = scope == .file ? Array(media.prefix(1)) : media
        self.subtitles = subtitles
        self.selected = selected ?? Set(subtitles)
        self.locationTitle = locationTitle
        self.listVideos = listVideos
        initialScope = scope
        initialMedia = media
        rematch()
    }

    var canSave: Bool { !media.isEmpty && (scope == .file ? media.count == 1 && !selected.isEmpty : !assignments.isEmpty) && !loading }

    func importFiles(_ urls: [URL]) {
        let valid = urls.filter { SubtitleMatcher.subtitleExtensions.contains($0.pathExtension.lowercased()) }
        guard !valid.isEmpty else { error = "Select a subtitle file such as SRT, ASS, or VTT."; return }
        for url in valid where !subtitles.contains(url) { subtitles.append(url); selected.insert(url) }
        error = nil
        rematch()
    }

    func rematch() {
        let matches = SubtitleMatcher.match(videos: media.map(\.listTitle), subtitles: subtitles.map(\.lastPathComponent))
        assignments = [:]
        for item in media {
            if let name = matches[item.listTitle], let url = subtitles.first(where: { $0.lastPathComponent == name }) { assignments[item.id] = url }
        }
    }

    func loadTargets(from app: AppModel) async {
        if context == nil {
            let seed = initialMedia.isEmpty ? app.interface.subtitleTargetMedia : initialMedia
            let file = seed.first ?? app.player.media
            let folder: LibraryLocation?
            // A file with no library folder (opened from Finder) uses its folder on disk, never
            // whatever folder the library happens to be browsing (SD-18).
            if let reference = file?.folder { folder = .folder(reference.id) }
            else if file?.id.hasPrefix("ml:") ?? true, case .folder = app.library.location { folder = app.library.location }
            else { folder = nil }
            let playlist: LibraryLocation?
            if case .playlist = app.library.location { playlist = app.library.location }
            else { playlist = nil }
            // A file opened from Finder has no library folder: use its folder on disk (SD-18).
            let directory = file.flatMap { URL(string: $0.mrl) }.flatMap { $0.isFileURL ? $0.deletingLastPathComponent() : nil }
            context = SubtitleTargetContext(seed: seed, file: file, folder: folder, playlist: playlist, directory: directory)
        }
        guard let context else { return }
        generation += 1
        let token = generation
        let scope = scope
        loading = true
        let items: [MediaItem]
        switch scope {
        case .file:
            items = context.file.map { [$0] } ?? []
        case .folder:
            if initialScope == .folder && !context.seed.isEmpty { items = context.seed }
            else if let location = context.folder { items = await app.library.allMedia(at: location) }
            else if let directory = context.directory {
                let listVideos = listVideos
                items = await SubtitleFilesystemLookup.run(cancelled: [MediaItem]()) {
                    var result: [MediaItem] = []
                    for url in listVideos(directory) {
                        guard !Task.isCancelled else { return [] }
                        result.append(MediaItem(url: url))
                    }
                    return result
                }
            }
            else { items = [] }
        case .playlist:
            if initialScope == .playlist && !context.seed.isEmpty { items = context.seed }
            else if let location = context.playlist { items = await app.library.allMedia(at: location) }
            else { items = [] }
        }
        guard token == generation, !Task.isCancelled else { return }
        media = items.filter { $0.kind == .video || $0.kind == .disc || $0.kind == .stream }
        if locationTitle.isEmpty {
            locationTitle = context.folder == nil && scope == .folder ? context.directory?.lastPathComponent ?? ""
                : app.library.breadcrumb.map(\.title).joined(separator: " / ")
        }
        if media.isEmpty {
            switch scope {
            case .file: error = "Play or select a video before adding its subtitles."
            case .folder: error = "There are no videos in this folder."
            case .playlist: error = "Open a playlist in the library before adding its subtitles."
            }
        }
        else { error = nil }
        rematch()
        loading = false
    }

    /// `resolve` gives a file's identity on disk (symbolic links resolved). It reads the file
    /// system, so it runs on the lookup queue, never on the main actor (PER-02): a slow or
    /// disconnected volume cannot stall the window while Save works out which item is playing.
    func save(to app: AppModel, rules: SubtitleFolderRulesStore = .shared,
              resolve: @escaping @Sendable (URL) -> URL = { $0.standardizedFileURL.resolvingSymlinksInPath() }) async throws {
        guard canSave else { throw DialogInputError.invalid("Select a video and at least one subtitle.") }
        // Busy while the paths are read: a second click cannot save twice.
        loading = true
        let playingFiles = await playingFileIDs(app: app, resolve: resolve)
        loading = false
        var remembered: [(video: URL, subtitle: URL)] = []
        var inLibrary: Set<URL> = []
        for item in media {
            let urls = scope == .file ? subtitles.filter { selected.contains($0) } : assignments[item.id].map { [$0] } ?? []
            for url in urls {
                // Only library items can carry an attached subtitle in the media library.
                if item.id.hasPrefix("ml:") { app.backends.library.attachSubtitle(url: url, toMedia: item.id) }
                if isPlaying(item, in: app) || playingFiles.contains(item.id) { app.tracks.addExternalTrack(url: url, kind: .subtitle) }
            }
            if let video = URL(string: item.mrl), video.isFileURL, !urls.isEmpty {
                remembered.append(contentsOf: urls.map { (video, $0) })
                // The library already loads this one (bridge AttachLibrarySubtitleSlaves): not again here.
                if item.id.hasPrefix("ml:") { inLibrary.insert(video) }
            }
        }
        // Folder scope keeps the choice for episodes added later; file and playlist scopes keep it per file.
        let folder = scope == .folder ? remembered.first.map { $0.video.deletingLastPathComponent() } : nil
        rules.remember(remembered, forFolder: folder, inLibrary: inLibrary)
    }

    private func isPlaying(_ item: MediaItem, in app: AppModel) -> Bool {
        guard let current = app.player.media else { return false }
        // Library IDs use ml:<id>, while the native player's IDs use the media URI.
        return current.id == item.id || (!item.mrl.isEmpty && current.mrl == item.mrl)
    }

    /// The items that are the playing file under another path (`..`, a symbolic link), found off
    /// the main actor. Empty when nothing local plays or the save is cancelled.
    private func playingFileIDs(app: AppModel, resolve: @escaping @Sendable (URL) -> URL) async -> Set<String> {
        guard let current = app.player.media, let playing = URL(string: current.mrl), playing.isFileURL else { return [] }
        let files = media.compactMap { item -> (String, URL)? in
            guard !isPlaying(item, in: app), let url = URL(string: item.mrl), url.isFileURL else { return nil }
            return (item.id, url)
        }
        guard !files.isEmpty else { return [] }
        let playingID = current.id
        let found = await SubtitleFilesystemLookup.run(cancelled: Set<String>()) {
            let target = resolve(playing)
            return Set(files.filter { resolve($0.1) == target }.map(\.0))
        }
        // The player moved on while the paths were read: the result is about another file.
        return app.player.media?.id == playingID ? found : []
    }
}

private struct SubtitleTargetContext {
    let seed: [MediaItem]
    let file: MediaItem?
    let folder: LibraryLocation?
    let playlist: LibraryLocation?
    /// The playing file's folder on disk, for files outside the library.
    let directory: URL?
}

/// The saved subtitle choices (``SubtitleFolderRules``), applied whenever a new item starts playing.
@MainActor
final class SubtitleFolderRulesStore {
    static let shared = SubtitleFolderRulesStore()
    private let defaults: UserDefaults?
    private(set) var rules: SubtitleFolderRules

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        rules = SubtitleFolderRules.load(from: defaults)
    }

    init(rules: SubtitleFolderRules) {
        defaults = nil
        self.rules = rules
    }

    func remember(_ assignments: [(video: URL, subtitle: URL)], forFolder folder: URL?, inLibrary: Set<URL> = []) {
        guard !assignments.isEmpty else { return }
        rules.remember(assignments, forFolder: folder, inLibrary: inLibrary)
        if let defaults { rules.save(to: defaults) }
    }

    /// The native input finishes sidecar discovery before entering playing/paused.
    /// Nil while opening also cancels pending work when a new input replaces it.
    static func readyMediaID(for media: MediaItem?, state: PlayerState) -> String? {
        guard state == .playing || state == .paused else { return nil }
        return media?.id
    }

    /// Resolve filesystem rules off the UI executor. Apply only to the still-current input.
    func apply(to media: MediaItem, tracks: TracksModel,
               resolve: @escaping @Sendable (SubtitleFolderRules, URL) -> [URL] = { $0.subtitles(for: $1) },
               isCurrent: @MainActor () -> Bool = { true }) async {
        guard let video = URL(string: media.mrl), video.isFileURL else { return }
        let snapshot = rules
        let subtitles = await SubtitleFilesystemLookup.run(cancelled: [URL]()) { resolve(snapshot, video) }
        guard !Task.isCancelled, isCurrent() else { return }
        // A filename prefix does not prove autodetection ran (it may be disabled or stricter).
        // Only tracks actually present in the player's snapshot count as already attached.
        let attached = Set(tracks.externalTracks(of: .subtitle).compactMap(\.sourceURL).map {
            $0.isFileURL ? $0.standardizedFileURL : $0
        })
        for subtitle in subtitles {
            let canonical = subtitle.isFileURL ? subtitle.standardizedFileURL : subtitle
            if !attached.contains(canonical) { tracks.addExternalTrack(url: subtitle, kind: .subtitle) }
        }
    }
}

extension View {
    /// Applies remembered Add Subtitles choices to each new item (SD-18).
    func mxrRememberedSubtitles() -> some View { modifier(MXRRememberedSubtitles()) }
}

private struct MXRRememberedSubtitles: ViewModifier {
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.task(id: SubtitleFolderRulesStore.readyMediaID(for: app.player.media, state: app.player.state)) {
            guard let media = app.player.media,
                  SubtitleFolderRulesStore.readyMediaID(for: media, state: app.player.state) != nil else { return }
            await SubtitleFolderRulesStore.shared.apply(to: media, tracks: app.tracks, isCurrent: {
                SubtitleFolderRulesStore.readyMediaID(for: app.player.media, state: app.player.state) == media.id
                    && app.player.media?.mrl == media.mrl
            })
        }
    }
}
