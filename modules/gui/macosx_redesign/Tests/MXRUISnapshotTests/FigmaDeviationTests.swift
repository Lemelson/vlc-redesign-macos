import CoreGraphics
import Foundation
import MXRGalleryCatalog
import XCTest

/// F-06: documented per-entry Figma deviations, and the Settings gate built on them.
final class FigmaDeviationTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            GalleryRenderer.matchFigmaTextRasterization()
            GalleryCatalog.bootstrap()
        }
    }

    /// Settings entries whose remaining differences are not covered by an accepted decision. They
    /// are real open items (reported to F-settings and the owner), so the gate expects them to
    /// fail until the product or DECISIONS.md changes; a fix makes the expectation pass silently.
    private static let openSettingsDifferences: [String: String] = [:]

    /// The cut really aligns the rows below a removed row: without the deviations Playback FAILs
    /// (its Pause on interruption row shifts everything up 42 pt); with them it does not.
    @MainActor
    func testRemovedRowRealignsTheRowsBelowIt() throws {
        let (entry, render, reference, index) = try playback()
        XCTAssertFalse(entry.figmaDeviations.isEmpty)
        let raw = ImageComparator.compare(render, reference.image, scale: 1, makeImages: false).0
        XCTAssertEqual(raw.verdict, .fail, "without deviations the D035 row shift must fail: \(raw.report())")
        let adjusted = try index.applying(entry.figmaDeviations, render: render, reference: reference)
        let comparison = ImageComparator.compare(adjusted.render, adjusted.reference, scale: 1, makeImages: false).0
        XCTAssertNotEqual(comparison.verdict, .fail, comparison.report())
        // Only the declared areas are left out: the 320×36 Continue dropdown and the 42 pt strip the
        // cut uncovers at the bottom of the 784 pt column, nothing else.
        let expected = 320 * 36 + 784 * 42
        XCTAssertEqual(adjusted.excludedPixels, expected, accuracy: 784, "excluded \(adjusted.excludedPixels) px")
        // The Tracks heading (Figma 326 pt) is compared at the product's 284 pt, pixel for pixel.
        let heading = CGRect(x: 240, y: 284, width: 200, height: 39)
        let crop = ImageComparator.compare(
            try XCTUnwrap(adjusted.render.cropping(to: heading)), try XCTUnwrap(adjusted.reference.cropping(to: heading)),
            scale: 1, makeImages: false
        ).0
        XCTAssertEqual(crop.verdict, .pass, crop.report())
    }

    /// A node-anchored `differs` follows the rows the product leaves out: in Recording the Play
    /// locally toggle (Figma 956,410 pt) is drawn 147 pt higher, below the removed Casting section,
    /// and that is the area left out; the Figma position, now another row, is still compared.
    @MainActor
    func testNodeAnchoredDifferenceFollowsRemovedRows() throws {
        let index: FigmaIndex
        do { index = try FigmaIndex.load(paths: GalleryPaths.locate()) } catch { throw XCTSkip("Figma data not available: \(error)") }
        let entry = try XCTUnwrap(GalleryCatalog.entry(id: "S48.Settings/recording"))
        let render = try GalleryRenderer.render(entry, scale: 1)
        let reference = try index.reference(for: try XCTUnwrap(entry.figmaNode), scale: 1)
        let adjusted = try index.applying(entry.figmaDeviations, render: render, reference: reference)
        let toggle = CGSize(width: 68, height: 32)
        let product = try Self.alphas(of: adjusted.render, in: CGRect(origin: CGPoint(x: 956, y: 410 - 147), size: toggle))
        XCTAssertEqual(product.max(), 0, "the product's toggle is left out")
        let figma = try Self.alphas(of: adjusted.render, in: CGRect(origin: CGPoint(x: 956, y: 410), size: toggle))
        XCTAssertGreaterThan(figma.filter { $0 > 0 }.count, figma.count / 2, "the row now at Figma's position is still compared")
    }

    /// A moved node is compared where the product draws it (D022): the top bar's left group after
    /// the traffic lights. The shifted icons match pixel for pixel, a wrong icon there still fails,
    /// and only the vacated strip (the lights) and the Windows buttons are left out.
    @MainActor
    func testMovedNodeIsComparedWhereTheProductDrawsIt() throws {
        let index: FigmaIndex
        do { index = try FigmaIndex.load(paths: GalleryPaths.locate()) } catch { throw XCTSkip("Figma data not available: \(error)") }
        let entry = try XCTUnwrap(GalleryCatalog.entry(id: "S01.Window/shipping"))
        XCTAssertTrue(entry.figmaDeviations.contains { if case .moved = $0.kind { true } else { false } })
        let render = try GalleryRenderer.render(entry, scale: 1)
        let reference = try index.reference(for: try XCTUnwrap(entry.figmaNode), scale: 1)
        let adjusted = try index.applying(entry.figmaDeviations, render: render, reference: reference)
        // The cone, ⋯, sidebar toggle and folder chip, where the product draws them.
        let group = CGRect(x: 80, y: 6, width: 300, height: 28)
        let crop = ImageComparator.compare(try XCTUnwrap(adjusted.render.cropping(to: group)),
                                           try XCTUnwrap(adjusted.reference.cropping(to: group)), scale: 1, makeImages: false).0
        XCTAssertEqual(crop.verdict, .pass, crop.report())
        XCTAssertGreaterThan(try Self.alphas(of: adjusted.render, in: group).filter { $0 > 0 }.count, 300 * 28 / 2,
                             "the moved group is compared, not left out")
        XCTAssertLessThan(adjusted.excludedFraction, 0.005, "only the lights and two Windows buttons are left out")
        // A regression inside the moved group fails.
        let broken = try XCTUnwrap(Self.drawing(on: render) { context, height in
            context.setFillColor(CGColor(srgbRed: 0.8, green: 0.1, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 90, y: CGFloat(height) - 8 - 24, width: 24, height: 24))
        })
        let brokenAdjusted = try index.applying(entry.figmaDeviations, render: broken, reference: reference)
        let brokenCrop = ImageComparator.compare(try XCTUnwrap(brokenAdjusted.render.cropping(to: group)),
                                                 try XCTUnwrap(brokenAdjusted.reference.cropping(to: group)), scale: 1, makeImages: false).0
        XCTAssertEqual(brokenCrop.verdict, .fail, brokenCrop.report())
    }

    /// A deviation does not hide a regression elsewhere: a wrong block drawn into the render
    /// outside every declared area still fails the check.
    @MainActor
    func testDeviationsDoNotHideRegressionsOutsideThem() throws {
        let (entry, render, reference, index) = try playback()
        let broken = try XCTUnwrap(Self.drawing(on: render) { context, height in
            context.setFillColor(CGColor(srgbRed: 0.8, green: 0.1, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 240, y: CGFloat(height) - 420 - 30, width: 300, height: 30)) // 240,420 pt, top-left
        })
        let adjusted = try index.applying(entry.figmaDeviations, render: broken, reference: reference)
        let comparison = ImageComparator.compare(adjusted.render, adjusted.reference, scale: 1, makeImages: false).0
        XCTAssertEqual(comparison.verdict, .fail, comparison.report())
    }

    /// Every deviation cites an accepted decision, and every removed node belongs to the entry's
    /// Figma frame, so a typo cannot silently widen what is left out.
    @MainActor
    func testDeviationsCiteAcceptedDecisionsAndOwnNodes() throws {
        let entries = GalleryCatalog.allEntries().filter { !$0.figmaDeviations.isEmpty }
        XCTAssertFalse(entries.isEmpty)
        let paths = try GalleryPaths.locate()
        let decisions = try String(contentsOf: paths.repoRoot.appending(path: "redesign/docs/DECISIONS.md"), encoding: .utf8)
        let index = try FigmaIndex.load(paths: paths)
        for entry in entries {
            let root = try XCTUnwrap(entry.figmaNode, "\(entry.id) declares deviations but has no figmaNode")
            for deviation in entry.figmaDeviations {
                let heading = decisions.split(separator: "\n").first { $0.hasPrefix("### \(deviation.decision) ") }
                XCTAssertNotNil(heading, "\(entry.id): \(deviation.decision) is not in DECISIONS.md")
                // "· accepted ·", "· accepted (owner, …) ·" or "· accepted (agent, …) ·" (awaiting the owner).
                XCTAssertTrue(heading.map { $0.contains("· accepted ·") || $0.contains("· accepted (") } ?? false,
                              "\(entry.id): \(deviation.decision) is not accepted")
                XCTAssertFalse(deviation.reason.isEmpty, entry.id)
                if case let .differs(rect) = deviation.kind {
                    XCTAssertTrue(CGRect(origin: .zero, size: entry.size).contains(rect), "\(entry.id): \(rect) outside the entry")
                }
                if let id = deviation.node {
                    let node = try XCTUnwrap(index.node(id), "\(entry.id): unknown node \(id)")
                    XCTAssertTrue(index.ancestry(of: node).contains { $0.id == FigmaIndex.normalizedID(root) },
                                  "\(entry.id): \(id) is not inside \(root)")
                }
            }
        }
    }

    /// The F-06 gate: every Settings category with a Figma frame matches it outside its documented
    /// deviations (PASS or REVIEW), at 2×, exactly as `mxr-snapshot check` reports it.
    ///
    /// Each check runs in its own `mxr-snapshot` process. Figma-like text rasterization
    /// (`matchFigmaTextRasterization`) only takes effect before a process first touches AppKit
    /// text, and in a test run an earlier suite may already have done that, which made in-process
    /// verdicts depend on test order (S48.Settings/recording moved from REVIEW to FAIL).
    func testSettingsCategoriesMatchFigmaOutsideDocumentedDeviations() throws {
        let ids = MainActor.assumeIsolated {
            GalleryCatalog.allEntries().filter { $0.id.hasPrefix("S48.Settings/") && $0.figmaNode != nil }.map(\.id)
        }
        XCTAssertGreaterThanOrEqual(ids.count, 14)
        let tool = try Self.snapshotTool()
        let output = FileManager.default.temporaryDirectory.appending(path: "mxr-settings-gate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: output) }

        let checks = ConcurrentChecks()
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        for id in ids {
            queue.addOperation {
                checks.store(id, Self.run(tool, ["check", "--id", id, "--scale", "2",
                                                 "--out-dir", output.appending(path: id.replacingOccurrences(of: "/", with: "-")).path]))
            }
        }
        queue.waitUntilAllOperationsAreFinished()

        for id in ids {
            let check = try XCTUnwrap(checks.result(id))
            // 0: PASS or REVIEW, 1: FAIL, anything else: the tool could not check the entry.
            XCTAssertTrue([0, 1].contains(check.status), "\(id): mxr-snapshot failed (\(check.status)): \(check.output)")
            let verdict = check.output.split(separator: "\n").first { $0.hasPrefix("verdict") }.map(String.init) ?? check.output
            let assertion = { XCTAssertNotEqual(check.status, 1, "\(id): \(verdict)") }
            if let reason = Self.openSettingsDifferences[id] {
                let options = XCTExpectedFailure.Options()
                options.isStrict = false
                XCTExpectFailure("open: \(reason)", options: options, failingBlock: assertion)
            } else {
                assertion()
            }
        }
    }

    /// Results of the concurrent `mxr-snapshot` runs.
    private final class ConcurrentChecks: @unchecked Sendable {
        private let lock = NSLock()
        private var results: [String: (status: Int32, output: String)] = [:]
        func store(_ id: String, _ result: (status: Int32, output: String)) { lock.withLock { results[id] = result } }
        func result(_ id: String) -> (status: Int32, output: String)? { lock.withLock { results[id] } }
    }

    /// `mxr-snapshot`, built next to this test bundle by `swift build --build-tests`.
    private static func snapshotTool() throws -> URL {
        let tool = Bundle(for: FigmaDeviationTests.self).bundleURL.deletingLastPathComponent().appending(path: "mxr-snapshot")
        guard FileManager.default.isExecutableFile(atPath: tool.path) else {
            throw GalleryToolingError("mxr-snapshot is not built at \(tool.path); run swift build --build-tests")
        }
        return tool
    }

    private static func run(_ tool: URL, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    // MARK: Helpers

    @MainActor
    private func playback() throws -> (GalleryEntry, CGImage, FigmaReference, FigmaIndex) {
        let index: FigmaIndex
        do { index = try FigmaIndex.load(paths: GalleryPaths.locate()) } catch { throw XCTSkip("Figma data not available: \(error)") }
        let entry = try XCTUnwrap(GalleryCatalog.entry(id: "S48.Settings/playback"))
        let render = try GalleryRenderer.render(entry, scale: 1)
        let reference = try index.reference(for: try XCTUnwrap(entry.figmaNode), scale: 1)
        return (entry, render, reference, index)
    }

    /// Alpha of every pixel of `image` (scale 1) inside `rect` (top-left points).
    private static func alphas(of image: CGImage, in rect: CGRect) throws -> [UInt8] {
        let crop = try XCTUnwrap(image.cropping(to: rect))
        var pixels = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: crop.width, height: crop.height, bitsPerComponent: 8, bytesPerRow: crop.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            return true
        }
        XCTAssertTrue(drawn)
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }

    private static func drawing(on image: CGImage, _ draw: (CGContext, Int) -> Void) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        draw(context, image.height)
        return context.makeImage()
    }
}
