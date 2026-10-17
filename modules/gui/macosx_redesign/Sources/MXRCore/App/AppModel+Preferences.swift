import Foundation

public enum ControlsAutoHideMode: String, Sendable, Codable, Hashable, CaseIterable {
    case always, fullscreen, never
}

extension AppModel {
    public var controlsAutoHideMode: ControlsAutoHideMode {
        ControlsAutoHideMode(rawValue: playerPreference("macosx-redesign-autohide")?.stringValue ?? "") ?? .fullscreen
    }

    /// Seconds before controls hide. Invalid values use the catalog default; valid values are bounded.
    public var controlsAutoHideDelay: TimeInterval {
        let delay = playerPreference("macosx-redesign-autohide-delay")?.doubleValue ?? 0.5
        return delay.isFinite ? min(max(delay, 0), 10) : 0.5
    }

    public var shouldAutoHideControls: Bool {
        switch controlsAutoHideMode {
        case .always: true
        case .fullscreen: player.isFullscreen
        case .never: false
        }
    }

    public var showsFullscreenControls: Bool {
        playerPreference("macosx-redesign-fullscreen-controls")?.boolValue ?? true
    }

    /// Applies before temporary reveal, playback, library and panel visibility rules.
    public var controlsAllowed: Bool {
        interface.isCustomizing || (!interface.isUIHidden && (!player.isFullscreen || showsFullscreenControls))
    }

    public var usesFilenameAsTitle: Bool {
        playerPreference("macosx-redesign-title-filename")?.boolValue ?? true
    }

    /// D042 (A-04): the top bar never shows a file extension (Figma 2425:13639 "The Wand S01E04" for
    /// `The_Wand_S01E04.mp4`; video 09m30.1). With "Show the file name in the title bar" on, a local
    /// file shows its decoded file name without the extension and with underscores read as spaces;
    /// off shows the media title (tags, episode name), dropping the extension when VLC's title is
    /// just the file name. Network sources keep their descriptive title. The full file name stays
    /// available as ``windowTitleFileName`` (tooltip and accessibility label).
    public var windowTitle: String {
        guard let media = player.media, let fileName = windowTitleFileName else { return player.windowTitle }
        if usesFilenameAsTitle { return Self.readableFileTitle(fileName) }
        let title = media.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title == fileName { return Self.bareFileName(fileName) }
        return title
    }

    static func bareFileName(_ fileName: String) -> String {
        let bare = (fileName as NSString).deletingPathExtension
        return bare.isEmpty ? fileName : bare
    }

    /// "The_Wand_S01E04.mp4" → "The Wand S01E04".
    static func readableFileTitle(_ fileName: String) -> String {
        let spaced = bareFileName(fileName).replacingOccurrences(of: "_", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return spaced.isEmpty ? bareFileName(fileName) : spaced
    }

    /// The decoded file name of the current local file ("The_Wand_S01E11.mp4"), nil for other sources.
    public var windowTitleFileName: String? {
        guard let media = player.media, let url = URL(string: media.mrl), url.isFileURL,
              !url.lastPathComponent.isEmpty else { return nil }
        return url.lastPathComponent
    }

    /// Startup preference only; hosts choose their initial library presentation.
    public var startsInCompactMode: Bool {
        playerPreference("macosx-redesign-compact-start")?.boolValue ?? false
    }

    public var savesRecentPlayback: Bool { playerPreference("save-recentplay")?.boolValue ?? true }
    public var remembersPlaybackPosition: Bool { playerPreference("macosx-redesign-remember-position")?.boolValue ?? true }
    public var historyExclusions: [String] {
        (playerPreference("macosx-redesign-history-exclude")?.stringValue ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    public func excludesFromHistory(_ media: MediaItem) -> Bool {
        let name = URL(string: media.mrl)?.lastPathComponent ?? media.fileName ?? media.title
        return historyExclusions.contains { name.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
    /// VLC volume scale, where 1 is 100%. User preference permits 100…300%.
    public var maximumVolume: Double { boundedPreference("macosx-redesign-max-volume", default: 200, range: 100...300) / 100 }
    public var volumeStep: Double { boundedPreference("macosx-redesign-volume-step", default: 1, range: 1...50) / 100 }
    public var startupVolume: Double { boundedPreference("macosx-redesign-startup-volume", default: 200, range: 0...(maximumVolume * 100)) / 100 }
    public var remembersVolume: Bool { playerPreference("volume-save")?.boolValue ?? true }

    func applyPlaybackPreferences(atStartup: Bool = false) {
        osd.duration = .seconds(boundedPreference("macosx-redesign-osd-duration", default: 1.5, range: 0.5...5))
        osd.isFeedbackEnabled = playerPreference("osd")?.boolValue ?? true
        if !osd.isFeedbackEnabled { osd.hide() }
        recents.isEnabled = savesRecentPlayback
        let excluded = player.media.map(excludesFromHistory) ?? false
        player.configurePreferences(maximumVolume: maximumVolume, volumeStep: volumeStep,
                                    allowsRestorePrompt: remembersPlaybackPosition && !excluded)
        if atStartup && !remembersVolume { player.setVolume(startupVolume) }
    }

    private func boundedPreference(_ name: String, default fallback: Double, range: ClosedRange<Double>) -> Double {
        let value = playerPreference(name)?.doubleValue ?? fallback
        return min(max(value.isFinite ? value : fallback, range.lowerBound), range.upperBound)
    }

    private func playerPreference(_ name: String) -> SettingValue? {
        _ = settings.revision
        return settings.backend.value(for: name)
    }
}
