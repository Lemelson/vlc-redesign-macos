import Foundation
@testable import MXRCore
import XCTest

/// Customize edits are undoable inside the session (live run 2: Edit ▸ Undo stayed grey).
@MainActor
final class LayoutUndoTests: XCTestCase {
    func testDraftEditsUndoAndRedoAndEndWithTheSession() throws {
        let store = LayoutStore(location: .inMemory)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        store.undoManager = undoManager
        store.beginEditing(profileID: "p", kind: .video)
        let start = try XCTUnwrap(store.draft)

        func edit(_ name: String, _ change: (inout PlayerLayout) -> Void) {
            undoManager.beginUndoGrouping()
            store.updateDraft(actionName: name, change)
            undoManager.endUndoGrouping()
        }
        edit("Add Favorite") { $0.insert(LayoutItem(.favorite), in: .top, at: 1) }
        let added = try XCTUnwrap(store.draft)
        edit("Remove Favorite") { layout in layout.remove(layout.top[1].id) }
        XCTAssertEqual(undoManager.undoActionName, "Remove Favorite")

        undoManager.undo()
        XCTAssertEqual(store.draft, added)
        undoManager.undo()
        XCTAssertEqual(store.draft, start)
        XCTAssertFalse(undoManager.canUndo)
        undoManager.redo()
        XCTAssertEqual(store.draft, added)
        XCTAssertEqual(undoManager.undoActionName, "Add Favorite")

        store.updateDraft(actionName: "No change") { _ in }
        XCTAssertEqual(undoManager.undoActionName, "Add Favorite", "an edit that changes nothing is not an undo step")

        store.cancelEditing()
        XCTAssertFalse(undoManager.canUndo, "Cancel ends the session's undo history")
        XCTAssertFalse(undoManager.canRedo)
        store.beginEditing(profileID: "p", kind: .video)
        XCTAssertEqual(store.draft, start)
        XCTAssertFalse(undoManager.canUndo)
    }
}
