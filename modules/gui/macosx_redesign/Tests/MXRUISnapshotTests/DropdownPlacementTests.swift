import CoreGraphics
@testable import MXRDesign
import XCTest

/// S63 (D034): a settings or sidebar dropdown drops its list below the field, which stays visible
/// (Figma `Dropdown` 2372:8300, `sub filename` 6456:13892, video 17m31.0); the preset list and the
/// dialog header pop-ups (video 06m08.5) open over their field with the current row on it.
final class DropdownPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    /// A 364×48 field whose bottom edge is at y 600 (AppKit coordinates grow upwards).
    private let field = CGRect(x: 300, y: 600, width: 364, height: 48)
    private let list = CGSize(width: 364, height: 232)

    func testStandardListDropsBelowTheVisibleField() {
        for selectedRow in [0, 3] {
            let placement = MXRDropdownListPlacement.placement(style: .standard, selectedRow: selectedRow,
                                                               fieldInset: Theme.Metric.Controls.dropdown.padding.top,
                                                               overField: false)
            let fit = placement.fit(size: list, anchor: field, visible: screen)
            XCTAssertEqual(fit.frame.maxY, field.minY - Theme.Popup.anchorGap, accuracy: 0.5,
                           "row \(selectedRow): the list's top edge sits one anchor gap below the field")
            XCTAssertFalse(fit.frame.intersects(field), "row \(selectedRow): the list never covers the field")
            XCTAssertEqual(fit.frame.minX, field.minX, accuracy: 0.5)
        }
    }

    func testStandardListGoesAboveWhenThereIsNoRoomBelow() {
        let low = CGRect(x: 300, y: 120, width: 364, height: 48)
        let fit = MXRDropdownListPlacement.placement(style: .standard, selectedRow: 0, fieldInset: 2, overField: false)
            .fit(size: list, anchor: low, visible: screen)
        XCTAssertEqual(fit.frame.minY, low.maxY + Theme.Popup.anchorGap, accuracy: 0.5)
        XCTAssertFalse(fit.frame.intersects(low))
    }

    func testPopUpHeadersAndThePresetListOpenOverTheField() {
        for (style, overField) in [(MXRDropdownStyle.standard, true), (.preset, false)] {
            let fit = MXRDropdownListPlacement.placement(style: style, selectedRow: 2, fieldInset: 0, overField: overField)
                .fit(size: list, anchor: field, visible: screen)
            let row = style.list.padding.top + 2 * (style.list.row.height + style.list.rowSpacing)
            XCTAssertEqual(fit.frame.maxY - row, field.maxY, accuracy: 0.5,
                           "\(style): the current row lies on the field's row")
        }
    }
}
