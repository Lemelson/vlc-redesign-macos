import AppKit
import MXRCore
import MXRGalleryCatalog
import MXRMockBackend
@testable import MXRUI
import XCTest

final class SettingsUITests: XCTestCase {
    func testShortcutEditorsFitNestedSheetsAndPreserveCanonicalColumns() {
        let canonical = SettingsShortcutLayout(width: 1048)
        XCTAssertFalse(canonical.stacksFields)
        XCTAssertEqual(canonical.leadingWidth, 379)
        XCTAssertEqual(canonical.fieldWidth, 270)
        XCTAssertEqual(canonical.leadingWidth + canonical.fieldWidth + canonical.rowGap, 738)
        for width: CGFloat in [320, 470, 832, 960, 1048] {
            let layout = SettingsShortcutLayout(width: width)
            let fieldsTrailingEdge = layout.stacksFields ? layout.fieldWidth : layout.leadingWidth + layout.fieldWidth * 2 + layout.rowGap
            XCTAssertEqual(fieldsTrailingEdge, layout.contentWidth, accuracy: 0.001, "Both edit buttons must remain inside a \(width)-point sheet")
            XCTAssertGreaterThanOrEqual(layout.fieldWidth, 200)
        }
        XCTAssertTrue(SettingsShortcutLayout(width: 470).stacksFields)
    }

    func testNumericEditingPreservesOptionTypeAndRejectsInvalidInput() {
        let row = SettingsRow(option: "duration", control: .number, label: "Duration", min: 0, max: 10)
        XCTAssertEqual(SettingsValueEditing.number("3.5", row: row, current: .float(2)), .float(3.5))
        XCTAssertEqual(SettingsValueEditing.number("3", row: row, current: .integer(2)), .integer(3))
        XCTAssertNil(SettingsValueEditing.number("3.5", row: row, current: .integer(2)))
        XCTAssertNil(SettingsValueEditing.number("11", row: row, current: .integer(2)))
        XCTAssertNil(SettingsValueEditing.number("nan", row: row, current: .float(2)))
    }

    func testColorEditingAcceptsSixHexDigitsAndRejectsPartialColors() {
        XCTAssertEqual(SettingsValueEditing.color("#a0B1c2"), .integer(0xA0B1C2))
        XCTAssertNil(SettingsValueEditing.color("#abc"))
        XCTAssertNil(SettingsValueEditing.color("#a0B1cz"))
        XCTAssertNil(SettingsValueEditing.color("a0#b1c2"))
        XCTAssertNil(SettingsValueEditing.color("#-00001"))
        XCTAssertNil(SettingsValueEditing.color("#+00001"))
    }

    func testFractionalControlsUseSchemaTypeInsteadOfIntegerLookingInitialValue() {
        let row = SettingsRow(option: "rate", control: .number, label: "Speed", min: 0.25, max: 2)
        XCTAssertEqual(SettingsValueEditing.number("0.75", row: row, current: .integer(1), isFloat: true), .float(0.75))
        XCTAssertEqual(SettingsValueEditing.slider(0.75, current: .integer(1), step: 0.25), .float(0.75))
        XCTAssertEqual(SettingsValueEditing.slider(2, current: .integer(1), isFloat: true), .float(2))
        XCTAssertEqual(SettingsValueEditing.slider(2, current: .integer(1)), .integer(2))
    }

    func testUnsupportedRowsAreHiddenInsteadOfListed() {
        // D035: rows whose options the engine does not publish are hidden; nothing says "unavailable".
        for name in ["macosx-redesign-sub-size-mode", "macosx-redesign-sub-pixel-size", "macosx-redesign-sub-position",
                     "macosx-redesign-sub-ignore-styles"] {
            let row = SettingsCatalog.bundled.allRows.first { $0.option == name }!
            XCTAssertFalse(SettingsAvailability.isAvailable(row, optionAvailable: { _ in false }), name)
            XCTAssertTrue(SettingsAvailability.isAvailable(row, optionAvailable: { _ in true }), name)
        }
        let composite = SettingsRow(composite: [SettingsCompositeChoice(title: "Mode", values: ["first": .bool(true), "second": .bool(false)])],
                                    control: .dropdown, label: "Modes")
        XCTAssertFalse(SettingsAvailability.isAvailable(composite, optionAvailable: { $0 != "second" }))
        XCTAssertTrue(SettingsAvailability.isAvailable(composite, optionAvailable: { _ in true }))
        let action = SettingsRow(action: "open-config-folder", control: .button, label: "Open")
        XCTAssertTrue(SettingsAvailability.isAvailable(action, optionAvailable: { _ in false }))
        let paired = SettingsRow(option: "remember", control: .stackedChoice, label: "Volume", secondaryOption: "volume")
        XCTAssertFalse(SettingsAvailability.isAvailable(paired, optionAvailable: { $0 != "volume" }))
        // A dependent row stays visible while its read-only visibility option has no schema.
        let relativeFont = SettingsCatalog.bundled.allRows.first { $0.option == "sub-text-scale" }!
        XCTAssertTrue(SettingsAvailability.isAvailable(relativeFont, optionAvailable: { $0 != "macosx-redesign-sub-size-mode" }))
    }

    func testFigmaRowsWithoutMeaningOnMacOSAreNotInTheCatalog() {
        let options = SettingsCatalog.bundled.referencedOptions
        for name in ["macosx-redesign-language", "macosx-redesign-update-check", "macosx-redesign-custom-skin",
                     "macosx-redesign-skin-file", "video-deco", "embedded-video", "playlist-tree", "one-instance",
                     "macosx-redesign-lastfm", "macosx-redesign-web-remote", "macosx-redesign-cipher-preference",
                     "macosx-redesign-process-priority", "macosx-redesign-audio-device", "encoder", "high-priority", "http-proxy"] {
            XCTAssertFalse(options.contains(name), name)
        }
        XCTAssertFalse(SettingsCatalog.bundled.categories.flatMap(\.sections).contains { $0.title == "Skin" })
    }

    @MainActor
    func testSettingsChoicesNeverShowRawEngineValues() {
        let app = AppModel.mock(.idle)
        let verbosity = SettingsCatalog.bundled.allRows.first { $0.option == "log-verbose" }!
        app.settings.setValue(.integer(-1), for: verbosity)
        XCTAssertEqual(SettingsChoices.title(for: verbosity, in: app.settings), "Errors only")
        app.settings.setValue(.integer(7), for: verbosity)
        XCTAssertEqual(SettingsChoices.title(for: verbosity, in: app.settings), "Custom")
        let preset = SettingsCatalog.bundled.allRows.first { $0.option == "sout-x264-preset" }!
        app.settings.setValue(.string(""), for: preset)
        XCTAssertEqual(SettingsChoices.title(for: preset, in: app.settings), "Medium") // x264 default, 6571:16813
        let device = SettingsCatalog.bundled.allRows.first { $0.option == "auhal-audio-device" }!
        app.settings.setValue(.string("0"), for: device)
        XCTAssertEqual(SettingsChoices.title(for: device, in: app.settings), "System default")
        let drive = SettingsCatalog.bundled.allRows.first { $0.option == "dvd" }!
        app.settings.setValue(.string("/Volumes/MY_MOVIE"), for: drive)
        XCTAssertEqual(SettingsChoices.title(for: drive, in: app.settings), "MY_MOVIE")
    }

    @MainActor
    func testDestructiveSettingsActionsAskFirst() {
        for action in ["reset-all-settings", "reset-shortcuts", "clear-history"] {
            XCTAssertNotNil(SettingsConfirmation(row: SettingsRow(action: action, control: .button, label: action)), action)
        }
        XCTAssertNil(SettingsConfirmation(row: SettingsRow(action: "open-config-folder", control: .button, label: "Open")))
    }

    @MainActor
    func testErrorDialogsDefaultOnAndDependentRowsDisableWithTheirParent() {
        let app = AppModel.mock(.idle)
        let row = SettingsCatalog.bundled.allRows.first { $0.option == "macosx-redesign-show-errors" }!
        XCTAssertTrue(app.settings.bool(row))
        XCTAssertTrue(SettingsAvailability.isAvailable(row, in: app.settings))
        let logFile = SettingsCatalog.bundled.allRows.first { $0.option == "logfile" }!
        let logging = SettingsCatalog.bundled.allRows.first { $0.option == "file-logging" }!
        app.settings.setValue(.bool(false), for: logging)
        XCTAssertFalse(app.settings.isEnabled(logFile))
        app.settings.setValue(.bool(true), for: logging)
        XCTAssertTrue(app.settings.isEnabled(logFile))
    }

    @MainActor
    func testCaptureResponderRecordsOneCombinationAndHonorsEscapeAndDelete() {
        func key(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags = [], repeated: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                             characters: chars, charactersIgnoringModifiers: chars.lowercased(), isARepeat: repeated, keyCode: code)!
        }
        var captured: [KeyBinding?] = []
        var cancelled = 0
        let responder = SettingsKeyCaptureResponder()
        responder.capture = { captured.append($0) }
        responder.cancel = { cancelled += 1 }
        responder.keyDown(with: key(35, "P", [.command, .shift], repeated: true))
        XCTAssertTrue(captured.isEmpty, "Key repeats are ignored")
        responder.keyDown(with: key(35, "P", [.command, .shift]))
        XCTAssertEqual(captured, [KeyBinding(key: "p", modifiers: [.command, .shift])])
        responder.keyDown(with: key(3, "f"))
        XCTAssertEqual(captured.count, 1, "A field records one combination per click")

        let escape = SettingsKeyCaptureResponder()
        escape.capture = { captured.append($0) }
        escape.cancel = { cancelled += 1 }
        escape.keyDown(with: key(53, "\u{1b}"))
        XCTAssertEqual(cancelled, 1)
        XCTAssertEqual(captured.count, 1, "Esc cancels instead of being recorded")

        let delete = SettingsKeyCaptureResponder()
        delete.capture = { captured.append($0) }
        delete.keyDown(with: key(51, "\u{7f}"))
        XCTAssertEqual(captured.count, 2)
        XCTAssertNil(captured[1], "Delete clears the binding")
    }

    @MainActor
    func testSettingsGalleryCoversAllCategoriesAndShortcutDialog() {
        GalleryCatalog.bootstrap()
        let entries = GalleryCatalog.allEntries()
        for category in SettingsCatalog.bundled.categories {
            XCTAssertTrue(entries.contains { $0.id == "S48.Settings/\(category.id)" }, category.id)
        }
        XCTAssertTrue(entries.contains { $0.id == "S64.KeyboardShortcuts/default" })
        XCTAssertTrue(entries.contains { $0.id == "S48.Settings/search" })
        XCTAssertTrue(entries.contains { $0.id == "S48.Settings/general-light" })
    }

    @MainActor
    func testShortcutConflictsRemainDraftUntilSavedAndCancelRestoresBinding() {
        let app = AppModel.mock(.idle)
        let original = app.shortcuts.primaryBinding(for: "play-pause")
        let fullscreen = app.shortcuts.primaryBinding(for: "toggle-fullscreen")!
        app.shortcuts.setBinding(fullscreen, for: "play-pause")
        XCTAssertTrue(app.shortcuts.conflicts(for: fullscreen, excluding: "play-pause").contains { $0.id == "toggle-fullscreen" })
        XCTAssertEqual(app.shortcuts.primaryBinding(for: "play-pause"), original)
        app.shortcuts.discardDraft()
        XCTAssertFalse(app.shortcuts.hasChanges)
        XCTAssertEqual(app.shortcuts.editedActions.first { $0.id == "play-pause" }?.hotkeys.first, original)
    }
}
