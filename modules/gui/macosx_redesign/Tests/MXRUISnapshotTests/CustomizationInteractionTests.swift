import Foundation
import MXRCore
import MXRMockBackend
@testable import MXRUI
import XCTest

@MainActor
final class CustomizationInteractionTests: XCTestCase {
    func testDropAddsTileToDraftAndCancelRestoresSavedLayout() {
        let app = AppModel.mock(.pausedEpisode)
        let original = app.playerLayout
        app.beginCustomizing()
        XCTAssertTrue(MXRLayoutDragPayload.tile(.favorite).place(in: .bottom(0), at: 4, app: app))
        XCTAssertTrue(app.playerLayout.contains(.favorite))
        XCTAssertFalse(app.playerLayout.availableTiles.contains(.favorite))
        XCTAssertTrue(app.layouts.hasChanges)
        app.endCustomizing(save: false)
        XCTAssertEqual(app.playerLayout, original)
    }

    func testMoveBetweenBarsAndNewRowSaveToSelectedProfile() {
        let app = AppModel.mock(.pausedEpisode)
        let originalProfile = app.profiles.current
        app.beginCustomizing()
        let menu = app.playerLayout.top.first { $0.control == .menu }!
        XCTAssertTrue(MXRLayoutDragPayload.placed(menu).place(in: .bottom(1), at: 0, app: app))
        XCTAssertEqual(app.playerLayout.bottom.count, 2)
        XCTAssertEqual(app.playerLayout.bottom[1].first?.control, .menu)
        XCTAssertFalse(app.playerLayout.top.contains { $0.control == .menu })
        app.endCustomizing(save: true)
        let saved = app.playerLayout
        let other = app.profiles.create(name: "Test")
        app.profiles.select(other)
        XCTAssertEqual(app.playerLayout, .video)
        app.profiles.select(originalProfile)
        XCTAssertEqual(app.playerLayout, saved)
    }

    func testSameBarDropUsesInsertionIndexBeforeTarget() {
        let app = AppModel.mock(.pausedEpisode)
        app.beginCustomizing()
        let items = app.playerLayout.top
        let first = items[0]
        XCTAssertTrue(MXRLayoutDragPayload.placed(first).place(in: .top, at: 3, app: app))
        XCTAssertEqual(Array(app.playerLayout.top.prefix(3)).map(\.id), [items[1].id, items[2].id, first.id])
        XCTAssertTrue(MXRLayoutDragPayload.placed(first).place(in: .top, at: 0, app: app))
        XCTAssertEqual(app.playerLayout.top, items)
    }

    func testRemovingPlacedTileMakesItAvailableAgainAndRejectsDuplicates() {
        let app = AppModel.mock(.pausedEpisode)
        app.beginCustomizing()
        let payload = MXRLayoutDragPayload.tile(.favorite)
        XCTAssertTrue(payload.place(in: .top, at: 1, app: app))
        XCTAssertFalse(payload.place(in: .top, at: 1, app: app))
        let item = app.playerLayout.top.first { $0.control == .favorite }!
        XCTAssertTrue(MXRLayoutDragPayload.placed(item).remove(from: app))
        XCTAssertTrue(app.playerLayout.availableTiles.contains(.favorite))
        XCTAssertFalse(payload.remove(from: app))
    }

    func testDropWithoutSessionOrIntoInvalidRowIsRejected() {
        let app = AppModel.mock(.pausedEpisode)
        let payload = MXRLayoutDragPayload.tile(.spacer)
        XCTAssertFalse(payload.place(in: .top, at: 0, app: app))
        app.beginCustomizing()
        XCTAssertFalse(payload.place(in: .bottom(-2), at: 0, app: app)) // -1 is the new-first-row band
        XCTAssertFalse(payload.place(in: .bottom(3), at: 0, app: app))
        XCTAssertFalse(app.layouts.hasChanges)
    }

    func testProfileNameValidationAndRenamePreserveIdentity() {
        let store = ProfileStore(location: .inMemory)
        XCTAssertNil(MXRProfileEditing.save(name: "  ", replacing: nil, in: store))
        let created = MXRProfileEditing.save(name: "  Documentaries  ", replacing: nil, in: store)!
        XCTAssertEqual(created.name, "Documentaries")
        XCTAssertEqual(store.currentID, created.id)
        let renamed = MXRProfileEditing.save(name: "Films", replacing: created, in: store)!
        XCTAssertEqual(renamed.id, created.id)
        XCTAssertEqual(store.current.name, "Films")
    }

    func testProfileActionsPreserveActiveLayoutDraftUntilSaveOrCancel() {
        let app = AppModel.mock(.pausedEpisode)
        let current = app.profiles.current
        let other = app.profiles.create(name: "Alternate")
        app.beginCustomizing()
        XCTAssertTrue(MXRLayoutDragPayload.tile(.favorite).place(in: .bottom(0), at: 0, app: app))
        let draft = app.playerLayout
        let names = app.profiles.profiles.map(\.name)

        XCTAssertFalse(MXRProfileEditing.select(other, in: app))
        XCTAssertNil(MXRProfileEditing.save(name: "New profile", replacing: nil, in: app))
        XCTAssertNil(MXRProfileEditing.save(name: "Renamed", replacing: current, in: app))
        XCTAssertFalse(MXRProfileEditing.delete(current, in: app))
        XCTAssertEqual(app.profiles.currentID, current.id)
        XCTAssertEqual(app.profiles.profiles.map(\.name), names)
        XCTAssertEqual(app.playerLayout, draft)
        XCTAssertTrue(app.layouts.hasChanges)

        app.endCustomizing(save: true)
        XCTAssertTrue(MXRProfileEditing.select(other, in: app))
        XCTAssertTrue(MXRProfileEditing.select(current, in: app))
        XCTAssertEqual(app.playerLayout, draft)

        app.beginCustomizing()
        app.endCustomizing(save: false)
        XCTAssertNotNil(MXRProfileEditing.save(name: "New profile", replacing: nil, in: app))
        XCTAssertTrue(MXRProfileEditing.delete(current, in: app))
    }

    func testOnboardingKeysReadRemappedBindingsAndCompletionPersists() {
        let app = AppModel.mock(.emptyLibrary)
        app.shortcuts.setBinding(KeyBinding(key: "p", modifiers: .command), for: "play-pause")
        app.shortcuts.saveDraft()
        XCTAssertEqual(MXROnboardingShortcut.rows[0].bindings(in: app.shortcuts).first?.displayString, "⌘P")
        XCTAssertTrue(app.needsOnboarding)
        app.interface.present(.onboarding)
        app.completeOnboarding()
        XCTAssertFalse(app.needsOnboarding)
        XCTAssertNil(app.interface.sheet)
    }

    func testRemovedDefaultControlCanBeRestoredFromPalette() {
        let app = AppModel.mock(.pausedEpisode)
        app.beginCustomizing()
        let menu = app.playerLayout.top.first { $0.control == .menu }!
        XCTAssertTrue(MXRLayoutDragPayload.placed(menu).remove(from: app))
        XCTAssertTrue(MXRCustomizationPalette.controls(for: app.playerLayout, kind: .video).contains(.menu))
        XCTAssertTrue(MXRLayoutDragPayload.tile(.menu).place(in: .bottom(0), at: 0, app: app))
        XCTAssertEqual(app.playerLayout.bottom[0].first?.control, .menu)
    }

    /// LIBSET-09: the folder is in the library as soon as Next accepts it, so closing onboarding
    /// on a later step (Esc / ⌘W) cannot lose it; Back then Next does not add it twice.
    func testOnboardingNextAddsTheFolderImmediatelyAndOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var added: [URL] = []
        let first = try MXROnboardingFolder.accept(directory.path, alreadyAdded: nil) { added.append($0) }
        XCTAssertEqual(added.map(\.path), [directory.path])
        let again = try MXROnboardingFolder.accept(directory.path, alreadyAdded: first) { added.append($0) }
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(again, first)
        XCTAssertNil(try MXROnboardingFolder.accept("", alreadyAdded: nil) { added.append($0) })
        XCTAssertEqual(added.count, 1)
    }

    func testOnboardingFolderAllowsSkippingAndRejectsFiles() throws {
        XCTAssertNil(try MXROnboardingFolder.url(for: "  "))
        XCTAssertThrowsError(try MXROnboardingFolder.url(for: "relative/folder"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("movie.mp4")
        try Data().write(to: file)
        XCTAssertEqual(try MXROnboardingFolder.url(for: directory.path)?.path, directory.path)
        XCTAssertThrowsError(try MXROnboardingFolder.url(for: file.path))
    }
}
