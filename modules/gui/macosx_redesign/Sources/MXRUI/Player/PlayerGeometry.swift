import CoreGraphics
import MXRCore
import MXRDesign

/// Where the media canvas sits in the window (D021, VIDEO_BREAKDOWN §03). It depends only on the
/// window mode, never on bar visibility or open panels, so the video never jumps.
enum PlayerCanvasStyle: Equatable {
    /// Player-6 (247:445): dark window with pinned bars; the video sits between the bars inside the
    /// 10 pt Frame 312 (6586:17371).
    case framed
    /// Player - hide UI (3328:11554) and the auto-hidden window (03m53.6): the whole window inside a
    /// uniform 10 pt frame; bars overlay the video when revealed.
    case thinFrame
    /// Fullscreen and Customize (2107:5604): the canvas fills the window and the bars overlay it.
    case fullBleed
    /// Player - Light (2425:13624): the canvas runs under the translucent bars, edge to edge, while
    /// the picture stays between the pinned bars, so a theme never moves or rescales the video and
    /// the bottom of the picture (subtitles) is never under the control bar (D055).
    case underBars

    static func resolve(fullscreen: Bool, uiHidden: Bool, customizing: Bool, light: Bool,
                        autoHidesInWindow: Bool) -> PlayerCanvasStyle {
        if fullscreen { return .fullBleed }
        if customizing { return .fullBleed }
        if uiHidden || autoHidesInWindow { return .thinFrame }
        return light ? .underBars : .framed
    }

    func insets(controlHeight: CGFloat) -> Theme.Insets {
        let frame = Theme.Metric.Window.videoArea.padding
        switch self {
        case .framed:
            // 6586:17371 starts at y=31; its 20 pt centred stroke puts the video at y=41, 1 pt below the bar.
            return Theme.Insets(top: Theme.Metric.Window.topBar.height + Theme.Stroke.hairline, leading: frame.leading,
                                bottom: controlHeight, trailing: frame.trailing)
        case .thinFrame: return frame
        case .fullBleed, .underBars: return .zero
        }
    }

    /// Where the picture sits inside the canvas (the canvas rect is ``insets(controlHeight:)``).
    func pictureInsets(controlHeight: CGFloat) -> Theme.Insets {
        guard self == .underBars else { return .zero }
        return Theme.Insets(top: Theme.Metric.Window.topBar.height, leading: 0, bottom: controlHeight, trailing: 0)
    }

    /// The picture's insets from the window edges.
    func windowPictureInsets(controlHeight: CGFloat) -> Theme.Insets {
        let canvas = insets(controlHeight: controlHeight), picture = pictureInsets(controlHeight: controlHeight)
        return Theme.Insets(top: canvas.top + picture.top, leading: canvas.leading + picture.leading,
                            bottom: canvas.bottom + picture.bottom, trailing: canvas.trailing + picture.trailing)
    }

    var cornerRadius: CGFloat { self == .fullBleed || self == .underBars ? 0 : MXRPlayerMetrics.videoClipRadius }
}

enum PlayerGeometry {
    /// Floating right panels share one slot between the bars (D021, sidePanels.placement): 20 pt
    /// from the right edge, below the top bar and above the control bar. The track popover keeps
    /// its 524 pt height anchored to the bottom; the sidebar and queue fill the slot.
    static func rightPanelFrame(_ panel: RightPanel, in size: CGSize, controlHeight: CGFloat,
                                leadingInset: CGFloat, topBarOffset: Double = 0) -> CGRect {
        let panels = Theme.Metric.SidePanels.self
        let top = Theme.Metric.Window.topBar.height + CGFloat(topBarOffset) + panels.placementGapBelowTopBar
        let bottom = size.height - controlHeight - panels.placementGapAboveControlBar
        let trailing = size.width - panels.placementRightInset
        let width = min(Theme.Metric.sidePanelWidth, max(0, trailing - leadingInset - panels.placementRightInset))
        let available = max(0, bottom - top)
        let height: CGFloat = switch panel {
        case .tracks: min(panels.tracksPopup.height, available)
        case .sidebar, .queue: available
        }
        return CGRect(x: trailing - width, y: bottom - height, width: width, height: height)
    }

    /// The compact library's width in a window `width` wide, 0 when it yields (D019, D057). At 1920 pt it
    /// keeps Figma's 427 pt; narrower windows give it a share of the width, never below the narrowest
    /// panel whose header fits (``LibraryGeometry/compactMinimumWidth``). With a right panel open it
    /// stays only while both fit at their own widths (the library at its minimum, the panel at
    /// Figma's 400 pt with its insets); otherwise it yields to the panel the user just opened, as a
    /// macOS sidebar collapses before an inspector, and returns when the panel closes.
    static func compactLibraryWidth(windowWidth width: CGFloat, panelOpen: Bool) -> CGFloat {
        let minimum = LibraryGeometry.compactMinimumWidth
        if panelOpen {
            let panel = Theme.Metric.sidePanelWidth + 2 * Theme.Metric.SidePanels.placementRightInset
            guard width >= minimum + panel else { return 0 }
        }
        let share = panelOpen ? MXRPlayerMetrics.compactLibraryShareWithPanel : MXRPlayerMetrics.compactLibraryShare
        return min(width, min(Theme.Metric.Library.sidebar.width, max(minimum, width * share)))
    }

    /// Where player information (OSD, metadata, resume toast) may draw (D027, A-02, A-08): the visible
    /// video between the shown bars, right of the compact library and left of an open right panel,
    /// inset by ``Theme/Metric/panelInset``. `top`/`bottom` are the heights of the visible bars.
    static func informationRect(in size: CGSize, top: CGFloat, bottom: CGFloat, leading: CGFloat,
                                rightPanel: CGRect?) -> CGRect {
        let inset = Theme.Metric.panelInset
        let minX = leading + inset
        let maxX = max(minX, (rightPanel?.minX ?? size.width) - inset)
        let minY = top + inset
        let maxY = max(minY, size.height - bottom - inset)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Control-bar rows drawn in the window: the layout's rows, and in Customize at least
    /// ``MXRPlayerMetrics/customizeControlRows`` (the empty new-row band of 2107:5604).
    static func controlRows(layoutRows: Int, customizing: Bool) -> Int {
        customizing ? max(layoutRows, MXRPlayerMetrics.customizeControlRows) : layoutRows
    }

    static func customizationOffset(windowHeight: CGFloat, paletteHeight: CGFloat, controlHeight: CGFloat) -> CGFloat {
        let canonicalOffset = Theme.Metric.Customization.panelY + Theme.Metric.Customization.panel.height / 2
            - Theme.Metric.Window.player.height / 2
        let desiredCenter = windowHeight / 2 + canonicalOffset
        let minimumCenter = Theme.Metric.Window.topBar.height + Theme.Metric.panelInset + paletteHeight / 2
        let maximumCenter = windowHeight - controlHeight - Theme.Metric.panelInset - paletteHeight / 2
        return min(max(desiredCenter, minimumCenter), max(minimumCenter, maximumCenter)) - windowHeight / 2
    }

    /// Full-library screens share minimal chrome. Preserve customized control sequences.
    static func topItems(_ items: [LayoutItem], fullLibrary: Bool) -> [LayoutItem] {
        guard fullLibrary, items.map(\.control) == PlayerLayout.video.top.map(\.control) else { return items }
        return items.filter { ![.sidebarToggle, .divider, .folderName].contains($0.control) }
    }

    static func seekHeadX(progress: Double, width: CGFloat, headWidth: CGFloat) -> CGFloat {
        Theme.Spacing.gap2 + max(0, width - headWidth) * min(max(progress, 0), 1)
    }

    static func animatesSeek(running: Bool, barsVisible: Bool, hidden: Bool, pip: Bool, reduceMotion: Bool) -> Bool {
        running && barsVisible && !hidden && !pip && !reduceMotion
    }

    /// Widths for the top-bar row (A-07, WIN-02). `widths` are the items' ideal widths and `gaps[i]` is
    /// the space before item `i`. The centred title needs ``MXRPlayerMetrics/headerTitleMinWidth``
    /// (or its whole text if shorter): the folder chips give up width first, down to their icon. When
    /// even that leaves no room, the title is left out (width 0) instead of collapsing to "…", and the
    /// folders may use whatever the fixed items leave.
    static func headerWidths(_ widths: [CGFloat], gaps: [CGFloat], title: Int?, folders: [Int], flexible: [Int],
                             width: CGFloat) -> (items: [CGFloat], title: CGFloat?) {
        var items = widths
        for index in flexible { items[index] = 0 }
        let chip = Theme.Metric.Window.folderChip
        let folderMinimum = MXRPlayerMetrics.headerIcon.width + chip.gap + chip.padding.trailing
        func side(_ range: [Int]) -> CGFloat { range.reduce(CGFloat.zero) { $0 + items[$1] + gaps[$1] } }
        guard let title else {
            var available = max(0, width - side(items.indices.filter { !folders.contains($0) }) - folders.reduce(0) { $0 + gaps[$1] })
            for index in folders {
                items[index] = min(widths[index], available)
                available -= items[index]
            }
            return (items, nil)
        }
        let leading = Array(items.indices.prefix(title)), trailing = Array(items.indices.suffix(from: title + 1))
        let needed = min(widths[title], MXRPlayerMetrics.headerTitleMinWidth)
        // Each side may use at most half of what the title leaves; folders shrink to fit their side.
        let sideLimit = max(0, (width - needed) / 2)
        for range in [leading, trailing] {
            var excess = side(range) - sideLimit
            for index in range.reversed() where folders.contains(index) && excess > 0 && items[index] > folderMinimum {
                var shrunk = max(folderMinimum, items[index] - excess)
                // A label shorter than a few characters reads as "F…": keep the icon alone instead.
                if shrunk < folderMinimum + MXRPlayerMetrics.headerFolderLabelMinWidth { shrunk = folderMinimum }
                excess -= items[index] - shrunk
                items[index] = shrunk
            }
        }
        let centred = max(0, width - 2 * max(side(leading), side(trailing)))
        if centred >= needed && needed > 0 { return (items, min(widths[title], centred)) }
        // No room for a readable title: hide it and let the folders use the space the fixed items leave.
        var withoutTitle = widths
        withoutTitle[title] = 0
        var result = headerWidths(withoutTitle, gaps: gaps.enumerated().map { $0.offset == title ? 0 : $0.element },
                                  title: nil, folders: folders, flexible: flexible, width: width)
        result.title = 0
        return result
    }

    /// Widths for one bar row: fixed items keep `widths[i]`, flexible items (spacers, seek bar) share
    /// what is left, and `skipped` items (the centred top title) take no room in the row. `gaps[i]` is
    /// the space before item `i`. When the row holds exactly two spacers, the run between them is
    /// centred on the row as far as the free width allows (customize-7 2160:8306 and 19m27.6: the
    /// transport sits at the window's centre, with spacers of 564 and 500 pt), the way a centred
    /// toolbar item behaves; otherwise flexible items share the free width equally (D057).
    static func rowWidths(_ widths: [CGFloat], gaps: [CGFloat], spacers: [Int], flexible: [Int], skipped: [Int] = [],
                          width: CGFloat) -> [CGFloat] {
        var items = widths
        for index in skipped { items[index] = 0 }
        let inRow = widths.indices.filter { !skipped.contains($0) }
        let fixed = inRow.reduce(CGFloat.zero) { $0 + (flexible.contains($1) ? 0 : items[$1]) + gaps[$1] }
        let free = max(0, width - fixed)
        for index in flexible { items[index] = flexible.isEmpty ? 0 : free / CGFloat(flexible.count) }
        guard spacers.count == 2, flexible.count == 2, let first = spacers.first, let last = spacers.last,
              last > first + 1 else { return items }
        // x where the first spacer starts, and the middle run's width (its own gaps, not the outer ones).
        let start = inRow.filter { $0 < first }.reduce(CGFloat.zero) { $0 + items[$1] + gaps[$1] } + gaps[first]
        let middle = Array((first + 1)..<last).filter { !skipped.contains($0) }
        let run = middle.reduce(CGFloat.zero) { $0 + items[$1] + gaps[$1] } - (middle.first.map { gaps[$0] } ?? 0)
        let leading = width / 2 - run / 2 - (middle.first.map { gaps[$0] } ?? 0) - start
        items[first] = min(max(0, leading), free)
        items[last] = free - items[first]
        return items
    }

    static func seekPosition(x: CGFloat, width: CGFloat) -> Double {
        let inset = Theme.Spacing.gap2
        guard width > inset * 2 else { return 0 }
        return Double(min(max((x - inset) / (width - inset * 2), 0), 1))
    }

    /// The Figma cone deliberately gives ordinary volumes more pointer travel than boosted volume.
    static func volumeFillWidth(percent: Double, maximumPercent: Double = 200) -> CGFloat {
        let points = Theme.Metric.Volume.fillWidthByStep
        let capacity = maximumPercent.isFinite ? min(max(maximumPercent, 100), 300) : 200
        let percent = min(max(percent * Double(Theme.Metric.Volume.maxPercent) / capacity, 0), Double(Theme.Metric.Volume.maxPercent))
        for (left, right) in zip(points, points.dropFirst()) where percent <= Double(right.percent) {
            let fraction = (percent - Double(left.percent)) / Double(right.percent - left.percent)
            return left.value + CGFloat(fraction) * (right.value - left.value)
        }
        return points.last!.value
    }

    static func volumePercent(at x: CGFloat, maximumPercent: Double = 200) -> Double {
        let points = Theme.Metric.Volume.fillWidthByStep
        let capacity = maximumPercent.isFinite ? min(max(maximumPercent, 100), 300) : 200
        let scale = capacity / Double(Theme.Metric.Volume.maxPercent)
        guard x > points[0].value else { return 0 }
        for (left, right) in zip(points, points.dropFirst()) where x <= right.value {
            let fraction = (x - left.value) / (right.value - left.value)
            return (Double(left.percent) + Double(fraction) * Double(right.percent - left.percent)) * scale
        }
        return capacity
    }

    /// Compact controls preserve the user's configured primary controls; the rest remain in overflow.
    static func compactItems(_ items: [LayoutItem]) -> [LayoutItem] {
        items.filter { [.playPause, .seekBar, .volume, .queue].contains($0.control) }
    }

    static func typedTime(_ text: String, length: MediaTime, remaining: Bool) -> MediaTime? {
        guard let parsed = MediaTime(parsing: text) else { return nil }
        let time = remaining ? length - parsed.magnitude : parsed
        return length > .zero ? time.clamped(to: .zero...length) : max(.zero, time)
    }
}
