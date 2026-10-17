import Foundation

// MARK: - Dialogs (vlc_dialog)

/// Severity of a question dialog (`vlc_dialog_question_type`).
public enum DialogSeverity: String, Sendable, Hashable {
    case normal, warning, critical
}

/// A dialog the engine asks the UI to show (`vlc_dialog_cbs`).
public struct DialogRequest: Identifiable, Hashable, Sendable {
    /// What the dialog asks.
    public enum Kind: Hashable, Sendable {
        /// Credentials for a network share or stream.
        case login(defaultUsername: String, canStore: Bool)
        /// A question with up to two actions and an optional cancel button.
        case question(severity: DialogSeverity, action1: String?, action2: String?, cancel: String?)
        /// Progress, determinate or not, optionally cancellable.
        case progress(isIndeterminate: Bool, value: Double, cancel: String?)
        /// An error message (no answer expected).
        case error
    }

    /// Unique per request (the bridge maps it to its `vlc_dialog_id`).
    public var id: UInt64
    public var title: String
    public var text: String
    public var kind: Kind

    public init(id: UInt64, title: String, text: String, kind: Kind) {
        self.id = id
        self.title = title
        self.text = text
        self.kind = kind
    }
}

// MARK: - Extensions

/// A Lua extension (`extension_t`), listed in Settings ▸ Extensions.
public struct ExtensionInfo: Identifiable, Hashable, Sendable {
    /// Script name.
    public var id: String
    public var title: String
    public var summary: String?
    public var author: String?
    public var version: String?
    public var isActivated: Bool
    public var hasMenu: Bool

    public init(id: String, title: String, summary: String? = nil, author: String? = nil, version: String? = nil, isActivated: Bool = false, hasMenu: Bool = false) {
        self.id = id
        self.title = title
        self.summary = summary
        self.author = author
        self.version = version
        self.isActivated = isActivated
        self.hasMenu = hasMenu
    }
}

/// An entry of an extension's menu (`extension_GetMenu`).
public struct ExtensionMenuItem: Identifiable, Hashable, Sendable {
    public var id: UInt16
    public var title: String

    public init(id: UInt16, title: String) {
        self.id = id
        self.title = title
    }
}

/// An add-on from the catalog (`addon_entry_t`), for "Find more extensions".
public struct AddonInfo: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var summary: String
    public var author: String?
    public var version: String?
    public var isInstalled: Bool

    public init(id: String, name: String, summary: String, author: String? = nil, version: String? = nil, isInstalled: Bool = false) {
        self.id = id
        self.name = name
        self.summary = summary
        self.author = author
        self.version = version
        self.isInstalled = isInstalled
    }
}

/// Extension change notifications.
public enum ExtensionsEvent: Sendable {
    case listChanged
    case activationChanged(String)
}

// MARK: - OSD

/// What the on-screen message shows (S13): the action result and, in the redesign, the key that was pressed.
public struct OSDMessage: Identifiable, Hashable, Sendable {
    public var id: UInt64
    /// First line, e.g. "Crop: 2.35:1". Nil when only the key is shown.
    public var text: String?
    /// Second line key, e.g. "C" for "Pressed C". Nil when no key triggered it.
    public var pressedKey: String?

    public init(id: UInt64, text: String?, pressedKey: String?) {
        self.id = id
        self.text = text
        self.pressedKey = pressedKey
    }

    /// "Pressed C", or nil.
    public var pressedKeyText: String? { pressedKey.map { "Pressed \($0)" } }
}

// MARK: - Media sources (vlc_media_source)

/// Kinds of media sources (`enum services_discovery_category_e`).
public enum MediaSourceCategory: String, Sendable, Hashable, CaseIterable {
    case devices, localNetwork, internet, myComputer
}

/// A discovered source ("UPnP", "SMB", "SAP").
public struct MediaSourceInfo: Identifiable, Hashable, Sendable {
    /// Services discovery module name.
    public var id: String
    public var title: String
    public var category: MediaSourceCategory

    public init(id: String, title: String, category: MediaSourceCategory) {
        self.id = id
        self.title = title
        self.category = category
    }
}

/// A node of a media-source tree: a container (share, folder) or a playable item.
public struct MediaSourceNode: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var mrl: String
    public var isContainer: Bool

    public init(id: String, title: String, mrl: String, isContainer: Bool) {
        self.id = id
        self.title = title
        self.mrl = mrl
        self.isContainer = isContainer
    }
}

// MARK: - Capabilities

/// How Picture in Picture can be provided (ARCHITECTURE §3.5).
public enum PictureInPictureSupport: String, Sendable, Hashable {
    case unsupported
    /// AVKit sample-buffer PiP.
    case sampleBuffer
}

/// What a backend can do, so screens hide what is not available (ARCHITECTURE §2.2).
public struct BackendCapabilities: Hashable, Sendable {
    public var hasMediaLibrary: Bool
    public var hasExtensions: Bool
    public var hasAddonsCatalog: Bool
    public var hasThumbnails: Bool
    public var hasRecording: Bool
    /// Chromecast and other renderers ("Render: Local").
    public var hasRenderers: Bool
    public var pictureInPicture: PictureInPictureSupport
    /// Reverse playback (D014: hidden until researched).
    public var supportsReversePlayback: Bool
    /// Waveform seek bar for music (D014).
    public var supportsWaveform: Bool
    /// Subtitle cue blocks on the seek bar (S21, D014).
    public var supportsSubtitleTimeline: Bool
    /// OpenSubtitles search (S27, D014).
    public var supportsOpenSubtitles: Bool
    public var supportsGlobalHotkeys: Bool
    /// A real bounded left/right output-device test independent of the main playback queue.
    public var hasStereoTest: Bool

    public init(hasMediaLibrary: Bool = true, hasExtensions: Bool = true, hasAddonsCatalog: Bool = true, hasThumbnails: Bool = true,
                hasRecording: Bool = true, hasRenderers: Bool = false, pictureInPicture: PictureInPictureSupport = .sampleBuffer,
                supportsReversePlayback: Bool = false, supportsWaveform: Bool = false, supportsSubtitleTimeline: Bool = false,
                supportsOpenSubtitles: Bool = false, supportsGlobalHotkeys: Bool = false, hasStereoTest: Bool = false) {
        self.hasMediaLibrary = hasMediaLibrary
        self.hasExtensions = hasExtensions
        self.hasAddonsCatalog = hasAddonsCatalog
        self.hasThumbnails = hasThumbnails
        self.hasRecording = hasRecording
        self.hasRenderers = hasRenderers
        self.pictureInPicture = pictureInPicture
        self.supportsReversePlayback = supportsReversePlayback
        self.supportsWaveform = supportsWaveform
        self.supportsSubtitleTimeline = supportsSubtitleTimeline
        self.supportsOpenSubtitles = supportsOpenSubtitles
        self.supportsGlobalHotkeys = supportsGlobalHotkeys
        self.hasStereoTest = hasStereoTest
    }

    /// Everything on (the mock backend).
    public static let all = BackendCapabilities(hasRenderers: true, supportsReversePlayback: true, supportsWaveform: true,
                                                supportsSubtitleTimeline: true, supportsOpenSubtitles: true, supportsGlobalHotkeys: true, hasStereoTest: true)
}
