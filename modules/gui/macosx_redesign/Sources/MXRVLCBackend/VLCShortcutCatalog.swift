import MXRCore

/// Names and groups of VLC's hotkey actions in the Keyboard Shortcuts dialog (S64, SD-01).
///
/// The bridge reports each action's own text (the `key-<id>` option text, translated). The
/// Figma wording overrides it where the design names the action, and fills the actions VLC
/// leaves unnamed. The raw id ("vol-up") is never shown.
enum VLCShortcutCatalog {
    struct Entry {
        let title: String
        let group: ShortcutGroup
        /// Position in the design's list (2437:14832); actions the catalog does not know follow.
        let rank: Int
    }

    /// Sort key that lists actions in the design's order instead of the engine's (S64).
    static func rank(for id: String) -> Int { entries[id]?.rank ?? Int.max }

    static func title(for id: String, engineName: String?) -> String {
        if let entry = entries[id] { return entry.title }
        if let engineName, !engineName.isEmpty, engineName != id { return engineName }
        return humanized(id)
    }

    static func group(for id: String) -> ShortcutGroup {
        if let entry = entries[id] { return entry.group }
        if id.hasPrefix("set-bookmark") || id.hasPrefix("play-bookmark") { return .bookmarks }
        if id.hasPrefix("sub") { return .subtitles }
        if id.hasPrefix("crop") || id.hasPrefix("uncrop") || id.hasPrefix("zoom") || id.hasPrefix("viewpoint") { return .video }
        if id.hasPrefix("nav-") { return .navigation }
        if id.hasPrefix("jump") || id.hasPrefix("rate") { return .playback }
        return .other
    }

    /// "projection-toggle" → "Projection toggle": last resort for an action VLC leaves unnamed.
    static func humanized(_ id: String) -> String {
        let words = id.replacingOccurrences(of: "+", with: " forward ").split(whereSeparator: { $0 == "-" || $0 == " " }).joined(separator: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    private static let entries: [String: Entry] = {
        var table: [String: Entry] = [:]
        func add(_ group: ShortcutGroup, _ items: [(String, String)]) {
            for (id, title) in items { table[id] = Entry(title: title, group: group, rank: table.count) }
        }
        // Figma "Keyboard Shortcuts" (2437:14832): Basic, then Playback.
        add(.basic, [
            ("toggle-fullscreen", "Toggle fullscreen"),
            ("leave-fullscreen", "Exit fullscreen / close dialog"),
            ("position", "Show playback position and time"),
            ("intf-show", "Show interface controls in fullscreen"),
        ])
        add(.playback, [
            ("play-pause", "Play / pause"),
            ("stop", "Stop playback"),
            ("next", "Next track"),
            ("prev", "Previous track"),
            ("program-sid-next", "Next program / Service ID"),
            ("program-sid-prev", "Previous program / Service ID"),
            ("play", "Play"),
            ("pause", "Pause"),
            ("jump-extrashort", "Seek backward (very short)"),
            ("jump+extrashort", "Seek forward (very short)"),
            ("jump-short", "Seek backward"),
            ("jump+short", "Seek forward"),
            ("jump-medium", "Seek backward (medium)"),
            ("jump+medium", "Seek forward (medium)"),
            ("jump-long", "Seek backward (long)"),
            ("jump+long", "Seek forward (long)"),
            ("frame-previous", "Previous frame"),
            ("frame-next", "Next frame"),
            ("faster", "Faster"),
            ("slower", "Slower"),
            ("rate-normal", "Normal rate"),
            ("rate-faster-fine", "Faster (fine)"),
            ("rate-slower-fine", "Slower (fine)"),
            ("record", "Record"),
            ("loop", "Cycle repeat mode"),
            ("random", "Shuffle"),
            ("clear-playlist", "Clear the queue"),
        ])
        add(.audio, [
            ("vol-up", "Increase volume"),
            ("vol-down", "Decrease volume"),
            ("vol-mute", "Mute"),
            ("audio-track", "Cycle audio track"),
            ("audiodelay-up", "Audio delay up"),
            ("audiodelay-down", "Audio delay down"),
            ("audiodevice-cycle", "Cycle audio output device"),
        ])
        add(.video, [
            ("crop", "Cycle crop"),
            ("aspect-ratio", "Cycle aspect ratio"),
            ("snapshot", "Take a snapshot"),
            ("deinterlace", "Toggle deinterlacing"),
            ("deinterlace-mode", "Cycle deinterlace mode"),
            ("toggle-autoscale", "Toggle scale to window"),
            ("incr-scalefactor", "Increase scale factor"),
            ("decr-scalefactor", "Decrease scale factor"),
            ("zoom", "Zoom"),
            ("unzoom", "Zoom out"),
            ("wallpaper", "Toggle wallpaper mode"),
            ("projection-toggle", "Toggle 360° projection"),
        ])
        add(.subtitles, [
            ("subtitle-track", "Cycle subtitle track"),
            ("subtitle-revtrack", "Cycle subtitle track backwards"),
            ("subtitle-toggle", "Toggle subtitles"),
            ("subtitle-control-secondary", "Toggle secondary subtitle control"),
            ("subdelay-up", "Subtitle delay up"),
            ("subdelay-down", "Subtitle delay down"),
        ])
        add(.navigation, [
            ("title-next", "Next title"),
            ("title-prev", "Previous title"),
            ("chapter-next", "Next chapter"),
            ("chapter-prev", "Previous chapter"),
            ("disc-menu", "Go to the disc menu"),
        ])
        add(.other, [
            ("quit", "Quit"),
        ])
        return table
    }()
}
