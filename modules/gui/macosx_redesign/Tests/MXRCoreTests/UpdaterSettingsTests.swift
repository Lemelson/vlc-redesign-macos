import XCTest
@testable import MXRCore
@testable import MXRMockBackend

/// D059: the update rows of Settings ▸ General read and write Sparkle, never the engine.
@MainActor
final class UpdaterSettingsTests: XCTestCase {
    private func row(_ id: String, in app: AppModel) throws -> SettingsRow {
        try XCTUnwrap(app.settings.catalog.allRows.first { $0.id == id })
    }

    func testUpdateRowsWriteSparkleAndNeverTheEngineOptions() throws {
        let mock = MockBackend(scenario: .idle)
        let app = AppModel(backends: mock.backends, persistence: .inMemory, clockTicks: false)
        let checks = try row(UpdaterSettings.automaticChecks, in: app)
        XCTAssertEqual(checks.label, "Check for updates automatically")
        XCTAssertTrue(checks.info?.contains("github.com") ?? false, "the row says which server it contacts")
        XCTAssertFalse(app.settings.bool(checks), "Figma 3046:9906 and Sparkle's unanswered question read off")
        app.settings.setValue(.bool(true), for: checks)
        XCTAssertTrue(mock.updater.automaticallyChecks)
        for name in UpdaterSettings.names {
            XCTAssertNil(mock.settings.option(named: name), "\(name) must not become a VLC option")
        }
    }

    /// 1.0.1: Sparkle 2.8.1 with profiling off sends no feed parameters; its User-Agent is
    /// "VLC Redesign/<version> Sparkle/2.8.1". The ⓘ must not promise or claim more (no macOS version).
    func testUpdateCheckInfoSaysOnlyTheAppAndItsVersionAreSent() throws {
        let app = AppModel(backends: MockBackend(scenario: .idle).backends, persistence: .inMemory, clockTicks: false)
        let info = try XCTUnwrap(try row(UpdaterSettings.automaticChecks, in: app).info)
        XCTAssertTrue(info.contains("only the app and its version"), info)
        XCTAssertFalse(info.contains("macOS version"), info)
    }

    func testInstallAutomaticallyNeedsAutomaticChecks() throws {
        let mock = MockBackend(scenario: .idle)
        let app = AppModel(backends: mock.backends, persistence: .inMemory, clockTicks: false)
        let installs = try row(UpdaterSettings.automaticInstalls, in: app)
        XCTAssertFalse(app.settings.isEnabled(installs))
        // Sparkle's own question or update window changes the value: the rows follow.
        mock.updater.automaticallyChecks = true
        XCTAssertTrue(app.settings.isEnabled(installs))
        app.settings.setValue(.bool(true), for: installs)
        XCTAssertTrue(mock.updater.automaticallyInstalls)
    }

    func testCheckNowRunsOneCheckAndWaitsWhileOneRuns() throws {
        let mock = MockBackend(scenario: .idle)
        let app = AppModel(backends: mock.backends, persistence: .inMemory, clockTicks: false)
        let checkNow = try row("check-for-updates", in: app)
        XCTAssertEqual(checkNow.buttonTitle, "Check Now")
        XCTAssertTrue(app.settings.isEnabled(checkNow))
        app.settings.perform(checkNow)
        XCTAssertEqual(mock.updater.checkCount, 1)
        mock.updater.canCheckForUpdates = false
        XCTAssertFalse(app.settings.isEnabled(checkNow))
        app.checkForUpdates()
        XCTAssertEqual(mock.updater.checkCount, 1, "no second check while Sparkle is busy")
    }

    func testResetKeepsTheUpdateAnswer() throws {
        let mock = MockBackend(scenario: .idle)
        let app = AppModel(backends: mock.backends, persistence: .inMemory, clockTicks: false)
        mock.updater.automaticallyChecks = true
        app.settings.resetCategory("general")
        let reset = try row("reset-all-settings", in: app)
        app.settings.perform(reset)
        XCTAssertTrue(mock.updater.automaticallyChecks)
    }

    func testUpdateRowsAndCommandAreAbsentWithoutSparkle() throws {
        let mock = MockBackend(scenario: .idle)
        let full = mock.backends
        let backends = Backends(player: full.player, clock: full.clock, queue: full.queue, library: full.library,
                                mediaSources: full.mediaSources, settings: full.settings, shortcuts: full.shortcuts,
                                dialogs: full.dialogs, extensions: full.extensions, thumbnails: full.thumbnails,
                                osd: full.osd, capabilities: full.capabilities)
        let app = AppModel(backends: backends, persistence: .inMemory, clockTicks: false)
        XCTAssertNil(app.updater)
        for name in UpdaterSettings.names { XCTAssertNil(app.settings.backend.option(named: name)) }
        app.checkForUpdates()
        XCTAssertEqual(mock.updater.checkCount, 0)
    }
}
