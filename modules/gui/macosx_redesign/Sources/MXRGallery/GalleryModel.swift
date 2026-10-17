import AppKit
import MXRGalleryCatalog
import Observation
import SwiftUI

/// State of the Gallery window: selection, environment, comparison mode and Figma reference.
@MainActor
@Observable
final class GalleryModel {
    /// How the canvas shows the entry and its Figma reference.
    enum Mode: String, CaseIterable, Identifiable {
        case render, side, overlay, difference, figma, heatmap

        var id: String { rawValue }

        var title: String {
            switch self {
            case .render: "SwiftUI Only"
            case .side: "Side by Side"
            case .overlay: "Overlay"
            case .difference: "Difference"
            case .figma: "Figma Only"
            case .heatmap: "Diff Heat Map"
            }
        }

        var symbol: String {
            switch self {
            case .render: "swift"
            case .side: "rectangle.split.2x1"
            case .overlay: "square.on.square"
            case .difference: "circle.lefthalf.filled"
            case .figma: "photo"
            case .heatmap: "flame"
            }
        }
    }

    /// Color scheme the canvas uses: the entry's own, or forced.
    enum SchemeChoice: String, CaseIterable, Identifiable {
        case entry, dark, light
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    /// The Figma crop for the selected entry.
    enum ReferenceState {
        case none(String)
        case loading
        case loaded(FigmaReference, NSImage)
        case failed(String)
    }

    /// Result of "Measure Against Figma".
    struct Measurement {
        let entryID: String
        let environment: GalleryEnvironment
        let comparison: ImageComparison
        let heatmap: NSImage
        let images: ComparisonImages
        let render: CGImage
        let reference: CGImage
    }

    private(set) var entries: [GalleryEntry] = []
    var selectedID: String?
    var searchText = ""
    var mode: Mode = .side
    var scheme: SchemeChoice = .entry
    /// Accent swatch name; `nil` = design default.
    var accent: String?
    var zoom: CGFloat = 1
    var overlayOpacity = 0.5
    var checkerboard = true
    var showInspector = true
    /// Sidebar groups the user collapsed (all start expanded).
    var collapsedGroups: Set<String> = []
    /// Measure as soon as the reference is loaded (`--measure` launch argument).
    private let measureOnLoad: Bool

    private(set) var figmaIndex: FigmaIndex?
    private(set) var figmaStatus = "Loading Figma index…"
    private(set) var reference: ReferenceState = .none("No Figma node")
    /// The last measurement; see `measurementIsCurrent` before trusting it.
    private(set) var measurement: Measurement?
    /// Whether a measurement is being rendered or compared.
    private(set) var isMeasuring = false
    /// Why the last measurement or save failed, if it did.
    private(set) var measureError: String?
    private(set) var lastSavedDirectory: URL?
    private(set) var theme: GalleryTheme
    /// Bumped by every measurement, so only the latest one updates the state.
    private var measureGeneration = 0
    private var measureTask: Task<Void, Never>?

    init(arguments: [String]) {
        measureOnLoad = arguments.contains("--measure")
        theme = GalleryCatalog.theme()
        entries = GalleryCatalog.allEntries()
        if let index = arguments.firstIndex(of: "--entry"), index + 1 < arguments.count {
            selectedID = arguments[index + 1]
        }
        if let index = arguments.firstIndex(of: "--mode"), index + 1 < arguments.count,
           let mode = Mode(rawValue: arguments[index + 1]) {
            self.mode = mode
        }
        if selectedID == nil || !entries.contains(where: { $0.id == selectedID }) {
            selectedID = entries.first?.id
        }
    }

    // MARK: Derived state

    var selectedEntry: GalleryEntry? {
        guard let selectedID else { return nil }
        return entries.first { $0.id == selectedID }
    }

    /// Entries matching the search field, grouped by kind and then by component/screen.
    var sections: [(kind: GalleryKind, groups: [(name: String, entries: [GalleryEntry])])] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let visible = entries.filter { entry in
            query.isEmpty || entry.id.localizedCaseInsensitiveContains(query)
                || entry.title.localizedCaseInsensitiveContains(query)
                || (entry.figmaNode ?? "").contains(query)
                || entry.screens.contains { $0.localizedCaseInsensitiveContains(query) }
        }
        return Dictionary(grouping: visible, by: \.kind)
            .sorted { $0.key < $1.key }
            .map { kind, items in
                let groups = Dictionary(grouping: items, by: \.group)
                    .sorted { $0.key < $1.key }
                    .map { (name: $0.key, entries: $0.value.sorted { $0.id < $1.id }) }
                return (kind: kind, groups: groups)
            }
    }

    func environment(for entry: GalleryEntry) -> GalleryEnvironment {
        let colorScheme: ColorScheme = switch scheme {
        case .entry: entry.colorScheme
        case .dark: .dark
        case .light: .light
        }
        return GalleryEnvironment(colorScheme: colorScheme, accent: accent)
    }

    /// Identity of what the reference and measurement depend on.
    var referenceKey: String { "\(selectedID ?? "")|\(figmaIndex == nil ? 0 : 1)" }

    /// Whether `measurement` belongs to the selected entry in the current scheme and accent.
    var measurementIsCurrent: Bool {
        guard let measurement, let entry = selectedEntry else { return false }
        return measurement.entryID == entry.id && measurement.environment == environment(for: entry)
    }

    /// Shell command that reproduces the current comparison with `mxr-snapshot`.
    var checkCommand: String? {
        guard let entry = selectedEntry, entry.figmaNode != nil else { return nil }
        var command = "swift run mxr-snapshot check --id '\(entry.id)'"
        if scheme != .entry { command += " --scheme \(scheme.rawValue)" }
        if let accent { command += " --accent \(accent)" }
        return command
    }

    // MARK: Actions

    func reloadEntries() {
        entries = GalleryCatalog.allEntries()
        if selectedEntry == nil { selectedID = entries.first?.id }
    }

    func selectAdjacent(_ offset: Int) {
        let ordered = sections.flatMap { $0.groups.flatMap(\.entries) }
        guard !ordered.isEmpty else { return }
        let current = ordered.firstIndex { $0.id == selectedID } ?? 0
        selectedID = ordered[(current + offset + ordered.count) % ordered.count].id
    }

    func zoomIn() { zoom = GalleryChrome.zoomSteps.first { $0 > zoom + 0.001 } ?? zoom }
    func zoomOut() { zoom = GalleryChrome.zoomSteps.last { $0 < zoom - 0.001 } ?? zoom }

    func toggleScheme() {
        guard let entry = selectedEntry else { return }
        scheme = environment(for: entry).colorScheme == .dark ? .light : .dark
    }

    /// Loads (or builds and caches) the Figma node index off the main thread.
    func loadFigmaIndex() async {
        guard figmaIndex == nil else { return }
        let started = Date()
        do {
            let index = try await Task.detached(priority: .userInitiated) {
                try FigmaIndex.load(paths: GalleryPaths.locate())
            }.value
            figmaIndex = index
            figmaStatus = String(format: "Figma index: %d nodes, %d frames (%.1f s)",
                                 index.nodes.count, index.frames.count, Date().timeIntervalSince(started))
        } catch {
            figmaStatus = "Figma index unavailable: \(error.localizedDescription)"
            reference = .failed(figmaStatus)
        }
    }

    /// Crops the selected entry's Figma node (off the main thread).
    func refreshReference() async {
        measurement = nil
        guard let entry = selectedEntry else { reference = .none("Nothing selected"); return }
        guard let nodeID = entry.figmaNode else { reference = .none("This entry has no Figma node"); return }
        guard let index = figmaIndex else { reference = .loading; return }
        reference = .loading
        do {
            let crop = try await Task.detached(priority: .userInitiated) {
                try index.reference(for: nodeID, scale: 2)
            }.value
            guard selectedID == entry.id else { return }
            let pointSize = CGSize(width: CGFloat(crop.image.width) / crop.scale, height: CGFloat(crop.image.height) / crop.scale)
            reference = .loaded(crop, NSImage(cgImage: crop.image, size: pointSize))
            if measureOnLoad { measure() }
        } catch {
            reference = .failed(error.localizedDescription)
        }
    }

    /// Starts measuring the selected entry against its Figma crop (see `measureNow()`); a
    /// measurement already running is superseded.
    func measure() {
        measureTask?.cancel()
        measureTask = Task { await measureNow() }
    }

    /// Renders the entry like `mxr-snapshot` does (on the main actor, as SwiftUI requires) and
    /// compares it with the reference off the main actor, so the window stays responsive.
    /// Returns the new measurement, or `nil` if it failed or was superseded, or the selection,
    /// scheme or accent changed meanwhile.
    @discardableResult
    func measureNow() async -> Measurement? {
        guard let entry = selectedEntry, case .loaded(let crop, _) = reference else { return nil }
        let environment = environment(for: entry)
        measureGeneration += 1
        let generation = measureGeneration
        isMeasuring = true
        measureError = nil
        defer { if generation == measureGeneration { isMeasuring = false } }
        let render: CGImage
        do {
            render = try GalleryRenderer.render(entry, scale: crop.scale, environment: environment)
        } catch {
            measureError = "Render failed: \(error.localizedDescription)"
            return nil
        }
        let referenceImage = crop.image
        let scale = crop.scale
        let (comparison, images) = await Task.detached(priority: .userInitiated) {
            ImageComparator.compare(render, referenceImage, scale: scale)
        }.value
        guard generation == measureGeneration, selectedID == entry.id,
              self.environment(for: entry) == environment, let images
        else { return nil }
        let heatmap = NSImage(
            cgImage: images.heatmap,
            size: CGSize(width: CGFloat(images.heatmap.width) / scale, height: CGFloat(images.heatmap.height) / scale)
        )
        let result = Measurement(
            entryID: entry.id, environment: environment, comparison: comparison, heatmap: heatmap,
            images: images, render: render, reference: referenceImage
        )
        measurement = result
        return result
    }

    /// Writes render.png, ref.png, the comparison images and report.txt to the entry's snapshot
    /// directory, measuring first when the last measurement is for another entry, scheme or accent.
    func saveComparison() {
        Task { await saveComparisonNow() }
    }

    private func saveComparisonNow() async {
        guard let entry = selectedEntry, let paths = try? GalleryPaths.locate() else { return }
        var current = measurementIsCurrent ? measurement : await measureNow()
        if current == nil, measurementIsCurrent { current = measurement }  // superseded by a newer one
        guard let measurement = current, measurement.entryID == entry.id else { return }
        let directory = paths.snapshotDirectory(for: entry)
        let render = measurement.render
        let referenceImage = measurement.reference
        let images = measurement.images
        var header = "entry       \(entry.id) (\(measurement.environment.colorScheme == .dark ? "dark" : "light")"
        header += (measurement.environment.accent.map { ", accent \($0)" } ?? "") + ")\n"
        if case .loaded(let crop, _) = reference, crop.node.id == FigmaIndex.normalizedID(entry.figmaNode ?? "") {
            header += "node        \(crop.node.id) \(crop.node.type) \"\(crop.node.name)\"\n"
            header += "frame       \(crop.frame.id) \"\(crop.frame.name)\" → renders/\(crop.frame.renderFile)\n"
            header += crop.warnings.map { "warning     \($0)\n" }.joined()
        }
        let report = header + measurement.comparison.report() + "\n"
        do {
            try await Task.detached(priority: .userInitiated) {
                try GalleryImageIO.writePNG(render, to: directory.appending(path: "render.png"))
                try GalleryImageIO.writePNG(referenceImage, to: directory.appending(path: "ref.png"))
                try images.write(to: directory)
                try report.write(to: directory.appending(path: "report.txt"), atomically: true, encoding: .utf8)
            }.value
            lastSavedDirectory = directory
        } catch {
            measureError = "Save failed: \(error.localizedDescription)"
        }
    }
}
