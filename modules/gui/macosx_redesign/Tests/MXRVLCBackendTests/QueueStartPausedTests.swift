import Foundation
import MXRBridgeAPI
import MXRCore
@testable import MXRVLCBackend
import XCTest

/// SET-02 / C-01: "start paused" is a per-input option in VLC. Opening a batch paused must not
/// make every later item of the batch pause when the queue advances to it.
final class QueueStartPausedTests: XCTestCase {
    @MainActor
    func testOpenPausedSendsStartPausedOnceAndNoItemCarriesTheOption() throws {
        let transport = QueueRecordingTransport()
        let backend = VLCQueueBackend(transport: transport)
        let urls = [URL(fileURLWithPath: "/tmp/a.mp4"), URL(fileURLWithPath: "/tmp/b.mp4")]
        try backend.playNow(urls.map(MediaItem.init(url:)), startAt: 1, inputOptions: [":network-caching=500"], startPaused: true)
        let args = try XCTUnwrap(transport.performed.last)
        XCTAssertEqual(args["startPaused"] as? Bool, true)
        XCTAssertEqual(args["index"] as? Int, 1)
        let items = try XCTUnwrap(args["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 2)
        for item in items {
            XCTAssertEqual(item["options"] as? [String], [":network-caching=500"])
        }
        try backend.playNow(urls.map(MediaItem.init(url:)), startAt: 0, inputOptions: [])
        XCTAssertEqual(transport.performed.last?["startPaused"] as? Bool, false)
    }
}

@MainActor private final class QueueRecordingTransport: VLCServiceTransport {
    var performed: [[String: Any]] = []
    let capabilities: [String: Any] = [:]
    func snapshot(for service: MXRBridgeService) -> [String: Any] { [:] }
    func perform(_ command: MXRBridgeCommand, service: MXRBridgeService, arguments: [String: Any]) throws {
        if command == .playNow { performed.append(arguments) }
    }
    func request(_ request: MXRBridgeRequest, service: MXRBridgeService, arguments: [String: Any]) async throws -> [String: Any] { [:] }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (MXRBridgeService) -> Void) {}
    func log(_ error: Error) {}
    func report(_ error: Error) {}
}
