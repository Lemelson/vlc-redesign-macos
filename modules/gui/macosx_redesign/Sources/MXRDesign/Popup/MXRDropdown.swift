import SwiftUI

/// Figma dropdown variants.
public enum MXRDropdownStyle: Hashable, Sendable {
    /// Settings and sidebar dropdowns (Figma `Dropdown` 2372:8300, `EQ presets`, `HDR Options`,
    /// `sub filename`): 48 pt field, 44 pt options.
    case standard
    /// The sidebar preset picker (Figma `Setting Preset` 2372:8834): 42 pt field (2372:8835),
    /// 38 pt options (2372:8836), `presetListShadow`.
    case preset

    var fieldHeight: CGFloat {
        switch self {
        case .standard: Theme.Metric.Controls.dropdown.height
        case .preset: Theme.Popup.presetFieldHeight
        }
    }

    var optionHeight: CGFloat {
        switch self {
        case .standard: Theme.Metric.Controls.dropdownOption.height
        case .preset: Theme.Popup.presetOptionHeight
        }
    }

    var list: MXRPopupStyle { self == .preset ? .preset : .dropdown }

    /// The inner option of the closed field: BG/A4 in `Dropdown` (2372:8360); the preset field's
    /// option has no fill, so the whole field is BG/B2 (2372:8836).
    var optionFill: ThemeColor { self == .preset ? Theme.Color.bgB2 : Theme.Color.bgA4 }
}

/// One choice of an ``MXRDropdown``.
public struct MXRDropdownOption<Value: Hashable> {
    public var value: Value
    public var title: String
    /// Leading icon (Figma `EQ presets` curves).
    public var icon: MXRIcon.Name?
    public var isEnabled: Bool
    /// Actions behind a leading `⋯` (Figma `Setting Preset`: rename / delete a custom preset).
    public var actions: (@MainActor () -> [MXRMenuItem])?

    public init(_ value: Value, title: String, icon: MXRIcon.Name? = nil, isEnabled: Bool = true,
                actions: (@MainActor () -> [MXRMenuItem])? = nil) {
        self.value = value
        self.title = title
        self.icon = icon
        self.isEnabled = isEnabled
        self.actions = actions
    }
}

/// The Figma dropdown (D025): a dark field with the current value and a chevron that opens the
/// option list below the still-visible field (video 17m31.0; the preset list opens over its field),
/// the current option with an orange check, hover rows, keyboard navigation, Esc and click-outside
/// dismissal.
///
/// ```swift
/// MXRDropdown(selection: $mode, options: HDRMode.allCases.map { MXRDropdownOption($0, title: $0.title) },
///             accessibilityLabel: "HDR")
/// ```
///
/// `leadingItems` are actions listed before the options (Figma `Setting Preset`: "+ New Preset").
public struct MXRDropdown<Value: Hashable>: View {
    @Binding private var selection: Value
    private let options: [MXRDropdownOption<Value>]
    private let style: MXRDropdownStyle
    private let width: CGFloat?
    private let accessibilityLabel: String
    private let leadingItems: @MainActor () -> [MXRMenuItem]
    @State private var isOpen = false
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    /// - Parameter width: field width; `nil` fills the proposed width (Figma fields are 364 pt).
    public init(selection: Binding<Value>, options: [MXRDropdownOption<Value>], style: MXRDropdownStyle = .standard,
                width: CGFloat? = Theme.Metric.Controls.dropdown.width, accessibilityLabel: String,
                @MXRMenuBuilder leadingItems: @escaping @MainActor () -> [MXRMenuItem] = { [] }) {
        _selection = selection
        self.options = options
        self.style = style
        self.width = width
        self.accessibilityLabel = accessibilityLabel
        self.leadingItems = leadingItems
    }

    private var selectedTitle: String { options.first { $0.value == selection }?.title ?? "" }

    private var selectedRow: Int {
        leadingItems().count + (options.firstIndex { $0.value == selection } ?? 0)
    }

    public var body: some View {
        let field = Theme.Metric.Controls.dropdown
        let option = Theme.Metric.Controls.dropdownOption
        Button { isOpen.toggle() } label: {
            HStack(spacing: option.gap) {
                Text(selectedTitle)
                    .mxrTextStyle(Theme.Font.body)
                    .foregroundStyle(Theme.Color.fgA2)
                    .lineLimit(1)
                Spacer(minLength: 0)
                // The preset list opens upward, so its chevron points up (2372:8835); a standard field
                // keeps its down chevron while its list is open below it (17m31.0).
                MXRIcon(style == .preset ? .chevronUp : .chevronDown)
            }
            .padding(option.padding)
            .frame(height: style.optionHeight)
            .frame(maxWidth: .infinity)
            .background(isHovered && !isOpen ? Theme.Color.bgA2 : style.optionFill,
                        in: .rect(cornerRadius: option.radius ?? Theme.Radius.sm))
            .padding(field.padding)
            .frame(width: width, height: style.fieldHeight)
            .background(Theme.Color.bgB2, in: .rect(cornerRadius: field.radius ?? Theme.Radius.md))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
        .opacity(isEnabled ? 1 : Theme.Popup.disabledOpacity)
        .mxrDropdownList(isPresented: $isOpen, selectedRow: selectedRow, style: style) { items }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(selectedTitle)
        .accessibilityHint("Shows the choices")
    }

    @MainActor private var items: [MXRMenuItem] {
        leadingItems() + options.map { option in
            MXRMenuItem(option.title, icon: option.icon, iconTone: .twoTone, isChecked: option.value == selection,
                        isEnabled: option.isEnabled, actions: option.actions) { [binding = $selection] in
                binding.wrappedValue = option.value
            }
        }
    }
}

extension View {
    /// Opens a Figma dropdown list for this view, which acts as the field. The list is as wide as the
    /// field (``MXRDropdownListPlacement``): a standard dropdown drops below the field, which stays
    /// visible (Figma `Dropdown` 2372:8300 and `sub filename` 6456:13892, video 17m31.0); the preset
    /// list (`Setting Preset`, 07m58.9) and pop-up headers (`overField`, Add Subtitles 06m08.5) open
    /// over the field with the row at `selectedRow` on the field's inner row. For custom fields that do
    /// not use ``MXRDropdown`` (dialog header dropdowns, the Shortcuts "All Fields" filter).
    ///
    /// - Parameter fieldInset: space between the field's edge and its inner row (2 pt in Figma).
    /// - Parameter overField: open over the field like a macOS pop-up button instead of below it.
    public func mxrDropdownList(isPresented: Binding<Bool>, selectedRow: Int, style: MXRDropdownStyle = .standard,
                                fieldInset: CGFloat = Theme.Metric.Controls.dropdown.padding.top, overField: Bool = false,
                                @MXRMenuBuilder items: @escaping @MainActor () -> [MXRMenuItem]) -> some View {
        let placement = MXRDropdownListPlacement.placement(style: style, selectedRow: selectedRow,
                                                            fieldInset: fieldInset, overField: overField)
        return modifier(MXRPopupModifier(isPresented: isPresented, placement: placement,
                                         style: style.list, width: nil, matchesAnchorWidth: true, surface: true,
                                         content: { .menu(items) }))
    }
}

/// Where a dropdown list opens relative to its field (S63, D034).
public enum MXRDropdownListPlacement {
    public static func placement(style: MXRDropdownStyle, selectedRow: Int, fieldInset: CGFloat,
                                 overField: Bool) -> MXRPopupPlacement {
        guard style == .preset || overField else { return .below(.leading, gap: Theme.Popup.anchorGap) }
        let list = style.list
        let rowOffset = list.padding.top + CGFloat(max(0, selectedRow)) * (list.row.height + list.rowSpacing) - fieldInset
        return .overField(rowOffset: rowOffset)
    }
}
