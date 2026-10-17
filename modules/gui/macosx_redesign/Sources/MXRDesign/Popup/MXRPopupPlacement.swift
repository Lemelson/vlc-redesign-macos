import CoreGraphics
import Foundation

/// Where a popup card goes relative to its anchor. All rectangles are AppKit screen
/// coordinates (origin bottom-left, y up).
public enum MXRPopupPlacement: Hashable, Sendable {
    public enum Alignment: Hashable, Sendable { case leading, center, trailing }

    /// Drops under the anchor (the `⋯` menu, library sort/view menus); flips above when the
    /// screen has no room below.
    case below(Alignment = .leading, gap: CGFloat = Theme.Popup.anchorGap)
    /// Opens over the anchor; flips below when there is no room above.
    case above(Alignment = .leading, gap: CGFloat = Theme.Popup.anchorGap)
    /// Below an anchor in the upper half of its window (a top-bar button), above one in the lower
    /// half (the same control placed in the control bar by Customize Player).
    case awayFromWindowEdge(Alignment = .leading, gap: CGFloat = Theme.Popup.anchorGap)
    /// Dropdown lists (Figma `Dropdown` / `Setting Preset` "open"): the list covers the field so the
    /// row at `rowOffset` (distance from the card top to the selected row) sits on the field's row,
    /// like a macOS pop-up button.
    case overField(rowOffset: CGFloat)
    /// A submenu beside its parent row: its first row (`topInset` under the card top) lines up
    /// with the parent row, to the right of the parent card (to the left when the screen has no room).
    case beside(row: CGRect, parentCard: CGRect, topInset: CGFloat)
    /// A context menu with its top-left corner at the pointer; opens to the left or shifts up
    /// near the screen edges.
    case pointer(CGPoint)
}

/// Direction the card slides in from (D024: "from its anchor").
public enum MXRPopupSlide: Hashable, Sendable {
    case down, up, right, left

    /// The starting offset (SwiftUI coordinates, y down) for a slide of `distance`.
    public func startOffset(_ distance: CGFloat) -> CGSize {
        switch self {
        case .down: CGSize(width: 0, height: -distance)
        case .up: CGSize(width: 0, height: distance)
        case .right: CGSize(width: -distance, height: 0)
        case .left: CGSize(width: distance, height: 0)
        }
    }
}

extension MXRPopupPlacement {
    /// Resolves ``awayFromWindowEdge(_:gap:)`` for an anchor inside `window` (screen coordinates).
    public func resolved(anchor: CGRect, window: CGRect) -> MXRPopupPlacement {
        guard case .awayFromWindowEdge(let alignment, let gap) = self else { return self }
        return anchor.midY >= window.midY ? .below(alignment, gap: gap) : .above(alignment, gap: gap)
    }

    /// Result of fitting a card on a screen.
    public struct Fit: Hashable, Sendable {
        /// The card frame (screen coordinates).
        public var frame: CGRect
        public var slide: MXRPopupSlide
        /// True when the card was shortened to fit and must scroll.
        public var isClipped: Bool
    }

    /// Fits a card of `size` next to `anchor` inside `visible` (the screen's visible frame),
    /// keeping ``Theme/Popup/screenMargin`` from its edges.
    public func fit(size: CGSize, anchor: CGRect, visible: CGRect,
                    margin: CGFloat = Theme.Popup.screenMargin) -> Fit {
        let bounds = visible.insetBy(dx: margin, dy: margin)
        let height = min(size.height, bounds.height)
        let clipped = height < size.height
        var origin = CGPoint.zero
        var slide = MXRPopupSlide.down

        func alignedX(_ alignment: Alignment) -> CGFloat {
            switch alignment {
            case .leading: anchor.minX
            case .center: anchor.midX - size.width / 2
            case .trailing: anchor.maxX - size.width
            }
        }

        switch self {
        case .awayFromWindowEdge(let alignment, let gap):
            // Resolved against the window by the presenter; on its own it drops below.
            return MXRPopupPlacement.below(alignment, gap: gap).fit(size: size, anchor: anchor, visible: visible, margin: margin)
        case .below(let alignment, let gap), .above(let alignment, let gap):
            let belowY = anchor.minY - gap - height
            let aboveY = anchor.maxY + gap
            let roomBelow = belowY >= bounds.minY
            let roomAbove = aboveY + height <= bounds.maxY
            let prefersBelow: Bool = if case .below = self { true } else { false }
            let moreRoomBelow = anchor.minY - bounds.minY >= bounds.maxY - anchor.maxY
            let goesBelow = if prefersBelow { roomBelow || (!roomAbove && moreRoomBelow) }
                            else { !roomAbove && (roomBelow || moreRoomBelow) }
            origin.y = goesBelow ? belowY : aboveY
            slide = goesBelow ? .down : .up
            origin.x = alignedX(alignment)
        case .overField(let rowOffset):
            origin.y = anchor.maxY + rowOffset - height
            origin.x = anchor.minX
            slide = .down
        case .beside(let row, let parentCard, let topInset):
            let gap = Theme.Popup.submenuGap
            let right = parentCard.maxX + gap
            if right + size.width <= bounds.maxX || parentCard.minX - gap - size.width < bounds.minX {
                origin.x = right
                slide = .right
            } else {
                origin.x = parentCard.minX - gap - size.width
                slide = .left
            }
            origin.y = row.maxY + topInset - height
        case .pointer(let point):
            origin.x = point.x + size.width <= bounds.maxX ? point.x : point.x - size.width
            origin.y = point.y - height
            slide = .down
        }

        origin.x = min(max(origin.x, bounds.minX), max(bounds.minX, bounds.maxX - size.width))
        origin.y = min(max(origin.y, bounds.minY), max(bounds.minY, bounds.maxY - height))
        return Fit(frame: CGRect(origin: origin, size: CGSize(width: size.width, height: height)),
                   slide: slide, isClipped: clipped)
    }
}
