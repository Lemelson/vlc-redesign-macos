import MXRBridgeAPI

extension MXRBridgeService {
    /// Explicit extensibility for VLC option notifications, never for arbitrary services.
    static func settingOption(_ option: String) -> Self { MXRBridgeServiceForSetting(option) }

    var settingOptionName: String? {
        let prefix = "settings:"
        guard rawValue.hasPrefix(prefix), rawValue.count > prefix.count else { return nil }
        return String(rawValue.dropFirst(prefix.count))
    }
}
