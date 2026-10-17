import Foundation
import XCTest
@testable import MXRCore

final class SubtitlePersistenceRegressionTests: XCTestCase {
    func testEveryExplicitTrackSurvivesCodingAndReplacesPreviousSelection() throws {
        let video = URL(fileURLWithPath: "/tmp/Show.mp4")
        let english = URL(fileURLWithPath: "/tmp/Show.en.srt")
        let french = URL(fileURLWithPath: "/tmp/Show.fr.srt")
        var rules = SubtitleFolderRules()
        rules.remember([(video, english), (video, french)], forFolder: nil)
        let reopened = try JSONDecoder().decode(SubtitleFolderRules.self, from: JSONEncoder().encode(rules))
        XCTAssertEqual(reopened.subtitles(for: video, fileExists: { _ in true }), [english, french])
        rules.remember([(video, french)], forFolder: nil)
        XCTAssertEqual(rules.subtitles(for: video, fileExists: { _ in true }), [french])
    }

    func testRemoteExplicitTrackSurvivesCodingWithoutLocalExistenceCheck() throws {
        let video = URL(fileURLWithPath: "/tmp/Show.mp4")
        let remote = URL(string: "https://example.com/Show.en.srt")!
        var rules = SubtitleFolderRules()
        rules.remember([(video, remote)], forFolder: nil)
        let reopened = try JSONDecoder().decode(SubtitleFolderRules.self, from: JSONEncoder().encode(rules))
        XCTAssertEqual(reopened.subtitles(for: video, fileExists: { _ in false }), [remote])
    }

    func testLegacySingleFileAssignmentStillLoadsAndMissingFilesAreSkipped() throws {
        let legacy = Data(#"{"files":{"/tmp/Show.mp4":"/tmp/Show.en.srt"},"folders":{}}"#.utf8)
        let rules = try JSONDecoder().decode(SubtitleFolderRules.self, from: legacy)
        let video = URL(fileURLWithPath: "/tmp/Show.mp4")
        XCTAssertEqual(rules.subtitles(for: video, fileExists: { _ in true }), [URL(fileURLWithPath: "/tmp/Show.en.srt")])
        XCTAssertTrue(rules.subtitles(for: video, fileExists: { _ in false }).isEmpty)
    }
    func testLibrarySelectionsRemainOwnedByLibraryAndLaterLocalSaveTakesOwnership() {
        let video = URL(fileURLWithPath: "/tmp/Show.mp4")
        let tracks = [URL(fileURLWithPath: "/tmp/Show.en.srt"), URL(fileURLWithPath: "/tmp/Show.fr.srt")]
        var rules = SubtitleFolderRules()
        rules.remember(tracks.map { (video, $0) }, forFolder: nil, inLibrary: [video])
        XCTAssertTrue(rules.subtitles(for: video, fileExists: { _ in true }).isEmpty)
        rules.remember(tracks.map { (video, $0) }, forFolder: nil)
        XCTAssertEqual(rules.subtitles(for: video, fileExists: { _ in true }), tracks)
    }

}
