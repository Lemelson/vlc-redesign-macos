import AppKit
import MXRCore
import MXRDesign
import SwiftUI
import UniformTypeIdentifiers

public enum MXROnboardingStep: Int, Sendable { case welcome, appearance, shortcuts }

private typealias O = Theme.Metric.Onboarding

/// S69–S71: an optional folder, live appearance choices, and the user's current key bindings.
///
/// Every choice applies when it is made: the folder is added on Next, theme and accent change live.
/// Closing onboarding at any step (Esc, ⌘W, Finish) therefore keeps everything chosen so far;
/// Esc on the welcome step skips onboarding without adding a folder.
public struct MXROnboardingView: View {
    @Environment(AppModel.self) private var app
    @State private var step: MXROnboardingStep
    /// Pre-filled with the Mac's own video folder (~/Movies), so Next really adds it (SD-13).
    @State private var folderPath = MXROnboardingFolder.suggestedPath
    @State private var folderError: String?
    @State private var isBrowsing = false
    /// The folder Next already added, so Back then Next does not add it twice.
    @State private var addedFolder: URL?
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    public init(initialStep: MXROnboardingStep = .welcome) { _step = State(initialValue: initialStep) }
    public static var preferredSize: CGSize { Theme.Metric.Dialogs.onboarding.size }

    public var body: some View {
        // Stacks with the Figma gaps; the footer stays pinned at its Figma insets and the step
        // scrolls when the window is shorter than the 1090×759 frame.
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                Group {
                    switch step {
                    case .welcome: welcome
                    case .appearance: appearance
                    case .shortcuts: shortcuts
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
        .frame(maxWidth: Self.preferredSize.width, maxHeight: Self.preferredSize.height)
        .background(Theme.Color.bgB1)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.Dialogs.onboarding.radius ?? Theme.Radius.lg))
        .compositingGroup()
        .mxrShadow(Theme.Effect.onboardingShadow)
        .mxrTheme(Theme.Mode(app.appearance.theme))
        .mxrAccent(Theme.Accent(app.appearance.accent))
        .fileImporter(isPresented: $isBrowsing, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                folderPath = url.path
                folderError = nil
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { folderError = error.localizedDescription }
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            MXRIcon(.vlc, size: O.logo.width)
                .frame(width: O.logo.width, height: O.logo.height)
                .padding(.top, O.logoTop)
            Text("Welcome to VLC!")
                .mxrTextStyle(.welcomeTitle).foregroundStyle(Theme.Color.fg1)
                .frame(height: O.welcomeTitle.height)
                .padding(.top, O.welcomeTitleGapAbove)
            Text("VLC is a free and open source cross-platform multimedia player and framework that plays most multimedia files as well as DVDs, Audio CDs, VCDs, and various streaming protocols.")
                .mxrTextStyle(.onboardingBody).foregroundStyle(Theme.Color.fgA1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: O.paragraph.width, height: O.paragraph.height, alignment: .topLeading)
                .padding(.top, O.paragraphGapAbove)
            Text("Choose a Media Folder to get started with")
                .mxrTextStyle(.body).foregroundStyle(Theme.Color.fgA1)
                .frame(width: O.folderLabel.width, height: O.folderLabel.height, alignment: .leading)
                .padding(.top, O.folderLabelGapAbove)
            HStack(spacing: O.folderInput.gap) {
                folderField
                Button("Browse") { isBrowsing = true }
                    .buttonStyle(.plain)
                    .mxrTextStyle(.bodyLarge)
                    .foregroundStyle(Theme.Color.fgA1)
                    .frame(width: O.browse.width, height: O.browse.height)
                    .background(Theme.Color.bgA3, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
            }
            .frame(width: O.paragraph.width, alignment: .leading)
            .padding(.top, O.folderInputGapAbove)
            if let folderHint {
                Text(folderHint).mxrTextStyle(.caption).foregroundStyle(folderError == nil ? Theme.Color.fgA3 : Theme.Color.accentMain)
                    .frame(width: O.paragraph.width, alignment: .leading)
                    .padding(.top, Theme.Spacing.gap8)
                    .accessibilityLabel(folderError.map { "Folder error: \($0)" } ?? folderHint)
            }
        }
    }

    private var folderField: some View {
        TextField("", text: $folderPath)
            .textFieldStyle(.plain)
            .font(Theme.Font.bodyLarge.font)
            .foregroundStyle(Theme.Color.fg1)
            .padding(.horizontal, Theme.Spacing.gap16)
            // An empty field shows its hint in the placeholder color, never as a value.
            .overlay(alignment: .leading) {
                if folderPath.isEmpty {
                    Text("No folder").font(Theme.Font.bodyLarge.font).foregroundStyle(Theme.Color.fgA4)
                        .padding(.horizontal, Theme.Spacing.gap16).allowsHitTesting(false)
                }
            }
            .frame(width: O.folderInput.width, height: O.folderInput.height)
            .background(Theme.Color.bgB2, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .strokeBorder(Theme.Color.bgA3, lineWidth: Theme.Stroke.iconActive))
            .accessibilityLabel("Media folder path")
    }

    private var folderHint: String? {
        if let folderError { return folderError }
        return folderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No folder will be added. You can add folders to the library at any time." : nil
    }

    private var appearance: some View {
        MXROnboardingPlayerPreview()
            .frame(width: O.preview.width, height: O.preview.height)
            .overlay(alignment: .top) {
                VStack(spacing: O.themesGapAbove) {
                    Text("Select your preferred theme and color.")
                        .mxrTextStyle(.onboardingTitle).foregroundStyle(Theme.Color.fgA1)
                        .frame(height: O.appearanceTitle.height)
                    HStack(spacing: O.themes.gap) {
                        ForEach([ThemePreference.light, .dark, .system], id: \.self) { theme in
                            themeTile(theme)
                        }
                    }
                    .frame(width: O.themes.width, height: O.themes.height)
                }
                .padding(.top, O.appearanceTitleTop - O.previewTop)
            }
            .padding(.top, O.previewTop)
            .padding(.horizontal, O.previewLeading)
    }

    private var swatches: some View {
        HStack(spacing: O.swatches.gap) {
            ForEach(AccentChoice.allCases, id: \.self) { choice in
                accentSwatch(choice)
            }
        }
    }

    private func themeTile(_ theme: ThemePreference) -> some View {
        let box = Theme.Metric.Dialogs.themeTile
        let selected = app.appearance.theme == theme
        return Button { app.appearance.setTheme(theme) } label: {
            VStack(spacing: O.themesLabelGap) {
                RoundedRectangle(cornerRadius: O.themesFillRadius)
                    .fill(themeFill(theme))
                    .padding(box.padding.edgeInsets)
                    .frame(width: box.width, height: box.height)
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: box.radius ?? Theme.Radius.lg)
                                .inset(by: -O.themesRing / 2)
                                .stroke(Theme.Color.accentMain, lineWidth: O.themesRing)
                        }
                    }
                Text(theme.title).mxrTextStyle(.onboardingTileLabel).foregroundStyle(Theme.Color.fgA1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.title) theme")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func themeFill(_ theme: ThemePreference) -> AnyShapeStyle {
        let stops = Theme.Gradient.onboardingSystemTile
        switch theme {
        case .light: return AnyShapeStyle(stops[0].color.color)
        case .dark: return AnyShapeStyle(stops[1].color.color)
        case .system:
            return AnyShapeStyle(LinearGradient(stops: stops.map { .init(color: $0.color.color, location: $0.location) },
                startPoint: UnitPoint(x: O.systemGradientStartX, y: O.systemGradientStartY),
                endPoint: UnitPoint(x: O.systemGradientEndX, y: O.systemGradientEndY)))
        }
    }

    private func accentSwatch(_ choice: AccentChoice) -> some View {
        let box = Theme.Metric.Dialogs.colorDot
        let selected = app.appearance.accent == choice
        return Button { app.appearance.setAccent(choice) } label: {
            // The accent's main colour in the shown theme, as the Next button and the preview use it
            // (D049): in Light the swatches are the Light accents, not the dark swatch hexes.
            Circle().fill(Theme.Color.accentMain)
                .environment(\.mxrAccent, Theme.Accent(choice))
                .opacity(selected ? 1 : O.swatchesUnselectedOpacity)
                .padding(O.swatchesInset)
                .frame(width: box.width, height: box.height)
                .overlay {
                    if selected {
                        Circle().strokeBorder(Theme.Color.accentRing, lineWidth: O.themesRing)
                        // Differentiate Without Color: the selection must not rely on the ring hue alone.
                        if differentiateWithoutColor {
                            MXRIcon(.check, state: .selected, size: box.width - 2 * O.swatchesInset,
                                    tint: Theme.Color.fgB1)
                        }
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(choice.rawValue.capitalized) accent")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: O.shortcutColumnsGapAbove) {
            Text("Learn the basic keyboard shortcuts.")
                .mxrTextStyle(.onboardingTitleRegular).foregroundStyle(Theme.Color.fgA1)
                .frame(height: O.shortcutTitle.height)
                .frame(maxWidth: .infinity)
            HStack(alignment: .top, spacing: O.shortcutColumns.gap) {
                shortcutColumn(Array(MXROnboardingShortcut.rows.prefix(6)))
                shortcutColumn(Array(MXROnboardingShortcut.rows.suffix(6)))
            }
            .padding(.leading, O.shortcutColumnsLeading)
        }
        .padding(.top, O.shortcutTitleTop)
    }

    private var shortcutHint: some View {
        // 1904:7211: the 28 pt text box shares the buttons' top edge (671), it is not centred on them.
        Text("Find the full list in the menu.")
            .mxrTextStyle(.onboardingBody).foregroundStyle(Theme.Color.fgA3)
            .frame(height: Theme.Metric.Dialogs.onboardingButton.height, alignment: .top)
    }

    private func shortcutColumn(_ rows: [MXROnboardingShortcut]) -> some View {
        VStack(alignment: .leading, spacing: O.shortcutColumnsRowGap) {
            ForEach(rows) { row in
                HStack(spacing: O.shortcutColumnsLabelGap) {
                    Text(row.title).mxrTextStyle(.onboardingBody).foregroundStyle(Theme.Color.fgA1)
                        .frame(width: O.shortcutColumnsLabelWidth, alignment: .leading)
                    HStack(spacing: O.keycapBindingGap) {
                        let bindings = row.bindings(in: app.shortcuts)
                        ForEach(Array(bindings.enumerated()), id: \.offset) { index, binding in
                            if index > 0 {
                                Text("/").mxrTextStyle(.onboardingBody).foregroundStyle(Theme.Color.fgA3).fixedSize()
                            }
                            keycaps(binding, compact: bindings.count > 1)
                        }
                        if bindings.isEmpty {
                            Text("—").mxrTextStyle(.onboardingBody).foregroundStyle(Theme.Color.fgA3)
                        }
                    }
                    // Wider Mac bindings (⌥⌘← / ⌥⌘→) run past the column into its trailing space rather
                    // than squeezing their keycaps.
                    .fixedSize()
                }
                .frame(height: O.shortcutColumnsRowHeight)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(width: O.shortcutColumnsColumnWidth, alignment: .leading)
    }

    private func keycaps(_ binding: KeyBinding, compact: Bool) -> some View {
        let caps = binding.onboardingKeycaps(pairedWithAnother: compact)
        let inset = compact || caps.count > 2 ? O.keycapCompactInset : O.keycapHorizontalInset
        return HStack(spacing: O.keycapModifierGap) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, key in
                // A keycap never truncates its glyphs (the Mac defaults are wider than Figma's keys).
                Text(key).mxrTextStyle(.onboardingBody).foregroundStyle(Theme.Color.fg1)
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, inset + O.keycapStroke)
                    .frame(minHeight: O.shortcutColumnsRowHeight)
                    .background(Theme.Color.bgA3, in: RoundedRectangle(cornerRadius: O.keycapRadius))
                    .overlay(RoundedRectangle(cornerRadius: O.keycapRadius)
                        .strokeBorder(Theme.Color.dividerBright, lineWidth: O.keycapStroke))
                    .compositingGroup()
                    .customizationShadow(Theme.Effect.keycapShadow,
                                         cornerRadius: O.keycapRadius)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: O.footerGap) {
            switch step {
            case .welcome: EmptyView()
            case .appearance: swatches
            case .shortcuts: shortcutHint
            }
            Spacer(minLength: 0)
            if step != .welcome {
                MXROnboardingButton(title: "Back", primary: false) {
                    step = step == .shortcuts ? .appearance : .welcome
                }
            }
            MXROnboardingButton(title: step == .shortcuts ? "Finish" : "Next", primary: true) {
                switch step {
                case .welcome:
                    // The folder is added as soon as it is accepted, so closing onboarding later (Esc,
                    // ⌘W, Finish) never loses it (LIBSET-09). Back does not remove it.
                    do {
                        addedFolder = try MXROnboardingFolder.accept(folderPath, alreadyAdded: addedFolder) {
                            app.library.addFolder($0)
                        }
                        folderError = nil
                        step = .appearance
                    } catch { folderError = error.localizedDescription }
                case .appearance: step = .shortcuts
                case .shortcuts:
                    app.completeOnboarding()
                }
            }
        }
        .frame(height: O.footerHeight)
        .padding(.leading, step == .appearance ? O.footerSwatchesLeading : O.footerLeading)
        .padding(.trailing, O.footerTrailing)
        .padding(.bottom, O.footerBottom)
    }
}

private struct MXROnboardingButton: View {
    let title: String
    let primary: Bool
    let action: () -> Void

    var body: some View {
        let box = Theme.Metric.Dialogs.onboardingButton
        Button(action: action) {
            Text(title).mxrTextStyle(.buttonLarge)
                .foregroundStyle(primary ? Theme.Color.fgB1 : Theme.Color.fgA1)
                .frame(width: box.width, height: box.height)
                .background(primary ? Theme.Color.accentMain : Theme.Color.bgA3,
                            in: RoundedRectangle(cornerRadius: box.radius ?? Theme.Radius.lg))
        }
        .buttonStyle(.plain)
    }
}

enum MXROnboardingFolder {
    /// The Mac's video folder, written with a tilde as the design shows it; empty when it is missing.
    static var suggestedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for name in ["Movies", "Videos"] {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: home.appendingPathComponent(name).path, isDirectory: &isDirectory), isDirectory.boolValue {
                return "~/" + name
            }
        }
        return ""
    }

    static func url(for input: String) throws -> URL? {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        let path = (input as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { throw FolderError.notDirectory }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Next on the welcome step: validates the path and adds the folder to the library right away
    /// (unless it is the one already added). Returns the folder now in the library, or nil when the
    /// path is empty (onboarding continues without a folder). Throws for a path that is not a folder.
    static func accept(_ input: String, alreadyAdded: URL?, add: (URL) -> Void) throws -> URL? {
        guard let folder = try url(for: input) else { return alreadyAdded }
        if folder != alreadyAdded { add(folder) }
        return folder
    }

    enum FolderError: LocalizedError {
        case notDirectory
        var errorDescription: String? { "Choose an existing media folder, or leave the path empty to continue." }
    }
}

struct MXROnboardingShortcut: Identifiable {
    let title: String
    let actionIDs: [String]
    var id: String { actionIDs.joined(separator: "/") }

    @MainActor func bindings(in model: ShortcutsModel) -> [KeyBinding] {
        actionIDs.compactMap { model.primaryBinding(for: $0) }
    }

    static let rows = [
        Self(title: "Play / Pause", actionIDs: ["play-pause"]),
        Self(title: "Seek Backward / Forward", actionIDs: ["jump-short", "jump+short"]),
        Self(title: "Previous / Next Item", actionIDs: ["prev", "next"]),
        Self(title: "Previous / Next Frame", actionIDs: ["frame-previous", "frame-next"]),
        Self(title: "Cycle Subtitle Track", actionIDs: ["subtitle-track"]),
        Self(title: "Cycle Audio Track", actionIDs: ["audio-track"]),
        Self(title: "Toggle Fullscreen", actionIDs: ["toggle-fullscreen"]),
        Self(title: "Increase / Decrease Volume", actionIDs: ["vol-up", "vol-down"]),
        Self(title: "Show / Hide Queue", actionIDs: ["app-toggle-queue"]),
        Self(title: "Show / Hide File Browser", actionIDs: ["app-toggle-library"]),
        Self(title: "Take a Snapshot", actionIDs: ["snapshot"]),
        Self(title: "Record", actionIDs: ["record"]),
    ]
}

extension KeyBinding {
    /// Onboarding keycaps (S71, D026): Mac glyphs in the Mac order ⌃ ⌥ ⇧ ⌘. A row's only binding
    /// shows one keycap per key, as Figma 1902:6770 does ("⌘" "L"); when two bindings share a row
    /// (Previous / Next) each binding is one keycap ("⌥⌘←"), the way Mac menus write a shortcut, so
    /// VLC's macOS defaults (⌥⌘← / ⌥⌘→) fit the row.
    func onboardingKeycaps(pairedWithAnother: Bool) -> [String] {
        var labels: [String] = []
        if modifiers.contains(.control) { labels.append("⌃") }
        if modifiers.contains(.option) { labels.append("⌥") }
        if modifiers.contains(.shift) { labels.append("⇧") }
        if modifiers.contains(.command) { labels.append("⌘") }
        labels.append(Self.displayName(forKey: key))
        return pairedWithAnother ? [labels.joined()] : labels
    }
}
