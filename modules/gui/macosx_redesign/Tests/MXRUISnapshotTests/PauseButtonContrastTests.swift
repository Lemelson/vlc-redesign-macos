import MXRDesign
@testable import MXRUI
import SwiftUI
import XCTest

/// B-11: the pause button's two-tone glyph stays legible on its surface under Increase Contrast.
final class PauseButtonContrastTests: XCTestCase {
    func testGlyphHalvesKeepThreeToOneOnThePauseFill() {
        for scheme in [ColorScheme.dark, .light] {
            let fill = PauseButtonFill.value(scheme: scheme)
            XCTAssertEqual(fill, Theme.Color.fgA3.value(scheme: scheme), "The surface keeps Figma FG/A3")
            for contrast in [ColorSchemeContrast.standard, .increased] {
                for glyph in [Theme.Color.fgB1, Theme.Color.bgB1] {
                    let ratio = ThemeContrastTests.contrast(glyph.value(scheme: scheme, contrast: contrast), fill)
                    XCTAssertGreaterThanOrEqual(ratio, 3, "\(scheme) \(contrast): \(ratio)")
                }
            }
        }
    }
}
