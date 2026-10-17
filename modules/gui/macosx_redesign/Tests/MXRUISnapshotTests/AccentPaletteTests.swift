import MXRDesign
import SwiftUI
import XCTest

final class AccentPaletteTests: XCTestCase {
    func testBlueSeekFillMatchesOnboardingException() {
        // Figma S70: Rectangle 11 (1925:9940), inside blue frame 1902:5245.
        let fill = Theme.Color.bgAccentBright.value(scheme: .dark, accent: .blue)
        XCTAssertEqual(fill.hexString, "#185DD3")
        XCTAssertEqual(fill.alpha, 0.30, accuracy: 0.000001)
    }

    func testOtherSeekFillsRetainTheirFigmaValues() {
        for accent in Theme.Accent.allCases where accent != .orange && accent != .blue {
            let fill = Theme.Color.bgAccentBright.value(scheme: .dark, accent: accent)
            XCTAssertEqual(fill.hexString, accent.swatch.hexString, "\(accent)")
            XCTAssertEqual(fill.alpha, 0.24, accuracy: 0.000001, "\(accent)")
        }
        let orange = Theme.Color.bgAccentBright.value(scheme: .dark, accent: .orange)
        XCTAssertEqual(orange.hexString, "#371F06")
        XCTAssertEqual(orange.alpha, 1)
    }
}
