import Foundation
import Observation

/// Library browsing for the compact panel (S28–S42), the full-window library (S43–S45, S47) and the
/// Add Subtitles dialog's file lists. Paged: call ``loadMoreIfNeeded(after:)`` from row `onAppear`.
///
/// Content is replaced atomically: the breadcrumb, entries, count and "+" row of a location are applied
/// together when its first page arrives. Until then the previous content stays on screen (a refresh never
/// blanks the page, and navigation never flashes a spinner); a location that takes longer than
/// ``staleContentLimit`` to answer is cleared so old rows are not mistaken for the new place.
@MainActor
@Observable
public final class LibraryModel {
    /// What was asked for (navigation state).
    public private(set) var location: LibraryLocation = .home
    /// The location the visible content belongs to. Equal to ``location`` once it has loaded.
    public private(set) var contentLocation: LibraryLocation = .home
    /// "Videos ▸ Shows ▸ The Wand ▸ S01" (root first), for ``contentLocation``.
    public private(set) var breadcrumb: [LibraryCrumb] = [LibraryCrumb(title: "Home", location: .home)]
    /// Entries loaded so far (a prefix of the full result).
    public private(set) var entries: [LibraryEntry] = []
    /// Total number of entries at the location ("15 items").
    public private(set) var totalCount: Int = 0
    /// The "+" row of the page, if any.
    public private(set) var addAction: LibraryAddAction?
    /// Home sections, filled when `contentLocation == .home` and no search is active.
    public private(set) var homeSections: [LibraryHomeSection] = []
    /// True while a load for the current location is in flight.
    public private(set) var isLoading = false
    /// True once ``location`` (with the current search) has been answered at least once.
    public private(set) var hasLoaded = false
    /// True while a next page is being fetched (show a spinner row at the end).
    public private(set) var isLoadingMore = false
    public private(set) var errorMessage: String?
    public private(set) var backStack: [LibraryLocation] = []
    public private(set) var forwardStack: [LibraryLocation] = []
    /// Sort per category (the sort menu shows a ✓ on the current one).
    public private(set) var sorts: [LibraryCategory: LibrarySort] = LibraryModel.defaultSorts
    /// The sort each category opens with; the sort button is only marked when the user changed it.
    public static let defaultSorts: [LibraryCategory: LibrarySort] = [
        .videos: .unwatchedFirst, .music: .oldestFirst, .network: .oldestFirst, .playlists: .oldestFirst,
        .recent: .newestFirst, .home: .newestFirst,
    ]
    /// Whether the current category uses a sort other than the one it opens with.
    public var hasCustomSort: Bool { sort != (Self.defaultSorts[category] ?? .titleAscending) }
    /// Saved playlists for "Add to Playlist" menus, kept fresh on playlist changes.
    public private(set) var playlists: [Playlist] = []
    /// Selected rows (entry ids). A single click selects, ⌘/⇧-click extend; double-click or Return plays.
    public var selection: Set<LibraryEntry.ID> = []
    /// Anchor of a ⇧-click range.
    @ObservationIgnored public var selectionAnchor: LibraryEntry.ID?
    /// The media an open "Add Audio File" panel attaches its files to (Edit / Add Audio Tracks,
    /// ``AppModel/presentAddAudioTracks(media:)``); empty for the player's own Add Audio File.
    @ObservationIgnored public var audioTrackTargets: [MediaItem] = []
    /// View mode of the compact panel (list in the design).
    public var compactViewMode: LibraryViewMode = .list
    /// View mode of the full-window library (grid in the design).
    public var fullViewMode: LibraryViewMode = .grid
    /// Search field text. Changing it reloads after ``searchDebounce``.
    public var searchText: String = "" {
        didSet { if searchText != oldValue, !isResettingSearch { scheduleSearch() } }
    }
    /// Set by Edit ▸ Find ▸ Search Library (⌥⌘F, D040): the library view shows and focuses its search
    /// field, then clears this.
    public var searchFieldRequested = false
    /// The search the shown content answers ("Results for …"); empty when not searching.
    public private(set) var appliedSearch: String = ""

    /// Page size of queries.
    @ObservationIgnored public var pageSize = 100
    @ObservationIgnored public var searchDebounce: Duration = .milliseconds(250)
    /// How long previous content may stand in for a location that is still loading.
    @ObservationIgnored public var staleContentLimit: Duration = .milliseconds(400)
    @ObservationIgnored public let backend: any LibraryBackend
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var moreTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var clearTask: Task<Void, Never>?
    @ObservationIgnored private var playlistsTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    /// Identifies the current load-more request; a finished request only clears ``moreTask`` if it is still current.
    @ObservationIgnored private var moreToken = 0
    @ObservationIgnored private var isResettingSearch = false
    @ObservationIgnored private var playlistsLoaded = false
    private var paginationExhausted = false

    public init(backend: any LibraryBackend, initialLocation: LibraryLocation = .home) {
        self.backend = backend
        self.location = initialLocation
        self.contentLocation = initialLocation
        backend.addListener(self) { [weak self] event in
            self?.handle(event)
        }
        reload()
    }

    // MARK: Derived

    /// The rail category to highlight (root of the breadcrumb). A folder belongs to Videos or to
    /// Music ▸ Songs; until its breadcrumb is known it stays in the category it was opened from.
    public var category: LibraryCategory {
        if contentLocation == location { return breadcrumb.first?.location.category ?? location.category }
        if case .folder = location { return breadcrumb.first?.location.category ?? location.category }
        return location.category
    }

    private func category(of location: LibraryLocation, crumbs: [LibraryCrumb]?) -> LibraryCategory {
        if let root = crumbs?.first { return root.location.category }
        return location == self.location ? category : location.category
    }
    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }
    /// The current sort.
    public var sort: LibrarySort { sorts[category] ?? .titleAscending }
    /// Sorts offered by the sort menu here.
    public var availableSorts: [LibrarySort] { LibrarySort.available(at: location, category: category) }
    public var hasMore: Bool { !paginationExhausted && entries.count < totalCount }
    /// "15 items" / "1 item".
    public var countText: String { totalCount == 1 ? "1 item" : "\(totalCount) items" }
    /// The current location's title (last crumb).
    public var title: String { breadcrumb.last?.title ?? category.title }
    /// Media entries only.
    public var mediaEntries: [MediaItem] { entries.compactMap(\.media) }
    /// True when the Home sections are what is shown (Home without a search).
    public var showsHome: Bool { contentLocation == .home && appliedSearch.isEmpty }
    /// The selected media in display order.
    public var selectedMedia: [MediaItem] { entries.filter { selection.contains($0.id) }.compactMap(\.media) }

    // MARK: Navigation

    /// Shows `location`, pushing the current one on the back stack.
    public func navigate(to location: LibraryLocation) {
        guard location != self.location else { return }
        backStack.append(self.location)
        forwardStack.removeAll()
        show(location)
    }

    /// Shows a category root (rail click).
    public func select(_ category: LibraryCategory) { navigate(to: category.location) }

    /// Shows the folder that contains `media`, if the library knows it (VIDEO_BREAKDOWN §08: the
    /// sidebar toggle and the folder chip open the compact library "at the current folder").
    public func reveal(_ media: MediaItem?) {
        guard let folder = media?.folder else { return }
        navigate(to: .folder(folder.id))
    }

    public func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(location)
        show(previous)
    }

    public func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(location)
        show(next)
    }

    /// Activates an entry: navigates into containers and returns nil, or returns the media to play.
    @discardableResult
    public func open(_ entry: LibraryEntry) -> MediaItem? {
        if let destination = entry.destination {
            navigate(to: destination)
            return nil
        }
        if case .stream(let stream) = entry, let url = stream.urls.first {
            var media = MediaItem(url: url)
            media.title = stream.name
            return media
        }
        return entry.media
    }

    public func setSort(_ sort: LibrarySort) {
        guard sorts[category] != sort else { return }
        sorts[category] = sort
        reload()
    }

    // MARK: Selection

    /// Click handling: plain click selects one row, ⌘ toggles, ⇧ extends from the anchor.
    public func select(_ entry: LibraryEntry, extending: Bool = false, toggling: Bool = false) {
        if toggling {
            if selection.contains(entry.id) { selection.remove(entry.id) } else { selection.insert(entry.id) }
            selectionAnchor = entry.id
        } else if extending, let anchor = selectionAnchor,
                  let from = entries.firstIndex(where: { $0.id == anchor }), let to = entries.firstIndex(where: { $0.id == entry.id }) {
            selection = Set(entries[min(from, to)...max(from, to)].map(\.id))
        } else {
            selection = [entry.id]
            selectionAnchor = entry.id
        }
    }

    /// ↑/↓: moves (or with ⇧ extends) the selection by one row and returns the newly focused entry.
    @discardableResult
    public func moveSelection(by offset: Int, extending: Bool = false) -> LibraryEntry? {
        guard !entries.isEmpty else { return nil }
        let current = entries.lastIndex(where: { selection.contains($0.id) && $0.id == selectionFocus })
            ?? entries.lastIndex(where: { selection.contains($0.id) })
        let index = current.map { min(max($0 + offset, 0), entries.count - 1) } ?? (offset > 0 ? 0 : entries.count - 1)
        let entry = entries[index]
        if extending, selectionAnchor != nil {
            let anchor = selectionAnchor
            select(entry, extending: true)
            selectionAnchor = anchor
        } else {
            select(entry)
        }
        selectionFocus = entry.id
        loadMoreIfNeeded(at: index)
        return entry
    }
    @ObservationIgnored private var selectionFocus: LibraryEntry.ID?
    /// Rows to select once `location` shows (files just imported).
    @ObservationIgnored private var pendingSelection: (location: LibraryLocation, ids: Set<LibraryEntry.ID>)?
    /// After an import of videos and songs together: the songs are listed under Music ▸ Songs, not
    /// in Videos where the import landed, so Videos says so (and offers to show them).
    public private(set) var importNotice: LibraryImportNotice?

    // MARK: Loading

    /// Reloads the current location from the first page.
    ///
    /// - Parameter keepingLoaded: re-query everything loaded so far in one request instead of only
    ///   the first page, so rows past ``pageSize`` do not disappear while scrolling. Used for library
    ///   events (indexing, progress updates); sort, search and navigation start over at page one.
    public func reload(keepingLoaded: Bool = false) {
        loadTask?.cancel()
        cancelLoadMore()
        generation += 1
        let generation = self.generation
        let location = self.location
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        paginationExhausted = false
        let limit = keepingLoaded ? max(pageSize, entries.count) : pageSize
        let cachedCrumbs = backend.cachedBreadcrumb(for: location)
        let query = LibraryQuery(sort: sorts[category(of: location, crumbs: cachedCrumbs)] ?? .titleAscending,
                                 searchText: search, offset: 0, limit: limit)
        let wantsHome = location == .home && search.isEmpty
        errorMessage = nil

        // Synchronously available content (scripted backends) applies before the first frame.
        if wantsHome, let sections = backend.cachedHomeSections() {
            applyHome(sections, crumbs: cachedCrumbs, location: location, search: search)
        } else if !wantsHome, let page = backend.cachedPage(at: location, query: query) {
            applyPage(page, crumbs: cachedCrumbs, search: search)
        }
        isLoading = true
        scheduleStaleClear(generation: generation)

        let backend = self.backend
        loadTask = Task { @MainActor [weak self] in
            // Crumbs and content are applied together, so the address line never names a place whose
            // rows are not shown yet.
            let trail = await backend.breadcrumb(for: location)
            // A superseded load must not hit the backend for a page nobody will see.
            guard !Task.isCancelled else { return }
            // The sort belongs to the category the breadcrumb names (a folder under Songs sorts as music).
            var query = query
            if let self, let sort = self.sorts[self.category(of: location, crumbs: trail)] { query.sort = sort }
            var sections: [LibraryHomeSection]?
            var page: LibraryPage?
            var failure: Error?
            do {
                if wantsHome { sections = try await backend.homeSections() }
                else { page = try await backend.page(at: location, query: query) }
            } catch { failure = error }
            guard let self, !Task.isCancelled, self.generation == generation else { return }
            if let sections { self.applyHome(sections, crumbs: trail, location: location, search: search) }
            else if let page { self.applyPage(page, crumbs: trail, search: search) }
            else if let failure {
                self.applyCrumbs(trail, for: location)
                self.errorMessage = Self.message(for: failure)
                self.contentLocation = location
                self.hasLoaded = true
            }
            self.isLoading = false
            self.clearTask?.cancel()
        }
    }

    /// Loads the next page for a visible row occurrence, including repeated playlist media.
    public func loadMoreIfNeeded(at index: Int) {
        guard entries.indices.contains(index), index >= entries.count - 20 else { return }
        loadMoreIfNeeded()
    }

    /// Loads the next page when `entry` is near the end of what is loaded.
    public func loadMoreIfNeeded(after entry: LibraryEntry? = nil) {
        guard hasMore, moreTask == nil, contentLocation == location, !showsHome else { return }
        if let entry, let index = entries.lastIndex(of: entry), index < entries.count - 20 { return }
        let generation = self.generation
        moreToken += 1
        let token = moreToken
        let query = LibraryQuery(sort: sort, searchText: appliedSearch, offset: entries.count, limit: pageSize)
        let location = self.location
        let backend = self.backend
        isLoadingMore = true
        moreTask = Task { @MainActor [weak self] in
            let page = try? await backend.page(at: location, query: query)
            guard let self else { return }
            // Only the request that is still current may clear the slot (a reload may have replaced it).
            if self.moreToken == token {
                self.moreTask = nil
                self.isLoadingMore = false
            }
            guard let page, !Task.isCancelled, self.generation == generation else { return }
            self.append(page)
        }
    }

    /// All media at the current location in display order (play or enqueue a whole folder).
    public func allMediaHere() async -> [MediaItem] {
        (try? await backend.allMedia(at: location, sort: sort)) ?? mediaEntries
    }

    /// All media at `location` (another folder, a playlist, an album).
    public func allMedia(at location: LibraryLocation) async -> [MediaItem] {
        return (try? await backend.allMedia(at: location, sort: sorts[self.category(of: location, crumbs: nil)] ?? .titleAscending)) ?? []
    }

    /// Loads ``playlists`` once (menus call this when they open); later changes keep it fresh.
    public func loadPlaylistsIfNeeded() {
        guard !playlistsLoaded else { return }
        refreshPlaylists()
    }

    // MARK: Actions (context menus)

    public func setFavorite(_ favorite: Bool, for media: [MediaItem]) { backend.setFavorite(favorite, mediaIDs: media.map(\.id)) }
    /// "Mark as Watched" / "Mark as Unwatched".
    public func setWatched(_ watched: Bool, for media: [MediaItem]) { backend.setWatched(watched, mediaIDs: media.map(\.id)) }
    public func setPlaylistFavorite(_ favorite: Bool, playlist: Playlist) { backend.setPlaylistFavorite(favorite, id: playlist.id) }

    /// New Playlist dialog "Save" (S39).
    @discardableResult
    public func createPlaylist(name: String, media: [MediaItem], artworkURL: URL? = nil) async throws -> Playlist {
        try await backend.createPlaylist(name: name, mediaIDs: media.map(\.id), artworkURL: artworkURL)
    }
    /// "Add File": imports the files, then shows where they are listed (Videos, or Music ▸ Songs) with
    /// them selected, so the user sees what was added wherever the menu was opened.
    /// A mixed import shows the videos and says where the songs went (``importNotice``).
    public func importFiles(urls: [URL]) async throws {
        let imported = try await backend.importFiles(urls: urls)
        guard !imported.isEmpty else { return }
        let songs = imported.filter { $0.kind == .audio }
        let root: LibraryLocation = songs.count == imported.count ? .songs : .videos
        pendingSelection = (root, Set(imported.filter { (root == .songs) == ($0.kind == .audio) }.map { LibraryEntry.media($0).id }))
        if location == root { reload(keepingLoaded: true) } else { navigate(to: root) }
        importNotice = root == .videos && !songs.isEmpty
            ? LibraryImportNotice(shownAt: root, songIDs: Set(songs.map { LibraryEntry.media($0).id }))
            : nil
    }
    /// Shows Music ▸ Songs with the songs of the last mixed import selected.
    public func showImportedSongs() {
        guard let notice = importNotice else { return }
        importNotice = nil
        pendingSelection = (.songs, notice.songIDs)
        if location == .songs { reload(keepingLoaded: true) } else { navigate(to: .songs) }
    }
    public func dismissImportNotice() { importNotice = nil }
    /// "Add to Playlist".
    public func add(_ media: [MediaItem], toPlaylist playlist: Playlist) async throws {
        try await backend.appendToPlaylist(id: playlist.id, mediaIDs: media.map(\.id))
    }
    public func renamePlaylist(_ playlist: Playlist, to name: String) async throws { try await backend.renamePlaylist(id: playlist.id, name: name) }
    public func deletePlaylist(_ playlist: Playlist) async throws { try await backend.deletePlaylist(id: playlist.id) }
    /// "Remove from Playlist" for rows of the shown playlist.
    public func removeFromCurrentPlaylist(entries targets: [LibraryEntry]) async throws {
        guard case .playlist(let id) = location, contentLocation == location else { return }
        let occurrences = targets.compactMap { $0.media?.playlistOccurrence }
        guard occurrences.count == targets.count, occurrences.allSatisfy({ $0.playlistID == id }) else {
            throw BackendOperationError.invalidInput("Reload the playlist before removing items.")
        }
        try await backend.removeFromPlaylist(id: id, occurrences: occurrences)
    }

    /// Open Network Stream dialog "Save" (S36): one URL per line; an optional playlist name.
    @discardableResult
    public func addNetworkStream(urls: [URL], name: String?) async throws -> NetworkStream {
        try await backend.addNetworkStream(urls: urls, name: name?.isEmpty == true ? nil : name)
    }
    public func removeNetworkStream(_ stream: NetworkStream) async throws { try await backend.removeNetworkStream(id: stream.id) }
    public func renameNetworkStream(_ stream: NetworkStream, to name: String) async throws { try await backend.renameNetworkStream(id: stream.id, name: name) }

    /// "Add Folder" / onboarding media folder.
    public func addFolder(_ url: URL) { backend.addFolder(url: url) }
    /// "Remove from Library" for an indexed root folder (entry point).
    public func removeFolder(_ folder: LibraryFolder) { backend.removeFolder(id: folder.id) }
    /// Folder menu "Resync" (nil = everything).
    public func rescan(_ folderID: String? = nil) { backend.rescan(folderID: folderID) }

    /// A sentence for the interface ("Use your words"): backend messages are already written for people.
    public static func message(for error: Error) -> String {
        let text = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
        return text.isEmpty ? "The library could not be read. Try again in a moment." : text
    }

    // MARK: Private

    private func show(_ location: LibraryLocation) {
        self.location = location
        hasLoaded = false
        if pendingSelection?.location != location { pendingSelection = nil }
        if importNotice?.shownAt != location { importNotice = nil }
        selection = []
        selectionAnchor = nil
        if !searchText.isEmpty {
            searchTask?.cancel()
            // Clearing the field must not schedule a second (debounced) reload.
            isResettingSearch = true
            searchText = ""
            isResettingSearch = false
        }
        reload()
    }

    /// Clears the previous location's content if the new one is slow to answer.
    private func scheduleStaleClear(generation: Int) {
        clearTask?.cancel()
        guard contentLocation != location || !hasLoaded else { return }
        let limit = staleContentLimit
        clearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: limit)
            guard let self, !Task.isCancelled, self.generation == generation, self.isLoading, self.contentLocation != self.location else { return }
            self.contentLocation = self.location
            self.entries = []
            self.homeSections = []
            self.totalCount = 0
            self.addAction = nil
            self.breadcrumb = [LibraryCrumb(title: self.location.category.title, location: self.location.category.location)]
        }
    }

    private func cancelLoadMore() {
        moreTask?.cancel()
        moreTask = nil
        moreToken += 1
        if isLoadingMore { isLoadingMore = false }
    }

    private func applyCrumbs(_ crumbs: [LibraryCrumb]?, for location: LibraryLocation) {
        let trail = crumbs.flatMap { $0.isEmpty ? nil : $0 }
            ?? (breadcrumb.last?.location == location ? breadcrumb : [LibraryCrumb(title: location.category.title, location: location.category.location)])
        if trail != breadcrumb { breadcrumb = trail }
    }

    private func applyHome(_ sections: [LibraryHomeSection], crumbs: [LibraryCrumb]?, location: LibraryLocation, search: String) {
        let arriving = contentLocation != location || !hasLoaded
        applyCrumbs(crumbs, for: location)
        if sections != homeSections { homeSections = sections }
        if !entries.isEmpty { entries = [] }
        if addAction != nil { addAction = nil }
        let count = backend.mediaCount
        if count != totalCount { totalCount = count }
        paginationExhausted = true
        finishApply(location: location, search: search, arriving: arriving)
    }

    private func applyPage(_ page: LibraryPage, crumbs: [LibraryCrumb]?, search: String) {
        let arriving = contentLocation != page.location || !hasLoaded
        applyCrumbs(crumbs, for: page.location)
        if page.entries != entries { entries = page.entries }
        if !homeSections.isEmpty { homeSections = [] }
        paginationExhausted = page.entries.isEmpty
        if page.totalCount != totalCount { totalCount = page.totalCount }
        if page.addAction != addAction { addAction = page.addAction }
        finishApply(location: page.location, search: search, arriving: arriving)
        if let pending = pendingSelection, pending.location == page.location {
            pendingSelection = nil
            let shown = pending.ids.intersection(entries.map(\.id))
            if !shown.isEmpty { selection = shown; selectionAnchor = entries.first { shown.contains($0.id) }?.id }
        }
        // Rows that disappeared cannot stay selected.
        if !selection.isEmpty {
            let ids = Set(entries.map(\.id))
            if !selection.isSubset(of: ids) { selection.formIntersection(ids) }
        }
    }

    private func finishApply(location: LibraryLocation, search: String, arriving: Bool) {
        if contentLocation != location { contentLocation = location }
        if appliedSearch != search { appliedSearch = search }
        if !hasLoaded { hasLoaded = true }
        if errorMessage != nil { errorMessage = nil }
        if arriving { clearTask?.cancel() }
    }

    private func append(_ page: LibraryPage) {
        // A playlist or stream can contain the same media at several positions.
        entries.append(contentsOf: page.entries)
        paginationExhausted = page.entries.isEmpty
        if page.totalCount != totalCount { totalCount = page.totalCount }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let delay = searchDebounce
        searchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    private func refreshPlaylists() {
        playlistsLoaded = true
        playlistsTask?.cancel()
        if let page = backend.cachedPage(at: .playlists, query: LibraryQuery(sort: .titleAscending, limit: 500)) {
            let cached = page.entries.compactMap { if case .playlist(let playlist) = $0 { return playlist }; return nil }
            if cached != playlists { playlists = cached }
        }
        let backend = self.backend
        playlistsTask = Task { @MainActor [weak self] in
            guard let page = try? await backend.page(at: .playlists, query: LibraryQuery(sort: .titleAscending, limit: 500)),
                  let self, !Task.isCancelled else { return }
            let loaded = page.entries.compactMap { if case .playlist(let playlist) = $0 { return playlist }; return nil }
            if loaded != self.playlists { self.playlists = loaded }
        }
    }

    private func handle(_ event: LibraryEvent) {
        switch event {
        case .contentChanged:
            if playlistsLoaded { refreshPlaylists() }
            reload(keepingLoaded: true)
        case .mediaUpdated(let ids):
            let shown = Set(entries.compactMap { $0.media?.id }).union(homeSections.flatMap { $0.entries.compactMap { $0.media?.id } })
            if !shown.isDisjoint(with: ids) || location == .home || location == .recent { reload(keepingLoaded: true) }
        case .playlistsChanged:
            if playlistsLoaded { refreshPlaylists() }
            if location.category == .playlists || location == .home || location.category == .network { reload(keepingLoaded: true) }
        case .thumbnailReady(let id):
            // The media library persisted a new picture: refresh only if that media is on screen.
            let shown = entries.contains { $0.media?.id == id } || homeSections.contains { $0.entries.contains { $0.media?.id == id } }
            if shown { reload(keepingLoaded: true) }
        case .bookmarksChanged, .indexingChanged:
            break
        }
    }
}

/// What a mixed import (videos and songs) says in Videos about the songs (``LibraryModel/importNotice``).
public struct LibraryImportNotice: Equatable, Sendable {
    /// The place the notice belongs to; navigating elsewhere drops it.
    public let shownAt: LibraryLocation
    /// Entry ids of the imported songs, selected when Songs opens.
    public let songIDs: Set<LibraryEntry.ID>

    public init(shownAt: LibraryLocation, songIDs: Set<LibraryEntry.ID>) {
        self.shownAt = shownAt
        self.songIDs = songIDs
    }

    /// "2 songs were added to Music ▸ Songs."
    public var message: String {
        (songIDs.count == 1 ? "1 song was" : "\(songIDs.count) songs were") + " added to Music ▸ Songs."
    }
}

// MARK: - Library audio tracks (S29 file, S30 folder, S31 playlist menus)

/// Pairs audio files with the media of a file, folder or playlist for Edit / Add Audio Tracks.
/// A single media takes every chosen file (like VLC's Add Audio Track); several media take the
/// file whose name matches theirs, by episode code ("S01E04") or base name, each file once —
/// the rules Add Subtitles uses (``SubtitleMatcher``). Files that are not audio are left out.
public enum LibraryAudioTracks {
    public struct Assignment: Equatable, Sendable {
        public let media: MediaItem
        public let url: URL
    }

    public static func match(_ urls: [URL], to media: [MediaItem]) -> [Assignment] {
        let audio = urls.filter { MediaItem.kind(of: $0) == .audio }
        guard !audio.isEmpty, !media.isEmpty else { return [] }
        if media.count == 1 { return audio.map { Assignment(media: media[0], url: $0) } }
        let names = SubtitleMatcher.match(videos: media.map(\.listTitle), subtitles: audio.map(\.lastPathComponent))
        return media.compactMap { item in
            guard let name = names[item.listTitle], let url = audio.first(where: { $0.lastPathComponent == name }) else { return nil }
            return Assignment(media: item, url: url)
        }
    }

    /// "Audio track added to 3 files." / "Audio tracks added to The_Wand_S01E04.mp4."
    public static func notice(_ assignments: [Assignment]) -> String {
        let files = Set(assignments.map(\.media.id))
        let tracks = assignments.count == 1 ? "Audio track" : "Audio tracks"
        if files.count == 1, let media = assignments.first?.media { return "\(tracks) added to \(media.listTitle)." }
        return "\(tracks) added to \(files.count) files."
    }
}

extension AppModel {
    /// Edit / Add Audio Tracks: an Add Audio File panel whose files become external audio tracks
    /// of `media` — attached in the media library (`VLC_ML_FILE_TYPE_SOUNDTRACK`), which every
    /// later playback loads as a slave, and added to the running input for the media that plays.
    public func presentAddAudioTracks(media: [MediaItem]) {
        guard interface.sheet == nil, interface.fileRequest == nil, !media.isEmpty else { return }
        library.audioTrackTargets = media
        interface.request(.addAudioFile)
        if interface.fileRequest != .addAudioFile { library.audioTrackTargets = [] }
    }

    /// The Add Audio File panel's result (``complete(_:urls:)``) for `targets`.
    func completeAddAudioFile(_ urls: [URL], targets: [MediaItem]) {
        guard !targets.isEmpty else {
            urls.forEach { tracks.addExternalTrack(url: $0, kind: .audio) }
            return
        }
        let assignments = LibraryAudioTracks.match(urls, to: targets)
        guard !assignments.isEmpty else {
            let reason = urls.contains { MediaItem.kind(of: $0) == .audio }
                ? "No audio file has the name or episode number of a file here."
                : "Choose audio files such as M4A, MP3 or FLAC."
            dialogs.presentError(BackendOperationError.invalidInput(reason), title: "No Audio Tracks Were Added")
            return
        }
        for assignment in assignments {
            if assignment.media.id.hasPrefix("ml:") { backends.library.attachAudioTrack(url: assignment.url, toMedia: assignment.media.id) }
            if isPlayerMedia(assignment.media) { tracks.addExternalTrack(url: assignment.url, kind: .audio) }
        }
        osd.showNotice(LibraryAudioTracks.notice(assignments))
    }

    private func isPlayerMedia(_ media: MediaItem) -> Bool {
        guard let current = player.media else { return false }
        if current.id == media.id || (!media.mrl.isEmpty && current.mrl == media.mrl) { return true }
        guard let a = URL(string: media.mrl), a.isFileURL, let b = URL(string: current.mrl), b.isFileURL else { return false }
        return a.standardizedFileURL == b.standardizedFileURL
    }
}
