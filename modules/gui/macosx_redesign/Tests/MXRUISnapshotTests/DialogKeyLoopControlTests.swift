import AppKit
import SwiftUI
import XCTest
@testable import MXRCore
@testable import MXRUI

/// Positive control for `DialogKeyLoopTests`: that test sends Tab with
/// `window.sendEvent` to a window that is never ordered on screen and asserts the
/// field behind the scrim never gets focus. That assertion would also hold if Tab
/// were never delivered at all. This test uses the same window, view stack and event
/// path without a dialog and proves Tab does move focus between two fields, so the
/// isolation test is not vacuous.
@MainActor
final class DialogKeyLoopControlTests: XCTestCase {
    func testTabDeliveredLikeTheIsolationTestMovesFocusWithoutADialog() async throws {
        _ = NSApplication.shared
        let app = AppModel.mock(.idle)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.autorecalculatesKeyViewLoop = true
        let host = NSHostingView(rootView: VStack {
            TextField("First", text: .constant("")).frame(width: 200)
            TextField("Second", text: .constant("")).frame(width: 200)
            Spacer()
        }
        .frame(width: 900, height: 700)
        .mxrDialogPresentation()
        .appModel(app))
        window.contentView = host
        func settle() async throws { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(200)) }
        func fields() -> [NSTextField] {
            func collect(_ view: NSView) -> [NSTextField] {
                ((view as? NSTextField).map { $0.isEditable ? [$0] : [] } ?? []) + view.subviews.flatMap(collect)
            }
            return collect(host)
        }
        func focused() -> NSTextField? {
            if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor { return editor.delegate as? NSTextField }
            return window.firstResponder as? NSTextField
        }
        try await settle()
        let both = fields()
        XCTAssertEqual(both.count, 2)
        let first = try XCTUnwrap(both.first)
        XCTAssertTrue(window.makeFirstResponder(first))
        XCTAssertTrue(focused() === first)

        let tab = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                 context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48))
        window.sendEvent(tab)
        try await settle()
        let moved = try XCTUnwrap(focused(), "Tab sent with window.sendEvent reaches the first responder")
        XCTAssertFalse(moved === first, "Tab moves focus to the next field when no dialog is open")
        XCTAssertTrue(both.contains { $0 === moved })
        window.close()
    }
}
