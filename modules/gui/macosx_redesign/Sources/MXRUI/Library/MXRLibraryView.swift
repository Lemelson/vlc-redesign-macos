import MXRCore
import MXRDesign
import SwiftUI

/// The compact browsing panel or full library content beneath the app's window bar (S28–S47).
public struct MXRLibraryView: View {
    @Environment(AppModel.self) private var app
    @Environment(LibraryModel.self) private var library
    public let compact: Bool
    @State private var searchVisible = false
    @State private var sheets = LibrarySheetCenter()
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool

    public init(compact: Bool = false) { self.compact = compact }

    public var body: some View {
        GeometryReader { geometry in
            let narrow = compact || geometry.size.width < Theme.Metric.Window.player.width / 2
            // A compact panel narrower than its full header (the 480 pt window gives it 216 pt) leaves
            // out Open Full Library rather than drawing past its column.
            let opensFull = compact && geometry.size.width >= LibraryGeometry.compactFullHeaderWidth
            let contentWidth = Self.contentWidth(geometry.size.width, compact: compact)
            HStack(spacing: 0) {
                LibraryNavigation(compact: compact)
                VStack(alignment: .leading, spacing: Theme.Metric.Library.panel.gap) {
                    header(narrow: narrow, opensFull: opensFull)
                    VStack(spacing: 0) {
                        LibraryDivider(header: true)
                        if searchVisible && narrow { search.padding(.top, Theme.Spacing.gap17) }
                        content(width: contentWidth)
                    }
                }
                .padding(EdgeInsets(top: Theme.Metric.Library.panel.padding.top,
                                    leading: Theme.Metric.Library.panel.padding.leading,
                                    bottom: compact ? Theme.Metric.Library.panel.padding.bottom : 0,
                                    trailing: Theme.Metric.Library.panel.padding.trailing))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background {
                    if compact { MXRBackdropSurface(tint: Theme.Color.bgB1Transparent) }
                    else { Rectangle().fill(Theme.Color.bgB1) }
                }
            }
        }
        .frame(maxWidth: compact ? Theme.Metric.Library.sidebar.width : .infinity)
        .background { if !compact { Rectangle().fill(Theme.Color.bgB1) } }
        .environment(sheets)
        .sheet(item: $sheets.sheet) { sheet in
            LibrarySheetView(sheet: sheet, center: sheets).appModel(app)
        }
        // Edit ▸ Find ▸ Search Library (⌥⌘F; ⌘F stays fullscreen, D040) is the one registration.
        .onChange(of: library.searchFieldRequested, initial: true) { _, requested in
            guard requested else { return }
            library.searchFieldRequested = false
            searchVisible = true; searchFocused = true
        }
    }

    private func header(narrow: Bool, opensFull: Bool) -> some View {
        VStack(spacing: Theme.Metric.Library.headerBlock.gap) {
            HStack(spacing: narrow ? Theme.Metric.Library.headerRow.gap : Theme.Spacing.gap20) {
                HStack(spacing: Theme.Metric.Library.headerRow.gap) {
                    HStack(spacing: Theme.Spacing.gap12) {
                        LibraryIconButton(icon: .arrowLeft, label: "Back", enabled: library.canGoBack) { library.goBack() }
                            .keyboardShortcut("[", modifiers: .command)
                        LibraryIconButton(icon: .arrowRight, label: "Forward", enabled: library.canGoForward) { library.goForward() }
                            .keyboardShortcut("]", modifiers: .command)
                    }
                    LibraryBreadcrumb(compact: narrow)
                }
                if !narrow { headerTools(narrow: false) }
                // Source S45 utility group 2139:8892 is 60pt; S43/S44 use just More24pt.
                HStack(spacing: Theme.Spacing.gap12) {
                    if !narrow && mode == .list { LibraryAddMenu() }
                    LibraryMoreMenu()
                    if opensFull {
                        LibraryIconButton(icon: .open, label: "Open full library", tool: true) { app.interface.library = .full }
                    }
                }
            }
            .frame(height: narrow ? Theme.Metric.Library.headerRow.height : LibraryGeometry.fullHeaderHeight)
            if narrow { HStack { headerTools(narrow: true) }.frame(height: Theme.Metric.Library.headerRow.height) }
        }
    }

    @ViewBuilder private func headerTools(narrow: Bool) -> some View {
        let count = Text(library.countText).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA3).fixedSize()
            .opacity(library.hasLoaded || library.contentLocation == library.location ? 1 : 0)
        if narrow {
            // The count gives way before the tools in a panel too narrow for both.
            ViewThatFits(in: .horizontal) { count; Color.clear.frame(width: 0, height: 0) }
            Spacer(minLength: 0)
        } else {
            count
        }
        HStack(spacing: narrow ? Theme.Spacing.gap12 : Theme.Spacing.gap20) {
            if !library.availableSorts.isEmpty { LibrarySortMenu() }
            LibraryViewMenu(compact: compact)
            if narrow {
                LibraryIconButton(icon: .search, label: "Search library", active: searchVisible, tool: true) {
                    searchVisible.toggle(); searchFocused = searchVisible
                    if !searchVisible { library.searchText = "" }
                }
            } else { search.frame(width: LibraryGeometry.searchWidth) }
        }
    }

    private var search: some View {
        @Bindable var library = library
        return HStack(spacing: Theme.Spacing.gap10) {
            MXRIcon(.search, tint: Theme.Color.fgA3)
            // AppKit draws a TextField prompt in its own placeholder gray; Figma's is FG/A4 (1040:2864).
            TextField("", text: $library.searchText).textFieldStyle(.plain)
                .font(Theme.Font.body.font).foregroundStyle(Theme.Color.fgA1)
                .focused($searchFocused).accessibilityLabel("Search library")
                .background(alignment: .leading) {
                    if library.searchText.isEmpty {
                        Text(searchPrompt).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA4)
                            .lineLimit(1).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
            if !library.searchText.isEmpty {
                LibraryIconButton(icon: .close, label: "Clear search") { library.searchText = "" }
            }
        }
        .padding(.horizontal, Theme.Spacing.gap8)
        .frame(height: LibraryGeometry.fullHeaderHeight)
        .background(Theme.Color.bgA5, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .onExitCommand { library.searchText = ""; searchVisible = false; searchFocused = false }
    }

    /// Figma 1040:2864: "Search". The scope shows in the address line ("Results for …").
    private var searchPrompt: String { "Search" }

    @ViewBuilder private func content(width: CGFloat) -> some View {
        if let error = library.errorMessage, library.contentLocation == library.location {
            LibraryMessage(icon: .info, title: "This part of the library can’t be shown", hint: error,
                           actionTitle: "Try Again") { library.reload() }
        } else if library.showsHome {
            if library.homeSections.isEmpty { if library.hasLoaded && !library.isLoading { empty } } else { home }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.gap10) {
                        if let notice = library.importNotice, library.contentLocation == notice.shownAt { importNoticeRow(notice) }
                        if let action = library.addAction { addRow(action) }
                        if library.entries.isEmpty {
                            // While a place is first loading, show nothing rather than a spinner.
                            if library.hasLoaded && !library.isLoading { empty }
                        }
                        else if mode == .grid { grid(width: width) }
                        else if compact { list }
                        else { fullList(width: width) }
                    }
                    .padding(.vertical, !compact && mode == .list ? Theme.Spacing.gap20 + Theme.Spacing.gap10 : Theme.Spacing.gap20)
                }
                .scrollIndicators(.hidden)
                .focusable()
                .focusEffectDisabled()
                .focused($listFocused)
                // ↑/↓ move by a row (a grid row holds `columns` entries), ←/→ by one entry.
                .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
                    guard let offset = Self.arrowOffset(press.key, columns: columns(width: width)) else { return .ignored }
                    return move(offset, press, proxy)
                }
                .onKeyPress(.return) { openSelection() }
                .onKeyPress(.escape) {
                    guard !library.selection.isEmpty else { return .ignored }
                    library.selection = []; return .handled
                }
            }
        }
    }

    private func move(_ offset: Int, _ press: KeyPress, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        guard let entry = library.moveSelection(by: offset, extending: press.modifiers.contains(.shift)) else { return .ignored }
        proxy.scrollTo(entry.id)
        return .handled
    }

    /// Return opens a selected container or plays the selected media (in display order).
    private func openSelection() -> KeyPress.Result {
        let selected = library.entries.filter { library.selection.contains($0.id) }
        guard let first = selected.first else { return .ignored }
        if selected.count == 1 || first.media == nil { MXRLibraryActions.open(first, app: app) }
        else { MXRLibraryActions.play(selected.compactMap(\.media), app: app) }
        return .handled
    }

    private var mode: LibraryViewMode { compact ? library.compactViewMode : library.fullViewMode }
    private func row(_ index: Int, _ entry: LibraryEntry) -> some View {
        LibraryEntryView(entry: entry, progressForAll: false, rowIndex: index) { listFocused = true }.id(entry.id)
    }
    /// Entry identity, not position: a row's hover and open-menu state must follow its entry when rows
    /// above it are removed or inserted. Playlist rows carry their occurrence; a stream (or a playlist
    /// with items on a disconnected drive) can still list one media twice, so repeats get a suffix.
    private var indexedEntries: [(offset: Int, key: String, element: LibraryEntry)] {
        var seen: [String: Int] = [:]
        return library.entries.enumerated().map { index, entry in
            let repeats = seen[entry.id, default: 0]
            seen[entry.id] = repeats + 1
            return (index, repeats == 0 ? entry.id : "\(entry.id)#\(repeats)", entry)
        }
    }
    private var list: some View {
        LazyVStack(spacing: Theme.Spacing.gap10) {
            ForEach(indexedEntries, id: \.key) { index, _, entry in row(index, entry) }
        }
    }

    private func columns(width: CGFloat) -> Int {
        Self.columns(mode: mode, compact: compact, music: library.category == .music, width: width)
    }
    private func listLayout(width: CGFloat) -> (rowWidth: CGFloat, count: Int) { Self.listLayout(width: width) }
    private func gridLayout(width available: CGFloat) -> (width: CGFloat, count: Int) {
        Self.gridLayout(width: available, compact: compact, music: library.category == .music)
    }

    private func fullList(width: CGFloat) -> some View {
        let (rowWidth, count) = listLayout(width: width)
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(rowWidth), spacing: Theme.Spacing.gap10), count: count), alignment: .leading, spacing: Theme.Spacing.gap10) {
            ForEach(indexedEntries, id: \.key) { index, _, entry in row(index, entry) }
        }
    }

    private func grid(width available: CGFloat) -> some View {
        let (width, count) = gridLayout(width: available)
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: Theme.Spacing.gap20, alignment: .topLeading), count: count), alignment: .leading, spacing: LibraryGeometry.gridRowGap) {
            ForEach(indexedEntries, id: \.key) { index, _, entry in
                LibraryEntryView(entry: entry, cardSize: cardSize(for: entry, width: width), showSubtitle: true, progressForAll: false, rowIndex: index) { listFocused = true }
                    .id(entry.id)
            }
        }
    }

    /// Square art for music (album, artist, song) and folder tiles; 16:9 for video.
    private func cardSize(for entry: LibraryEntry, width: CGFloat) -> CGSize {
        let square = entry.media?.kind == .audio || entry.mxrIcon == .album || entry.mxrIcon == .artist || entry.mxrIcon == .genre
        guard square else { return CGSize(width: width, height: width * Theme.Metric.Library.homeCard.height / Theme.Metric.Library.homeCard.width) }
        let side = compact ? width : min(width, LibraryGeometry.squareCard)
        return CGSize(width: side, height: side)
    }

    private var home: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: compact ? LibraryGeometry.compactSectionGap : LibraryGeometry.homeSectionGap) {
                // Every section in both sizes (compact Figma 1106:5633 lists all five); compact shows three rows each.
                ForEach(library.homeSections) { section in
                    VStack(alignment: .leading, spacing: compact ? LibraryGeometry.compactHeadingGap : 0) {
                        Button {
                            if let destination = section.destination { library.navigate(to: destination) }
                        } label: {
                            HStack(spacing: Theme.Spacing.gap5) {
                                Text(section.title).mxrTextStyle(compact ? Theme.Font.bodyLarge : Theme.Font.homeSectionTitle)
                                    .foregroundStyle(Theme.Color.fgA1)
                                if compact { Spacer(minLength: 0) }
                                if section.destination != nil { MXRIcon(.chevronRight) }
                            }
                            .frame(height: compact ? Theme.Metric.Library.thumb.height : Theme.Metric.iconSize)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).disabled(section.destination == nil)
                        .accessibilityLabel(section.destination == nil ? section.title : "Show all \(section.title)")
                        if compact {
                            LazyVStack(spacing: Theme.Spacing.gap10) {
                                ForEach(Array(section.entries.prefix(3))) { LibraryEntryView(entry: $0, restingColor: Theme.Color.fgA3) }
                            }
                        } else {
                            ScrollView(.horizontal) {
                                HStack(alignment: .top, spacing: Theme.Spacing.gap20) {
                                    // Backends cap each row to LibraryHomeSectionKind.homeLimit.
                                    ForEach(section.entries) { entry in
                                        let square = section.kind != .continueWatching
                                        LibraryEntryView(entry: entry,
                                            cardSize: square ? CGSize(width: LibraryGeometry.squareCard, height: LibraryGeometry.squareCard) : Theme.Metric.Library.homeCard.size,
                                            showSubtitle: section.kind == .listenAgain, homeCard: section.kind == .listenAgain,
                                            restingColor: Theme.Color.fgA1)
                                    }
                                }.padding(.vertical, Theme.Spacing.gap20)
                            }.scrollIndicators(.hidden).scrollClipDisabled()
                        }
                    }
                    .padding(.vertical, compact ? 0 : Theme.Spacing.gap20)
                }
            }
            .padding(.top, compact ? Theme.Spacing.gap20 : LibraryGeometry.homeSectionGap)
            .padding(.bottom, Theme.Spacing.gap20)
        }.scrollIndicators(.hidden)
    }

    /// A mixed import lands in Videos; this row says where its songs went and opens them (selected).
    private func importNoticeRow(_ notice: LibraryImportNotice) -> some View {
        HStack(spacing: Theme.Spacing.gap10) {
            MXRIcon(.songs).frame(width: Theme.Metric.Library.thumb.width, height: Theme.Metric.Library.thumb.height)
            Button { library.showImportedSongs() } label: {
                Text(notice.message).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA2)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Show the songs in Music ▸ Songs")
            .accessibilityLabel(notice.message).accessibilityHint("Shows them in Music ▸ Songs")
            LibraryIconButton(icon: .close, label: "Dismiss") { library.dismissImportNotice() }
        }
    }

    private func addRow(_ action: LibraryAddAction) -> some View {
        Button { MXRLibraryActions.add(action, app: app) } label: {
            HStack(spacing: Theme.Spacing.gap10) {
                MXRIcon(.add).frame(width: Theme.Metric.Library.thumb.width, height: Theme.Metric.Library.thumb.height)
                Text(action.title).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA3)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(action.title)
    }

    /// Empty states per place (the design is silent; reuse the design system and say what to do next).
    @ViewBuilder private var empty: some View {
        if !library.appliedSearch.isEmpty {
            LibraryMessage(icon: .search, title: "No results for “\(library.appliedSearch)”",
                           hint: library.location == .home ? "Check the spelling, or try a shorter word." : "Search Home to look through the whole library.",
                           actionTitle: "Clear Search") { library.searchText = "" }
        } else {
            switch library.location {
            case .home where library.totalCount > 0:
                // Indexed media but nothing played yet: Home fills as the user watches and listens.
                LibraryMessage(icon: .home, title: "Nothing played yet",
                               hint: "What you watch and listen to shows up here. Start with your videos.",
                               actionTitle: "Open Videos") { library.navigate(to: .videos) }
            case .home:
                LibraryMessage(icon: .home, title: "Your library is empty",
                               hint: "Add a folder of videos or music. What you play next shows up here.",
                               actionTitle: "Add Folder…") { app.interface.request(.addLibraryFolder) }
            case .videos:
                LibraryMessage(icon: .videos, title: "No video folders yet",
                               hint: "Add a folder that contains videos. VLC keeps its subfolders as they are on disk.",
                               actionTitle: "Add Folder…") { app.interface.request(.addLibraryFolder) }
            case .songs, .music:
                LibraryMessage(icon: .songs, title: "No music folders yet",
                               hint: "Add a folder that contains music to browse it by song, album, artist and genre.",
                               actionTitle: "Add Folder…") { app.interface.request(.addLibraryFolder) }
            case .albums, .artists, .genres:
                LibraryMessage(icon: library.location == .albums ? .album : library.location == .artists ? .artist : .genre,
                               title: "Nothing here yet", hint: "Albums, artists and genres come from the tags of the music in your library.")
            case .folder(let id):
                LibraryMessage(icon: .folder, title: "This folder is empty",
                               hint: "Files added to it on disk appear after the next scan.",
                               actionTitle: "Resync") { library.rescan(id) }
            case .playlist:
                LibraryMessage(icon: .playlist, title: "This playlist is empty",
                               hint: "Use Add to Playlist from any file’s menu to add to it.")
            case .playlists:
                LibraryMessage(icon: .playlist, title: "No playlists yet", hint: "Create one to keep files together in your own order.")
            case .network, .stream:
                LibraryMessage(icon: .streaming, title: "No saved streams", hint: "Add a link to a stream or an m3u playlist to keep it here.")
            case .homeSection, .recent:
                LibraryMessage(icon: .recent, title: "Nothing played yet", hint: "Files and streams you play appear here, newest first.")
            case .album, .artist, .genre, .show:
                LibraryMessage(icon: library.category.mxrIcon, title: "Nothing here yet")
            }
        }
    }
}

/// The layout the content draws and the arrow keys follow (E-07): one source for both.
extension MXRLibraryView {
    /// Width left for entries beside the navigation column, inside the panel padding.
    static func contentWidth(_ total: CGFloat, compact: Bool) -> CGFloat {
        let navigation = compact ? Theme.Metric.Library.rail.width : Theme.Metric.Library.fullWindowNavColumn.width
        return max(0, total - navigation - Theme.Metric.Library.panel.padding.leading - Theme.Metric.Library.panel.padding.trailing)
    }
    static func listLayout(width: CGFloat) -> (rowWidth: CGFloat, count: Int) {
        let rowWidth = min(width, LibraryGeometry.fullListRowWidth)
        return (rowWidth, max(1, Int((width + Theme.Spacing.gap10) / (rowWidth + Theme.Spacing.gap10))))
    }
    static func gridLayout(width available: CGFloat, compact: Bool, music: Bool) -> (width: CGFloat, count: Int) {
        // Music pages use the Home music cards (200 pt squares, 6272:13899); video uses 316 pt tiles (970:4081).
        let full = music ? LibraryGeometry.squareCard : Theme.Metric.Library.homeCard.width
        let width = min(available, compact ? Theme.Metric.Library.headerRow.width / 2 - Theme.Spacing.gap10 : full)
        return (width, max(1, Int((available + Theme.Spacing.gap20) / (width + Theme.Spacing.gap20))))
    }
    /// Entries per drawn row: the compact list is one column.
    static func columns(mode: LibraryViewMode, compact: Bool, music: Bool, width: CGFloat) -> Int {
        if mode == .grid { return gridLayout(width: width, compact: compact, music: music).count }
        return compact ? 1 : listLayout(width: width).count
    }
    /// ↑/↓ move by a drawn row (`columns` entries), ←/→ by one entry.
    static func arrowOffset(_ key: KeyEquivalent, columns: Int) -> Int? {
        switch key {
        case .upArrow: -columns
        case .downArrow: columns
        case .leftArrow: -1
        case .rightArrow: 1
        default: nil
        }
    }
}
