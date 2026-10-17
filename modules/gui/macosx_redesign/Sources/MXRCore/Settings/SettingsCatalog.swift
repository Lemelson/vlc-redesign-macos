import Foundation
import os

/// The settings UI structure (D013): categories → sections → rows, each row bound to VLC option(s).
///
/// Loaded from `Resources/settings-map.json5`. Values are never stored here; they come from the
/// ``SettingsBackend``. See ARCHITECTURE.md §5.2.
public struct SettingsCatalog: Hashable, Sendable, Codable {
    public var version: Int
    public var categories: [SettingsCategory]
    /// Option names (or `prefix-*` patterns) that are never shown.
    public var hidden: [String]

    public init(version: Int = 1, categories: [SettingsCategory], hidden: [String] = []) {
        self.version = version
        self.categories = categories
        self.hidden = hidden
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        categories = try c.decode([SettingsCategory].self, forKey: .categories)
        hidden = try c.decodeIfPresent([String].self, forKey: .hidden) ?? []
    }

    private enum CodingKeys: String, CodingKey { case version, categories, hidden }

    /// The category with `id`.
    public func category(_ id: String) -> SettingsCategory? { categories.first { $0.id == id } }

    /// Every row of every category.
    public var allRows: [SettingsRow] { categories.flatMap { $0.sections.flatMap(\.rows) } }

    /// Every VLC option name referenced by the catalog.
    public var referencedOptions: Set<String> {
        Set(allRows.flatMap { $0.optionNames })
    }

    /// Decodes a catalog from JSON5 data.
    public static func decode(json5 data: Data) throws -> SettingsCatalog {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        return try decoder.decode(SettingsCatalog.self, from: data)
    }

    /// The catalog bundled with the Core resources (`settings-map.json5`), or an empty catalog
    /// (logged) when it cannot be found or parsed.
    public static let bundled: SettingsCatalog = {
        let logger = Logger(subsystem: "org.videolan.vlc-redesign", category: "settings")
        guard let url = MXRResources.url(forResource: "settings-map", withExtension: "json5") else {
            logger.error("settings-map.json5 not found")
            return SettingsCatalog(categories: [])
        }
        do {
            return try decode(json5: Data(contentsOf: url))
        } catch {
            logger.error("settings-map.json5 is invalid: \(String(describing: error), privacy: .public)")
            return SettingsCatalog(categories: [])
        }
    }()
}

/// Sidebar groups of the Settings window.
public enum SettingsGroup: String, Sendable, Codable, Hashable, CaseIterable {
    case app, media, system

    /// "App", "Media", "System".
    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// One settings category (sidebar item + page).
public struct SettingsCategory: Identifiable, Hashable, Sendable, Codable {
    /// "general", "interface", …, "extensions".
    public var id: String
    public var group: SettingsGroup
    /// Sidebar label ("General").
    public var sidebar: String
    /// Page title ("Global Settings").
    public var title: String
    /// Icon name from `ICONS.md` (outline; the selected state uses the filled variant).
    public var icon: String
    public var sections: [SettingsSection]

    public init(id: String, group: SettingsGroup, sidebar: String, title: String, icon: String, sections: [SettingsSection]) {
        self.id = id
        self.group = group
        self.sidebar = sidebar
        self.title = title
        self.icon = icon
        self.sections = sections
    }

    /// Basic sections, shown first.
    public var basicSections: [SettingsSection] { sections.filter { !$0.advanced } }
    /// Sections under the collapsible "Advanced Options" bar.
    public var advancedSections: [SettingsSection] { sections.filter(\.advanced) }
}

/// A titled group of rows ("Appearance"). Advanced sections appear below "Advanced Options".
public struct SettingsSection: Identifiable, Hashable, Sendable, Codable {
    public var title: String
    public var advanced: Bool
    public var rows: [SettingsRow]

    public var id: String { (advanced ? "advanced:" : "") + title }

    public init(title: String, advanced: Bool = false, rows: [SettingsRow]) {
        self.title = title
        self.advanced = advanced
        self.rows = rows
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        advanced = try c.decodeIfPresent(Bool.self, forKey: .advanced) ?? false
        rows = try c.decode([SettingsRow].self, forKey: .rows)
    }

    private enum CodingKeys: String, CodingKey { case title, advanced, rows }
}

/// Which control a row uses (spec-part2 §14 A).
public enum SettingsControl: String, Sendable, Codable, Hashable {
    /// The square ON/OFF toggle.
    case toggle
    case dropdown
    /// Equal segments ("Dark | Light | System", "Relative | Pixels").
    case segmented
    /// Slider with optional tick labels.
    case slider
    /// Single-line text field.
    case text
    /// Numeric text field with optional unit.
    case number
    /// Hex field + swatch.
    case color
    /// The 9 accent swatches.
    case swatches
    /// Text field + "Browse" (file).
    case file
    /// Text field + "Browse" (folder).
    case directory
    /// A secondary button (`buttonTitle`) that triggers `action`.
    case button
    /// Two stacked options, the second with an inline value ("Remember last volume" / "Always starts at:").
    case stackedChoice
    /// The inline 11-band equalizer panel.
    case equalizer
    /// The extensions list box.
    case extensionList
    /// A key-binding field.
    case key
}

/// When a changed value takes effect.
public enum SettingsApply: Hashable, Sendable, Codable {
    /// Read when the next media opens (VLC default).
    case nextMedia
    /// Needs an app restart (the UI shows a note).
    case restart
    /// Also applied immediately to the current object(s): "vout", "aout" or "instance".
    /// (Playlist order options are applied live by the bridge by option name, not through this.)
    case live(String)

    public init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            self = text == "restart" ? .restart : .nextMedia
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self = .live(try c.decode(String.self, forKey: .live))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .nextMedia:
            var c = encoder.singleValueContainer()
            try c.encode("next-media")
        case .restart:
            var c = encoder.singleValueContainer()
            try c.encode("restart")
        case .live(let target):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(target, forKey: .live)
        }
    }

    private enum CodingKeys: String, CodingKey { case live }
}

/// A row is enabled only when another option has a given value (e.g. "Skin file" needs "Use a custom skin").
public struct SettingsCondition: Hashable, Sendable, Codable {
    public var option: String
    public var equals: SettingValue

    public init(option: String, equals: SettingValue) {
        self.option = option
        self.equals = equals
    }
}

/// One choice of a composite row: the title and the values it writes to several options.
public struct SettingsCompositeChoice: Hashable, Sendable, Codable {
    public var title: String
    public var values: [String: SettingValue]

    public init(title: String, values: [String: SettingValue]) {
        self.title = title
        self.values = values
    }
}

/// One settings row.
public struct SettingsRow: Identifiable, Hashable, Sendable, Codable {
    /// Unique id; defaults to the option name, the custom key or the action id.
    public var id: String
    /// The VLC (or `macosx-redesign-*`) option the row edits.
    public var option: String?
    /// Composite rows: one control writing several options (Network ▸ Buffering).
    public var composite: [SettingsCompositeChoice]?
    /// For `.button` rows: the action to perform ("clear-history", "edit-shortcuts").
    public var action: String?
    public var control: SettingsControl
    /// Human label ("Load subtitle files automatically").
    public var label: String
    /// Text of the ⓘ popover; nil = no info icon.
    public var info: String?
    /// Choices for dropdowns and segmented controls; when nil the backend's option choices are used.
    public var choices: [SettingChoice]?
    /// Choices computed at runtime and listed after ``choices`` ("audio-devices", "optical-drives").
    public var choiceSource: String?
    public var min: Double?
    public var max: Double?
    public var step: Double?
    /// Unit suffix for numbers and sliders ("s", "%", "ms", "px").
    public var unit: String?
    /// Integral engine units per displayed unit (e.g. deciseconds per second).
    public var engineUnitsPerUnit: Double
    /// Added to the engine value for display and removed when writing: VLC's 0-based stream
    /// index (`audio-track`) reads as track 1, 2, 3…
    public var displayOffset: Double
    /// The engine value meaning "automatic": shown as an empty field with ``placeholder``,
    /// and written back when the field is emptied (`audio-track` -1).
    public var automaticValue: SettingValue?
    /// Labels under a slider, e.g. ["0%", "50%", "100%"].
    public var scaleLabels: [String]?
    /// Tick positions of a slider, both ends included (Figma's "degrees" vectors: Maximum volume
    /// 3176:16473 has 9, one per 25 %); nil derives them from ``step``.
    public var ticks: Int?
    /// The Figma row height where it differs from the control's usual one (a 46-point text row,
    /// 3046:9521); nil uses the usual height.
    public var rowHeight: Double?
    /// Button title for `.button`, `.file`, `.directory` ("Browse", "Clear", "Reset").
    public var buttonTitle: String?
    /// Placeholder for text fields.
    public var placeholder: String?
    public var apply: SettingsApply
    public var enabledWhen: SettingsCondition?
    /// The row is shown only when this holds (e.g. "Font size" in pixels vs relative mode).
    public var visibleWhen: SettingsCondition?
    /// For toggles bound to a negative option ("Seek precisely" = `input-fast-seek` off).
    public var inverted: Bool
    /// For `.stackedChoice`: the option edited by the inline value of the second choice
    /// ("Always starts at: 200%").
    public var secondaryOption: String?
    /// The value the mock backend starts with (what the Figma render shows). Ignored by the VLC backend.
    public var mock: SettingValue?
    /// Mock value of ``secondaryOption``.
    public var secondaryMock: SettingValue?

    public init(id: String? = nil, option: String? = nil, composite: [SettingsCompositeChoice]? = nil, action: String? = nil,
                control: SettingsControl, label: String, info: String? = nil, choices: [SettingChoice]? = nil,
                choiceSource: String? = nil, min: Double? = nil, max: Double? = nil, step: Double? = nil, unit: String? = nil, engineUnitsPerUnit: Double = 1, displayOffset: Double = 0, automaticValue: SettingValue? = nil, scaleLabels: [String]? = nil,
                buttonTitle: String? = nil, placeholder: String? = nil, apply: SettingsApply = .nextMedia,
                enabledWhen: SettingsCondition? = nil, visibleWhen: SettingsCondition? = nil, inverted: Bool = false,
                secondaryOption: String? = nil, mock: SettingValue? = nil, secondaryMock: SettingValue? = nil, ticks: Int? = nil) {
        self.id = id ?? option ?? action ?? label
        self.option = option
        self.composite = composite
        self.action = action
        self.control = control
        self.label = label
        self.info = info
        self.choices = choices
        self.choiceSource = choiceSource
        self.min = min
        self.max = max
        self.step = step
        self.unit = unit
        self.engineUnitsPerUnit = engineUnitsPerUnit
        self.displayOffset = displayOffset
        self.automaticValue = automaticValue
        self.scaleLabels = scaleLabels
        self.ticks = ticks
        self.buttonTitle = buttonTitle
        self.placeholder = placeholder
        self.apply = apply
        self.enabledWhen = enabledWhen
        self.visibleWhen = visibleWhen
        self.inverted = inverted
        self.secondaryOption = secondaryOption
        self.mock = mock
        self.secondaryMock = secondaryMock
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        option = try c.decodeIfPresent(String.self, forKey: .option)
        composite = try c.decodeIfPresent([SettingsCompositeChoice].self, forKey: .composite)
        action = try c.decodeIfPresent(String.self, forKey: .action)
        control = try c.decode(SettingsControl.self, forKey: .control)
        label = try c.decode(String.self, forKey: .label)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? option ?? action ?? label
        info = try c.decodeIfPresent(String.self, forKey: .info)
        choices = try c.decodeIfPresent([SettingChoice].self, forKey: .choices)
        choiceSource = try c.decodeIfPresent(String.self, forKey: .choiceSource)
        min = try c.decodeIfPresent(Double.self, forKey: .min)
        max = try c.decodeIfPresent(Double.self, forKey: .max)
        step = try c.decodeIfPresent(Double.self, forKey: .step)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        engineUnitsPerUnit = try c.decodeIfPresent(Double.self, forKey: .engineUnitsPerUnit) ?? 1
        displayOffset = try c.decodeIfPresent(Double.self, forKey: .displayOffset) ?? 0
        automaticValue = try c.decodeIfPresent(SettingValue.self, forKey: .automaticValue)
        scaleLabels = try c.decodeIfPresent([String].self, forKey: .scaleLabels)
        ticks = try c.decodeIfPresent(Int.self, forKey: .ticks)
        rowHeight = try c.decodeIfPresent(Double.self, forKey: .rowHeight)
        buttonTitle = try c.decodeIfPresent(String.self, forKey: .buttonTitle)
        placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder)
        apply = try c.decodeIfPresent(SettingsApply.self, forKey: .apply) ?? .nextMedia
        enabledWhen = try c.decodeIfPresent(SettingsCondition.self, forKey: .enabledWhen)
        visibleWhen = try c.decodeIfPresent(SettingsCondition.self, forKey: .visibleWhen)
        inverted = try c.decodeIfPresent(Bool.self, forKey: .inverted) ?? false
        secondaryOption = try c.decodeIfPresent(String.self, forKey: .secondaryOption)
        mock = try c.decodeIfPresent(SettingValue.self, forKey: .mock)
        secondaryMock = try c.decodeIfPresent(SettingValue.self, forKey: .secondaryMock)
    }

    private enum CodingKeys: String, CodingKey {
        case id, option, composite, action, control, label, info, choices, choiceSource, min, max, step, unit, engineUnitsPerUnit, displayOffset, automaticValue, scaleLabels, ticks, rowHeight
        case buttonTitle, placeholder, apply, enabledWhen, visibleWhen, inverted, secondaryOption, mock, secondaryMock
    }

    /// Every option this row reads or writes.
    public var optionNames: [String] {
        if let option { return [option] + (secondaryOption.map { [$0] } ?? []) }
        if let composite { return Array(Set(composite.flatMap { $0.values.keys })).sorted() }
        return []
    }
}
