import AppKit
import MXRDesign
import SwiftUI
import XCTest

/// D032: text tokens stay readable on the surfaces they are drawn on, in both themes.
final class ThemeContrastTests: XCTestCase {
    private let texts: [(String, ThemeColor)] = [("fg1", Theme.Color.fg1), ("fg2", Theme.Color.fg2), ("fgA1", Theme.Color.fgA1)]
    private let surfaces: [(String, ThemeColor)] = [("bgB1", Theme.Color.bgB1), ("bgB2", Theme.Color.bgB2),
                                                    ("bgA1", Theme.Color.bgA1), ("bgA3", Theme.Color.bgA3)]

    func testBodyTextMeetsWCAGAAOnDialogSurfaces() {
        for scheme in [ColorScheme.dark, .light] {
            for (textName, text) in texts {
                for (surfaceName, surface) in surfaces {
                    let ratio = Self.contrast(text.value(scheme: scheme), surface.value(scheme: scheme))
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(textName) on \(surfaceName) (\(scheme)) is \(ratio):1")
                }
            }
        }
    }

    func testIncreasedContrastStrengthensSecondaryText() {
        for scheme in [ColorScheme.dark, .light] {
            XCTAssertEqual(Theme.Color.fgA3.value(scheme: scheme, contrast: .increased), Theme.Color.fgA1.value(scheme: scheme))
            XCTAssertEqual(Theme.Color.fgA2.value(scheme: scheme, contrast: .increased), Theme.Color.fgA2.value(scheme: scheme))
        }
    }

    /// AppKit paths (NSColor, `color(accent:)`) follow Increase Contrast like the SwiftUI path,
    /// and keep the standard values while it is off.
    func testIncreasedContrastReachesAppKitColors() throws {
        for (name, scheme) in [(NSAppearance.Name.darkAqua, ColorScheme.dark), (.aqua, .light)] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            for increased in [true, false] {
                var resolved: NSColor?
                appearance.performAsCurrentDrawingAppearance {
                    resolved = Theme.Color.fgA3.nsColor(accent: .orange, increasedContrast: { _ in increased })
                        .usingColorSpace(.sRGB)
                }
                let expected = (increased ? Theme.Color.fgA1 : Theme.Color.fgA3).value(scheme: scheme)
                XCTAssertEqual(try XCTUnwrap(resolved).redComponent, expected.red, accuracy: 0.002, "\(name) \(increased)")
            }
        }
        XCTAssertFalse(try XCTUnwrap(NSAppearance(named: .darkAqua)).mxrIsHighContrast)
    }

    /// The keyboard focus ring (fgA1) is drawn outside the control, on the bar or panel surface:
    /// opaque surfaces and the translucent chrome over black video, in both schemes.
    func testFocusIndicatorHasThreeToOneContrastOnChrome() {
        let video = Theme.RGBA(hex: 0x000000)
        for scheme in [ColorScheme.dark, .light] {
            var surfaces = [Theme.Color.bgA2, Theme.Color.bgB1, Theme.Color.bgA3].map { $0.value(scheme: scheme) }
            surfaces += [Theme.Color.bgA3Transparent, Theme.Color.bgB1Transparent].map { $0.value(scheme: scheme).composited(over: video) }
            for surface in surfaces {
                XCTAssertGreaterThanOrEqual(Self.contrast(Theme.Color.fgA1.value(scheme: scheme), surface), 3, "\(surface) (\(scheme))")
            }
        }
    }

    /// Player - Light draws the volume cone track and overlay with its own values (H-01).
    func testVolumeConeFollowsTheColorScheme() {
        XCTAssertNotEqual(Theme.Gradient.volumeConeTrack.value(scheme: .dark), Theme.Gradient.volumeConeTrack.value(scheme: .light))
        XCTAssertNotEqual(Theme.Gradient.volumeConeOverlay.value(scheme: .dark), Theme.Gradient.volumeConeOverlay.value(scheme: .light))
    }

    /// Reduce Transparency / Increase Contrast fill backdrops with the opaque form of the tint.
    func testTransparentStylesHaveOpaqueCounterparts() {
        XCTAssertEqual(Theme.Color.bgA3Transparent.opaqueCounterpart, Theme.Color.bgA3)
        XCTAssertEqual(Theme.Color.bgB1Transparent.opaqueCounterpart, Theme.Color.bgB1)
        XCTAssertEqual(Theme.Color.fgA1.opaqueCounterpart, Theme.Color.fgA1)
    }

    /// Placeholders and disabled text (fgA4) must read as secondary: lighter than body text on a light surface.
    func testLightPlaceholderIsSecondaryToBodyText() {
        let surface = Theme.Color.bgB1.value(scheme: .light)
        let placeholder = Self.contrast(Theme.Color.fgA4.value(scheme: .light), surface)
        let body = Self.contrast(Theme.Color.fgA1.value(scheme: .light), surface)
        XCTAssertLessThan(placeholder, body / 2, "Light fgA4 must be clearly dimmer than fgA1")
        XCTAssertGreaterThan(placeholder, 1.5, "Light fgA4 must stay visible")
    }

    /// App-defined colors (rawColors) must have their own light value where they draw chrome.
    func testAppDefinedChromeColorsFollowTheTheme() {
        for token in [Theme.Color.homeCard, Theme.Color.thumbPlaceholder, Theme.Color.swatchOutline] {
            XCTAssertNotEqual(token.value(scheme: .dark), token.value(scheme: .light))
        }
    }

    static func contrast(_ a: Theme.RGBA, _ b: Theme.RGBA) -> Double {
        let (la, lb) = (luminance(a, over: b), luminance(b, over: b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func luminance(_ color: Theme.RGBA, over background: Theme.RGBA) -> Double {
        func channel(_ value: Double, _ under: Double) -> Double {
            let blended = value * color.alpha + under * (1 - color.alpha)
            return blended <= 0.04045 ? blended / 12.92 : pow((blended + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.red, background.red) + 0.7152 * channel(color.green, background.green)
            + 0.0722 * channel(color.blue, background.blue)
    }
}
