import AppKit
import MXRCore
import MXRDesign
import MXRMockBackend
import QuartzCore
@testable import MXRUI
import SwiftUI
import XCTest

/// Final-polish B-controls: what the control bar draws where Figma 177:99, video 03m29.3 / 15m27.1
/// and VLC semantics define it (D048).
@MainActor final class ControlBarParityTests: XCTestCase {
    // MARK: Rendering helpers

    private struct Pixels {
        let width: Int, height: Int
        let data: [UInt8]
        func rgba(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            let i = (y * width + x) * 4
            return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]), Int(data[i + 3]))
        }
    }

    private func render(_ view: some View, size: CGSize, background: SwiftUI.Color) -> Pixels {
        let content = view.frame(width: size.width, height: size.height).background(background)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.cgImage else { XCTFail("render failed"); return Pixels(width: 0, height: 0, data: []) }
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Pixels(width: width, height: height, data: data)
    }

    /// The brightest channel value of the glyph (the centre of the tile, where the icon is drawn).
    private func brightestGlyph(_ pixels: Pixels) -> Int {
        var best = 0
        for y in pixels.height / 4..<pixels.height * 3 / 4 {
            for x in pixels.width / 4..<pixels.width * 3 / 4 {
                let p = pixels.rgba(x, y); best = max(best, p.r, p.g, p.b)
            }
        }
        return best
    }

    // MARK: Icon hover (Figma Icon Wrapper 177:99)

    func testHoverAddsOnlyTheTileAndKeepsTheGlyphColour() {
        let box = Theme.Metric.ControlBar.iconButton
        let size = CGSize(width: box.width, height: box.height)
        let idle = render(MXRPlayerIconTile(icon: .queue, active: false, hovered: false, box: box), size: size, background: .black)
        let hover = render(MXRPlayerIconTile(icon: .queue, active: false, hovered: true, box: box), size: size, background: .black)
        // The glyph stays FG/A2 (#8F8F8F); a brightened glyph would reach FG/1.
        let fgA2 = Int((Theme.Color.fgA2.value(scheme: .dark, accent: .orange, contrast: .standard).red * 255).rounded())
        XCTAssertEqual(brightestGlyph(idle), fgA2, accuracy: 3)
        XCTAssertEqual(brightestGlyph(hover), brightestGlyph(idle), accuracy: 3, "hover must not brighten the glyph")
        // The 6 % white tile appears: an empty spot inside the tile (away from the glyph) lifts off black.
        let spot = (x: 3 * 2, y: hover.height / 2)
        XCTAssertEqual(idle.rgba(spot.x, spot.y).r, 0)
        XCTAssertGreaterThan(hover.rgba(spot.x, spot.y).r, 8)
    }

    // MARK: Live streams

    func testLiveStreamDrawsNoHeadAndKnownLengthDoes() {
        let source = ManualSource()
        source.timerPoint = TimerPoint(time: .seconds(754), length: .zero, position: 0, rate: 1, hostTime: CACurrentMediaTime())
        let clock = PlaybackClock(source: source, schedulesTicks: false)
        let view = SeekProgressNSView(frame: CGRect(x: 0, y: 0, width: 1000, height: 24))
        view.configure(clock: clock, width: 996, head: Theme.Metric.ControlBar.playhead, samples: nil, resume: nil,
                       visible: false, reduceMotion: true, rate: 1, scheme: .dark, accent: .orange)
        XCTAssertFalse(view.rendersHead, "a stream without a length has no position on the track")

        source.timerPoint = TimerPoint(time: .seconds(10), length: .seconds(100), position: 0.1, rate: 1, hostTime: CACurrentMediaTime())
        source.send(.updated)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(view.rendersHead)
        view.stop()
    }

    func testLiveStreamDurationReadsDashesNotZero() {
        let app = AppModel.mock(.stream)
        XCTAssertEqual(app.clock.length, .zero)
        XCTAssertEqual(MXRTimeLabel.durationText(length: app.clock.length, remaining: nil), "--:--:--")
        XCTAssertEqual(MXRTimeLabel.durationText(length: app.clock.length, remaining: app.clock.displayRemaining), "--:--:--")
        XCTAssertEqual(MXRTimeLabel.durationText(length: .hms(0, 25, 40), remaining: nil), "00:25:40")
        XCTAssertEqual(MXRTimeLabel.durationText(length: .hms(0, 25, 40), remaining: .hms(0, 23, 30)), "-00:23:30")
    }

    // MARK: Music head corner

    func testMusicHeadIsAPillNotANotchedCap() {
        let clock = PlaybackClock(source: ManualSource(), schedulesTicks: false)
        let view = SeekProgressNSView(frame: CGRect(x: 0, y: 0, width: 1000, height: 24))
        let head = MXRPlayerMetrics.musicPlayhead
        XCTAssertGreaterThan(head.radius ?? 0, head.width / 2, "Figma's radius exceeds half the 4 pt head")
        view.configure(clock: clock, width: 996, head: head, samples: nil, resume: nil,
                       visible: false, reduceMotion: true, rate: 1, scheme: .dark, accent: .orange)
        XCTAssertEqual(view.renderedHeadCornerRadius, head.width / 2, "CALayer must get Figma's clamped radius")
        view.stop()
    }

    func testPlayedWaveformIsAccentDimAndTheHeadAccentMain() {
        let source = ManualSource()
        source.timerPoint = TimerPoint(time: .seconds(10), length: .seconds(100), position: 0.1, rate: 1, hostTime: CACurrentMediaTime())
        let clock = PlaybackClock(source: source, schedulesTicks: false)
        let view = SeekProgressNSView(frame: CGRect(x: 0, y: 0, width: 1000, height: 24))
        view.configure(clock: clock, width: 996, head: MXRPlayerMetrics.musicPlayhead,
                       samples: WaveformSamples([0.25, 0.5, 0.75, 1, 0.5]), resume: nil,
                       visible: false, reduceMotion: true, rate: 1, scheme: .dark, accent: .orange)
        let dim = Theme.Color.accentDim.value(scheme: .dark, accent: .orange).cgColor
        XCTAssertEqual(view.renderedPlayedWaveformColor?.components, dim.components,
                       "Figma 4778:26181 draws the played bars #AB6314")
        view.stop()
    }

    // MARK: Seek thumbnail placement (video 03m29.3)

    func testThumbnailCardFloatsAboveTheBarCentredOnThePointer() {
        let card = Theme.Metric.ControlBar.seekThumbnail
        let track = Theme.Metric.ControlBar.seekTrack
        let bar = Theme.Metric.ControlBar.bar
        let origin = MXRSeekBar.previewOrigin(pointerX: 600, barWidth: track.width, window: -254...1666)
        XCTAssertEqual(origin.x + card.width / 2, 600, "centred on the pointer")
        // The card's bottom clears the control bar's top edge (the track is inset in the bar).
        let barTopInTrack = -(bar.height - track.height) / 2
        XCTAssertLessThan(origin.y + card.height, barTopInTrack, "the card never overlaps the bar")
        XCTAssertEqual(origin.y + card.height, barTopInTrack - Theme.Spacing.gap5)
    }

    func testThumbnailCardStaysCentredPastTheTrackEndsAndInsideTheWindow() {
        let card = Theme.Metric.ControlBar.seekThumbnail
        let window: ClosedRange<CGFloat> = -254...1666
        // Near the track's start there is room in the window: still centred (not clamped to the bar).
        let start = MXRSeekBar.previewOrigin(pointerX: 4, barWidth: 1238, window: window)
        XCTAssertEqual(start.x + card.width / 2, 4)
        // At the window edge it slides in, keeping the framed video's inset.
        let tight = MXRSeekBar.previewOrigin(pointerX: 4, barWidth: 1238, window: -60...1300)
        XCTAssertEqual(tight.x, -60 + Theme.Metric.Window.videoArea.padding.leading)
        let end = MXRSeekBar.previewOrigin(pointerX: 1238, barWidth: 1238, window: -60...1300)
        XCTAssertEqual(end.x + card.width, 1300 - Theme.Metric.Window.videoArea.padding.trailing)
        // Without a window (a bar on its own) it stays over the bar.
        let alone = MXRSeekBar.previewOrigin(pointerX: 0, barWidth: 1238, window: nil)
        XCTAssertEqual(alone.x, 0)
    }

    // MARK: OSD (B-08, key frame 15m27.1)

    func testOSDAnchorsToThePillarboxedPictureAndStaysClearOfPanels() {
        let canvas = CGRect(x: 10, y: 41, width: 1900, height: 985)
        // 4:3 in a wide canvas: pillarboxed, the picture's right edge is well inside the canvas.
        let picture = Theme.OSD.pictureRect(canvas: canvas, videoSize: CGSize(width: 640, height: 480))
        XCTAssertEqual(picture.height, 985, accuracy: 0.01)
        XCTAssertEqual(picture.midX, canvas.midX, accuracy: 0.01)
        let info = CGRect(x: 20, y: 60, width: 1880, height: 946)
        XCTAssertEqual(Theme.OSD.anchorRect(picture: picture, bounds: info).maxX, picture.maxX, accuracy: 0.01,
                       "the OSD sits on the picture, not in the pillarbox")
        // A right panel covering the picture's edge: the OSD moves left of it.
        let withPanel = CGRect(x: 20, y: 60, width: 1000, height: 946)
        XCTAssertEqual(Theme.OSD.anchorRect(picture: picture, bounds: withPanel).maxX, withPanel.maxX, accuracy: 0.01)
        // The size follows the picture in the canvas, not the narrower information rect.
        let styles = Theme.OSD.styles(videoHeight: picture.height)
        XCTAssertEqual(styles.title.size, 985 * Theme.OSD.titleHeightFraction, accuracy: 0.01)
    }

    func testOSDTextHasVLCsDarkOutlineOnABrightFrame() {
        let style = Theme.OSD.styles(videoHeight: 1000).title
        let pixels = render(MXROSDLine(text: "Crop: 2.35:1", style: style),
                            size: CGSize(width: 400, height: 90), background: .white)
        var darkest = 255
        for y in 0..<pixels.height { for x in 0..<pixels.width { darkest = min(darkest, pixels.rgba(x, y).r) } }
        // A crisp black edge (VLC freetype outline), not the soft 46 % menu shadow (~140 at best on white).
        XCTAssertLessThan(darkest, 40)
    }

    /// VLC casts one 50 % shadow from the outlined glyph. The nine layers of the line must be shadowed
    /// as one: shadowing each layer stacks the 50 % shadows into a near-black halo (S13 parity).
    func testOSDShadowIsOneHalfOpaqueLayer() {
        let style = Theme.OSD.styles(videoHeight: 1000).title
        let grey = 200.0 / 255
        let pixels = render(MXROSDLine(text: "l", style: style), size: CGSize(width: 60, height: 90),
                            background: SwiftUI.Color(red: grey, green: grey, blue: grey))
        // Pixels whose value is the background at half strength: the shadow seen past the outline.
        var halfShadow = 0
        for y in pixels.height / 3..<pixels.height * 2 / 3 {
            for x in 0..<pixels.width where (90...110).contains(pixels.rgba(x, y).r) { halfShadow += 1 }
        }
        XCTAssertGreaterThan(halfShadow, 20, "the shadow beside the outlined stem is 50 % black over the frame")
    }

    // MARK: Play/pause hover and disabled controls

    /// Figma has no hover for the play tile; the bar's rule (Icon Wrapper 177:99) puts the `iconHover`
    /// tile over its fill, so Play stays Accent/Main under the pointer (no switch to Accent/DIm) and
    /// Pause reacts as well.
    func testPlayAndPauseHoverAddTheBarHoverTile() {
        func fill(playing: Bool, hovered: Bool) -> (r: Int, g: Int, b: Int, a: Int) {
            let box = playing ? Theme.Metric.ControlBar.pauseButton : Theme.Metric.ControlBar.playButton
            let pixels = render(MXRPlayPauseTile(playing: playing, hovered: hovered, editing: false),
                                size: box.size, background: .black)
            return pixels.rgba(4 * 2, pixels.height / 2) // inside the tile, left of the glyph
        }
        let accent = Theme.Color.accentMain.value(scheme: .dark, accent: .orange)
        let hover = Theme.Color.iconHover.value(scheme: .dark, accent: .orange)
        func over(_ c: Double, _ h: Double) -> Int { Int(((c * (1 - hover.alpha) + h * hover.alpha) * 255).rounded()) }
        let play = fill(playing: false, hovered: true)
        XCTAssertEqual(play.r, over(accent.red, hover.red), accuracy: 2, "hovered Play is Accent/Main under the hover tile")
        XCTAssertEqual(play.g, over(accent.green, hover.green), accuracy: 2)
        XCTAssertEqual(play.b, over(accent.blue, hover.blue), accuracy: 2)
        let idle = fill(playing: false, hovered: false)
        XCTAssertEqual(idle.r, Int((accent.red * 255).rounded()), accuracy: 2)
        let pause = fill(playing: true, hovered: false), pauseHover = fill(playing: true, hovered: true)
        XCTAssertGreaterThan(pauseHover.r + pauseHover.g + pauseHover.b, pause.r + pause.g + pause.b + 6,
                             "Pause shows the same hover as every other bar control")
    }

    /// An unavailable bar control draws at Figma's disabled opacity (Player-6 I856:2587;848:1877, 30 %).
    func testDisabledBarControlUsesFigmasDisabledOpacity() {
        let box = Theme.Metric.ControlBar.iconButton
        func glyph(enabled: Bool) -> Int {
            brightestGlyph(render(MXRPlayerIconButton(.queue, title: "Queue", box: box) {}.disabled(!enabled),
                                  size: box.size, background: .black))
        }
        let ratio = Double(glyph(enabled: false)) / Double(glyph(enabled: true))
        XCTAssertEqual(ratio, Theme.Metric.ControlBar.iconButtonDisabledOpacity, accuracy: 0.03)
        XCTAssertEqual(Theme.Metric.ControlBar.iconButtonDisabledOpacity, 0.3, accuracy: 0.001)
    }

    // MARK: Volume cone gradient (244:183–244:240)

    /// The cone draws 244:214's paint: its stops' exact sRGB values under the 20 % black layer. The
    /// hex-rounded stops (#95D318, #B2A918) drew every column up to 0.4/255 redder (C.VolumeCone FAILs).
    func testConeGradientDrawsFigmasExactStops() {
        let size = MXRPlayerMetrics.coneFillSize
        let pixels = render(VolumeConeGradient(), size: size, background: .black)
        // gradientStops of 244:214 (figma_file.json), handles at x = -2.5 and 87.5 of the 86 pt vector.
        let stops: [(Double, [Double])] = [(0, [0.5830065608, 0.8274509907, 0.0941176489]),
                                           (0.5788085461, [0.6960828900, 0.6641857028, 0.0941176489]),
                                           (0.7923790812, [0.8274509907, 0.4745098054, 0.0941176489]),
                                           (1, [1, 0.2150127739, 0.2150127739])]
        func paint(_ t: Double) -> [Double] {
            let t = min(max(t, 0), 1)
            for (a, b) in zip(stops, stops.dropFirst()) where t <= b.0 {
                let f = (t - a.0) / (b.0 - a.0)
                return (0..<3).map { (a.1[$0] + f * (b.1[$0] - a.1[$0])) * 0.8 * 255 }
            }
            return stops.last!.1.map { $0 * 0.8 * 255 }
        }
        // The green-to-yellow run (t 0.05…0.55), where the rounded stops were 0.26–0.4/255 too red;
        // 8-bit output is compared with the 8-bit value of the paint, over two rows (dithering).
        var bias = [0.0, 0.0], count = 0.0
        for y in [pixels.height / 2, pixels.height / 2 + 1] {
            for x in 0..<pixels.width {
                let t = (Double(x) / 2 + 0.25 + 2.5) / 90
                guard (0.05...0.55).contains(t) else { continue }
                let expected = paint(t), p = pixels.rgba(x, y)
                bias[0] += Double(p.r) - expected[0].rounded(); bias[1] += Double(p.g) - expected[1].rounded()
                count += 1
            }
        }
        for (channel, total) in zip(["red", "green"], bias) {
            XCTAssertEqual(total / count, 0, accuracy: 0.15, "mean \(channel) offset from the Figma paint")
        }
    }

    // MARK: Play control after the end of the media (live run 1)

    /// VLC after the last item ends: STOPPED, the media kept, the clock at the end. The button draws
    /// the orange Play tile (not the grey Pause one), and pressing it starts playback again.
    func testPlayControlAfterTheEndShowsPlayAndRestarts() {
        let mock = MockBackend(scenario: .playingEpisode)
        guard let media = mock.player.currentMedia, let length = media.duration else { return XCTFail("fixture media") }
        mock.player.load(media, at: length, state: .stopped)
        let app = mock.makeAppModel()
        let box = Theme.Metric.ControlBar.playButton
        func fill() -> (r: Int, g: Int, b: Int, a: Int) {
            let pixels = render(MXRPlayPauseButton().appModel(app), size: box.size, background: .black)
            return pixels.rgba(4 * 2, pixels.height / 2) // inside the tile, left of the glyph
        }
        let accent = Theme.Color.accentMain.value(scheme: .dark, accent: .orange)
        let ended = fill()
        XCTAssertEqual(ended.r, Int((accent.red * 255).rounded()), accuracy: 3, "Play tile after the end")
        XCTAssertEqual(ended.g, Int((accent.green * 255).rounded()), accuracy: 3)

        app.playOrOpenLibrary()
        XCTAssertEqual(mock.player.commandLog.last, "play", "a stopped player is started, not toggled")
        XCTAssertEqual(app.player.state, .playing)
        let playing = fill()
        XCTAssertLessThan(playing.r, 120, "the grey FG/A3 Pause tile replaces the orange Play tile")
    }
}

private final class ManualSource: PlaybackClockSource {
    var timerPoint: TimerPoint?
    private var handler: (@MainActor (ClockEvent) -> Void)?
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (ClockEvent) -> Void) { self.handler = handler }
    @MainActor func send(_ event: ClockEvent) { handler?(event) }
}
