import Foundation
import MXRBridgeAPI
import MXRCore
@testable import MXRVLCBackend
import XCTest
@MainActor
final class SettingsAuditRegressionTests: XCTestCase {
    func testProfileEngineHotkeysInvalidateWarmDispatchCache() {
        let bridge = SettingsAuditBridge()
        let shortcuts = VLCShortcutsBackend(transport: bridge)
        XCTAssertEqual(shortcuts.actions.first?.hotkeys.first?.vlcString, "Space")
        // The bridge raises its coalesced `shortcuts` topic for every key-*/global-key-* write (C-07).
        bridge.binding = "x"; bridge.events.send(.settingOption("key-play-pause")); bridge.events.send(.shortcuts)
        XCTAssertEqual(shortcuts.actions.first?.hotkeys.first?.vlcString, "x")
        bridge.binding = "y"; bridge.events.send(.settingOption("global-key-play-pause")); bridge.events.send(.shortcuts)
        XCTAssertEqual(shortcuts.actions.first?.hotkeys.first?.vlcString, "y")
    }
    func testSaveFailureProducesUserFeedbackAndAllowsRetry() {
        let bridge = SettingsAuditBridge()
        let settings = VLCSettingsBackend(transport: bridge)
        bridge.events.send(MXRBridgeService(rawValue: "settingsSaveFailed"))
        XCTAssertEqual(bridge.errors.count, 1)
        XCTAssertTrue(bridge.errors.first?.localizedDescription.contains("not saved") ?? false)
        settings.save(); XCTAssertEqual(bridge.saves, 1)
    }
}
@MainActor
private final class SettingsAuditBridge: VLCServiceTransport {
    var capabilities: [String: Any] = [:]
    var binding = "Space"
    var errors: [Error] = []
    var saves = 0
    let events = EventChannel<MXRBridgeService>()
    func snapshot(for service: MXRBridgeService) -> [String: Any] { let service = service.rawValue;
        if service == "shortcuts" { return ["actions": [["id": "play-pause", "hotkeys": [binding]]]] }
        return [:]
    }
    func perform(_ command: MXRBridgeCommand, service: MXRBridgeService, arguments: [String: Any]) throws { let command = command.rawValue; let service = service.rawValue; if command == "save" { saves += 1 } }
    func request(_ request: MXRBridgeRequest, service: MXRBridgeService, arguments: [String: Any]) async throws -> [String: Any] { let request = request.rawValue; let service = service.rawValue; return [:] }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (MXRBridgeService) -> Void) { events.add(owner, handler: handler) }
    func log(_ error: Error) {}
    func report(_ error: Error) { errors.append(error) }
}
