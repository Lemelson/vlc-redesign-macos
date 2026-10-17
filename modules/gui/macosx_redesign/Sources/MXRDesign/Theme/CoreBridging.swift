import MXRCore

extension Theme.Accent {
    /// The design accent for the stored setting (`macosx-redesign-accent`); the raw values match.
    public init(_ choice: AccentChoice) {
        self = Theme.Accent(rawValue: choice.rawValue) ?? .orange
    }
}

extension Theme.Mode {
    /// The theme mode for the stored setting (`macosx-redesign-theme`); the raw values match.
    public init(_ preference: ThemePreference) {
        self = Theme.Mode(rawValue: preference.rawValue) ?? .dark
    }
}
