import AppKit
import MXRGalleryCatalog
import SwiftUI

/// Main window: entry list, canvas with the Figma reference, and an inspector.
struct GalleryWindow: View {
    @Bindable var model: GalleryModel

    var body: some View {
        NavigationSplitView {
            GallerySidebar(model: model)
                .navigationSplitViewColumnWidth(min: GalleryChrome.sidebarWidth * 0.8, ideal: GalleryChrome.sidebarWidth)
        } detail: {
            GalleryDetail(model: model)
        }
        .inspector(isPresented: $model.showInspector) {
            GalleryInspector(model: model)
                .inspectorColumnWidth(min: GalleryChrome.inspectorWidth * 0.8, ideal: GalleryChrome.inspectorWidth)
        }
        .toolbar { GalleryToolbar(model: model) }
        .navigationTitle(model.selectedEntry?.title ?? "MXR Gallery")
        .navigationSubtitle(model.selectedEntry?.id ?? "")
        .task { await model.loadFigmaIndex() }
        .task(id: model.referenceKey) { await model.refreshReference() }
    }
}

// MARK: - Sidebar

struct GallerySidebar: View {
    @Bindable var model: GalleryModel

    /// Groups start expanded; the model remembers the ones the user collapsed.
    private func expansion(of group: String) -> Binding<Bool> {
        Binding(
            get: { !model.collapsedGroups.contains(group) },
            set: { expanded in
                if expanded { model.collapsedGroups.remove(group) } else { model.collapsedGroups.insert(group) }
            }
        )
    }

    var body: some View {
        List(selection: $model.selectedID) {
            ForEach(model.sections, id: \.kind) { section in
                Section(section.kind.title) {
                    ForEach(section.groups, id: \.name) { group in
                        if group.entries.count == 1, let entry = group.entries.first {
                            EntryRow(entry: entry, label: entry.group).tag(entry.id)
                        } else {
                            DisclosureGroup(isExpanded: expansion(of: group.name)) {
                                ForEach(group.entries) { entry in
                                    EntryRow(entry: entry, label: entry.state.isEmpty ? entry.id : entry.state).tag(entry.id)
                                }
                            } label: {
                                Text(group.name)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Entries, nodes, screens")
        .overlay {
            if model.entries.isEmpty {
                ContentUnavailableView(
                    "No Entries", systemImage: "square.dashed",
                    description: Text("Add a GalleryProvider under Sources/MXRGalleryCatalog/Entries/.")
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text(model.figmaStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, GalleryChrome.labelGap)
        }
    }
}

private struct EntryRow: View {
    let entry: GalleryEntry
    let label: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            if entry.figmaNode != nil {
                Image(systemName: "photo").foregroundStyle(.tertiary).help("Has a Figma reference")
            }
        }
    }
}

// MARK: - Detail canvas

struct GalleryDetail: View {
    @Bindable var model: GalleryModel

    var body: some View {
        if let entry = model.selectedEntry {
            VStack(spacing: 0) {
                ScrollView([.horizontal, .vertical]) {
                    CanvasContent(model: model, entry: entry)
                        .padding(GalleryChrome.canvasPadding)
                }
                .background { CanvasBackground(checkerboard: model.checkerboard) }
                Divider()
                StatusBar(model: model, entry: entry)
            }
        } else {
            ContentUnavailableView("Select an Entry", systemImage: "sidebar.left")
        }
    }
}

/// The entry and its reference arranged for the current mode, at the current zoom.
private struct CanvasContent: View {
    let model: GalleryModel
    let entry: GalleryEntry

    var body: some View {
        let environment = model.environment(for: entry)
        switch model.mode {
        case .render:
            Zoomed(size: entry.size, zoom: model.zoom) { live(environment) }
        case .figma:
            referencePane
        case .side:
            HStack(alignment: .top, spacing: GalleryChrome.paneGap) {
                Labeled("SwiftUI") { Zoomed(size: entry.size, zoom: model.zoom) { live(environment) } }
                Labeled("Figma") { referencePane }
            }
        case .overlay:
            Zoomed(size: entry.size, zoom: model.zoom) {
                ZStack(alignment: .topLeading) {
                    live(environment)
                    referenceImage.opacity(model.overlayOpacity).allowsHitTesting(false)
                }
            }
        case .difference:
            // Difference against black is the identity, so identical pixels turn black.
            Zoomed(size: entry.size, zoom: model.zoom) {
                ZStack(alignment: .topLeading) {
                    Color.black
                    live(environment)
                    referenceImage.blendMode(.difference).allowsHitTesting(false)
                }
                .compositingGroup()
            }
        case .heatmap:
            if let measurement = model.measurement, model.measurementIsCurrent {
                Zoomed(size: measurement.heatmap.size, zoom: model.zoom) {
                    Image(nsImage: measurement.heatmap).resizable().interpolation(.none)
                }
            } else {
                Placeholder(text: heatmapPlaceholder, size: entry.size)
            }
        }
    }

    private var heatmapPlaceholder: String {
        if entry.figmaNode == nil { return "No Figma node to measure against" }
        if model.isMeasuring { return "Measuring…" }
        if model.measurement?.entryID == entry.id { return "Scheme or accent changed: measure (⇧⌘M) again" }
        return "Measure (⇧⌘M) to see the heat map"
    }

    private func live(_ environment: GalleryEnvironment) -> some View {
        GalleryCatalog.canvas(for: entry, environment: environment)
    }

    @ViewBuilder private var referenceImage: some View {
        if case .loaded(_, let image) = model.reference {
            Image(nsImage: image)
                .resizable()
                .interpolation(model.zoom >= 1 ? .none : .medium)
                .frame(width: image.size.width, height: image.size.height)
        }
    }

    @ViewBuilder private var referencePane: some View {
        switch model.reference {
        case .loaded(_, let image):
            Zoomed(size: image.size, zoom: model.zoom) { referenceImage }
        case .loading:
            Placeholder(text: "Loading Figma reference…", size: entry.size, progress: true)
        case .none(let message), .failed(let message):
            Placeholder(text: message, size: entry.size)
        }
    }
}

/// Scales content from its top-left corner and reserves the scaled size for scrolling.
private struct Zoomed<Content: View>: View {
    let size: CGSize
    let zoom: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .scaleEffect(zoom, anchor: .topLeading)
            .frame(width: size.width * zoom, height: size.height * zoom, alignment: .topLeading)
    }
}

private struct Labeled<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GalleryChrome.labelGap) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}

private struct Placeholder: View {
    let text: String
    let size: CGSize
    var progress = false

    var body: some View {
        VStack {
            if progress { ProgressView().controlSize(.small) }
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding()
        .frame(minWidth: min(size.width, GalleryChrome.inspectorWidth), minHeight: min(size.height, GalleryChrome.inspectorWidth / 2))
        .background(.quaternary.opacity(0.4), in: .rect)
    }
}

/// Neutral checkerboard (or plain window background) behind the canvas.
private struct CanvasBackground: View {
    let checkerboard: Bool

    var body: some View {
        if checkerboard {
            Canvas { context, size in
                let cell = GalleryChrome.checkerCell
                let shade = GraphicsContext.Shading.color(.gray.opacity(0.18))
                for row in 0..<Int((size.height / cell).rounded(.up)) {
                    for column in 0..<Int((size.width / cell).rounded(.up)) where (row + column).isMultiple(of: 2) {
                        context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)), with: shade)
                    }
                }
            }
            .background(.background)
        } else {
            Rectangle().fill(.background)
        }
    }
}

private struct StatusBar: View {
    let model: GalleryModel
    let entry: GalleryEntry

    var body: some View {
        HStack(spacing: GalleryChrome.paneGap / 2) {
            Text("\(Self.format(entry.size.width))×\(Self.format(entry.size.height)) pt")
            Text(model.environment(for: entry).colorScheme == .dark ? "Dark" : "Light")
            if let node = entry.figmaNode { Text("Figma \(node)") }
            Text("\(Int((model.zoom * 100).rounded())) %")
            Spacer()
            if model.isMeasuring {
                ProgressView().controlSize(.mini)
            } else if let measurement = model.measurement, model.measurementIsCurrent {
                VerdictBadge(comparison: measurement.comparison)
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, GalleryChrome.labelGap)
    }

    static func format(_ value: CGFloat) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }
}

struct VerdictBadge: View {
    let comparison: ImageComparison

    var body: some View {
        Label {
            Text(String(format: "%@  structural %.2f %%  flat color %.2f %%", comparison.verdict.rawValue,
                        comparison.structuralFraction * 100, comparison.flatColorFraction * 100))
        } icon: {
            Image(systemName: symbol).foregroundStyle(style)
        }
        .help(comparison.reason)
    }

    private var symbol: String {
        switch comparison.verdict {
        case .pass: "checkmark.circle.fill"
        case .review: "exclamationmark.triangle.fill"
        case .fail: "xmark.octagon.fill"
        }
    }

    private var style: Color {
        switch comparison.verdict {
        case .pass: .green
        case .review: .yellow
        case .fail: .red
        }
    }
}

// MARK: - Toolbar

struct GalleryToolbar: ToolbarContent {
    @Bindable var model: GalleryModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Mode", selection: $model.mode) {
                ForEach(GalleryModel.Mode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("Comparison mode (⌘1…⌘6)")
        }
        ToolbarItemGroup {
            if model.mode == .overlay {
                Slider(value: $model.overlayOpacity, in: 0...1) { Text("Figma opacity") }
                    .frame(width: GalleryChrome.sidebarWidth / 2)
                    .help("Figma overlay opacity: \(Int(model.overlayOpacity * 100)) %")
            }
            Menu {
                Picker("Appearance", selection: $model.scheme) {
                    ForEach(GalleryModel.SchemeChoice.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(model.scheme == .entry ? "Entry Scheme" : model.scheme.title, systemImage: "circle.lefthalf.filled")
                    .labelStyle(.titleAndIcon)
            }
            .help("Color scheme (⇧⌘L toggles)")
            Menu {
                Button("Design Default") { model.accent = nil }
                Divider()
                ForEach(model.theme.accents) { accent in
                    Button {
                        model.accent = accent.id
                    } label: {
                        Label { Text(accent.id.capitalized) } icon: {
                            Image(systemName: model.accent == accent.id ? "checkmark.circle.fill" : "circle.fill")
                        }
                    }
                    .tint(accent.color)
                }
            } label: {
                Label(model.accent?.capitalized ?? "Accent", systemImage: "paintpalette")
            }
            .disabled(model.theme.accents.isEmpty)
            .help("Accent color")
            ControlGroup {
                Button { model.zoomOut() } label: { Label("Zoom Out", systemImage: "minus.magnifyingglass") }
                Button { model.zoom = 1 } label: { Text("\(Int((model.zoom * 100).rounded()))%").monospacedDigit() }
                    .help("Actual size (⌘0)")
                Button { model.zoomIn() } label: { Label("Zoom In", systemImage: "plus.magnifyingglass") }
            }
            Toggle(isOn: $model.checkerboard) { Label("Checkerboard", systemImage: "checkerboard.rectangle") }
                .help("Checkerboard behind transparent canvases")
            Button { model.measure() } label: { Label("Measure", systemImage: "ruler") }
                .disabled(model.selectedEntry?.figmaNode == nil)
                .help("Render like mxr-snapshot and compare with Figma (⇧⌘M)")
            Toggle(isOn: $model.showInspector) { Label("Inspector", systemImage: "sidebar.right") }
        }
    }
}
