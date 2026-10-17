import AppKit
import Foundation
import MXRCore
import MXRMockBackend
@testable import MXRUI
import SwiftUI
import XCTest

/// The modal dialog host isolates what is behind the scrim from VoiceOver (D035 dialogs).
final class DialogIsolationTests: XCTestCase {
    @MainActor
    func testContentBehindADialogLeavesTheAccessibilityTree() async throws {
        let app = AppModel.mock(.idle)
        _ = NSApplication.shared
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXManualAccessibility"))
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let behind = Color.clear.frame(width: 200, height: 20)
            .mxrKeyboardFocusable()
            .accessibilityElement().accessibilityLabel("Seek marker behind the dialog")
        let host = NSHostingView(rootView: VStack { behind; Spacer() }
            .frame(width: 900, height: 700)
            .mxrDialogPresentation()
            .appModel(app))
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 700)

        func value(_ object: NSObject, _ method: String) -> Any? {
            let selector = NSSelectorFromString(method)
            guard object.responds(to: selector) else { return nil }
            return object.perform(selector)?.takeUnretainedValue()
        }
        func elements(_ object: Any) -> [NSObject] {
            guard let node = object as? NSObject else { return [] }
            return [node] + ((value(node, "accessibilityChildren") as? [Any]) ?? []).flatMap(elements)
        }
        func markerIsReachable() async throws -> Bool {
            host.layoutSubtreeIfNeeded()
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) { host.cacheDisplay(in: host.bounds, to: bitmap) }
            try await Task.sleep(for: .milliseconds(150))
            return elements(host).contains { (value($0, "accessibilityLabel") as? String) == "Seek marker behind the dialog" }
        }

        let reachableBefore = try await markerIsReachable()
        XCTAssertTrue(reachableBefore, "Without a dialog the control is in the tree")
        app.interface.present(.about)
        let reachableBehind = try await markerIsReachable()
        XCTAssertFalse(reachableBehind, "Behind a dialog it is hidden from VoiceOver")
        app.interface.dismissSheet()
        let reachableAfter = try await markerIsReachable()
        XCTAssertTrue(reachableAfter)
    }

    @MainActor func testMediaInfoLocationIsReadable() {
        XCTAssertEqual(MXRMediaInfoView.location(of: "file:///Volumes/Media/The%20Wand_S01E04.mp4"), "/Volumes/Media/The Wand_S01E04.mp4")
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/My Film.mkv")
        XCTAssertEqual(MXRMediaInfoView.location(of: home.absoluteString), "~/Movies/My Film.mkv")
        XCTAssertEqual(MXRMediaInfoView.location(of: "https://example.com/a%20b.mp4"), "https://example.com/a b.mp4")
    }
}

/// Tab never carries the keyboard from a dialog into a text field behind the scrim.
@MainActor
final class DialogKeyLoopTests: XCTestCase {
    func testTextFieldBehindADialogLosesAndNeverRegainsFocus() async throws {
        _ = NSApplication.shared
        let app = AppModel.mock(.idle)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: VStack { TextField("Search behind", text: .constant("")).frame(width: 200); Spacer() }
            .frame(width: 900, height: 700)
            .mxrDialogPresentation()
            .appModel(app))
        window.contentView = host
        // Never ordered on screen (unit tests must not present GUI): the window routes
        // key events to its first responder directly.
        func settle() async throws { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(200)) }
        func behindField() -> NSTextField? {
            func find(_ view: NSView) -> NSTextField? {
                if let field = view as? NSTextField, field.isEditable { return field }
                return view.subviews.lazy.compactMap(find).first
            }
            return find(host)
        }
        func behindHasFocus() -> Bool {
            guard let field = behindField() else { return false }
            if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor { return editor.delegate as? NSTextField === field }
            return window.firstResponder === field
        }
        try await settle()
        let field = try XCTUnwrap(behindField())
        XCTAssertTrue(window.makeFirstResponder(field)); XCTAssertTrue(behindHasFocus())

        app.interface.present(.about)
        try await settle()
        XCTAssertFalse(behindHasFocus(), "The field behind gives up the keyboard when a dialog opens")

        func tabs() async throws {
          for flags: NSEvent.ModifierFlags in [[], [], [.shift], [.shift]] {
            let tab = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                                                     context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48))
            window.sendEvent(tab)
            try await settle()
            XCTAssertFalse(behindHasFocus(), "Tab stays out of the field behind the scrim")
          }
        }
        try await tabs()
        app.interface.dismissSheet(); try await settle()
        // A dialog with its own text field: Tab cycles inside it. Start in the dialog's field, as
        // a user typing a name would, so each Tab really asks the key loop for the next view.
        app.interface.present(.newPlaylist); try await settle()
        func dialogField() -> NSTextField? {
            func find(_ view: NSView) -> NSTextField? {
                if let found = view as? NSTextField, found.isEditable, found !== field { return found }
                return view.subviews.lazy.compactMap(find).first
            }
            return find(host)
        }
        let nameField = try XCTUnwrap(dialogField(), "New Playlist shows its name field")
        XCTAssertTrue(window.makeFirstResponder(nameField), "The dialog's own field takes the keyboard")
        try await tabs()

        app.interface.dismissSheet()
        try await settle()
        XCTAssertTrue(window.makeFirstResponder(field), "Without a dialog the field takes focus again")
        window.close()
    }
}
