import AppKit
import MXRCore
import MXRDesign
import MXRMockBackend
@testable import MXRUI
import SwiftUI
import XCTest

/// Library sheets are native `.sheet`s, not drawn over the video or a dialog scrim, so the dark
/// material base of D046 must not show through them in Light: they use the dialog surface, which
/// is the opaque `BG/A3` in Light and the translucent `BG/A3 Transparent` in Dark.
@MainActor
final class LibrarySheetSurfaceTests: XCTestCase {
    func testLightLibrarySheetIsTheOpaqueLightDialogSurface() throws {
        let light = try XCTUnwrap(Self.bodyPixel(appearance: .aqua))
        let expected = Theme.Color.bgA3.value(scheme: .light)
        XCTAssertEqual(light.red, expected.red, accuracy: 0.02, "Light sheet body \(light) is not BG/A3 \(expected)")
        XCTAssertEqual(light.green, expected.green, accuracy: 0.02)
        XCTAssertEqual(light.blue, expected.blue, accuracy: 0.02)
        XCTAssertEqual(light.alpha, 1, accuracy: 0.01, "Light sheet body must be opaque")
    }

    func testDarkLibrarySheetStaysADarkSurface() throws {
        let dark = try XCTUnwrap(Self.bodyPixel(appearance: .darkAqua))
        XCTAssertLessThan(max(dark.red, dark.green, dark.blue), 0.3, "Dark sheet body \(dark) must read dark")
    }

    /// The sheet as AppKit would show it: in its own window with the system window background
    /// behind, captured with its live material. Returns a pixel inside the body, below the header.
    private static func bodyPixel(appearance name: NSAppearance.Name) throws -> Theme.RGBA? {
        _ = NSApplication.shared
        let app = AppModel.mock(.idle)
        let center = LibrarySheetCenter()
        let sheet = LibrarySheetCenter.Sheet.failure(title: "Could Not Rename", message: "The library is busy.")
        let hosting = NSHostingView(rootView: LibrarySheetView(sheet: sheet, center: center).appModel(app))
        let size = hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: name)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        defer { window.contentView = nil; window.close() }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let cached = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: cached)
        // The cache holds the drawn sRGB values under a generic profile; read them as sRGB (as mxr-snapshot does).
        guard let rep = cached.retagging(with: .sRGB) else { return nil }
        if let dir = ProcessInfo.processInfo.environment["MXR_TEST_RENDER_DIR"], let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("library-sheet-\(name.rawValue).png"))
        }
        // Left edge of the body, clear of text: 6 pt in, at mid height (between header and footer).
        let x = Int(6 * CGFloat(rep.pixelsWide) / size.width)
        let y = rep.pixelsHigh / 2
        guard let color = rep.colorAt(x: x, y: y) else { return nil }
        return Theme.RGBA(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent, alpha: color.alphaComponent)
    }
}
