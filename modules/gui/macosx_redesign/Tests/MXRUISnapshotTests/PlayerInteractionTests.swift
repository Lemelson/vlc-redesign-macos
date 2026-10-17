import AppKit
import MXRCore
import MXRDesign
import MXRMockBackend
@testable import MXRUI
import SwiftUI
import XCTest

final class PlayerInteractionTests: XCTestCase {
    func testCustomizationPaletteMatchesCanonicalPositionAndKeepsSmallWindowControlsClear() {
        let canonicalOffset = PlayerGeometry.customizationOffset(windowHeight: 1080, paletteHeight: 655, controlHeight: 108)
        XCTAssertEqual(1080 / 2 + canonicalOffset - 655 / 2, 189.5, accuracy: 0.01)
        for rows in 1...3 {
            let height: CGFloat = 540
            let controls = CGFloat(rows) * Theme.Metric.ControlBar.bar.height
            let palette = min(Theme.Metric.Customization.panel.height,
                              height - Theme.Metric.Window.topBar.height - controls - Theme.Metric.panelInset * 2)
            let center = height / 2 + PlayerGeometry.customizationOffset(windowHeight: height, paletteHeight: palette, controlHeight: controls)
            XCTAssertGreaterThanOrEqual(center - palette / 2, Theme.Metric.Window.topBar.height + Theme.Metric.panelInset)
            XCTAssertLessThanOrEqual(center + palette / 2, height - controls - Theme.Metric.panelInset)
        }
    }

    func testWaveformKeepsOrderedSamplesAndFixedPitchAroundTheThumbSlot() {
        let shape = WaveformShape(samples: WaveformSamples([0.25, 0.5, 0.75, 1]), headSlot: WaveformShape.slot(forHeadX: 10))
        let path = shape.path(in: CGRect(x: 0, y: 0, width: 25, height: 24))
        XCTAssertTrue(path.contains(CGPoint(x: 1, y: 12)))
        XCTAssertTrue(path.contains(CGPoint(x: 6, y: 12)))
        XCTAssertFalse(path.contains(CGPoint(x: 13.5, y: 12)), "The head slot must keep waveform bars clear of the thumb")
        XCTAssertTrue(path.contains(CGPoint(x: 18, y: 4)), "The third original sample must stay in sequence after the slot")
        XCTAssertTrue(path.contains(CGPoint(x: 23, y: 2)))

        XCTAssertTrue(shape.path(in: .zero).isEmpty)
        XCTAssertTrue(WaveformShape(samples: WaveformSamples([])).path(in: CGRect(x: 0, y: 0, width: 100, height: 24)).isEmpty)
    }

    func testNarrowWaveformRetainsTheSignalAtTheEndOfTheMedia() {
        var samples = Array(repeating: Float(0.05), count: 243) + [1]
        samples[127] = 0.75
        let path = WaveformShape(samples: WaveformSamples(samples), headSlot: WaveformShape.slot(forHeadX: 5))
            .path(in: CGRect(x: 0, y: 0, width: 42, height: 24))
        XCTAssertTrue(path.contains(CGPoint(x: 38, y: 2)), "The final peak must remain near the end of the narrow track")
        XCTAssertTrue(path.contains(CGPoint(x: 23, y: 4)), "A middle peak must also survive downsampling")
        XCTAssertFalse(path.contains(CGPoint(x: 1, y: 2)), "Early quiet samples must remain quiet")
        XCTAssertLessThanOrEqual(path.boundingRect.maxX, 42)
    }

    func testFullLibraryUsesMinimalHeaderOnlyForTheDefaultLayout() {
        let defaultItems = PlayerLayout.video.top
        XCTAssertEqual(PlayerGeometry.topItems(defaultItems, fullLibrary: true).map(\.control),
                       [.logo, .menu, .spacer, .title, .spacer, .fullscreen])
        XCTAssertEqual(PlayerGeometry.topItems(defaultItems, fullLibrary: false), defaultItems)

        let customizedItems = defaultItems + [LayoutItem(.pictureInPicture)]
        XCTAssertEqual(PlayerGeometry.topItems(customizedItems, fullLibrary: true), customizedItems)
        let reorderedItems = Array(defaultItems.reversed())
        XCTAssertEqual(PlayerGeometry.topItems(reorderedItems, fullLibrary: true), reorderedItems)
    }

    func testSeekUsesInsetTrackAndClampsOutsidePointer() {
        XCTAssertEqual(PlayerGeometry.seekPosition(x: -40, width: 100), 0)
        XCTAssertEqual(PlayerGeometry.seekPosition(x: 50, width: 100), 0.5, accuracy: 0.0001)
        XCTAssertEqual(PlayerGeometry.seekPosition(x: 140, width: 100), 1)
        XCTAssertEqual(PlayerGeometry.seekPosition(x: 5, width: 0), 0)
    }

    func testConeUsesFigmaNonlinearScaleAndRoundTripsEveryStep() {
        XCTAssertEqual(PlayerGeometry.volumeFillWidth(percent: 100), 63)
        XCTAssertEqual(PlayerGeometry.volumePercent(at: 63), 100)
        for step in Theme.Metric.Volume.fillWidthByStep {
            XCTAssertEqual(PlayerGeometry.volumePercent(at: step.value), Double(step.percent), accuracy: 0.001)
        }
        XCTAssertEqual(PlayerGeometry.volumeFillWidth(percent: 999), 88)
        XCTAssertEqual(PlayerGeometry.volumePercent(at: -5), 0)
    }

    func testVolumeConeUsesTheConfiguredCeilingAcrossItsWholeTravel() {
        XCTAssertEqual(PlayerGeometry.volumePercent(at: 88, maximumPercent: 100), 100)
        XCTAssertEqual(PlayerGeometry.volumePercent(at: 88, maximumPercent: 300), 300)
        XCTAssertEqual(PlayerGeometry.volumeFillWidth(percent: 100, maximumPercent: 100), 88)
        XCTAssertEqual(PlayerGeometry.volumeFillWidth(percent: 150, maximumPercent: 300), 63)
    }

    @MainActor
    func testEveryControlRowKeepsItsIndependentFigmaHeight() {
        for count in 1...3 {
            let app = AppModel.mock(.pausedEpisode)
            app.beginCustomizing()
            app.layouts.updateDraft { layout in
                layout.bottom = Array(repeating: [], count: count - 1) + [layout.bottom[0]]
            }
            let host = NSHostingView(rootView: MXRControlBar().appModel(app).frame(width: 1920))
            // In Customize a one-row bar also shows the empty new-row band above it (2107:5604, D051).
            XCTAssertEqual(host.fittingSize.height, CGFloat(max(count, 2)) * Theme.Metric.ControlBar.bar.height, accuracy: 0.01)
        }
    }

    @MainActor
    func testPresentationPreferencesRefreshFromSettingsAndClampFullscreenOpacity() {
        let mock = MockBackend(scenario: .playingEpisode)
        let preferences = MXRPlayerPreferences(app: mock.makeAppModel())
        XCTAssertTrue(preferences.showsSeekThumbnails)
        XCTAssertTrue(preferences.showsCoverArtwork)
        XCTAssertEqual(preferences.fullscreenControlsOpacity, 1)
        XCTAssertEqual(preferences.fullscreenHoverEdge, 64)
        mock.settings.setValue(.bool(false), for: "macosx-redesign-seek-thumbnails", apply: .nextMedia)
        mock.settings.setValue(.bool(false), for: "macosx-redesign-show-cover", apply: .nextMedia)
        mock.settings.setValue(.float(-20), for: "macosx-redesign-fs-controls-opacity", apply: .nextMedia)
        mock.settings.setValue(.string("high"), for: "macosx-redesign-fs-sensitivity", apply: .nextMedia)
        XCTAssertFalse(preferences.showsSeekThumbnails)
        XCTAssertFalse(preferences.showsCoverArtwork)
        XCTAssertEqual(preferences.fullscreenControlsOpacity, 0.1)
        XCTAssertEqual(preferences.fullscreenHoverEdge, 120)
        mock.settings.setValue(.float(.nan), for: "macosx-redesign-fs-controls-opacity", apply: .nextMedia)
        XCTAssertEqual(preferences.fullscreenControlsOpacity, 1)
    }

    func testCompactBarKeepsConfiguredPrimaryControlsAndLeavesOthersForOverflow() {
        let controls: [PlayerControl] = [.previous, .playPause, .next, .currentTime, .seekBar, .duration,
                                        .volume, .audioTracks, .subtitleTracks, .playbackSettings, .queue]
        let items = controls.map { LayoutItem($0) }
        XCTAssertEqual(PlayerGeometry.compactItems(items).map(\.control), [.playPause, .seekBar, .volume, .queue])
        XCTAssertEqual(PlayerGeometry.compactItems(items.filter { $0.control != .volume }).map(\.control),
                       [.playPause, .seekBar, .queue])
    }

    func testTypedSeekClampsToMediaAndInterpretsRemaining() {
        XCTAssertEqual(PlayerGeometry.typedTime("00:02:10", length: 600, remaining: false), 130)
        XCTAssertEqual(PlayerGeometry.typedTime("-00:02:10", length: 600, remaining: true), 470)
        XCTAssertEqual(PlayerGeometry.typedTime("00:45:00", length: 600, remaining: false), 600)
        XCTAssertNil(PlayerGeometry.typedTime("not a time", length: 600, remaining: false))
    }
}
