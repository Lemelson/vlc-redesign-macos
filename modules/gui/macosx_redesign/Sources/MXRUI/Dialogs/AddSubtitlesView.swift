import MXRCore
import MXRDesign
import SwiftUI
import UniformTypeIdentifiers

/// S25–S27. The same draft handles current-file selection and folder/playlist matching.
public struct MXRAddSubtitlesView: View {
    @Environment(AppModel.self) private var app
    @State private var draft: SubtitleImportDraft
    @State private var hoveredMedia: String?

    public init(scope: AddSubtitlesScope, source: AddSubtitlesSource) {
        _draft = State(initialValue: SubtitleImportDraft(scope: scope, source: source))
    }

    /// Hosts may prepopulate already chosen media and subtitle files (also used by the gallery).
    public init(scope: AddSubtitlesScope, source: AddSubtitlesSource, media: [MediaItem], subtitles: [URL],
                selected: Set<URL>? = nil, locationTitle: String = "", search: String = "") {
        let draft = SubtitleImportDraft(scope: scope, source: source, media: media, subtitles: subtitles,
                                        selected: selected, locationTitle: locationTitle)
        draft.search = search
        _draft = State(initialValue: draft)
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Theme.Metric.Dialogs.addSubtitlesHeader.gap) {
                DialogHeader(title: "Add Subtitles", close: app.interface.dismissSheet)
                    .padding(-Theme.Metric.DialogForms.headerInset)
                toolbar
            }
            .padding(Theme.Metric.Dialogs.addSubtitlesHeader.padding)
            .frame(height: Theme.Metric.dialogHeaderWithToolbarHeight)
            .background(Theme.Color.bgB2)
            content.frame(maxHeight: .infinity, alignment: .topLeading)
            DialogFooter(enabled: draft.canSave, busy: draft.loading, error: draft.error,
                         cancel: app.interface.dismissSheet) {
                Task { @MainActor in
                    do { try await draft.save(to: app); app.interface.dismissSheet() }
                    catch { draft.error = error.localizedDescription }
                }
            }
        }
        .frame(idealWidth: Theme.Metric.Dialogs.addSubtitles.width, maxWidth: Theme.Metric.Dialogs.addSubtitles.width,
               idealHeight: Theme.Metric.Dialogs.addSubtitles.height, maxHeight: Theme.Metric.Dialogs.addSubtitles.height)
        .background { MXRDialogSurface(tint: Theme.Color.bgB1Transparent, cornerRadius: Theme.Radius.xxl) }
        .clipShape(.rect(cornerRadius: Theme.Radius.xxl))
        .task(id: draft.scope) {
            await draft.loadTargets(from: app)
            if draft.source == .openSubtitles && !app.capabilities.supportsOpenSubtitles {
                draft.source = .computer
                draft.error = "OpenSubtitles is unavailable. Choose local files or a direct subtitle link."
            }
        }
        .onDisappear { app.interface.subtitleTargetMedia = [] }
    }

    private var toolbar: some View {
        @Bindable var draft = draft
        return HStack(spacing: Theme.Spacing.gap10) {
            DialogMenu {
                AddSubtitlesScope.allCases.map { scope in DialogMenuChoice(title: scope.title, isSelected: scope == draft.scope) { draft.scope = scope } }
            } label: { dropdownLabel(draft.scope.title) }
            .accessibilityLabel("Subtitle scope")
            DialogMenu {
                let sources: [AddSubtitlesSource] = app.capabilities.supportsOpenSubtitles ? [.computer, .openSubtitles, .link] : [.computer, .link]
                return sources.map { source in
                    DialogMenuChoice(title: source.title, isSelected: source == draft.source) { draft.source = source }
                }
            } label: { dropdownLabel(draft.source.title) }
            .accessibilityLabel("Subtitle source")
            switch draft.source {
            case .computer:
                Button { chooseSubtitles() } label: {
                    HStack(spacing: Theme.Spacing.gap10) {
                        MXRIcon(.folder, tint: Theme.Color.fgA2)
                        Text(draft.locationTitle.isEmpty ? "Select subtitle files…" : draft.locationTitle)
                            .mxrTextStyle(Theme.Font.body).lineLimit(1)
                        Spacer(minLength: 0)
                    }.foregroundStyle(Theme.Color.fgA2)
                        .padding(.horizontal, Theme.Spacing.gap8)
                        .frame(height: Theme.Metric.textFieldHeight)
                        .background(Theme.Color.bgA5, in: .rect(cornerRadius: Theme.Radius.lg))
                }.buttonStyle(.plain).help("Choose subtitle files from this computer")
            case .link:
                TextField("Subtitle URL", text: $draft.link).textFieldStyle(.plain)
                    .mxrTextStyle(Theme.Font.body).padding(.horizontal, Theme.Spacing.gap8)
                    .frame(height: Theme.Metric.textFieldHeight)
                    .background(Theme.Color.bgA5, in: .rect(cornerRadius: Theme.Radius.lg))
                Button("Load") { importLink() }.buttonStyle(.plain).foregroundStyle(Theme.Color.accentMain)
                    .disabled(draft.link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            case .openSubtitles:
                HStack(spacing: Theme.Spacing.gap10) {
                    MXRIcon(.search, tint: Theme.Color.fgA2)
                    TextField("Search subtitles", text: $draft.search).textFieldStyle(.plain).mxrTextStyle(Theme.Font.body)
                }.padding(.horizontal, Theme.Spacing.gap8).frame(height: Theme.Metric.textFieldHeight)
                    .background(Theme.Color.bgA5, in: .rect(cornerRadius: Theme.Radius.lg))
                DialogMenu {
                    ["English", "Spanish", "Japanese", "German", "French", "Russian"].map { language in
                        DialogMenuChoice(title: language, isSelected: language == draft.language) { draft.language = language }
                    }
                } label: { dropdownLabel(draft.language) }
            }
        }
        .foregroundStyle(Theme.Color.fgA1)
    }

    private func dropdownLabel(_ title: String) -> some View {
        HStack(spacing: Theme.Spacing.gap10) {
            Text(title).mxrTextStyle(Theme.Font.body)
            Spacer(minLength: 0)
            MXRIcon(.chevronDown, tint: Theme.Color.fgA2)
        }
        .foregroundStyle(Theme.Color.fgA1)
        .padding(Theme.Metric.Controls.dialogHeaderDropdown.padding)
        .frame(width: Theme.Metric.Controls.dialogHeaderDropdown.width, height: Theme.Metric.Controls.dialogHeaderDropdown.height)
        .background(Theme.Color.bgA5, in: .rect(cornerRadius: Theme.Radius.lg))
    }

    @ViewBuilder private var content: some View {
        if draft.source == .openSubtitles && draft.subtitles.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.gap20) {
                DialogSectionHeading(title: "OpenSubtitles is unavailable", hint: "Subtitle search requires an OpenSubtitles API key. Add files from your computer or a direct subtitle link.")
                DialogButton(title: "Choose Files") { draft.source = .computer; chooseSubtitles() }
            }.padding(Theme.Metric.Dialogs.dialogBody.padding)
        } else if draft.subtitles.isEmpty && draft.scope == .file {
            VStack(spacing: Theme.Spacing.gap20) {
                Text("Choose subtitle files to add to this video.").mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA3)
                DialogButton(title: "Choose Files", action: chooseSubtitles)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: Theme.Spacing.gap4) {
                    if draft.scope == .file {
                        ForEach(draft.subtitles, id: \.self) { url in
                            Button {
                                if draft.selected.contains(url) { draft.selected.remove(url) } else { draft.selected.insert(url) }
                            } label: { subtitleRow(url: url, selected: draft.selected.contains(url)) }
                            .buttonStyle(.plain).accessibilityLabel(url.lastPathComponent)
                            .accessibilityValue(draft.selected.contains(url) ? "Selected" : "Not selected")
                        }
                    } else {
                        ForEach(draft.media) { media in batchRow(media) }
                    }
                }
                .padding(.vertical, Theme.Spacing.gap22)
                .padding(.horizontal, draft.scope == .file ? Theme.Spacing.gap20 : 0)
            }.scrollIndicators(.hidden)
        }
    }

    private func subtitleRow(url: URL?, selected: Bool = false, editable: Bool = false) -> some View {
        HStack(spacing: Theme.Spacing.gap14) {
            MXRIcon(.subtitle, tint: Theme.Color.fgA3)
            Text(url?.lastPathComponent ?? "No matching subtitle").mxrTextStyle(Theme.Font.body).lineLimit(1)
            Spacer(minLength: 0)
            if selected { MXRIcon(.check, state: .active) }
            if editable { MXRIcon(.swap, tint: Theme.Color.fgA2) }
        }
        .foregroundStyle(Theme.Color.fgA2)
        .padding(.horizontal, Theme.Spacing.gap8)
        .frame(height: Theme.Metric.DialogForms.subtitleRowHeight)
        .background {
            if selected || editable { RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgB2) }
        }
    }

    private func batchRow(_ media: MediaItem) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.gap14) {
                MXRIcon(.video, tint: Theme.Color.fgA3)
                Text(media.listTitle).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA2).fixedSize()
                SubtitleConnector().stroke(Theme.Color.dividerBright,
                    style: StrokeStyle(lineWidth: Theme.Stroke.hairline, lineCap: .round, dash: Theme.Stroke.subtitleConnectorDash))
                    .frame(maxWidth: .infinity).frame(height: Theme.Stroke.hairline)
            }
            .padding(.leading, Theme.Metric.DialogForms.batchInset)
            .frame(width: Theme.Metric.DialogForms.batchLeftWidth, height: Theme.Metric.DialogForms.subtitleRowHeight)
            .offset(y: Theme.Spacing.gap2)
            DialogMenu {
                let choose = DialogMenuChoice(title: "Choose subtitle file…") {
                    Task { @MainActor in
                        let urls = await DialogFilePicker.open(multiple: false, types: subtitleTypes)
                        if let url = urls.first { draft.assignments[media.id] = url }
                    }
                }
                let available = draft.subtitles.map { url in DialogMenuChoice(title: url.lastPathComponent) { draft.assignments[media.id] = url } }
                return [choose] + available + [DialogMenuChoice(title: "Clear match") { draft.assignments.removeValue(forKey: media.id) }]
            } label: { subtitleRow(url: draft.assignments[media.id], editable: hoveredMedia == media.id) }
            .padding(.horizontal, Theme.Spacing.gap20)
            .accessibilityLabel("Subtitle for \(media.listTitle)")
            .onHover { hoveredMedia = $0 ? media.id : nil }
        }
    }

    private var subtitleTypes: [UTType] { SubtitleMatcher.subtitleExtensions.compactMap { UTType(filenameExtension: $0) } }
    private func chooseSubtitles() {
        Task { @MainActor in
            let urls = await DialogFilePicker.open(types: subtitleTypes)
            if !urls.isEmpty { draft.importFiles(urls) }
        }
    }
    private func importLink() {
        do { draft.importFiles([try DialogInput.subtitleURL(draft.link)]); draft.link = "" }
        catch { draft.error = error.localizedDescription }
    }
}

private struct SubtitleConnector: Shape {
    func path(in rect: CGRect) -> Path { Path { $0.move(to: CGPoint(x: rect.minX, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) } }
}
