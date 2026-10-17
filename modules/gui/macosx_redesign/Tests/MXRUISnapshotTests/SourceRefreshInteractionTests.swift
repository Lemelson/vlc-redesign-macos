import MXRCore
@testable import MXRUI
import XCTest

final class SourceRefreshInteractionTests: XCTestCase {
    @MainActor
    func testManualRefreshFetchesSourceAndEventBurstsOnlyReadCache() async {
        let backend = RefreshSourceBackend()
        let model = LibrarySourceBrowserModel(backend: backend)
        await model.browse(backend.source)
        await model.open(backend.folder)
        XCTAssertEqual(model.nodes.count, 1)

        backend.liveNodes.append(backend.second)
        await model.reload()
        XCTAssertEqual(model.nodes.count, 1, "Ordinary reads use the existing listing")
        await model.manualRefresh()
        XCTAssertEqual(model.nodes.count, 2)
        XCTAssertEqual(model.path, [backend.folder])
        XCTAssertEqual(backend.refreshCount, 1)

        for _ in 0..<20 { backend.changed() }
        for _ in 0..<40 { await Task.yield() }
        XCTAssertEqual(model.nodes.count, 2)
        XCTAssertEqual(model.path, [backend.folder])
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(backend.refreshCount, 1, "An event re-query must not start another refresh")

        backend.liveNodes.removeLast()
        await model.manualRefresh()
        await model.reload()
        XCTAssertEqual(model.nodes.count, 1)
        XCTAssertEqual(backend.refreshCount, 2)
    }

    @MainActor
    func testCategoryChangeDiscardsSuspendedManualRefresh() async {
        let backend = RefreshSourceBackend()
        let model = LibrarySourceBrowserModel(backend: backend)
        await model.browse(backend.source)
        await model.open(backend.folder)
        backend.suspendsRefresh = true
        let refresh = Task { await model.manualRefresh() }
        while backend.pendingRefresh == nil { await Task.yield() }
        model.select(.internet)
        backend.pendingRefresh?.resume(returning: [backend.second])
        backend.pendingRefresh = nil
        await refresh.value
        XCTAssertEqual(model.category, .internet)
        XCTAssertNil(model.source)
        XCTAssertTrue(model.path.isEmpty)
        XCTAssertTrue(model.nodes.isEmpty)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testBackendWithoutRefreshImplementationUsesDefaultChildRead() async throws {
        let backend = ReadOnlySourceBackend()
        let source = try XCTUnwrap(backend.sources(in: .localNetwork).first)
        let nodes = try await backend.refreshChildren(of: nil, in: source)
        XCTAssertEqual(nodes.map(\.id), ["existing"])
        XCTAssertEqual(backend.readCount, 1)
    }
}

@MainActor private final class RefreshSourceBackend: MediaSourceBackend {
    let source = MediaSourceInfo(id: "network", title: "Network", category: .localNetwork)
    let folder = MediaSourceNode(id: "folder", title: "Shared folder", mrl: "smb://server/share/", isContainer: true)
    let second = MediaSourceNode(id: "second", title: "Second movie", mrl: "smb://server/share/second.mp4", isContainer: false)
    var liveNodes = [MediaSourceNode(id: "first", title: "First movie", mrl: "smb://server/share/first.mp4", isContainer: false)]
    private var cachedNodes: [MediaSourceNode]?
    private let events = EventChannel<MediaSourceEvent>()
    var refreshCount = 0
    var suspendsRefresh = false
    var pendingRefresh: CheckedContinuation<[MediaSourceNode], Error>?

    func sources(in category: MediaSourceCategory) -> [MediaSourceInfo] { category == .localNetwork ? [source] : [] }
    func children(of node: MediaSourceNode?, in source: MediaSourceInfo) async throws -> [MediaSourceNode] {
        guard node != nil else { return [folder] }
        if cachedNodes == nil { cachedNodes = liveNodes }
        return cachedNodes ?? []
    }
    func refreshChildren(of node: MediaSourceNode?, in source: MediaSourceInfo) async throws -> [MediaSourceNode] {
        refreshCount += 1
        if suspendsRefresh { return try await withCheckedThrowingContinuation { pendingRefresh = $0 } }
        cachedNodes = liveNodes
        return node == nil ? [folder] : liveNodes
    }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (MediaSourceEvent) -> Void) { events.add(owner, handler: handler) }
    func changed() { events.send(.childrenChanged(sourceID: source.id, nodeID: folder.id)) }
}

@MainActor private final class ReadOnlySourceBackend: MediaSourceBackend {
    var readCount = 0
    func sources(in category: MediaSourceCategory) -> [MediaSourceInfo] {
        [MediaSourceInfo(id: "readonly", title: "Existing source", category: .localNetwork)]
    }
    func children(of node: MediaSourceNode?, in source: MediaSourceInfo) async throws -> [MediaSourceNode] {
        readCount += 1
        return [MediaSourceNode(id: "existing", title: "Existing", mrl: "smb://server/file.mp4", isContainer: false)]
    }
}
