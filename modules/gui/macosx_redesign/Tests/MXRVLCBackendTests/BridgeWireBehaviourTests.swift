import Foundation
import MXRBridgeAPI
import MXRCore
@testable import MXRVLCBackend
import XCTest

/// Behaviour of the adapters on the typed wire, through a fake bridge transport (C-07, C-10, C-14).
@MainActor
final class BridgeWireBehaviourTests: XCTestCase {
    /// A profile writes dozens of key-* options; the bridge coalesces them into one `shortcuts`
    /// topic. The shortcuts adapter reloads once per flush, not once per option write.
    func testShortcutBatchReloadsOncePerShortcutsFlush() {
        let transport = WireTransport()
        let backend = VLCShortcutsBackend(transport: transport)
        var reloads = 0
        backend.addListener(self) { reloads += 1 }
        _ = backend.actions
        let before = transport.shortcutSnapshotReads
        for name in ["key-play-pause", "key-stop", "global-key-play-pause", "macosx-redesign-key-app-open"] {
            transport.send(.settingOption(name))
        }
        XCTAssertEqual(reloads, 0, "per-option notifications never reload shortcuts")
        transport.send(.shortcuts)
        XCTAssertEqual(reloads, 1)
        _ = backend.actions; _ = backend.actions
        XCTAssertEqual(transport.shortcutSnapshotReads, before + 1, "one snapshot read per flush; the cache serves the rest")
    }

    /// D039: reading the sources of a category is a snapshot read; only an explicit start discovers.
    func testReadingSourcesNeverStartsDiscovery() {
        let transport = WireTransport()
        let backend = VLCMediaSourcesBackend(transport: transport)
        _ = backend.sources(in: .localNetwork)
        XCTAssertTrue(transport.commands.isEmpty)
        backend.startDiscovery(in: .localNetwork)
        XCTAssertEqual(transport.commands.map(\.0), [.discover])
        XCTAssertEqual(transport.commands.first?.1["category"] as? String, MediaSourceCategory.localNetwork.rawValue)
    }

    /// C-10: the preferred stream resolution is a saved setting, never a filter-chain rewrite.
    func testResolutionOnlyChangeWritesTheSettingAndLeavesFiltersAlone() {
        let transport = WireTransport()
        let backend = VLCPlayerBackend(transport: transport)
        var effects = backend.videoEffects
        effects.resolution = "720p"
        backend.setVideoEffects(effects)
        XCTAssertEqual(transport.commands.map(\.0), [.set, .save])
        XCTAssertEqual(transport.commands.first?.1["name"] as? String, "preferred-resolution")
        XCTAssertEqual(transport.commands.first?.1["value"] as? Int, 720)
        transport.publish(.playerEffects, [MXRPlayerKey.videoEffects.rawValue: VLCWire.dictionary(effects)])
        transport.commands.removeAll()
        effects.rotation = 90
        backend.setVideoEffects(effects)
        XCTAssertEqual(transport.commands.map(\.0), [.setVideoEffects], "a filter change leaves the preference alone")
        XCTAssertNil(transport.commands.last?.1["resolution"], "the filter command never carries the preference")
    }

    /// A value changed and changed back before the effects snapshot arrives must still reach
    /// the engine: the lagging snapshot never gates a request.
    func testRevertBeforeTheSnapshotArrivesIsStillSent() {
        let transport = WireTransport()
        let backend = VLCPlayerBackend(transport: transport)
        let original = backend.videoEffects
        var changed = original; changed.rotation = 90
        backend.setVideoEffects(changed)
        transport.commands.removeAll()
        backend.setVideoEffects(original)
        XCTAssertTrue(transport.commands.contains { $0.0 == .setVideoEffects }, "the revert reaches the filters")
        XCTAssertEqual(transport.commands.first(where: { $0.0 == .setVideoEffects })?.1["rotation"] as? Double, original.rotation)
    }

    /// A revert during the lag that comes with a resolution change still reverts the filter;
    /// comparing with the snapshot alone would see only the resolution change.
    func testRevertTogetherWithAResolutionChangeSendsBothSides() {
        let transport = WireTransport()
        let backend = VLCPlayerBackend(transport: transport)
        let original = backend.videoEffects
        var changed = original; changed.rotation = 90
        backend.setVideoEffects(changed)
        transport.commands.removeAll()
        var reverted = original; reverted.resolution = "720p"
        backend.setVideoEffects(reverted)
        XCTAssertEqual(transport.commands.map(\.0), [.set, .save, .setVideoEffects])
        XCTAssertEqual(transport.commands.last?.1["rotation"] as? Double, original.rotation)
    }

    /// A value changed elsewhere (a crop hotkey) and then requested back is sent even though it
    /// equals the previous request; a call equal to both the snapshot and the previous request
    /// sends nothing.
    func testRequestEqualToThePreviousOneIsSentAfterAnOutsideChange() {
        let transport = WireTransport()
        let backend = VLCPlayerBackend(transport: transport)
        var requested = backend.videoEffects; requested.crop = "16:9"
        backend.setVideoEffects(requested)
        transport.publish(.playerEffects, [MXRPlayerKey.videoEffects.rawValue: VLCWire.dictionary(requested)])
        transport.commands.removeAll()
        backend.setVideoEffects(requested)
        XCTAssertTrue(transport.commands.isEmpty, "nothing to apply: engine, snapshot and request agree")
        var hotkey = requested; hotkey.crop = "4:3"
        transport.publish(.playerEffects, [MXRPlayerKey.videoEffects.rawValue: VLCWire.dictionary(hotkey)])
        XCTAssertEqual(backend.videoEffects.crop, "4:3")
        backend.setVideoEffects(requested)
        XCTAssertEqual(transport.commands.map(\.0), [.setVideoEffects])
        XCTAssertEqual(transport.commands.last?.1["crop"] as? String, "16:9")
    }

}

@MainActor private final class WireTransport: VLCServiceTransport {
    var commands: [(MXRBridgeCommand, [String: Any])] = []
    var shortcutSnapshotReads = 0
    private var listeners: [(@MainActor (MXRBridgeService) -> Void)] = []
    private var snapshots: [MXRBridgeService: [String: Any]] = [:]
    let capabilities: [String: Any] = [:]
    func snapshot(for service: MXRBridgeService) -> [String: Any] {
        if service == .shortcuts { shortcutSnapshotReads += 1 }
        return snapshots[service] ?? [:]
    }
    /// Publishes a topic snapshot, as the bridge does after an engine change.
    func publish(_ service: MXRBridgeService, _ values: [String: Any]) {
        snapshots[service] = values
        send(service)
    }
    func perform(_ command: MXRBridgeCommand, service: MXRBridgeService, arguments: [String: Any]) throws { commands.append((command, arguments)) }
    func request(_ request: MXRBridgeRequest, service: MXRBridgeService, arguments: [String: Any]) async throws -> [String: Any] { [:] }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (MXRBridgeService) -> Void) { listeners.append(handler) }
    func send(_ service: MXRBridgeService) { listeners.forEach { $0(service) } }
    func log(_ error: Error) {}
    func report(_ error: Error) {}
}
