import Foundation
@testable import MXRCore
import XCTest

final class SubtitleCooperativeCancellationTests: XCTestCase {
    func testCancelledMatcherDoesNotProduceAssignments() async {
        let matches = await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return SubtitleMatcher.match(videos: ["Show.S01E02.mp4"], subtitles: ["Show.S01E02.srt"])
        }.value
        XCTAssertTrue(matches.isEmpty)
    }
}
