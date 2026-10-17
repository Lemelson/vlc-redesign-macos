import AppKit
import MXRCore
import MXRDesign
import SwiftUI

/// The groups named in S18 (1065:3956, 1065:3964, 1065:3972). Their detailed controls
/// are not drawn in Figma, so each group discovers actual VLC option metadata.
enum VideoFilterGroup: String, CaseIterable, Identifiable {
    case geometry, overlay, advanced
    var id: String { rawValue }
    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    private var modules: [String] {
        switch self {
        case .geometry: ["transform", "rotate", "magnify", "puzzle", "wall", "croppadd"]
        case .overlay: ["marq", "logo", "erase", "mosaic"]
        case .advanced: ["clone", "anaglyph", "motionblur", "postproc", "wave", "ripple", "ball", "motiondetect", "psychedelic", "oldmovie"]
        }
    }
    static func group(for option: SettingOption) -> Self? {
        if ["video-filter", "video-splitter", "sub-source", "sub-filter"].contains(option.name) { return .advanced }
        return allCases.first { group in
            group.modules.contains { module in option.module == module || option.name.hasPrefix(module + "-") }
        }
    }
}

enum VideoFilterOption {
    static func value(from text: String, option: SettingOption) -> SettingValue? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch option.type {
        case .integer:
            guard var number = Int(trimmed) else { return nil }
            if let range = option.range {
                if Double(number) < range.lowerBound {
                    guard let lower = Int(exactly: range.lowerBound.rounded(.up)) else { return nil }
                    number = lower
                }
                if Double(number) > range.upperBound {
                    guard let upper = Int(exactly: range.upperBound.rounded(.down)) else { return nil }
                    number = upper
                }
            }
            return .integer(number)
        case .float:
            guard let number = Double(trimmed), number.isFinite else { return nil }
            return .float(option.range.map { min(max(number, $0.lowerBound), $0.upperBound) } ?? number)
        case .color:
            guard let color = MXRCore.RGBColor(hex: trimmed) else { return nil }
            return .integer(color.vlcValue)
        case .bool:
            switch trimmed.lowercased() { case "true", "1": return .bool(true); case "false", "0": return .bool(false); default: return nil }
        default: return .string(text)
        }
    }

    static func row(_ option: SettingOption, catalog: SettingsCatalog) -> SettingsRow {
        if let row = catalog.allRows.first(where: { $0.option == option.name }) { return row }
        let control: SettingsControl = if option.type == .bool { .toggle }
        else if !option.choices.isEmpty { .dropdown }
        else { switch option.type { case .integer, .float: .number; case .color: .color; case .loadFile, .saveFile: .file; case .directory: .directory; default: .text } }
        return SettingsRow(option: option.name, control: control, label: option.text.flatMap { $0.isEmpty ? nil : $0 } ?? option.name,
                           info: option.longText, min: option.range?.lowerBound, max: option.range?.upperBound,
                           step: option.type == .integer ? 1 : nil, apply: .nextMedia)
    }
}

/// Additional S18 groups built from available VLC configuration metadata.
public struct MXRVideoFilterOptionsView: View {
    public let expanded: Bool
    public init(expanded: Bool = false) { self.expanded = expanded }
    public var body: some View {
        VStack(spacing: 0) {
            ForEach(VideoFilterGroup.allCases) { group in VideoFilterInspector(group: group, expanded: expanded) }
        }
    }
}

/// Uses SettingsModel for reads/writes; only schema discovery reads the public SettingsBackend.
struct VideoFilterInspector: View {
    let group: VideoFilterGroup
    var expanded = false
    @Environment(SettingsModel.self) private var settings
    private var options: [SettingOption] {
        _ = settings.revision
        return settings.backend.allOptionNames.compactMap { settings.backend.option(named: $0) }
            .filter { VideoFilterGroup.group(for: $0) == group && settings.backend.value(for: $0.name) != nil }
            .sorted { ($0.module ?? "", $0.name) < ($1.module ?? "", $1.name) }
    }
    var body: some View {
        if !options.isEmpty {
            VStack(spacing: Theme.Spacing.gap10) {
                Text(group.title).foregroundStyle(Theme.Color.fgA3).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, PanelSpace.xs).frame(height: PanelMetric.cardTitleHeight) // 1065:3958, 1065:3966, 1065:3974
                PanelExpand(title: group.title, expanded: expanded) {
                    // Inside the open card like the designed cards' rows (536:1541: 16 pt insets).
                    VStack(spacing: PanelSpace.md) {
                        Text("Filter configuration applies when media opens.").mxrTextStyle(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.fgA3).frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(options, id: \.name) { option in
                            VideoFilterOptionRow(option: option, row: VideoFilterOption.row(option, catalog: settings.catalog))
                                .id(option.name)
                        }
                    }
                    .padding(.horizontal, PanelSpace.lg)
                }
            }
            .padding(.horizontal, PanelSpace.xl).padding(.top, Theme.Spacing.gap10).padding(.bottom, PanelSpace.xl)
            .overlay(alignment: .bottom) { PanelDivider(consumesHeight: false) }
        }
    }
}

private struct VideoFilterOptionRow: View {
    let option: SettingOption
    let row: SettingsRow
    @Environment(SettingsModel.self) private var settings
    @State private var validationMessage: String?
    var body: some View {
        VStack(spacing: PanelMetric.settingsRowGap) {
            if option.type == .bool {
                PanelToggleRow(title: row.label, isOn: Binding(get: { settings.bool(row) }, set: { settings.setValue(.bool($0), for: row) }))
            } else if !settings.choices(for: row).isEmpty {
                PanelDropdownRow(title: row.label, selected: settings.selectedChoiceTitle(for: row) ?? settings.string(row), choices: settings.choices(for: row).map { choice in
                    PanelChoice(id: choice.value.description, title: choice.title) { settings.setValue(choice.value, for: row) }
                })
            } else if option.type == .color {
                PanelColorField(title: row.label, color: Binding(get: { MXRCore.RGBColor(vlcValue: settings.value(for: row)?.intValue ?? 0) }, set: { settings.setValue(.integer($0.vlcValue), for: row) }))
            } else {
                PanelFieldRow(title: row.label, value: settings.string(row), commit: commit)
                if let range = option.range, range.lowerBound.isFinite, range.upperBound.isFinite, range.lowerBound < range.upperBound,
                   option.type == .integer || option.type == .float {
                    PanelSlider(title: row.label, value: Binding(get: { settings.double(row) }, set: { number in
                        if let value = VideoFilterOption.value(from: option.type == .integer ? String(format: "%.0f", number) : String(number), option: option) { settings.setValue(value, for: row) }
                    }), range: range, step: option.type == .integer ? 1 : 0.01)
                }
                if [.loadFile, .saveFile, .directory].contains(option.type) {
                    Button("Browse…", action: browse).buttonStyle(.plain).foregroundStyle(Theme.Color.fgA2)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            if let validationMessage { Text(validationMessage).mxrTextStyle(Theme.Font.caption).foregroundStyle(Theme.Color.accentMain) }
        }
        .help(settings.info(for: row) ?? option.name)
        .disabled(!settings.isEnabled(row))
    }
    private func commit(_ text: String) {
        guard let value = VideoFilterOption.value(from: text, option: option) else {
            validationMessage = option.type == .integer ? "Enter a whole number." : "Enter a valid value."
            return
        }
        validationMessage = nil
        settings.setValue(value, for: row)
    }
    private func browse() {
        if option.type == .saveFile {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = URL(fileURLWithPath: settings.string(row)).lastPathComponent
            if panel.runModal() == .OK, let url = panel.url { settings.setValue(.string(url.path), for: row) }
        } else {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = option.type == .directory
            panel.canChooseFiles = option.type != .directory
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url { settings.setValue(.string(url.path), for: row) }
        }
    }
}
