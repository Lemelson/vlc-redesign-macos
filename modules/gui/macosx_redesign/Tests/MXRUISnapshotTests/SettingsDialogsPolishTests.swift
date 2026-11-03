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

    /// The rows the dialog body covers in column x 480 (the dark body, not its soft shadow).
    private func dialogRows(_ sheet: AppSheet, in size: CGSize) throws -> (top: CGFloat, bottom: CGFloat) {
        let app = AppModel.mock(.playingEpisode)
        app.interface.present(sheet)
        let pixels = try draw(Color.white.mxrDialogPresentation().appModel(app), size: size)
        let rows = (0..<Int(size.height)).filter { pixels.luminance(at: CGPoint(x: size.width / 2, y: CGFloat($0))) < 100 }
        return (CGFloat(try XCTUnwrap(rows.first)), CGFloat(try XCTUnwrap(rows.last)) + 1)
    }

    func testShrunkDialogStaysBelowTheTopBar() throws {
        // S48.App/settings-compact: in a 960×540 window Settings ran from y 20, under the traffic lights;
        // live run 2: in the real window Settings, Convert and Properties then started exactly at the
        // top bar's bottom edge (y 40), with no panel inset between.
        let compact = CGSize(width: 960, height: 540)
        let clearance = Theme.Metric.topBarHeight + Theme.Metric.panelInset
        let settings = try dialogRows(.settings(categoryID: "controls"), in: compact)
        XCTAssertEqual(settings.top, clearance, accuracy: 1, "Settings starts a panel inset below the 40 pt top bar")
        XCTAssertEqual(settings.bottom, compact.height - Theme.Metric.panelInset, accuracy: 1, "and fills the window down to a panel inset")
        // Open Disc (432 pt) still gets its full design height (live run 2: about 713×434).
        let disc = try dialogRows(.openDisc, in: compact)
        XCTAssertGreaterThanOrEqual(disc.top, clearance - 1, "Open Disc keeps the same gap below the top bar")
        XCTAssertEqual(disc.bottom - disc.top, AppSheet.openDisc.preferredSize.height, accuracy: 1, "at its design height")
        // A dialog that fits stays exactly centred, as in the video (S48.App/settings at 1080).
        let tall = CGSize(width: 1920, height: 1080)
        let centred = try dialogRows(.settings(categoryID: "controls"), in: tall)
        XCTAssertEqual(centred.top + centred.bottom, tall.height, accuracy: 2, "centred in a 1080 window")
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

    func testScaleLabelsStandUnderTheirTicks() throws {
        // 3062:13083 (Default playback speed, 320 pt, a label on each of 8 ticks): Figma spreads 26 pt
        // label boxes space-between two 18 pt end frames, so "0.5" is centred at x 49.3, "1" at 137.9
        // and "1.75" at 270.7; "0.25" starts 2 pt in and "2" ends 2 pt before the end. Measured on the
        // drawn ink against Figma's render (critic P2: "0.5" and "1.75" sat 1.4 pt off when the labels
        // were centred on the tick spacing).
        let labels = ["0.25", "0.5", "0.75", "1", "1.25", "1.5", "1.75", "2"]
        let size = CGSize(width: 320, height: 57)
        let slider = SettingsSlider(value: .constant(1), range: 0.25...2, step: 0.25, ticks: 8, labels: labels, label: "Speed")
        let pixels = try draw(slider.background(Color.black), size: size, scale: 2)
        let band = (Int(size.height - Theme.Spacing.gap4 - Theme.Metric.SettingsDetail.sliderLabelHeight) * 2)..<(Int(size.height - Theme.Spacing.gap4) * 2)
        let inked = (0..<Int(size.width * 2)).filter { x in
            band.contains { y in pixels.luminance(at: CGPoint(x: CGFloat(x) / 2, y: CGFloat(y) / 2)) > 40 }
        }
        // Runs of inked columns; a label's glyphs are never 5 pt apart, two labels always are.
        var runs: [(first: Int, last: Int)] = []
        for x in inked {
            if let last = runs.last, x - last.last <= 10 { runs[runs.count - 1].last = x } else { runs.append((x, x)) }
        }
        XCTAssertEqual(runs.count, labels.count, "every label is drawn on its own")
        guard runs.count == labels.count else { return }
        // The ink of each label in Figma's own render (Settings - playback.png at 2×, same threshold).
        // Left edges are compared only where the label does not start with "1": Figma rasterizes the
        // 1's thin flag below the threshold.
        let figmaLeft: [CGFloat] = [2.5, 41, 82, 138, 173.5, 221.5, 262.5, 311.5]
        let figmaRight: [CGFloat] = [26.5, 57.5, 105, 139, 193, 233.5, 281, 317]
        for (i, text) in labels.enumerated() {
            XCTAssertEqual(CGFloat(runs[i].last + 1) / 2, figmaRight[i], accuracy: 0.75, "\(text) ends where Figma's does")
            if !text.hasPrefix("1") {
                XCTAssertEqual(CGFloat(runs[i].first) / 2, figmaLeft[i], accuracy: 0.75, "\(text) starts where Figma's does")
            }
        }
        // 3176:16483 (Maximum volume, 3 labels on 7 ticks): the ends sit on the track's edges, the
        // middle label in the middle.
        let width: CGFloat = 320
        XCTAssertEqual(SettingsSlider.labelAnchor(index: 0, count: 3, width: width, ticks: 7).x, 0)
        XCTAssertEqual(SettingsSlider.labelAnchor(index: 2, count: 3, width: width, ticks: 7).x, width)
        XCTAssertEqual(SettingsSlider.labelAnchor(index: 1, count: 3, width: width, ticks: 7).x, width / 2, accuracy: 0.01)
    }

    func testGeneralAccentSwatchesFollowTheThemeLikeOnboarding() throws {
        // Critic P2 / D049: Settings › General drew the dark swatch hex #D37918 in Light while the
        // onboarding swatches draw Light/Accent/Main. The selected (orange) swatch sits at 722,178.
        for (id, scheme) in [("S48.Settings/general", ColorScheme.dark), ("S48.Settings/general-light", .light)] {
            let entry = try XCTUnwrap(GalleryCatalog.entry(id: id))
            let pixels = Pixels(image: try GalleryRenderer.render(entry, scale: 1, environment: GalleryEnvironment(colorScheme: scheme)))
            let rgba = Theme.Color.accentMain.value(scheme: scheme, accent: .orange, contrast: .standard)
            let expected = (Int((rgba.red * 255).rounded()), Int((rgba.green * 255).rounded()), Int((rgba.blue * 255).rounded()))
            XCTAssertTrue(pixels.near(CGPoint(x: 722, y: 178), expected, tolerance: 3),
                          "\(scheme): the orange swatch is \(pixels.rgb(at: CGPoint(x: 722, y: 178))), Accent/Main is \(expected)")
        }
    }

    func testNarrowStartupVolumeKeepsToItsColumn() throws {
        // S48.Settings/narrow (480 pt, Audio): keeping "Always starts at:" beside its value grew the
        // stacked control to 228 pt, past the 180 pt column, and wrapped "Startup volume" (F-settings
        // verifier). The control now starts where the dropdowns above it start.
        let entry = try XCTUnwrap(GalleryCatalog.entry(id: "S48.Settings/narrow"))
        let pixels = Pixels(image: try GalleryRenderer.render(entry, scale: 1))
        func isAccentFill(_ x: Int, _ y: Int) -> Bool {
            let c = pixels.rgb(at: CGPoint(x: x, y: y)); return c.0 - c.2 > 25 && c.0 < 120
        }
        // The selected "Remember last volume" choice: the first row with its accent fill below the
        // Maximum volume slider (its scale labels end at y 360).
        let choiceRow = try XCTUnwrap((370..<520).first { y in (300..<450).contains { isAccentFill($0, y) } })
        let choiceLeft = try XCTUnwrap((150..<450).first { isAccentFill($0, choiceRow + 4) })
        // The Speaker setup dropdown (y 220): its dark field starts at the column's edge.
        let dropdownLeft = try XCTUnwrap((150..<450).first { pixels.luminance(at: CGPoint(x: $0, y: 220)) < 15 })
        XCTAssertGreaterThanOrEqual(CGFloat(choiceLeft), CGFloat(dropdownLeft), "the stacked control keeps to the control column")
    }

    func testShortcutFieldDrawsTheCommandGlyphAtKeySize() throws {
        // S64 (C-bridge note): DM Mono has no ⌘, and font fallback drew it about half as tall as "F".
        let size = CGSize(width: Theme.Metric.SettingsDetail.shortcutFieldWidth, height: Theme.Metric.SettingsDetail.shortcutFieldHeight)
        let field = ShortcutKeyField(text: "⌘F", isRecording: false, width: size.width, label: "Hotkey",
                                     start: {}, onKey: { _ in }, onCancel: {})
        let pixels = try draw(field.background(Color.black), size: size, scale: 2)
        // Ink columns of the centred text (the edit icon sits in the trailing 34 pt).
        let columns = (0..<Int((size.width - 40) * 2)).filter { x in
            (0..<Int(size.height * 2)).contains { pixels.luminance(at: CGPoint(x: CGFloat(x) / 2, y: CGFloat($0) / 2)) > 60 }
        }
        var runs: [ClosedRange<Int>] = []
        for x in columns {
            if let last = runs.last, x - last.upperBound <= 2 { runs[runs.count - 1] = last.lowerBound...x } else { runs.append(x...x) }
        }
        XCTAssertEqual(runs.count, 2, "⌘ and F")
        guard runs.count == 2 else { return }
        func inkHeight(_ run: ClosedRange<Int>) -> Int {
            let rows = (0..<Int(size.height * 2)).filter { y in
                run.contains { pixels.luminance(at: CGPoint(x: CGFloat($0) / 2, y: CGFloat(y) / 2)) > 60 }
            }
            return (rows.last ?? 0) - (rows.first ?? 0) + 1
        }
        let command = inkHeight(runs[0]), key = inkHeight(runs[1])
        XCTAssertGreaterThanOrEqual(Double(command), Double(key) * 0.8, "⌘ is \(command) px tall, F \(key) px")
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
