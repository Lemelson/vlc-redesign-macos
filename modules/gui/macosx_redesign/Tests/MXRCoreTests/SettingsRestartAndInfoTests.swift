import XCTest
@testable import MXRCore
@testable import MXRMockBackend

/// C-15 restart note and the catalog-owned ⓘ (F-settings, 2026-10-17).
@MainActor
final class SettingsRestartAndInfoTests: XCTestCase {
    /// The note compares with the value VLC started with: changing "Load add-ons on startup" and
    /// changing it back clears the note, and so does a category reset.
    func testRestartNoteFollowsTheValueAtLaunch() throws {
        let app = AppModel.mock(.idle)
        let startup = try XCTUnwrap(app.settings.catalog.allRows.first { $0.option == "lua" })
        XCTAssertEqual(startup.apply, .restart)
        let launch = try XCTUnwrap(app.settings.value(for: startup)?.boolValue)
        XCTAssertFalse(app.settings.needsRestart(startup))

        app.settings.setValue(.bool(!launch), for: startup)
        XCTAssertTrue(app.settings.needsRestart(startup))
        XCTAssertEqual(app.settings.restartPendingOptions, ["lua"])

        app.settings.setValue(.bool(launch), for: startup)
        XCTAssertFalse(app.settings.needsRestart(startup), "back to the running value: nothing to restart for")
        XCTAssertTrue(app.settings.restartPendingOptions.isEmpty)

        app.settings.setValue(.bool(!launch), for: startup)
        XCTAssertTrue(app.settings.needsRestart(startup))
        app.settings.resetCategory("extensions")
        XCTAssertEqual(app.settings.value(for: startup)?.boolValue, launch, "the mock starts at the default")
        XCTAssertFalse(app.settings.needsRestart(startup), "Reset restores the running value")
    }

    /// The new Additional command line options row (3046:9524) applies at the next start.
    func testAdditionalCommandLineOptionsRowAppliesAfterRestart() throws {
        let app = AppModel.mock(.idle)
        let general = try XCTUnwrap(app.settings.catalog.category("general"))
        let advanced = general.advancedSections.flatMap(\.rows)
        let row = try XCTUnwrap(advanced.first)
        XCTAssertEqual(row.option, "macosx-redesign-extra-args", "first advanced row, as in Figma")
        XCTAssertEqual(row.label, "Additional command line options")
        XCTAssertEqual(row.apply, .restart)
        app.settings.setValue(.string("--no-osd"), for: row)
        XCTAssertTrue(app.settings.needsRestart(row))
        app.settings.setValue(.string(""), for: row)
        XCTAssertFalse(app.settings.needsRestart(row))
    }

    /// A row without an info text has no ⓘ, even when the engine has a long text for its option
    /// (Figma has none on "Remember window size and position" although VLC describes the option).
    func testInfoComesFromTheCatalogOnly() throws {
        let described = SettingsRow(option: "fullscreen", control: .toggle, label: "Start videos in fullscreen",
                                    info: "VLC's long text", mock: .bool(false))
        let catalog = SettingsCatalog(categories: [
            SettingsCategory(id: "video", group: .media, sidebar: "Video", title: "Video Defaults", icon: "video",
                             sections: [SettingsSection(title: "Output", rows: [described])]),
        ])
        let backend = MockBackend(scenario: .idle, settingsCatalog: catalog)
        let app = AppModel(backends: backend.backends, persistence: .inMemory, settingsCatalog: catalog, clockTicks: false)
        XCTAssertEqual(backend.settings.option(named: "fullscreen")?.longText, "VLC's long text", "the engine describes the option")
        var plain = described
        plain.info = nil
        XCTAssertNil(app.settings.info(for: plain), "no catalog info: no ⓘ")
        XCTAssertEqual(app.settings.info(for: described), "VLC's long text")
    }

    /// Figma rows that differed in the 2026-10-16 parity review.
    func testFigmaRowDetails() throws {
        let rows = SettingsCatalog.bundled.allRows
        func row(_ option: String) throws -> SettingsRow { try XCTUnwrap(rows.first { $0.option == option }, option) }
        for option in ["fullscreen", "disable-screensaver", "video-wallpaper", "deinterlace-mode", "aspect-ratio",
                       "mix-mode", "norm-max-level", "audio-replay-gain-preamp"] {
            XCTAssertFalse(try row(option).info?.isEmpty ?? true, "\(option) has its Figma ⓘ")
        }
        for option in ["macosx-redesign-remember-window", "input-record-native", "sout-display", "sout-audio", "sout-video", "sout-spu", "drop-late-frames"] {
            XCTAssertEqual(try row(option).info, "", "\(option) has no ⓘ in Figma")
        }
        XCTAssertNil(try row("norm-max-level").enabledWhen, "Target level is drawn enabled (3073:15879)")
        XCTAssertNil(try row("macosx-redesign-volume-step").unit, "Volume step reads \"1\"")
        XCTAssertEqual(try row("macosx-redesign-max-volume").ticks, 9)
        let preset = try row("sout-x264-preset")
        XCTAssertEqual(preset.choices?.first { $0.value == .string("") }?.title, "Medium")
        let developer = try XCTUnwrap(SettingsCatalog.bundled.category("performance")?.advancedSections.first { $0.title == "Developer" })
        XCTAssertTrue(developer.rows.allSatisfy { $0.visibleWhen == nil }, "shown under Advanced Options as in 6571:16321")
        XCTAssertEqual(try row("clock-synchro").label, "Clock synchronisation")
    }
}
