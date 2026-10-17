import Foundation
import Observation

public struct RendererInfo: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var type: String
    public var iconURL: URL?
    public var canAudio: Bool
    public var canVideo: Bool
    public init(id: String, name: String, type: String, iconURL: URL? = nil, canAudio: Bool = true, canVideo: Bool = true) {
        self.id = id; self.name = name; self.type = type; self.iconURL = iconURL; self.canAudio = canAudio; self.canVideo = canVideo
    }
}
@MainActor public protocol RendererBackend: AnyObject {
    var items: [RendererInfo] { get }
    var selectedID: String? { get }
    var isDiscovering: Bool { get }
    func discover() async throws
    func select(id: String?) throws
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor () -> Void)
}
@MainActor @Observable public final class RendererModel {
    public private(set) var items: [RendererInfo] = []
    public private(set) var selectedID: String?
    public private(set) var isDiscovering = false
    public var errorMessage: String?
    @ObservationIgnored private let backend: (any RendererBackend)?
    public init(backend: (any RendererBackend)?) {
        self.backend = backend
        reload()
        backend?.addListener(self) { [weak self] in self?.reload() }
    }
    public func discover() async throws {
        guard let backend else { throw BackendOperationError.unsupported("Renderer discovery") }
        do { try await backend.discover(); errorMessage = nil; reload() }
        catch { errorMessage = error.localizedDescription; reload(); throw error }
    }
    public func select(id: String?) throws {
        guard let backend else { throw BackendOperationError.unsupported("Selecting a renderer") }
        do { try backend.select(id: id); errorMessage = nil; reload() }
        catch { errorMessage = error.localizedDescription; throw error }
    }
    private func reload() { items = backend?.items ?? []; selectedID = backend?.selectedID; isDiscovering = backend?.isDiscovering ?? false }
}
