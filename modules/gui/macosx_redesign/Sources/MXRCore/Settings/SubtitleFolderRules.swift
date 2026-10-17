import Foundation

/// Remembers subtitles chosen in Add Subtitles (S25) so they come back for every episode of the
/// folder, including episodes added later (VIDEO_BREAKDOWN §06: "the mapping persists for that
/// folder or playlist"). Works on file-system paths, so files opened from Finder are covered too.
public struct SubtitleFolderRules: Codable, Equatable, Sendable {
    /// Video file path → its explicit selections as URL strings (several tracks, remote links).
    public var fileSelections: [String: [String]] = [:]
    /// Video folder path → subtitle files chosen for that folder. Their folders are searched again
    /// for subtitles of new episodes.
    public var folders: [String: [String]] = [:]
    /// Video file paths whose subtitle the media library already attaches (VLC_ML_MEDIA_ADD_EXTERNAL_MRL,
    /// loaded as a slave by the bridge). They are never loaded again from here, so a subtitle is not
    /// added twice; their subtitles still count as taken for other episodes.
    public var libraryVideos: Set<String> = []

    public init() {}

    /// Video files VLC opens from a folder (the Add Subtitles "To This Folder" list).
    public static let videoExtensions: Set<String> = ["mkv", "mp4", "m4v", "mov", "avi", "webm", "wmv", "flv", "ts", "m2ts",
                                                      "mts", "mpg", "mpeg", "ogv", "3gp", "vob", "divx", "rmvb", "asf", "f4v"]

    /// Records all selected tracks for each video, replacing its previous selection.
    public mutating func remember(_ assignments: [(video: URL, subtitle: URL)], forFolder folder: URL?, inLibrary: Set<URL> = []) {
        let library = Set(inLibrary.map(\.standardizedFileURL.path))
        let grouped = Dictionary(grouping: assignments.filter { $0.video.isFileURL }, by: { $0.video.standardizedFileURL.path })
        for (path, choices) in grouped {
            var urls: [String] = []
            for choice in choices {
                let subtitle = choice.subtitle.isFileURL ? choice.subtitle.standardizedFileURL : choice.subtitle
                guard subtitle.isFileURL || ["http", "https"].contains(subtitle.scheme?.lowercased() ?? "") else { continue }
                if !urls.contains(subtitle.absoluteString) { urls.append(subtitle.absoluteString) }
            }
            guard !urls.isEmpty else { continue }
            fileSelections[path] = urls
            if library.contains(path) { libraryVideos.insert(path) } else { libraryVideos.remove(path) }
        }
        if let folder, folder.isFileURL {
            let localPaths = assignments.filter { $0.subtitle.isFileURL }.map { $0.subtitle.standardizedFileURL.path }
            let subtitles = Set(localPaths + (folders[folder.standardizedFileURL.path] ?? []))
            folders[folder.standardizedFileURL.path] = subtitles.sorted()
        }
    }

    /// Every explicit selection for this video, or the best match for a later episode.
    /// Remote links are explicit assignments only; they are never scanned as directories.
    /// The work in memory is short; callers cancel around the file-system reads (``files(in:extensions:)``).
    public func subtitles(for video: URL, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                          listSubtitles: (URL) -> [URL] = SubtitleFolderRules.subtitles(in:)) -> [URL] {
        guard video.isFileURL, !Task.isCancelled else { return [] }
        let path = video.standardizedFileURL.path
        if libraryVideos.contains(path) { return [] }
        if let chosen = fileSelections[path] {
            return chosen.compactMap(URL.init(string:)).filter { !$0.isFileURL || fileExists($0.path) }
        }
        let folder = video.deletingLastPathComponent().standardizedFileURL.path
        guard let remembered = folders[folder], !remembered.isEmpty else { return [] }
        let directories = Set(remembered.map { URL(fileURLWithPath: $0).deletingLastPathComponent() })
        let taken = Set(fileSelections.filter { $0.key != path }.values.joined()
            .compactMap { URL(string: $0) }.filter(\.isFileURL).map(\.path))
        let candidates = directories.flatMap(listSubtitles).filter { !taken.contains($0.standardizedFileURL.path) }
        guard !Task.isCancelled,
              let name = SubtitleMatcher.match(videos: [video.lastPathComponent], subtitles: candidates.map(\.lastPathComponent))[video.lastPathComponent]
        else { return [] }
        return candidates.first { $0.lastPathComponent == name }.map { [$0] } ?? []
    }

    /// Legacy single-selection accessor.
    public func subtitle(for video: URL, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                         listSubtitles: (URL) -> [URL] = SubtitleFolderRules.subtitles(in:)) -> URL? {
        subtitles(for: video, fileExists: fileExists, listSubtitles: listSubtitles).first
    }

    public static func subtitles(in folder: URL) -> [URL] { files(in: folder, extensions: SubtitleMatcher.subtitleExtensions) }

    public static func videos(in folder: URL) -> [URL] { files(in: folder, extensions: videoExtensions) }

    private static func files(in folder: URL, extensions: Set<String>) -> [URL] {
        // Foundation cannot interrupt a directory read: skip it when cancelled, and drop its result.
        guard !Task.isCancelled else { return [] }
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        guard !Task.isCancelled else { return [] }
        return items.filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    // MARK: Persistence

    private enum CodingKeys: String, CodingKey { case fileSelections, folders, libraryVideos, files }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fileSelections = try c.decodeIfPresent([String: [String]].self, forKey: .fileSelections) ?? [:]
        folders = try c.decodeIfPresent([String: [String]].self, forKey: .folders) ?? [:]
        libraryVideos = try c.decodeIfPresent(Set<String>.self, forKey: .libraryVideos) ?? []
        // Older builds kept one subtitle path per video in `files`: read once into fileSelections.
        for (video, subtitle) in try c.decodeIfPresent([String: String].self, forKey: .files) ?? [:] where fileSelections[video] == nil {
            fileSelections[video] = [URL(fileURLWithPath: subtitle).absoluteString]
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fileSelections, forKey: .fileSelections)
        try c.encode(folders, forKey: .folders)
        try c.encode(libraryVideos, forKey: .libraryVideos)
    }

    static let defaultsKey = "MXRSubtitleFolderRules"

    public static func load(from defaults: UserDefaults = .standard) -> SubtitleFolderRules {
        guard let data = defaults.data(forKey: defaultsKey),
              let rules = try? JSONDecoder().decode(SubtitleFolderRules.self, from: data) else { return SubtitleFolderRules() }
        return rules
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}
