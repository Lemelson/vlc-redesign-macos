import Foundation
import XCTest
import MXRCore
import MXRBridgeAPI
@testable import MXRVLCBackend

@MainActor
final class DeviceDiscoveryAdapterTests: XCTestCase {
    func testCameraDiscoveryIsLazyOffMainAndPreservesOpaqueIDs() async {
        let probe = DiscoveryProbe()
        let backend = VLCSettingsBackend(transport: DeviceDiscoveryBridge(), deviceDiscovery: probe.discover)
        XCTAssertEqual(probe.calls, [])
        let cameras = await backend.availableDevices(for: .videoCapture)
        XCTAssertEqual(cameras, [MediaDevice(id: "camera-uid-一", name: "Worker")])
        XCTAssertEqual(probe.calls, [.videoCapture])
    }

    /// C-11: the Output device row lists exactly the engine's auhal devices, with the ids
    /// `auhal-audio-device` accepts (including the system default and encoded variants).
    func testAudioOutputsAreTheEngineDeviceList() async {
        let probe = DiscoveryProbe()
        let backend = VLCSettingsBackend(transport: DeviceDiscoveryBridge(), deviceDiscovery: probe.discover)
        let devices = await backend.availableDevices(for: .audioOutput)
        XCTAssertEqual(devices, [MediaDevice(id: "0", name: "System Sound Output Device"),
                                 MediaDevice(id: "73", name: "MacBook Pro Speakers"),
                                 MediaDevice(id: "74", name: "LG HDR (Encoded Output)")])
        XCTAssertEqual(probe.calls, [], "no separate CoreAudio enumeration")
    }
}
private final class DiscoveryProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var kinds: [MediaDeviceKind] = []
    var calls: [MediaDeviceKind] { lock.withLock { kinds } }
    func discover(_ kind: MediaDeviceKind) -> [MediaDevice] {
        lock.withLock { kinds.append(kind) }
        return [MediaDevice(id: "camera-uid-一", name: Thread.isMainThread ? "Main" : "Worker")]
    }
}
@MainActor
private final class DeviceDiscoveryBridge: VLCServiceTransport {
    var capabilities: [String: Any] = [:]
    func snapshot(for service: MXRBridgeService) -> [String: Any] {
        guard service == .playerDevices else { return [:] }
        return [MXRPlayerKey.audioDevices.rawValue: [["id": "0", "name": "System Sound Output Device"],
                                                     ["id": "73", "name": "MacBook Pro Speakers"],
                                                     ["id": "74", "name": "LG HDR (Encoded Output)"]],
                MXRPlayerKey.currentAudioDeviceID.rawValue: "0"]
    }
    func perform(_ command: MXRBridgeCommand, service: MXRBridgeService, arguments: [String: Any]) throws {}
    func request(_ request: MXRBridgeRequest, service: MXRBridgeService, arguments: [String: Any]) async throws -> [String: Any] { [:] }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (MXRBridgeService) -> Void) {}
    func log(_ error: Error) {}
    func report(_ error: Error) {}
}
