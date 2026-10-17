import Foundation
import MXRBridgeAPI
import MXRCore
@testable import MXRVLCBackend
import XCTest

/// ARC-15: writing one setting re-reads one value, never the whole configuration.
@MainActor
final class SettingsBackendEventTests: XCTestCase {
    func testSettingAValueReadsOnlyThatOption() async throws {
        let bridge = CountingSettingsBridge()
        let settings = VLCSettingsBackend(transport: bridge)
        var events: [SettingsEvent] = []
        settings.addListener(self) { events.append($0) }
        XCTAssertEqual(bridge.reads["settings"], 1, "The schema is read once at startup")

        settings.setValue(.integer(3000), for: "network-caching", apply: .nextMedia)
        XCTAssertEqual(settings.value(for: "network-caching"), .integer(3000))
        XCTAssertEqual(bridge.reads["settings"], 1)
        XCTAssertNil(bridge.reads["settingsValues"])
        XCTAssertEqual(bridge.reads["settings:network-caching"], 1)
        XCTAssertEqual(events.count, 1)
        if case .valueChanged(let name)? = events.first { XCTAssertEqual(name, "network-caching") } else { XCTFail("Expected one value change") }

        // A burst of broad changes (effects sliders, resets) refreshes the values once, without the schema.
        for _ in 0..<10 { bridge.emit("settings") }
        for _ in 0..<50 where bridge.reads["settingsValues"] == nil { await Task.yield() }
        XCTAssertEqual(bridge.reads["settingsValues"], 1)
        XCTAssertEqual(bridge.reads["settings"], 1)
        XCTAssertNotNil(settings.option(named: "network-caching"))
    }

    func testDeviceHotPlugIsADeviceEventNotASettingsReload() {
        let bridge = CountingSettingsBridge()
        let settings = VLCSettingsBackend(transport: bridge)
        var events: [SettingsEvent] = []
        settings.addListener(self) { events.append($0) }
        bridge.emit("player.devices")
        XCTAssertEqual(events.count, 1)
        guard case .devicesChanged? = events.first else { return XCTFail("A hot-plug must not reload settings or profiles") }
    }

    func testShortcutsIgnoreUnrelatedSettingsAndReadOnlyBindingOptions() {
        let bridge = CountingSettingsBridge()
        let shortcuts = VLCShortcutsBackend(transport: bridge)
        var reloads = 0
        shortcuts.addListener(self) { reloads += 1 }
        bridge.emit("settings")
        bridge.emit("settings:network-caching")
        XCTAssertEqual(reloads, 0)
        bridge.emit("settings:macosx-redesign-key-app-toggle-queue")
        XCTAssertEqual(reloads, 0, "a single option write is not a reload; the bridge's coalesced topic is (C-07)")
        bridge.emit("shortcuts")
        XCTAssertEqual(reloads, 1)
        _ = shortcuts.actions
        XCTAssertNil(bridge.reads["settings"], "Shortcuts never take a full settings snapshot")
    }
}

@MainActor
private final class CountingSettingsBridge: VLCServiceTransport {
    var reads: [String: Int] = [:]
    var values: [String: Any] = ["network-caching": NSNumber(value: 1000)]
    let events = EventChannel<MXRBridgeService>()
    var capabilities: [String: Any] = [:]

    func snapshot(for service: MXRBridgeService) -> [String: Any] { let service = service.rawValue;
        reads[service, default: 0] += 1
        switch service {
        case "settings":
            return ["options": [["name": "network-caching", "type": "integer", "defaultValue": NSNumber(value: 1000)]], "values": values]
        case "settingsValues": return ["values": values]
        case "shortcuts": return ["actions": []]
        default:
            if service.hasPrefix("settings:"), let value = values[String(service.dropFirst("settings:".count))] { return ["value": value] }
            return [:]
        }
    }
    func perform(_ command: MXRBridgeCommand, service: MXRBridgeService, arguments: [String: Any]) throws { let command = command.rawValue; let service = service.rawValue;
        guard service == "settings", command == "set", let name = arguments["name"] as? String else { return }
        values[name] = arguments["value"]
        emit("settings:" + name) // what MXRServicesBridge reports after config_Put*
    }
    func request(_ request: MXRBridgeRequest, service: MXRBridgeService, arguments: [String: Any]) async throws -> [String: Any] { let request = request.rawValue; let service = service.rawValue; return [:] }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (MXRBridgeService) -> Void) { events.add(owner, handler: handler) }
    func emit(_ service: String) { events.send(MXRBridgeService(rawValue: service)) }
    func log(_ error: Error) {}
    func report(_ error: Error) {}
}
