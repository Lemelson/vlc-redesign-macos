import AppKit
import MXRCore
import MXRDesign
import MXRMockBackend
@testable import MXRUI
import SwiftUI
import XCTest

/// S65: a dialog body that scrolls ends at a divider above the footer, so the row cut by the footer
/// reads as scrolled content; a body that fits draws no divider there.
@MainActor
final class DialogScrollEdgeTests: XCTestCase {
    /// Brightest luminance (0–255) along x = 85 % of the width, in `rows` (points from the top).
    /// `playing`: the media is the one playing, so its track rows are listed too.
    private func brightness(playing: Bool, width: CGFloat, height: CGFloat, rows: ClosedRange<CGFloat>) throws -> (edge: Int, footer: Int) {
        _ = NSApplication.shared
        let media = try XCTUnwrap(AppModel.mock(.playingEpisode).player.media)
        let app = playing ? AppModel.mock(.playingEpisode) : AppModel.mock(.idle)
        if playing { XCTAssertEqual(app.player.media?.id, media.id) }
        let hosting = NSHostingView(rootView: MXRMediaInfoView(media: media).appModel(app)
            .frame(width: width, height: height).environment(\.colorScheme, .dark))
        hosting.frame = CGRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        defer { window.contentView = nil; window.close() }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        let scale: CGFloat = 2
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = NSSize(width: width, height: height)
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let x = Int(width * 0.85 * scale)
        func luminance(_ y: Int) -> Int {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return 0 }
            return Int((c.redComponent * 0.2126 + c.greenComponent * 0.7152 + c.blueComponent * 0.0722) * 255)
        }
        let edge = stride(from: Int(rows.lowerBound * scale), through: Int(rows.upperBound * scale), by: 1).map(luminance).max() ?? 0
        let footer = luminance(Int((height - Theme.Metric.dialogFooterHeight / 2) * scale))
        return (edge, footer)
    }

    func testScrollingBodyEndsAtADividerAboveTheFooter() throws {
        // The gallery size (S65).
        let size = Theme.Metric.Dialogs.newPlaylist.size
        let footerTop = size.height - Theme.Metric.dialogFooterHeight
        // Playing: the track rows run under the footer.
        let clipped = try brightness(playing: true, width: size.width, height: size.height, rows: (footerTop - 1)...(footerTop + 1))
        XCTAssertGreaterThan(clipped.edge, clipped.footer + 1, "a divider separates the scrolled rows from the footer")

        // Not playing: no track rows, the properties fit, and no divider is drawn where the body ends.
        let fits = try brightness(playing: false, width: size.width, height: size.height, rows: (footerTop - 1)...(footerTop + 1))
        XCTAssertLessThanOrEqual(fits.edge, fits.footer + 1, "a body that fits needs no divider")
    }
}
