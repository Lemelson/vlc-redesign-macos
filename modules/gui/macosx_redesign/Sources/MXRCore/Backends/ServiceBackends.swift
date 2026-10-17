import CoreGraphics
import Foundation

/// VLC configuration (`config_Get*/Put*`, `module_config_get`). Values are addressed by option name;
/// app-level options use the `macosx-redesign-` prefix and are declared by our module.
@MainActor
public protocol SettingsBackend: AnyObject {
    /// Engine description of an option, nil when the option does not exist.
    func option(named name: String) -> SettingOption?
    /// Current value, nil when the option does not exist.
    func value(for name: String) -> SettingValue?
    /// Writes a value and applies it according to `apply` (live to vouts/aout when asked).
    func setValue(_ value: SettingValue, for name: String, apply: SettingsApply)
    /// Restores one option's default.
    func resetValue(for name: String)
    /// Restores every default (`config_ResetAll`).
    func resetAll()
    /// Persists the configuration (`config_SaveConfigFile`), debounced by the implementation.
    func save()
    /// Choices computed at runtime (audio devices, module lists); defaults to the static ones.
    func dynamicChoices(for name: String) async -> [SettingChoice]
    /// Available hardware, enumerated outside the UI. Default implementations expose no devices.
    func availableDevices(for kind: MediaDeviceKind) async -> [MediaDevice]
    /// Every option name the engine knows (for the drift check and "All modules").
    var allOptionNames: [String] { get }

    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (SettingsEvent) -> Void)
}

extension SettingsBackend {
    public func availableDevices(for kind: MediaDeviceKind) async -> [MediaDevice] { [] }
}

/// Hotkeys (`vlc_actions`, `key-*` options). Dispatch is live: a triggered action goes through
/// `key-action` on the instance, so the engine runs it and shows its OSD (ARCHITECTURE §5.3).
@MainActor
public protocol ShortcutsBackend: AnyObject {
    /// Every action with its current bindings.
    var actions: [ShortcutAction] { get }
    /// Runs an action as if its hotkey was pressed.
    func trigger(actionID: String)
    /// Replaces the bindings of an action (written to `key-<id>` / `global-key-<id>`).
    func setBindings(_ hotkeys: [KeyBinding], global: [KeyBinding], forAction actionID: String)
    /// Restores every default binding.
    func resetAllBindings()
    /// Persists bindings.
    func save()
    /// Called when actions or bindings change outside ``ShortcutsModel`` (another window, config reload).
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor () -> Void)
}

/// Transitional default (never notifies) so backends written before the listener existed compile.
extension ShortcutsBackend {
    public func addListener(_ owner: AnyObject, handler: @escaping @MainActor () -> Void) {}
}

/// The UI side of engine dialogs. Core implements it (``DialogModel``); the backend calls it.
@MainActor
public protocol DialogPresenter: AnyObject {
    func present(_ request: DialogRequest)
    func updateProgress(id: UInt64, value: Double, text: String?)
    /// The engine cancelled the dialog (`pf_cancel`).
    func cancel(id: UInt64)
}

/// Answers to engine dialogs (`vlc_dialog_id_post_*`).
@MainActor
public protocol DialogBackend: AnyObject {
    /// Set once by `AppModel`; the backend forwards engine requests to it.
    var presenter: (any DialogPresenter)? { get set }
    func postLogin(id: UInt64, username: String, password: String, store: Bool)
    /// `action` is 1 or 2 (the question's buttons).
    func postAction(id: UInt64, action: Int)
    func dismiss(id: UInt64)
}

/// Lua extensions and the add-ons catalog.
@MainActor
public protocol ExtensionsBackend: AnyObject {
    var extensions: [ExtensionInfo] { get }
    func activate(id: String)
    func deactivate(id: String)
    func menu(forExtension id: String) -> [ExtensionMenuItem]
    func triggerMenu(extensionID: String, itemID: UInt16)
    /// Asks for the current catalog and extension menus (`extension_GetMenu`); listeners hear the
    /// reply. Default: nothing (a backend whose snapshot is always current).
    func refresh()
    /// Searches the add-ons catalog.
    func searchAddons(_ text: String) async throws -> [AddonInfo]
    func installAddon(id: String) async throws
    func removeAddon(id: String) async throws
    /// Installs a local extension script.
    func installExtension(fileURL: URL) async throws

    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (ExtensionsEvent) -> Void)
}

public extension ExtensionsBackend {
    func refresh() {}
}

/// Images and media analysis: library thumbnails and cover art, seek previews (S03), music waveforms.
@MainActor
public protocol ThumbnailBackend: AnyObject {
    /// A thumbnail (video) or cover art (audio) for a library item, generating it if needed.
    func artwork(for media: MediaItem, maxPixelSize: CGSize) async -> CGImage?
    /// The artwork if already in memory; never generates. Default nil.
    func cachedArtwork(for media: MediaItem, maxPixelSize: CGSize) -> CGImage?
    /// A frame of `media` near `time` (seek preview). Cancelling the task cancels the request.
    func seekPreview(for media: MediaItem, at time: MediaTime, maxPixelSize: CGSize) async -> CGImage?
    /// `bins` peak amplitudes 0...1 for the waveform seek bar, nil when unsupported.
    func waveform(for media: MediaItem, bins: Int) async -> [Float]?
}

extension ThumbnailBackend {
    public func cachedArtwork(for media: MediaItem, maxPixelSize: CGSize) -> CGImage? { nil }
}

/// A message for the redesign OSD (S13, D027).
public enum OSDBackendMessage: Sendable, Hashable {
    /// What an action did ("Crop: 2.35:1"). Paired with the pressed key and shown only while
    /// "Show feedback for shortcuts" is on.
    case feedback(String)
    /// Not shortcut feedback: the file name when a video starts, a command that could not run.
    /// Always shown, for `duration` or else the user's OSD duration.
    case notice(String, duration: Duration?)
}

/// The OSD messages of the engine. VLC's own OSD is off for this interface (D027): the backend
/// reports the text of hotkey actions and notices, and the redesign draws them.
@MainActor
public protocol OSDBackend: AnyObject {
    /// Shows `text` in the OSD as action feedback.
    func showMessage(_ text: String)
    /// Called when the engine reports action feedback (e.g. a hotkey); the handler receives the text.
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (String) -> Void)
    /// Called for every OSD message, feedback or notice.
    func addMessageListener(_ owner: AnyObject, handler: @escaping @MainActor (OSDBackendMessage) -> Void)
}

extension OSDBackend {
    public func addMessageListener(_ owner: AnyObject, handler: @escaping @MainActor (OSDBackendMessage) -> Void) {
        addListener(owner) { handler(.feedback($0)) }
    }
}

/// The set of backends an ``AppModel`` is built from. MXRVLCBackend and MXRMockBackend each
/// produce one.
@MainActor
public struct Backends {
    public let player: any PlayerBackend
    public let clock: any PlaybackClockSource
    public let queue: any PlayQueueBackend
    public let library: any LibraryBackend
    public let mediaSources: any MediaSourceBackend
    public let settings: any SettingsBackend
    public let shortcuts: any ShortcutsBackend
    public let dialogs: any DialogBackend
    public let extensions: any ExtensionsBackend
    public let thumbnails: any ThumbnailBackend
    public let osd: any OSDBackend
    public let output: (any OutputBackend)?
    public let renderers: (any RendererBackend)?
    public let quitHandler: (@MainActor () -> Void)?
    public let capabilities: BackendCapabilities

    public init(player: any PlayerBackend, clock: any PlaybackClockSource, queue: any PlayQueueBackend, library: any LibraryBackend,
                mediaSources: any MediaSourceBackend, settings: any SettingsBackend, shortcuts: any ShortcutsBackend,
                dialogs: any DialogBackend, extensions: any ExtensionsBackend, thumbnails: any ThumbnailBackend,
                osd: any OSDBackend, capabilities: BackendCapabilities, output: (any OutputBackend)? = nil, renderers: (any RendererBackend)? = nil, quitHandler: (@MainActor () -> Void)? = nil) {
        self.player = player
        self.clock = clock
        self.queue = queue
        self.library = library
        self.mediaSources = mediaSources
        self.settings = settings
        self.shortcuts = shortcuts
        self.dialogs = dialogs
        self.extensions = extensions
        self.thumbnails = thumbnails
        self.osd = osd
        self.capabilities = capabilities
        self.output = output
        self.renderers = renderers
        self.quitHandler = quitHandler
    }
}
