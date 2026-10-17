import Foundation
import Observation

/// The Settings window (S48–S63): catalog navigation, search, values and Advanced Options.
@MainActor
@Observable
public final class SettingsModel {
    /// The UI structure (categories → sections → rows).
    public let catalog: SettingsCatalog
    /// The selected sidebar category id ("general").
    public var selectedCategoryID: String
    /// Search field text; filters rows across categories.
    public var searchText: String = ""
    /// Categories whose "Advanced Options" are expanded.
    public var expandedAdvanced: Set<String> = []
    /// Incremented on every value change, so views that read values through methods refresh.
    public private(set) var revision = 0

    @ObservationIgnored public let backend: any SettingsBackend
    /// Called for `.button` rows ("clear-history", "edit-shortcuts", …). Set by ``AppModel``.
    @ObservationIgnored public var actionHandler: (@MainActor (String) -> Void)?
    private var deviceValues: [MediaDeviceKind: [MediaDevice]] = [:]
    @ObservationIgnored private var deviceRequests: [MediaDeviceKind: Task<Void, Never>] = [:]
    /// Incremented when the engine reports a device hot-plug; views reload their device rows on it.
    public private(set) var deviceGeneration = 0
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Delay before changes are persisted.
    @ObservationIgnored public var saveDelay: Duration = .milliseconds(500)

    public init(backend: any SettingsBackend, catalog: SettingsCatalog = .bundled) {
        self.backend = backend
        self.catalog = catalog
        self.selectedCategoryID = catalog.categories.first?.id ?? "general"
        for row in catalog.allRows where row.apply == .restart { if let option = row.option { recordLaunchValue(of: option) } }
        backend.addListener(self) { [weak self] event in
            guard let self else { return }
            if case .devicesChanged = event {
                // Only the device lists are stale: values and profiles are untouched.
                self.deviceGeneration += 1
                return
            }
            self.revision += 1
        }
    }

    /// Feedback from maintenance actions.
    public var actionMessage: String?
    /// The values the running engine started with, for options that apply after a restart (C-15).
    @ObservationIgnored private var launchValues: [String: SettingValue] = [:]
    private func recordLaunchValue(of option: String) {
        if launchValues[option] == nil, let value = backend.value(for: option) { launchValues[option] = value }
    }
    /// `apply: restart` options whose value now differs from the one VLC started with: the running
    /// engine still uses the old value. Setting it back (by hand, Reset or a profile) clears it.
    public var restartPendingOptions: Set<String> {
        _ = revision
        return Set(catalog.allRows.filter { $0.apply == .restart }.compactMap(\.option).filter { option in
            guard let launch = launchValues[option], let current = backend.value(for: option) else { return false }
            return !current.isEquivalent(to: launch)
        })
    }
    public func needsRestart(_ row: SettingsRow) -> Bool {
        _ = revision
        guard row.apply == .restart, let option = row.option, let launch = launchValues[option],
              let current = backend.value(for: option) else { return false }
        return !current.isEquivalent(to: launch)
    }
    public var allModuleOptions: [SettingOption] = []
    public var showsAllModules = false

    /// The last loaded hardware choices (empty until ``loadDeviceChoices(for:)`` ran). A pure read:
    /// loading never starts from a view body and never changes setting values.
    public func deviceChoices(for kind: MediaDeviceKind) -> [MediaDevice] {
        _ = revision
        return deviceValues[kind] ?? []
    }

    /// The device kind a runtime `choiceSource` lists, if any.
    public static func deviceKind(forChoiceSource source: String?) -> MediaDeviceKind? {
        source == "audio-devices" ? .audioOutput : nil
    }

    /// Device kinds listed by the rows on screen (the selected category, or the search results).
    public var visibleDeviceKinds: Set<MediaDeviceKind> {
        let rows = searchResults.isEmpty ? (selectedCategory?.sections.flatMap(\.rows) ?? []) : searchResults.flatMap(\.rows)
        return Set(rows.compactMap { Self.deviceKind(forChoiceSource: $0.choiceSource) })
    }

    /// Queries the hardware for these kinds, keeping the previous list on screen meanwhile.
    /// Concurrent requests for one kind share a single query.
    public func loadDeviceChoices(for kinds: Set<MediaDeviceKind>) async {
        for kind in kinds {
            let request = deviceRequests[kind] ?? Task { @MainActor [weak self] in
                guard let self else { return }
                let devices = await self.backend.availableDevices(for: kind)
                self.deviceRequests[kind] = nil
                if self.deviceValues[kind] != devices {
                    self.deviceValues[kind] = devices
                    self.revision += 1
                }
            }
            deviceRequests[kind] = request
            await request.value
        }
    }

    // MARK: Navigation

    public var selectedCategory: SettingsCategory? { catalog.category(selectedCategoryID) }

    /// Categories grouped for the sidebar (App, Media, System).
    public var groupedCategories: [(group: SettingsGroup, categories: [SettingsCategory])] {
        SettingsGroup.allCases.compactMap { group in
            let list = catalog.categories.filter { $0.group == group }
            return list.isEmpty ? nil : (group, list)
        }
    }

    public func select(categoryID: String) { selectedCategoryID = categoryID }

    public func isAdvancedExpanded(_ categoryID: String) -> Bool { expandedAdvanced.contains(categoryID) }
    public func toggleAdvanced(_ categoryID: String) {
        if expandedAdvanced.contains(categoryID) { expandedAdvanced.remove(categoryID) } else { expandedAdvanced.insert(categoryID) }
    }

    /// Rows matching the search text (label, info or option name), grouped by category.
    public var searchResults: [(category: SettingsCategory, rows: [SettingsRow])] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        return catalog.categories.compactMap { category in
            let rows = category.sections.flatMap(\.rows).filter { row in
                row.label.lowercased().contains(query)
                    || (row.info?.lowercased().contains(query) ?? false)
                    || row.optionNames.contains { $0.contains(query) }
            }
            return rows.isEmpty ? nil : (category, rows)
        }
    }

    // MARK: Values

    /// The current value of a row's option (composite rows: nil; use ``compositeSelection(for:)``).
    /// Inverted toggles are returned already negated.
    public func value(for row: SettingsRow) -> SettingValue? {
        _ = revision
        guard let option = row.option, let value = backend.value(for: option) else { return nil }
        if row.inverted, let flag = value.boolValue { return .bool(!flag) }
        if let automatic = row.automaticValue, value.isEquivalent(to: automatic) { return nil }
        if row.engineUnitsPerUnit != 1, let number = value.doubleValue { return .float(number / row.engineUnitsPerUnit) }
        if row.displayOffset != 0 { return Self.offset(value, by: row.displayOffset) }
        return value
    }

    private static func offset(_ value: SettingValue, by delta: Double) -> SettingValue {
        switch value {
        case .integer(let number): .integer(number + Int(delta))
        case .float(let number): .float(number + delta)
        default: value
        }
    }

    /// Returns a row with an ``SettingsRow/automaticValue`` to automatic (the field is emptied).
    public func setAutomatic(for row: SettingsRow) {
        guard let option = row.option, let automatic = row.automaticValue else { return }
        backend.setValue(automatic, for: option, apply: row.apply)
        revision += 1
        scheduleSave()
    }

    /// The inline value of a `.stackedChoice` row's second choice.
    public func secondaryValue(for row: SettingsRow) -> SettingValue? {
        _ = revision
        guard let option = row.secondaryOption else { return nil }
        return backend.value(for: option)
    }

    public func setSecondaryValue(_ value: SettingValue, for row: SettingsRow) {
        guard let option = row.secondaryOption else { return }
        backend.setValue(value, for: option, apply: row.apply)
        revision += 1
        scheduleSave()
    }

    /// Typed accessors.
    public func bool(_ row: SettingsRow) -> Bool { value(for: row)?.boolValue ?? false }
    public func double(_ row: SettingsRow) -> Double { value(for: row)?.doubleValue ?? row.min ?? 0 }
    public func string(_ row: SettingsRow) -> String { value(for: row)?.stringValue ?? "" }

    /// Writes a row's value and schedules a save.
    public func setValue(_ value: SettingValue, for row: SettingsRow) {
        guard let option = row.option else { return }
        var value = value
        if row.inverted, let flag = value.boolValue { value = .bool(!flag) }
        if row.engineUnitsPerUnit != 1, let number = value.doubleValue {
            let scaled = number * row.engineUnitsPerUnit
            guard scaled.isFinite else { return }
            // Round at the engine's integral precision, rather than truncating.
            value = .float(scaled.rounded())
        }
        if row.displayOffset != 0 { value = Self.offset(value, by: -row.displayOffset) }
        if row.apply == .restart { recordLaunchValue(of: option) }
        backend.setValue(value, for: option, apply: row.apply)
        revision += 1
        scheduleSave()
    }

    /// The choices of a dropdown/segmented row (catalog choices, else the engine's).
    public func choices(for row: SettingsRow) -> [SettingChoice] {
        if let choices = row.choices { return choices }
        if let composite = row.composite {
            return composite.enumerated().map { SettingChoice(value: .integer($0.offset), title: $0.element.title) }
        }
        guard let option = row.option else { return [] }
        return backend.option(named: option)?.choices ?? []
    }

    /// The selected choice's title (dropdown label).
    public func selectedChoiceTitle(for row: SettingsRow) -> String? {
        if row.composite != nil {
            guard let index = compositeSelection(for: row) else { return nil }
            return row.composite?[index].title
        }
        guard let value = value(for: row) else { return nil }
        return choices(for: row).first { $0.value.isEquivalent(to: value) }?.title
    }

    /// Index of the composite choice whose values all match the current options, if any.
    public func compositeSelection(for row: SettingsRow) -> Int? {
        _ = revision
        guard let composite = row.composite else { return nil }
        return composite.firstIndex { choice in
            choice.values.allSatisfy { name, value in backend.value(for: name)?.isEquivalent(to: value) ?? false }
        }
    }

    /// Selects a composite choice, writing all of its option values.
    public func selectComposite(_ index: Int, for row: SettingsRow) {
        guard let composite = row.composite, composite.indices.contains(index) else { return }
        for (name, value) in composite[index].values.sorted(by: { $0.key < $1.key }) {
            backend.setValue(value, for: name, apply: row.apply)
        }
        revision += 1
        scheduleSave()
    }

    /// Whether the row is enabled (its `enabledWhen` condition holds).
    public func isEnabled(_ row: SettingsRow) -> Bool {
        _ = revision
        guard let condition = row.enabledWhen else { return true }
        return backend.value(for: condition.option)?.isEquivalent(to: condition.equals) ?? false
    }

    /// Whether the row is shown (its `visibleWhen` condition holds).
    public func isVisible(_ row: SettingsRow) -> Bool {
        _ = revision
        guard let condition = row.visibleWhen else { return true }
        return backend.value(for: condition.option)?.isEquivalent(to: condition.equals) ?? false
    }

    /// Visible rows of a section.
    public func visibleRows(of section: SettingsSection) -> [SettingsRow] { section.rows.filter(isVisible) }

    /// The ⓘ text. The catalog decides, because it follows the Figma rows: a row without `info`
    /// has no ⓘ even when VLC has a long text for its option (Figma 3046:10057 "Remember window
    /// size and position", 3073:14187 "Hue"). Generated rows (VLC modules, filter inspectors) put
    /// the engine's long text in `info` themselves.
    public func info(for row: SettingsRow) -> String? { row.info }

    /// Performs a `.button` row's action.
    public func perform(_ row: SettingsRow) {
        guard let action = row.action else { return }
        actionHandler?(action)
    }

    /// Restores the defaults of every option in a category.
    public func resetCategory(_ categoryID: String) {
        guard let category = catalog.category(categoryID) else { return }
        for name in Set(category.sections.flatMap { $0.rows.flatMap(\.optionNames) }) {
            backend.resetValue(for: name)
        }
        revision += 1
        scheduleSave()
    }

    /// Persists now (window close).
    public func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        backend.save()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let delay = saveDelay
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.backend.save()
            self?.saveTask = nil
        }
    }
}
