import XCTest
@testable import MXRCore
import MXRMockBackend

/// LIVE (live2 D-disabled-submenus): behind Settings every menu-bar row is grey, Keyboard
/// Shortcuts… included (D040). The menu bar's enabled state and its action both go through
/// ``AppModel/canPerform(_:)``. Only Settings' own Edit Keyboard Shortcuts button swaps the dialogs.
@MainActor
final class KeyboardShortcutsBehindSettingsTests: XCTestCase {
    func testMenuCommandIsOffBehindSettings() {
        let app = MockBackend(scenario: .playingMovie).makeAppModel(clockTicks: false)
        XCTAssertTrue(app.canPerform(.keyboardShortcuts))
        app.perform(.settings)
        XCTAssertEqual(app.interface.sheet, .settings(categoryID: nil))
        XCTAssertFalse(app.canPerform(.keyboardShortcuts), "App ▸ / Help ▸ Keyboard Shortcuts… must be grey behind Settings")
        app.perform(.keyboardShortcuts)
        XCTAssertEqual(app.interface.sheet, .settings(categoryID: nil), "the menu bar must not replace Settings")
        XCTAssertTrue(app.canPerform(.quit))
    }

    func testSettingsButtonStillOpensShortcutsAndReturns() throws {
        let app = MockBackend(scenario: .playingMovie).makeAppModel(clockTicks: false)
        app.perform(.settings)
        app.settings.selectedCategoryID = "controls"
        let edit = try XCTUnwrap(app.settings.catalog.allRows.first { $0.action == "edit-shortcuts" })
        app.settings.perform(edit)
        XCTAssertEqual(app.interface.sheet, .keyboardShortcuts)
        app.interface.dismissSheet()
        XCTAssertEqual(app.interface.sheet, .settings(categoryID: "controls"))
    }
}
