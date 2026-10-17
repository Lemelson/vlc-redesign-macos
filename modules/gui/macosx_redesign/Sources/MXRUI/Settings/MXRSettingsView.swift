import AppKit
import MXRCore
import MXRDesign
import SwiftUI

/// Catalog-driven Settings (S48–S63). The presenting root injects `AppModel`.
public struct MXRSettingsView: View {
    @Environment(SettingsModel.self) private var settings
    @Environment(InterfaceModel.self) private var interface
    @Environment(AppearanceModel.self) private var appearance
    @State private var pendingConfirmation: SettingsConfirmation?
    @State private var feedback: SettingsActionFeedback?
    private let categoryID: String?

    public init(categoryID: String? = nil) { self.categoryID = categoryID }

    public var body: some View {
        @Bindable var settings = settings
        GeometryReader { geometry in
            let compact = geometry.size.width < Theme.Metric.Dialogs.settingsContent.width
            let navigationWidth = compact ? compactNavigationWidth : Theme.Metric.Dialogs.settingsNavColumn.width
            let contentWidth = geometry.size.width - navigationWidth
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    SettingsSearch(text: $settings.searchText)
                        .frame(width: min(Theme.Metric.Dialogs.settingsSearch.width, geometry.size.width / 3))
                        .padding(.leading, Theme.Spacing.gap8)
                    Text(settings.showsAllModules ? "VLC Modules"
                         : settings.searchText.isEmpty ? settings.selectedCategory?.title ?? "Settings" : "Search Settings")
                        .mxrTextStyle(Theme.Font.bodyLarge).foregroundStyle(Theme.Color.fgA1)
                        .padding(.leading, Theme.Metric.Dialogs.settingsContent.padding.leading + Theme.Spacing.gap8)
                    Spacer(minLength: 0)
                    Button(action: close) { MXRIcon(.close).frame(width: Theme.Metric.iconButtonHeight, height: Theme.Metric.iconButtonHeight) }
                        .buttonStyle(.plain).accessibilityLabel("Close settings")
                        .padding(.trailing, Theme.Spacing.gap14)
                }
                .frame(height: Theme.Metric.Dialogs.settingsHeader.height)
                .background(Theme.Color.bgB2)
                HStack(alignment: .top, spacing: 0) {
                    navigation(height: geometry.size.height - Theme.Metric.Dialogs.settingsHeader.height, compact: compact)
                    Group {
                        if settings.showsAllModules {
                            SettingsModuleBrowser()
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: Theme.Spacing.gap20) {
                                    if settings.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                                        if let category = settings.selectedCategory {
                                            ForEach(category.basicSections.filter(hasVisibleRows)) { section in sectionView(section) }
                                            let advanced = category.advancedSections.filter(hasVisibleRows)
                                            if !advanced.isEmpty {
                                                advancedBar(category)
                                                if settings.isAdvancedExpanded(category.id) {
                                                    ForEach(advanced) { section in
                                                        sectionView(section, hidesTitle: section.title == "Advanced Options")
                                                    }
                                                }
                                            }
                                        }
                                    } else {
                                        searchResults
                                    }
                                }
                                .padding(Theme.Metric.Dialogs.settingsContent.padding.edgeInsets)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .scrollIndicators(.automatic)
                        }
                    }
                    .frame(width: contentWidth)
                    .environment(
                        \.settingsControlWidth,
                        min(
                            Theme.Metric.SettingsDetail.controlWidth,
                            max(
                                Theme.Metric.buttonWidth,
                                (contentWidth - Theme.Metric.Dialogs.settingsContent.padding.leading
                                    - Theme.Metric.Dialogs.settingsContent.padding.trailing) / 2))
                    )
                    .id(settings.selectedCategoryID)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(idealWidth: Theme.Metric.Dialogs.settings.width, idealHeight: Theme.Metric.Dialogs.settings.height)
        .background { MXRDialogSurface(tint: Theme.Color.bgB1Transparent) }
        .clipShape(.rect(cornerRadius: Theme.Metric.Dialogs.settings.radius ?? Theme.Radius.xxl))
        .mxrAccent(Theme.Accent(appearance.accent))
        .mxrTheme(Theme.Mode(appearance.theme))
        .onAppear {
            if let categoryID, settings.catalog.category(categoryID) != nil { settings.select(categoryID: categoryID) }
        }
        // Device rows on screen are listed fresh on open, on a category or search change and on a hot-plug.
        .task(id: DeviceLoad(kinds: settings.visibleDeviceKinds, generation: settings.deviceGeneration)) {
            await settings.loadDeviceChoices(for: settings.visibleDeviceKinds)
        }
        .onDisappear { settings.saveNow(); settings.showsAllModules = false }
        .environment(\.settingsActionFeedback, feedback)
        .alert(pendingConfirmation?.title ?? "", isPresented: Binding(get: { pendingConfirmation != nil },
                                                                      set: { if !$0 { pendingConfirmation = nil } }),
               presenting: pendingConfirmation) { confirmation in
            Button(confirmation.confirmTitle, role: .destructive) { run(confirmation.row) }
            Button("Cancel", role: .cancel) {}
        } message: { confirmation in
            Text(confirmation.message)
        }
    }

    private func hasVisibleRows(_ section: SettingsSection) -> Bool { !visibleRows(section.rows).isEmpty }

    private func visibleRows(_ rows: [SettingsRow]) -> [SettingsRow] {
        rows.filter { settings.isVisible($0) && SettingsAvailability.isAvailable($0, in: settings) }
    }

    private var compactNavigationWidth: CGFloat {
        Theme.Metric.iconButtonHeight + Theme.Metric.Dialogs.settingsCategoryRow.padding.leading
            + Theme.Metric.Dialogs.settingsCategoryRow.padding.trailing + Theme.Metric.Dialogs.settingsNavCard.padding.leading
            + Theme.Metric.Dialogs.settingsNavCard.padding.trailing + Theme.Metric.Dialogs.settingsNavColumn.padding.leading
            + Theme.Metric.Dialogs.settingsNavColumn.padding.trailing
    }

    private func navigation(height: CGFloat, compact: Bool) -> some View {
        let columnWidth = compact ? compactNavigationWidth : Theme.Metric.Dialogs.settingsNavColumn.width
        let cardWidth = columnWidth - Theme.Metric.Dialogs.settingsNavColumn.padding.leading - Theme.Metric.Dialogs.settingsNavColumn.padding.trailing
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Metric.Dialogs.settingsNavCard.gap) {
                ForEach(settings.groupedCategories, id: \.group) { group, categories in
                    if !compact {
                        Text(group.title).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: Theme.Metric.SettingsDetail.groupHeight)
                            .padding(.leading, Theme.Spacing.gap10)
                    }
                    ForEach(categories) { category in
                        let selected = settings.selectedCategoryID == category.id && settings.searchText.isEmpty && !settings.showsAllModules
                        Button {
                            settings.searchText = ""
                            settings.showsAllModules = false
                            settings.select(categoryID: category.id)
                        } label: {
                            HStack(spacing: Theme.Spacing.gap8) {
                                MXRIcon(icon(category), state: selected ? .active : .default)
                                    .frame(width: Theme.Metric.iconButtonHeight, height: Theme.Metric.iconButtonHeight)
                                if !compact {
                                    Text(category.sidebar).mxrTextStyle(Theme.Font.body)
                                        .foregroundStyle(selected ? Theme.Color.fg1 : Theme.Color.fgA2)
                                    Spacer(minLength: 0)
                                }
                            }
                            .padding(Theme.Metric.Dialogs.settingsCategoryRow.padding.edgeInsets)
                            .frame(height: Theme.Metric.Dialogs.settingsCategoryRow.height)
                            .background {
                                if selected { RoundedRectangle(cornerRadius: Theme.Radius.xs).fill(Theme.Color.bgA1) }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(category.sidebar).help(category.sidebar)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            .padding(Theme.Metric.Dialogs.settingsNavCard.padding.edgeInsets)
        }
        .scrollIndicators(.automatic)
        .frame(
            width: cardWidth,
            height: max(0, height - Theme.Metric.Dialogs.settingsNavColumn.padding.top - Theme.Metric.Dialogs.settingsNavColumn.padding.bottom)
        )
        .background(Theme.Color.bgA3Transparent, in: .rect(cornerRadius: Theme.Radius.lg))
        .padding(Theme.Metric.Dialogs.settingsNavColumn.padding.edgeInsets)
        .frame(width: columnWidth)
        .background(Theme.Color.bgB1Transparent)
    }

    private func icon(_ category: SettingsCategory) -> MXRIcon.Name {
        switch category.id {
        case "general", "performance": .preferences
        case "interface": .interface
        case "privacy": .privacy
        case "controls": .hotkeys
        case "playback": .playback
        case "video": .video
        case "audio": .audio
        case "subtitles": .subtitles
        case "library": .folder
        case "network": .streaming
        case "recording": .record
        default: .plugins
        }
    }

    private func sectionView(_ section: SettingsSection, hidesTitle: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !hidesTitle {
                Text(section.title).mxrTextStyle(Theme.Font.sectionHeader).foregroundStyle(Theme.Color.fg2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Theme.Metric.Dialogs.settingsSectionHeaderRow.height)
            }
            ForEach(visibleRows(section.rows)) { row in
                SettingsRowView(row: row, perform: perform)
            }
        }
    }

    private func advancedBar(_ category: SettingsCategory) -> some View {
        Button { settings.toggleAdvanced(category.id) } label: {
            HStack(spacing: Theme.Spacing.gap10) {
                Text("Advanced Options").mxrTextStyle(Theme.Font.body)
                MXRIcon(settings.isAdvancedExpanded(category.id) ? .chevronDown : .chevronRight)
            }
            .foregroundStyle(Theme.Color.fgA1)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Metric.Dialogs.advancedOptionsBar.height)
            .background(Theme.Color.bgA3Transparent, in: .rect(cornerRadius: Theme.Radius.xs))
        }
        .buttonStyle(.plain)
        .accessibilityValue(settings.isAdvancedExpanded(category.id) ? "Expanded" : "Collapsed")
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.gap20) {
            if settings.searchResults.isEmpty {
                Text("No settings match “\(settings.searchText)”.").mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA1)
            }
            ForEach(settings.searchResults.filter { !visibleRows($0.rows).isEmpty }, id: \.category.id) { category, rows in
                VStack(alignment: .leading, spacing: 0) {
                    Button { settings.select(categoryID: category.id); settings.searchText = "" } label: {
                        Text(category.sidebar).mxrTextStyle(Theme.Font.sectionHeader).foregroundStyle(Theme.Color.fg2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: Theme.Metric.Dialogs.settingsSectionHeaderRow.height)
                    }.buttonStyle(.plain)
                    let advancedIDs = Set(category.advancedSections.flatMap(\.rows).map(\.id))
                    ForEach(visibleRows(rows)) { row in
                        SettingsRowView(row: row, perform: perform, isAdvancedMatch: advancedIDs.contains(row.id))
                    }
                }
            }
        }
    }

    private func perform(_ row: SettingsRow) {
        if let confirmation = SettingsConfirmation(row: row) { pendingConfirmation = confirmation; return }
        run(row)
    }

    /// Runs a button row and shows its result next to the button for a few seconds (SD-16).
    private func run(_ row: SettingsRow) {
        settings.actionMessage = nil
        settings.perform(row)
        guard let text = settings.actionMessage ?? SettingsConfirmation.doneMessage(for: row.action) else { return }
        settings.actionMessage = nil
        let current = SettingsActionFeedback(rowID: row.id, text: text)
        feedback = current
        Task { @MainActor in
            try? await Task.sleep(for: Theme.DialogMotion.feedbackDuration)
            if feedback == current { feedback = nil }
        }
    }

    private func close() {
        settings.saveNow()
        interface.dismissSheet()
    }
}

/// "Show all modules": every engine option, shown in place of the category page (one level, no sheet).
private struct SettingsModuleBrowser: View {
    @Environment(SettingsModel.self) private var settings
    @State private var search = ""

    private var options: [SettingOption] {
        settings.allModuleOptions.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
            || ($0.text?.localizedCaseInsensitiveContains(search) ?? false)
            || ($0.module?.localizedCaseInsensitiveContains(search) ?? false) }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: Theme.Spacing.gap20) {
                HStack {
                    Text("Every option of every VLC module").mxrTextStyle(Theme.Font.sectionHeader).foregroundStyle(Theme.Color.fg2)
                    Spacer(minLength: 0)
                    SettingsButton(title: "Done") {
                        settings.saveNow(); settings.showsAllModules = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
                SettingsSearch(text: $search, placeholder: "Search module options")
                Text("\(options.count) options").mxrTextStyle(Theme.Font.caption).foregroundStyle(Theme.Color.fgA3)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.gap8) {
                        ForEach(options, id: \.name) { option in
                            VStack(alignment: .leading, spacing: 0) {
                                Text([option.module, option.name].compactMap { $0 }.joined(separator: " · "))
                                    .mxrTextStyle(Theme.Font.caption).foregroundStyle(Theme.Color.fgA3)
                                SettingsRowView(row: row(option), perform: settings.perform)
                            }
                        }
                    }
                }
                .scrollIndicators(.automatic)
            }
            .padding(Theme.Metric.Dialogs.settingsContent.padding.edgeInsets)
            .environment(
                \.settingsControlWidth,
                min(
                    Theme.Metric.SettingsDetail.controlWidth,
                    max(Theme.Metric.buttonWidth, (geometry.size.width - Theme.Metric.Dialogs.settingsContent.padding.trailing * 2) / 2)))
        }
    }

    private func row(_ option: SettingOption) -> SettingsRow {
        let control: SettingsControl
        switch option.type {
        case .bool: control = .toggle
        case .integer, .float: control = option.choices.isEmpty ? .number : .dropdown
        case .color: control = .color
        case .key: control = .key
        case .loadFile, .saveFile: control = .file
        case .directory: control = .directory
        default: control = option.choices.isEmpty ? .text : .dropdown
        }
        return SettingsRow(option: option.name, control: control, label: option.text ?? option.name,
                           info: option.longText, choices: option.choices.isEmpty ? nil : option.choices,
                           min: option.range?.lowerBound, max: option.range?.upperBound)
    }
}

private struct SettingsRowView: View {
    let row: SettingsRow
    let perform: (SettingsRow) -> Void
    var isAdvancedMatch = false
    @Environment(SettingsModel.self) private var settings
    @Environment(AppearanceModel.self) private var appearance
    @Environment(TracksModel.self) private var tracks
    @Environment(\.settingsControlWidth) private var controlWidth
    @Environment(\.settingsActionFeedback) private var feedback
    @State private var showsInfo = false
    @State private var equalizerOpen = false

    private var isEnabled: Bool { settings.isEnabled(row) }
    /// The ⓘ text, only when it explains more than the label already says (SD-06).
    private var rowInfo: String? {
        guard let info = settings.info(for: row)?.trimmingCharacters(in: .whitespacesAndNewlines), !info.isEmpty else { return nil }
        let plain = { (text: String) in text.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted) }
        return plain(info) == plain(row.label) ? nil : info
    }
    private var feedbackText: String? { feedback?.rowID == row.id ? feedback?.text : nil }

    var body: some View {
        if row.control == .extensionList {
            SettingsExtensionsView()
        } else if row.control == .equalizer {
            VStack(spacing: 0) {
                if equalizerOpen { SettingsEqualizerView(row: row) { equalizerOpen = false } }
                else { SettingsButton(title: row.buttonTitle ?? "Open Equalizer", width: nil) { equalizerOpen = true } }
            }.padding(.vertical, Theme.Spacing.gap5).disabled(!isEnabled)
        } else {
            HStack(spacing: Theme.Spacing.gap10) {
                HStack(spacing: Theme.Spacing.gap10) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.gap4) {
                        Text(row.label).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA2)
                            .fixedSize(horizontal: false, vertical: true)
                        if isAdvancedMatch {
                            Text("Advanced").mxrTextStyle(Theme.Font.caption).foregroundStyle(Theme.Color.fgA3)
                        }
                        if settings.needsRestart(row) && feedbackText == nil {
                            Text("Takes effect after restarting VLC.").mxrTextStyle(Theme.Font.caption).foregroundStyle(Theme.Color.fgA3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let feedbackText {
                            Text(feedbackText).mxrTextStyle(Theme.Font.caption).foregroundStyle(Theme.Color.accentMain)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity)
                                .accessibilityAddTraits(.updatesFrequently)
                        }
                    }
                    if let info = rowInfo {
                        Button { showsInfo.toggle() } label: {
                            MXRIcon(.info, size: Theme.Metric.SettingsDetail.infoSize, tint: Theme.Color.fgA4)
                        }
                        .buttonStyle(.plain).accessibilityLabel("Information about \(row.label)")
                        .mxrPopup(isPresented: $showsInfo, surface: .contextMenu) {
                            VStack(alignment: .leading, spacing: Theme.Spacing.gap10) {
                                Text(row.label).mxrTextStyle(Theme.Font.sectionHeader).foregroundStyle(Theme.Color.fg2)
                                Text(info).mxrTextStyle(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                                if row.apply == .restart { Text("Takes effect after restarting VLC.").mxrTextStyle(Theme.Font.caption) }
                            }
                            .foregroundStyle(Theme.Color.fgA1).padding(Theme.Spacing.gap20)
                            .frame(width: Theme.Metric.SettingsDetail.controlWidth)
                        }
                    }
                    Spacer(minLength: 0)
                }
                controlFrame
                    .disabled(!isEnabled)
                    .accessibilityLabel(row.label)
            }
            .padding(.vertical, row.control == .stackedChoice ? Theme.Spacing.gap10 : Theme.Spacing.gap5)
            .frame(minHeight: minimumRowHeight)
            .compositingGroup()
            // 6542:15562/6542:15575: a disabled row (its dependency is off) dims as a whole, once.
            .opacity(isEnabled ? 1 : Theme.Metric.SettingsDetail.disabledRowOpacity)
            .animation(.easeOut(duration: 0.15), value: feedbackText)
        }
    }

    @ViewBuilder private var controlFrame: some View {
        switch row.control {
        case .toggle: control.frame(width: Theme.Metric.Controls.toggle.width)
        // The stacked choice keeps "Always starts at:" on one line: in a narrow window it may grow past
        // the half-width column, up to its design width, and the label beside it wraps instead.
        case .stackedChoice:
            control.frame(minWidth: controlWidth, maxWidth: max(controlWidth, Theme.Metric.SettingsDetail.controlWidth))
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        default: control.frame(width: controlWidth)
        }
    }

    private var minimumRowHeight: CGFloat {
        switch row.control {
        case .toggle, .button, .color: Theme.Metric.Dialogs.settingsRow.height
        case .number:
            // 3072:13821/3072:13833 track-number rows use the 46-point dropdown row height.
            ["audio-track", "video-track", "sub-track"].contains(row.option ?? "") ? Theme.Metric.Dialogs.settingsRowTall.height : Theme.Metric.SettingsDetail.inputRowHeight
        // Figma draws text rows 48 points (3180:18098) or 46 (3046:9521, 3062:12466); the catalog
        // names the 46-point ones.
        case .text: row.rowHeight.map { CGFloat($0) } ?? Theme.Metric.SettingsDetail.inputRowHeight
        case .directory: Theme.Metric.SettingsDetail.inputRowHeight
        // 3191:18686 uses a 38-point inner wrapper for the subtitle size segment.
        case .segmented: row.option == AppearanceModel.themeOption ? Theme.Metric.Dialogs.settingsRowTall.height : Theme.Metric.SettingsDetail.inputRowHeight
        case .slider:
            (row.scaleLabels?.isEmpty ?? true) ? Theme.Metric.Dialogs.settingsRow.height
                : Theme.Metric.SettingsDetail.sliderHeight + (compactSliderScale ? 0 : Theme.Spacing.gap10)
        case .stackedChoice: Theme.Metric.SettingsDetail.stackedRowHeight
        default: Theme.Metric.Dialogs.settingsRowTall.height
        }
    }

    private var compactSliderScale: Bool {
        // 3056:10875 timeout sliders omit the outer track wrapper and use an eight-point gap.
        row.option == "macosx-redesign-autohide-delay" || row.option == "macosx-redesign-notification-duration"
    }

    private var buttonWidth: CGFloat {
        // 3062:12486 and 3073:14906 use the standard 100-point action button.
        // Shortcut and maintenance launchers use the full value-column width (6540:15094, 6571:16316).
        switch row.action {
        case "open-config-folder", "open-extensions-folder", "reset-all-settings", "clear-history", "reset-picture": min(Theme.Metric.buttonWidth, controlWidth)
        default: controlWidth
        }
    }

    @ViewBuilder private var control: some View {
        switch row.control {
        case .toggle:
            SettingsToggle(isOn: Binding(get: { settings.bool(row) }, set: { settings.setValue(.bool($0), for: row) }), label: row.label)
        case .dropdown:
            SettingsChoiceMenu(title: SettingsChoices.title(for: row, in: settings), choices: SettingsChoices.all(for: row, in: settings),
                               selected: SettingsChoices.selection(for: row, in: settings)) { choice in
                if row.composite != nil, let index = choice.value.intValue { settings.selectComposite(index, for: row) }
                else { select(choice) }
            }
        case .segmented:
            let choices = settings.choices(for: row)
            SettingsSegmentedControl(choices: choices.map { ($0.value, $0.title) },
                                     selection: choices.first { settings.value(for: row)?.isEquivalent(to: $0.value) ?? false }?.value,
                                     select: { value in
                if row.option == AppearanceModel.themeOption, let raw = value.stringValue, let theme = ThemePreference(rawValue: raw) { appearance.setTheme(theme) }
                else { settings.setValue(value, for: row) }
            }, label: row.label)
        case .swatches:
            HStack(spacing: Theme.Spacing.gap4) {
                ForEach(AccentChoice.allCases, id: \.self) { accent in
                    Button { appearance.setAccent(accent) } label: {
                        RoundedRectangle(cornerRadius: Theme.Radius.xs).fill(Theme.Accent(accent).swatch.color)
                            .opacity(appearance.accent == accent ? 1 : Theme.Metric.SettingsDetail.inactiveSwatchOpacity)
                            .frame(width: Theme.Metric.SettingsDetail.swatchSize, height: Theme.Metric.SettingsDetail.swatchSize)
                            .frame(maxWidth: .infinity).frame(height: Theme.Metric.SettingsDetail.controlInnerHeight)
                            .background(appearance.accent == accent ? Theme.Color.bgAccentBright : Theme.Color.bgB2,
                                        in: .rect(cornerRadius: Theme.Radius.md))
                    }.buttonStyle(.plain).accessibilityLabel("\(accent.rawValue.capitalized) accent")
                        .accessibilityAddTraits(appearance.accent == accent ? .isSelected : [])
                }
            }.padding(Theme.Spacing.gap2).background(Theme.Color.bgB2, in: .rect(cornerRadius: Theme.Radius.lg))
        case .text, .number, .color:
            SettingsTextEditor(row: row)
        case .file, .directory:
            HStack(spacing: Theme.Spacing.gap10) {
                SettingsTextEditor(row: row)
                SettingsButton(title: row.buttonTitle ?? "Browse") { browse() }
            }
        case .button:
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                SettingsButton(title: row.buttonTitle ?? row.label, width: buttonWidth) { perform(row) }
            }
        case .slider:
            SettingsSlider(value: Binding(get: { settings.double(row) }, set: {
                settings.setValue(SettingsValueEditing.slider($0, current: settings.value(for: row), step: row.step ?? 1,
                                                             isFloat: settings.backend.option(named: row.option ?? "")?.type == .float), for: row)
            }),
                           range: (row.min ?? 0)...(row.max ?? 100), step: row.step ?? 1, ticks: row.ticks, labels: row.scaleLabels ?? [],
                           compactScale: compactSliderScale, label: row.label)
        case .stackedChoice:
            VStack(spacing: Theme.Spacing.gap2) {
                ForEach(Array(settings.choices(for: row).enumerated()), id: \.offset) { index, choice in
                    let selected = settings.value(for: row)?.isEquivalent(to: choice.value) ?? false
                    HStack(spacing: Theme.Spacing.gap10) {
                        Button { settings.setValue(choice.value, for: row) } label: {
                            HStack {
                                Text(choice.title).mxrTextStyle(Theme.Font.body).lineLimit(1).fixedSize()
                                Spacer(minLength: 0)
                            }
                        }.buttonStyle(.plain)
                        if index == 1 {
                            SettingsSecondaryValueEditor(row: row, isSelected: selected)
                        }
                    }
                    .foregroundStyle(selected ? AnyShapeStyle(MXRAccentLabel()) : AnyShapeStyle(Theme.Color.fgA3))
                    .padding(.leading, Theme.Spacing.gap12)
                    .padding(.trailing, index == 1 ? Theme.Spacing.gap2 : Theme.Spacing.gap12)
                    .frame(minHeight: Theme.Metric.Controls.stackedChoiceRow.height)
                    .background(selected ? Theme.Color.bgAccentBright : Theme.Color.bgA4, in: .rect(cornerRadius: Theme.Radius.md))
                }
            }.padding(Theme.Spacing.gap2).background(Theme.Color.bgB2, in: .rect(cornerRadius: Theme.Radius.lg))
        case .key:
            SettingsKeyValueField(row: row)
        case .equalizer, .extensionList:
            EmptyView()
        }
    }

    private func select(_ choice: SettingChoice) {
        settings.setValue(choice.value, for: row)
        // The output device also switches the running output, as the audio button does.
        if row.choiceSource == "audio-devices", let id = choice.value.stringValue,
           let device = tracks.audioDevices.first(where: { $0.id == (id.isEmpty ? "0" : id) }) {
            tracks.selectAudioDevice(device)
        }
    }

    private func browse() {
        if settings.backend.option(named: row.option ?? "")?.type == .saveFile {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = URL(fileURLWithPath: settings.string(row)).lastPathComponent
            if panel.runModal() == .OK, let url = panel.url { settings.setValue(.string(url.path), for: row) }
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = row.control == .directory
        panel.canChooseFiles = row.control == .file
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { settings.setValue(.string(url.path), for: row) }
    }
}

/// Destructive maintenance actions ask first (HIG; SD-16).
struct SettingsConfirmation: Identifiable {
    let row: SettingsRow
    let title: String
    let message: String
    let confirmTitle: String
    var id: String { row.id }

    init?(row: SettingsRow) {
        self.row = row
        switch row.action {
        case "reset-all-settings":
            title = "Reset All Settings?"
            message = "Every setting, including keyboard shortcuts, returns to its default. Your library, playlists and profiles are kept."
            confirmTitle = "Reset"
        case "reset-shortcuts":
            title = "Reset All Keyboard Shortcuts?"
            message = "Every action gets VLC's default key back. Changes you made to shortcuts are lost."
            confirmTitle = "Reset"
        case "clear-history":
            title = "Clear History?"
            message = "Recently played items and saved playback positions are removed. This can't be undone."
            confirmTitle = "Clear History"
        default: return nil
        }
    }

    /// The result shown beside a button whose action reports nothing itself.
    static func doneMessage(for action: String?) -> String? {
        switch action {
        case "reset-shortcuts": "Keyboard shortcuts restored."
        case "clear-history": "History cleared."
        case "reset-picture": "Picture restored."
        default: nil
        }
    }
}

/// A transient result shown under the label of the row whose button ran.
struct SettingsActionFeedback: Equatable {
    let id = UUID()
    let rowID: String
    let text: String
}

private struct SettingsActionFeedbackKey: EnvironmentKey {
    static let defaultValue: SettingsActionFeedback? = nil
}

extension EnvironmentValues {
    var settingsActionFeedback: SettingsActionFeedback? {
        get { self[SettingsActionFeedbackKey.self] }
        set { self[SettingsActionFeedbackKey.self] = newValue }
    }
}

private struct DeviceLoad: Equatable {
    let kinds: Set<MediaDeviceKind>
    let generation: Int
}
