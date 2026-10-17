import AppKit
import MXRCore
import MXRDesign
import SwiftUI
import UniformTypeIdentifiers

/// Payload shared by queue rows, library drags and file drops. URLs are accepted only as
/// local files or explicit network MRLs; arbitrary text is never turned into a media item.
enum PanelDropPayload: Equatable {
    case queueItem(UInt64)
    case url(URL)
    init?(text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("mxr-queue:") {
            let id = String(text.dropFirst("mxr-queue:".count))
            guard let numericID = UInt64(id) else { return nil }
            self = .queueItem(numericID)
        } else if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
                  ["file", "http", "https", "rtsp", "rtmp", "smb", "ftp"].contains(scheme) {
            self = .url(url)
        } else { return nil }
    }
}

public struct MXRQueuePanelView: View {
    public let tab: QueuePanelTab
    @Environment(InterfaceModel.self) private var ui
    @Environment(QueueModel.self) private var queue
    @Environment(BookmarksModel.self) private var bookmarks
    @Environment(ChaptersModel.self) private var chapters
    @Environment(PlayerModel.self) private var player
    @Environment(AppModel.self) private var app
    @State private var selectedBookmark: Bookmark.ID?
    @State private var editingBookmark: Bookmark?
    @State private var bookmarkName = ""
    @FocusState private var bookmarkEditorFocused: Bool
    @FocusState private var focusedQueueItem: QueueItem.ID?
    @FocusState private var focusedBookmark: Bookmark.ID?
    @State private var isDropTargeted = false
    @State private var showsSort = false
    /// The key of the last sort run from this panel; the engine has no persistent sort order.
    @State private var lastSortKey: QueueSortKey?
    public init(tab: QueuePanelTab = .queue) { self.tab = tab }
    public var body: some View {
        let box = Theme.Metric.SidePanels.queuePanel
        PanelSurface {
            VStack(spacing: box.gap) {
                PanelTabStrip(tabs: QueuePanelTab.allCases, selected: tab, title: { $0.title }, icon: {
                    switch $0 { case .queue: .queue; case .bookmarks: .bookmarks; case .chapters: .chapters } // 2127:7555 → 2461:9714.
                }, width: { _ in Theme.Metric.SidePanels.tabCell3.width }) { ui.selectTab(.queue($0)) }
                switch tab {
                case .queue: queueBody
                case .bookmarks: bookmarksBody
                case .chapters: chaptersBody
                }
            }
        }.frame(maxWidth: box.width, maxHeight: box.height)
        // G-03: while a list row has keyboard focus, Return, arrows and Delete reach the list
        // instead of VLC's hotkeys (see MXRKeyRouting); Space stays play/pause.
        .onChange(of: focusedQueueItem) { updateListFocus() }
        .onChange(of: focusedBookmark) { updateListFocus() }
        .onChange(of: tab) { saveBookmarkName() }
        .onDisappear { saveBookmarkName(); ui.panelListHasKeyboardFocus = false }
    }
    private var queueBody: some View {
        VStack(spacing: Theme.Metric.SidePanels.queuePanel.gap) {
            HStack(spacing: Theme.Spacing.gap10) {
                // P17: narrow panels drop the total duration rather than truncating "4 item…".
                ViewThatFits(in: .horizontal) {
                    Text(queue.summary)
                    Text(queue.items.count == 1 ? "1 item" : "\(queue.items.count) items")
                }
                .foregroundStyle(Theme.Color.fgA3).lineLimit(1)
                .accessibilityLabel(queue.summary)
                Spacer(minLength: 0)
                // 463:842: 180 pt action group, 12 pt gaps; 24/30 pt cells and FG/A3 instance strokes.
                HStack(spacing: PanelSpace.md) {
                    PanelIconButton(icon: .sort, label: "Sort queue", width: Theme.Metric.iconSize, tint: Theme.Color.fgA3) { showsSort = true }
                        .mxrPopupMenu(isPresented: $showsSort, placement: .below(.trailing), style: .textMenu) {
                            QueueSortKey.allCases.map { key in
                                MXRMenuItem(key.title, isChecked: lastSortKey == key) { lastSortKey = key; queue.sort(by: key) }
                            }
                        }
                    PanelIconButton(icon: .repeatRight, label: "Repeat: \(queue.repeatMode.rawValue)", active: queue.repeatMode != .off, tint: Theme.Color.fgA3) { queue.cycleRepeatMode() }
                    PanelIconButton(icon: .shuffleRight, label: "Shuffle", active: queue.isShuffled, tint: Theme.Color.fgA3) { queue.toggleShuffle() }
                    PanelIconButton(icon: .remove, label: "Remove selected items", width: Theme.Metric.iconSize, tint: Theme.Color.fgA3, preservesDisabledTint: true) { queue.removeSelection() }.disabled(queue.selection.isEmpty)
                    PanelIconButton(icon: .add, label: "Add files to queue", width: Theme.Metric.iconSize, tint: Theme.Color.fgA3) { ui.request(.addFilesToQueue) } // 463:844/845: Remove precedes Add.
                }
            }
            .padding(Theme.Metric.SidePanels.queueHeaderRow.padding.edgeInsets)
            .frame(height: Theme.Metric.SidePanels.queueHeaderRow.height)
            ScrollView {
                VStack(spacing: PanelMetric.gap) {
                    ForEach(Array(queue.items.enumerated()), id: \.element.id) { index, item in
                        QueuePanelRow(item: item, selected: queue.selection.contains(item.id), current: queue.isCurrent(item),
                                      keyboardFocused: focusedQueueItem == item.id,
                                      select: { flags in select(item, modifiers: flags) }, play: { queue.play(item) }, remove: { queue.remove([item.id]) },
                                      addToPlaylist: addToPlaylistMenu(for: item),
                                      moveUp: { move(item, direction: -1) }, moveDown: { move(item, direction: 1) },
                                      drop: { acceptDrop($0, at: index) })
                            .focused($focusedQueueItem, equals: item.id)
                    }
                    if queue.isEmpty { empty("Queue is empty", detail: "Drop media here or add files.") }
                    Spacer(minLength: PanelSpace.xl)
                        .frame(maxWidth: .infinity).contentShape(Rectangle())
                        .onDrop(of: [.plainText, .url], isTargeted: $isDropTargeted) { acceptDrop($0, at: queue.items.count) }
                        .overlay(alignment: .top) { if isDropTargeted { QueueInsertionPlaceholder() } }
                }.padding(.horizontal, PanelSpace.xl)
            }.scrollIndicators(.hidden)
            .onDeleteCommand { queue.removeSelection() }
            .onMoveCommand { direction in
                let ids = queue.items.map(\.id)
                guard let next = PanelQueueInteraction.neighbor(in: ids, current: focusedQueueItem, direction: direction) else { return }
                focusedQueueItem = next
                queue.selection = [next]
            }
        }
    }
    private var bookmarksBody: some View {
        VStack(spacing: Theme.Metric.SidePanels.queuePanel.gap) {
            HStack(spacing: Theme.Spacing.gap10) {
                Text(bookmarks.summary).foregroundStyle(Theme.Color.fgA3).lineLimit(1)
                Spacer()
                HStack(spacing: PanelSpace.md) { // 6320:13803: − then +, as in the queue header.
                    PanelIconButton(icon: .remove, label: "Remove selected bookmark", width: Theme.Metric.iconSize) {
                        if let bookmark = bookmarks.bookmarks.first(where: { $0.id == selectedBookmark }) { bookmarks.remove(bookmark); selectedBookmark = nil }
                    }.disabled(selectedBookmark == nil)
                    PanelIconButton(icon: .add, label: "Add bookmark at current time", width: Theme.Metric.iconSize) { saveBookmarkName(); bookmarks.addAtCurrentTime() }
                        .disabled(player.media == nil)
                }
            }
            .padding(Theme.Metric.SidePanels.queueHeaderRow.padding.edgeInsets)
            .frame(height: PanelMetric.bookmarksHeaderHeight) // 6320:13801
            ScrollView {
                VStack(spacing: PanelMetric.gap) {
                    ForEach(bookmarks.bookmarks) { bookmark in
                        bookmarkRow(bookmark)
                    }
                    if bookmarks.bookmarks.isEmpty { empty("No bookmarks", detail: "Add a bookmark at the current time.") }
                }.padding(.horizontal, PanelSpace.xl)
            }.scrollIndicators(.hidden)
            .onMoveCommand { direction in
                guard let next = PanelQueueInteraction.neighbor(in: bookmarks.bookmarks.map(\.id), current: focusedBookmark, direction: direction) else { return }
                focusedBookmark = next
                selectedBookmark = next
            }
        }
    }
    private func bookmarkRow(_ bookmark: Bookmark) -> some View {
        HStack(spacing: Theme.Spacing.gap10) {
            if editingBookmark?.id == bookmark.id {
                // Styled like PanelTextField (4046:12353); clicking away saves, as Return does.
                TextField("Bookmark name", text: $bookmarkName)
                    .textFieldStyle(.plain)
                    .mxrTextStyle(Theme.Font.body)
                    .foregroundStyle(Theme.Color.fgA1)
                    .padding(.horizontal, PanelSpace.xs)
                    .frame(maxHeight: .infinity)
                    .background(Theme.Color.bgB2, in: .rect(cornerRadius: Theme.Radius.md))
                    .focused($bookmarkEditorFocused)
                    .onAppear { bookmarkEditorFocused = true }
                    .onSubmit { saveBookmarkName() }
                    .onChange(of: bookmarkEditorFocused) { _, focused in if !focused { saveBookmarkName() } }
                    .onExitCommand { editingBookmark = nil }
            } else {
                Text(bookmark.name).lineLimit(1).foregroundStyle(Theme.Color.fgA1)
            } // 6320:13815
            Spacer(minLength: 0)
            Text(bookmark.time.formatted(.hoursMinutesSecondsMilliseconds)).foregroundStyle(Theme.Color.fgA3) // 6320:13816
        }
        .padding(.trailing, PanelSpace.xs)
        .frame(height: Theme.Metric.SidePanels.listRow.height)
        .panelRowFill(selected: selectedBookmark == bookmark.id)
        .overlay { if focusedBookmark == bookmark.id { PanelRowFocusRing() } }
        .contentShape(Rectangle())
        .onTapGesture {
            guard editingBookmark?.id != bookmark.id else { return }
            // Rows never take focus from the name field (D028), so a click on another row is the
            // click-away that saves the rename in progress.
            saveBookmarkName()
            selectedBookmark = bookmark.id; bookmarks.jump(to: bookmark)
        }
        .mxrContextMenu {
            MXRMenuItem("Jump to Bookmark") { bookmarks.jump(to: bookmark) }
            MXRMenuItem("Rename") { beginRename(bookmark) }
            MXRMenuItem("Remove") { bookmarks.remove(bookmark) }
        }
        // Keyboard focus only (Tab with Full Keyboard Access); a click never focuses (D028).
        .focusable(true, interactions: .activate)
        .focusEffectDisabled()
        .focused($focusedBookmark, equals: bookmark.id)
        .accessibilityAction(named: "Rename") { beginRename(bookmark) }
        .accessibilityAction(named: "Remove") { bookmarks.remove(bookmark) }
        .onKeyPress(.return) { selectedBookmark = bookmark.id; focusedBookmark = bookmark.id; bookmarks.jump(to: bookmark); return .handled }
        .onDeleteCommand { bookmarks.remove(bookmark) }
        .accessibilityElement(children: editingBookmark?.id == bookmark.id ? .contain : .combine)
        .accessibilityAddTraits(editingBookmark?.id == bookmark.id ? [] : .isButton)
        .accessibilityAction { selectedBookmark = bookmark.id; focusedBookmark = bookmark.id; bookmarks.jump(to: bookmark) }
    }
    private var chaptersBody: some View {
        ScrollView {
            VStack(spacing: PanelMetric.gap) {
                ForEach(chapters.chapters) { chapter in
                    Button { chapters.select(chapter) } label: {
                        HStack(spacing: Theme.Spacing.gap10) {
                            Text(String(chapter.index + 1)).mxrTextStyle(Theme.Font.chapterNumber).foregroundStyle(Theme.Color.accentMain)
                                .frame(width: PanelMetric.chapterNumberWidth, alignment: .leading) // 6321:14070
                            Text(chapter.name).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(chapter.time.formatted(.hoursMinutesSeconds))
                        }
                        .foregroundStyle(Theme.Color.fgA2)
                        .padding(.horizontal, PanelSpace.xs)
                        .frame(height: Theme.Metric.SidePanels.listRow.height)
                    }.buttonStyle(PanelButtonStyle(kind: .row))
                        .accessibilityAddTraits(chapters.currentChapter?.id == chapter.id ? .isSelected : [])
                }
                if chapters.chapters.isEmpty { empty("No chapters", detail: "This media has no chapter markers.") }
            }.padding(.horizontal, PanelSpace.xl).padding(.top, PanelSpace.xl)
        }.scrollIndicators(.hidden)
    }
    private func beginRename(_ bookmark: Bookmark) {
        saveBookmarkName()
        bookmarkName = bookmark.name; editingBookmark = bookmark
    }
    private func saveBookmarkName() {
        guard let bookmark = editingBookmark else { return }
        let text = bookmarkName.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty name cancels the rename and keeps the old one.
        if !text.isEmpty, text != bookmark.name { bookmarks.rename(bookmark, to: text) }
        editingBookmark = nil
    }
    private func updateListFocus() {
        ui.panelListHasKeyboardFocus = focusedQueueItem != nil || focusedBookmark != nil
    }
    private func addToPlaylistMenu(for item: QueueItem) -> MXRMenuItem {
        PanelQueueInteraction.addToPlaylistMenu(app, for: item)
    }
    private func select(_ item: QueueItem, modifiers: NSEvent.ModifierFlags) {
        queue.selection = PanelQueueInteraction.selection(current: queue.selection, clicked: item.id, modifiers: modifiers)
    }
    private func move(_ item: QueueItem, direction: Int) {
        guard let index = queue.items.firstIndex(where: { $0.id == item.id }),
              let destination = PanelQueueInteraction.moveDestination(index: index, count: queue.items.count, direction: direction) else { return }
        queue.move([item.id], to: destination)
    }
    private func acceptDrop(_ providers: [NSItemProvider], at index: Int) -> Bool {
        let providers = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) || $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }
        guard !providers.isEmpty else { return false }
        Task { @MainActor in
            var media: [MediaItem] = []
            for provider in providers {
                let type = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ? UTType.fileURL.identifier : (provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ? UTType.url.identifier : UTType.plainText.identifier)
                let data: Data? = await withCheckedContinuation { continuation in
                    provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in continuation.resume(returning: data) }
                }
                guard let data, let text = String(data: data, encoding: .utf8) else { continue }
                // A multi-row library drag carries one URL per line.
                for line in text.split(whereSeparator: \.isNewline) {
                    switch PanelDropPayload(text: String(line)) {
                    case .queueItem(let id): queue.move([id], to: index)
                    case .url(let url): media.append(MediaItem(url: url))
                    case nil: continue
                    }
                }
            }
            if !media.isEmpty { queue.insert(media, at: index) }
        }
        return true
    }
    private func empty(_ title: String, detail: String) -> some View {
        VStack(spacing: Theme.Spacing.gap8) {
            Text(title).foregroundStyle(Theme.Color.fgA2)
            Text(detail).mxrTextStyle(Theme.Font.caption).foregroundStyle(Theme.Color.fgA3)
        }.frame(maxWidth: .infinity).padding(.vertical, PanelSpace.xl)
    }
}

/// The dim "•••" row at a queue drop position (video 20m21.4).
private struct QueueInsertionPlaceholder: View {
    var body: some View {
        Text("•••").foregroundStyle(Theme.Color.fgA4)
            .frame(maxWidth: .infinity).frame(height: Theme.Metric.SidePanels.listRow.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct QueuePanelRow: View {
    let item: QueueItem
    let selected: Bool
    let current: Bool
    let keyboardFocused: Bool
    let select: (NSEvent.ModifierFlags) -> Void
    let play: @MainActor () -> Void
    let remove: @MainActor () -> Void
    let addToPlaylist: MXRMenuItem
    let moveUp: @MainActor () -> Void
    let moveDown: @MainActor () -> Void
    let drop: ([NSItemProvider]) -> Bool
    @State private var isTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var rowContent: some View {
        HStack(spacing: Theme.Spacing.gap10) {
            // 463:849 → 463:417 neutral drag handle; the current item shows the outline ▷ in orange (20m21.4).
            Group {
                if current { MXRIcon(.playback, tint: Theme.Color.accentMain) } else { MXRIcon(.move) }
            }
            .frame(width: Theme.Metric.SidePanels.listRow.height, height: Theme.Metric.SidePanels.listRow.height)
            Text(item.media.listTitle).lineLimit(1)
                .foregroundStyle(current ? Theme.Color.accentMain : Theme.Color.fgA1) // 463:850, fill 247:711.
            Spacer(minLength: 0)
            Text(item.media.duration?.formatted(.compact) ?? "—")
                .foregroundStyle(Theme.Color.fgA3) // 491:2378, fill 217:229; also on the current row (20m21.4).
        }
        .foregroundStyle(current ? Theme.Color.accentMain : Theme.Color.fgA2)
        .padding(.trailing, PanelSpace.xs).frame(height: Theme.Metric.SidePanels.listRow.height)
        .panelRowFill(selected: selected)
        .overlay { if keyboardFocused { PanelRowFocusRing() } }
        .contentShape(Rectangle())
    }
    private var selectableRow: some View {
        rowContent
        // The single click selects at once, alongside double-click recognition (as LibraryEntryView).
        .onTapGesture(count: 2, perform: play)
        .simultaneousGesture(TapGesture().onEnded {
            select(NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask))
        })
        // Keyboard focus only (Tab with Full Keyboard Access); a click never focuses (D028).
        .focusable(true, interactions: .activate)
        .focusEffectDisabled()
        .onKeyPress(.return) { play(); return .handled }
        .onKeyPress(.upArrow, phases: .down) { press in
            guard press.modifiers.contains(.option) else { return .ignored }
            moveUp(); return .handled
        }
        .onKeyPress(.downArrow, phases: .down) { press in
            guard press.modifiers.contains(.option) else { return .ignored }
            moveDown(); return .handled
        }
    }
    var body: some View {
        selectableRow
        .onDrag { NSItemProvider(object: "mxr-queue:\(item.id)" as NSString) }
        .onDrop(of: [.plainText, .url], isTargeted: $isTargeted.animation(reduceMotion ? nil : .easeOut(duration: MXRPopupMotion.insertion)), perform: drop)
        // 20m21.4: the drop point opens a dim "•••" row where the item will land.
        .padding(.top, isTargeted ? Theme.Metric.SidePanels.listRow.height + PanelMetric.gap : 0)
        .overlay(alignment: .top) { if isTargeted { QueueInsertionPlaceholder() } }
        .mxrContextMenu {
            PanelQueueInteraction.rowMenu(play: play, addToPlaylist: addToPlaylist, moveUp: moveUp, moveDown: moveDown, remove: remove)
        }
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Play", play).accessibilityAction(named: "Select") { select([]) }
        .accessibilityAction(named: "Move Up", moveUp)
        .accessibilityAction(named: "Move Down", moveDown)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The design's keyboard focus ring on a list row (D028), in place of the system accent ring.
private struct PanelRowFocusRing: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.md)
            .strokeBorder(Theme.Color.fgA1, lineWidth: Theme.Stroke.iconActive)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Shared by pointer, keyboard and accessibility entry points.
enum PanelQueueInteraction {
    /// A queue row's right-click menu.
    @MainActor static func rowMenu(play: @escaping @MainActor () -> Void, addToPlaylist: MXRMenuItem,
                                   moveUp: @escaping @MainActor () -> Void, moveDown: @escaping @MainActor () -> Void,
                                   remove: @escaping @MainActor () -> Void) -> [MXRMenuItem] {
        [MXRMenuItem("Play", action: play), addToPlaylist, MXRMenuItem("Move Up", action: moveUp),
         MXRMenuItem("Move Down", action: moveDown), MXRMenuItem("Remove from Queue", action: remove)]
    }
    /// D-07: the queue row's "Add to Playlist" is the shared submenu of the library, mini player and
    /// player menus. A row inside a multi-row selection adds the whole selection, in queue order.
    @MainActor static func addToPlaylistMenu(_ app: AppModel, for item: QueueItem) -> MXRMenuItem {
        let queue = app.queue
        return MXRPlayerMenus.addToPlaylist(app, isEnabled: app.capabilities.hasMediaLibrary,
                                            newPlaylist: { [app] in app.presentNewPlaylist(media: media(for: item, in: queue)) },
                                            media: { media(for: item, in: queue) },
                                            onError: { [app] title, error in app.dialogs.presentError(error, title: title) })
    }
    static func selection(current: Set<QueueItem.ID>, clicked: QueueItem.ID, modifiers: NSEvent.ModifierFlags) -> Set<QueueItem.ID> {
        guard modifiers.contains(.command) else { return [clicked] }
        var result = current
        if result.contains(clicked) { result.remove(clicked) } else { result.insert(clicked) }
        return result
    }
    /// What a row's "Add to Playlist" adds: the selection when the row is part of it, else the row.
    @MainActor static func media(for item: QueueItem, in queue: QueueModel) -> [MediaItem] {
        guard queue.selection.contains(item.id), queue.selection.count > 1 else { return [item.media] }
        return queue.items.filter { queue.selection.contains($0.id) }.map(\.media)
    }
    static func neighbor<ID: Hashable>(in ids: [ID], current: ID?, direction: MoveCommandDirection) -> ID? {
        guard !ids.isEmpty, direction == .up || direction == .down else { return nil }
        guard let current, let index = ids.firstIndex(of: current) else { return ids.first }
        let next = index + (direction == .up ? -1 : 1)
        return ids.indices.contains(next) ? ids[next] : nil
    }
    static func moveDestination(index: Int, count: Int, direction: Int) -> Int? {
        let target = index + direction
        guard (0..<count).contains(target) else { return nil }
        // QueueBackend takes an insertion index before removal of the source row.
        return direction > 0 ? target + 1 : target
    }
}
