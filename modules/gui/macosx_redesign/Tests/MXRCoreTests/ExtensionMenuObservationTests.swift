import Foundation
import MXRCore
import Observation
import XCTest

/// An active extension can change its menu without any change to the extension list (the
/// bridge republishes the catalog when the script's menu() answers differently). A view that
/// shows the menu must redraw then, so reading a menu has to depend on the catalog.
final class ExtensionMenuObservationTests: XCTestCase {
    @MainActor
    func testReadingAMenuObservesACatalogChangeThatOnlyChangesTheMenu() throws {
        let backend = MenuChangingBackend()
        let model = ExtensionsModel(backend: backend)
        let ext = try XCTUnwrap(model.extensions.first)
        let redraws = RedrawCounter()
        withObservationTracking {
            XCTAssertEqual(model.menu(for: ext).map(\.title), ["First"])
        } onChange: { redraws.increment() }

        backend.menu = [ExtensionMenuItem(id: 1, title: "First"), ExtensionMenuItem(id: 2, title: "Second")]
        backend.publish()

        XCTAssertEqual(redraws.count, 1, "a menu-only catalog change must invalidate a view that shows the menu")
        XCTAssertEqual(model.menu(for: ext).map(\.title), ["First", "Second"])
    }
}

/// onChange runs synchronously in willSet, on the main actor here.
private final class RedrawCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}

@MainActor private final class MenuChangingBackend: ExtensionsBackend {
    let extensions = [ExtensionInfo(id: "menu", title: "Menu fixture", isActivated: true, hasMenu: true)]
    var menu = [ExtensionMenuItem(id: 1, title: "First")]
    private var handlers: [@MainActor (ExtensionsEvent) -> Void] = []
    func publish() { for handler in handlers { handler(.listChanged) } }
    func activate(id: String) {}
    func deactivate(id: String) {}
    func menu(forExtension id: String) -> [ExtensionMenuItem] { menu }
    func triggerMenu(extensionID: String, itemID: UInt16) {}
    func searchAddons(_ text: String) async throws -> [AddonInfo] { [] }
    func installAddon(id: String) async throws {}
    func removeAddon(id: String) async throws {}
    func installExtension(fileURL: URL) async throws {}
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (ExtensionsEvent) -> Void) { handlers.append(handler) }
}
