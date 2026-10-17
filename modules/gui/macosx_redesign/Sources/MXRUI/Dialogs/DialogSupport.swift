import AppKit
import MXRCore
import MXRDesign
import SwiftUI
import UniformTypeIdentifiers

// Additional dialog measurements read from the canonical Figma nodes. Kept beside the
// screens until the shared token generator incorporates these finer-grained form boxes.
extension Theme.Metric {
    enum DialogForms {
        static let headerInset: CGFloat = 9 // 6216:13615
        static let titleInset: CGFloat = 10 // 6216:13616
        static let sectionHeight: CGFloat = 58 // 6251:13895
        static let textAreaHeight: CGFloat = 194 // 6251:13829
        static let fieldHeight: CGFloat = 37 // 6251:13904
        static let fieldSlotHeight: CGFloat = 41 // 6251:13903
        static let thumbnailSize: CGFloat = 112 // 6259:14969
        static let thumbnailTopInset: CGFloat = 7 // 6259:14968
        static let playlistDetailsHeight: CGFloat = 119 // 6259:14960
        static let dropZoneHeight: CGFloat = 186 // 6259:14977
        static let dropTrailingInset: CGFloat = 18 // 6259:14977
        static let dropAddWidth: CGFloat = 84 // 6259:14979
        static let addRadius: CGFloat = 5 // 6259:14979
        static let fieldHorizontalInset: CGFloat = 14 // text 6259:14967 minus border 6259:14966
        static let batchLeftWidth: CGFloat = 519 // 1911:7562
        static let batchInset: CGFloat = 30 // 1911:7562
        static let subtitleRowHeight: CGFloat = 36 // 1919:9163
        static let subtitleRowPitch: CGFloat = 40 // 1919:9163 to 1919:9182
        static let listBodyHeight: CGFloat = 632 // 1911:7561
        static let batchLeftTop: CGFloat = 8 // 1911:7853 y126 minus 1915:8446 y118
        static let border: CGFloat = 2 // 6251:13829
        static let formSize = Theme.Metric.Dialogs.newPlaylist.size
    }
}

extension Theme {
    /// In-window modal motion (D024 popup timing; the card grows in from 97 %, none under Reduce Motion).
    enum DialogMotion {
        static let appearDuration = Theme.Popup.appearDuration
        static let disappearDuration = Theme.Popup.disappearDuration
        static let enterScale: CGFloat = 0.97
        /// How long a Settings action's result ("Preferences reset") stays next to its button.
        static let feedbackDuration: Duration = .seconds(4)
    }

    enum DialogPaint {
        static let dropBorder = Theme.RGBA(hex: 0x2D2D2D).color // raw fill, 6259:14977
        static let addButton = Theme.RGBA(hex: 0x161616).color // raw fill, 6259:14979
    }
}

struct DialogHeader: View {
    let title: String
    let close: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.gap1) {
            Text(title).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA2)
                .padding(.leading, Theme.Metric.DialogForms.titleInset)
            Spacer(minLength: 0)
            Button(action: close) {
                MXRIcon(.close, tint: Theme.Color.fgA2)
                    .frame(width: Theme.Metric.iconButtonHeight, height: Theme.Metric.iconButtonHeight)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close \(title)")
        }
        .frame(height: Theme.Metric.iconButtonHeight)
        .padding(Theme.Metric.DialogForms.headerInset)
        .background(Theme.Color.bgB2)
    }
}

struct DialogButton: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.mxrAccent) private var accent
    let title: String
    var primary = false
    var enabled = true
    /// nil fits the title (with the footer buttons' side padding) instead of the fixed button width.
    var width: CGFloat? = Theme.Metric.buttonWidth
    /// The tile of a secondary button; nil is the dialog style (``secondaryFill(for:)``).
    var fill: ThemeColor? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).mxrTextStyle(Theme.Font.button)
                .foregroundStyle(paint(primary ? Theme.Color.accentMain : Theme.Color.fgA2))
                .lineLimit(1)
                .padding(.horizontal, width == nil ? Theme.Spacing.gap14 : 0)
                .frame(width: width, height: Theme.Metric.buttonHeight)
                .background(paint(primary ? Theme.Color.bgAccentBright : fill ?? Self.secondaryFill(for: scheme)),
                            in: .rect(cornerRadius: Theme.Radius.lg))
                // macOS applies the Figma 0.5 opacity when the native button is disabled.
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// Figma draws every dialog's Cancel on BG/A3 (6216:13750, 6259:14982, 1994:5586), over the BG/A3
    /// Transparent and BG/B1 Transparent dialog bodies. Light dialogs are the opaque BG/A3 or BG/B1
    /// (D045), where a BG/A3 tile vanishes, so Light draws it one step darker on the same ramp,
    /// BG/A4, as the Light Settings buttons (SettingsButton) and the video's Light Browse (17m44.0).
    static func secondaryFill(for scheme: ColorScheme) -> ThemeColor {
        scheme == .light ? Theme.Color.bgA4 : Theme.Color.bgA3
    }

    private func paint(_ token: ThemeColor) -> Color {
        let value = token.value(scheme: scheme, accent: accent)
        guard !enabled else { return value.color }
        // Figma's disabled button uses LUMINOSITY (6216:13752). Resolve it before
        // drawing; NSHostingView does not apply nonseparable blend modes consistently.
        let luminosity = value.red * 0.2126 + value.green * 0.7152 + value.blue * 0.0722
        return Theme.RGBA(red: luminosity, green: luminosity, blue: luminosity, alpha: value.alpha).color
    }
}

struct DialogFooter: View {
    var saveTitle = "Save"
    var cancelTitle = "Cancel"
    var enabled = true
    var busy = false
    var error: String?
    let cancel: () -> Void
    var save: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.Spacing.gap20) {
            // Esc belongs to the dialog host (MXRDialogPresentation), which closes like Cancel.
            DialogButton(title: cancelTitle, enabled: !busy, action: cancel)
            if let error {
                Text(error).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.accentMain)
                    .lineLimit(2).accessibilityLabel("Error: \(error)")
            }
            Spacer(minLength: 0)
            if let save {
                DialogButton(title: busy ? (saveTitle == "Save" ? "Saving…" : "Starting…") : saveTitle,
                             primary: true, enabled: enabled && !busy, action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Metric.Dialogs.dialogFooter.padding)
        .frame(height: Theme.Metric.dialogFooterHeight)
    }
}

struct DialogShell<Content: View>: View {
    @Environment(AppModel.self) private var app
    let title: String
    var size = Theme.Metric.DialogForms.formSize
    var saveTitle = "Save"
    var enabled = true
    var busy = false
    var error: String?
    var save: (() -> Void)?
    /// The dialog is as tall as its header, body and footer, up to `size.height` (a body whose length
    /// depends on the media, S65); otherwise it is `size.height` tall and the body scrolls inside.
    var fitsContent = false
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    /// The body is taller than the space it gets, so part of it is under the footer.
    var overflows: Bool { contentHeight > viewportHeight + Theme.Stroke.hairline }

    private var height: CGFloat {
        guard fitsContent else { return size.height }
        // Before the body is measured, the standard form height (no tall first frame).
        guard contentHeight > 0 else { return min(size.height, Theme.Metric.DialogForms.formSize.height) }
        return min(size.height, Theme.Metric.dialogHeaderSimpleHeight + contentHeight + Theme.Metric.dialogFooterHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            DialogHeader(title: title) { if !busy { app.interface.dismissSheet() } }
            // The body scrolls when the window is smaller than the design frame (SD-11; never scaled).
            ScrollView(.vertical) {
                content().frame(maxWidth: .infinity, alignment: .topLeading)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.automatic)
            .frame(maxHeight: .infinity)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { viewportHeight = $0 }
            // A body that scrolls ends at a divider above the footer instead of a row cut in half
            // against the buttons (S65), like the scroll edge of a macOS sheet.
            .overlay(alignment: .bottom) { if overflows { DialogDivider() } }
            DialogFooter(saveTitle: saveTitle, cancelTitle: save == nil ? "Close" : "Cancel", enabled: enabled,
                         busy: busy, error: error, cancel: app.interface.dismissSheet, save: save)
        }
        .frame(idealWidth: size.width, maxWidth: size.width, idealHeight: height, maxHeight: height)
        .background { MXRDialogSurface(tint: Theme.Color.bgA3Transparent, cornerRadius: Theme.Radius.xxl) }
        .clipShape(.rect(cornerRadius: Theme.Radius.xxl))
        .accessibilityElement(children: .contain)
    }
}

/// A modal dialog's body. Dark uses Figma's translucent style over the blurred player. Light uses
/// the opaque form of the same style (D032 addendum): Figma has no light dialog frame, and an 80 %
/// light tint over the dark blurred video and scrim mixes to a muddy mid-grey with the artwork
/// showing through.
struct MXRDialogSurface: View {
    let tint: ThemeColor
    var cornerRadius: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MXRBackdropSurface(tint: colorScheme == .light ? tint.opaqueCounterpart : tint, cornerRadius: cornerRadius)
    }
}

struct DialogSectionHeading: View {
    let title: String
    let hint: String
    var optional = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.gap5) {
            HStack(spacing: Theme.Spacing.gap4) {
                Text(title).foregroundStyle(Theme.Color.fg2)
                if optional { Text("(optional)").foregroundStyle(Theme.Color.fgA3) }
            }.mxrTextStyle(Theme.Font.dialogSectionTitle)
            Text(hint).mxrTextStyle(Theme.Font.dialogHint).foregroundStyle(Theme.Color.fgA3)
                .fixedSize(horizontal: false, vertical: true) // a long hint wraps instead of truncating
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: Theme.Metric.DialogForms.sectionHeight, alignment: .topLeading)
    }
}

struct DialogDivider: View {
    // Figma divider vectors occupy zero height in auto layout, with a centered 1 pt stroke.
    var body: some View { Rectangle().fill(Theme.Color.dividerDim).frame(height: Theme.Stroke.hairline).frame(height: 0) }
}

struct DialogField: View {
    let placeholder: String
    @Binding var text: String
    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA1)
            .padding(.horizontal, Theme.Metric.DialogForms.fieldHorizontalInset)
            .frame(height: Theme.Metric.DialogForms.fieldHeight)
            .background(Theme.Color.bgB2, in: .rect(cornerRadius: Theme.Radius.lg))
            .overlay(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA4)
                        .padding(.horizontal, Theme.Metric.DialogForms.fieldHorizontalInset)
                        .allowsHitTesting(false)
                }
            }
            .overlay { RoundedRectangle(cornerRadius: Theme.Radius.lg).strokeBorder(Theme.Color.bgA4, lineWidth: Theme.Metric.DialogForms.border) }
            .frame(height: Theme.Metric.DialogForms.fieldSlotHeight)
            .accessibilityLabel(placeholder)
    }
}

struct DialogTextArea: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            DialogMultilineEditor(text: $text, label: "Network URLs")
            if text.isEmpty {
                Text(placeholder).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA4)
                    .padding(.leading, Theme.Metric.DialogForms.fieldHorizontalInset)
                    .padding(.top, Theme.Spacing.gap10)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: Theme.Metric.DialogForms.textAreaHeight)
        .background(Theme.Color.bgB2, in: .rect(cornerRadius: Theme.Radius.lg))
        .overlay { RoundedRectangle(cornerRadius: Theme.Radius.lg).strokeBorder(Theme.Color.bgA4, lineWidth: Theme.Metric.DialogForms.border) }
        .clipShape(.rect(cornerRadius: Theme.Radius.lg))
    }
}

private struct DialogMultilineEditor: NSViewRepresentable {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.mxrAccent) private var accent
    @Binding var text: String
    let label: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        let view = scroll.documentView as! NSTextView
        view.delegate = context.coordinator
        view.drawsBackground = false
        view.isRichText = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.font = Theme.Font.body.nsFont
        view.textContainerInset = CGSize(width: Theme.Spacing.gap12, height: Theme.Spacing.gap8)
        view.textContainer?.lineFragmentPadding = Theme.Spacing.gap2
        view.setAccessibilityLabel(label)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.binding = $text
        let view = scroll.documentView as! NSTextView
        if view.string != text { view.string = text }
        view.textColor = Theme.Color.fgA1.value(scheme: scheme, accent: accent).nsColor
        view.insertionPointColor = Theme.Color.accentMain.value(scheme: scheme, accent: accent).nsColor
    }

    func makeCoordinator() -> Coordinator { Coordinator(binding: $text) }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var binding: Binding<String>
        init(binding: Binding<String>) { self.binding = binding }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            binding.wrappedValue = view.string
        }
    }
}

@MainActor
enum DialogFilePicker {
    static func open(multiple: Bool = true, types: [UTType] = [], directories: Bool = false) async -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = directories
        panel.canChooseFiles = !directories
        if !types.isEmpty { panel.allowedContentTypes = types }
        return await withCheckedContinuation { continuation in
            panel.begin { response in continuation.resume(returning: response == .OK ? panel.urls : []) }
        }
    }

    static func save(fileExtension: String, name: String) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = UTType(filenameExtension: fileExtension).map { [$0] } ?? []
        panel.nameFieldStringValue = name
        return await withCheckedContinuation { continuation in
            panel.begin { response in continuation.resume(returning: response == .OK ? panel.url : nil) }
        }
    }
}
