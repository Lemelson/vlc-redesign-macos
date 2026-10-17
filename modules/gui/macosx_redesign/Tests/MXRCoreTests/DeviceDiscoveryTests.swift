import XCTest
@testable import MXRCore
@testable import MXRMockBackend

@MainActor
final class DeviceDiscoveryTests: XCTestCase {
    func testDeviceRequirementDispatchesThroughSettingsExistential() async {
        let mock = MockBackend(scenario: .idle)
        let expected = [MediaDevice(id: "81", name: "Studio output")]
        mock.settings.deviceFixtures[.audioOutput] = expected
        let backend: any SettingsBackend = mock.settings
        let devices = await backend.availableDevices(for: .audioOutput)
        XCTAssertEqual(devices, expected)
    }

    func testDeviceChoicesAreAPureReadAndLoadOnlyWhenAsked() async {
        let mock = MockBackend(scenario: .idle)
        let expected = [MediaDevice(id: "81", name: "Studio output")]
        mock.settings.deviceFixtures[.audioOutput] = expected
        mock.settings.setValue(.string("0"), for: "auhal-audio-device", apply: .nextMedia)
        let model = SettingsModel(backend: mock.settings)
        XCTAssertTrue(model.deviceChoices(for: .audioOutput).isEmpty)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(mock.settings.deviceQueries.isEmpty, "Reading a device row never queries the hardware.")
        model.select(categoryID: "general")
        XCTAssertTrue(model.visibleDeviceKinds.isEmpty, "A category without a device row needs no query.")
        let audio = model.catalog.categories.first(where: { $0.sections.contains { $0.rows.contains { $0.choiceSource == "audio-devices" } } })
        model.select(categoryID: audio?.id ?? "audio")
        XCTAssertEqual(model.visibleDeviceKinds, [.audioOutput])
        async let first: Void = model.loadDeviceChoices(for: [.audioOutput])
        async let second: Void = model.loadDeviceChoices(for: [.audioOutput])
        _ = await (first, second)
        XCTAssertEqual(model.deviceChoices(for: .audioOutput), expected)
        XCTAssertEqual(mock.settings.deviceQueries, [.audioOutput], "Concurrent loads share one query.")
        XCTAssertEqual(mock.settings.value(for: "auhal-audio-device"), .string("0"))
    }

    func testMockDeviceCapabilitiesDefaultToEmpty() async {
        let mock = MockBackend(scenario: .idle)
        let audio = await mock.settings.availableDevices(for: .audioOutput)
        let video = await mock.settings.availableDevices(for: .videoCapture)
        XCTAssertEqual(audio, [])
        XCTAssertEqual(video, [])
    }

    func testHotPlugMarksDevicesStaleWithoutTouchingValuesOrProfiles() async {
        let mock = MockBackend(scenario: .idle)
        let first = [MediaDevice(id: "81", name: "Studio output")]
        let second = [MediaDevice(id: "99", name: "External output")]
        mock.settings.deviceFixtures[.audioOutput] = first
        let model = SettingsModel(backend: mock.settings)
        await model.loadDeviceChoices(for: [.audioOutput])
        let revision = model.revision, generation = model.deviceGeneration
        mock.settings.deviceFixtures[.audioOutput] = second
        XCTAssertEqual(model.deviceGeneration, generation + 1)
        XCTAssertEqual(model.revision, revision, "A hot-plug is not a settings change.")
        XCTAssertEqual(model.deviceChoices(for: .audioOutput), first, "The previous list stays while refreshing.")
        await model.loadDeviceChoices(for: [.audioOutput])
        XCTAssertEqual(model.deviceChoices(for: .audioOutput), second)
    }

    func testCameraSelectionKeepsExplicitIDAndOnlyAutoselectsSoleDevice() {
        let first = MediaDevice(id: "camera-uid-一", name: "Camera")
        let second = MediaDevice(id: "camera-other", name: "Other")
        XCTAssertEqual(MediaDevice.captureSelection(currentID: "", devices: []), "")
        XCTAssertEqual(MediaDevice.captureSelection(currentID: "", devices: [first]), first.id)
        XCTAssertEqual(MediaDevice.captureSelection(currentID: "", devices: [first, second]), "")
        XCTAssertEqual(MediaDevice.captureSelection(currentID: second.id, devices: [first]), second.id)
    }
}
