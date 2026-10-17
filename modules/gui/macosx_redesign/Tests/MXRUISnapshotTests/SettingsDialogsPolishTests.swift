import AppKit
import MXRCore
import MXRDesign
@testable import MXRGalleryCatalog
import MXRMockBackend
@testable import MXRUI
import SwiftUI
import XCTest

/// F-settings final-polish items (2026-10-17): what the modal host, the dialog buttons and the
/// Settings controls draw, checked on rendered pixels.
@MainActor
final class SettingsDialogsPolishTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            GalleryRenderer.matchFigmaTextRasterization()
            GalleryCatalog.bootstrap()
        }
    }

    // MARK: Helpers

    /// Draws `view` at `size` (1× unless `scale`) and returns its pixels, top-left origin.
    private func draw<V: View>(_ view: V, size: CGSize, scheme: ColorScheme = .dark, scale: CGFloat = 1) throws -> Pixels {
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height).environment(\.colorScheme, scheme))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = hosting
        defer { window.contentView = nil; window.close() }
        for _ in 0..<3 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return Pixels(rep: rep, scale: scale)
    }

    // MARK: Modal host (S25.App, S37/S48 compact)

    func testDialogHostLeavesTheWindowBehindAtFullBrightness() throws {
        // 06m02.47: the player and both bars keep their brightness while Add Subtitles is open. The
        // old BG/B2 Transparent scrim drew #000 @ 80 % over everything.
        let app = AppModel.mock(.playingEpisode)
        app.interface.present(.about)
        let pixels = try draw(Color.white.mxrDialogPresentation().appModel(app), size: CGSize(width: 960, height: 1080))
        for point in [CGPoint(x: 10, y: 10), CGPoint(x: 950, y: 540), CGPoint(x: 480, y: 1070)] {
            XCTAssertGreaterThan(pixels.luminance(at: point), 250, "the window at \(point) is not dimmed")
        }
        XCTAssertLessThan(pixels.luminance(at: CGPoint(x: 480, y: 540)), 200, "the dialog itself is drawn")
    }

    func testShrunkDialogStaysBelowTheTopBar() throws {
        // S48.App/settings-compact: in a 960×540 window Settings ran from y 20, under the traffic lights.
        let app = AppModel.mock(.playingEpisode)
        app.interface.present(.settings(categoryID: "controls"))
        let size = CGSize(width: 960, height: 540)
        let pixels = try draw(Color.white.mxrDialogPresentation().appModel(app), size: size)
        // The dark dialog body, not its soft shadow.
        let firstDialogRow = (0..<Int(size.height)).first { pixels.luminance(at: CGPoint(x: 480, y: CGFloat($0))) < 100 }
        let lastDialogRow = (0..<Int(size.height)).last { pixels.luminance(at: CGPoint(x: 480, y: CGFloat($0))) < 100 }
        let top = try XCTUnwrap(firstDialogRow), bottom = try XCTUnwrap(lastDialogRow)
        XCTAssertGreaterThanOrEqual(CGFloat(top), Theme.Metric.topBarHeight - 1, "the dialog starts below the 40 pt top bar")
        XCTAssertEqual(CGFloat(top) + CGFloat(bottom), size.height - 1, accuracy: 3, "and stays centred")
    }

    // MARK: Dialog buttons (critic P1, D045)

    func testSecondaryDialogButtonsStandOutFromTheLightDialogSurface() throws {
        // Every DialogShell dialog: in Light the BG/A3 Cancel/Choose… tile was the opaque BG/A3 surface.
        let entry = try XCTUnwrap(GalleryCatalog.entry(id: "S37.Convert/empty"))
        for scheme in [ColorScheme.light, .dark] {
            let image = try GalleryRenderer.render(entry, scale: 1, environment: GalleryEnvironment(colorScheme: scheme))
            let pixels = Pixels(image: image)
            let footerMiddle = entry.size.height - Theme.Metric.dialogFooterHeight / 2
            // Cancel's tile beside its title, and the surface between Cancel and Convert.
            let tile = pixels.luminance(at: CGPoint(x: 28, y: footerMiddle))
            let surface = pixels.luminance(at: CGPoint(x: entry.size.width / 2, y: footerMiddle))
            XCTAssertGreaterThanOrEqual(abs(tile - surface), scheme == .light ? 20 : 1, "\(scheme): Cancel draws its tile")
        }
    }

    func testDisabledShortcutsSaveBlendsLikeFigma() throws {
        // S64 2437:14853: Luminosity at 50 % over the 95 % dialog fill reads #1F1E1D, not neutral #1F1F1F.
        let entry = try XCTUnwrap(GalleryCatalog.entry(id: "S64.KeyboardShortcuts/default"))
        let pixels = Pixels(image: try GalleryRenderer.render(entry, scale: 2), scale: 2)
        let fill = pixels.rgb(at: CGPoint(x: 940, y: 752))
        XCTAssertEqual(fill.0, 31, accuracy: 1)
        XCTAssertEqual(fill.1, 30, accuracy: 1)
        XCTAssertEqual(fill.2, 29, accuracy: 1)
        XCTAssertGreaterThan(fill.0, fill.2, "a trace of the accent fill stays, as in Figma")
    }

    // MARK: Settings controls

    func testToggleKeepsFigmaInsetAndGap() throws {
        // 536:1013: label cell at x 3…36, 3 pt gap, knob at 39…65, 3 pt inset.
        let track = Theme.Color.bgB2.value(scheme: .dark).rgb255
        for isOn in [true, false] {
            let pixels = try draw(SettingsToggle(isOn: .constant(isOn), label: "Toggle"),
                                  size: Theme.Metric.Controls.toggle.size, scale: 4)
            let middle = Theme.Metric.Controls.toggle.height / 2
            let gapX: CGFloat = isOn ? 37.5 : 30.5
            for x in [CGFloat(1.5), gapX, 66.5] {
                XCTAssertTrue(pixels.near(CGPoint(x: x, y: middle), track, tolerance: 3), "on \(isOn): track at x \(x)")
            }
            for x in [CGFloat(isOn ? 4.5 : 33.5), isOn ? 40 : 27] {
                XCTAssertFalse(pixels.near(CGPoint(x: x, y: middle), track, tolerance: 3), "on \(isOn): a cell at x \(x)")
            }
        }
    }

    func testScaleLabelsStandUnderTheirTicks() {
        // 3062:13083 (Default playback speed, 320 pt, a label on each of 8 ticks): "1" is centred under
        // its tick at x 137.4, the first label starts at the first tick and the last ends at the last.
        let width: CGFloat = 320
        let one = SettingsSlider.labelAnchor(index: 3, count: 8, width: width, ticks: 8)
        XCTAssertEqual(one.x, 137.4, accuracy: 0.5)
        XCTAssertEqual(one.alignment, .center)
        XCTAssertEqual(SettingsSlider.labelAnchor(index: 0, count: 8, width: width, ticks: 8).x, Theme.Spacing.gap2)
        XCTAssertEqual(SettingsSlider.labelAnchor(index: 0, count: 8, width: width, ticks: 8).alignment, .leading)
        XCTAssertEqual(SettingsSlider.labelAnchor(index: 7, count: 8, width: width, ticks: 8).x, width - Theme.Spacing.gap2)
        XCTAssertEqual(SettingsSlider.labelAnchor(index: 7, count: 8, width: width, ticks: 8).alignment, .trailing)
        // 3176:16483 (Maximum volume, 3 labels on 7 ticks): the ends sit on the track's edges, the
        // middle label in the middle.
        XCTAssertEqual(SettingsSlider.labelAnchor(index: 0, count: 3, width: width, ticks: 7).x, 0)
        XCTAssertEqual(SettingsSlider.labelAnchor(index: 2, count: 3, width: width, ticks: 7).x, width)
        XCTAssertEqual(SettingsSlider.labelAnchor(index: 1, count: 3, width: width, ticks: 7).x, width / 2, accuracy: 0.01)
    }

    func testReplayGainPreampIsAFloatInTheMock() throws {
        // S56: the fixture showed "0" because JSON decodes the mock 0.0 as an integer.
        let app = AppModel.mock(.idle)
        XCTAssertEqual(app.settings.backend.option(named: "audio-replay-gain-preamp")?.type, .float)
    }

    // MARK: Media Info (S65)

    func testMediaInfoFitsAllTrackRows() throws {
        let app = AppModel.mock(.playingEpisode)
        let media = try XCTUnwrap(app.player.media)
        let size = MXRMediaInfoView.maximumSize
        let pixels = try draw(Color.white.overlay { MXRMediaInfoView(media: media).appModel(app) }, size: size)
        let rows = (0..<Int(size.height)).filter { pixels.luminance(at: CGPoint(x: size.width / 2, y: CGFloat($0))) < 200 }
        let height = try CGFloat(XCTUnwrap(rows.last)) - CGFloat(XCTUnwrap(rows.first)) + 1
        XCTAssertLessThan(height, size.height - 1, "the dialog is as tall as its content")
        XCTAssertGreaterThan(height, Theme.Metric.DialogForms.formSize.height, "taller than the form, so every track row shows")
    }

    // MARK: PER-02

    func testSavingSubtitlesResolvesFilePathsOffTheMainThread() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let originals = directory.appendingPathComponent("Originals"), alias = directory.appendingPathComponent("Alias")
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = originals.appendingPathComponent("Episode.mp4")
        try Data().write(to: source)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: originals)
        let mock = MockBackend(scenario: .idle)
        mock.player.load(MediaItem(url: source))
        let app = AppModel(backends: mock.backends, persistence: .inMemory, clockTicks: false)
        var selected = MediaItem(url: alias.appendingPathComponent("Episode.mp4"))
        selected.id = "ml:42"
        let subtitle = directory.appendingPathComponent("Episode.en.srt")
        let draft = SubtitleImportDraft(scope: .file, source: .computer, media: [selected], subtitles: [subtitle])
        let onMain = ThreadRecord()
        try await draft.save(to: app, rules: SubtitleFolderRulesStore(rules: SubtitleFolderRules())) { url in
            onMain.add(Thread.isMainThread)
            return url.standardizedFileURL.resolvingSymlinksInPath()
        }
        XCTAssertFalse(onMain.values.isEmpty, "the playing file was looked up on disk")
        XCTAssertFalse(onMain.values.contains(true), "no file-system read on the main thread")
        XCTAssertTrue(app.tracks.externalTracks(of: .subtitle).contains { $0.sourceURL == subtitle }, "the symlinked item is the playing file")
    }
}

private final class ThreadRecord: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Bool] = []
    func add(_ value: Bool) { lock.withLock { stored.append(value) } }
    var values: [Bool] { lock.withLock { stored } }
}

private struct Pixels {
    let width: Int, height: Int, scale: CGFloat
    let data: [UInt8]

    init(rep: NSBitmapImageRep, scale: CGFloat) {
        self.init(image: rep.cgImage!, scale: scale)
    }

    init(image: CGImage, scale: CGFloat = 1) {
        width = image.width; height = image.height; self.scale = scale
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &buffer, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        data = buffer
    }

    /// `point` in points from the top left; an image rendered at 2× is sampled at 2× too.
    func rgb(at point: CGPoint) -> (Int, Int, Int) {
        let x = min(width - 1, max(0, Int(point.x * scale))), y = min(height - 1, max(0, Int(point.y * scale)))
        let i = (y * width + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    func luminance(at point: CGPoint) -> Int {
        let c = rgb(at: point)
        return Int(Double(c.0) * 0.2126 + Double(c.1) * 0.7152 + Double(c.2) * 0.0722)
    }

    func near(_ point: CGPoint, _ expected: (Int, Int, Int), tolerance: Int) -> Bool {
        let c = rgb(at: point)
        return abs(c.0 - expected.0) <= tolerance && abs(c.1 - expected.1) <= tolerance && abs(c.2 - expected.2) <= tolerance
    }
}

private extension Theme.RGBA {
    var rgb255: (Int, Int, Int) { (Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded())) }
}
