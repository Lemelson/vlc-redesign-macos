import AppKit
import MXRCore
@testable import MXRDesign
import MXRMockBackend
@testable import MXRUI
import Observation
import XCTest

/// The menu bar's copy of the in-window menu rows (MXRNativeMenuMirror): enabled state that
/// AppKit's autoenabling cannot override, and open menus that follow their models.
@MainActor
final class NativeMenuMirrorTests: XCTestCase {
    @Observable final class Rows {
        var title = "A"
        var count = 1
        var opened = 0
    }

    /// AppKit's autoenabling enables every row with a submenu; the mirror's disabled submenu
    /// (Speed at a fixed rate, Audio Device with no devices) must stay disabled through updates.
    func testDisabledSubmenuRowStaysDisabledThroughAppKitUpdates() throws {
        var blocked = false
        var ran = 0
        let mirror = MXRNativeMenuMirror(isBlocked: { blocked })
        let menu = NSMenu(title: "Audio")
        mirror.mirror(menu) {
            MXRMenuItem.submenu("Speed", isEnabled: false) { MXRMenuItem("1×") {} }
            MXRMenuItem("Run") { ran += 1 }
            MXRMenuItem("Unavailable", isEnabled: false) { ran += 100 }
            MXRMenuItem.submenu("Audio Device") { MXRMenuItem("Built-in") {} }
        }
        mirror.menuNeedsUpdate(menu)
        menu.update()
        XCTAssertEqual(menu.items.map(\.title), ["Speed", "Run", "Unavailable", "Audio Device"])
        XCTAssertEqual(menu.items.map(\.isEnabled), [false, true, false, true])
        XCTAssertTrue(menu.items[0].hasSubmenu)

        choose(menu.items[1])
        choose(menu.items[2])
        XCTAssertEqual(ran, 1, "only the enabled row runs")

        // Behind a dialog every row waits (D040), also the enabled submenu.
        blocked = true
        mirror.menuNeedsUpdate(menu)
        menu.update()
        XCTAssertEqual(menu.items.map(\.isEnabled), [false, false, false, false])
        choose(menu.items[1])
        XCTAssertEqual(ran, 1)
    }

    /// An open menu follows its model at once (the popups re-evaluate their rows while shown):
    /// the same rows are patched in place, new rows rebuild it; a closed menu waits for AppKit.
    func testOpenMenuFollowsItsModelAndClosedMenuWaits() async throws {
        let state = Rows()
        let mirror = MXRNativeMenuMirror(isBlocked: { false })
        let menu = NSMenu(title: "Extensions")
        mirror.mirror(menu, rows: {
            (0..<state.count).map { index in MXRMenuItem("\(state.title)\(index)") {} }
        }, onOpen: { state.opened += 1 })
        mirror.menuNeedsUpdate(menu)
        mirror.menuWillOpen(menu)
        XCTAssertEqual(state.opened, 1, "opening asks for fresh contents")
        let first = try XCTUnwrap(menu.items.first)

        state.title = "B"
        await settle()
        XCTAssertEqual(menu.items.map(\.title), ["B0"])
        XCTAssertTrue(menu.items[0] === first, "same rows are patched, so the highlighted item stays")

        state.count = 2
        await settle()
        XCTAssertEqual(menu.items.map(\.title), ["B0", "B1"])

        mirror.menuDidClose(menu)
        state.title = "C"
        await settle()
        XCTAssertEqual(menu.items.map(\.title), ["B0", "B1"], "a closed menu is rebuilt when AppKit next asks")
        mirror.menuNeedsUpdate(menu)
        XCTAssertEqual(menu.items.map(\.title), ["C0", "C1"])
    }

    /// An extension's submenu reads its entries when it is built, not from the parent's last build.
    func testExtensionSubmenuReadsItsEntriesWhenItOpens() async throws {
        let backend = MockBackend(scenario: .playingMovie)
        let app = backend.makeAppModel(clockTicks: false)
        backend.extensions.seedSamples()
        let mirror = MXRNativeMenuMirror(isBlocked: { false })
        let menu = NSMenu(title: "Extensions")
        mirror.mirror(menu) { MXRPlayerMenus.extensions(app) }
        mirror.menuNeedsUpdate(menu)
        XCTAssertFalse(menu.items[0].hasSubmenu)
        choose(menu.items[0]) // enable VLsub
        await settle()
        mirror.menuNeedsUpdate(menu)
        let submenu = try XCTUnwrap(menu.items[0].submenu)
        XCTAssertEqual(menu.items[0].state, .on)
        mirror.menuNeedsUpdate(submenu)
        XCTAssertEqual(submenu.items.map(\.title), ["Search subtitles…", "Settings", "", "Disable"])
    }

    /// Figma's file context menu (2404:13340) draws Mark as Watched with the two-tone check
    /// (state=selected, 4004:12348); the plain check has no artwork, which left the slot empty.
    func testMarkAsWatchedDrawsTheTwoToneCheck() throws {
        let app = AppModel.mock(.playingEpisode)
        app.library.navigate(to: .folder("wand-s01"))
        let media = try XCTUnwrap(app.library.entries.compactMap(\.media).first { !$0.isWatched })
        let rows = LibraryMenus.popupItems(for: .file(media), app: app, sheets: nil, rowIndex: nil)
        let row = try XCTUnwrap(rows.first { $0.title == "Mark as Watched" })
        let icon = try XCTUnwrap(row.icon)
        let drawn = MXRIcon.resolve(icon, tone: row.iconTone, state: row.iconState).variant
        XCTAssertFalse(drawn.layers.isEmpty, "the icon slot draws artwork")
        XCTAssertEqual(drawn.figmaNode, "4004:12348")
    }

    /// Sends the row's action as AppKit does, without AppKit's own enabled check, so the mirror's
    /// guard is what is tested.
    private func choose(_ item: NSMenuItem) {
        guard let action = item.action, let target = item.target as? NSObject else { return }
        _ = target.perform(action, with: item)
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}
