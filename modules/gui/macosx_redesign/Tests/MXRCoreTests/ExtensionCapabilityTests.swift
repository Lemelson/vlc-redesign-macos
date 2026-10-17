import Foundation
import MXRCore
import MXRMockBackend
import XCTest

final class ExtensionCapabilityTests: XCTestCase {
    @MainActor
    func testBackendWithoutAvailabilityDoesNotAdvertiseUnimplementedOperations() async {
        let backend = LegacyExtensionBackend()
        let model = ExtensionsModel(backend: backend)
        for operation in ExtensionOperation.allCases { XCTAssertFalse(model.availability(for: operation).isAvailable) }
        await model.searchAddons("")
        XCTAssertNotNil(model.catalogError)
        XCTAssertFalse(backend.didSearch)
    }

    @MainActor
    func testMockLocalInstallationRemovalAndActivationChangeModelState() async throws {
        let mock = MockBackend(scenario: .idle)
        let model = ExtensionsModel(backend: mock.extensions)
        XCTAssertTrue(model.availability(for: .searchCatalog).isAvailable)
        XCTAssertFalse(model.availability(for: .run).isAvailable, "Activatable mock extensions must retain their enable toggles")
        try await model.installExtension(at: URL(fileURLWithPath: "/tmp/local.lua"))
        let item = try XCTUnwrap(model.extensions.first { $0.id == "local" })
        model.setActivated(true, item)
        XCTAssertEqual(model.extensions.first?.isActivated, true)
        try await model.removeExtension(item)
        XCTAssertTrue(model.extensions.isEmpty)
    }
}

@MainActor private final class LegacyExtensionBackend: ExtensionsBackend {
    let extensions: [ExtensionInfo] = []
    var didSearch = false
    func activate(id: String) {}
    func deactivate(id: String) {}
    func menu(forExtension id: String) -> [ExtensionMenuItem] { [] }
    func triggerMenu(extensionID: String, itemID: UInt16) {}
    func searchAddons(_ text: String) async throws -> [AddonInfo] { didSearch = true; return [] }
    func installAddon(id: String) async throws {}
    func removeAddon(id: String) async throws {}
    func installExtension(fileURL: URL) async throws {}
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (ExtensionsEvent) -> Void) {}
}
