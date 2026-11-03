import Foundation

/// App updates (Sparkle, D059). The native backend wraps Sparkle's updater; a build without
/// Sparkle has none, and then the update rows and the menu item are not shown (D035).
@MainActor
public protocol UpdaterBackend: AnyObject {
    /// Sparkle checks once a day in the background. Unset until the user answers Sparkle's question
    /// on the second launch; the toggle then reads off.
    var automaticallyChecks: Bool { get set }
    /// A found update is downloaded in the background and installed when the app quits.
    var automaticallyInstalls: Bool { get set }
    /// False while a check or an installation is running.
    var canCheckForUpdates: Bool { get }
    var lastCheckDate: Date? { get }
    /// A user-initiated check: Sparkle's own window reports the result.
    func checkForUpdates()
    /// Called after any of the values above changed (also when Sparkle changed them itself).
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor () -> Void)
}

/// The Settings rows of the updater. They are not VLC options: Sparkle keeps them in the app's
/// defaults, where its own permission question and update window also write them.
public enum UpdaterSettings {
    /// General ▸ Startup "Check for updates automatically" (Figma 3046:9901).
    public static let automaticChecks = "updater-automatic-checks"
    /// "Install updates automatically".
    public static let automaticInstalls = "updater-automatic-installs"
    /// Read-only: whether "Check Now" can run; its row is enabled by it.
    public static let canCheck = "updater-can-check"
    public static let names: Set<String> = [automaticChecks, automaticInstalls, canCheck]
}

/// Serves the ``UpdaterSettings`` names from the updater and forwards every other option to the
/// engine's settings, so the Settings UI binds them like any other row.
@MainActor
public final class UpdaterSettingsBackend: SettingsBackend {
    public let base: any SettingsBackend
    public let updater: any UpdaterBackend
    private let events = EventChannel<SettingsEvent>()

    public init(base: any SettingsBackend, updater: any UpdaterBackend) {
        self.base = base
        self.updater = updater
        updater.addListener(self) { [weak self] in
            for name in UpdaterSettings.names.sorted() { self?.events.send(.valueChanged(name)) }
        }
    }

    public func option(named name: String) -> SettingOption? {
        guard UpdaterSettings.names.contains(name) else { return base.option(named: name) }
        return SettingOption(name: name, type: .bool, defaultValue: .bool(name == UpdaterSettings.canCheck))
    }

    public func value(for name: String) -> SettingValue? {
        switch name {
        case UpdaterSettings.automaticChecks: .bool(updater.automaticallyChecks)
        case UpdaterSettings.automaticInstalls: .bool(updater.automaticallyInstalls)
        case UpdaterSettings.canCheck: .bool(updater.canCheckForUpdates)
        default: base.value(for: name)
        }
    }

    public func setValue(_ value: SettingValue, for name: String, apply: SettingsApply) {
        switch name {
        case UpdaterSettings.automaticChecks:
            guard let flag = value.boolValue else { return }
            updater.automaticallyChecks = flag
        case UpdaterSettings.automaticInstalls:
            guard let flag = value.boolValue else { return }
            updater.automaticallyInstalls = flag
        case UpdaterSettings.canCheck: return
        default: base.setValue(value, for: name, apply: apply); return
        }
        events.send(.valueChanged(name))
    }

    /// Resets restore VLC's defaults only: whether to look for updates stays the user's answer
    /// (Sparkle has no "unset" to return to).
    public func resetValue(for name: String) {
        guard !UpdaterSettings.names.contains(name) else { return }
        base.resetValue(for: name)
    }
    public func resetAll() { base.resetAll() }
    public func save() { base.save() }
    public func dynamicChoices(for name: String) async -> [SettingChoice] { await base.dynamicChoices(for: name) }
    public func availableDevices(for kind: MediaDeviceKind) async -> [MediaDevice] { await base.availableDevices(for: kind) }
    public var allOptionNames: [String] { base.allOptionNames }

    public func addListener(_ owner: AnyObject, handler: @escaping @MainActor (SettingsEvent) -> Void) {
        base.addListener(owner, handler: handler)
        events.add(owner, handler: handler)
    }
}
