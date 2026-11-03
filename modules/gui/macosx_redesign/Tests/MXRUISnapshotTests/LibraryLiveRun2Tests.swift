import AppKit
import MXRCore
import MXRDesign
import MXRMockBackend
@testable import MXRGalleryCatalog
@testable import MXRUI
import SwiftUI
import XCTest

/// Library findings of live run 2 and the close wave's parity/critic items (E-library).
@MainActor
final class LibraryLiveRun2Tests: XCTestCase {
    override class func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            GalleryRenderer.matchFigmaTextRasterization()
            GalleryCatalog.bootstrap()
        }
    }
    private var windows: [NSWindow] = []
    override func tearDown() async throws { windows.forEach { $0.close() }; windows = [] }

    // MARK: S46 hover overlay in Light (parity major)

    /// Figma's hover overlay (975:4333) draws ✕, ↗ and ⏮ ▶ ⏭ white over the scrimmed video. In Light
    /// they were Light FG/1 (near-black) on the dark video, so they could not be seen.
    func testMiniPlayerOverVideoControlsAreLightInBothThemes() throws {
        let entry = try XCTUnwrap(GalleryCatalog.entry(id: "S46.MiniPlayer/hover"))
        for scheme in [ColorScheme.light, .dark] {
            let image = try GalleryRenderer.render(entry, scale: 2, environment: GalleryEnvironment(colorScheme: scheme))
            let pixels = try Pixels(image)
            // ✕ at the video's top left (16 pt inset, 24 pt icon) and ⏭ right of the centre.
            XCTAssertGreaterThan(pixels.brightest(in: CGRect(x: 50, y: 50, width: 46, height: 46)), 200, "\(scheme): ✕ is drawn white")
            XCTAssertGreaterThan(pixels.brightest(in: CGRect(x: 520, y: 200, width: 46, height: 50)), 200, "\(scheme): ⏭ is drawn white")
        }
    }

    // MARK: Mini player in a small window (live major)

    func testDockedMiniPlayerKeepsToAThirdOfASmallLibrary() {
        let natural = Theme.Metric.Miniplayer.collapsed.width
        XCTAssertEqual(MiniPlayerLayout.dockedWidth(available: Theme.Metric.Window.player.width), natural, "Figma's 391 pt in the designed window")
        XCTAssertEqual(MiniPlayerLayout.dockedWidth(available: 680), 680 / 3, accuracy: 0.01, "680 pt: a third, not 391 pt")
        XCTAssertEqual(MiniPlayerLayout.dockedWidth(available: 480), MiniPlayerLayout.minimumWidth, "the minimum window keeps a readable card")
        let full = MiniPlayerLayout(width: natural)
        XCTAssertEqual(full.collapsedHeight, Theme.Metric.Miniplayer.collapsed.height, accuracy: 0.001, "the designed card is unchanged")
        XCTAssertEqual(full.scale, 1, accuracy: 0.0001)
        let small = MiniPlayerLayout(width: 680 / 3)
        XCTAssertEqual(small.video.width / small.video.height, 16 / 9, accuracy: 0.001)
        XCTAssertLessThan(small.collapsedHeight, 383 - Theme.Metric.Window.topBar.height, "the card fits under a 383 pt window's top bar")
    }

    // MARK: Breadcrumb at ~680 pt (live minor)

    /// Two folders deep in a narrow header the crumb row fell through to a bare "..." because the
    /// one-crumb row (unshrinkable) never fit. Now "... ▸ <current>" always stays, middle-truncated.
    func testNarrowBreadcrumbKeepsTheCurrentFolder() async throws {
        XCTAssertEqual(LibraryBreadcrumb.compactCrumbCounts(4, searching: false), [2, 1], "no bare \"...\" choice")
        XCTAssertEqual(LibraryBreadcrumb.compactCrumbCounts(0, searching: false), [0])
        let app = AppModel.mock(.idle)
        app.library.navigate(to: .folder(MockMediaID.theWandS01Folder))
        for _ in 0..<200 where app.library.breadcrumb.count < 2 { await Task.yield() }
        let current = try XCTUnwrap(app.library.breadcrumb.last?.title)
        enableAccessibilityTree()
        // Narrower than "... ▸ S01" at its natural width.
        let size = CGSize(width: 36, height: 40)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        let host = NSHostingView(rootView: LibraryBreadcrumb(compact: true).frame(width: size.width, height: size.height).appModel(app))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        let labels = elements(host).compactMap { value($0, "accessibilityLabel") as? String }
        XCTAssertTrue(labels.contains("Enclosing folders"), "the parents fold into \"...\"")
        XCTAssertTrue(labels.contains(current), "the current folder (\(current)) stays drawn: \(labels)")
    }

    // MARK: Menus and counts (live minors, critic P2)

    func testSongsOfferNoAudioTrackAndVideosDo() throws {
        let app = AppModel.mock(.idle)
        let song = MediaItem(id: "ml:song", mrl: "file:///tmp/untangle.mp3", title: "untangle", kind: .audio)
        let video = MediaItem(id: "ml:video", mrl: "file:///tmp/video.mp4", title: "video", kind: .video)
        func addAudio(_ media: MediaItem) throws -> LibraryMenuItem {
            try XCTUnwrap(LibraryMenus.sections(for: .file(media), app: app, sheets: nil, rowIndex: nil, dismiss: {}).figma.first { $0.title == "Add Audio Tracks" })
        }
        XCTAssertFalse(try addAudio(song).enabled, "D039: songs take no audio track")
        XCTAssertTrue(try addAudio(video).enabled)
    }

    func testCountsAreSingularForOne() {
        XCTAssertEqual(LibraryEntry.stream(NetworkStream(id: "s", name: "Radio", urls: [], itemCount: 1)).mxrSubtitle, "1 item")
        XCTAssertEqual(LibraryEntry.stream(NetworkStream(id: "s", name: "Radio", urls: [], itemCount: 2)).mxrSubtitle, "2 items")
        XCTAssertEqual(LibraryEntry.playlist(Playlist(id: "p", name: "P", itemCount: 1)).mxrSubtitle, "1 item")
    }

    /// Playlist ⋯ ▸ Add File: the files join the library and the playlist that is shown.
    func testAddFileFromAPlaylistAddsToThatPlaylist() async throws {
        let app = AppModel.mock(.idle)
        app.library.select(.playlists)
        for _ in 0..<200 where app.library.entries.isEmpty { await Task.yield() }
        let playlist = try XCTUnwrap(app.library.entries.compactMap { if case .playlist(let p) = $0 { return p }; return nil }.first)
        app.library.navigate(to: .playlist(playlist.id))
        for _ in 0..<200 where app.library.contentLocation != .playlist(playlist.id) { await Task.yield() }
        let before = app.library.totalCount
        let url = URL(fileURLWithPath: "/tmp/LibraryLiveRun2-added.mp4")
        try await app.library.importFiles(urls: [url])
        for _ in 0..<400 where app.library.totalCount == before { await Task.yield() }
        XCTAssertEqual(app.library.location, .playlist(playlist.id), "the playlist stays shown")
        XCTAssertEqual(app.library.totalCount, before + 1)
        XCTAssertTrue(app.library.entries.contains { $0.media?.mrl == url.absoluteString }, "the file is in the playlist")
    }

    // MARK: Helpers

    private func value(_ object: NSObject, _ method: String) -> Any? {
        let selector = NSSelectorFromString(method)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }
    private func elements(_ object: Any) -> [NSObject] {
        guard let node = object as? NSObject else { return [] }
        return [node] + ((value(node, "accessibilityChildren") as? [Any]) ?? []).flatMap(elements)
    }
}

private struct Pixels {
    let width: Int, height: Int
    let data: [UInt8]
    init(_ image: CGImage) throws {
        width = image.width; height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        data = buffer
    }
    /// The brightest gray level in `box` (pixels, top-left origin).
    func brightest(in box: CGRect) -> Int {
        var best = 0
        for y in max(0, Int(box.minY))..<min(height, Int(box.maxY)) { for x in max(0, Int(box.minX))..<min(width, Int(box.maxX)) {
            let i = (y * width + x) * 4
            best = max(best, (Int(data[i]) + Int(data[i + 1]) + Int(data[i + 2])) / 3)
        } }
        return best
    }
}
