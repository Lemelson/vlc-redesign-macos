import Foundation
import MXRCore
import MXRGalleryCatalog
@testable import MXRUI
import XCTest

/// Side panel content (G-panels): subtitle timeline window, Playback tab persistence, gallery coverage.
final class SidePanelContentTests: XCTestCase {
    func testTimelineWindowFollowsWithThePlayheadCentredAndClamped() {
        let length: MediaTime = .seconds(1_500)
        // 3744:12370/12376: playhead at 02:15 shows 01:50*–02:40*.
        XCTAssertEqual(SubtitleTimelineWindow.followStart(time: .seconds(135), length: length), .seconds(110))
        XCTAssertEqual(SubtitleTimelineWindow.followStart(time: .seconds(10), length: length), .zero)
        XCTAssertEqual(SubtitleTimelineWindow.followStart(time: .seconds(1_495), length: length), .seconds(1_450))
        // Unknown lengths (streams) never clamp the end.
        XCTAssertEqual(SubtitleTimelineWindow.followStart(time: .seconds(400), length: .zero), .seconds(375))
        // A paged window wins until it is cleared.
        XCTAssertEqual(SubtitleTimelineWindow.start(manual: .seconds(300), time: .seconds(135), length: length), .seconds(300))
        XCTAssertEqual(SubtitleTimelineWindow.latestStart(length: .seconds(20)), .zero)
    }

    @MainActor
    func testPlaybackTabTogglesSurviveRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = InterfaceModel(persistence: .directory(directory))
        XCTAssertFalse(first.showWaveform, "D028: the waveform is off by default")
        first.showSubtitleTimeline = true
        first.showMetadata = true
        let relaunched = InterfaceModel(persistence: .directory(directory))
        XCTAssertTrue(relaunched.showSubtitleTimeline)
        XCTAssertTrue(relaunched.showMetadata)
        XCTAssertFalse(relaunched.showWaveform)

        let preview = InterfaceModel()
        preview.showMetadata = true
        XCTAssertFalse(InterfaceModel().showMetadata, "In-memory models never share state")
    }

    @MainActor
    func testGalleryCoversPresetListAndMetadataOverlay() {
        GalleryCatalog.bootstrap()
        for id in ["S17.Sidebar/playback", "S17.Metadata/overlay", "S20.Presets/open", "S21.Timeline/default"] {
            XCTAssertNotNil(GalleryCatalog.entry(id: id), id)
        }
    }
}
