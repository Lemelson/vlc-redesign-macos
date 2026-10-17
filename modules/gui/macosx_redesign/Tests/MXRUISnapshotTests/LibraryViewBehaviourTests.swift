import AppKit
import MXRCore
import MXRDesign
import MXRMockBackend
@testable import MXRUI
import SwiftUI
import XCTest

/// Behaviour of the drawn library (E-07, E-10, E-11, mixed-import notice, minimum width), read and
/// driven through the accessibility tree of a hosting view in a window never ordered on screen.
@MainActor
final class LibraryViewBehaviourTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        windows.forEach { $0.close() }
        windows = []
    }

    // MARK: Hosting and accessibility

    private func host<V: View>(_ view: V, size: CGSize) async throws -> NSHostingView<AnyView> {
        _ = NSApplication.shared
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXManualAccessibility"))
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        let host = NSHostingView(rootView: AnyView(view.frame(width: size.width, height: size.height)))
        window.contentView = host
        try await settle(host)
        return host
    }

    private func settle(_ host: NSView) async throws {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
    }

    // SwiftUI AX nodes expose the Objective-C selectors without conforming to NSAccessibility.
    private func value(_ object: NSObject, _ method: String) -> Any? {
        let selector = NSSelectorFromString(method)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }
    private func elements(_ object: Any) -> [NSObject] {
        guard let node = object as? NSObject else { return [] }
        return [node] + ((value(node, "accessibilityChildren") as? [Any]) ?? []).flatMap(elements)
    }
    private func label(_ element: NSObject) -> String? { value(element, "accessibilityLabel") as? String }
    private func frame(_ element: NSObject) -> NSRect { (element.value(forKey: "accessibilityFrame") as? NSRect) ?? .zero }
    private func buttons(_ host: NSView) -> [NSObject] {
        elements(host).filter { value($0, "accessibilityRole") as? String == NSAccessibility.Role.button.rawValue }
    }
    private func press(_ element: NSObject) {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        typealias Press = @convention(c) (AnyObject, Selector) -> Bool
        _ = unsafeBitCast(element.method(for: selector), to: Press.self)(element, selector)
    }

    // MARK: E-07

    /// ↓ selects the card drawn directly below, ← / → the neighbour: the arrow keys follow the
    /// columns the grid draws (E-07), not the list order.
    func testArrowKeysFollowTheDrawnGridColumns() async throws {
        let app = AppModel.mock(.idle)
        app.library.navigate(to: .folder(MockMediaID.theWandS01Folder))
        app.library.fullViewMode = .grid
        app.interface.library = .full
        let size = CGSize(width: 1600, height: 900)
        let host = try await host(MXRLibraryView().appModel(app), size: size)
        let entries = app.library.entries
        let cards = buttons(host).filter { button in entries.contains { $0.title == label(button) } }
        XCTAssertEqual(cards.count, entries.count, "every card is drawn")
        // AX frames are bottom-left based: a drawn row shares its maxY.
        let firstRowTop = frame(cards[0]).maxY
        let drawnColumns = cards.filter { abs(frame($0).maxY - firstRowTop) < 1 }.count
        XCTAssertGreaterThan(drawnColumns, 1)

        let columns = MXRLibraryView.columns(mode: .grid, compact: false, music: false, width: MXRLibraryView.contentWidth(size.width, compact: false))
        XCTAssertEqual(columns, drawnColumns, "the keys use the drawn column count")
        let below = try XCTUnwrap(cards.first { abs(frame($0).minX - frame(cards[1]).minX) < 1 && frame($0).maxY < firstRowTop - 1 })

        app.library.select(entries[1])
        app.library.moveSelection(by: try XCTUnwrap(MXRLibraryView.arrowOffset(.downArrow, columns: columns)), extending: false)
        XCTAssertEqual(app.library.selection.compactMap { id in entries.first { $0.id == id }?.title }, [label(below)], "↓ selects the card drawn below")
        app.library.moveSelection(by: try XCTUnwrap(MXRLibraryView.arrowOffset(.upArrow, columns: columns)), extending: false)
        XCTAssertEqual(app.library.selection, [entries[1].id], "↑ comes back")
        app.library.moveSelection(by: try XCTUnwrap(MXRLibraryView.arrowOffset(.rightArrow, columns: columns)), extending: false)
        XCTAssertEqual(app.library.selection, [entries[2].id], "→ moves to the card drawn on the right")
        XCTAssertEqual(abs(frame(cards[2]).maxY - firstRowTop) < 1, true)
        XCTAssertEqual(MXRLibraryView.arrowOffset(.downArrow, columns: MXRLibraryView.columns(mode: .list, compact: true, music: false, width: 300)), 1,
                       "the compact list is one column")
    }

    // MARK: E-10

    /// With two rows of a playlist selected, the row card offers and removes both (E-10).
    func testRemoveFromPlaylistActsOnTheWholeSelection() async throws {
        let app = AppModel.mock(.idle)
        let library = try XCTUnwrap(app.backends.library as? MockLibrary)
        let playlists = try await library.page(at: .playlists, query: LibraryQuery()).entries.compactMap { entry -> Playlist? in
            if case .playlist(let playlist) = entry { return playlist }; return nil
        }
        let playlist = try XCTUnwrap(playlists.first { $0.itemCount >= 3 })
        app.library.navigate(to: .playlist(playlist.id))
        for _ in 0..<400 where app.library.entries.count < playlist.itemCount { await Task.yield() }
        let entries = app.library.entries
        app.library.select(entries[0])
        app.library.select(entries[2], toggling: true)
        let media = try XCTUnwrap(entries[2].media)

        let host = try await host(MXRLibraryPopupView(kind: .file(media)).appModel(app),
                                  size: CGSize(width: Theme.Metric.Menus.contextMenu.width, height: Theme.Metric.Menus.contextMenuRow.height * 16))
        XCTAssertNil(buttons(host).first { label($0) == "Remove from Playlist" }, "a selected row does not offer to remove only itself")
        let remove = try XCTUnwrap(buttons(host).first { label($0) == "Remove 2 Items from Playlist" })
        press(remove)
        let remaining = { try await library.page(at: .playlist(playlist.id), query: LibraryQuery(sort: .oldestFirst)).entries.compactMap(\.media?.id) }
        var ids = try await remaining()
        for _ in 0..<200 where ids.count != playlist.itemCount - 2 { await Task.yield(); ids = try await remaining() }
        XCTAssertEqual(ids, entries.enumerated().filter { $0.offset != 0 && $0.offset != 2 }.compactMap(\.element.media?.id),
                       "both selected occurrences are removed, the others stay in order")
    }

    // MARK: E-11

    /// A row's own state (the open ⋯ card brightens its label) stays with its entry when the rows
    /// above it go away (E-11): rows are keyed by entry, not by position. (Playlist rows carry their
    /// occurrence revision in the key on purpose, so a changed playlist starts fresh.)
    func testRowStateFollowsItsEntryWhenRowsAboveGoAway() async throws {
        let app = AppModel.mock(.idle)
        app.library.navigate(to: .folder(MockMediaID.theWandS01Folder))
        for _ in 0..<400 where app.library.entries.isEmpty { await Task.yield() }
        let host = try await host(MXRLibraryView(compact: true).appModel(app), size: Theme.Metric.Library.sidebar.size)
        let entries = app.library.entries
        let target = entries[2]
        let row = try XCTUnwrap(buttons(host).first { label($0) == target.title })
        let actions = try XCTUnwrap(value(row, "accessibilityCustomActions") as? [NSAccessibilityCustomAction])
        let show = try XCTUnwrap(actions.first { $0.name == "Show actions" })
        _ = show.handler?() ?? show.target?.perform(show.selector)
        try await settle(host)
        XCTAssertEqual(brightRows(host, entries.map(\.title)), [target.title], "the open card brightens its own row")

        // A search that keeps only the target removes the two rows above it.
        app.library.searchText = target.title
        for _ in 0..<200 where app.library.entries.count != 1 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(app.library.entries.map(\.id), [target.id])
        try await settle(host)
        XCTAssertEqual(brightRows(host, [target.title]), [target.title], "the state moved up with its entry")
    }

    /// Titles of rows whose label is drawn at the hover/open color (FG/2), read from the pixels.
    private func brightRows(_ host: NSHostingView<AnyView>, _ titles: [String]) -> [String] {
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return [] }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        var result: [String] = []
        for button in buttons(host) {
            guard let title = label(button), titles.contains(title) else { continue }
            // The label starts after the 32 pt thumb and the row gap; AX frames are bottom-left based.
            let rect = frame(button)
            let x0 = rect.minX + Theme.Metric.Library.thumb.width + Theme.Metric.Library.mediaRow.gap
            var brightest: CGFloat = 0
            for px in stride(from: x0, to: min(rect.maxX, x0 + 120), by: 0.5) {
                for py in stride(from: rect.minY + 4, to: rect.maxY - 4, by: 0.5) {
                    let x = Int(px * scale), y = Int((host.bounds.height - py) * scale)
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    brightest = max(brightest, color.redComponent)
                }
            }
            // Resting rows draw at FG/A1 or FG/A3; FG/2 is clearly brighter.
            if brightest > 0.8 { result.append(title) }
        }
        return result
    }

    // MARK: Mixed import notice

    /// The Videos notice of a mixed import opens Songs with the songs selected.
    func testImportNoticeRowOpensTheImportedSongs() async throws {
        let app = AppModel.mock(.idle)
        let song = URL(fileURLWithPath: "/Users/Shared/Media/Imported/Song.flac")
        try await app.library.importFiles(urls: [URL(fileURLWithPath: "/Users/Shared/Media/Imported/Clip.mp4"), song])
        for _ in 0..<400 where app.library.selection.isEmpty { await Task.yield() }
        let host = try await host(MXRLibraryView(compact: true).appModel(app), size: Theme.Metric.Library.sidebar.size)
        let notice = try XCTUnwrap(buttons(host).first { label($0) == "1 song was added to Music ▸ Songs." }, "Videos says where the song went")
        press(notice)
        for _ in 0..<400 where app.library.location != .songs || app.library.selection.isEmpty { await Task.yield() }
        XCTAssertEqual(app.library.location, .songs)
        XCTAssertEqual(app.library.selection, [LibraryEntry.media(MediaItem(url: song)).id])
    }

    // MARK: Minimum window

    /// At the 480 pt minimum window the compact panel gets 216 pt; everything it draws stays inside.
    func testCompactPanelDrawsInsideTheMinimumColumn() async throws {
        let app = AppModel.mock(.playingEpisode)
        app.library.navigate(to: .folder(MockMediaID.theWandS01Folder))
        let width = Theme.Metric.Window.player.width / 4 * 0.45
        let host = try await host(MXRLibraryView(compact: true).appModel(app), size: CGSize(width: width, height: Theme.Metric.Library.sidebar.height / 2))
        let controls = buttons(host)
        XCTAssertNotNil(controls.first { label($0) == "Back" })
        XCTAssertNotNil(controls.first { label($0) == "More library actions" })
        for control in controls {
            XCTAssertLessThanOrEqual(frame(control).maxX, width + 0.5, "\(label(control) ?? "?") is drawn past the column")
        }
        XCTAssertLessThan(width, LibraryGeometry.compactFullHeaderWidth)
        XCTAssertGreaterThanOrEqual(width, LibraryGeometry.compactMinimumWidth)
    }
}
