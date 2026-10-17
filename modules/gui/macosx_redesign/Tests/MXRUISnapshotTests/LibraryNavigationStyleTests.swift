import AppKit
import MXRCore
import MXRDesign
import MXRMockBackend
@testable import MXRGalleryCatalog
@testable import MXRUI
import SwiftUI
import XCTest

/// What the compact library draws where Figma's sidebar variants (848:1996) are explicit:
/// navigation rows (Music's Songs / Albums / …, the Videos root's Shows / Films / Anime, The Wand,
/// S01 / S02, Network's Podcasts / Radio) rest at FG/A3 while playlist rows rest at FG/A1, in both
/// themes; the header's "▶" separators and its divider keep their Dark styles in Light as Player -
/// Light (2425:13624) draws them. And the folder / playlist / file menus' audio-track rows act.
@MainActor
final class LibraryNavigationStyleTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            GalleryRenderer.matchFigmaTextRasterization()
            GalleryCatalog.bootstrap()
        }
    }

    private func pixels(_ id: String, scheme: ColorScheme = .dark) throws -> Pixels {
        let entry = try XCTUnwrap(GalleryCatalog.entry(id: id), id)
        return try Pixels(try GalleryRenderer.render(entry, scale: 2, environment: GalleryEnvironment(colorScheme: scheme)))
    }
    private func gray(_ color: ThemeColor, _ scheme: ColorScheme) -> Int { Int((color.value(scheme: scheme).red * 255).rounded()) }

    /// The first row under "Add" (Songs, Shows, The Wand's S01, Podcasts / Cool Songs): its label
    /// box at 2× (x 112–250 pt, y 175–192 pt).
    private let firstRowLabel = CGRect(x: 224, y: 350, width: 276, height: 34)

    func testNavigationRowsRestAtFGA3InDark() throws {
        let fgA3 = gray(Theme.Color.fgA3, .dark)
        for id in ["S33.Library/music", "S33.Library/songs", "S28.Library/videos-root", "S28.Library/shows", "S28.Library/the-wand", "S35.Library/network"] {
            let brightest = try pixels(id).extreme(in: firstRowLabel, brightest: true)
            XCTAssertEqual(brightest, fgA3, accuracy: 3, "\(id): the navigation row label peaks at \(brightest), FG/A3 is \(fgA3)")
        }
        let playlist = try pixels("S38.Library/playlists").extreme(in: firstRowLabel, brightest: true)
        XCTAssertEqual(playlist, gray(Theme.Color.fgA1, .dark), accuracy: 3, "playlist rows stay FG/A1 (2459:9359)")
    }

    func testNavigationRowsRestAtFGA3InLight() throws {
        let darkest = try pixels("S33.Library/music", scheme: .light).extreme(in: firstRowLabel, brightest: false)
        XCTAssertEqual(darkest, gray(Theme.Color.fgA3, .light), accuracy: 4, "Light navigation rows use Light FG/A3, not FG/A1")
    }

    func testHeaderSeparatorsAndDividerKeepTheirDarkStylesInLight() throws {
        let light = try pixels("S28.Library/the-wand", scheme: .light)
        // "... ▶ Shows ▶ The Wand": the first "▶" (x 158–170 pt, y 25–40 pt) and the divider at y 105 pt.
        let separator = light.extreme(in: CGRect(x: 316, y: 50, width: 24, height: 30), brightest: false)
        XCTAssertEqual(separator, gray(Theme.Color.fgA4, .dark), accuracy: 4, "▶ is Dark/FG/A4 #404040 (6131:13620), not Light FG/A4")
        let divider = light.extreme(in: CGRect(x: 400, y: 205, width: 200, height: 10), brightest: false)
        XCTAssertEqual(divider, gray(Theme.Color.dividerDim, .dark), accuracy: 4, "the header divider is Dark/Divider/Dim (I2425:13646;6784:16224)")
    }

    func testVideosRootLightsItsRailIconLikeMusic() throws {
        let accent = Theme.Color.accentMain.value(scheme: .dark)
        let root = try pixels("S28.Library/videos-root").count(near: accent, in: CGRect(x: 30, y: 116, width: 40, height: 48))
        let inside = try pixels("S28.Library/shows").count(near: accent, in: CGRect(x: 30, y: 116, width: 40, height: 48))
        XCTAssertGreaterThan(root, 200, "the Videos root draws the accent videos icon (848:1997)")
        XCTAssertEqual(inside, 0, "a folder inside Videos draws the base icon (848:1995)")
    }

    // MARK: Audio tracks (S29–S31, D039)

    private func perform(_ title: String, in kind: MXRLibraryPopupKind, app: AppModel) async throws {
        let item = try XCTUnwrap(LibraryMenus.sections(for: kind, app: app, sheets: nil, rowIndex: nil, dismiss: {}).figma.first { $0.title == title }, title)
        XCTAssertTrue(item.enabled, "\(title) is enabled as in Figma")
        guard case .perform(let action) = item.kind else { return XCTFail("\(title) performs") }
        action()
        for _ in 0..<200 where app.interface.fileRequest == nil { await Task.yield() }
    }

    func testFolderMenuEditAudioTracksTargetsTheFolder() async throws {
        let app = AppModel.mock(.playingEpisode)
        app.library.navigate(to: .folder(MockMediaID.theWandS01Folder))
        try await perform("Edit Audio Tracks", in: .folder, app: app)
        XCTAssertEqual(app.interface.fileRequest, .addAudioFile)
        XCTAssertEqual(app.library.audioTrackTargets.count, 15, "every episode of S01 can take a track")
    }

    func testPlaylistAndFileMenusAddAudioTracks() async throws {
        let app = AppModel.mock(.idle)
        app.library.select(.playlists)
        for _ in 0..<200 where app.library.entries.isEmpty { await Task.yield() }
        let playlists = app.library.entries.compactMap { if case .playlist(let p) = $0 { return p }; return nil }
        // A playlist of songs only says so instead of opening the panel.
        let songs = try XCTUnwrap(playlists.first { $0.name == "Cool Songs" })
        try await perform("Add Audio Tracks", in: .playlist(songs), app: app)
        XCTAssertNil(app.interface.fileRequest)
        XCTAssertEqual(app.dialogs.current?.text, "There are no videos in this playlist.")
        app.dialogs.current.map { app.dialogs.dismiss($0) }
        let playlist = try XCTUnwrap(playlists.first { $0.name == "Anime to Watch" })
        try await perform("Add Audio Tracks", in: .playlist(playlist), app: app)
        XCTAssertEqual(app.interface.fileRequest, .addAudioFile)
        XCTAssertFalse(app.library.audioTrackTargets.isEmpty)
        XCTAssertTrue(app.library.audioTrackTargets.allSatisfy { $0.kind != .audio }, "songs take no audio track")
        app.complete(.addAudioFile, urls: [])

        XCTAssertTrue(app.library.audioTrackTargets.isEmpty, "a cancelled panel forgets its targets")
        let episodes = await app.library.allMedia(at: .folder(MockMediaID.theWandS01Folder))
        let file = try XCTUnwrap(episodes.last)
        try await perform("Add Audio Tracks", in: .file(file), app: app)
        XCTAssertEqual(app.library.audioTrackTargets.map(\.id), [file.id], "a file that is not playing can take a track too")
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

    private func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let i = (y * width + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    /// The brightest (or darkest) gray level in `box` (pixels, top-left origin).
    func extreme(in box: CGRect, brightest: Bool) -> Int {
        var best = brightest ? 0 : 255
        for y in Int(box.minY)..<Int(box.maxY) { for x in Int(box.minX)..<Int(box.maxX) {
            let (r, g, b) = rgb(x, y); let level = (r + g + b) / 3
            best = brightest ? max(best, level) : min(best, level)
        } }
        return best
    }

    func count(near color: Theme.RGBA, in box: CGRect) -> Int {
        let target = (Int(color.red * 255), Int(color.green * 255), Int(color.blue * 255))
        var n = 0
        for y in Int(box.minY)..<Int(box.maxY) { for x in Int(box.minX)..<Int(box.maxX) {
            let (r, g, b) = rgb(x, y)
            if abs(r - target.0) < 24, abs(g - target.1) < 24, abs(b - target.2) < 24 { n += 1 }
        } }
        return n
    }
}

/// At the 480 pt minimum window the compact panel gets 216 pt (S28.Library/minimum): nothing it
/// draws — header tools, crumbs, rows, Home sections — may reach past that column into the video.
@MainActor
final class LibraryMinimumColumnTests: XCTestCase {
    private func value(_ object: NSObject, _ method: String) -> Any? {
        let selector = NSSelectorFromString(method)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }
    private func elements(_ object: Any) -> [NSObject] {
        guard let node = object as? NSObject else { return [] }
        return [node] + ((value(node, "accessibilityChildren") as? [Any]) ?? []).flatMap(elements)
    }

    func testEveryLocationDrawsInsideTheMinimumColumn() async throws {
        _ = NSApplication.shared
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXManualAccessibility"))
        // The 480 pt minimum content width (MXRAppController) without a right panel.
        let width = PlayerGeometry.compactLibraryWidth(windowWidth: Theme.Metric.Window.player.width / 4, panelOpen: false)
        XCTAssertGreaterThanOrEqual(width, LibraryGeometry.compactMinimumWidth)
        for location in [LibraryLocation.folder(MockMediaID.theWandS01Folder), .home, .music, .videos, .network, .playlists, .recent] {
            let app = AppModel.mock(.playingEpisode)
            app.library.navigate(to: location)
            if location == .home { app.library.reload() }
            let size = CGSize(width: width, height: Theme.Metric.Library.sidebar.height / 2)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let host = NSHostingView(rootView: MXRLibraryView(compact: true).appModel(app).frame(width: size.width, height: size.height))
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(250))
            host.layoutSubtreeIfNeeded()
            let drawn = elements(host).map { ($0.value(forKey: "accessibilityFrame") as? NSRect) ?? .zero }.filter { !$0.isEmpty }
            XCTAssertFalse(drawn.isEmpty)
            for frame in drawn {
                XCTAssertLessThanOrEqual(frame.maxX, window.frame.minX + width + 0.5, "\(location): an element ends at \(frame.maxX - window.frame.minX) pt in a \(width) pt column")
                XCTAssertGreaterThanOrEqual(frame.minX, window.frame.minX - 0.5, "\(location): an element starts left of the column")
            }
        }
    }
}
