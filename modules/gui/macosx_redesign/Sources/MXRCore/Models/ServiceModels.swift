import AppKit
import Foundation
import Observation

/// Hotkeys: dispatch from the key router and the Keyboard Shortcuts dialog (S64, S71).
@MainActor
@Observable
public final class ShortcutsModel {
    /// Search field filter for the dialog column ("All Fields" dropdown).
    public enum SearchField: String, CaseIterable, Sendable {
        case all, action, hotkey, globalHotkey

        public var title: String {
            switch self {
            case .all: "All Fields"
            case .action: "Action"
            case .hotkey: "Hotkey"
            case .globalHotkey: "Global Hotkey"
            }
        }
    }

    /// Saved actions (what the engine uses).
    public private(set) var actions: [ShortcutAction] = []
    /// Edits in the dialog, not yet saved (Cancel discards).
    public private(set) var draft: [String: ShortcutAction] = [:]
    public var searchText: String = ""
    public var searchField: SearchField = .all

    @ObservationIgnored public let backend: any ShortcutsBackend
    /// Called after an action is triggered by a key, with the binding (``AppModel`` shows "Pressed C").
    @ObservationIgnored public var onTriggered: (@MainActor (ShortcutAction, KeyBinding) -> Void)?
    /// Runs app-level actions (ids starting with ``appActionPrefix``), which the engine does not know,
    /// and says whether a key triggered it (then the action reports its OSD line, D027).
    /// Set by ``AppModel``.
    @ObservationIgnored public var appActionHandler: (@MainActor (_ actionID: String, _ keyed: Bool) -> Void)?
    /// Runs an engine action in the UI instead when the engine's own handler would do nothing; returns
    /// true when it did. Set by ``AppModel`` (Space after the end of the media restarts it, like Play).
    @ObservationIgnored public var engineActionOverride: (@MainActor (_ actionID: String, _ keyed: Bool) -> Bool)?

    /// Prefix of app-level action ids ("app-toggle-queue", "app-hide-ui"). Their bindings are stored
    /// by the backend like VLC's (`macosx-redesign-key-<id>`), but they run in the UI.
    public static let appActionPrefix = "app-"
    @ObservationIgnored private var lookup: [KeyBinding: String] = [:]

    public init(backend: any ShortcutsBackend) {
        self.backend = backend
        backend.addListener(self) { [weak self] in
            self?.reload()
        }
        reload()
    }

    // MARK: Dispatch

    /// The action bound to `binding`, if any.
    public func action(for binding: KeyBinding) -> ShortcutAction? {
        guard let id = lookup[binding] else { return nil }
        return actions.first { $0.id == id }
    }

    /// Handles a key press from the key router; returns true when an action ran.
    @discardableResult
    public func handle(_ binding: KeyBinding) -> Bool {
        guard let action = action(for: binding) else { return false }
        // Report the key first so the engine's OSD text (sent while the action runs) pairs with it.
        onTriggered?(action, binding)
        trigger(action.id, keyed: true)
        return true
    }

    /// Handles a key-down event from the key router; returns true when an action ran (then swallow the event).
    @discardableResult
    public func handle(event: NSEvent) -> Bool {
        guard let binding = KeyBinding(event: event) else { return false }
        return handle(binding)
    }

    /// Runs an action by id (menus, Customize Player tiles).
    public func trigger(_ actionID: String) { trigger(actionID, keyed: false) }

    private func trigger(_ actionID: String, keyed: Bool) {
        if actionID.hasPrefix(Self.appActionPrefix) {
            appActionHandler?(actionID, keyed)
        } else if engineActionOverride?(actionID, keyed) != true {
            backend.trigger(actionID: actionID)
        }
    }

    /// The first hotkey of an action, for menu key equivalents and onboarding keycaps.
    public func primaryBinding(for actionID: String) -> KeyBinding? {
        actions.first { $0.id == actionID }?.hotkeys.first
    }

    // MARK: Dialog

    /// Actions with draft edits applied.
    public var editedActions: [ShortcutAction] { actions.map { draft[$0.id] ?? $0 } }

    /// Grouped and filtered rows for the dialog.
    public var filteredGroups: [(group: ShortcutGroup, actions: [ShortcutAction])] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let list = editedActions.filter { action in
            guard !query.isEmpty else { return true }
            let inTitle = action.title.lowercased().contains(query)
            let inHotkeys = action.hotkeys.contains { $0.displayString.lowercased().contains(query) || $0.vlcString.lowercased().contains(query) }
            let inGlobal = action.globalHotkeys.contains { $0.displayString.lowercased().contains(query) || $0.vlcString.lowercased().contains(query) }
            switch searchField {
            case .all: return inTitle || inHotkeys || inGlobal
            case .action: return inTitle
            case .hotkey: return inHotkeys
            case .globalHotkey: return inGlobal
            }
        }
        return ShortcutGroup.allCases.compactMap { group in
            let rows = list.filter { $0.group == group }
            return rows.isEmpty ? nil : (group, rows)
        }
    }

    public var hasChanges: Bool { !draft.isEmpty }

    /// Sets the hotkey (or global hotkey) of an action in the draft; nil clears it.
    public func setBinding(_ binding: KeyBinding?, for actionID: String, global: Bool = false) {
        guard var action = draft[actionID] ?? actions.first(where: { $0.id == actionID }) else { return }
        if global {
            action.globalHotkeys = binding.map { [$0] } ?? []
        } else {
            action.hotkeys = binding.map { [$0] } ?? []
        }
        if action == actions.first(where: { $0.id == actionID }) {
            draft[actionID] = nil
        } else {
            draft[actionID] = action
        }
    }

    /// Removes one binding from an action in the draft, keeping its other keys (Keyboard Shortcuts "Reassign").
    public func removeBinding(_ binding: KeyBinding, from actionID: String) {
        guard var action = draft[actionID] ?? actions.first(where: { $0.id == actionID }) else { return }
        action.hotkeys.removeAll { $0 == binding }
        action.globalHotkeys.removeAll { $0 == binding }
        draft[actionID] = action == actions.first(where: { $0.id == actionID }) ? nil : action
    }

    /// Other actions (with the draft applied) already using `binding`.
    public func conflicts(for binding: KeyBinding, excluding actionID: String) -> [ShortcutAction] {
        editedActions.filter { $0.id != actionID && ($0.hotkeys.contains(binding) || $0.globalHotkeys.contains(binding)) }
    }

    /// Dialog "Save".
    public func saveDraft() {
        for action in draft.values {
            backend.setBindings(action.hotkeys, global: action.globalHotkeys, forAction: action.id)
        }
        backend.save()
        draft = [:]
        reload()
    }

    /// Dialog "Cancel".
    public func discardDraft() { draft = [:] }

    /// Settings ▸ Controls "Reset all shortcuts".
    public func resetAll() {
        backend.resetAllBindings()
        backend.save()
        draft = [:]
        reload()
    }

    /// Re-reads bindings from the backend.
    public func reload() {
        actions = backend.actions
        var table: [KeyBinding: String] = [:]
        // D026: one key, one action. App actions (menu commands the UI runs) win over an engine
        // default on the same key; among equals the first listed wins.
        for action in actions where action.id.hasPrefix("app-") {
            for binding in action.hotkeys where table[binding] == nil { table[binding] = action.id }
        }
        for action in actions where !action.id.hasPrefix("app-") {
            for binding in action.hotkeys where table[binding] == nil { table[binding] = action.id }
        }
        lookup = table
    }
}

/// The on-screen message with the pressed key (S13): "Crop: 2.35:1" / "Pressed C".
///
/// The only OSD of the interface (D027): VLC's own OSD is off, the backend reports what a
/// hotkey did, and ``keyPressed(_:)`` adds the key. Notices (a file name when a video starts, a
/// command that could not run) are shown even when shortcut feedback is off.
@MainActor
@Observable
public final class OSDModel {
    /// The message to draw, nil when hidden.
    public private(set) var message: OSDMessage?
    /// "Show feedback for shortcuts" (Settings ▸ Subtitles ▸ On-Screen Messages).
    public var isFeedbackEnabled = true
    /// "Show feedback for" (0.5...5 s).
    public var duration: Duration = .seconds(1.5)

    @ObservationIgnored public let backend: any OSDBackend
    /// Platform announcement boundary, replaceable by headless tests.
    @ObservationIgnored public var announce: @MainActor (String) -> Void = { text in
        guard let app = NSApp else { return }
        NSAccessibility.post(element: app, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var nextID: UInt64 = 1
    @ObservationIgnored private var pendingKey: String?

    public init(backend: any OSDBackend) {
        self.backend = backend
        backend.addMessageListener(self) { [weak self] message in
            switch message {
            case .feedback(let text): self?.engineDisplayed(text)
            case .notice(let text, let duration): self?.showNotice(text, duration: duration)
            }
        }
    }

    /// Shows a message natively (and optionally the pressed key).
    public func show(_ text: String?, pressedKey: String? = nil) {
        guard isFeedbackEnabled, text != nil || pressedKey != nil else { return }
        present(text, pressedKey: pressedKey, for: duration)
    }

    /// Shows information that is not shortcut feedback, regardless of "Show feedback for shortcuts".
    public func showNotice(_ text: String, duration: Duration? = nil) {
        guard !text.isEmpty else { return }
        pendingKey = nil
        present(text, pressedKey: nil, for: duration ?? self.duration)
    }

    /// Shows action feedback through the backend (the same path as a hotkey's result).
    public func showEngineMessage(_ text: String) { backend.showMessage(text) }

    /// Records the key that triggered an action; the action's text, reported while it runs or
    /// shortly after (track changes), is paired with it.
    public func keyPressed(_ binding: KeyBinding) {
        guard isFeedbackEnabled else { return }
        let key = KeyBinding.displayName(forKey: binding.key)
        let display = binding.modifiers.isEmpty ? key : binding.displayString
        pendingKey = display
        show(nil, pressedKey: display)
    }

    public func hide() {
        hideTask?.cancel()
        message = nil
        pendingKey = nil
    }

    /// The result of a shortcut the interface performs itself (volume keys step the model, not
    /// the engine): paired with the pressed key like engine feedback (D027).
    public func actionPerformed(_ text: String) { engineDisplayed(text) }

    private func engineDisplayed(_ text: String) {
        show(text, pressedKey: pendingKey)
        pendingKey = nil
    }

    private func present(_ text: String?, pressedKey: String?, for duration: Duration) {
        message = OSDMessage(id: nextID, text: text, pressedKey: pressedKey)
        if let text, !text.isEmpty { announce(text) }
        nextID += 1
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.message = nil
            self?.pendingKey = nil
        }
    }
}

/// Engine dialogs (login, question, progress, error), presented as sheets.
@MainActor
@Observable
public final class DialogModel: DialogPresenter {
    /// Pending requests, oldest first. The UI shows ``current``.
    public private(set) var requests: [DialogRequest] = []

    @ObservationIgnored private var localErrorIDs: Set<UInt64> = []
    @ObservationIgnored private var nextLocalErrorID = UInt64.max / 2
    @ObservationIgnored public let backend: any DialogBackend

    public init(backend: any DialogBackend) {
        self.backend = backend
        backend.presenter = self
    }

    public var current: DialogRequest? { requests.first }

    /// App operation errors share the sheet UI but have no engine dialog handle.
    public func presentError(_ error: Error, title: String) {
        let id = nextLocalErrorID
        nextLocalErrorID &-= 1
        localErrorIDs.insert(id)
        present(DialogRequest(id: id, title: title, text: error.localizedDescription, kind: .error))
    }

    // DialogPresenter
    public func present(_ request: DialogRequest) {
        requests.removeAll { $0.id == request.id }
        requests.append(request)
    }

    public func updateProgress(id: UInt64, value: Double, text: String?) {
        guard let index = requests.firstIndex(where: { $0.id == id }) else { return }
        var request = requests[index]
        if case .progress(let indeterminate, _, let cancel) = request.kind {
            request.kind = .progress(isIndeterminate: indeterminate, value: value, cancel: cancel)
        }
        if let text { request.text = text }
        requests[index] = request
    }

    public func cancel(id: UInt64) { requests.removeAll { $0.id == id } }

    // Answers
    public func submitLogin(_ request: DialogRequest, username: String, password: String, store: Bool) {
        backend.postLogin(id: request.id, username: username, password: password, store: store)
        requests.removeAll { $0.id == request.id }
    }

    /// `action` is 1 or 2.
    public func choose(_ request: DialogRequest, action: Int) {
        backend.postAction(id: request.id, action: action)
        requests.removeAll { $0.id == request.id }
    }

    /// Cancel / close / OK on errors.
    public func dismiss(_ request: DialogRequest) {
        if localErrorIDs.remove(request.id) == nil { backend.dismiss(id: request.id) }
        requests.removeAll { $0.id == request.id }
    }
}

/// Settings ▸ Extensions (S62).
@MainActor
@Observable
public final class ExtensionsModel {
    public private(set) var extensions: [ExtensionInfo] = []
    public private(set) var addonResults: [AddonInfo] = []
    public private(set) var isSearching = false
    public private(set) var catalogError: String?
    public private(set) var actionError: String?
    public var selection: String?
    private var availabilityRevision = 0

    @ObservationIgnored public let backend: any ExtensionsBackend

    public init(backend: any ExtensionsBackend) {
        self.backend = backend
        extensions = backend.extensions
        backend.addListener(self) { [weak self] _ in
            guard let self else { return }
            self.extensions = self.backend.extensions
            self.availabilityRevision += 1
        }
    }

    public func setActivated(_ activated: Bool, _ ext: ExtensionInfo) {
        guard availability(for: .activate, extensionID: ext.id).isAvailable else {
            actionError = availability(for: .activate, extensionID: ext.id).reason
            return
        }
        actionError = nil
        if activated { backend.activate(id: ext.id) } else { backend.deactivate(id: ext.id) }
    }

    public func availability(for operation: ExtensionOperation, extensionID: String? = nil) -> ExtensionAvailability {
        _ = availabilityRevision
        return (backend as? any ExtensionsAvailabilityBackend)?.availability(for: operation, extensionID: extensionID)
            ?? .unavailable(operation.unavailableReason)
    }

    /// Reading it makes a view depend on the catalog, so a menu the extension changes redraws.
    public func menu(for ext: ExtensionInfo) -> [ExtensionMenuItem] {
        _ = availabilityRevision
        return backend.menu(forExtension: ext.id)
    }
    /// Fresh extension menus, for a menu that is opening (they can change after activation).
    public func refresh() { backend.refresh() }
    public func trigger(_ item: ExtensionMenuItem, of ext: ExtensionInfo) { backend.triggerMenu(extensionID: ext.id, itemID: item.id) }

    /// "Find more extensions".
    public func searchAddons(_ text: String) async {
        guard !isSearching else { return }
        guard availability(for: .searchCatalog).isAvailable else {
            catalogError = availability(for: .searchCatalog).reason
            addonResults = []
            return
        }
        catalogError = nil
        isSearching = true
        defer { isSearching = false }
        do { addonResults = try await backend.searchAddons(text) }
        catch { addonResults = []; catalogError = error.localizedDescription }
    }

    public func install(_ addon: AddonInfo) async throws {
        try require(.installAddon, extensionID: addon.id)
        try await backend.installAddon(id: addon.id)
    }
    public func remove(_ addon: AddonInfo) async throws {
        try require(.removeAddon, extensionID: addon.id)
        try await backend.removeAddon(id: addon.id)
    }
    /// "Add" (a local .lua file).
    public func installExtension(at url: URL) async throws {
        try require(.installLocal)
        try await backend.installExtension(fileURL: url)
    }
    public func removeExtension(_ ext: ExtensionInfo) async throws {
        try require(.removeLocal, extensionID: ext.id)
        guard let removal = backend as? any LocalExtensionRemovalBackend else { throw BackendOperationError.unsupported("Removing local extensions") }
        try await removal.removeExtension(id: ext.id)
    }

    public func runExtension(_ ext: ExtensionInfo) async throws {
        try require(.run, extensionID: ext.id)
        guard let runner = backend as? any ExtensionRunningBackend else { throw BackendOperationError.unsupported("Running on-demand extensions") }
        try await runner.runExtension(id: ext.id)
    }

    private func require(_ operation: ExtensionOperation, extensionID: String? = nil) throws {
        if let reason = availability(for: operation, extensionID: extensionID).reason { throw BackendOperationError.invalidInput(reason) }
    }
}
