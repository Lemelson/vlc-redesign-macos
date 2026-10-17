import Foundation
import MXRBridgeAPI
import MXRCore
@testable import MXRVLCBackend
import XCTest

final class ExtensionAvailabilityTests: XCTestCase {
    @MainActor
    func testUnavailableNativeOperationsNeverReachTransport() async {
        let transport = ExtensionAvailabilityTransport()
        let model = ExtensionsModel(backend: VLCExtensionsBackend(transport: transport))
        let addon = AddonInfo(id: "catalog-item", name: "Catalog item", summary: "")
        let item = ExtensionInfo(id: "stock", title: "Stock extension")
        await model.searchAddons("")
        do { try await model.install(addon); XCTFail("Unsupported catalog installation should fail") } catch {}
        do { try await model.remove(addon); XCTFail("Unsupported catalog removal should fail") } catch {}
        do { try await model.installExtension(at: URL(fileURLWithPath: "/tmp/test.lua")); XCTFail("Unavailable local installation should fail") } catch {}
        do { try await model.removeExtension(item); XCTFail("Unavailable local removal should fail") } catch {}
        do { try await model.runExtension(item); XCTFail("Unavailable on-demand execution should fail") } catch {}
        model.setActivated(true, item)
        await Task.yield()
        XCTAssertTrue(transport.requests.isEmpty, "Unavailable UI actions must not invoke native operations")
        XCTAssertEqual(model.catalogError, ExtensionOperation.searchCatalog.unavailableReason)
        XCTAssertEqual(model.actionError, ExtensionOperation.activate.unavailableReason)
        XCTAssertFalse(model.isSearching)
    }

    @MainActor
    func testTriggerOnlyExtensionRunsOnceWithoutEnablingAndStopsWhenUnavailable() async throws {
        let transport = ExtensionAvailabilityTransport()
        transport.state = ["supportsActivation": true, "items": [
            ["id": "run-once", "title": "Run once", "available": true, "triggerOnly": true],
            ["id": "activatable", "title": "Activatable", "available": true, "triggerOnly": false]]]
        let backend = VLCExtensionsBackend(transport: transport)
        let model = ExtensionsModel(backend: backend)
        let item = try XCTUnwrap(model.extensions.first { $0.id == "run-once" })
        XCTAssertFalse(model.availability(for: .activate, extensionID: item.id).isAvailable)
        XCTAssertTrue(model.availability(for: .run, extensionID: item.id).isAvailable)
        XCTAssertFalse(model.availability(for: .run, extensionID: "activatable").isAvailable)
        XCTAssertFalse(model.availability(for: .run, extensionID: "missing").isAvailable)
        try await model.runExtension(item)
        XCTAssertEqual(transport.requests.map(\.name), ["activate"])
        XCTAssertEqual(transport.requests.first?.arguments["id"] as? String, item.id)
        XCTAssertFalse(model.extensions.first?.isActivated ?? true)
        transport.state["supportsActivation"] = false
        do { try await model.runExtension(item); XCTFail("A capability loss must block the next run") } catch {}
        XCTAssertEqual(transport.requests.count, 1)
    }

    @MainActor
    func testLiveAvailabilityEnablesLocalOperationsAndProtectsStockAndTriggerOnlyScripts() async throws {
        let transport = ExtensionAvailabilityTransport()
        let backend = VLCExtensionsBackend(transport: transport)
        let model = ExtensionsModel(backend: backend)
        XCTAssertFalse(model.availability(for: .installLocal).isAvailable)
        transport.state = ["supportsInstall": true, "supportsRemove": true, "supportsActivation": true,
                           "supportsSearchCatalog": false, "items": [
                            ["id": "stock", "title": "Stock", "available": true, "removable": false],
                            ["id": "user", "title": "User", "available": true, "removable": true],
                            ["id": "trigger", "title": "Run once", "available": true, "triggerOnly": true, "removable": false]]]
        XCTAssertTrue(model.availability(for: .installLocal).isAvailable, "Live flags must supersede frozen startup capabilities")
        XCTAssertTrue(model.availability(for: .removeLocal, extensionID: "user").isAvailable)
        XCTAssertFalse(model.availability(for: .removeLocal, extensionID: "stock").isAvailable)
        XCTAssertFalse(model.availability(for: .removeLocal, extensionID: "missing").isAvailable)
        XCTAssertTrue(model.availability(for: .activate, extensionID: "stock").isAvailable)
        XCTAssertEqual(model.availability(for: .activate, extensionID: "trigger").reason, "This extension runs on demand and cannot be enabled.")
        try await model.installExtension(at: URL(fileURLWithPath: "/tmp/user.lua"))
        XCTAssertEqual(transport.requests.first?.arguments["url"] as? String, "file:///tmp/user.lua")
        do { try await model.removeExtension(ExtensionInfo(id: "stock", title: "Stock")); XCTFail("Stock scripts must remain protected") }
        catch { XCTAssertTrue(error.localizedDescription.contains("user extension folder")) }
        try await model.removeExtension(ExtensionInfo(id: "user", title: "User"))
        XCTAssertEqual(transport.requests.map(\.name), ["installExtension", "removeExtension"])
        transport.state["supportsInstall"] = false
        transport.state["localUnavailableReason"] = "The user extension folder is not writable."
        do { try await backend.installExtension(fileURL: URL(fileURLWithPath: "/tmp/user.lua")); XCTFail("Availability can change while Settings is open") }
        catch { XCTAssertEqual(error.localizedDescription, "The user extension folder is not writable.") }
        XCTAssertEqual(transport.requests.count, 2)
    }

    @MainActor
    func testCatalogFailureIsShownAsAnErrorAndNativeAddonMutationsStayUnavailable() async {
        let transport = ExtensionAvailabilityTransport()
        transport.state = ["supportsSearchCatalog": true]
        transport.failure = BackendOperationError.invalidInput("The catalog connection failed.")
        let model = ExtensionsModel(backend: VLCExtensionsBackend(transport: transport))
        await model.searchAddons("subtitles")
        XCTAssertEqual(model.catalogError, "The catalog connection failed.")
        XCTAssertTrue(model.addonResults.isEmpty)
        XCTAssertFalse(model.isSearching)
        XCTAssertFalse(model.availability(for: .installAddon).isAvailable)
        XCTAssertFalse(model.availability(for: .removeAddon).isAvailable)
        XCTAssertEqual(transport.requests.map(\.name), ["searchAddons"])
    }
}

@MainActor private final class ExtensionAvailabilityTransport: VLCServiceTransport {
    struct Request { let name: String; let arguments: [String: Any] }
    var requests: [Request] = []
    var state: [String: Any] = [:]
    var failure: Error?
    // Startup flags deliberately stay false; live extension snapshots decide availability.
    let capabilities: [String: Any] = ["extensions": false, "extensionInstall": false, "extensionRemove": false]
    func snapshot(for service: MXRBridgeService) -> [String: Any] { let service = service.rawValue; return service == "extensions" ? state : [:] }
    func perform(_ command: MXRBridgeCommand, service: MXRBridgeService, arguments: [String: Any]) throws { let command = command.rawValue; let service = service.rawValue;}
    func request(_ request: MXRBridgeRequest, service: MXRBridgeService, arguments: [String: Any]) async throws -> [String: Any] { let request = request.rawValue; let service = service.rawValue;
        requests.append(Request(name: request, arguments: arguments))
        if let failure { throw failure }
        return state
    }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (MXRBridgeService) -> Void) {}
    func log(_ error: Error) {}
    func report(_ error: Error) {}
}
