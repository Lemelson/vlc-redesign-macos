import AppKit
import MXRCore
import MXRDesign
import MXRMockBackend
@testable import MXRUI
import SwiftUI
import XCTest

/// G-panels final wave: what the side-panel cards draw where Figma defines it, and the values behind
/// them (open filter cards 536:1514/536:1860/614:1435, Font Size 804:1341, Subtitle Speed 804:1170,
/// delay sliders 1905:7365, the preset list 2372:8838, the track popover 491:2243/496:2523).
@MainActor final class FilterCardParityTests: XCTestCase {
    private struct Pixels {
        let width: Int, height: Int, scale: Int
        let data: [UInt8]
        /// The colour at a point in pt.
        func hex(_ x: CGFloat, _ y: CGFloat) -> Int {
            let i = (Int(y) * scale * width + Int(x) * scale) * 4
            return Int(data[i]) << 16 | Int(data[i + 1]) << 8 | Int(data[i + 2])
        }
        /// The colour of one device pixel.
        func hex(px x: Int, _ y: Int) -> Int {
            let i = (y * width + x) * 4
            return Int(data[i]) << 16 | Int(data[i + 1]) << 8 | Int(data[i + 2])
        }
        /// The device pixels in a row span whose grey level is above `threshold`.
        func bright(row y: Int, from x0: Int, to x1: Int, threshold: Int = 0x30) -> [(x: Int, level: Int)] {
            (x0..<x1).compactMap { x in
                let level = hex(px: x, y) & 0xFF
                return level > threshold ? (x, level) : nil
            }
        }
    }

    private func render(_ view: some View, size: CGSize) -> Pixels {
        let content = view.frame(width: size.width, height: size.height).background(SwiftUI.Color.black)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.cgImage else { XCTFail("render failed"); return Pixels(width: 0, height: 0, scale: 2, data: []) }
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Pixels(width: image.width, height: image.height, scale: 2, data: data)
    }

    private func token(_ color: ThemeColor) -> Int {
        let rgba = color.value(scheme: .dark, accent: .orange, contrast: .standard)
        return Int((rgba.red * 255).rounded()) << 16 | Int((rgba.green * 255).rounded()) << 8 | Int((rgba.blue * 255).rounded())
    }

    // MARK: Open filter cards (S18/S19, parity group 4)

    /// Figma 536:1514 and 08m49.0: the open card is one BG/A3 container that holds the "Collapse
    /// Settings" header and every row, inset; the closed card is the BG/B2 bar (536:1512).
    func testOpenCardIsOneLighterContainerAroundHeaderAndRows() {
        let app = AppModel.mock(.playingEpisode)
        let open = render(MXRFilterCardPreview(.compressor).appModel(app), size: CGSize(width: 360, height: 590))
        let bgA3 = token(Theme.Color.bgA3)
        XCTAssertEqual(open.hex(200, 24), bgA3, "the Collapse Settings header sits on the card, not on a dark bar")
        // Left of the rows' 16 pt inset, between two sliders and under the last one: still the card.
        XCTAssertEqual(open.hex(8, 300), bgA3, "rows are inside the container")
        XCTAssertEqual(open.hex(8, 584), bgA3, "the card's 10 pt bottom padding closes it under the last row")
        // The value is plain text right-aligned on the label's row: no field box behind it (536:1544).
        XCTAssertEqual(open.hex(300, 56), bgA3, "Compressor values are text, not fields")

        let closed = render(MXRFilterCardPreview(.essential, expanded: false).appModel(app), size: CGSize(width: 360, height: 48))
        XCTAssertEqual(closed.hex(200, 8), token(Theme.Color.bgB2))
    }

    /// 536:1860: Essential has label-only rows and no "Enable Adjustments" switch; the sliders alone
    /// switch VLC's `adjust` filter on and off.
    func testEssentialSlidersDriveTheAdjustFilterWithoutASwitch() {
        let app = AppModel.mock(.playingEpisode)
        XCTAssertFalse(app.videoEffects.effects.essential.isEnabled)
        app.videoEffects.updateEssential { $0.hue = 30 }
        XCTAssertTrue(app.videoEffects.effects.essential.isEnabled)
        app.videoEffects.updateEssential { $0.hue = 0 }
        XCTAssertFalse(app.videoEffects.effects.essential.isEnabled, "back at neutral, the filter is removed")
        app.videoEffects.updateEssential { $0.sharpenSigma = 1 }
        XCTAssertFalse(app.videoEffects.effects.essential.isEnabled, "sharpen is its own filter, not adjust")
    }

    /// 673:1691: Sepia Intensity is the Colors card's only sepia control; 0 means off.
    func testSepiaIntensityZeroIsOffAndAnyOtherValueAppliesIt() {
        let app = AppModel.mock(.playingEpisode)
        XCTAssertEqual(app.videoEffects.sepiaIntensity, 0)
        app.videoEffects.setSepiaIntensity(85)
        XCTAssertTrue(app.videoEffects.effects.colors.sepia)
        XCTAssertEqual(app.videoEffects.effects.colors.sepiaIntensity, 85)
        app.videoEffects.setSepiaIntensity(0)
        XCTAssertFalse(app.videoEffects.effects.colors.sepia)
        XCTAssertEqual(app.videoEffects.effects.colors.sepiaIntensity, 85, "the last intensity is kept for next time")
        XCTAssertEqual(app.videoEffects.sepiaIntensity, 0)
    }

    /// The gradient mode dropdown (673:1670) is VLC's `gradient-mode`; values saved before it existed
    /// still decode.
    func testGradientModeIsStoredAndOldValuesDecode() throws {
        let app = AppModel.mock(.playingEpisode)
        app.videoEffects.update { $0.colors.gradientMode = "edge" }
        XCTAssertEqual(app.videoEffects.effects.colors.gradientMode, "edge")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ColorVideoFilters())) as! [String: Any]
        json.removeValue(forKey: "gradientMode")
        let decoded = try JSONDecoder().decode(ColorVideoFilters.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.gradientMode, ColorVideoFilters.defaultGradientMode)
        XCTAssertFalse(ColorVideoFilters().gradientColor, "VLC's gradient-color default is off")
    }

    // MARK: Subtitles tab (S20)

    /// Owner decision on D033 (804:1341): "Auto" is stop 3 of 0…5, the text grows left to right.
    func testFontSizeSliderPutsAutoInTheMiddleAndGrowsToTheRight() {
        let order = SubtitleRelativeSize.sliderOrder
        XCTAssertEqual(Set(order), Set(SubtitleRelativeSize.allCases))
        XCTAssertEqual(order.firstIndex(of: .automatic), 3)
        // VLC's freetype-rel-fontsize is a divisor: a larger value is a smaller font.
        let sizes = order.filter { $0 != .automatic }.map(\.rawValue)
        XCTAssertEqual(sizes, sizes.sorted(by: >), "smaller sizes left of Auto, larger to its right")
    }

    /// 804:1170: "1.000 fps" with the thumb at the start; VLC treats sub-fps ≤ 1 as not overridden.
    func testSubtitleSpeedShowsOneFpsAtTheStartOfItsRange() {
        let app = AppModel.mock(.playingEpisode)
        app.tracks.setSubtitleFPS(0)
        XCTAssertEqual(app.tracks.subtitleSpeed, 1)
        XCTAssertEqual(app.tracks.subtitleSpeed, TracksModel.subtitleSpeedRange.lowerBound, "the thumb sits at the start")
        app.tracks.setSubtitleSpeed(0.5)
        XCTAssertEqual(app.tracks.subtitleFPS, 1)
        app.tracks.setSubtitleSpeed(23.976)
        XCTAssertEqual(app.tracks.subtitleFPS, 23.976, accuracy: 0.001)
        app.tracks.setSubtitleSpeed(500)
        XCTAssertEqual(app.tracks.subtitleFPS, TracksModel.subtitleSpeedRange.upperBound)
    }

    /// 1905:7365 (delays): the fill runs from the zero point, the thumb centre under "0 s", and the
    /// "-10 s" label is flush with the track's left end (1905:7369 spaces its labels edge to edge).
    func testDelaySliderFillsFromItsZeroPointAndItsLabelsSpanTheTrack() throws {
        let width: CGFloat = 360
        let image = render(delayControl(title: "Subtitle Track Delay", value: -4, set: { _ in }), size: CGSize(width: width, height: 110))
        let bgB2 = token(Theme.Color.bgB2), fill = token(Theme.Color.bgAccentBright)
        // The track's centre row: the first row whose left end is the empty track.
        let trackRow = try XCTUnwrap((0..<image.height).first { image.hex(px: 8, $0) == bgB2 }) + Int(PanelMetric.sliderTrackHeight)
        // 1905:7367: for -4 s the fill runs 107…184 pt, from the thumb to the far edge of the thumb
        // at 0 s (176…184); the thumb 1905:7368 starts at 107 (2 + 0.3 × 348 = 106.4 here).
        XCTAssertEqual(image.hex(px: 2 * 184 - 2, trackRow), fill, "the fill covers the 0 s thumb's position")
        XCTAssertEqual(image.hex(px: 2 * 184 + 2, trackRow), bgB2, "and ends at its far edge, 184 pt")
        let accent = token(Theme.Color.accentDim)
        let thumbStart = try XCTUnwrap((0..<image.width).first { image.hex(px: $0, trackRow) == accent })
        XCTAssertEqual(Double(thumbStart) / 2, 106.4, accuracy: 1, "the -4 s thumb starts where 1905:7368 does")
        // The labels row: the lowest rows that draw anything.
        let labelRows = (trackRow + 20..<image.height)
        let left = labelRows.compactMap { image.bright(row: $0, from: 0, to: 60).first?.x }.min()
        let right = labelRows.compactMap { image.bright(row: $0, from: image.width - 80, to: image.width).last?.x }.max()
        XCTAssertLessThanOrEqual(try XCTUnwrap(left), 3, "\"-10 s\" starts at the track's left end (≤ 1.5 pt)")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(right), image.width - 4, "\"+10 s\" ends at the track's right end")
    }

    /// 2372:8838: the preset card's shadow stays outside the card (no shade around the checked row
    /// or the titles), its rows use Inter 14, and the built-in "Default Preset" starts at the 16 pt
    /// inset with no empty ⋯ slot (2372:8839).
    func testPresetListDrawsFlatRowsAtFigmaType() throws {
        let app = AppModel.mock(.playingEpisode)
        if let media = app.player.media { app.presets.assign(nil, to: media) }
        for preset in app.presets.customPresets { app.presets.delete(id: preset.id) }
        let size = CGSize(width: 364, height: 82) // "+ New Custom Preset" and the checked Default Preset
        let image = render(MXRSidebarPresetList().appModel(app).frame(maxHeight: .infinity, alignment: .bottom), size: size)
        let bgA4 = token(Theme.Color.bgA4), bgA2 = token(Theme.Color.bgA2)
        // The 2 pt gap above the checked row and the card's padding beside it are the card's own colour.
        XCTAssertEqual(image.hex(px: 360, 2 * 40 + 1), bgA4, "no shadow from the checked row onto the card")
        XCTAssertEqual(image.hex(px: 2, 2 * 60), bgA4, "no shadow at the card's padding")
        XCTAssertEqual(image.hex(px: 360, 2 * 60), bgA2, "the checked row is BG/A2")
        let title = image.bright(row: 2 * 61, from: 0, to: 2 * 200, threshold: 0x50)
        let first = try XCTUnwrap(title.first?.x), last = try XCTUnwrap(title.last?.x)
        XCTAssertEqual(Double(first) / 2, 16, accuracy: 2, "Default Preset starts at the row's 16 pt inset")
        // Inter 14 "Default Preset" is about 94 pt wide (2372:8839), 13 pt type would be about 87.
        XCTAssertGreaterThan(Double(last - first) / 2, 87, "rows use the 14 pt body type")
    }

    // MARK: Slider geometry (S18–S20)

    /// Figma's sliders: the thumb travels 2 pt inside both ends (804:1177 at 2, 607:1155 at W − 10,
    /// 1905:7355 at 176 of 360), ticks spread over 2…W − 2 (804:1287, 536:1986), and a ticked thumb is
    /// centred on its tick (804:1299 at 212, 804:1315 at 235, 607:1136 at 234).
    func testSliderGeometryMatchesFigmaThumbsFillsAndTicks() {
        let wide = PanelSliderGeometry(width: 360)
        XCTAssertEqual(wide.thumbX(0), 2, accuracy: 0.01)
        XCTAssertEqual(wide.thumbX(1), 350, accuracy: 0.01)
        XCTAssertEqual(wide.thumbX(0.5), 176, accuracy: 0.01)
        XCTAssertEqual(wide.fill(progress: 0, anchor: nil).minX, 2, accuracy: 0.01)
        XCTAssertEqual(wide.fill(progress: 0, anchor: nil).width, 8, accuracy: 0.01, "804:1176: 2…10 under the thumb")
        let delay = wide.fill(progress: 0.3, anchor: 0.5)
        XCTAssertEqual(delay.minX + delay.width, 184, accuracy: 0.01, "1905:7367 ends at 184")
        XCTAssertEqual(wide.tickCenter(0.2), 73.3, accuracy: 0.2, "804:1289")
        XCTAssertEqual(wide.tickCenter(0.6), 215.6, accuracy: 0.2, "804:1291")

        let ticked = PanelSliderGeometry(width: 360, snapsToTicks: true)
        XCTAssertEqual(ticked.thumbX(0.6), 212, accuracy: 0.5, "Font Size Auto (804:1299)")
        XCTAssertEqual(ticked.thumbX(2.0 / 3), 235, accuracy: 0.5, "Outline Normal (804:1315)")
        XCTAssertEqual(ticked.thumbX(0), 2, accuracy: 0.01, "held inside the travel at the ends (848:1698)")
        XCTAssertEqual(ticked.fraction(atX: ticked.tickCenter(0.4)), 0.4, accuracy: 0.001)
        XCTAssertEqual(PanelSliderGeometry(width: 328, snapsToTicks: true).thumbX(8.0 / 11), 234, accuracy: 0.5, "Spatializer Size 8.0 (607:1136)")
    }

    /// 536:1860, 614:1435, 612:1228: no marks at the track ends (Figma's end marks are hidden), and
    /// the `degrees` frame screen-blends BG/Accent Dark, so an inner tick on the fill reads #4B3217.
    func testSteppedSliderDrawsOnlyInnerScreenBlendedTicks() throws {
        XCTAssertEqual(PanelSlider(title: "", value: .constant(0), range: 0...1, stops: 11).tickFractions.count, 9)
        XCTAssertEqual(PanelSlider(title: "", value: .constant(0), range: 0...1, stops: 2).tickFractions, [])
        let width: CGFloat = 360
        let image = render(PanelSlider(title: "Opacity", value: .constant(1), range: 0...1, step: 0.1, stops: 11),
                           size: CGSize(width: width, height: 24))
        let fill = token(Theme.Color.bgAccentBright)
        let row = 2 * 12
        // An end tick would sit on the track 1…5 pt from its start (both the old 3…5 pt and Figma's 1…3 pt).
        for pt in [2, 4] { XCTAssertEqual(image.hex(px: 2 * pt, row), fill, "no tick at \(pt) pt, the start of the track") }
        let tick = image.hex(px: Int(2 * (2 + 0.1 * 356)), row)
        XCTAssertNotEqual(tick, token(Theme.Color.bgAccentDark), "ticks are not drawn as plain BG/Accent Dark")
        XCTAssertEqual(Double(tick >> 16), 0x4B, accuracy: 3, "screen(#1A1611 over #371F06) = #4B3217")
    }

    /// 498:2969 / 536:1094: the selected Video or Audio tab's underline is 70 pt (122…192 for Video),
    /// not the 61 pt of its content; 5187:24342: only the Playback tab draws a hairline at y 51.
    func testSidebarTabUnderlineAndPlaybackHairlineFollowFigma() throws {
        let size = CGSize(width: 400, height: 120)
        let accent = token(Theme.Color.accentMain)
        func underline(_ tab: SidebarTab) -> (CGFloat, CGFloat)? {
            let image = render(MXRSettingsSidebarView(tab: tab).appModel(AppModel.mock(.playingEpisode)), size: size)
            let xs = (0..<image.width).filter { image.hex(px: $0, 2 * 49) == accent }
            guard let first = xs.first, let last = xs.last else { return nil }
            return (CGFloat(first) / 2, CGFloat(last + 1) / 2)
        }
        let video = try XCTUnwrap(underline(.video)), audio = try XCTUnwrap(underline(.audio))
        XCTAssertEqual(video.0, 122, accuracy: 0.5); XCTAssertEqual(video.1, 192, accuracy: 0.5)
        XCTAssertEqual(audio.0, 208, accuracy: 0.5); XCTAssertEqual(audio.1, 278, accuracy: 0.5)
        let playback = try XCTUnwrap(underline(.playback))
        XCTAssertEqual(playback.1 - playback.0, 91.5, accuracy: 0.5, "wide tabs keep 5187:24314's 91.5 pt")

        // The content is in an AppKit scroll view, so draw it through a window (ImageRenderer leaves it out).
        let playbackImage = try renderHosted(MXRSettingsSidebarView(tab: .playback).appModel(AppModel.mock(.playingEpisode)), size: size)
        for x: CGFloat in [1, 200, 399] {
            XCTAssertGreaterThan(playbackImage.level(x, 51.25), playbackImage.level(x, 54) + 8,
                                 "the hairline spans the panel at x \(x) pt")
        }
        let videoImage = try renderHosted(MXRSettingsSidebarView(tab: .video).appModel(AppModel.mock(.playingEpisode)), size: size)
        XCTAssertEqual(videoImage.level(200, 51.25), videoImage.level(200, 54), accuracy: 2, "the Video tab has no such line")
    }

    // MARK: Track popover (S14/S15)

    /// The popover's backdrop is an AppKit view, so it is drawn through a hosting view in a window
    /// (ImageRenderer leaves AppKit views out). Returns grey levels by pt position.
    private func renderHosted(_ view: some View, size: CGSize) throws -> (scale: CGFloat, level: (CGFloat, CGFloat) -> Int) {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height).environment(\.colorScheme, .dark))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.contentView = hosting
        defer { window.contentView = nil; window.close() }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let cached = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: cached)
        let rep = try XCTUnwrap(cached.retagging(with: .sRGB))
        let scale = CGFloat(rep.pixelsWide) / size.width
        return (scale, { x, y in
            Int(((rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB)?.greenComponent ?? 0) * 255).rounded())
        })
    }

    /// 496:2523 / 491:2243: sections sit 1 pt apart, the divider is the zero-height line at y 251
    /// (496:2652), and the section actions are 24 pt FG/A3 icons 20 pt apart ending at the 28 pt
    /// inset: "+" centred at x 360, the pencil at 316 (6059:13202).
    func testTrackPopoverDividerAndSectionActionsSitWhereFigmaDrawsThem() throws {
        let app = AppModel.mock(.playingEpisode)
        let (scale, level) = try renderHosted(MXRTrackPopoverView(tab: .subtitles).appModel(app), size: CGSize(width: 400, height: 524))
        let step = 1 / scale
        func centroid(_ points: [(CGFloat, Int)], background: Int) -> CGFloat? {
            let weights = points.map { ($0.0, CGFloat(abs($0.1 - background))) }.filter { $0.1 > 3 }
            let total = weights.reduce(0) { $0 + $1.1 }
            return total > 0 ? weights.reduce(0) { $0 + $1.0 * $1.1 } / total + step / 2 : nil
        }
        // The divider: the line between the Embedded rows and the External header, in a clear column.
        let background = level(200, 240)
        let column = stride(from: CGFloat(240), to: 262, by: step).map { ($0, level(200, $0)) }
        XCTAssertEqual(try XCTUnwrap(centroid(column, background: background)), 251, accuracy: 0.3, "the divider is centred on y 251")
        // The "+" and pencil glyphs on the External Tracks header (y 252…312, icons 270…294).
        let iconRows = stride(from: CGFloat(270), to: 294, by: step)
        let plus = iconRows.flatMap { y in stride(from: CGFloat(340), to: 380, by: step).map { ($0, level($0, y)) } }
        XCTAssertEqual(try XCTUnwrap(centroid(plus, background: background)), 360, accuracy: 1, "+ is centred at x 360")
        let pencil = iconRows.flatMap { y in stride(from: CGFloat(298), to: 334, by: step).map { ($0, level($0, y)) } }
        XCTAssertEqual(try XCTUnwrap(centroid(pencil, background: background)), 316, accuracy: 1.5, "the pencil is centred at x 316, 20 pt left of +")
        // FG/A3 like the "External Tracks" title beside them (FG/A2 would be clearly brighter).
        let title = iconRows.flatMap { y in stride(from: CGFloat(28), to: 130, by: step).map { level($0, y) } }.max() ?? 0
        XCTAssertEqual(Double(plus.map(\.1).max() ?? 0), Double(title), accuracy: 6, "the icons are FG/A3, not FG/A2")
    }

    // MARK: Queue (S22)

    /// D-07: the queue row's right-click menu carries the shared Add to Playlist submenu, and its
    /// "New Playlist…" starts the new-playlist sheet with the row's media.
    func testQueueRowMenuContainsTheSharedAddToPlaylistSubmenu() throws {
        let app = AppModel.mock(.pausedEpisode)
        let item = try XCTUnwrap(app.queue.items.dropFirst().first)
        let menu = PanelQueueInteraction.rowMenu(play: {}, addToPlaylist: PanelQueueInteraction.addToPlaylistMenu(app, for: item),
                                                 moveUp: {}, moveDown: {}, remove: {})
        XCTAssertEqual(menu.map(\.title), ["Play", "Add to Playlist", "Move Up", "Move Down", "Remove from Queue"])
        let submenu = try XCTUnwrap(menu.first { $0.title == "Add to Playlist" })
        XCTAssertTrue(submenu.isSubmenu)
        let shared = MXRPlayerMenus.playlistItems(app, newPlaylist: {}, media: { [] }, onError: { _, _ in })
        XCTAssertEqual(submenu.children?.map(\.title), shared.map(\.title), "the same rows as the library and mini player")
        let newPlaylist = try XCTUnwrap(submenu.children?.first { $0.title == "New Playlist…" })
        if case .action(let action) = newPlaylist.kind { action() } else { XCTFail("New Playlist… is an action") }
        XCTAssertEqual(app.interface.pendingPlaylistMedia.map(\.id), [item.media.id])
    }
}
