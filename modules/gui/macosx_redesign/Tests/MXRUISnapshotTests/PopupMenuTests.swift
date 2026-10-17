import AppKit
import MXRCore
@testable import MXRDesign
import MXRMockBackend
@testable import MXRUI
import XCTest

/// D024–D026: the design-system popup's placement, the menus built on it, and Mac shortcuts.
@MainActor
final class PopupMenuTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CGSize(width: 265, height: 296)

    // MARK: Placement

    func testDropsUnderTheAnchorLeftAligned() {
        let anchor = CGRect(x: 100, y: 800, width: 28, height: 28)
        let fit = MXRPopupPlacement.below(.leading, gap: 6).fit(size: size, anchor: anchor, visible: screen)
        XCTAssertEqual(fit.frame.minX, 100)
        XCTAssertEqual(fit.frame.maxY, 794)
        XCTAssertEqual(fit.slide, .down)
        XCTAssertFalse(fit.isClipped)
    }

    func testFlipsAboveNearTheScreenBottom() {
        let anchor = CGRect(x: 100, y: 40, width: 28, height: 28)
        let fit = MXRPopupPlacement.below().fit(size: size, anchor: anchor, visible: screen)
        XCTAssertEqual(fit.frame.minY, anchor.maxY + Theme.Popup.anchorGap)
        XCTAssertEqual(fit.slide, .up)
    }

    func testAwayFromWindowEdgeOpensAboveInTheLowerHalf() {
        let window = CGRect(x: 0, y: 0, width: 960, height: 540)
        let bottomButton = CGRect(x: 900, y: 20, width: 24, height: 24)
        XCTAssertEqual(MXRPopupPlacement.awayFromWindowEdge().resolved(anchor: bottomButton, window: window), .above())
        let topButton = CGRect(x: 90, y: 506, width: 28, height: 28)
        XCTAssertEqual(MXRPopupPlacement.awayFromWindowEdge().resolved(anchor: topButton, window: window), .below())
    }

    func testContextMenuAtPointerOpensLeftAndShiftsUpAtScreenEdges() {
        let point = CGPoint(x: 1400, y: 100)
        let fit = MXRPopupPlacement.pointer(point).fit(size: size, anchor: CGRect(origin: point, size: .zero), visible: screen)
        XCTAssertEqual(fit.frame.maxX, point.x, "opens to the left of the pointer")
        XCTAssertEqual(fit.frame.minY, screen.minY + Theme.Popup.screenMargin, "shifted up to stay on screen")
    }

    func testSubmenuLinesUpWithItsRowAndFlipsLeftAtTheRightEdge() {
        let parent = CGRect(x: 200, y: 300, width: 375, height: 585)
        let row = CGRect(x: 204, y: 300 + 585 - 341 - 48, width: 367, height: 48)
        let inset = MXRPopupStyle.contextMenu.padding.top
        let right = MXRPopupPlacement.beside(row: row, parentCard: parent, topInset: inset)
            .fit(size: CGSize(width: 265, height: 249), anchor: row, visible: screen)
        XCTAssertEqual(right.frame.minX, parent.maxX + Theme.Popup.submenuGap)
        XCTAssertEqual(right.frame.maxY - inset, row.maxY, "first submenu row aligned with the parent row (Figma Profiles)")
        let crowded = CGRect(x: 1100, y: 300, width: 300, height: 585)
        let left = MXRPopupPlacement.beside(row: row.offsetBy(dx: 900, dy: 0), parentCard: crowded, topInset: inset)
            .fit(size: CGSize(width: 265, height: 249), anchor: row, visible: screen)
        XCTAssertEqual(left.frame.maxX, crowded.minX - Theme.Popup.submenuGap)
        XCTAssertEqual(left.slide, .left)
    }

    func testFitsOnASecondScreenWithNegativeCoordinates() {
        let second = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        let anchor = CGRect(x: -1910, y: 260, width: 28, height: 28)
        let fit = MXRPopupPlacement.below().fit(size: size, anchor: anchor, visible: second)
        XCTAssertTrue(second.contains(fit.frame), "\(fit.frame) leaves \(second)")
        XCTAssertEqual(fit.slide, .up)
    }

    func testTallMenusAreClippedToTheScreenAndScroll() {
        let fit = MXRPopupPlacement.pointer(CGPoint(x: 10, y: 890))
            .fit(size: CGSize(width: 265, height: 2000), anchor: .zero, visible: screen)
        XCTAssertTrue(fit.isClipped)
        XCTAssertEqual(fit.frame.height, screen.height - 2 * Theme.Popup.screenMargin)
    }

    func testDropdownListCoversTheFieldWithTheSelectedRowOnIt() {
        // Figma `Setting Preset`: the sixth option sits on the 42 pt field, the list opens upward.
        let field = CGRect(x: 21, y: 400, width: 364, height: 42)
        let style = MXRPopupStyle.preset
        let rowOffset = style.padding.top + 5 * (style.row.height + style.rowSpacing) - Theme.Metric.Controls.dropdown.padding.top
        let fit = MXRPopupPlacement.overField(rowOffset: rowOffset).fit(size: CGSize(width: 364, height: 242), anchor: field, visible: screen)
        XCTAssertEqual(fit.frame.minY, field.minY, accuracy: 0.5)
        XCTAssertEqual(fit.frame.maxY, field.maxY + 200, accuracy: 0.5)
    }

    // MARK: Menus

    func testAppMenuFollowsFigmaOrderWithMacGlyphs() {
        let app = AppModel.mock(.pausedEpisode)
        let items = MXRPlayerMenus.appMenu(app)
        XCTAssertEqual(items.map(\.title), ["Open File(s)", "Open Folder", "Open Network Stream", "Open Disc",
                                            "Open Capture Device", "Convert", "Open Recent", "",
                                            app.profiles.menuTitle, "Keyboard Shortcuts", "Customize Player",
                                            "Settings", "About VLC"])
        XCTAssertEqual(items[0].shortcut?.displayString, "⌘O")
        XCTAssertEqual(items[1].shortcut?.displayString, "⇧⌘O")
        XCTAssertEqual(items[11].shortcut?.displayString, "⌘,")
        XCTAssertNil(items[12].shortcut)
        XCTAssertTrue(items[6].isSubmenu && items[8].isSubmenu)
        XCTAssertEqual(app.shortcutText(for: .openFiles), "⌘O")
    }

    func testProfileSubmenuChecksTheCurrentProfileAndOffersNew() throws {
        let app = AppModel.mock(.pausedEpisode)
        let profile = try XCTUnwrap(MXRPlayerMenus.appMenu(app).first { $0.title == app.profiles.menuTitle }?.children)
        XCTAssertEqual(profile.filter(\.isChecked).map(\.title), [app.profiles.current.name])
        XCTAssertEqual(profile.last?.title, "New")
        XCTAssertTrue(profile.dropLast().last?.isSeparator == true)
    }

    func testVideoContextMenuMatchesFigmaAndBuildsSubmenusFromCommands() throws {
        let app = AppModel.mock(.pausedEpisode)
        let items = MXRPlayerMenus.videoContextMenu(app)
        XCTAssertEqual(items.filter { !$0.isSeparator }.map(\.title),
                       ["Play", "Stop", "Previous Item", "Next Item", "Record", "Hide UI", "Playback", "Video",
                        "Audio", "Subtitle", "More Settings", "Playlist", "Open Media", "Quit VLC"])
        XCTAssertEqual(items.first { $0.title == "Hide UI" }?.shortcut?.displayString, "⌘\\")
        let subtitle = try XCTUnwrap(items.first { $0.title == "Subtitle" }?.children)
        XCTAssertFalse(subtitle.contains { $0.title.hasSuffix("✓") }, "checks are row state, not text")
        let tracks = app.tracks.tracks(of: .subtitle)
        if !tracks.isEmpty { XCTAssertEqual(subtitle.filter(\.isChecked).count, 1) }
    }

    func testMoreSettingsSelectsATabWithoutClosingTheOpenSidebar() throws {
        let app = AppModel.mock(.pausedEpisode)
        app.interface.selectTab(.sidebar(.video))
        let more = try XCTUnwrap(MXRPlayerMenus.videoContextMenu(app).first { $0.title == "More Settings" }?.children)
        let video = try XCTUnwrap(more.first { $0.title == "Video" })
        XCTAssertTrue(video.isChecked)
        guard case .action(let action) = video.kind else { return XCTFail("Video is an action") }
        action()
        XCTAssertEqual(app.interface.rightPanel, .sidebar(.video))
    }

    func testSeparatorsAreTidied() {
        let items: [MXRMenuItem] = [.separator, MXRMenuItem("A") {}, .separator, .separator, MXRMenuItem("B") {}, .separator]
        XCTAssertEqual(items.tidiedSeparators.map(\.title), ["A", "", "B"])
    }
}
