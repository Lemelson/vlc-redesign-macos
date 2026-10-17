import Foundation

/// A configuration value, typed like VLC's `module_config_t` values.
public enum SettingValue: Hashable, Sendable, Codable, CustomStringConvertible {
    case bool(Bool)
    /// Integers, key codes and RGB colors (`CONFIG_ITEM_INTEGER/RGB/BOOL` store `int64_t`).
    case integer(Int)
    case float(Double)
    /// Strings, paths, fonts, module names, key bindings (`CONFIG_ITEM_STRING/…`).
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .float(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let v): try container.encode(v)
        case .integer(let v): try container.encode(v)
        case .float(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        }
    }

    /// The value as a Bool (integers: non-zero).
    public var boolValue: Bool? {
        switch self {
        case .bool(let v): v
        case .integer(let v): v != 0
        default: nil
        }
    }

    /// The value as an Int (floats are truncated, Bools are 0/1).
    public var intValue: Int? {
        switch self {
        case .integer(let v): v
        case .bool(let v): v ? 1 : 0
        case .float(let v): Int(v)
        case .string(let v): Int(v)
        }
    }

    /// The value as a Double.
    public var doubleValue: Double? {
        switch self {
        case .float(let v): v
        case .integer(let v): Double(v)
        case .bool(let v): v ? 1 : 0
        case .string(let v): Double(v)
        }
    }

    /// The value as a String (numbers are formatted).
    public var stringValue: String? {
        switch self {
        case .string(let v): v
        case .integer(let v): String(v)
        case .float(let v): String(v)
        case .bool(let v): v ? "true" : "false"
        }
    }

    public var description: String { stringValue ?? "" }

    /// True when both values denote the same number/flag/text, ignoring the integer/float/bool case.
    public func isEquivalent(to other: SettingValue) -> Bool {
        if self == other { return true }
        switch (self, other) {
        case (.string(let a), .string(let b)): return a == b
        case (.string, _), (_, .string): return stringValue == other.stringValue
        default: return doubleValue == other.doubleValue
        }
    }
}

/// VLC configuration item types (`CONFIG_ITEM_*`).
public enum SettingOptionType: String, Sendable, Codable, Hashable {
    case bool, integer, float, string, password, key, module, moduleList, loadFile, saveFile, directory, font, color
}

/// One choice of a dropdown or segmented control: the stored value and its human label.
/// In the mapping file a choice is written as a two-element array: `[3, "Title with extra characters"]`.
public struct SettingChoice: Hashable, Sendable, Codable {
    public var value: SettingValue
    public var title: String

    public init(value: SettingValue, title: String) {
        self.value = value
        self.title = title
    }

    public init(from decoder: Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            value = try array.decode(SettingValue.self)
            title = try array.decode(String.self)
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            value = try container.decode(SettingValue.self, forKey: .value)
            title = try container.decode(String.self, forKey: .title)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var array = encoder.unkeyedContainer()
        try array.encode(value)
        try array.encode(title)
    }

    private enum CodingKeys: String, CodingKey { case value, title }
}

/// Engine-side description of one option (`module_config_t`), as reported by the settings backend.
public struct SettingOption: Hashable, Sendable {
    /// VLC option name, e.g. `"sub-autodetect-fuzzy"`, or an app option `"macosx-redesign-theme"`.
    public var name: String
    public var type: SettingOptionType
    public var defaultValue: SettingValue
    /// Inclusive numeric range, if the option has one.
    public var range: ClosedRange<Double>?
    /// Static choices (`list`/`list_text`), translated.
    public var choices: [SettingChoice]
    /// Short text (`psz_text`).
    public var text: String?
    /// Long text (`psz_longtext`), used as a fallback for the ⓘ info.
    public var longText: String?
    /// Owning module ("freetype", "core").
    public var module: String?

    public init(name: String, type: SettingOptionType, defaultValue: SettingValue, range: ClosedRange<Double>? = nil,
                choices: [SettingChoice] = [], text: String? = nil, longText: String? = nil, module: String? = nil) {
        self.name = name
        self.type = type
        self.defaultValue = defaultValue
        self.range = range
        self.choices = choices
        self.text = text
        self.longText = longText
        self.module = module
    }
}

/// Settings change notifications.
public enum SettingsEvent: Sendable {
    /// One option changed (from the UI, a hotkey or the engine).
    case valueChanged(String)
    /// Everything was reset or reloaded.
    case reloaded
    /// Audio outputs or capture devices were plugged in or removed; no setting value changed.
    case devicesChanged
}
