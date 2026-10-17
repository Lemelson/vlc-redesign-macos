import AppKit
import Foundation
import MXRCore

/// Rows are shown only when the engine provides every option they read or write (D035). Native
/// backends publish metadata only for options that work in this build, so an unsupported row is
/// hidden instead of listed as unavailable.
enum SettingsAvailability {
    static func isAvailable(_ row: SettingsRow, optionAvailable: (String) -> Bool) -> Bool {
        let required = row.optionNames + (row.enabledWhen.map { [$0.option] } ?? [])
        return required.allSatisfy(optionAvailable)
    }

    @MainActor
    static func isAvailable(_ row: SettingsRow, in settings: SettingsModel) -> Bool {
        isAvailable(row) { settings.backend.option(named: $0) != nil }
    }
}

/// Dropdown titles and runtime choices. A dropdown never shows a raw engine value (SD-04): the
/// catalog title wins, then a runtime choice, then VLC's own choice text, then a readable fallback.
@MainActor
enum SettingsChoices {
    static func all(for row: SettingsRow, in settings: SettingsModel) -> [SettingChoice] {
        let fixed = settings.choices(for: row)
        guard let source = row.choiceSource else { return fixed }
        let extra = runtimeChoices(source, in: settings).filter { choice in !fixed.contains { $0.value.isEquivalent(to: choice.value) } }
        return fixed + extra
    }

    static func title(for row: SettingsRow, in settings: SettingsModel) -> String {
        if row.composite != nil { return settings.selectedChoiceTitle(for: row) ?? "Custom" }
        guard let value = normalized(settings.value(for: row), row: row) else {
            return all(for: row, in: settings).first?.title ?? ""
        }
        if let title = all(for: row, in: settings).first(where: { $0.value.isEquivalent(to: value) })?.title { return title }
        if let option = row.option,
           let title = settings.backend.option(named: option)?.choices.first(where: { $0.value.isEquivalent(to: value) })?.title,
           !title.isEmpty {
            return title
        }
        if case .string(let text) = value, text.hasPrefix("/") { return URL(fileURLWithPath: text).lastPathComponent }
        return "Custom"
    }

    /// The choice that is checked in the menu (the normalized current value).
    static func selection(for row: SettingsRow, in settings: SettingsModel) -> SettingValue? {
        if row.composite != nil { return settings.compositeSelection(for: row).map(SettingValue.integer) }
        return normalized(settings.value(for: row), row: row)
    }

    /// auhal stores the system output as "0" after it closes; the catalog spells it "".
    private static func normalized(_ value: SettingValue?, row: SettingsRow) -> SettingValue? {
        if row.choiceSource == "audio-devices", value?.stringValue == "0" { return .string("") }
        return value
    }

    static func runtimeChoices(_ source: String, in settings: SettingsModel) -> [SettingChoice] {
        switch source {
        case "audio-devices": settings.deviceChoices(for: .audioOutput).map { SettingChoice(value: .string($0.id), title: $0.name) }
        case "optical-drives": OpticalDiscs.mounted().map { SettingChoice(value: .string($0.path), title: $0.lastPathComponent) }
        default: []
        }
    }
}

/// Mounted DVDs, Blu-ray discs and audio CDs (what VLC's disc access can open by path).
/// The probing lives with the Open Disc dialog (`OpticalDiscs.discs()`, OpenMediaDialogs.swift).
enum OpticalDiscs {
    static func mounted() -> [URL] { discs().map(\.url) }
}
