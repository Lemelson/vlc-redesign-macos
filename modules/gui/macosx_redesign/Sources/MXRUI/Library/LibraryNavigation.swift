import MXRCore
import MXRDesign
import SwiftUI

struct LibraryNavigation: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    let compact: Bool
    @State private var addPresented = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: compact ? .center : .leading, spacing: Theme.Metric.Library.rail.gap) {
                ForEach(LibraryCategory.allCases, id: \.self) { category in
                    navButton(icon: category.mxrIcon, title: category.title, selected: app.library.category == category) {
                        app.library.select(category)
                    }
                }
                if !app.pins.pins.isEmpty {
                    LibraryDivider().padding(.vertical, Theme.Spacing.gap4)
                    ForEach(app.pins.pins) { pin in
                        Button { open(pin) } label: {
                            HStack(spacing: Theme.Spacing.gap8) {
                                pinIcon(pin)
                                if !compact { Text(pin.title).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA1).lineLimit(1) }
                            }
                            .frame(height: Theme.Metric.Library.thumb.height)
                            .frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain).help(pin.title).accessibilityLabel(pin.title)
                        .mxrContextMenu(style: .contextMenu) { [app] in MXRMenuItem("Unpin") { app.pins.unpin(pin) } }
                    }
                }
                Button { addPresented.toggle() } label: {
                    HStack(spacing: Theme.Spacing.gap8) {
                        MXRIcon(.add).frame(width: Theme.Metric.ControlBar.iconButton.width, height: Theme.Metric.Library.thumb.height)
                        if !compact { Text("Add item").mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA2) }
                    }
                    .frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .mxrLibraryPopup(isPresented: $addPresented, kind: .add, placement: .above(.leading))
                .accessibilityLabel(compact ? "Add pin" : "Add item")
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
            .padding(compact ? Theme.Metric.Library.rail.padding : Theme.Metric.Library.fullWindowNavCard.padding)
        }
        .scrollIndicators(.hidden)
        .frame(width: compact ? Theme.Metric.Library.rail.width : Theme.Metric.Library.fullWindowNavCard.width)
        // Light player I2425:13646;848:1867 overrides the compact rail paint with translucent BG/A3.
        .background {
            if compact && colorScheme == .light { MXRBackdropSurface(tint: Theme.Color.bgA3Transparent) }
            else { RoundedRectangle(cornerRadius: compact ? 0 : Theme.Radius.lg).fill(Theme.Color.bgA4) }
        }
        .padding(compact ? .zero : Theme.Metric.Library.fullWindowNavColumn.padding)
    }

    private func navButton(icon: MXRIcon.Name, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.gap8) {
                MXRIcon(icon, state: navIconState(icon, selected: selected))
                    // Videos wrapper is 32pt (970:4050); other source wrappers are 30pt.
                    .frame(width: icon == .videos ? Theme.Metric.Library.thumb.width : Theme.Metric.ControlBar.iconButton.width, height: Theme.Metric.Library.thumb.height)
                if !compact { Text(title).mxrTextStyle(Theme.Font.body).foregroundStyle(selected && icon == .home ? Theme.Color.fg2 : Theme.Color.fgA2) }
            }
            .frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(title).accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func navIconState(_ icon: MXRIcon.Name, selected: Bool) -> MXRIcon.State {
        guard selected else { return .default }
        switch icon {
        case .songs:
            // Music root 858:5005 uses accent 87:1009; Songs/My Songs use base 470:592.
            return compact && app.library.location == .music ? .active : .selected
        case .videos:
            // The Videos root 848:1997 uses the accent like Music's root; its folders use base (848:1995).
            return compact && app.library.location == .videos ? .active : .selected
        default: return .active
        }
    }

    @ViewBuilder private func pinIcon(_ pin: Pin) -> some View {
        switch pin.target {
        case .media(let media): LibraryArtwork(entry: .media(media), size: Theme.Metric.Library.thumb.size)
        case .location(let location):
            MXRIcon(location.category == .playlists ? .playlist : location.category == .network ? .streaming : .folder)
                .frame(width: Theme.Metric.ControlBar.iconButton.width, height: Theme.Metric.Library.thumb.height)
        }
    }

    private func open(_ pin: Pin) {
        switch pin.target {
        case .location(let location): app.library.navigate(to: location)
        case .media(let media): app.play(media)
        }
    }
}

struct LibraryBreadcrumb: View {
    @Environment(LibraryModel.self) private var library
    let compact: Bool
    @State private var showsHiddenCrumbs = false

    var body: some View {
        Group {
            if compact {
                // A narrow panel folds crumbs into "..." rather than clipping them to unreadable
                // pieces ("Th ▸ S0"): the last two (Figma S28), then the current one, then none.
                ViewThatFits(in: .horizontal) {
                    ForEach(Self.compactCrumbCounts(library.breadcrumb.count, searching: !library.appliedSearch.isEmpty), id: \.self) { count in
                        row(crumbs: Array(library.breadcrumb.suffix(count)))
                    }
                }
            } else {
                row(crumbs: library.breadcrumb)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// How many trailing crumbs the compact panel tries, widest first. Search results show only
    /// their own place after the current crumb (S47); the last choice keeps just "...".
    static func compactCrumbCounts(_ total: Int, searching: Bool) -> [Int] {
        let widest = min(total, searching ? 1 : 2)
        return Array((0...widest).reversed())
    }

    private func row(crumbs: [LibraryCrumb]) -> some View {
        HStack(spacing: Theme.Spacing.gap6) {
            if compact, library.breadcrumb.count > crumbs.count {
                // The hidden parent folders, in the design-system text menu (D025).
                Button { showsHiddenCrumbs.toggle() } label: {
                    Text("...").mxrTextStyle(Theme.Font.bodyLarge).foregroundStyle(Theme.Color.fgA2)
                        .libraryHeaderDarkStyle()
                }
                .buttonStyle(.plain).fixedSize()
                .help("Show enclosing folders").accessibilityLabel("Enclosing folders")
                .mxrPopupMenu(isPresented: $showsHiddenCrumbs, placement: .below(.leading), style: .textMenu) { [library] in
                    library.breadcrumb.dropLast(crumbs.count).map { crumb in
                        MXRMenuItem(crumb.title) { library.navigate(to: crumb.location) }
                    }
                }
                .frame(width: LibraryGeometry.collapsedBreadcrumbWidth, alignment: .leading)
                if !crumbs.isEmpty || !library.appliedSearch.isEmpty { separator }
            }
            ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                if index > 0 { separator }
                Button { library.navigate(to: crumb.location) } label: {
                    let currentFullCrumb = !compact && crumbs.count > 1 && index == crumbs.count - 1 && library.appliedSearch.isEmpty
                    Text(crumb.title).mxrTextStyle(currentFullCrumb ? LibraryBreadcrumbTypography.current : Theme.Font.bodyLarge)
                        .foregroundStyle(currentFullCrumb ? Theme.Color.fgA1 : Theme.Color.fgA2).lineLimit(1)
                }.buttonStyle(.plain).help(crumb.title)
            }
            if !library.appliedSearch.isEmpty {
                // Search results are a place of their own in the address line (S47).
                separator
                Text("Results for “\(library.appliedSearch)”")
                    .mxrTextStyle(compact ? Theme.Font.bodyLarge : LibraryBreadcrumbTypography.current)
                    .foregroundStyle(Theme.Color.fgA1).lineLimit(1).truncationMode(.middle)
            }
        }
    }

    private var separator: some View {
        Text("▶").mxrTextStyle(Theme.Font.thumbGlyph).foregroundStyle(Theme.Color.fgA4)
            .libraryHeaderDarkStyle()
            .frame(width: LibraryGeometry.crumbSeparatorWidth)
    }
}

extension View {
    /// The library header's "▶" separators, "..." slot and divider keep their Dark styles in both
    /// themes: Player - Light (2425:13624) draws them with Dark/FG/A4 (6131:13620, 6131:13475),
    /// Dark/FG/A2 (6131:13671) and Dark/Divider/Dim (I2425:13646;6784:16224), like every dark
    /// frame. The crumbs, rows and counts around them use Light styles (D032).
    func libraryHeaderDarkStyle() -> some View { environment(\.colorScheme, .dark) }
}

private enum LibraryBreadcrumbTypography {
    // Current full-library breadcrumb 6153:13631 /6153:13649.
    static let current = Theme.TextStyle(name: "libraryCurrentCrumb", family: .inter, weight: 600,
                                        size: 16, lineHeight: 19.363636016845703)
}

struct LibrarySortMenu: View {
    @Environment(LibraryModel.self) private var library
    @State private var presented = false
    var body: some View {
        LibraryIconButton(icon: .sort, label: "Sorting Options", active: presented || library.hasCustomSort, tool: true) { presented.toggle() }
            .mxrLibraryPopup(isPresented: $presented, kind: .sort)
    }
}

struct LibraryViewMenu: View {
    @Environment(LibraryModel.self) private var library
    let compact: Bool
    @State private var presented = false
    var body: some View {
        LibraryIconButton(icon: current == .grid ? .grid : .list, label: "View Options", active: presented, tool: true) { presented.toggle() }
            .mxrLibraryPopup(isPresented: $presented, kind: .view(compact: compact))
    }
    private var current: LibraryViewMode { compact ? library.compactViewMode : library.fullViewMode }
}

struct LibraryMoreMenu: View {
    @Environment(LibraryModel.self) private var library
    @State private var presented = false
    @State private var sourcesPresented = false
    var body: some View {
        LibraryIconButton(icon: .more, label: "More library actions", active: presented, tool: true) { presented.toggle() }
            .mxrLibraryPopup(isPresented: $presented, kind: .folder) {
                library.category == .network
                    ? [MXRMenuItem("Browse Devices & Network Sources…", icon: .streaming) { sourcesPresented = true }]
                    : []
            }
            .sheet(isPresented: $sourcesPresented) { MXRMediaSourcesView() }
    }
}

struct LibraryAddMenu: View {
    @State private var presented = false
    var body: some View {
        LibraryIconButton(icon: .add, label: "Add library item", active: presented, tool: true) { presented.toggle() }
            .mxrLibraryPopup(isPresented: $presented, kind: .add)
    }
}
