import AppKit
import Foundation
import MXRCore
import MXRMockBackend
@testable import MXRUI
import SwiftUI
import XCTest

/// F-08: while a dialog is up the controls behind it leave the key-view loop; the guard decides
/// "inside the dialog" by membership, not by geometry, and Tab from a dialog's own field never lands
/// in a field behind the scrim, even one lying under the dialog.
@MainActor
final class DialogKeyLoopGuardTests: XCTestCase {
    private struct Fixture {
        let window: NSWindow
        let host: NSView
        let app: AppModel
    }

    /// A 900×700 window whose only background text field sits in the middle, under the dialog.
    private func makeFixture() throws -> Fixture {
        _ = NSApplication.shared
        let app = AppModel.mock(.idle)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: ZStack {
            TextField("Search behind", text: .constant("")).frame(width: 200)
        }
        .frame(width: 900, height: 700)
        .mxrDialogPresentation()
        .appModel(app))
        window.contentView = host
        return Fixture(window: window, host: host, app: app)
    }

    private func settle(_ fixture: Fixture) async throws {
        fixture.host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
    }

    private func editableFields(in view: NSView) -> [NSTextField] {
        var fields: [NSTextField] = []
        if let field = view as? NSTextField, field.isEditable { fields.append(field) }
        for subview in view.subviews { fields += editableFields(in: subview) }
        return fields
    }

    private func guardView(in view: NSView) -> DialogKeyLoopGuard.GuardView? {
        if let found = view as? DialogKeyLoopGuard.GuardView { return found }
        return view.subviews.lazy.compactMap { self.guardView(in: $0) }.first
    }

    private func focusedField(_ window: NSWindow) -> NSView? {
        if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor { return editor.delegate as? NSView }
        return window.firstResponder as? NSView
    }

    func testFieldBehindTheDialogIsOutsideEvenUnderTheDialogRectangle() async throws {
        let fixture = try makeFixture()
        defer { fixture.window.close() }
        try await settle(fixture)
        let behind = try XCTUnwrap(editableFields(in: fixture.host).first)

        fixture.app.interface.present(.newPlaylist)
        try await settle(fixture)
        let guardView = try XCTUnwrap(guardView(in: fixture.host))
        let dialogFields = editableFields(in: fixture.host).filter { $0 !== behind }
        let dialogField = try XCTUnwrap(dialogFields.first, "New Playlist has a name field")

        // The premise: the field behind lies under the dialog's rectangle (what fooled the old
        // geometric test), so only membership can tell the two apart.
        let dialogRect = guardView.convert(guardView.bounds, to: nil)
        let behindRect = behind.convert(behind.bounds, to: nil)
        XCTAssertTrue(dialogRect.contains(CGPoint(x: behindRect.midX, y: behindRect.midY)), "dialog \(dialogRect), behind \(behindRect)")

        XCTAssertFalse(guardView.isInside(behind), "the field behind the scrim is not part of the dialog")
        XCTAssertTrue(guardView.isInside(dialogField), "the dialog's own field is")
    }

    func testTabFromTheDialogFieldNeverReachesTheFieldBehind() async throws {
        let fixture = try makeFixture()
        defer { fixture.window.close() }
        try await settle(fixture)
        let behind = try XCTUnwrap(editableFields(in: fixture.host).first)
        fixture.app.interface.present(.newPlaylist)
        try await settle(fixture)
        let guardView = try XCTUnwrap(guardView(in: fixture.host))
        let dialogField = try XCTUnwrap(editableFields(in: fixture.host).first { $0 !== behind })
        let window = fixture.window
        // The fallback for a field that appears behind the dialog after it opened: such a field
        // has not been taken out of the key loop yet.
        behind.refusesFirstResponder = false

        for backwards in [false, true, false, true] {
            XCTAssertTrue(window.makeFirstResponder(dialogField))
            // What AppKit does for Tab / Shift-Tab: the next key view in the window's loop.
            if backwards { window.selectKeyView(preceding: dialogField) } else { window.selectKeyView(following: dialogField) }
            // What the guard's key monitor does right after it.
            guardView.keepFocusInside(backwards: backwards)
            XCTAssertFalse(focusedField(window) === behind, "Tab (backwards: \(backwards)) stays out of the field behind the scrim")
        }

        // Positive control: the window's own key loop does lead from the dialog into the field
        // behind, so the assertion above depends on the guard.
        var reachedBehind = false
        var view: NSView = dialogField
        for _ in 0..<8 {
            guard let next = view.nextValidKeyView, next !== dialogField else { break }
            if next === behind { reachedBehind = true; break }
            view = next
        }
        XCTAssertTrue(reachedBehind, "AppKit's key-view loop includes the field behind the dialog")
    }

    /// The fields from `start` along the window's key-view loop (what Tab visits), at most `limit`.
    private func keyLoop(from start: NSView, limit: Int = 32) -> [NSView] {
        var loop: [NSView] = []
        var view = start
        while loop.count < limit, let next = view.nextValidKeyView, next !== start, !loop.contains(where: { $0 === next }) {
            loop.append(next)
            view = next
        }
        return loop
    }

    /// F-08 at the source: while a dialog is up the field behind it is not a key view at all, so
    /// Tab cannot reach it, without any correction by the
    /// guard's key monitor. It gets the keyboard back when the dialog closes, also after one dialog
    /// replaced another.
    func testControlsBehindTheDialogLeaveTheKeyLoopUntilItCloses() async throws {
        let fixture = try makeFixture()
        defer { fixture.window.close() }
        try await settle(fixture)
        let window = fixture.window
        let behind = try XCTUnwrap(editableFields(in: fixture.host).first)
        XCTAssertTrue(behind.acceptsFirstResponder, "without a dialog the field takes the keyboard")

        fixture.app.interface.present(.newPlaylist)
        try await settle(fixture)
        let dialogField = try XCTUnwrap(editableFields(in: fixture.host).first { $0 !== behind })
        XCTAssertTrue(dialogField.acceptsFirstResponder, "the dialog's own field stays a key view")
        XCTAssertFalse(behind.acceptsFirstResponder, "the field behind the scrim leaves the key loop")
        XCTAssertFalse(behind.canBecomeKeyView, "the field behind the scrim is no key view")
        XCTAssertTrue(window.makeFirstResponder(dialogField))
        XCTAssertFalse(keyLoop(from: dialogField).contains { $0 === behind }, "Tab from the dialog never visits the field behind")
        for backwards in [false, true] {
            XCTAssertTrue(window.makeFirstResponder(dialogField))
            if backwards { window.selectKeyView(preceding: dialogField) } else { window.selectKeyView(following: dialogField) }
            XCTAssertFalse(focusedField(window) === behind, "AppKit's own Tab (backwards: \(backwards)) stays in the dialog")
        }

        // One dialog replacing another keeps the background out until the last one closes.
        fixture.app.interface.present(.about)
        try await settle(fixture)
        XCTAssertFalse(behind.acceptsFirstResponder, "still out while the next dialog is up")

        fixture.app.interface.dismissSheet()
        try await settle(fixture)
        XCTAssertNil(guardView(in: fixture.host), "the dialog is gone")
        XCTAssertTrue(behind.acceptsFirstResponder, "the field behind is a key view again")
        XCTAssertTrue(window.makeFirstResponder(behind), "and takes the keyboard again")
    }
}
