import MXRCore
import MXRDesign
import Observation
import SwiftUI

/// Discovery is live: a share may appear after the chooser has opened.
@MainActor @Observable
final class LibrarySourceBrowserModel {
    private(set) var category: MediaSourceCategory
    private(set) var sources: [MediaSourceInfo] = []
    private(set) var source: MediaSourceInfo?
    private(set) var path: [MediaSourceNode] = []
    private(set) var nodes: [MediaSourceNode] = []
    private(set) var isLoading = false
    private(set) var error: String?
    @ObservationIgnored private let backend: any MediaSourceBackend
    @ObservationIgnored private var generation = 0

    init(backend: any MediaSourceBackend, category: MediaSourceCategory = .localNetwork) {
        self.backend = backend
        self.category = category
        backend.startDiscovery(in: category)
        sources = backend.sources(in: category)
        backend.addListener(self) { [weak self] event in
            guard let self else { return }
            switch event {
            case .sourcesChanged(let category) where category == self.category:
                self.sources = self.backend.sources(in: category)
                if let current = self.source, !self.sources.contains(where: { $0.id == current.id }) {
                    self.select(category)
                }
            case .childrenChanged(let sourceID, let nodeID)
                where sourceID == self.source?.id:
                Task { [weak self] in await self?.refreshAfterChange(parentID: nodeID) }
            default: break
            }
        }
    }

    func select(_ category: MediaSourceCategory) {
        generation += 1
        self.category = category
        backend.startDiscovery(in: category)
        sources = backend.sources(in: category)
        source = nil; path = []; nodes = []; error = nil; isLoading = false
    }

    func browse(_ source: MediaSourceInfo) async {
        self.source = source
        path = []
        await reload()
    }

    func open(_ node: MediaSourceNode) async {
        guard node.isContainer else { return }
        path.append(node)
        await reload()
    }

    func goBack() async {
        if path.isEmpty { select(category) }
        else { path.removeLast(); await reload() }
    }

    /// Entering another place starts empty; the stale list of a different folder would mislead.
    func reload() async {
        nodes = []
        await loadChildren(refresh: false)
    }

    /// A manual refresh keeps the current list on screen until the new one arrives.
    func manualRefresh() async {
        await loadChildren(refresh: true)
    }

    private func loadChildren(refresh: Bool) async {
        guard let source else { return }
        generation += 1
        let request = generation
        let parent = path.last
        error = nil; isLoading = true
        do {
            let children: [MediaSourceNode]
            if refresh { children = try await backend.refreshChildren(of: parent, in: source) }
            else { children = try await backend.children(of: parent, in: source) }
            guard request == generation else { return }
            nodes = children; isLoading = false
        } catch {
            guard request == generation else { return }
            self.error = error.localizedDescription; isLoading = false
        }
    }

    /// A removal notifies the removed node's parent, so validate ancestors before reusing a path.
    func refreshAfterChange(parentID: String?) async {
        guard let source, parentID == nil || path.contains(where: { $0.id == parentID }) else { return }
        generation += 1
        let request = generation
        let previousPath = path
        error = nil; isLoading = true
        do {
            var children = try await backend.children(of: nil, in: source)
            var validPath: [MediaSourceNode] = []
            for previous in previousPath {
                guard request == generation else { return }
                guard let current = children.first(where: { $0.id == previous.id && $0.isContainer }) else { break }
                validPath.append(current)
                children = try await backend.children(of: current, in: source)
            }
            guard request == generation else { return }
            path = validPath; nodes = children; isLoading = false
        } catch {
            guard request == generation else { return }
            self.error = error.localizedDescription; isLoading = false
        }
    }
}

/// Browser for VLC devices, discovery modules and their live media trees.
public struct MXRMediaSourcesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: LibrarySourceBrowserModel?

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.gap17) {
            HStack {
                Text("Browse Sources").mxrTextStyle(Theme.Font.homeSectionTitle).foregroundStyle(Theme.Color.fgA1)
                Spacer(minLength: 0)
                LibraryIconButton(icon: .close, label: "Close source browser") { dismiss() }
            }
            if let model { browser(model) }
        }
        .padding(Theme.Spacing.gap20)
        .frame(minWidth: Theme.Metric.Library.sidebar.width, minHeight: Theme.Metric.Miniplayer.queue.height)
        .background(Theme.Color.bgB1)
        .task { if model == nil { model = LibrarySourceBrowserModel(backend: app.backends.mediaSources) } }
    }

    private func browser(_ model: LibrarySourceBrowserModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.gap17) {
            HStack(spacing: Theme.Spacing.gap10) {
                ForEach(MediaSourceCategory.allCases, id: \.self) { category in
                    Button(category.title) { model.select(category) }
                        .buttonStyle(.plain)
                        .mxrTextStyle(Theme.Font.body)
                        .foregroundStyle(category == model.category ? Theme.Color.accentMain : Theme.Color.fgA1)
                        .accessibilityAddTraits(category == model.category ? .isSelected : [])
                }
            }
            LibraryDivider()
            if let source = model.source {
                HStack(spacing: Theme.Spacing.gap10) {
                    LibraryIconButton(icon: .arrowLeft, label: "Back") { Task { await model.goBack() } }
                    Text(([source.title] + model.path.map(\.title)).joined(separator: " ▸ "))
                        .mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA1).lineLimit(1)
                    Spacer(minLength: 0)
                    LibraryIconButton(icon: .refresh, label: "Refresh source") { Task { await model.manualRefresh() } }
                }
                if let error = model.error, model.nodes.isEmpty {
                    LibraryMessage(icon: .info, title: "This source can’t be shown", hint: error,
                                   actionTitle: "Try Again") { Task { await model.manualRefresh() } }
                } else if model.nodes.isEmpty {
                    // While discovery is running show nothing rather than a spinner.
                    if !model.isLoading {
                        LibraryMessage(icon: .streaming, title: "Nothing found here yet",
                                       hint: "Items appear as VLC discovers them.")
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Theme.Spacing.gap10) {
                            ForEach(model.nodes) { node in
                                sourceRow(node.title, icon: node.isContainer ? .folder : .video) {
                                    if node.isContainer { Task { await model.open(node) } }
                                    else if let url = URL(string: node.mrl) { app.open(urls: [url]); dismiss() }
                                }
                                .mxrContextMenu(style: .contextMenu) { [app] in
                                    if !node.isContainer, let url = URL(string: node.mrl) {
                                        MXRMenuItem("Add to Queue", icon: .queue) { app.enqueue(urls: [url]) }
                                    }
                                }
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
            } else if model.sources.isEmpty {
                Text("No sources available in \(model.category.title)")
                    .mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA3)
            } else {
                ForEach(model.sources) { source in
                    sourceRow(source.title, icon: .streaming) { Task { await model.browse(source) } }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func sourceRow(_ title: String, icon: MXRIcon.Name, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.gap10) {
                MXRIcon(icon).frame(width: Theme.Metric.Library.thumb.width, height: Theme.Metric.Library.thumb.height)
                Text(title).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA1)
                Spacer(minLength: 0)
                MXRIcon(.chevronRight)
            }
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
}

private extension MediaSourceCategory {
    var title: String {
        switch self {
        case .devices: "Devices"
        case .localNetwork: "Local Network"
        case .internet: "Internet"
        case .myComputer: "My Computer"
        }
    }
}
