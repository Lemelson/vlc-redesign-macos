import MXRDesign
import SwiftUI

extension Theme.Metric {
    /// Additional measurements from the exact Settings and Keyboard Shortcuts Figma nodes.
    enum SettingsDetail {
        // 3046:9863 Dropdown; I3046:9870;999:4559 inner segment.
        static let controlWidth: CGFloat = 320
        static let controlHeight: CGFloat = 36
        static let controlInnerHeight: CGFloat = 32
        // 3176:16465 slider row; 3176:16469 slider wrapper; 3176:16496 stacked row.
        static let sliderHeight: CGFloat = 57
        static let sliderLabelHeight: CGFloat = 15
        static let stackedRowHeight: CGFloat = 98
        // 3176:16518 numeric row and 6575:17174 extension toolbar.
        static let inputRowHeight: CGFloat = 48
        static let inputTrailingPadding: CGFloat = 18
        static let extensionsToolbarHeight: CGFloat = 53
        // 6571:15888 disabled rows; 6575:17180 extension catalog button.
        static let disabledRowOpacity = 0.3
        static let extensionsCatalogButtonWidth: CGFloat = 185
        // I3176:16574;3176:16553 startup volume input; 3191:18739 color swatch.
        static let secondaryInputWidth: CGFloat = 182
        static let colorSwatchSize: CGFloat = 22
        static let colorSwatchStroke: CGFloat = 1.5
        // 536:1013 toggle: the label cell (536:1010) sits 3 pt in from the edge and 3 pt from the knob
        // (536:1011): 3 + 33 + 3 + 26 + 3 = 68.
        static let toggleInset: CGFloat = 3
        static let toggleGap: CGFloat = 3
        // 3062:10945 info glyph; 3021:9823 group header.
        static let infoSize: CGFloat = 18
        static let groupHeight: CGFloat = 33
        // 3046:9875 accent swatch (cell stretches equally across the control).
        static let swatchSize: CGFloat = 20
        // 3046:9877 … 3046:9891: unselected swatches have 70% opacity.
        static let inactiveSwatchOpacity = 0.7
        // 6338:14145 shortcut field; 6338:14144 action; 6338:14143 row.
        static let shortcutFieldWidth: CGFloat = 270
        static let shortcutFieldHeight: CGFloat = 33
        static let shortcutActionWidth: CGFloat = 290
        // Figma row 6338:14143 places fields at x379 and x738 relative to the body margin.
        static let shortcutLeadingWidth: CGFloat = 379
        static let shortcutRowGap: CGFloat = 89
        // 6338:13885 and 6338:13886 column-heading boxes.
        static let shortcutHeaderActionWidth: CGFloat = 488
        static let shortcutHeaderHotkeyWidth: CGFloat = 332
        // 6575:17173 list box; 3178:16776 equalizer track.
        static let extensionsHeight: CGFloat = 194
        static let equalizerTrackHeight: CGFloat = 320
        // 3178:16988 equalizer band column and 3178:16868 numeric value.
        static let equalizerBandWidth: CGFloat = 60
        // 3178:16988 track-to-label gap; 3178:16872 label and value group.
        static let equalizerBandGap: CGFloat = 33
        static let equalizerValueGroupHeight: CGFloat = 62
    }
}

private struct SettingsControlWidthKey: EnvironmentKey {
    static let defaultValue = Theme.Metric.SettingsDetail.controlWidth
}

extension EnvironmentValues {
    var settingsControlWidth: CGFloat {
        get { self[SettingsControlWidthKey.self] }
        set { self[SettingsControlWidthKey.self] = newValue }
    }
}

/// Preserves the S64 columns at 1048 points and keeps both editors inside narrower sheets.
struct SettingsShortcutLayout {
    let width: CGFloat
    /// The Global Hotkey column exists only where the engine has global hotkeys (not on macOS).
    var showsGlobal = true
    var contentWidth: CGFloat { max(0, width - Theme.Spacing.gap20 * 2) }
    var stacksFields: Bool { width < Theme.Metric.Dialogs.settingsContent.width }
    private var columnScale: CGFloat { contentWidth / (Theme.Metric.Dialogs.keyboardShortcuts.width - Theme.Spacing.gap20 * 2) }
    /// With one key column (this Mac), the field moves to the trailing edge like every Settings control.
    var leadingWidth: CGFloat {
        showsGlobal ? Theme.Metric.SettingsDetail.shortcutLeadingWidth * columnScale : max(0, contentWidth - fieldWidth)
    }
    var fieldWidth: CGFloat { stacksFields ? contentWidth : Theme.Metric.SettingsDetail.shortcutFieldWidth * columnScale }
    var rowGap: CGFloat { Theme.Metric.SettingsDetail.shortcutRowGap * columnScale }
    var headerActionWidth: CGFloat { Theme.Metric.SettingsDetail.shortcutHeaderActionWidth * columnScale }
    var headerHotkeyWidth: CGFloat { Theme.Metric.SettingsDetail.shortcutHeaderHotkeyWidth * columnScale }
    var filterWidth: CGFloat {
        min(Theme.Metric.Controls.dialogHeaderDropdown.width,
            max(0, (width - Theme.Metric.Dialogs.addSubtitlesHeader.padding.leading
                    - Theme.Metric.Dialogs.addSubtitlesHeader.padding.trailing - Theme.Spacing.gap10) / 2))
    }
}
