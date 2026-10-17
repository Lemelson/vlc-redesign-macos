import MXRCore
import MXRGalleryCatalog
@testable import MXRUI
import XCTest

final class PanelsTests: XCTestCase {
    func testCueClipIncludesDelayAndClampsToWindow() {
        let cue = SubtitleCue(start: 8, end: 14, text: "Crossing")
        XCTAssertEqual(SubtitleTimelineGeometry.fractions(cue: cue, delay: 2, start: 10, duration: 10), 0...0.6)
        XCTAssertNil(SubtitleTimelineGeometry.fractions(cue: cue, delay: 2, start: 20, duration: 10))
    }

    func testDragPayloadKeepsQueueIdentitySeparateFromURLs() {
        XCTAssertEqual(PanelDropPayload(text: "mxr-queue:3"), .queueItem(3))
        XCTAssertEqual(PanelDropPayload(text: "file:///tmp/episode.mp4"), .url(URL(fileURLWithPath: "/tmp/episode.mp4")))
        XCTAssertNil(PanelDropPayload(text: "garbage"))
        XCTAssertNil(PanelDropPayload(text: "mxr-queue:"))
    }

    func testNumericFieldsRejectNonFiniteValuesBeforeCallingMediaTime() {
        XCTAssertNil(panelNumber("nan s"))
        XCTAssertNil(panelNumber("inf"))
        XCTAssertEqual(panelNumber("-2.500 s"), -2.5)
    }

    func testFilterInspectorKeepsEngineTypesRangesAndUnknownValues() {
        let integer = SettingOption(name: "puzzle-rows", type: .integer, defaultValue: .integer(4), range: 2...42)
        XCTAssertEqual(VideoFilterOption.value(from: "100", option: integer), .integer(42))
        XCTAssertNil(VideoFilterOption.value(from: "2.5", option: integer))
        XCTAssertNil(VideoFilterOption.value(from: "inf", option: integer))
        let float = SettingOption(name: "rotate-angle", type: .float, defaultValue: .float(30), range: 0...360)
        XCTAssertEqual(VideoFilterOption.value(from: "-1", option: float), .float(0))
        let text = SettingOption(name: "marq-marquee", type: .string, defaultValue: .string("VLC"))
        XCTAssertEqual(VideoFilterOption.value(from: "An unknown title", option: text), .string("An unknown title"))
        XCTAssertEqual(VideoFilterGroup.group(for: integer), .geometry)
        XCTAssertEqual(VideoFilterGroup.group(for: text), .overlay)
        XCTAssertNil(VideoFilterGroup.group(for: SettingOption(name: "network-caching", type: .integer, defaultValue: .integer(1000))))
    }

    @MainActor
    func testPanelGalleryCoversEveryDesignedCrop() {
        GalleryCatalog.bootstrap()
        let expected = ["S14.Tracks/subtitles", "S15.Tracks/audio", "S16.Tracks/video", "S17.Sidebar/playback", "S18.Sidebar/video", "S19.Sidebar/audio", "S20.Sidebar/subtitles", "S21.Timeline/default", "S22.Queue/default", "S23.Queue/bookmarks", "S24.Queue/chapters"]
        for id in expected { XCTAssertNotNil(GalleryCatalog.entry(id: id), id) }
    }
}
