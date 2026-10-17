import AppKit
import Foundation

/// Modifier keys of a binding, in VLC's vocabulary (`KEY_MODIFIER_*`).
public struct KeyModifiers: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let shift = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)
}

/// A key combination stored as VLC stores hotkeys: `"Command+Shift+r"`, `"Space"`, `"f"`, `"Esc"`.
///
/// `key` is VLC's key name (`vlc_keycode2str` without modifiers): a lower-case character
/// or a named key ("Space", "Left", "Esc", "Enter", "F1", "Page Up", "Media Play Pause").
public struct KeyBinding: Hashable, Sendable, Codable, CustomStringConvertible {
    public var key: String
    public var modifiers: KeyModifiers

    public init(key: String, modifiers: KeyModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Parses VLC's string form (`"Ctrl+Alt+Left"`, `"Command+f"`). Returns nil for an empty string.
    public init?(vlcString: String) {
        let trimmed = vlcString.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // "+" itself is a key ("Command++" or "+").
        var parts = trimmed.components(separatedBy: "+")
        var key = parts.removeLast()
        if key.isEmpty, !parts.isEmpty { parts.removeLast(); key = "+" }
        var modifiers: KeyModifiers = []
        for part in parts where !part.isEmpty {
            switch part.lowercased() {
            case "ctrl": modifiers.insert(.control)
            case "alt": modifiers.insert(.option)
            case "shift": modifiers.insert(.shift)
            case "command", "meta": modifiers.insert(.command)
            default: return nil
            }
        }
        self.init(key: key, modifiers: modifiers)
    }

    /// VLC's string form, modifiers in VLC's order (Ctrl, Alt, Shift, Meta, Command).
    public var vlcString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.option) { parts.append("Alt") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Command") }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    /// macOS display form, used by every menu, the shortcuts dialog and onboarding (D026):
    /// "⌃⌥⇧⌘F", "⌘,", "Space", "←", "esc".
    public var displayString: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + Self.displayName(forKey: key)
    }

    /// The key's display name ("F" for "f", "←" for "Left", "esc" for "Esc").
    public static func displayName(forKey key: String) -> String {
        switch key {
        case "Left": "←"
        case "Right": "→"
        case "Up": "↑"
        case "Down": "↓"
        case "Esc": "esc"
        case "Enter": "↩"
        case "Tab": "⇥"
        case "Backspace": "⌫"
        case "Delete": "⌦"
        default: key.count == 1 ? key.uppercased() : key
        }
    }

    public var description: String { vlcString }

    /// Converts a key-down event, using the characters ignoring modifiers (VLC semantics).
    /// Returns nil for pure modifier presses.
    @MainActor
    public init?(event: NSEvent) {
        guard event.type == .keyDown || event.type == .keyUp else { return nil }
        var modifiers: KeyModifiers = []
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if let named = Self.namedKeys[event.keyCode] {
            self.init(key: named, modifiers: modifiers)
            return
        }
        guard let characters = event.charactersIgnoringModifiers?.lowercased(), let first = characters.first else { return nil }
        if first == " " {
            self.init(key: "Space", modifiers: modifiers)
            return
        }
        // Function keys arrive as private-use characters.
        if let scalar = first.unicodeScalars.first, (0xF704...0xF70F).contains(scalar.value) {
            self.init(key: "F\(scalar.value - 0xF704 + 1)", modifiers: modifiers)
            return
        }
        self.init(key: String(first), modifiers: modifiers)
    }

    /// Virtual key codes of keys with VLC names.
    private static let namedKeys: [UInt16: String] = [
        0x31: "Space", 0x24: "Enter", 0x4C: "Enter", 0x35: "Esc", 0x30: "Tab", 0x33: "Backspace", 0x75: "Delete",
        0x7B: "Left", 0x7C: "Right", 0x7E: "Up", 0x7D: "Down", 0x73: "Home", 0x77: "End", 0x74: "Page Up", 0x79: "Page Down",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
    ]
}

/// Groups of the Keyboard Shortcuts dialog (S64), in display order.
public enum ShortcutGroup: String, Sendable, Codable, Hashable, CaseIterable {
    case basic, playback, audio, video, subtitles, navigation, bookmarks
    /// App-level actions (``ShortcutAction/appActions``): panels, Hide UI, the `⋯` menu items.
    case interface
    case other

    public var title: String {
        switch self {
        case .basic: "Basic"
        case .playback: "Playback"
        case .audio: "Audio"
        case .video: "Video"
        case .subtitles: "Subtitles"
        case .navigation: "Navigation"
        case .bookmarks: "Bookmarks"
        case .interface: "Interface"
        case .other: "Other"
        }
    }
}

/// One hotkey action (`vlc_actions`), with its bindings (`key-<id>` / `global-key-<id>` options).
public struct ShortcutAction: Identifiable, Hashable, Sendable {
    /// VLC action name without the `key-` prefix: "play-pause", "toggle-fullscreen".
    public var id: String
    /// Human title ("Play / pause").
    public var title: String
    public var group: ShortcutGroup
    public var hotkeys: [KeyBinding]
    public var globalHotkeys: [KeyBinding]

    public init(id: String, title: String, group: ShortcutGroup, hotkeys: [KeyBinding] = [], globalHotkeys: [KeyBinding] = []) {
        self.id = id
        self.title = title
        self.group = group
        self.hotkeys = hotkeys
        self.globalHotkeys = globalHotkeys
    }
}

extension ShortcutAction {
    /// App-level actions (ids with the `app-` prefix, run by the UI through ``AppModel``) with their
    /// macOS default bindings (D026): ⌘O open, ⇧⌘O folder, ⌘N network, ⌘D disc, ⌘R capture,
    /// ⇧⌘S convert, ⌘, Settings, ⌘B bookmark, ⌘\ Hide UI, ⌘L library. They follow VLC for Mac's
    /// reserved interface keys (`src/libvlc-module.c`, the `__APPLE__` block) and never reuse a VLC
    /// engine default or a standard menu key (⌘C/⌘V copy and paste, ⌘W, ⌘M, ⌘H, ⌘Q). Q for the
    /// queue is the onboarding keycap and has no engine binding on macOS. About has no shortcut
    /// on the Mac. Backends list these after the engine's actions; the VLC backend stores their
    /// bindings in the app options `macosx-redesign-key-<id>` (defaults in `module/MXRAppOptions.inc`).
    public static let appActions: [ShortcutAction] = {
        func key(_ text: String) -> [KeyBinding] { KeyBinding(vlcString: text).map { [$0] } ?? [] }
        return [
            ShortcutAction(id: "app-hide-ui", title: "Hide UI", group: .interface, hotkeys: key("Command+\\")),
            ShortcutAction(id: "app-toggle-queue", title: "Show / Hide Queue", group: .interface, hotkeys: key("q")),
            ShortcutAction(id: "app-toggle-library", title: "Show / Hide File Browser", group: .interface, hotkeys: key("Command+l")),
            ShortcutAction(id: "app-settings-sidebar", title: "Show / Hide Settings Sidebar", group: .interface),
            ShortcutAction(id: "app-open-files", title: "Open File(s)", group: .interface, hotkeys: key("Command+o")),
            ShortcutAction(id: "app-open-folder", title: "Open Folder", group: .interface, hotkeys: key("Command+Shift+o")),
            ShortcutAction(id: "app-open-network", title: "Open Network Stream", group: .interface, hotkeys: key("Command+n")),
            ShortcutAction(id: "app-open-disc", title: "Open Disc", group: .interface, hotkeys: key("Command+d")),
            ShortcutAction(id: "app-open-capture", title: "Open Capture Device", group: .interface, hotkeys: key("Command+r")),
            ShortcutAction(id: "app-open-clipboard", title: "Open from Clipboard", group: .interface, hotkeys: key("Command+Alt+v")),
            ShortcutAction(id: "app-convert", title: "Convert", group: .interface, hotkeys: key("Command+Shift+s")),
            ShortcutAction(id: "app-stream", title: "Stream", group: .interface),
            ShortcutAction(id: "app-keyboard-shortcuts", title: "Keyboard Shortcuts", group: .interface),
            ShortcutAction(id: "app-customize-player", title: "Customize Player", group: .interface),
            ShortcutAction(id: "app-settings", title: "Settings", group: .interface, hotkeys: key("Command+,")),
            ShortcutAction(id: "app-about", title: "About VLC", group: .interface),
            ShortcutAction(id: "app-add-bookmark", title: "Add bookmark", group: .bookmarks, hotkeys: key("Command+b")),
        ]
    }()
}

extension ShortcutAction {
    /// The Windows-style Control defaults of the first builds, by app action id (M2, CMP-14). A stored
    /// binding equal to one of these was never chosen by the user on purpose; the backend drops it
    /// once so the Mac default (`appActions`) applies.
    public static let legacyAppDefaults: [String: String] = [
        "app-hide-ui": "Ctrl+\\", "app-toggle-library": "l", "app-open-files": "Ctrl+o", "app-open-folder": "Ctrl+f",
        "app-open-network": "Ctrl+n", "app-open-disc": "Ctrl+d", "app-open-capture": "Ctrl+c", "app-open-clipboard": "Ctrl+v",
        "app-convert": "Ctrl+r", "app-stream": "Ctrl+s", "app-settings": "Ctrl+p", "app-about": "Shift+F1", "app-add-bookmark": "Ctrl+b",
    ]

    /// True when `stored` (tab-separated VLC key strings) is exactly the old Control default of `id`.
    public static func isLegacyAppDefault(_ stored: String, forID id: String) -> Bool {
        guard let legacy = legacyAppDefaults[id] else { return false }
        let normalize: (String) -> [KeyBinding] = { $0.split(separator: "\t").compactMap { KeyBinding(vlcString: String($0)) } }
        return normalize(stored) == normalize(legacy)
    }
}

/// Which keys the macOS menu bar may run as key equivalents (SD-09, D026).
public enum MenuKeyEquivalentPolicy {
    /// - Parameters:
    ///   - isRecording: the Keyboard Shortcuts recorder is listening; it gets every key and only
    ///     ⌘Q still quits.
    ///   - hasModal: a dialog, onboarding or another sheet is open. Only standard Edit equivalents,
    ///     Quit and Close reach the menu. ⌘, is not let through: ``AppModel/canPerform(_:from:)``
    ///     refuses Settings behind a dialog, so it would only reach a disabled item.
    ///   - isEditing: a text field or focused control has the keyboard; bare keys stay there.
    public static func allows(_ binding: KeyBinding, isRecording: Bool, hasModal: Bool, isEditing: Bool) -> Bool {
        if isRecording { return binding == KeyBinding(key: "q", modifiers: .command) }
        if hasModal {
            let edit = ["c", "v", "x", "a", "z"].contains(binding.key)
            if binding.modifiers == .command { return edit || ["q", "w"].contains(binding.key) }
            return binding.modifiers == [.command, .shift] && ["z", "v"].contains(binding.key)
        }
        if binding.modifiers.contains(.command) { return true }
        return !hasModal && !isEditing
    }
}
