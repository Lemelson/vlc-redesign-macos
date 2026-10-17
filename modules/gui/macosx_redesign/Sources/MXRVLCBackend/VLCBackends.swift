import Foundation
import MXRBridgeAPI
import MXRCore

/// All adapters share one main-actor bridge connection. The model retains its adapters.
@MainActor
public final class VLCBackends {
    public let session: VLCBridgeSession
    public let backends: Backends
    private let transport: LiveVLCServiceTransport
    public init(bridge: MXRInterfaceBridge) {
        session = VLCBridgeSession(bridge: bridge)
        transport = LiveVLCServiceTransport(session: session)
        let flags = transport.capabilities
        backends = Backends(player: VLCPlayerBackend(transport: transport), clock: VLCClockBackend(session: session),
            queue: VLCQueueBackend(transport: transport), library: VLCLibraryBackend(transport: transport),
            mediaSources: VLCMediaSourcesBackend(transport: transport), settings: VLCSettingsBackend(transport: transport),
            shortcuts: VLCShortcutsBackend(transport: transport), dialogs: VLCDialogBackend(transport: transport),
            extensions: VLCExtensionsBackend(transport: transport), thumbnails: VLCThumbnailBackend(transport: transport),
            osd: VLCOSDBackend(transport: transport), capabilities: VLCWire.capabilities(flags), output: VLCOutputBackend(transport: transport), renderers: VLCRendererBackend(transport: transport), quitHandler: { bridge.quit() })
    }
    public func invalidate() { transport.invalidate(); session.invalidate() }
}

@MainActor
public enum VLCBackend {
    public static func makeAppModel(bridge: MXRInterfaceBridge, persistence: PersistenceLocation = .applicationSupport) -> AppModel {
        let adapters = VLCBackends(bridge: bridge)
        return AppModel(backends: adapters.backends, persistence: persistence)
    }
}

@MainActor
private final class LiveVLCServiceTransport: NSObject, VLCServiceTransport, MXRServicesEventSink {
    private let session: VLCBridgeSession
    private let events = EventChannel<MXRBridgeService>()
    private var operationError: [String: Any] = [:]
    private var nextErrorID = UInt64.max
    /// The latest OSD message: the bridge's, or a local notice from `notify`.
    private var osdMessage: [String: Any] = [:]
    private var invalidated = false
    init(session: VLCBridgeSession) { self.session = session; super.init(); session.bridge.services.sink = self }
    var capabilities: [String: Any] { session.bridge.services.capabilities }
    func snapshot(for service: MXRBridgeService) -> [String: Any] {
        switch service {
        case .operationError: operationError
        case MXRBridgeService.OSD: osdMessage
        default: session.bridge.services.snapshot(for: service)
        }
    }
    func perform(_ command: MXRBridgeCommand, service: MXRBridgeService, arguments: [String: Any]) throws {
        guard !invalidated else { throw BackendOperationError.invalidInput("VLC has shut down.") }
        if service == .dialogs, command == .dismiss, let id = arguments["id"] as? String, id == operationError.string("id") {
            operationError = [:]; events.send(.operationError); return
        }
        try session.bridge.services.perform(command, service: service, arguments: arguments)
    }
    func request(_ request: MXRBridgeRequest, service: MXRBridgeService, arguments: [String: Any]) async throws -> [String: Any] {
        guard !invalidated else { throw BackendOperationError.invalidInput("VLC has shut down.") }
        let reply: ServiceReply = try await withCheckedThrowingContinuation { continuation in
            session.bridge.services.request(request, service: service, arguments: arguments) { result, error in
                // The Objective-C contract delivers this completion on main.
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ServiceReply(values: result ?? [:])) }
            }
        }
        return reply.values
    }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (MXRBridgeService) -> Void) { events.add(owner, handler: handler) }
    func log(_ error: Error) { session.log(error.localizedDescription, level: .error) }
    func report(_ error: Error) {
        log(error)
        operationError = ["id": String(nextErrorID), "message": error.localizedDescription]
        nextErrorID &-= 1
        events.send(.operationError)
    }
    func notify(_ message: String) {
        log(BackendOperationError.invalidInput(message))
        guard !invalidated else { return }
        osdMessage = [MXROSDKey.text.rawValue: message, MXROSDKey.kind.rawValue: MXROSDKindNotice]
        events.send(MXRBridgeService.OSD)
    }
    func bridgeServiceDidChange(_ service: MXRBridgeService) {
        // Every notification reaches the adapters; each one reacts only to the services it reads.
        // (A filter list here silently dropped any service nobody remembered to add, C-08.)
        guard !invalidated else { return }
        if service == MXRBridgeService.OSD { osdMessage = session.bridge.services.snapshot(for: service) }
        events.send(service)
    }
    func invalidate() { invalidated = true; if session.bridge.services.sink === self { session.bridge.services.sink = nil } }
}

@MainActor
private final class VLCClockBackend: PlaybackClockSource {
    private let session: VLCBridgeSession
    private let events = EventChannel<ClockEvent>()
    init(session: VLCBridgeSession) {
        self.session = session
        session.observePlayer { [weak self] change in
            guard let self else { return }
            switch change {
            case .media: self.events.send(self.timerPoint == nil ? .reset : .updated)
            case .clockPaused, .state: self.events.send(.discontinuity)
            case .time, .length: self.events.send(.updated)
            case .fullscreen: break
            }
        }
    }
    var timerPoint: TimerPoint? {
        guard session.player.mediaURL != nil else { return nil }
        let p = session.player.timerPoint
        let running = session.player.state == .playing && p.hostTime > 0
        return TimerPoint(time: MediaTime(microseconds: max(0, p.time)), length: MediaTime(microseconds: max(0, p.length)), position: p.position, rate: p.rate, hostTime: running ? p.hostTime : nil)
    }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (ClockEvent) -> Void) { events.add(owner, handler: handler) }
}

/// Native request snapshots are immutable; this box crosses only the continuation boundary,
/// and both production and consumption happen on the main actor.
private struct ServiceReply: @unchecked Sendable { let values: [String: Any] }
