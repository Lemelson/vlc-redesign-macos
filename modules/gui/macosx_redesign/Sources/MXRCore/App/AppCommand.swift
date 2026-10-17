import Foundation

/// Where a command comes from (D026, D040). `.ui` is the window, its keys and the menu bar: behind a
/// dialog it is blocked so it cannot replace a draft. `.system` is media keys, headphones, Control
/// Center, Now Playing and the status item: transport from there keeps working behind a dialog,
/// as in every Mac player, because it never touches a draft.
public enum CommandSource: Sendable, Equatable {
    case ui, system
}

/// Commands shared by the `⋯` menu (S07), the right-click menu (S09/S10), the macOS menu bar (S11)
/// and Customize Player tiles. Perform with ``AppModel/perform(_:)``.
public enum AppCommand: String, Sendable, Hashable, CaseIterable, Identifiable {
    // ⋯ menu (Figma "menu" / "Profiles")
    case openFiles, openFolder, openNetworkStream, openDisc, openCaptureDevice, convert, stream, openFromClipboard
    case keyboardShortcuts, customizePlayer, manageProfiles, settings, about
    // Playback (right-click menu)
    case playPause, stop, previous, next, record, hideUI
    case jumpBackward10, jumpForward10, jumpBackward15, jumpForward15
    case faster, slower, normalRate, nextFrame, snapshot, toggleABLoop
    case toggleFullscreen, toggleMute, volumeUp, volumeDown
    case toggleRepeat, toggleShuffle
    // Panels and library
    case toggleQueue, toggleLibrary, showFullLibrary, toggleSettingsSidebar, showSubtitleTracks, showAudioTracks
    case addBookmark, addSubtitleFile, favoriteCurrent
    case quit

    public var id: String { rawValue }

    /// Playback transport that a ``CommandSource/system`` source may run behind a dialog.
    public var isTransport: Bool {
        switch self {
        case .playPause, .stop, .previous, .next, .jumpBackward10, .jumpForward10, .jumpBackward15, .jumpForward15,
             .toggleMute, .volumeUp, .volumeDown: true
        default: false
        }
    }

    /// Menu label as in the design.
    public var title: String {
        switch self {
        case .openFiles: "Open File(s)"
        case .openFolder: "Open Folder"
        case .openNetworkStream: "Open Network Stream"
        case .openDisc: "Open Disc"
        case .openCaptureDevice: "Open Capture Device"
        case .convert: "Convert"
        case .stream: "Stream"
        case .openFromClipboard: "Open from Clipboard"
        case .keyboardShortcuts: "Keyboard Shortcuts"
        case .customizePlayer: "Customize Player"
        case .manageProfiles: "Manage Profiles"
        case .settings: "Settings"
        case .about: "About VLC"
        case .playPause: "Play"
        case .stop: "Stop"
        case .previous: "Previous Item"
        case .next: "Next Item"
        case .record: "Record"
        case .hideUI: "Hide UI"
        case .jumpBackward10: "Backward 10s"
        case .jumpForward10: "Forward 10s"
        case .jumpBackward15: "Backward 15s"
        case .jumpForward15: "Forward 15s"
        case .faster: "Faster"
        case .slower: "Slower"
        case .normalRate: "Normal Speed"
        case .nextFrame: "Next Frame"
        case .snapshot: "Snapshot"
        case .toggleABLoop: "A→B Loop"
        case .toggleFullscreen: "Fullscreen"
        case .toggleMute: "Mute"
        case .volumeUp: "Increase Volume"
        case .volumeDown: "Decrease Volume"
        case .toggleRepeat: "Repeat"
        case .toggleShuffle: "Shuffle"
        case .toggleQueue: "Queue"
        case .toggleLibrary: "Library"
        case .showFullLibrary: "Go Home"
        case .toggleSettingsSidebar: "Right Sidebar"
        case .showSubtitleTracks: "Subtitles"
        case .showAudioTracks: "Audio Tracks"
        case .addBookmark: "Bookmark"
        case .addSubtitleFile: "Add Subtitle File…"
        case .favoriteCurrent: "Favorite"
        case .quit: "Quit VLC"
        }
    }

    /// The hotkey action whose binding is shown next to the item, if any: a VLC action ("play-pause")
    /// or an app action (``ShortcutAction/appActions``, "app-open-files"). Show it with
    /// ``AppModel/shortcutText(for:)``.
    public var shortcutActionID: String? {
        switch self {
        case .openFiles: "app-open-files"
        case .openFolder: "app-open-folder"
        case .openNetworkStream: "app-open-network"
        case .openDisc: "app-open-disc"
        case .openCaptureDevice: "app-open-capture"
        case .convert: "app-convert"
        case .stream: "app-stream"
        case .openFromClipboard: "app-open-clipboard"
        case .keyboardShortcuts: "app-keyboard-shortcuts"
        case .customizePlayer: "app-customize-player"
        case .settings: "app-settings"
        case .about: "app-about"
        case .hideUI: "app-hide-ui"
        case .toggleQueue: "app-toggle-queue"
        case .toggleLibrary: "app-toggle-library"
        case .toggleSettingsSidebar: "app-settings-sidebar"
        case .addBookmark: "app-add-bookmark"
        case .playPause: "play-pause"
        case .stop: "stop"
        case .previous: "prev"
        case .next: "next"
        case .record: "record"
        case .jumpBackward10: "jump-short"
        case .jumpForward10: "jump+short"
        case .faster: "faster"
        case .slower: "slower"
        case .normalRate: "rate-normal"
        case .nextFrame: "frame-next"
        case .snapshot: "snapshot"
        case .toggleFullscreen: "toggle-fullscreen"
        case .toggleMute: "vol-mute"
        case .volumeUp: "vol-up"
        case .volumeDown: "vol-down"
        case .toggleRepeat: "loop"
        case .toggleShuffle: "random"
        case .quit: "quit"
        default: nil
        }
    }

    /// The `⋯` menu items in Figma order; `nil` marks the divider. "Open Recent" and "Profile" are
    /// submenus built from ``RecentStore`` and ``ProfileStore``.
    public static let appMenu: [AppCommand?] = [
        .openFiles, .openFolder, .openNetworkStream, .openDisc, .openCaptureDevice, .convert, nil,
        .keyboardShortcuts, .customizePlayer, .settings, .about,
    ]

    /// The first group of the right-click menu (Figma "right-click menu"), before its submenus.
    public static let contextMenu: [AppCommand] = [.playPause, .stop, .previous, .next, .record, .hideUI]
}
