import Foundation

/// Matches subtitle files to videos for the Add Subtitles dialog (S25): by season/episode code
/// ("S01E04", "1x04"), else by normalized base name. Pure logic.
public enum SubtitleMatcher {
    /// Subtitle file extensions VLC loads.
    public static let subtitleExtensions: Set<String> = ["srt", "ass", "ssa", "sub", "idx", "vtt", "smi", "txt", "usf", "jss", "ttml", "dfxp"]

    /// Returns, for each video name, the best subtitle name (or nil). Each subtitle is used at most once.
    public static func match(videos: [String], subtitles: [String]) -> [String: String] {
        do {
            var remaining = subtitles
            var result: [String: String] = [:]
            // Pass 1: episode codes.
            for video in videos {
                try Task.checkCancellation()
                guard let code = episodeCode(in: video) else { continue }
                if let index = try remaining.firstIndex(where: {
                    try Task.checkCancellation()
                    return episodeCode(in: $0) == code
                }) { result[video] = remaining.remove(at: index) }
            }
            // Pass 2: normalized base name containment.
            for video in videos where result[video] == nil {
                try Task.checkCancellation()
                let key = normalized(baseName(video))
                guard !key.isEmpty else { continue }
                if let index = try remaining.firstIndex(where: { candidate in
                    try Task.checkCancellation()
                    let other = normalized(baseName(candidate))
                    return other == key || other.hasPrefix(key) || key.hasPrefix(other)
                }) { result[video] = remaining.remove(at: index) }
            }
            try Task.checkCancellation()
            return result
        } catch { return [:] }
    }

    /// "S01E04" for "The_Wand_S01E04.mp4", "1x04" forms are normalized to "S01E04".
    public static func episodeCode(in name: String) -> String? {
        let text = name.uppercased()
        if let range = text.range(of: #"S(\d{1,2})[ ._-]?E(\d{1,3})"#, options: .regularExpression) {
            return normalize(code: String(text[range]), separator: "E")
        }
        if let range = text.range(of: #"(?<![0-9])(\d{1,2})X(\d{2,3})(?![0-9])"#, options: .regularExpression) {
            return normalize(code: String(text[range]), separator: "X")
        }
        return nil
    }

    private static func normalize(code: String, separator: Character) -> String? {
        let digits = code.split(whereSeparator: { !$0.isNumber })
        guard digits.count == 2, let season = Int(digits[0]), let episode = Int(digits[1]) else { return nil }
        return "S" + String(format: "%02d", season) + "E" + String(format: "%02d", episode)
    }

    /// File name without extension and without a trailing language tag ("_English", ".en").
    public static func baseName(_ name: String) -> String {
        var base = (name as NSString).deletingPathExtension
        let lowered = base.lowercased()
        for tag in languageTags {
            for separator in ["_", ".", " ", "-"] where lowered.hasSuffix(separator + tag) {
                base = String(base.dropLast(tag.count + 1))
                return base
            }
        }
        return base
    }

    /// Language guessed from a file name suffix ("The_Wand_S01E01_English.srt" → "English").
    public static func language(in name: String) -> String? {
        let base = (name as NSString).deletingPathExtension.lowercased()
        for (tag, language) in languageNames where base.hasSuffix("_" + tag) || base.hasSuffix("." + tag) || base.hasSuffix(" " + tag) || base.hasSuffix("-" + tag) {
            return language
        }
        return nil
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static let languageNames: [(String, String)] = [
        ("english", "English"), ("en", "English"), ("eng", "English"), ("spanish", "Spanish"), ("es", "Spanish"),
        ("japanese", "Japanese"), ("ja", "Japanese"), ("jpn", "Japanese"), ("german", "German"), ("de", "German"),
        ("dutch", "Dutch"), ("nl", "Dutch"), ("french", "French"), ("fr", "French"), ("italian", "Italian"), ("it", "Italian"),
        ("portuguese", "Portuguese"), ("pt", "Portuguese"), ("russian", "Russian"), ("ru", "Russian"),
    ]

    private static var languageTags: [String] { languageNames.map(\.0) }
}
