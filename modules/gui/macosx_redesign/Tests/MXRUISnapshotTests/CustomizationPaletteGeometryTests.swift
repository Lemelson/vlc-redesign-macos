import MXRCore
import MXRDesign
import MXRMockBackend
@testable import MXRUI
import XCTest

/// S66/S67: the Customize Player tile grid follows Figma 6587:18867, a wrapping auto layout whose
/// tiles hug their content (icon box, 16 pt gap, label) and whose rows take their tallest tile.
@MainActor
final class CustomizationPaletteGeometryTests: XCTestCase {
    private typealias C = Theme.Metric.Customization

    /// The default video palette in 9 columns is Figma's body: rows at 128, 248, 368 and 484
    /// (heights 82, 82, 78, 65), so the whole body is the 489 pt frame 6587:18874.
    func testDefaultPaletteRowsMatchTheFigmaBody() {
        let app = AppModel.mock(.pausedEpisode)
        let controls = MXRCustomizationPalette.controls(for: app.playerLayout, kind: .video)
        let columns = Int(C.gridColumns)
        let rows = stride(from: 0, to: controls.count, by: columns).map {
            Array(controls[$0..<min($0 + columns, controls.count)])
        }
        XCTAssertEqual(rows.count, 4)
        // Inter's 16.94 pt body line is 17 pt in Figma's boxes, so allow a fraction of a point.
        for (height, figma) in zip(rows.map(MXRCustomizationPalette.rowHeight), [82.0, 82, 78, 65]) {
            XCTAssertEqual(height, figma, accuracy: 0.5)
        }
        XCTAssertEqual(MXRCustomizationPalette.contentHeight(rows: rows), C.body.height, accuracy: 0.5)
    }

    /// Labels sit 16 pt under the icon box, so a 28 pt box (Forward/Backward 15s, 6587:18894) puts
    /// the label at +44 and a 32 pt wrapper (Forward 10s, 6587:18888) at +48, as in Figma.
    func testLabelTopFollowsTheIconBoxHeight() {
        let labelTop = { (control: PlayerControl) in
            MXRCustomizationPalette.iconSize(for: control).height + Theme.Spacing.gap16
        }
        XCTAssertEqual(labelTop(.forward15), 44)
        XCTAssertEqual(labelTop(.backward15), 44)
        XCTAssertEqual(labelTop(.favorite), 44)
        XCTAssertEqual(labelTop(.forward10), 48)
        XCTAssertEqual(labelTop(.bookmark), 48)
        XCTAssertEqual(MXRCustomizationPalette.tileHeight(for: .forward15), 78, accuracy: 0.5)
        XCTAssertEqual(MXRCustomizationPalette.tileHeight(for: .stop), C.tile.height, accuracy: 0.5)
    }
}
