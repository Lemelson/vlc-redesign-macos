import CoreGraphics
import MXRGalleryCatalog
import SwiftUI
import XCTest

/// Renders every gallery entry so broken entries are caught, and checks the Figma tooling.
final class GalleryRenderTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            // Same setup as mxr-snapshot: Figma-like text rasterization, then fonts.
            GalleryRenderer.matchFigmaTextRasterization()
            GalleryCatalog.bootstrap()
        }
    }

    @MainActor
    func testCatalogHasEntries() {
        XCTAssertFalse(GalleryCatalog.allEntries().isEmpty, "no GalleryProvider entries were discovered")
    }

    @MainActor
    func testEntryIdsAreUniqueAndWellFormed() {
        let entries = GalleryCatalog.allEntries()
        let duplicates = Dictionary(grouping: entries, by: \.id).filter { $0.value.count > 1 }.keys.sorted()
        XCTAssertTrue(duplicates.isEmpty, "duplicate gallery ids: \(duplicates)")
        let pattern = /^[DCSX][0-9]{0,2}\.[^\/\s]+\/[^\/\s]+$/
        for entry in entries {
            XCTAssertNotNil(entry.id.wholeMatch(of: pattern), "\(entry.id): id must look like C.Name/state or S01.Name/state")
            XCTAssertTrue(entry.size.width > 0 && entry.size.height > 0, "\(entry.id): empty size \(entry.size)")
        }
    }

    @MainActor
    func testShippingEntriesUseTitledWindowHost() throws {
        let entries = GalleryCatalog.allEntries().filter { $0.group.contains(".Window") }
        XCTAssertFalse(entries.isEmpty)
        for entry in entries {
            XCTAssertEqual(entry.renderEngine.rawValue, "shipping-window", entry.id)
            XCTAssertEqual(GalleryRenderer.effectiveEngine(for: entry, override: .imageRenderer), .shippingWindow)
            XCTAssertEqual(GalleryRenderer.effectiveEngine(for: entry, override: .hostingView), .shippingWindow)
        }
    }

    /// CODE-04: a complete shipping-style window has a real Figma comparison, beyond size/opacity.
    /// Hide UI has no intentional platform chrome differences, so it uses the strict verdict.
    @MainActor
    func testShippingHiddenUIWindowMatchesFigma() throws {
        let entry = try XCTUnwrap(GalleryCatalog.entry(id: "S06.Window/hidden-ui"))
        let render = try GalleryRenderer.render(entry, scale: 1)
        let reference = try figmaIndex().reference(for: try XCTUnwrap(entry.figmaNode), scale: 1)
        let comparison = ImageComparator.compare(render, reference.image, scale: 1, makeImages: false).0
        XCTAssertEqual(comparison.verdict, .pass, comparison.report())
    }

    /// A-05: the shipping window with Player-6's media (S01) against Player-6 (247:445), strictly, in
    /// every region that is not a documented deviation. Left out: the top bar's left group and right
    /// end (D022: native traffic lights shift the cone, and Figma's Windows controls are not drawn)
    /// and the seek track, where Figma's playhead (7.3 %) disagrees with its own 00:02:10 / 00:25:40.
    @MainActor
    func testShippingWindowMatchesFigmaPlayer6OutsideDocumentedDeviations() throws {
        let entry = try XCTUnwrap(GalleryCatalog.entry(id: "S01.Window/shipping"))
        let render = try GalleryRenderer.render(entry, scale: 1)
        let reference = try figmaIndex().reference(for: try XCTUnwrap(entry.figmaNode), scale: 1).image
        let regions: [(String, CGRect)] = [
            ("centred title", CGRect(x: 640, y: 0, width: 640, height: 40)),
            ("video frame", CGRect(x: 0, y: 40, width: 1920, height: 986)),
            ("transport and elapsed time", CGRect(x: 0, y: 1026, width: 252, height: 54)),
            ("duration, volume and track buttons", CGRect(x: 1494, y: 1026, width: 426, height: 54)),
        ]
        for (name, rect) in regions {
            let a = try XCTUnwrap(render.cropping(to: rect)), b = try XCTUnwrap(reference.cropping(to: rect))
            let comparison = ImageComparator.compare(a, b, scale: 1, makeImages: false).0
            XCTAssertEqual(comparison.verdict, .pass, "\(name): \(comparison.report())")
        }
    }

    /// Every entry renders to a non-empty image of exactly `size` × 2 pixels.
    @MainActor
    func testEveryEntryRenders() throws {
        for entry in GalleryCatalog.allEntries() {
            // Each offscreen render autoreleases its window, layers and bitmaps; drain them per entry
            // so the whole catalog does not pile up several gigabytes in one test.
            autoreleasepool {
                let image: CGImage
                do {
                    image = try GalleryRenderer.render(entry, scale: 2)
                } catch {
                    XCTFail("\(entry.id): render failed: \(error)")
                    return
                }
                let expected = GalleryRenderer.pixelSize(of: entry.size, scale: 2)
                XCTAssertEqual(image.width, expected.width, "\(entry.id): render width")
                XCTAssertEqual(image.height, expected.height, "\(entry.id): render height")
                XCTAssertGreaterThan(Self.opaquePixelCount(image), 0, "\(entry.id): render is fully transparent")
            }
        }
    }

    /// Entries that name a Figma node point at an existing node whose box matches their size.
    @MainActor
    func testFigmaNodesExistAndMatchEntrySizes() throws {
        let entries = GalleryCatalog.allEntries().filter { $0.figmaNode != nil }
        try XCTSkipIf(entries.isEmpty, "no entries with a figmaNode")
        let index = try figmaIndex()
        for entry in entries {
            guard let nodeID = entry.figmaNode, let node = index.node(nodeID) else {
                XCTFail("\(entry.id): unknown Figma node \(entry.figmaNode ?? "")")
                continue
            }
            XCTAssertEqual(node.boundingBox.width, entry.size.width, accuracy: 0.5, "\(entry.id): width vs node \(node.id)")
            XCTAssertEqual(node.boundingBox.height, entry.size.height, accuracy: 0.5, "\(entry.id): height vs node \(node.id)")
        }
    }

    /// The `play` component set (848:1712) renders 2× of its render bounds; its "type=play"
    /// variant sits 20 pt in, so its crop starts at (40, 40) px and is 108×56 px.
    @MainActor
    func testFigmaCropMath() throws {
        let index = try figmaIndex()
        XCTAssertEqual(FigmaIndex.normalizedID("848-1711"), "848:1711")
        let crop = try index.reference(for: "848:1711")
        XCTAssertEqual(crop.frame.id, "848:1712")
        XCTAssertEqual(crop.frame.renderFile, "play.png")
        XCTAssertEqual(crop.pixelRect, CGRect(x: 40, y: 40, width: 108, height: 56))
        XCTAssertEqual(crop.image.width, 108)
        XCTAssertEqual(crop.image.height, 56)
        XCTAssertTrue(crop.warnings.isEmpty, "\(crop.warnings)")
        // Center-left of the button is the orange accent (#D37918), not the dashed set border.
        let pixel = Self.pixel(crop.image, x: 10, y: 28)
        XCTAssertEqual(pixel.r, 0xD3, accuracy: 2)
        XCTAssertEqual(pixel.g, 0x79, accuracy: 2)
        XCTAssertEqual(pixel.b, 0x18, accuracy: 2)
        XCTAssertEqual(pixel.a, 255)
        // Resampling to 1× keeps the node size in points and is an exact 2×2 average.
        let small = try index.reference(for: "848:1711", scale: 1)
        XCTAssertEqual(small.image.width, 54)
        XCTAssertEqual(small.image.height, 28)
        let full = Self.rgba(crop.image), half = Self.rgba(small.image)
        var worst = 0
        for y in 0..<28 {
            for x in 0..<54 {
                for c in 0..<4 {
                    let sum = [(0, 0), (1, 0), (0, 1), (1, 1)].reduce(0) { $0 + Int(full[((2 * y + $1.1) * 108 + 2 * x + $1.0) * 4 + c]) }
                    worst = max(worst, abs(Int(half[(y * 54 + x) * 4 + c]) - (sum + 2) / 4))
                }
            }
        }
        XCTAssertLessThanOrEqual(worst, 1, "1× crop should be the 2×2 average of the 2× crop")
    }

    /// The Onboarding frames' render bounds start at x.2 / y.8, but their renders are exactly 2×
    /// (2228 px = ceil(1113.6 × 2)), so node 1902:4003 (a 64 pt ring) starts at 105.6 px. The crop
    /// is shifted bilinearly, so the ring is centered: its left and right (top and bottom)
    /// edges have the same coverage instead of being clipped on one side.
    @MainActor
    func testFractionalFrameCropIsCentered() throws {
        let index = try figmaIndex()
        let crop = try index.reference(for: "1902:4003")
        XCTAssertEqual(crop.renderScale, CGSize(width: 2, height: 2))
        XCTAssertEqual(crop.pixelRect.minX, 105.6, accuracy: 0.01)
        XCTAssertEqual(crop.pixelRect.minY, 1325.6, accuracy: 0.01)
        XCTAssertTrue(crop.isSubpixelShifted)
        XCTAssertEqual(crop.image.width, 128)
        XCTAssertEqual(crop.image.height, 128)
        XCTAssertTrue(crop.warnings.contains { $0.contains("between pixels") }, "\(crop.warnings)")
        let left = Self.pixel(crop.image, x: 0, y: 64), right = Self.pixel(crop.image, x: 127, y: 64)
        let top = Self.pixel(crop.image, x: 64, y: 0), bottom = Self.pixel(crop.image, x: 64, y: 127)
        XCTAssertEqual(left.r, right.r, accuracy: 3, "left/right edge coverage")
        XCTAssertEqual(top.r, bottom.r, accuracy: 3, "top/bottom edge coverage")
        // The ring's outer edge covers more than half of the edge pixels (0.76 when centered).
        let inside = Self.pixel(crop.image, x: 1, y: 64)
        XCTAssertGreaterThan(left.r, (inside.r + 14) / 2, "ring clipped at the left edge")
    }

    /// A node inside a hidden layer (not hidden itself) is flagged: Figma renders nothing there.
    @MainActor
    func testHiddenAncestorIsWarned() throws {
        let index = try figmaIndex()
        let nodeID = "I856:2450;2464:9237;2459:9360;247:420"
        let node = try XCTUnwrap(index.node(nodeID))
        XCTAssertTrue(node.visible, "the node itself is visible; its ancestor is hidden")
        XCTAssertEqual(index.hiddenAncestor(of: node)?.id, "I856:2450;2464:9237;2459:9360")
        let crop = try index.reference(for: nodeID)
        XCTAssertTrue(crop.warnings.contains { $0.contains("inside the hidden layer") }, "\(crop.warnings)")
    }

    /// End to end: the token-built play stand-in matches its Figma node (skipped once removed).
    @MainActor
    func testPlayDemoMatchesFigma() throws {
        let entry = try XCTUnwrap(
            GalleryCatalog.entry(id: "X.PlayDemo/play") ?? { throw XCTSkip("X.PlayDemo/play was removed") }()
        )
        let render = try GalleryRenderer.render(entry, scale: 2)
        let reference = try figmaIndex().reference(for: try XCTUnwrap(entry.figmaNode), scale: 2)
        let comparison = ImageComparator.compare(render, reference.image, makeImages: false).0
        XCTAssertEqual(comparison.verdict, .pass, comparison.report())
    }

    func testComparatorVerdicts() throws {
        let base = try XCTUnwrap(Self.image(width: 80, height: 40) { context in
            context.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
            context.setFillColor(CGColor(srgbRed: 0.83, green: 0.47, blue: 0.09, alpha: 1))
            context.fill(CGRect(x: 20, y: 10, width: 20, height: 20))
        })
        let same = ImageComparator.compare(base, base, makeImages: false).0
        XCTAssertEqual(same.verdict, .pass)
        XCTAssertEqual(same.differingPixels, 0)

        let recolored = try XCTUnwrap(Self.image(width: 80, height: 40) { context in
            context.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
            context.setFillColor(CGColor(srgbRed: 0.88, green: 0.31, blue: 0.2, alpha: 1))
            context.fill(CGRect(x: 20, y: 10, width: 20, height: 20))
        })
        let color = ImageComparator.compare(recolored, base, makeImages: false).0
        XCTAssertEqual(color.verdict, .fail)
        XCTAssertGreaterThan(color.flatColorPixels, 0)

        let moved = try XCTUnwrap(Self.image(width: 80, height: 40) { context in
            context.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
            context.setFillColor(CGColor(srgbRed: 0.83, green: 0.47, blue: 0.09, alpha: 1))
            context.fill(CGRect(x: 24, y: 10, width: 20, height: 20))
        })
        let (shifted, images) = ImageComparator.compare(moved, base)
        XCTAssertEqual(shifted.verdict, .fail)
        XCTAssertGreaterThan(shifted.structuralPixels, 0)
        XCTAssertEqual(shifted.bestShift?.dx, -4)
        XCTAssertEqual(shifted.bestShift?.dy, 0)
        XCTAssertEqual(images?.sideBySide.width, 80 * 2 + 16)

        let resized = try XCTUnwrap(Self.image(width: 82, height: 40) { _ in })
        XCTAssertEqual(ImageComparator.compare(resized, base, makeImages: false).0.verdict, .fail)

        // Moved by ½ pt (1 px at 2×): antialiasing-level only, so no regions, but the strict
        // differences still get a bounding box.
        let nudged = try XCTUnwrap(Self.image(width: 80, height: 40) { context in
            context.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
            context.setFillColor(CGColor(srgbRed: 0.83, green: 0.47, blue: 0.09, alpha: 1))
            context.fill(CGRect(x: 21, y: 10, width: 20, height: 20))
        })
        let half = ImageComparator.compare(nudged, base, makeImages: false).0
        XCTAssertEqual(half.verdict, .pass, half.report())
        XCTAssertTrue(half.regions.isEmpty)
        XCTAssertGreaterThan(half.differingPixels, 0)
        let strict = try XCTUnwrap(half.largestStrictRegion)
        XCTAssertTrue(strict.rect.contains(CGPoint(x: 20.5, y: 20)) || strict.rect.contains(CGPoint(x: 40.5, y: 20)), "\(strict.rect)")
    }

    /// Neighbouring dark surface tokens are only 2–5/255 apart; painting a surface with the
    /// wrong one must fail, and the report must name both tokens. ±1 is rasterization noise.
    func testNeighbouringSurfaceTokensFail() throws {
        func solid(_ hex: Int) throws -> CGImage {
            try XCTUnwrap(Self.image(width: 120, height: 60) { context in
                context.setFillColor(CGColor(
                    srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1
                ))
                context.fill(CGRect(x: 0, y: 0, width: 120, height: 60))
            })
        }
        let bgA2 = try solid(0x1F1F1F), bgA3 = try solid(0x1B1B1B), bgA4 = try solid(0x191919)
        for (render, reference, delta) in [(bgA2, bgA3, 4), (bgA3, bgA4, 2)] {
            let comparison = ImageComparator.compare(render, reference, makeImages: false).0
            XCTAssertEqual(comparison.verdict, .fail, comparison.report())
            XCTAssertEqual(comparison.flatColorPixels, 120 * 60)
            let colors = try XCTUnwrap(comparison.largestRegion?.flatColors)
            XCTAssertEqual(colors.delta, delta)
            XCTAssertTrue(colors.summary.contains("bgA3"), colors.summary)
            XCTAssertTrue(comparison.reason.contains("bgA3"), comparison.reason)
        }
        let noise = ImageComparator.compare(try solid(0x1A1A1A), bgA4, makeImages: false).0
        XCTAssertEqual(noise.verdict, .pass, noise.report())
        XCTAssertEqual(noise.flatColorPixels, 0)
    }

    // MARK: Helpers

    private func figmaIndex() throws -> FigmaIndex {
        do {
            return try FigmaIndex.load(paths: GalleryPaths.locate())
        } catch {
            throw XCTSkip("Figma data not available: \(error)")
        }
    }

    private static func image(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        draw(context)
        return context.makeImage()
    }

    private static func rgba(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        data.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return data
    }

    private static func opaquePixelCount(_ image: CGImage) -> Int {
        let data = rgba(image)
        return stride(from: 3, to: data.count, by: 4).reduce(0) { $0 + (data[$1] > 0 ? 1 : 0) }
    }

    /// Unpremultiplied pixel at (x, y), top-left origin.
    private static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Double, g: Double, b: Double, a: Int) {
        let data = rgba(image)
        let o = (y * image.width + x) * 4
        let alpha = Double(data[o + 3])
        guard alpha > 0 else { return (0, 0, 0, 0) }
        func channel(_ value: UInt8) -> Double { (Double(value) * 255 / alpha).rounded() }
        return (channel(data[o]), channel(data[o + 1]), channel(data[o + 2]), Int(alpha))
    }
}
