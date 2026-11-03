import AppKit
import MXRCore
import MXRDesign
import MXRMockBackend
@testable import MXRUI
import SwiftUI
import XCTest

/// Live run 2 (group 9): in Customize Esc did nothing, Edit ▸ Undo stayed grey after an edit, several
/// bar tiles had no VoiceOver move/remove actions and the paused picture was cropped under the bars.
/// These drive the real window composition offscreen.
@MainActor
final class CustomizationKeyboardTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        windows.forEach { $0.close() }
        windows = []
    }

    /// Esc is Cancel: the key equivalent reaches the dialog's Cancel button without any focus in it.
    func testEscapeCancelsCustomizeAndDiscardsTheDraft() async throws {
        let app = AppModel.mock(.pausedEpisode)
        let saved = app.playerLayout
        app.beginCustomizing()
        let window = try await hostWindow(app)
        XCTAssertTrue(MXRLayoutDragPayload.tile(.favorite).place(in: .bottom(0), at: 2, app: app))

        XCTAssertTrue(window.performKeyEquivalent(with: try key("\u{1b}", keyCode: 53)), "Esc is handled by the dialog")
        try await settle(window)
        XCTAssertFalse(app.interface.isCustomizing, "Esc closes Customize like Cancel")
        XCTAssertEqual(app.playerLayout, saved, "Esc discards the draft")
    }

    /// ⌘Z / ⇧⌘Z (Edit ▸ Undo / Redo, the `undo:` / `redo:` actions the window answers) step through
    /// the session's edits.
    func testWindowUndoAndRedoStepThroughCustomizeEdits() async throws {
        let app = AppModel.mock(.pausedEpisode)
        app.beginCustomizing()
        let window = try await hostWindow(app)
        let undoManager = try XCTUnwrap(window.undoManager)
        XCTAssertTrue(app.layouts.undoManager === undoManager, "the store registers on the window's undo manager")
        XCTAssertFalse(undoManager.canUndo)

        let start = app.playerLayout
        let seek = try XCTUnwrap(start.bottom[0].first { $0.control == .seekBar })
        XCTAssertTrue(MXRLayoutDragPayload.placed(seek).moveToNewRow(app: app))
        let moved = app.playerLayout
        XCTAssertEqual(moved.bottom.count, 2)
        XCTAssertEqual(undoManager.undoMenuItemTitle, "Undo Move Seek Bar")

        window.perform(Selector(("undo:")), with: nil)
        XCTAssertEqual(app.playerLayout, start, "Undo puts the seek bar back")
        XCTAssertTrue(app.interface.isCustomizing, "Undo stays in Customize")
        window.perform(Selector(("redo:")), with: nil)
        XCTAssertEqual(app.playerLayout, moved, "Redo moves it again")

        app.endCustomizing(save: false)
        XCTAssertFalse(undoManager.canUndo, "nothing of the ended session stays undoable")
        XCTAssertFalse(undoManager.canRedo)
    }

    /// Every control on the bars is one element with the move/remove actions in edit mode.
    func testEveryBarTileExposesTheEditActions() async throws {
        enableAccessibilityTree()
        let app = AppModel.mock(.pausedEpisode)
        app.beginCustomizing()
        let window = try await hostWindow(app)
        let elements = Self.elements(try XCTUnwrap(window.contentView))
        let expected = ["Move to top bar", "Move to control bar", "Move to new row", "Remove from player"]
        let placed = app.playerLayout.allItems.map(\.control).filter { $0 != .logo && $0 != .spacer }
        var missing: [String] = []
        for control in placed {
            let label = "Move \(control.title)"
            let tile = elements.first { Self.value($0, "accessibilityLabel") as? String == label }
            let actions = (tile.flatMap { Self.value($0, "accessibilityCustomActions") } as? [NSAccessibilityCustomAction])?.map(\.name) ?? []
            if Set(actions) != Set(expected) { missing.append(control.title) }
        }
        XCTAssertEqual(missing, [], "tiles without the edit actions")
        let palette = elements.filter { (Self.value($0, "accessibilityCustomActions") as? [NSAccessibilityCustomAction])?
            .contains { $0.name == "Add to control bar" } == true }
        XCTAssertFalse(palette.isEmpty)
        XCTAssertEqual(Set(palette.compactMap { Self.value($0, "accessibilityRole") as? String }), [NSAccessibility.Role.button.rawValue],
                       "palette tiles are buttons, not AXUnknown")
    }

    /// Opening Customize keeps the picture between the bars (2107:5604: the video ends at the band,
    /// y 972), in the window's picture rect, so a fitted picture is never cropped under the bars.
    func testCustomizeKeepsThePictureBetweenTheBars() async throws {
        let app = AppModel.mock(.pausedEpisode)
        let probe = NSView()
        let window = try await hostWindow(app, size: CGSize(width: 960, height: 540), video: AnyView(VideoProbe(view: probe)))
        func pictureFrame() throws -> CGRect {
            let frame = probe.convert(probe.bounds, to: nil), height = try XCTUnwrap(window.contentView).bounds.height
            return CGRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
        }
        let before = try pictureFrame()
        app.beginCustomizing()
        try await settle(window)
        let during = try pictureFrame()
        let band = Theme.Metric.ControlBar.bar.height * CGFloat(MXRPlayerMetrics.customizeControlRows)
        XCTAssertEqual(during.minY, before.minY, accuracy: 0.5, "the picture's top stays below the top bar")
        XCTAssertEqual(during.minX, before.minX, accuracy: 0.5, "the picture keeps its sides")
        XCTAssertEqual(during.maxX, before.maxX, accuracy: 0.5, "the picture keeps its sides")
        XCTAssertEqual(during.maxY, 540 - band, accuracy: 0.5, "the picture ends at the new-row band")
        XCTAssertGreaterThanOrEqual(during.minY, Theme.Metric.Window.topBar.height, "nothing of the picture is under the top bar")
    }

    /// A palette that scrolls (a compact window) ends at a divider above the footer like every
    /// scrolling dialog body (S65, D035; parity S66 compact); one that fits draws none.
    func testOverflowingPaletteEndsAtADivider() async throws {
        func dividerRow(height: CGFloat) async throws -> Int {
            let app = AppModel.mock(.pausedEpisode)
            app.beginCustomizing()
            let size = CGSize(width: MXRCustomizationView.preferredSize.width, height: height)
            let host = NSHostingView(rootView: MXRCustomizationView().appModel(app).frame(width: size.width, height: size.height)
                .mxrNativeBackdropEnabled(false).environment(\.colorScheme, .dark))
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            host.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / size.width
            let y = Int(((height - Theme.Metric.dialogFooterHeight) * scale).rounded()) - 1
            let divider = Theme.Color.dividerDim.value(scheme: .dark, accent: .orange)
            // Count columns across the palette that draw the divider colour on the footer's top edge.
            return stride(from: rep.pixelsWide / 10, to: rep.pixelsWide * 9 / 10, by: 4).filter { x in
                (y...(y + 1)).contains { row in
                    guard let c = rep.colorAt(x: x, y: row)?.usingColorSpace(.sRGB) else { return false }
                    return abs(c.redComponent - divider.red) < 0.02 && abs(c.greenComponent - divider.green) < 0.02
                }
            }.count
        }
        let total = (MXRCustomizationView.preferredSize.width * 0.8 * 2 / 4).rounded(.down)
        let compact = try await dividerRow(height: 360)
        XCTAssertGreaterThan(Double(compact), Double(total) * 0.9, "a scrolling palette ends at a divider")
        let full = try await dividerRow(height: MXRCustomizationView.preferredSize.height)
        XCTAssertLessThan(Double(full), Double(total) * 0.1, "a palette that fits has no divider")
    }

    // MARK: Helpers

    private func hostWindow(_ app: AppModel, size: CGSize = CGSize(width: 1280, height: 720),
                            video: AnyView = AnyView(Color.red)) async throws -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        window.contentView = NSHostingView(rootView: MXRAppView(videoView: video).appModel(app))
        try await settle(window)
        return window
    }

    private func settle(_ window: NSWindow) async throws {
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func key(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                       windowNumber: windows.last?.windowNumber ?? 0, context: nil,
                                       characters: characters, charactersIgnoringModifiers: characters,
                                       isARepeat: false, keyCode: keyCode))
    }

    // SwiftUI AX nodes expose Objective-C selectors without conforming to the NSAccessibility protocol.
    private static func value(_ object: NSObject, _ method: String) -> Any? {
        let selector = NSSelectorFromString(method)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }

    private static func elements(_ object: Any) -> [NSObject] {
        guard let node = object as? NSObject else { return [] }
        return [node] + ((value(node, "accessibilityChildren") as? [Any]) ?? []).flatMap(elements)
    }
}

/// Stands in for the vout host: an AppKit view whose frame is the picture's.
private struct VideoProbe: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ view: NSView, context: Context) {}
}
