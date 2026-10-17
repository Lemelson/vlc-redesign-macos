import Foundation
import MXRBridgeAPI
import MXRCore

@MainActor final class VLCRendererBackend: RendererBackend {
    private let transport: any VLCServiceTransport
    private let events = EventChannel<Void>()
    init(transport: any VLCServiceTransport) {
        self.transport = transport
        transport.addListener(self) { [weak self] service in if service == .renderers { self?.events.send(()) } }
    }
    var items: [RendererInfo] { transport.snapshot(for: .renderers).dictionaries("items").compactMap { x in x.string("id").map { RendererInfo(id: $0, name: x.string("name") ?? $0, type: x.string("type") ?? "", iconURL: x.url("iconURL"), canAudio: x.bool("canAudio"), canVideo: x.bool("canVideo")) } } }
    var selectedID: String? { transport.snapshot(for: .renderers).string("selectedID") }
    var isDiscovering: Bool { transport.snapshot(for: .renderers).bool("discovering") }
    func discover() async throws { _ = try await transport.request(.discover, service: .renderers, arguments: [:]); events.send(()) }
    func select(id: String?) throws { try transport.perform(.select, service: .renderers, arguments: ["id": id as Any? ?? NSNull()]); events.send(()) }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor () -> Void) { events.add(owner) { _ in handler() } }
}
