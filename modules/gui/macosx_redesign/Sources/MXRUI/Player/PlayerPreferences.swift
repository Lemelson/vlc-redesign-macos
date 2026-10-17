import CoreGraphics
import MXRCore

/// UI presentation preferences shared by the player and the app's external chrome.
@MainActor
public struct MXRPlayerPreferences {
    private let app: AppModel
    public init(app: AppModel) { self.app = app }

    public var showsSeekThumbnails: Bool { value("macosx-redesign-seek-thumbnails")?.boolValue ?? true }
    public var showsCoverArtwork: Bool { value("macosx-redesign-show-cover")?.boolValue ?? true }
    public var fullscreenControlsOpacity: Double {
        let opacity = value("macosx-redesign-fs-controls-opacity")?.doubleValue ?? 100
        return opacity.isFinite ? min(max(opacity, 10), 100) / 100 : 1
    }
    /// The settings schema names three sensitivities; wider edge zones reveal controls sooner.
    public var fullscreenHoverEdge: CGFloat {
        switch value("macosx-redesign-fs-sensitivity")?.stringValue {
        case "low": 24
        case "high": 120
        default: 64
        }
    }

    private func value(_ option: String) -> SettingValue? {
        _ = app.settings.revision
        return app.settings.backend.value(for: option)
    }
}
