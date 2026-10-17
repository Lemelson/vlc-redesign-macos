import AppKit
import MXRCore
import MXRDesign
import SwiftUI

/// Library mini player, with a real video host supplied by the app (S46).
public struct MXRMiniPlayerView: View {
    @Environment(AppModel.self) private var app
    @Environment(PlayerModel.self) private var player
    @Environment(QueueModel.self) private var queue
    @Environment(InterfaceModel.self) private var ui
    @Environment(\.mxrLibraryPreviewHover) private var previewHover
    let videoView: AnyView
    let maximumHeight: CGFloat?
    /// Moves the card (the dock passes its corner-snapping drag); nil keeps the card fixed.
    var cardDrag: AnyGesture<DragGesture.Value>?
    /// ✕: stops playback and hides the card (the dock decides how).
    var close: (() -> Void)?
    @State private var hovered = false
    @State private var videoHovered = false
    @State private var sortPresented = false
    @State private var actionError: String?

    public init(videoView: AnyView = AnyView(Color.clear), maximumHeight: CGFloat? = nil) {
        self.videoView = videoView; self.maximumHeight = maximumHeight
    }

    init(videoView: AnyView, maximumHeight: CGFloat?, cardDrag: AnyGesture<DragGesture.Value>?, close: (() -> Void)?) {
        self.videoView = videoView; self.maximumHeight = maximumHeight; self.cardDrag = cardDrag; self.close = close
    }

    private var overlayVisible: Bool { videoHovered || previewHover == MXRLibraryPreview.miniPlayer }
    /// Playback reached the end of the queue: Figma's replay variant (1919:9515).
    private var ended: Bool { player.state == .stopped && player.media != nil }

    public var body: some View {
        VStack(spacing: Theme.Metric.Miniplayer.collapsed.gap) {
            if showsQueue { queueSection }
            VStack(spacing: Theme.Metric.Miniplayer.videoBlock.gap) {
                ZStack {
                    Rectangle().fill(Theme.Color.bgB2)
                    if ended { Rectangle().fill(Theme.Color.bgA2) }
                    else if player.isAudioOnly { MXRMediaArtwork() }
                    else { videoView }
                    if overlayVisible || ended { overlayControls }
                }
                .frame(width: videoSize.width, height: videoSize.height)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg).strokeBorder(Theme.Color.bgB2, lineWidth: Theme.Spacing.gap2))
                .contentShape(Rectangle())
                .onHover { videoHovered = $0 }
                .modifier(OptionalCardDrag(gesture: cardDrag))
                MiniSeekBar(showsPlayhead: overlayVisible || ended)
            }
            .frame(height: videoBlockHeight, alignment: .top)
            VStack(alignment: .leading, spacing: Theme.Metric.Miniplayer.infoBlock.gap) {
                Text(player.media?.listTitle ?? "VLC Media Player")
                    .mxrTextStyle(Theme.Font.bodyLarge).foregroundStyle(Theme.Color.fgA1).lineLimit(1)
                    .frame(height: LibraryGeometry.cardCaptionHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    if let folder = player.media?.folder {
                        Button {
                            app.library.navigate(to: .folder(folder.id))
                        } label: {
                            HStack(spacing: Theme.Spacing.gap8) {
                                MXRIcon(.folder)
                                Text(folder.name).mxrTextStyle(Theme.Font.bodyLarge).foregroundStyle(Theme.Color.fgA1).lineLimit(1)
                            }
                        }.buttonStyle(.plain).help("Open \(folder.name)")
                    }
                    if let artist = player.media?.artist, !artist.isEmpty {
                        Button {
                            if player.media?.kind == .audio {
                                app.library.navigate(to: .artists)
                                app.library.searchText = artist
                            } else if let folder = player.media?.folder {
                                app.library.navigate(to: .folder(folder.id))
                            } else {
                                app.library.select(.videos)
                                app.library.searchText = artist
                            }
                        } label: {
                            HStack(spacing: Theme.Spacing.gap8) {
                                MXRIcon(.artist)
                                Text(artist).mxrTextStyle(Theme.Font.bodyLarge).foregroundStyle(Theme.Color.fgA1).lineLimit(1)
                            }
                        }.buttonStyle(.plain).help("Browse music by \(artist)")
                        .padding(.leading, Theme.Spacing.gap20 - Theme.Spacing.gap8)
                    }
                    Spacer(minLength: 0)
                    LibraryIconButton(icon: .lists, label: showsQueue ? "Collapse queue" : "Expand queue", active: showsQueue,
                                      enabled: queueHeight >= Self.minimumQueueHeight) {
                        ui.isMiniPlayerQueueExpanded.toggle()
                    }
                    .frame(width: Theme.Metric.ControlBar.iconButton.width)
                    .help(queueHeight >= Self.minimumQueueHeight ? "Show or hide the queue" : "Make the window taller to expand the queue")
                }.frame(height: Theme.Metric.Library.thumb.height)
            }
            .padding(Theme.Metric.Miniplayer.infoBlock.padding)
            .frame(height: Theme.Metric.Miniplayer.infoBlock.height)
            .contentShape(Rectangle())
            .modifier(OptionalCardDrag(gesture: cardDrag))
        }
        .padding(Theme.Metric.Miniplayer.collapsed.padding)
        .frame(width: Theme.Metric.Miniplayer.collapsed.width)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xxl))
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.xxl).fill(Theme.Color.bgA3)
                .mxrShadow(Theme.Effect.miniplayerShadow)
        }
        .onHover { hovered = $0 }
        .alert("Queue action failed", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK") { actionError = nil }
        } message: { Text(actionError ?? "") }
    }

    /// Hover variant 975:4333: a 60 % black scrim, ✕ (top left), ↗ (top right) and large white
    /// ⏮ ▶ ⏭ without a pill; at the end of the queue ▶ becomes ↻ (1919:9515) on a plain BG/A2 fill.
    private var overlayControls: some View {
        ZStack {
            if !ended { Rectangle().fill(LibraryPaint.miniHoverScrim) }
            VStack(spacing: 0) {
                HStack {
                    MiniOverlayButton(icon: .close, label: "Stop and close the mini player", size: Theme.Metric.iconSize) {
                        if let close { close() } else { player.stop() }
                    }
                    Spacer(minLength: 0)
                    MiniOverlayButton(icon: .open, label: "Return to player", size: Theme.Metric.iconSize) { ui.library = .compact }
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.gap16)
            GeometryReader { video in
            HStack(spacing: LibraryGeometry.miniTransportGap) {
                MiniOverlayButton(icon: .previous, label: "Previous", size: LibraryGeometry.miniTransportIcon, enabled: queue.hasPrevious) { queue.previous() }
                    .frame(width: LibraryGeometry.miniTransportCell.width, height: LibraryGeometry.miniTransportCell.height)
                if ended {
                    MiniOverlayButton(icon: .replay, label: "Play again", size: LibraryGeometry.miniTransportIcon) {
                        if let item = queue.currentItem ?? queue.items.first { queue.play(item) } else { player.play() }
                    }
                } else {
                    MiniOverlayButton(icon: player.isPlaying ? .pause : .play, label: player.isPlaying ? "Pause" : "Play",
                                      size: LibraryGeometry.miniTransportIcon) { player.togglePlayPause() }
                }
                MiniOverlayButton(icon: .next, label: "Next", size: LibraryGeometry.miniTransportIcon, enabled: queue.hasNext) { queue.next() }
                    .frame(width: LibraryGeometry.miniTransportCell.width, height: LibraryGeometry.miniTransportCell.height)
            }
            .position(x: video.size.width * LibraryGeometry.miniTransportCenter.x / LibraryGeometry.miniVideoSize.width,
                      y: video.size.height * LibraryGeometry.miniTransportCenter.y / LibraryGeometry.miniVideoSize.height)
            }
        }
    }

    private var videoSize: CGSize {
        let naturalHeight = LibraryGeometry.miniVideoSize.height
        return CGSize(width: LibraryGeometry.miniVideoSize.width,
                      height: videoBlockHeight >= LibraryGeometry.miniExpandedVideoBlock ? naturalHeight : min(naturalHeight, max(0, videoBlockHeight - LibraryGeometry.miniSeekHeight - Theme.Metric.Miniplayer.videoBlock.gap)))
    }

    private var queueHeight: CGFloat {
        guard let maximumHeight else { return Theme.Metric.Miniplayer.queue.height }
        if maximumHeight >= Theme.Metric.Miniplayer.expanded.height { return Theme.Metric.Miniplayer.queue.height }
        let roomWithNaturalVideo = maximumHeight - Theme.Metric.Miniplayer.collapsed.height - Theme.Metric.Miniplayer.collapsed.gap
        let roomWithReducedVideo = maximumHeight - Self.minimumExpandedHeight + Self.minimumQueueHeight
        guard roomWithReducedVideo >= Self.minimumQueueHeight else { return 0 }
        return min(Theme.Metric.Miniplayer.queue.height, max(Self.minimumQueueHeight, roomWithNaturalVideo))
    }
    private var showsQueue: Bool { ui.isMiniPlayerQueueExpanded && queueHeight >= Self.minimumQueueHeight }
    private var videoBlockHeight: CGFloat {
        let naturalHeight = showsQueue ? Theme.Metric.Miniplayer.expanded.height : Theme.Metric.Miniplayer.collapsed.height
        let limit = min(maximumHeight ?? naturalHeight, naturalHeight)
        let reduced = limit - Theme.Metric.Miniplayer.infoBlock.height - Theme.Metric.Miniplayer.collapsed.gap
            - Theme.Metric.Miniplayer.collapsed.padding.top - Theme.Metric.Miniplayer.collapsed.padding.bottom
            - (showsQueue ? queueHeight + Theme.Metric.Miniplayer.collapsed.gap : 0)
        return max(LibraryGeometry.miniSeekHeight, min(Theme.Metric.Miniplayer.videoBlock.height, reduced))
    }
    // Keep its 50pt title, 64pt tools header and one 32pt row visible in constrained windows.
    private static var minimumQueueHeight: CGFloat {
        Theme.Metric.SidePanels.tabStrip.height * 2 + Theme.Spacing.gap14 + Theme.Spacing.gap2 + Theme.Metric.Library.thumb.height
    }
    private static var minimumExpandedHeight: CGFloat {
        Theme.Metric.Miniplayer.videoBlock.height / 2 + Theme.Metric.Miniplayer.infoBlock.height
            + Theme.Metric.Miniplayer.collapsed.gap * 2 + Theme.Metric.Miniplayer.collapsed.padding.top
            + Theme.Metric.Miniplayer.collapsed.padding.bottom + minimumQueueHeight
    }
    static func fittingHeight(expanded: Bool, available: CGFloat) -> CGFloat {
        let expandedFits = expanded && available >= minimumExpandedHeight
        return min(available, expandedFits ? Theme.Metric.Miniplayer.expanded.height : Theme.Metric.Miniplayer.collapsed.height)
    }

    private var queueSection: some View {
        VStack(spacing: Theme.Spacing.gap1) {
            // Mini-player Queue title/header/rows: 970:4274, 970:3188, 970:3196.
            Text("Queue").mxrTextStyle(Theme.Font.bodyLarge).foregroundStyle(Theme.Color.fgA2)
                .frame(maxWidth: .infinity).frame(height: Theme.Metric.SidePanels.tabStrip.height + Theme.Spacing.gap8)
                .background(Theme.Color.bgA5)
                .padding(.horizontal, -Theme.Spacing.gap8)
                .padding(.top, -Theme.Spacing.gap8)
            HStack(spacing: Theme.Spacing.gap10) {
                Text(queue.summary).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA3).lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: Theme.Spacing.gap20) {
                    LibraryIconButton(icon: .sort, label: "Sort queue", active: sortPresented, tool: true) { sortPresented.toggle() }
                        .mxrPopupMenu(isPresented: $sortPresented, placement: .below(.trailing), style: .textMenu) {
                            QueueSortKey.allCases.map { key in MXRMenuItem(key.title) { queue.sort(by: key) } }
                                + [.separator,
                                   MXRMenuItem(queue.isShuffled ? "Disable Shuffle" : "Shuffle") { queue.toggleShuffle() },
                                   MXRMenuItem("Repeat: \(queue.repeatMode.rawValue)") { queue.cycleRepeatMode() }]
                        }
                    LibraryIconButton(icon: .remove, label: "Remove selected queue items", enabled: !queue.selection.isEmpty, tool: true) { queue.removeSelection() }
                    LibraryIconButton(icon: .add, label: "Add files to queue", tool: true) { ui.request(.addFilesToQueue) }
                }
            }
            .padding(.leading, Theme.Spacing.gap20 + Theme.Spacing.gap8)
            .padding(.trailing, Theme.Spacing.gap20)
            .frame(height: Theme.Metric.SidePanels.tabStrip.height + Theme.Spacing.gap14)
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.gap12) {
                    ForEach(queue.items) { item in
                        Button { queue.play(item) } label: {
                            HStack(spacing: Theme.Spacing.gap10) {
                                MXRIcon(.move).frame(width: Theme.Metric.Library.thumb.width)
                                Text(item.media.listTitle).mxrTextStyle(Theme.Font.body)
                                    .foregroundStyle(Theme.Color.fgA1).lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(item.media.duration?.formatted(.compact) ?? "Live").mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA3)
                            }
                            .padding(.trailing, Theme.Spacing.gap4)
                            .frame(height: Theme.Metric.Library.thumb.height)
                        }
                        .buttonStyle(.plain)
                        .mxrContextMenu(style: .contextMenu) { [app, queue] in
                            MXRMenuItem(queue.selection.contains(item.id) ? "Deselect" : "Select") {
                                if queue.selection.contains(item.id) { queue.selection.remove(item.id) }
                                else { queue.selection.insert(item.id) }
                            }
                            MXRMenuItem("Remove from Queue") { queue.remove([item.id]) }
                            MXRPlayerMenus.addToPlaylist(app, isEnabled: app.capabilities.hasMediaLibrary,
                                                         newPlaylist: { app.presentNewPlaylist(media: [item.media]) },
                                                         media: { [item.media] },
                                                         onError: { title, error in app.dialogs.presentError(error, title: title) })
                        }
                        .onDrag { NSItemProvider(object: "mxr-queue:\(item.id)" as NSString) }
                        .onDrop(of: LibraryQueueDrop.types, isTargeted: nil) { providers in
                            LibraryQueueDrop.accept(providers, at: queue.items.firstIndex(where: { $0.id == item.id }) ?? queue.items.count, app: app)
                        }
                    }
                }.padding(.horizontal, Theme.Spacing.gap20)
            }.scrollIndicators(.hidden)
                .onDrop(of: LibraryQueueDrop.types, isTargeted: nil) { LibraryQueueDrop.accept($0, at: queue.items.count, app: app) }
        }
        .frame(height: queueHeight)
        .onAppear { app.library.loadPlaylistsIfNeeded() }
    }
}

@MainActor enum LibraryQueueDrop {
    static let types = ["public.file-url", "public.url", "public.utf8-plain-text"]

    static func accept(_ providers: [NSItemProvider], at index: Int, app: AppModel) -> Bool {
        let supported = providers.compactMap { provider -> (NSItemProvider, String)? in
            guard let type = types.first(where: provider.hasItemConformingToTypeIdentifier) else { return nil }
            return (provider, type)
        }
        Task {
            var offset = 0
            for (provider, type) in supported {
                let payload: String? = await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                        if let url = item as? URL { continuation.resume(returning: url.absoluteString) }
                        else if let text = item as? String { continuation.resume(returning: text) }
                        else if let data = item as? Data { continuation.resume(returning: String(data: data, encoding: .utf8)) }
                        else { continuation.resume(returning: nil) }
                    }
                }
                if let payload, apply(payload, at: index + offset, app: app), !payload.hasPrefix("mxr-queue:") { offset += 1 }
            }
        }
        return !supported.isEmpty
    }

    @discardableResult static func apply(_ payload: String, at index: Int, app: AppModel) -> Bool {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = min(max(index, 0), app.queue.items.count)
        if text.hasPrefix("mxr-queue:") {
            guard let id = UInt64(text.dropFirst("mxr-queue:".count)), app.queue.items.contains(where: { $0.id == id }) else { return false }
            app.queue.move([id], to: target)
            return true
        }
        // A multi-row library drag carries one URL per line.
        let media = text.split(whereSeparator: \.isNewline).compactMap { line -> MediaItem? in
            let value = line.trimmingCharacters(in: .whitespaces)
            let url = value.hasPrefix("/") ? URL(fileURLWithPath: value) : URL(string: value)
            guard let url, url.scheme != nil else { return nil }
            return MediaItem(url: url)
        }
        guard !media.isEmpty else { return false }
        app.queue.insert(media, at: target)
        return true
    }
}

struct MiniSeekBar: View {
    @Environment(PlayerModel.self) private var player
    @Environment(PlaybackClock.self) private var clock
    /// Figma hover/ended variants draw an orange playhead (Rectangle 10, 975:4511).
    var showsPlayhead = false
    @State private var scrub: ScrubSession?

    var body: some View {
        GeometryReader { geometry in
            let fill = max(0, geometry.size.width * fraction - Theme.Radius.xs * 2)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgB2)
                RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.bgAccentBright)
                    .frame(width: fill, height: LibraryGeometry.miniSeekHeight - Theme.Radius.xs * 2)
                    .padding(.leading, Theme.Radius.xs)
                if showsPlayhead || scrub?.isActive == true {
                    RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.accentMain)
                        .frame(width: LibraryGeometry.miniPlayheadWidth, height: LibraryGeometry.miniSeekHeight - Theme.Radius.xs * 2)
                        .offset(x: max(Theme.Radius.xs, Theme.Radius.xs + fill - LibraryGeometry.miniPlayheadWidth + Theme.Stroke.hairline))
                }
            }
            .contentShape(Rectangle())
            // High priority: scrubbing must never start a card drag (L15).
            .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard player.canSeek, geometry.size.width > 0 else { return }
                let position = min(max(value.location.x / geometry.size.width, 0), 1)
                session.update(to: clock.length * position)
            }.onEnded { value in
                guard player.canSeek, geometry.size.width > 0 else { scrub?.cancel(); return }
                session.end(at: clock.length * min(max(value.location.x / geometry.size.width, 0), 1))
            })
            .accessibilityElement().accessibilityLabel("Playback position")
            .accessibilityValue(clock.displayTime.formatted(.hoursMinutesSeconds))
            .accessibilityAdjustableAction { direction in
                guard player.canSeek else { return }
                player.jump(by: direction == .increment ? 10 : -10)
            }
        }
        .frame(height: LibraryGeometry.miniSeekHeight)
        .onDisappear { scrub?.cancel() }
        .onChange(of: player.media?.id) { _, _ in scrub?.cancel() }
        .onChange(of: player.canSeek) { _, canSeek in if !canSeek { scrub?.cancel() } }
    }

    private var session: ScrubSession {
        if let scrub { return scrub }
        let player = player
        let created = ScrubSession(clock: clock) { time, precision in player.seek(to: time, precision: precision) }
        scrub = created
        return created
    }
    private var fraction: Double { Self.fraction(clock: clock) }

    /// The exact binding read by the fill, isolated for observation-contract tests.
    static func fraction(clock: PlaybackClock) -> Double {
        guard clock.length > .zero else { return 0 }
        // Observe each precise pointer/settling target. Ordinary playback deliberately reads only
        // displayTime, so fractional engine ticks do not invalidate this mini-player fill.
        let time = clock.scrubTime ?? clock.displayTime
        return min(max(time.seconds / clock.length.seconds, 0), 1)
    }
}

/// A white, pill-less transport icon of the mini player's hover overlay (FG/1, 975:4507).
private struct MiniOverlayButton: View {
    let icon: MXRIcon.Name
    let label: String
    let size: CGFloat
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // FG/1 at full strength, as Figma's hover overlay draws every transport icon (975:4507).
            MXRIcon(icon, size: size, tint: enabled ? Theme.Color.fg1 : Theme.Color.fgA3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityLabel(label).help(label)
    }
}

private struct OptionalCardDrag: ViewModifier {
    let gesture: AnyGesture<DragGesture.Value>?
    func body(content: Content) -> some View {
        if let gesture { content.gesture(gesture) } else { content }
    }
}

/// Draggable mini player that snaps to the nearest corner of the full library.
public struct MXRMiniPlayerDock: View {
    @Environment(InterfaceModel.self) private var ui
    @Environment(PlayerModel.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let videoView: AnyView
    @State private var leading = false
    @State private var top = false
    @State private var translation: CGSize = .zero
    /// The media the user closed the card for; a new media (or playing again) brings it back.
    @State private var dismissedMediaID: String?

    public init(videoView: AnyView = AnyView(Color.clear)) { self.videoView = videoView }

    public var body: some View {
        GeometryReader { geometry in
            let width = Theme.Metric.Miniplayer.collapsed.width
            let margin = Theme.Spacing.gap6 // S45 970:3588 docks at 1523,735 within 1920×1080: 6pt inset.
            let availableHeight = max(0, geometry.size.height - margin * 2)
            let height = MXRMiniPlayerView.fittingHeight(expanded: ui.isMiniPlayerQueueExpanded, available: availableHeight)
            let x = leading ? margin + width / 2 : geometry.size.width - margin - width / 2
            let y = top ? margin + height / 2 : geometry.size.height - margin - height / 2
            let drag = DragGesture(minimumDistance: Theme.Spacing.gap8)
                .onChanged { translation = $0.translation }
                .onEnded { value in
                    let action = {
                        leading = x + value.translation.width < geometry.size.width / 2
                        top = y + value.translation.height < geometry.size.height / 2
                        translation = .zero
                    }
                    if reduceMotion { action() } else { withAnimation(.easeOut(duration: 0.2), action) }
                }
            if dismissedMediaID == nil || dismissedMediaID != player.media?.id {
                MXRMiniPlayerView(videoView: videoView, maximumHeight: availableHeight, cardDrag: AnyGesture(drag)) {
                    dismissedMediaID = player.media?.id
                    player.stop()
                }
                .position(x: x + translation.width, y: y + translation.height)
                .transition(.opacity)
            }
        }
        .onChange(of: player.isPlaying) { _, playing in if playing { dismissedMediaID = nil } }
    }
}
