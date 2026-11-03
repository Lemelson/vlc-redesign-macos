import XCTest
@testable import MXRCore
import MXRMockBackend

/// LIVE (live2 E-arrow-keys): with the compact library list focused, ↓ ran VLC's nav-down (a volume
/// step) instead of moving the selection. The window key monitor runs before SwiftUI and only knew
/// about the queue and bookmark lists. The library now reports its focus too, and the monitor's gate
/// (``WindowKeyPolicy``) reads the combined ``InterfaceModel/listHasKeyboardFocus``.
@MainActor
final class WindowKeyPolicyTests: XCTestCase {
    private func binding(_ text: String) throws -> KeyBinding { try XCTUnwrap(KeyBinding(vlcString: text)) }

    private func monitorTakes(_ text: String, _ app: AppModel) throws -> Bool {
        WindowKeyPolicy.monitorHandles(try binding(text), hasSheet: app.interface.sheet != nil, isCapturing: false,
                                       isEditing: false, listFocused: app.interface.listHasKeyboardFocus)
    }

    func testFocusedLibraryListKeepsItsKeys() throws {
        let app = MockBackend(scenario: .playingMovie).makeAppModel(clockTicks: false)
        for key in ["Down", "Up", "Left", "Right", "Enter"] {
            XCTAssertTrue(try monitorTakes(key, app), "\(key) is VLC's hotkey while no list has the keyboard")
        }
        app.interface.libraryListHasKeyboardFocus = true
        XCTAssertTrue(app.interface.listHasKeyboardFocus)
        for key in ["Down", "Up", "Left", "Right", "Enter", "Delete", "Backspace", "Alt+Down"] {
            XCTAssertFalse(try monitorTakes(key, app), "\(key) stays with the focused library list or grid")
        }
        // Space, ⌘↓ (volume) and the other hotkeys keep working with the list focused.
        for key in ["Space", "Command+Down", "Command+Right", "Command+Alt+Right", "s"] {
            XCTAssertTrue(try monitorTakes(key, app), "\(key) is still VLC's")
        }
        app.interface.libraryListHasKeyboardFocus = false
        XCTAssertTrue(try monitorTakes("Down", app))
    }

    func testQueueFocusStillCountsAndDialogsTakeEverything() throws {
        let app = MockBackend(scenario: .playingMovie).makeAppModel(clockTicks: false)
        app.interface.panelListHasKeyboardFocus = true
        XCTAssertFalse(try monitorTakes("Down", app))
        app.interface.panelListHasKeyboardFocus = false
        app.perform(.settings)
        XCTAssertFalse(try monitorTakes("Space", app), "a dialog's own key loop gets every key")
        XCTAssertFalse(WindowKeyPolicy.monitorHandles(try binding("Space"), hasSheet: false, isCapturing: false,
                                                      isEditing: true, listFocused: false), "a text field keeps its keys")
        XCTAssertFalse(WindowKeyPolicy.monitorHandles(try binding("Down"), hasSheet: false, isCapturing: true,
                                                      isEditing: false, listFocused: false), "the recorder keeps its keys")
    }
}
