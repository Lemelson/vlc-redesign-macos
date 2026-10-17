import XCTest
@testable import MXRCore
@testable import MXRMockBackend
@MainActor
final class SettingsUnitsAuditRegressionTests: XCTestCase {
    func testSubtitleDelaySecondsRoundTripInEngineDeciseconds() throws {
        let mock = MockBackend(scenario: .idle)
        let model = SettingsModel(backend: mock.settings)
        let row = try XCTUnwrap(model.catalog.categories.flatMap { $0.sections.flatMap(\.rows) }.first { $0.option == "sub-delay" })
        mock.settings.setValue(.integer(5), for: "sub-delay", apply: .nextMedia)
        XCTAssertEqual(model.double(row), 0.5)
        model.setValue(.float(-4.5), for: row)
        XCTAssertEqual(mock.settings.value(for: "sub-delay")?.doubleValue, -45)
        XCTAssertEqual(row.step, 0.1)
        model.saveNow()
    }
    func testDefaultTrackRowsShowOneBasedTracksAndAutoForMinusOne() throws {
        let mock = MockBackend(scenario: .idle)
        let model = SettingsModel(backend: mock.settings)
        for option in ["audio-track", "sub-track"] {
            let row = try XCTUnwrap(model.catalog.allRows.first { $0.option == option })
            mock.settings.setValue(.integer(-1), for: option, apply: .nextMedia)
            XCTAssertNil(model.value(for: row), "VLC's -1 reads as automatic, not as a number")
            XCTAssertEqual(model.string(row), "")
            XCTAssertEqual(row.placeholder, "Auto")
            mock.settings.setValue(.integer(0), for: option, apply: .nextMedia)
            XCTAssertEqual(model.string(row), "1", "VLC's 0-based stream index 0 is the first track")
            model.setValue(.integer(3), for: row)
            XCTAssertEqual(mock.settings.value(for: option)?.intValue, 2, "Track 3 is stream index 2")
            model.setAutomatic(for: row)
            XCTAssertEqual(mock.settings.value(for: option)?.intValue, -1)
            XCTAssertEqual(row.min, 1)
        }
        model.saveNow()
    }
    func testUnsupportedPluginRescanIsAbsent() {
        XCTAssertFalse(SettingsCatalog.bundled.categories.flatMap { $0.sections.flatMap(\.rows) }.contains { $0.action == "rescan-plugins" })
    }
}
