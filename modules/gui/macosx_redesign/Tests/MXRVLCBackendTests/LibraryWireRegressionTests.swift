import MXRBridgeAPI
import XCTest
@testable import MXRVLCBackend
import MXRCore

@MainActor
final class LibraryWireRegressionTests: XCTestCase {
    func testNativeOccurrencesKeepStorageIdentityAndMetadataIDSeparate() throws {
        func row(_ position: Int) -> [String: Any] {
            ["type": "media", "media": ["id": "ml:42", "url": "https://fixture.invalid/Alpha.mp4", "title": "Alpha", "kind": "video", "playlistOccurrence": ["playlistID": "ml:8", "position": position, "revision": "revision-a"]]]
        }
        let a = try XCTUnwrap(VLCLibraryBackend.entry(row(0)))
        let b = try XCTUnwrap(VLCLibraryBackend.entry(row(3)))
        XCTAssertEqual(a.media?.id, b.media?.id)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(b.media?.playlistOccurrence?.position, 3)
        XCTAssertEqual(b.media?.playlistOccurrence?.revision, "revision-a")
    }
    func testEveryHomeSectionDestinationRoundTripsWithoutChangingQueryScope() {
        for kind in LibraryHomeSectionKind.allCases {
            let location = LibraryLocation.homeSection(kind)
            XCTAssertEqual(VLCLibraryBackend.parseLocation(VLCLibraryBackend.location(location)), location)
        }
    }
    func testRemovalSerializesNativePositionsAndRevision() async throws {
        let transport = LibraryWireTransport()
        let backend = VLCLibraryBackend(transport: transport)
        try await backend.removeFromPlaylist(id: "ml:8", occurrences: [PlaylistOccurrence(playlistID: "ml:8", position: 3, revision: "revision-a")])
        XCTAssertEqual(transport.requestName, "removeFromPlaylist")
        XCTAssertEqual(transport.arguments["positions"] as? [Int], [3])
        XCTAssertEqual(transport.arguments["revision"] as? String, "revision-a")
    }
    func testImportUsesLibraryRequestWithoutQueueCommand() async throws {
        let transport = LibraryWireTransport()
        let backend = VLCLibraryBackend(transport: transport)
        let url = URL(fileURLWithPath: "/tmp/LibraryWireImport.mp4")
        try await backend.importFiles(urls: [url])
        XCTAssertEqual(transport.requestName, "importFiles")
        XCTAssertEqual(transport.arguments["urls"] as? [String], [url.absoluteString])
        XCTAssertTrue(transport.commands.isEmpty)
    }
}

@MainActor
private final class LibraryWireTransport: VLCServiceTransport {
    var capabilities: [String: Any] { [:] }
    var requestName: String?
    var arguments: [String: Any] = [:]
    var commands: [String] = []
    func snapshot(for service: MXRBridgeService) -> [String: Any] { let service = service.rawValue; return [:] }
    func perform(_ command: MXRBridgeCommand, service: MXRBridgeService, arguments: [String: Any]) throws { let command = command.rawValue; let service = service.rawValue; commands.append(command) }
    func request(_ request: MXRBridgeRequest, service: MXRBridgeService, arguments: [String: Any]) async throws -> [String: Any] { let request = request.rawValue; let service = service.rawValue;
        requestName = request; self.arguments = arguments; return [:]
    }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (MXRBridgeService) -> Void) {}
    func log(_ error: Error) {}
    func report(_ error: Error) {}
}
