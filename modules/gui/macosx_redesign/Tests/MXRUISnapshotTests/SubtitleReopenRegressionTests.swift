import Foundation
import MXRCore
import MXRMockBackend
@testable import MXRUI
import XCTest

final class SubtitleReopenRegressionTests: XCTestCase {
    @MainActor
    func testRememberedImportStartsOnlyWhenInputHasFinishedOpening() {
        let media = MediaItem(url: URL(fileURLWithPath: "/tmp/Show.mp4"))
        for state in [PlayerState.stopped, .started, .stopping] {
            XCTAssertNil(SubtitleFolderRulesStore.readyMediaID(for: media, state: state))
        }
        for state in [PlayerState.playing, .paused] {
            XCTAssertEqual(SubtitleFolderRulesStore.readyMediaID(for: media, state: state), media.id)
            XCTAssertNil(SubtitleFolderRulesStore.readyMediaID(for: nil, state: state))
        }
    }

    @MainActor
    func testExplicitSameFolderPrefixSelectionLoadsWithoutAssumingAutodetection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let video = directory.appendingPathComponent("Show.mp4")
        let subtitle = directory.appendingPathComponent("Show.en.srt")
        try Data().write(to: subtitle)
        var rules = SubtitleFolderRules()
        rules.remember([(video, subtitle)], forFolder: nil)
        let app = AppModel.mock(.idle)
        let store = SubtitleFolderRulesStore(rules: rules)
        await store.apply(to: MediaItem(url: video), tracks: app.tracks)
        XCTAssertEqual(app.tracks.externalTracks(of: .subtitle).compactMap(\.sourceURL), [subtitle])
        await store.apply(to: MediaItem(url: video), tracks: app.tracks)
        XCTAssertEqual(app.tracks.externalTracks(of: .subtitle).compactMap(\.sourceURL), [subtitle], "Actual loaded tracks suppress duplicate attachment")
    }

    @MainActor
    func testReopenDoesNotAttachAfterMediaIdentityChanges() async {
        let video = URL(fileURLWithPath: "/tmp/Show.mp4")
        let remote = URL(string: "https://example.com/Show.srt")!
        var rules = SubtitleFolderRules()
        rules.remember([(video, remote)], forFolder: nil)
        let app = AppModel.mock(.idle)
        await SubtitleFolderRulesStore(rules: rules).apply(to: MediaItem(url: video), tracks: app.tracks, isCurrent: { false })
        XCTAssertTrue(app.tracks.externalTracks(of: .subtitle).isEmpty)
    }

    @MainActor
    func testSingleFileSaveRemembersAllSelectedTracksWithoutPreferences() async throws {
        let video = URL(fileURLWithPath: "/tmp/Show.mp4")
        let tracks = [URL(fileURLWithPath: "/tmp/Show.en.srt"), URL(fileURLWithPath: "/tmp/Show.fr.srt")]
        let draft = SubtitleImportDraft(scope: .file, source: .computer, media: [MediaItem(url: video)], subtitles: tracks)
        let store = SubtitleFolderRulesStore(rules: SubtitleFolderRules())
        try await draft.save(to: AppModel.mock(.idle), rules: store)
        XCTAssertEqual(store.rules.subtitles(for: video, fileExists: { _ in true }), tracks)
    }
    @MainActor
    func testCancelledReopenNeverAttachesRememberedTrack() async {
        let video = URL(fileURLWithPath: "/tmp/Show.mp4")
        var rules = SubtitleFolderRules()
        rules.remember([(video, URL(string: "https://example.com/Show.srt")!)], forFolder: nil)
        let app = AppModel.mock(.idle)
        let store = SubtitleFolderRulesStore(rules: rules)
        let task = Task { await store.apply(to: MediaItem(url: video), tracks: app.tracks) }
        task.cancel()
        await task.value
        XCTAssertTrue(app.tracks.externalTracks(of: .subtitle).isEmpty)
    }

}
