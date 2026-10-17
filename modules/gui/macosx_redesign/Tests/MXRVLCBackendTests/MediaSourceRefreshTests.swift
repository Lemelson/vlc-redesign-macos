import MXRBridgeAPI
import MXRCore
@testable import MXRVLCBackend
import XCTest

final class MediaSourceRefreshTests: XCTestCase {
    @MainActor
    func testRefreshUsesExplicitOperationAndRetainsNodeIdentity() async throws {
        let transport = SourceRefreshTransport()
        let backend = VLCMediaSourcesBackend(transport: transport)
        let source = MediaSourceInfo(id: "smb", title: "SMB", category: .localNetwork)
        let folder = MediaSourceNode(id: "folder", title: "Share", mrl: "smb://server/share/", isContainer: true)
        let nodes = try await backend.refreshChildren(of: folder, in: source)
        XCTAssertEqual(transport.requests.map(\.name), ["refreshChildren"])
        XCTAssertEqual(transport.requests.first?.service, "mediaSources")
        XCTAssertEqual(transport.requests.first?.arguments["sourceID"] as? String, source.id)
        XCTAssertEqual(transport.requests.first?.arguments["nodeID"] as? String, folder.id)
        XCTAssertEqual(nodes.map(\.id), ["movie"])
        XCTAssertEqual(nodes.first?.mrl, "smb://server/share/movie.mp4")

        _ = try await backend.children(of: nil, in: source)
        XCTAssertEqual(transport.requests.last?.name, "children")
        XCTAssertNil(transport.requests.last?.arguments["nodeID"])
    }

    @MainActor
    func testRefreshPropagatesFailureInsteadOfReturningStaleChildren() async {
        let transport = SourceRefreshTransport()
        transport.failure = BackendOperationError.invalidInput("Source unavailable")
        let backend = VLCMediaSourcesBackend(transport: transport)
        do {
            _ = try await backend.refreshChildren(of: nil, in: MediaSourceInfo(id: "smb", title: "SMB", category: .localNetwork))
            XCTFail("Refresh should report the native error")
        } catch { XCTAssertEqual(error.localizedDescription, "Source unavailable") }
    }
}

@MainActor private final class SourceRefreshTransport: VLCServiceTransport {
    struct Request { let name: String; let service: String; let arguments: [String: Any] }
    var requests: [Request] = []
    var failure: Error?
    let capabilities: [String: Any] = ["mediaSources": true]
    func snapshot(for service: MXRBridgeService) -> [String: Any] { let service = service.rawValue; return [:] }
    func perform(_ command: MXRBridgeCommand, service: MXRBridgeService, arguments: [String: Any]) throws { let command = command.rawValue; let service = service.rawValue;}
    func request(_ request: MXRBridgeRequest, service: MXRBridgeService, arguments: [String: Any]) async throws -> [String: Any] { let request = request.rawValue; let service = service.rawValue;
        requests.append(Request(name: request, service: service, arguments: arguments))
        if let failure { throw failure }
        return ["children": [["id": "movie", "title": "Movie", "mrl": "smb://server/share/movie.mp4", "isContainer": false]]]
    }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (MXRBridgeService) -> Void) {}
    func log(_ error: Error) {}
    func report(_ error: Error) {}
}
