import Foundation
import MXRBridgeAPI
import MXRCore
@testable import MXRVLCBackend
import XCTest

/// Live run 1: subtitles were hidden under the revealed fullscreen control bar. The backend sends
/// the covered points and the backing scale to the bridge, which raises VLC's "sub-margin".
@MainActor
final class SubtitleSafeInsetWireTests: XCTestCase {
    func testTheInsetReachesThePlayerServiceWithItsBackingScale() {
        let transport = InsetTransport()
        let backend = VLCPlayerBackend(transport: transport)
        backend.setSubtitleSafeInset(points: 64, backingScale: 2)
        backend.setSubtitleSafeInset(points: -3, backingScale: 0)
        XCTAssertEqual(transport.commands.map(\.command), [.setSubtitleSafeInset, .setSubtitleSafeInset])
        XCTAssertEqual(transport.commands.map(\.service), [.player, .player])
        XCTAssertEqual(transport.commands[0].arguments["points"] as? Double, 64)
        XCTAssertEqual(transport.commands[0].arguments["scale"] as? Double, 2)
        XCTAssertEqual(transport.commands[1].arguments["points"] as? Double, 0, "a negative inset is no inset")
        XCTAssertEqual(transport.commands[1].arguments["scale"] as? Double, 1, "an unknown scale is 1x")
        XCTAssertEqual(MXRBridgeCommand.setSubtitleSafeInset.rawValue, "setSubtitleSafeInset", "the bridge routes this name")
    }
}

@MainActor private final class InsetTransport: VLCServiceTransport {
    var commands: [(command: MXRBridgeCommand, service: MXRBridgeService, arguments: [String: Any])] = []
    let capabilities: [String: Any] = [:]
    func snapshot(for service: MXRBridgeService) -> [String: Any] { [:] }
    func perform(_ command: MXRBridgeCommand, service: MXRBridgeService, arguments: [String: Any]) throws {
        commands.append((command, service, arguments))
    }
    func request(_ request: MXRBridgeRequest, service: MXRBridgeService, arguments: [String: Any]) async throws -> [String: Any] { [:] }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (MXRBridgeService) -> Void) {}
    func log(_ error: Error) {}
    func report(_ error: Error) {}
}
