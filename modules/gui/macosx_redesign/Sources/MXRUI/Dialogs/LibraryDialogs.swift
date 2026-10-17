import AppKit
import MXRCore
import MXRDesign
import SwiftUI

public struct MXRNetworkStreamView: View {
    @Environment(AppModel.self) private var app
    @State private var urls = ""
    @State private var name = ""
    @State private var error: String?
    @State private var saving = false

    public init() {}
    public init(urls: String, name: String = "") { _urls = State(initialValue: urls); _name = State(initialValue: name) }

    public var body: some View {
        DialogShell(title: "Open Network Stream", size: Theme.Metric.Dialogs.openNetworkStream.size,
                    enabled: (try? DialogInput.networkURLs(urls)) != nil, busy: saving, error: error ?? inputError, save: save) {
            VStack(alignment: .leading, spacing: Theme.Spacing.gap20) {
                DialogSectionHeading(title: "Network URL", hint: "You can enter multiple links to load.")
                DialogTextArea(placeholder: "e.g., https://www.example.com/stream.avi", text: $urls)
                DialogDivider()
                DialogSectionHeading(title: "Playlist Name", hint: "The playlist will be saved and displayed with this title.", optional: true)
                DialogField(placeholder: "e.g., Favorite TV Channels", text: $name)
            }.padding(Theme.Metric.Dialogs.dialogBody.padding)
        }.onChange(of: urls) { error = nil }
    }

    private var inputError: String? {
        guard !urls.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        do { _ = try DialogInput.networkURLs(urls); return nil } catch { return error.localizedDescription }
    }

    private func save() {
        Task { @MainActor in
            saving = true
            defer { saving = false }
            do {
                let parsed = try DialogInput.networkURLs(urls)
                let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = try await app.library.addNetworkStream(urls: parsed, name: title.isEmpty ? nil : title)
                app.library.select(.network)
                app.interface.dismissSheet()
            } catch { self.error = error.localizedDescription }
        }
    }
}

public struct MXRNewPlaylistView: View {
    @Environment(AppModel.self) private var app
    @State private var name = ""
    @State private var files: [PlaylistFileOccurrence] = []
    @State private var initialMedia: [MediaItem] = []
    @State private var artwork: URL?
    @State private var error: String?
    @State private var saving = false
    @State private var isTargeted = false

    public init() {}

    public var body: some View {
        DialogShell(title: "New Playlist", size: Theme.Metric.Dialogs.newPlaylist.size,
                    enabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    busy: saving, error: error, save: save) {
            VStack(alignment: .leading, spacing: Theme.Spacing.gap20) {
                HStack(alignment: .top, spacing: Theme.Spacing.gap20) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.gap20) {
                        DialogSectionHeading(title: "Playlist Details", hint: "The playlist will be saved and displayed with this title and thumbnail.")
                        DialogField(placeholder: "e.g., Favorite Videos", text: $name)
                    }
                    Button(action: chooseArtwork) {
                        ZStack {
                            if let artwork, let image = NSImage(contentsOf: artwork) {
                                Image(nsImage: image).resizable().scaledToFill()
                            } else { addIcon(width: Theme.Metric.DialogForms.batchInset) }
                        }
                        .frame(width: Theme.Metric.DialogForms.thumbnailSize, height: Theme.Metric.DialogForms.thumbnailSize)
                        .background(Theme.Color.bgB2, in: .rect(cornerRadius: Theme.Radius.lg))
                        .overlay { RoundedRectangle(cornerRadius: Theme.Radius.lg).strokeBorder(Theme.Color.bgA4, lineWidth: Theme.Metric.DialogForms.border) }
                        .clipShape(.rect(cornerRadius: Theme.Radius.lg))
                    }.buttonStyle(.plain).padding(.top, Theme.Metric.DialogForms.thumbnailTopInset)
                        .accessibilityLabel("Choose playlist thumbnail")
                }.frame(height: Theme.Metric.DialogForms.playlistDetailsHeight)
                DialogDivider()
                DialogSectionHeading(title: "Select Files", hint: "These files will be added to the playlist.")
                fileDropZone
            }.padding(Theme.Metric.Dialogs.dialogBody.padding)
        }
        .onAppear {
            initialMedia = app.interface.pendingPlaylistMedia
            files = initialMedia.compactMap { media in
                URL(string: media.mrl).map { PlaylistFileOccurrence(url: $0, media: media) }
            }
        }
        .onDisappear { app.interface.pendingPlaylistMedia = [] }
    }

    private var fileDropZone: some View {
        VStack(spacing: Theme.Spacing.gap20) {
            if files.isEmpty {
                Button(action: chooseFiles) {
                    Text("Drag files into the box or click here to select files.").mxrTextStyle(Theme.Font.body)
                        .foregroundStyle(Theme.Color.fgA4)
                }.buttonStyle(.plain)
            } else {
                ScrollView {
                    VStack(spacing: Theme.Spacing.gap4) {
                        ForEach(files) { file in
                            HStack(spacing: Theme.Spacing.gap8) {
                                MXRIcon(.file, tint: Theme.Color.fgA2)
                                Text(file.url.lastPathComponent).mxrTextStyle(Theme.Font.body).lineLimit(1)
                                Spacer(minLength: 0)
                                Button {
                                    if let index = files.firstIndex(where: { $0.id == file.id }) { files.remove(at: index) }
                                } label: { MXRIcon(.remove, tint: Theme.Color.fgA2) }
                                    .buttonStyle(.plain).accessibilityLabel("Remove \(file.url.lastPathComponent)")
                            }.foregroundStyle(Theme.Color.fgA1)
                        }
                    }
                }.padding(.horizontal, Theme.Spacing.gap12)
            }
            Button(action: chooseFiles) { addIcon(width: Theme.Metric.DialogForms.dropAddWidth) }
                .buttonStyle(.plain).accessibilityLabel("Select playlist files")
        }
        .padding(.leading, Theme.Spacing.gap12)
        .padding(.trailing, Theme.Metric.DialogForms.dropTrailingInset)
        .frame(maxWidth: .infinity).frame(height: Theme.Metric.DialogForms.dropZoneHeight)
        .background(Theme.Color.bgB2, in: .rect(cornerRadius: Theme.Radius.lg))
        .overlay {
            DialogDropOutline().stroke(isTargeted ? AnyShapeStyle(Theme.Color.accentMain) : AnyShapeStyle(Theme.DialogPaint.dropBorder),
                                       lineWidth: Theme.Metric.DialogForms.border)
                .clipShape(.rect(cornerRadius: Theme.Radius.lg))
        }
        .dropDestination(for: URL.self) { urls, _ in
            addFiles(urls)
            return !urls.isEmpty
        } isTargeted: { isTargeted = $0 }
    }

    private func addIcon(width: CGFloat) -> some View {
        MXRIcon(.add, tint: Theme.Color.fgA2).frame(width: width, height: Theme.Metric.DialogForms.batchInset)
            .background(Theme.DialogPaint.addButton, in: .rect(cornerRadius: Theme.Metric.DialogForms.addRadius))
    }

    private func addFiles(_ urls: [URL]) {
        for url in urls where !files.contains(where: { $0.url == url }) {
            let media = initialMedia.first { URL(string: $0.mrl) == url } ?? MediaItem(url: url)
            files.append(PlaylistFileOccurrence(url: url, media: media))
        }
    }
    private func chooseFiles() {
        Task { @MainActor in addFiles(await DialogFilePicker.open()) }
    }
    private func chooseArtwork() {
        Task { @MainActor in if let url = await DialogFilePicker.open(multiple: false, types: [.image]).first { artwork = url } }
    }
    private func save() {
        Task { @MainActor in
            saving = true
            defer { saving = false }
            do {
                _ = try await app.library.createPlaylist(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                                         media: files.map(\.media), artworkURL: artwork)
                app.library.select(.playlists)
                app.interface.dismissSheet()
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct PlaylistFileOccurrence: Identifiable {
    let id = UUID()
    let url: URL
    let media: MediaItem
}

/// Figma fits each edge's [4, 4] dash pattern to the straight span, and mirrors it
/// on the opposite edge. A continuous rounded-rectangle dash shifts at every corner.
private struct DialogDropOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = Theme.Radius.lg
        let border = Theme.Metric.DialogForms.border
        let dashCycle = Theme.Stroke.customizeOutlineDash.reduce(0, +)
        let offset = radius - border
        return Path { path in
            func edge(span: CGFloat, draw: (CGFloat, CGFloat) -> Void) {
                let cycles = max(1, (span / dashCycle).rounded())
                let step = span / cycles
                for index in 0...Int(cycles) {
                    let start = offset + CGFloat(index) * step
                    draw(start, start + step / 2)
                }
            }
            edge(span: rect.width - 2 * radius) { start, end in
                for y in [rect.minY + border / 2, rect.maxY - border / 2] {
                    path.move(to: CGPoint(x: rect.minX + start, y: y))
                    path.addLine(to: CGPoint(x: rect.minX + end, y: y))
                }
            }
            edge(span: rect.height - 2 * radius) { start, end in
                for x in [rect.minX + border / 2, rect.maxX - border / 2] {
                    path.move(to: CGPoint(x: x, y: rect.minY + start))
                    path.addLine(to: CGPoint(x: x, y: rect.minY + end))
                }
            }
        }
    }
}
