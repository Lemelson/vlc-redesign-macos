import Foundation
import Observation

/// Everything that can sit in the player's top bar or control bar: the default controls plus the
/// 31 tiles of the Customize Player dialog (S66, Figma "Player - customize"), in tile order.
public enum PlayerControl: String, Sendable, Codable, Hashable, CaseIterable {
    // Default bar items (not tiles)
    case logo, menu, sidebarToggle, folderName, title, fullscreen
    case previous, playPause, next, currentTime, seekBar, duration, volume, audioTracks, subtitleTracks, playbackSettings, queue
    // Tiles, in the dialog's order
    case spacer, divider, playbackSpeed, forward10, backward10, forward15, backward15, stop, repeatMode, shuffle, record, snapshot
    case pictureInPicture, hdr, zoom, rightSidebar, quit, settings, goHome, thumbnail, fileName, artistName, folderNameTile
    case playlistName, properties, replay, chapters, favorite, bookmark, bookmarks, playlists

    /// The tiles of the Customize Player dialog, in Figma order.
    public static let tiles: [PlayerControl] = [
        .spacer, .divider, .playbackSpeed, .forward10, .backward10, .forward15, .backward15, .stop, .repeatMode, .shuffle, .record,
        .snapshot, .pictureInPicture, .hdr, .zoom, .rightSidebar, .quit, .settings, .goHome, .thumbnail, .fileName, .artistName,
        .folderNameTile, .playlistName, .properties, .replay, .chapters, .favorite, .bookmark, .bookmarks, .playlists,
    ]

    /// Tile label (Figma).
    public var title: String {
        switch self {
        case .logo: "VLC"
        case .menu: "Menu"
        case .sidebarToggle: "Library"
        case .folderName, .folderNameTile: "Folder Name"
        case .title: "Title"
        case .fullscreen: "Fullscreen"
        case .previous: "Previous"
        case .playPause: "Play"
        case .next: "Next"
        case .currentTime: "Current Time"
        case .seekBar: "Seek Bar"
        case .duration: "Duration"
        case .volume: "Volume"
        case .audioTracks: "Audio Tracks"
        case .subtitleTracks: "Subtitles"
        case .playbackSettings: "Playback Settings"
        case .queue: "Queue"
        case .spacer: "Spacer"
        case .divider: "Divider"
        case .playbackSpeed: "Playback Speed"
        case .forward10: "Forward 10s"
        case .backward10: "Backward 10s"
        case .forward15: "Forward 15s"
        case .backward15: "Backward 15s"
        case .stop: "Stop"
        case .repeatMode: "Repeat"
        case .shuffle: "Shuffle"
        case .record: "Record"
        case .snapshot: "Snapshot"
        case .pictureInPicture: "Picture in Picture"
        case .hdr: "HDR"
        case .zoom: "Zoom"
        case .rightSidebar: "Right Sidebar"
        case .quit: "Quit VLC"
        case .settings: "VLC Settings"
        case .goHome: "Go Home"
        case .thumbnail: "Thumbnail"
        case .fileName: "File Name"
        case .artistName: "Artist Name"
        case .playlistName: "Playlist Name"
        case .properties: "Properties"
        case .replay: "Replay"
        case .chapters: "Chapters"
        case .favorite: "Favorite"
        case .bookmark: "Bookmark"
        case .bookmarks: "Bookmarks"
        case .playlists: "Playlists"
        }
    }

    /// Items that take the remaining width of their row.
    public var isFlexible: Bool { self == .seekBar || self == .spacer }

    /// Items that may appear more than once (the dialog keeps offering them).
    public var isRepeatable: Bool { self == .spacer || self == .divider }

    /// The command a clickable item runs, if it maps to one.
    public var command: AppCommand? {
        switch self {
        case .previous: .previous
        case .playPause: .playPause
        case .next: .next
        case .forward10: .jumpForward10
        case .backward10: .jumpBackward10
        case .forward15: .jumpForward15
        case .backward15: .jumpBackward15
        case .stop: .stop
        case .repeatMode: .toggleRepeat
        case .shuffle: .toggleShuffle
        case .record: .record
        case .snapshot: .snapshot
        case .fullscreen: .toggleFullscreen
        case .queue, .chapters, .bookmarks: .toggleQueue
        case .sidebarToggle: .toggleLibrary
        case .rightSidebar, .playbackSettings: .toggleSettingsSidebar
        case .quit: .quit
        case .settings: .settings
        case .goHome: .showFullLibrary
        case .favorite: .favoriteCurrent
        case .bookmark: .addBookmark
        case .subtitleTracks: .showSubtitleTracks
        case .audioTracks: .showAudioTracks
        default: nil
        }
    }
}

/// One placed control. Ids keep repeated spacers/dividers distinct while dragging.
public struct LayoutItem: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var control: PlayerControl

    public init(_ control: PlayerControl, id: String? = nil) {
        self.control = control
        self.id = id ?? control.rawValue + "-" + UUID().uuidString.prefix(8)
    }
}

/// Which bar row an item is in: the top bar, or a control-bar row (0 = the row nearest the video).
public enum LayoutZone: Hashable, Sendable, Codable {
    case top
    case bottom(Int)
    /// A new control-bar row nearest the video: the empty band Customize shows above a one-row
    /// control bar (Figma "Player - customize*", key frames 19m12–19m27).
    public static let newFirstRow = LayoutZone.bottom(-1)
}

/// The player's bars: one top row and one or more control-bar rows, each a list laid out left to
/// right where flexible items (seek bar, spacers) share the free width. The title in the top bar is
/// centered on the window by the view.
public struct PlayerLayout: Hashable, Sendable, Codable {
    public var top: [LayoutItem]
    public var bottom: [[LayoutItem]]

    /// Items another version wrote that this one cannot read. Not shown and not part of equality;
    /// written back so that version finds them again.
    private var unreadable = Unreadable()

    private struct Unreadable: Sendable {
        var top: [UnreadableEntry] = []
        /// By row of ``bottom``.
        var rows: [Int: [UnreadableEntry]] = [:]
        /// Rows that held only unreadable items, by their index in the file.
        var hiddenRows: [Int: [UnreadableEntry]] = [:]
        /// ``bottom`` is the `[[]]` placeholder because every row was hidden.
        var placeholder = false
    }

    public init(top: [LayoutItem], bottom: [[LayoutItem]]) {
        self.top = top
        self.bottom = bottom
    }

    public static func == (lhs: PlayerLayout, rhs: PlayerLayout) -> Bool { lhs.top == rhs.top && lhs.bottom == rhs.bottom }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(top)
        hasher.combine(bottom)
    }

    private enum CodingKeys: String, CodingKey { case top, bottom }

    /// Items decode one by one: a control this version does not know (saved by a newer one, or
    /// renamed) is left out and the rest of the layout stays. A row that held only such controls is
    /// hidden; an empty row in the file stays.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let topList = try c.decode(LossyArray<LayoutItem>.self, forKey: .top)
        top = topList.elements
        unreadable.top = topList.unreadable
        bottom = []
        for (index, row) in try c.decode([LossyArray<LayoutItem>].self, forKey: .bottom).enumerated() {
            if row.elements.isEmpty, !row.unreadable.isEmpty {
                unreadable.hiddenRows[index] = row.unreadable
                continue
            }
            if !row.unreadable.isEmpty { unreadable.rows[bottom.count] = row.unreadable }
            bottom.append(row.elements)
        }
        if bottom.isEmpty {
            bottom = [[]]
            unreadable.placeholder = !unreadable.hiddenRows.isEmpty
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(LossyArray(top, unreadable: unreadable.top), forKey: .top)
        var rows = unreadable.placeholder && bottom == [[]] ? [] : bottom.enumerated().map {
            LossyArray($0.element, unreadable: unreadable.rows[$0.offset] ?? [])
        }
        for (index, entries) in unreadable.hiddenRows.sorted(by: { $0.key < $1.key }) {
            rows.insert(LossyArray([], unreadable: entries), at: min(index, rows.count))
        }
        try c.encode(rows, forKey: .bottom)
    }

    private static func items(_ controls: [PlayerControl], prefix: String) -> [LayoutItem] {
        controls.enumerated().map { LayoutItem($0.element, id: "\(prefix)-\($0.offset)-\($0.element.rawValue)") }
    }

    /// The Figma default for video (Player frames): one control-bar row.
    public static let video = PlayerLayout(
        top: items([.logo, .menu, .sidebarToggle, .divider, .folderName, .spacer, .title, .spacer, .fullscreen], prefix: "t"),
        bottom: [items([.previous, .playPause, .next, .currentTime, .seekBar, .duration, .volume, .audioTracks, .subtitleTracks,
                        .playbackSettings, .queue], prefix: "b0")])

    /// The Figma default for music (Controls "music" variant): ±15 s skips, no subtitles button.
    public static let music = PlayerLayout(
        top: items([.logo, .menu, .sidebarToggle, .divider, .folderName, .spacer, .title, .spacer, .fullscreen], prefix: "t"),
        bottom: [items([.previous, .backward15, .playPause, .forward15, .next, .currentTime, .seekBar, .duration, .volume,
                        .audioTracks, .queue], prefix: "b0")])

    /// The alternate two-row layout shown in the video (S67).
    public static let twoRowExample = PlayerLayout(
        top: items([.logo, .spacer], prefix: "t"),
        bottom: [
            items([.currentTime, .seekBar, .duration], prefix: "b0"),
            items([.menu, .sidebarToggle, .divider, .folderName, .title, .favorite, .spacer, .previous, .playPause, .next, .spacer,
                   .volume, .audioTracks, .subtitleTracks, .playbackSettings, .queue, .fullscreen], prefix: "b1"),
        ])

    /// All placed items.
    public var allItems: [LayoutItem] { top + bottom.flatMap { $0 } }

    /// Whether a control is placed somewhere.
    public func contains(_ control: PlayerControl) -> Bool { allItems.contains { $0.control == control } }

    /// Tiles the dialog still offers (placed tiles disappear, except spacer and divider).
    public var availableTiles: [PlayerControl] {
        PlayerControl.tiles.filter { $0.isRepeatable || !contains($0) }
    }

    /// The items of a zone.
    public func items(in zone: LayoutZone) -> [LayoutItem] {
        switch zone {
        case .top: return top
        case .bottom(let row): return bottom.indices.contains(row) ? bottom[row] : []
        }
    }

    /// Where an item is.
    public func location(of id: LayoutItem.ID) -> (zone: LayoutZone, index: Int)? {
        if let index = top.firstIndex(where: { $0.id == id }) { return (.top, index) }
        for (row, items) in bottom.enumerated() {
            if let index = items.firstIndex(where: { $0.id == id }) { return (.bottom(row), index) }
        }
        return nil
    }

    /// Removes an item (drag back into the dialog).
    public mutating func remove(_ id: LayoutItem.ID) {
        top.removeAll { $0.id == id }
        for row in bottom.indices { bottom[row].removeAll { $0.id == id } }
    }

    /// Inserts an item in a zone at `index` (clamped). A new bottom row is created when `zone`
    /// is the row just past the last one, or ``LayoutZone/newFirstRow`` (the edit-mode band above
    /// the control bar, 2107:5604).
    public mutating func insert(_ item: LayoutItem, in zone: LayoutZone, at index: Int) {
        remove(item.id)
        switch zone {
        case .top:
            top.insert(item, at: min(max(index, 0), top.count))
        case .bottom(let row):
            if row < 0 { bottom.insert([], at: 0) } else if row >= bottom.count { bottom.append([]) }
            let target = min(max(row, 0), bottom.count - 1)
            bottom[target].insert(item, at: min(max(index, 0), bottom[target].count))
        }
        bottom.removeAll { $0.isEmpty }
        if bottom.isEmpty { bottom = [[]] }
    }

    /// Moves an existing item.
    public mutating func move(_ id: LayoutItem.ID, to zone: LayoutZone, at index: Int) {
        guard let current = location(of: id) else { return }
        let item = items(in: current.zone)[current.index]
        var adjusted = index
        if current.zone == zone, current.index < index { adjusted -= 1 }
        insert(item, in: zone, at: adjusted)
    }
}

/// Player layouts per profile and media kind, and the Customize Player editing session (S66–S68).
/// Persisted to `layouts.json`.
@MainActor
@Observable
public final class LayoutStore {
    /// Which default a layout derives from.
    public enum Kind: String, Sendable, Codable, Hashable, CaseIterable {
        case video, music
    }

    private var layouts: [String: PlayerLayout] = [:]
    /// The layout being edited, nil when not customizing.
    public private(set) var draft: PlayerLayout?
    @ObservationIgnored private var draftKey: (profileID: String, kind: Kind)?
    /// The undo manager of the window that shows Customize. Each draft change registers its inverse
    /// there, so Edit ▸ Undo / ⌘Z and Redo / ⇧⌘Z step through the session's edits (macOS editors
    /// undo inside a session that Cancel can still discard). The session's actions are removed when
    /// it ends, so Undo never reaches a layout that was saved or cancelled.
    @ObservationIgnored public weak var undoManager: UndoManager? {
        didSet { if oldValue !== undoManager { oldValue?.removeAllActions(withTarget: self) } }
    }
    /// Layouts decode one by one, so one unreadable layout costs only itself.
    @ObservationIgnored private let file: JSONFileStore<LossyDictionary<PlayerLayout>>
    /// Layouts another version wrote that this one cannot read; saved back until replaced or reset.
    @ObservationIgnored private var unreadable: [String: JSONValue] = [:]

    public init(location: PersistenceLocation) {
        file = JSONFileStore(location: location, fileName: "layouts.json")
        let saved = file.load()
        layouts = saved?.values ?? [:]
        unreadable = saved?.unreadable ?? [:]
    }

    private func save() { file.save(LossyDictionary(layouts, unreadable: unreadable)) }

    private static func key(_ profileID: String, _ kind: Kind) -> String { "\(profileID)/\(kind.rawValue)" }

    /// The saved layout (or the Figma default).
    public func layout(profileID: String, kind: Kind) -> PlayerLayout {
        layouts[Self.key(profileID, kind)] ?? (kind == .music ? .music : .video)
    }

    /// Starts customizing (copies the saved layout into ``draft``).
    public func beginEditing(profileID: String, kind: Kind) {
        endUndoSession()
        draft = layout(profileID: profileID, kind: kind)
        draftKey = (profileID, kind)
    }

    /// Edits the draft in place. A change is undoable (``undoManager``) under `actionName`.
    public func updateDraft(actionName: String? = nil, _ change: (inout PlayerLayout) -> Void) {
        guard var copy = draft else { return }
        change(&copy)
        replaceDraft(with: copy, actionName: actionName)
    }

    /// Sets the draft and registers the way back. Run from an undo, the registration becomes the redo.
    private func replaceDraft(with layout: PlayerLayout, actionName: String?) {
        guard let previous = draft, previous != layout else { return }
        draft = layout
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.replaceDraft(with: previous, actionName: actionName) }
        }
        if let actionName { undoManager.setActionName(actionName) }
    }

    private func endUndoSession() {
        undoManager?.removeAllActions(withTarget: self)
    }

    /// True when the draft differs from the saved layout (enables "Save").
    public var hasChanges: Bool {
        guard let draft, let key = draftKey else { return false }
        return draft != layout(profileID: key.profileID, kind: key.kind)
    }

    /// "Save".
    public func commit() {
        guard let draft, let key = draftKey else { return }
        layouts[Self.key(key.profileID, key.kind)] = draft
        unreadable[Self.key(key.profileID, key.kind)] = nil
        save()
        self.draft = nil
        draftKey = nil
        endUndoSession()
    }

    /// "Cancel".
    public func cancelEditing() {
        draft = nil
        draftKey = nil
        endUndoSession()
    }

    /// Forgets every layout of a deleted profile (video and music).
    public func removeLayouts(profileID: String) {
        let keys = Kind.allCases.map { Self.key(profileID, $0) }.filter { layouts[$0] != nil || unreadable[$0] != nil }
        guard !keys.isEmpty else { return }
        for key in keys { layouts[key] = nil; unreadable[key] = nil }
        save()
    }

    /// Restores the Figma default for a profile and kind.
    public func reset(profileID: String, kind: Kind) {
        layouts[Self.key(profileID, kind)] = nil
        unreadable[Self.key(profileID, kind)] = nil
        save()
    }
}
