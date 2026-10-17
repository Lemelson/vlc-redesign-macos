import CoreGraphics
import Foundation
import ImageIO
import MXRBridgeAPI
import MXRCore

@MainActor
final class VLCShortcutsBackend: ShortcutsBackend {
    private typealias K = MXRShortcutKey
    private let transport: any VLCServiceTransport
    private let events = EventChannel<Void>()
    /// Read once per change, not on every access (the dispatch table reads it per key press).
    private var cachedActions: [ShortcutAction]?
    init(transport: any VLCServiceTransport) {
        self.transport = transport
        // ARC-15: only binding changes matter here, never every settings write or effects tick.
        // The bridge raises one coalesced `shortcuts` topic for any batch of key-*, global-key-*
        // and macosx-redesign-key-* writes (a profile applies dozens): one reload per flush (C-07).
        transport.addListener(self) { [weak self] service in
            if service == MXRBridgeService.shortcuts { self?.changed() }
        }
        migrateLegacyAppDefaults()
    }
    /// M2: an earlier build stored Control defaults for the app actions; reset them once at start so
    /// the Mac defaults apply again. Done here, not in `actions`, so reading the cache has no side effects.
    private func migrateLegacyAppDefaults() {
        let appBindings = transport.snapshot(for: MXRBridgeService.shortcuts).dictionary(K.appBindings)
        for action in ShortcutAction.appActions {
            guard let value = appBindings.string("macosx-redesign-key-" + action.id),
                  ShortcutAction.isLegacyAppDefault(value, forID: action.id) else { continue }
            transport.command(.reset, service: .settings, arguments: ["name": "macosx-redesign-key-" + action.id])
        }
    }
    var actions: [ShortcutAction] {
        if let cachedActions { return cachedActions }
        let snapshot = transport.snapshot(for: MXRBridgeService.shortcuts)
        let engine = snapshot.dictionaries(K.actions).compactMap { x -> ShortcutAction? in
            guard let id = x.string(K.ID) else { return nil }
            return ShortcutAction(id: id, title: VLCShortcutCatalog.title(for: id, engineName: x.string(K.name)), group: VLCShortcutCatalog.group(for: id),
                                  hotkeys: (x[K.hotkeys] as? [String] ?? []).compactMap(KeyBinding.init(vlcString:)),
                                  globalHotkeys: (x[K.global] as? [String] ?? []).compactMap(KeyBinding.init(vlcString:)))
        }
        // The design's order (Toggle fullscreen first, then Play/pause…), not the engine's (stable for the rest).
        .enumerated().sorted { (VLCShortcutCatalog.rank(for: $0.element.id), $0.offset) < (VLCShortcutCatalog.rank(for: $1.element.id), $1.offset) }
        .map(\.element)
        let appBindings = snapshot.dictionary(K.appBindings)
        let result = engine + ShortcutAction.appActions.map { action in
            var result = action
            if let value = appBindings.string("macosx-redesign-key-" + action.id) {
                // A legacy Control default (see migrateLegacyAppDefaults) reads as the Mac default.
                if ShortcutAction.isLegacyAppDefault(value, forID: action.id) { return result }
                result.hotkeys = value.split(separator: "\t").compactMap { KeyBinding(vlcString: String($0)) }
            }
            return result
        }
        cachedActions = result
        return result
    }
    func trigger(actionID: String) { transport.command(.trigger, service: MXRBridgeService.shortcuts, arguments: ["id": actionID]) }
    func setBindings(_ hotkeys: [KeyBinding], global: [KeyBinding], forAction id: String) {
        if id.hasPrefix("app-") {
            transport.command(.set, service: .settings, arguments: ["name": "macosx-redesign-key-" + id, "value": hotkeys.map(\.vlcString).joined(separator: "\t"), "apply": "next-media"])
        } else { transport.command(.setBindings, service: MXRBridgeService.shortcuts, arguments: ["id": id, "hotkeys": hotkeys.map(\.vlcString), "global": global.map(\.vlcString)]) }
        changed()
    }
    func resetAllBindings() {
        transport.command(.resetAll, service: MXRBridgeService.shortcuts)
        for action in ShortcutAction.appActions { transport.command(.reset, service: .settings, arguments: ["name": "macosx-redesign-key-" + action.id]) }
        changed()
    }
    func save() { transport.command(.save, service: MXRBridgeService.shortcuts) }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor () -> Void) { events.add(owner) { _ in handler() } }
    private func changed() { cachedActions = nil; events.send(()) }
}

@MainActor
final class VLCDialogBackend: DialogBackend {
    private let transport: any VLCServiceTransport
    weak var presenter: (any DialogPresenter)? { didSet { reload() } }
    private var presented: [UInt64: DialogRequest] = [:]
    init(transport: any VLCServiceTransport) {
        self.transport = transport
        transport.addListener(self) { [weak self] service in if service == .dialogs || service == .operationError { self?.reload() } }
    }
    func postLogin(id: UInt64, username: String, password: String, store: Bool) { transport.command(.postLogin, service: .dialogs, arguments: ["id": String(id), "username": username, "password": password, "store": store]) }
    func postAction(id: UInt64, action: Int) { transport.command(.postAction, service: .dialogs, arguments: ["id": String(id), "action": action]) }
    func dismiss(id: UInt64) { transport.command(.dismiss, service: .dialogs, arguments: ["id": String(id)]) }
    private func reload() {
        guard let presenter else { return }
        let state = transport.snapshot(for: .dialogs)
        let list = state.dictionaries("requests").compactMap(Self.dialog)
        let ids = Set(list.map(\.id))
        for id in Array(presented.keys) where !ids.contains(id) { presenter.cancel(id: id); presented[id] = nil }
        for request in list {
            if presented[request.id] == nil { presenter.present(request) }
            else if case .progress(_, let value, _) = request.kind { presenter.updateProgress(id: request.id, value: value, text: request.text) }
            presented[request.id] = request
        }
        let error = transport.snapshot(for: .operationError)
        if let text = error.string("message") {
            let id = error.string("id").flatMap(UInt64.init) ?? (error["id"] as? NSNumber)?.uint64Value ?? UInt64.max
            if presented[id] == nil { let request = DialogRequest(id: id, title: "VLC operation failed", text: text, kind: .error); presented[id] = request; presenter.present(request) }
        }
    }
    static func dialog(_ x: [String: Any]) -> DialogRequest? {
        guard let id = x.string("id").flatMap(UInt64.init) ?? (x["id"] as? NSNumber)?.uint64Value else { return nil }
        let kind: DialogRequest.Kind
        switch x.string("kind") ?? x.string("type") {
        case "login": kind = .login(defaultUsername: x.string("defaultUsername") ?? "", canStore: x.bool("canStore"))
        case "question": kind = .question(severity: DialogSeverity(rawValue: x.string("severity") ?? "normal") ?? .normal, action1: x.string("action1"), action2: x.string("action2"), cancel: x.string("cancel"))
        case "progress": kind = .progress(isIndeterminate: x.bool("isIndeterminate"), value: x.double("value"), cancel: x.string("cancel"))
        default: kind = .error
        }
        return DialogRequest(id: id, title: x.string("title") ?? "VLC", text: x.string("text") ?? "", kind: kind)
    }
}

@MainActor
final class VLCMediaSourcesBackend: MediaSourceBackend {
    private let transport: any VLCServiceTransport
    private let events = EventChannel<MediaSourceEvent>()
    init(transport: any VLCServiceTransport) {
        self.transport = transport
        transport.addListener(self) { [weak self] service in
            guard service == .mediaSources, let self else { return }
            let event = self.transport.snapshot(for: .mediaSources).dictionary("event")
            if event.string("type") == "childrenChanged", let sourceID = event.string("sourceID") { self.events.send(.childrenChanged(sourceID: sourceID, nodeID: event.string("nodeID"))) }
            else if let category = event.string("category").flatMap(MediaSourceCategory.init(rawValue:)) { self.events.send(.sourcesChanged(category)) }
            else { for category in MediaSourceCategory.allCases { self.events.send(.sourcesChanged(category)) } }
        }
    }
    /// D039: network discovery starts only when a browser asks for a category, never on a read.
    func startDiscovery(in category: MediaSourceCategory) {
        transport.command(.discover, service: .mediaSources, arguments: ["category": category.rawValue])
    }
    func sources(in category: MediaSourceCategory) -> [MediaSourceInfo] {
        transport.snapshot(for: .mediaSources).dictionary("categories").dictionaries(category.rawValue).compactMap { x in x.string("id").map { MediaSourceInfo(id: $0, title: x.string("title") ?? $0, category: category) } }
    }
    func children(of node: MediaSourceNode?, in source: MediaSourceInfo) async throws -> [MediaSourceNode] {
        try await queryChildren(.children, node: node, source: source)
    }
    func refreshChildren(of node: MediaSourceNode?, in source: MediaSourceInfo) async throws -> [MediaSourceNode] {
        try await queryChildren(.refreshChildren, node: node, source: source)
    }
    private func queryChildren(_ request: MXRBridgeRequest, node: MediaSourceNode?, source: MediaSourceInfo) async throws -> [MediaSourceNode] {
        var args: [String: Any] = ["sourceID": source.id]
        if let node { args["nodeID"] = node.id }
        let reply = try await transport.request(request, service: .mediaSources, arguments: args)
        return reply.dictionaries("children").compactMap { x in guard let id = x.string("id"), let mrl = x.string("mrl") ?? x.string("url") else { return nil }; return MediaSourceNode(id: id, title: x.string("title") ?? id, mrl: mrl, isContainer: x.bool("isContainer")) }
    }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (MediaSourceEvent) -> Void) { events.add(owner, handler: handler) }
}

@MainActor
final class VLCExtensionsBackend: ExtensionsBackend, LocalExtensionRemovalBackend, ExtensionsAvailabilityBackend, ExtensionRunningBackend {
    private let transport: any VLCServiceTransport
    private let events = EventChannel<ExtensionsEvent>()
    init(transport: any VLCServiceTransport) {
        self.transport = transport
        transport.addListener(self) { [weak self] service in if service == .extensions { self?.events.send(.listChanged) } }
        if transport.capabilities.bool("extensions") {
            Task { @MainActor in do { _ = try await transport.request(.list, service: .extensions, arguments: [:]) } catch { transport.report(error) } }
        }
    }
    var extensions: [ExtensionInfo] { transport.snapshot(for: .extensions).dictionaries("items").compactMap { x in x.string("id").map { ExtensionInfo(id: $0, title: x.string("title") ?? x.string("name") ?? $0, summary: x.string("summary"), author: x.string("author"), version: x.string("version"), isActivated: x.bool("active"), hasMenu: x.bool("hasMenu")) } } }
    func availability(for operation: ExtensionOperation, extensionID: String?) -> ExtensionAvailability {
        let snapshot = transport.snapshot(for: .extensions)
        switch operation {
        case .searchCatalog:
            return snapshot.bool("supportsSearchCatalog") ? .available : .unavailable(operation.unavailableReason)
        case .installAddon, .removeAddon:
            return .unavailable(operation.unavailableReason)
        case .installLocal:
            return snapshot.bool("supportsInstall") ? .available : .unavailable(snapshot.string("localUnavailableReason") ?? "Local Lua extension management requires a loaded extension manager and a writable user extension folder.")
        case .removeLocal:
            guard snapshot.bool("supportsRemove") else { return .unavailable(snapshot.string("localUnavailableReason") ?? "Local Lua extension management requires a loaded extension manager and a writable user extension folder.") }
            guard let extensionID else { return .available }
            guard let item = snapshot.dictionaries("items").first(where: { $0.string("id") == extensionID }) else { return .unavailable("Select an installed extension to remove.") }
            return item.bool("removable") ? .available : .unavailable("Only Lua extensions installed in your user extension folder can be removed.")
        case .activate:
            guard snapshot.bool("supportsActivation") else { return .unavailable(snapshot.string("activationUnavailableReason") ?? operation.unavailableReason) }
            guard let extensionID else { return .available }
            guard let item = snapshot.dictionaries("items").first(where: { $0.string("id") == extensionID }), item.bool("available") else { return .unavailable("This extension is unavailable. Reload the extension manager or check the script.") }
            return item.bool("triggerOnly") ? .unavailable("This extension runs on demand and cannot be enabled.") : .available
        case .run:
            guard snapshot.bool("supportsActivation") else { return .unavailable(snapshot.string("activationUnavailableReason") ?? operation.unavailableReason) }
            guard let extensionID, let item = snapshot.dictionaries("items").first(where: { $0.string("id") == extensionID }), item.bool("available") else { return .unavailable("Select an available on-demand extension to run.") }
            return item.bool("triggerOnly") ? .available : .unavailable("This extension uses the enable toggle instead of running on demand.")
        }
    }
    func activate(id: String) { operate(.activate, id: id) }
    func deactivate(id: String) { operate(.deactivate, id: id) }
    func menu(forExtension id: String) -> [ExtensionMenuItem] { transport.snapshot(for: .extensions).dictionary("menus").dictionaries(id).map { ExtensionMenuItem(id: UInt16(clamping: $0.integer("id")), title: $0.string("title") ?? "") } }
    func refresh() {
        guard transport.capabilities.bool("extensions") else { return }
        let transport = transport
        // A failure here is the one the catalog already reported; the menu keeps the last snapshot.
        Task { @MainActor in do { _ = try await transport.request(.list, service: .extensions, arguments: [:]) } catch { transport.log(error) } }
    }
    func triggerMenu(extensionID: String, itemID: UInt16) { let transport = transport; Task { @MainActor in do { _ = try await transport.request(.triggerMenu, service: .extensions, arguments: ["id": extensionID, "menuID": Int(itemID)]) } catch { transport.report(error) } } }
    func searchAddons(_ text: String) async throws -> [AddonInfo] { try require(.searchCatalog); let result = try await transport.request(.searchAddons, service: .extensions, arguments: ["text": text]); return result.dictionaries("addons").compactMap { x in x.string("id").map { AddonInfo(id: $0, name: x.string("name") ?? $0, summary: x.string("summary") ?? "", author: x.string("author"), version: x.string("version"), isInstalled: x.bool("isInstalled")) } } }
    func installAddon(id: String) async throws { try require(.installAddon, id: id); _ = try await transport.request(.installAddon, service: .extensions, arguments: ["id": id]) }
    func removeAddon(id: String) async throws { try require(.removeAddon, id: id); _ = try await transport.request(.removeAddon, service: .extensions, arguments: ["id": id]) }
    func installExtension(fileURL: URL) async throws { try require(.installLocal); _ = try await transport.request(.installExtension, service: .extensions, arguments: ["url": fileURL.absoluteString]) }
    func removeExtension(id: String) async throws { try require(.removeLocal, id: id); _ = try await transport.request(.removeExtension, service: .extensions, arguments: ["id": id]) }
    func runExtension(id: String) async throws {
        try require(.run, id: id)
        _ = try await transport.request(.activate, service: .extensions, arguments: ["id": id])
    }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (ExtensionsEvent) -> Void) { events.add(owner, handler: handler) }
    private func require(_ operation: ExtensionOperation, id: String? = nil) throws {
        if let reason = availability(for: operation, extensionID: id).reason { throw BackendOperationError.invalidInput(reason) }
    }
    private func operate(_ command: MXRBridgeRequest, id: String) {
        do { try require(.activate, id: id) } catch { transport.report(error); return }
        let transport = transport
        Task { @MainActor in do { _ = try await transport.request(command, service: .extensions, arguments: ["id": id]) } catch { transport.report(error) } }
    }
}

/// The redesign OSD's source (D027). The bridge switches VLC's own OSD off, reports what a
/// hotkey did (feedback) and file names at video start (notices); a player command that could
/// not run arrives as a notice from the transport.
@MainActor
final class VLCOSDBackend: OSDBackend {
    private typealias K = MXROSDKey
    private let transport: any VLCServiceTransport
    private let events = EventChannel<OSDBackendMessage>()
    init(transport: any VLCServiceTransport) {
        self.transport = transport
        transport.addListener(self) { [weak self] service in
            guard service == MXRBridgeService.OSD, let self else { return }
            let message = self.transport.snapshot(for: service)
            guard let text = message.string(K.text) else { return }
            if message.string(K.kind) == MXROSDKindNotice {
                let seconds = message.double(K.duration)
                self.events.send(.notice(text, duration: seconds > 0 ? .milliseconds(Int(seconds * 1000)) : nil))
            } else {
                self.events.send(.feedback(text))
            }
        }
    }
    func showMessage(_ text: String) { transport.command(.showMessage, service: MXRBridgeService.player, arguments: ["text": text]) }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (String) -> Void) {
        events.add(owner) { message in if case .feedback(let text) = message { handler(text) } }
    }
    func addMessageListener(_ owner: AnyObject, handler: @escaping @MainActor (OSDBackendMessage) -> Void) { events.add(owner, handler: handler) }
}
