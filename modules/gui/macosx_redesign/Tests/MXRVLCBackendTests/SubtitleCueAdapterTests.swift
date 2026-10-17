import Foundation
import MXRBridgeAPI
import MXRCore
@testable import MXRVLCBackend
import XCTest

final class SubtitleCueAdapterTests: XCTestCase {
    @MainActor
    func testNativeCueTimesAndSelectedTrackIdentityArePreserved() async {
        let transport = CueTransport()
        transport.reply = ["cues": [["start": Int64(1_250_000), "end": Int64(3_500_000), "text": "First\nNext"]]]
        let player = VLCPlayerBackend(transport: transport)
        let cues = await player.subtitleCues(trackID: "hash/spu/0")
        XCTAssertEqual(transport.operation, "subtitleCues")
        XCTAssertEqual(transport.service, "player")
        XCTAssertEqual(transport.arguments["id"] as? String, "hash/spu/0")
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues.first?.start.microseconds, 1_250_000)
        XCTAssertEqual(cues.first?.end.microseconds, 3_500_000)
        XCTAssertEqual(cues.first?.text, "First\nNext")
        XCTAssertTrue(transport.reportedErrors.isEmpty)
    }

    @MainActor
    func testUnavailableOrCancelledTimelineDoesNotBecomeAPlaybackError() async {
        let transport = CueTransport()
        let player = VLCPlayerBackend(transport: transport)
        for code in [3, NSUserCancelledError] {
            transport.failure = NSError(domain: "MXRVLCBridge", code: code)
            let cues = await player.subtitleCues(trackID: "spu/0")
            XCTAssertTrue(cues.isEmpty)
            XCTAssertNil(player.errorMessage)
            XCTAssertTrue(transport.reportedErrors.isEmpty, "Optional cue data must not produce a player error")
        }
        XCTAssertEqual(transport.loggedErrors.count, 2)
    }
}

@MainActor private final class CueTransport: VLCServiceTransport {
    let capabilities: [String: Any] = ["supportsSubtitleTimeline": true]
    var reply: [String: Any] = ["cues": []]
    var failure: Error?
    var operation: String?
    var service: String?
    var arguments: [String: Any] = [:]
    var loggedErrors: [Error] = []
    var reportedErrors: [Error] = []
    func snapshot(for service: MXRBridgeService) -> [String: Any] { let service = service.rawValue; return [:] }
    func perform(_ command: MXRBridgeCommand, service: MXRBridgeService, arguments: [String: Any]) throws { let command = command.rawValue; let service = service.rawValue;}
    func request(_ request: MXRBridgeRequest, service: MXRBridgeService, arguments: [String: Any]) async throws -> [String: Any] { let request = request.rawValue; let service = service.rawValue;
        operation = request; self.service = service; self.arguments = arguments
        if let failure { throw failure }
        return reply
    }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (MXRBridgeService) -> Void) {}
    func log(_ error: Error) { loggedErrors.append(error) }
    func report(_ error: Error) { reportedErrors.append(error) }
}
