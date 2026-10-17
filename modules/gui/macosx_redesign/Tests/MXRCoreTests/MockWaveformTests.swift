import XCTest
@testable import MXRCore
@testable import MXRMockBackend

@MainActor
final class MockWaveformTests: XCTestCase {
    func testCanonicalSongUsesFigmaBarSamples() async throws {
        let mock = MockBackend(scenario: .music)
        let song = try XCTUnwrap(mock.library.mediaItem(id: MockDatabase.untangleID))
        let requested = await mock.thumbnails.waveform(for: song, bins: 244)
        let values = try XCTUnwrap(requested)
        XCTAssertEqual(values.count, 244)
        XCTAssertEqual(Array(values.prefix(10)), [0.083333, 0.166667, 0.25, 0.166667, 0.25, 0.083333, 0.166667, 0.25, 0.25, 0.083333])
        XCTAssertEqual(Array(values.suffix(4)), [0.583333, 0.583333, 0.25, 0.583333])
        XCTAssertTrue(values.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    func testCanonicalFixtureResamplesAndOtherMediaStayDeterministic() async throws {
        let mock = MockBackend(scenario: .music)
        let song = try XCTUnwrap(mock.library.mediaItem(id: MockDatabase.untangleID))
        let requestedSource = await mock.thumbnails.waveform(for: song, bins: 244)
        let requestedResampled = await mock.thumbnails.waveform(for: song, bins: 487)
        let source = try XCTUnwrap(requestedSource)
        let resampled = try XCTUnwrap(requestedResampled)
        XCTAssertEqual(resampled.count, 487)
        XCTAssertEqual(resampled.first, source.first)
        XCTAssertEqual(resampled.last, source.last)
        XCTAssertEqual(resampled[1], (source[0] + source[1]) / 2, accuracy: 0.000001)
        let single = await mock.thumbnails.waveform(for: song, bins: 1)
        let empty = await mock.thumbnails.waveform(for: song, bins: 0)
        XCTAssertEqual(single, [source[0]])
        XCTAssertEqual(empty, [])

        let other = try XCTUnwrap(mock.library.mediaItem(id: MockDatabase.moonlightID))
        let first = await mock.thumbnails.waveform(for: other, bins: 244)
        let second = await mock.thumbnails.waveform(for: other, bins: 244)
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, source)
    }
}
