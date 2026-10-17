import CoreGraphics

/// F-06: where the Settings categories intentionally differ from their Figma frames, so
/// `mxr-snapshot check` and `FigmaDeviationTests` compare everything else strictly.
/// Node ids are rows or sections of the Figma frame (`mxr-snapshot node <id>`); a section's band
/// includes the 20 pt gap after it. A `differs(node:)` area is the Figma control (toggle or
/// dropdown) of the row whose product default differs, placed where the product draws it.
extension SettingsGallery {
    private static func generalRows(interfaceLanguage: String, checkForUpdates: String, dialogsToggle: String) -> [FigmaDeviation] {
        [
            .removed(interfaceLanguage, decision: "D035", "Interface language (no localizations yet)"),
            .removed(checkForUpdates, decision: "D035", "Check for updates (no updater)"),
            .differs(node: dialogsToggle, decision: "D035", "Show confirmation and error dialogs defaults ON (VLC's behaviour)"),
        ]
    }

    static let figmaDeviations: [String: [FigmaDeviation]] = [
        "general": generalRows(interfaceLanguage: "3046:9860", checkForUpdates: "3046:9901", dialogsToggle: "3046:9900"),
        "general-advanced": generalRows(interfaceLanguage: "3046:9316", checkForUpdates: "3046:9357", dialogsToggle: "3046:9356") + [
            .removed("3046:9515", decision: "D035", "Show minor warnings (VLC's verbose level is a command-line-only option)"),
        ],
        "interface": [
            .removed("3062:11305", gap: 20, decision: "D035", "the Skin section"),
            .removed("3051:10601", decision: "D035", "Play video inside main window"),
            .removed("3051:10623", decision: "D035", "Show window decorations"),
            .removed("3062:11226", gap: 20, decision: "D035", "Show the playlist as a tree (its Playlist section)"),
            .differs(node: "3062:11130", decision: "D050", "Menu Bar and Notifications: macOS has a menu bar and notifications, no system tray"),
        ],
        "privacy": [
            .removed("3062:12496", decision: "D035", "Last.fm submission"),
            .removed("3062:12521", decision: "D035", "Last.fm username"),
            .removed("3062:12542", decision: "D035", "Last.fm password"),
            .removed("3062:12532", decision: "D035", "Last.fm submission URL"),
        ],
        "controls": [
            .removed("6540:15180", gap: 20, decision: "D035", "the Remotes section (Web remote)"),
            .removed("6536:14800", decision: "D035", "Advanced Options: the category has no advanced row"),
        ],
        "playback": [
            .removed("3062:12874", decision: "D035", "Pause on interruption"),
            .differs(node: "3062:12858", decision: "D030", "Continue where you left off shows the product default Ask, not Figma's Always"),
        ],
        "library": [
            .removed("6542:15547", decision: "D035", "one-instance option (Windows and Linux only)"),
            .removed("6542:15562", decision: "D035", "one-instance option (Windows and Linux only)"),
            .removed("6542:15575", decision: "D035", "one-instance option (Windows and Linux only)"),
        ],
        "network": [
            .removed("6543:15716", gap: 20, decision: "D035", "the proxy fields (macOS proxy is used)"),
            .removed("6571:15946", decision: "D035", "Cipher preference"),
        ],
        "performance": [
            .removed("6571:16290", decision: "D035", "Give VLC real-time priority (obsolete in VLC 4)"),
            .removed("6571:16301", decision: "D035", "Process priority"),
            .removed("6571:16312", decision: "D035", "Rescan plugins (the plugins are sealed in the app bundle)"),
            .removed("6571:16357", decision: "D035", "Encoder (obsolete in VLC 4)"),
        ],
        "recording": [
            .removed("6571:16501", gap: 20, decision: "D035", "Cast discovery and quality (the Casting section)"),
            .differs(node: "6571:16804", decision: "D030", "Play locally while streaming shows VLC's default OFF, not Figma's ON"),
            .differs(node: "6571:16770", decision: "D030", "Recordings go to ~/Movies, the Mac's video folder, not Figma's ~/Videos"),
        ],
        "extensions": [
            .differs(node: "6575:17184", decision: "D050", "Remove is disabled until an add-on is selected"),
        ],
    ]
}
