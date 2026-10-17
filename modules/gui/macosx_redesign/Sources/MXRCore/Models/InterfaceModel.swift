import Foundation
import Observation

/// Tabs of the track popover (S14–S16).
public enum TrackPanelTab: String, Sendable, Hashable, CaseIterable {
    case video, audio, subtitles

    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// Tabs of the playback settings sidebar (S17–S20), in design order.
public enum SidebarTab: String, Sendable, Hashable, CaseIterable {
    case playback, video, audio, subtitles

    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// The sidebar tab matching a track popover tab ("Show Preferences").
    public init(_ tab: TrackPanelTab) {
        switch tab {
        case .video: self = .video
        case .audio: self = .audio
        case .subtitles: self = .subtitles
        }
    }
}

/// Tabs of the right panel opened by the queue button (S22–S24).
public enum QueuePanelTab: String, Sendable, Hashable, CaseIterable {
    case queue, bookmarks, chapters

    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// The floating panel at the right of the video. Only one is open at a time.
public enum RightPanel: Hashable, Sendable {
    case tracks(TrackPanelTab)
    case sidebar(SidebarTab)
    case queue(QueuePanelTab)
}

/// How the library is shown.
public enum LibraryPresentation: String, Sendable, Hashable {
    case hidden
    /// The 378-pt panel with the icon rail beside the video (S28).
    case compact
    /// The full-window library with the mini player (S43).
    case full
}

/// Scope of the Add Subtitles dialog ("To This File / Folder / Playlist").
public enum AddSubtitlesScope: String, Sendable, Hashable, CaseIterable {
    case file, folder, playlist

    public var title: String {
        switch self {
        case .file: "To This File"
        case .folder: "To This Folder"
        case .playlist: "To This Playlist"
        }
    }
}

/// Source of the Add Subtitles dialog ("From Computer / From OpenSubtitles / From Link ...").
public enum AddSubtitlesSource: String, Sendable, Hashable, CaseIterable {
    case computer, openSubtitles, link

    public var title: String {
        switch self {
        case .computer: "From Computer"
        case .openSubtitles: "From OpenSubtitles"
        case .link: "From Link ..."
        }
    }
}

/// Modal surfaces presented over the player window.
public enum AppSheet: Hashable, Sendable, Identifiable {
    /// Settings window, optionally at a category id.
    case settings(categoryID: String?)
    case keyboardShortcuts
    case profiles
    case addSubtitles(scope: AddSubtitlesScope, source: AddSubtitlesSource)
    case openNetworkStream
    case newPlaylist
    case openDisc
    case openCaptureDevice
    case convert
    case stream
    case about
    case onboarding
    /// "Properties & Metadata".
    case mediaInfo(MediaItem)

    public var id: String {
        switch self {
        case .settings: "settings"
        case .keyboardShortcuts: "keyboardShortcuts"
        case .profiles: "profiles"
        case .addSubtitles: "addSubtitles"
        case .openNetworkStream: "openNetworkStream"
        case .newPlaylist: "newPlaylist"
        case .openDisc: "openDisc"
        case .openCaptureDevice: "openCaptureDevice"
        case .convert: "convert"
        case .stream: "stream"
        case .about: "about"
        case .onboarding: "onboarding"
        case .mediaInfo(let media): "mediaInfo:" + media.id
        }
    }
}

/// A request for a native open panel. The UI shows `NSOpenPanel`, then calls the matching
/// ``AppModel`` method with the chosen URLs (or clears the request on cancel).
public enum FileRequest: String, Sendable, Hashable, Identifiable {
    /// "Open File(s)": play the files.
    case openFiles
    /// "Open Folder": play the folder.
    case openFolder
    /// External Tracks "+": load a subtitle file for the current media.
    case addSubtitleFile
    case addAudioFile
    /// Library "Add Folder": index a folder.
    case addLibraryFolder
    /// Library "Add File": add files to the queue.
    case addFilesToQueue
    /// Explicitly import chosen files into the media library.
    case addLibraryFiles

    public var id: String { rawValue }
}

/// Elapsed vs remaining for the right time label (S02).
public enum TimeDisplayMode: String, Sendable, Hashable, Codable {
    case elapsed, remaining
}

/// Window-level UI state shared by every view: which panel/sheet is open, hidden UI, library mode.
/// Not engine state; nothing here talks to VLC.
@MainActor
@Observable
public final class InterfaceModel {
    /// The open right panel (track popover, sidebar or queue panel).
    public var rightPanel: RightPanel?
    public var library: LibraryPresentation = .hidden {
        didSet { if library == .full { rightPanel = nil; isAppMenuOpen = false } }
    }
    /// "Hide UI" (⌘\, D026): no bars, only the video (S06).
    public var isUIHidden = false
    /// Customize Player mode (S66).
    /// Native menus and key monitors defer while a shortcut editor captures keys.
    public var isCapturingShortcut = false
    /// A queue or bookmark row has keyboard focus: its list keys bypass VLC's hotkeys (``FocusedListKeys``).
    public var panelListHasKeyboardFocus = false
    public var isCustomizing = false
    public var sheet: AppSheet?
    public var fileRequest: FileRequest?
    /// Library selections retained until the matching dialog completes.
    public var pendingPlaylistMedia: [MediaItem] = []
    public var pendingOutputSource: MediaItem?
    public var subtitleTargetMedia: [MediaItem] = []
    /// The duration label shows the length or the remaining time ("-00:23:30").
    public var timeDisplay: TimeDisplayMode = .elapsed
    /// Playback tab toggles, remembered across launches in `playback-tab.json` (CMP-10).
    public var showSubtitleTimeline = false { didSet { savePlaybackTab() } }
    public var showStatistics = false
    public var showWaveform = false { didSet { savePlaybackTab() } } // D028: off by default (09m17.5 frame); the waveform is computed only when drawn
    /// "Show Metadata" (video 09m17.5): the media information overlay on the video.
    public var showMetadata = false { didSet { savePlaybackTab() } }
    /// Subtitle timeline window chosen by dragging or ‹ ›; nil follows the playhead (S21).
    public var subtitleTimelineWindowStart: MediaTime?
    /// Mini player: the queue section is expanded above the video (S46).
    public var isMiniPlayerQueueExpanded = false
    /// D023: the top bar and the control bar reveal independently. These are the effective states
    /// (hover zones, hide timers and pins already applied) kept by the window's reveal controller.
    /// The host shows the native traffic lights only while the top bar is visible (D022).
    public var isTopBarVisible = true
    public var isControlBarVisible = true
    /// The `⋯` app menu is open. It pins the top bar and closes with Esc or an outside click (D024).
    public var isAppMenuOpen = false
    /// Leading width the host's native window buttons take in the top bar, including the Figma gap
    /// to the cone (D022). Zero without a titled window, in fullscreen and while the buttons are hidden.
    public var windowControlsReserve: Double = 0
    /// Fullscreen only: how far macOS's own strip (the menu bar and the window's titlebar with the
    /// traffic lights) reaches into the window from its top edge while macOS shows it; 0 when it is
    /// hidden and in a window. Set by the host from the strip window's frame (D055).
    public var fullscreenSystemInset: Double = 0
    /// Where the top bar is drawn below the window's top edge. In fullscreen it moves below macOS's
    /// strip when that strip appears and stays there until the bar hides, so the bar never slides
    /// away from a pointer that comes down from the menu bar (D055). Kept by the window's reveal
    /// controller; 0 in a window.
    public var topBarOffset: Double = 0
    /// Points the shown bottom chrome (the control bar over a fullscreen picture) covers at the bottom
    /// of the video view; the backend raises subtitles by it (VLC "sub-margin", live run 1 item 6).
    /// Kept by the window composition; 0 when nothing covers the picture.
    public var subtitleSafeInset: Double = 0

    /// - Parameter persistence: where the Playback tab toggles are kept; `.inMemory` for previews and tests.
    public init(persistence: PersistenceLocation = .inMemory) {
        playbackTabStore = JSONFileStore(location: persistence, fileName: "playback-tab.json")
        if let saved = playbackTabStore.load() {
            showSubtitleTimeline = saved.showSubtitleTimeline
            showWaveform = saved.showWaveform
            showMetadata = saved.showMetadata
        }
    }

    private struct PlaybackTabPreferences: Codable {
        var showSubtitleTimeline: Bool
        var showWaveform: Bool
        var showMetadata: Bool
    }
    @ObservationIgnored private let playbackTabStore: JSONFileStore<PlaybackTabPreferences>
    private func savePlaybackTab() {
        playbackTabStore.save(PlaybackTabPreferences(showSubtitleTimeline: showSubtitleTimeline,
                                                     showWaveform: showWaveform, showMetadata: showMetadata))
    }

    // MARK: Bars

    /// True while the control bar shows (display link, subtitle timeline). Setting it reveals or
    /// hides both bars at once, as the "show controls" click action and Customize Player do.
    public var areBarsVisible: Bool {
        get { isControlBarVisible }
        set { isTopBarVisible = newValue; isControlBarVisible = newValue }
    }

    /// A transient popup (app menu, track popover, sidebar or queue) is open.
    public var hasTransientPopup: Bool { !isUIHidden && (isAppMenuOpen || (library != .full && rightPanel != nil)) }

    /// Persistent player information follows Hide UI; brief shortcut feedback remains available.
    public var showsPlayerInformation: Bool { !isUIHidden && library != .full }

    /// Esc and a click outside close the front-most popup (D024). Returns false when none was open,
    /// so the caller can give the event to playback (Esc leaves fullscreen, a click toggles play).
    @discardableResult
    public func dismissTransientPopup() -> Bool {
        guard hasTransientPopup else { return false }
        if isAppMenuOpen { isAppMenuOpen = false; return true }
        if rightPanel != nil { rightPanel = nil; return true }
        return false
    }

    /// D029: with nothing to open or resume, launch shows the full-window library on Home, or the
    /// compact library beside the player when "Start in compact mode" is on.
    public func presentLaunchLibrary(compact: Bool) {
        guard !isCustomizing else { return }
        library = compact ? .compact : .full
    }

    // MARK: Right panel

    public var isTracksPanelOpen: Bool { if case .tracks = rightPanel { true } else { false } }
    public var isSidebarOpen: Bool { if case .sidebar = rightPanel { true } else { false } }
    public var isQueuePanelOpen: Bool { if case .queue = rightPanel { true } else { false } }

    /// Opens `panel`, or closes it when exactly that panel is already open.
    public func toggle(_ panel: RightPanel) {
        if rightPanel == panel {
            rightPanel = nil
        } else {
            selectTab(panel)
        }
    }

    /// Audio/subtitles bar icons: toggle the track popover on that tab.
    public func toggleTracks(_ tab: TrackPanelTab) { toggle(.tracks(tab)) }

    /// Gear icon: toggle the sidebar (keeps the last tab when reopening).
    public func toggleSidebar(_ tab: SidebarTab? = nil) {
        if isSidebarOpen, tab == nil {
            rightPanel = nil
        } else {
            let target = tab ?? lastSidebarTab
            toggle(.sidebar(target))
        }
    }

    /// Queue icon: toggle the queue panel (keeps the last tab).
    public func toggleQueuePanel(_ tab: QueuePanelTab? = nil) {
        if isQueuePanelOpen, tab == nil {
            rightPanel = nil
        } else {
            toggle(.queue(tab ?? lastQueueTab))
        }
    }

    /// Switches the tab of the open panel family.
    public func selectTab(_ panel: RightPanel) {
        guard library != .full else { return }
        rightPanel = panel
        if case .sidebar(let tab) = panel { lastSidebarTab = tab }
        if case .queue(let tab) = panel { lastQueueTab = tab }
    }

    /// "Show Preferences" in the track popover: opens the sidebar on the matching tab.
    public func showPreferences(for tab: TrackPanelTab) { selectTab(.sidebar(SidebarTab(tab))) }

    public func closeRightPanel() { rightPanel = nil }

    @ObservationIgnored private var lastSidebarTab: SidebarTab = .playback
    @ObservationIgnored private var lastQueueTab: QueuePanelTab = .queue

    // MARK: Library

    /// Sidebar-toggle icon in the top bar: compact library on/off.
    public func toggleCompactLibrary() { library = library == .compact ? .hidden : .compact }
    /// "Open full library" icon / Go Home.
    public func showFullLibrary() { library = .full }

    /// D057: the compact library closed itself for the right panel in a window too narrow for both,
    /// and reopens when the panel closes or the window grows.
    public private(set) var libraryYieldedToPanel = false

    /// D057: keeps the compact library and a right panel apart in a window too narrow for both
    /// (`fit` is false). A panel opened over the library makes the library yield (it closes and
    /// remembers to come back); opening the library while a panel is open (`libraryOpened`) closes
    /// the panel instead, so the sidebar toggle never switches a library nobody can see.
    public func reconcileLibraryAndPanel(fit: Bool, libraryOpened: Bool = false) {
        if library == .full { libraryYieldedToPanel = false; return }
        if !fit && library == .compact && rightPanel != nil {
            if libraryOpened {
                libraryYieldedToPanel = false
                rightPanel = nil
            } else {
                libraryYieldedToPanel = true
                library = .hidden
            }
            return
        }
        if libraryYieldedToPanel && (rightPanel == nil || fit) {
            libraryYieldedToPanel = false
            if library == .hidden && !isUIHidden { library = .compact }
        }
    }

    // MARK: Sheets and misc

    @ObservationIgnored private var returnSheet: AppSheet?

    public func present(_ sheet: AppSheet) {
        if let current = self.sheet {
            guard case .settings = current, sheet == .keyboardShortcuts else { return }
            returnSheet = current
        }
        isAppMenuOpen = false
        self.sheet = sheet
    }
    public func dismissSheet() {
        sheet = returnSheet
        returnSheet = nil
    }
    public func request(_ file: FileRequest) {
        guard sheet == nil, fileRequest == nil else { return }
        fileRequest = file
    }
    /// Hide UI removes all chrome (S06), so open popups close with it. The ⋯ menu is transient and
    /// stays closed; the right panel that was open (queue, sidebar, tracks) comes back with the UI.
    public func toggleUIHidden() {
        isUIHidden.toggle()
        if isUIHidden {
            isAppMenuOpen = false
            panelBeforeHidingUI = rightPanel
            rightPanel = nil
        } else {
            if rightPanel == nil, library != .full, !isCustomizing, let panel = panelBeforeHidingUI { selectTab(panel) }
            panelBeforeHidingUI = nil
        }
    }
    @ObservationIgnored private var panelBeforeHidingUI: RightPanel?
    public func toggleTimeDisplay() { timeDisplay = timeDisplay == .elapsed ? .remaining : .elapsed }
}
