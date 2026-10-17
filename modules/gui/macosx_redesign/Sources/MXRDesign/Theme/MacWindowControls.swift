import CoreGraphics

extension Theme {
    /// The macOS window controls (D022) for pictures of the player window that cannot hold AppKit's
    /// own buttons, such as the onboarding player preview (S70; Figma 1902:3670 draws Windows controls
    /// there). The real window always uses AppKit's buttons (`MXRWindowControls`). The geometry is where
    /// AppKit puts them in the player's compact unified toolbar (measured from the shipping-window
    /// render: 12 pt buttons 8 pt apart, the first 13 pt from the edge, centred in the 40 pt bar); the
    /// colours are those of an active window's close, minimise and zoom buttons.
    public enum MacWindowControls {
        public static let diameter: CGFloat = 12
        public static let spacing: CGFloat = 8
        public static let leadingInset: CGFloat = 13
        /// Right edge of the zoom button, from the window's leading edge.
        public static var trailingEdge: CGFloat { leadingInset + 3 * diameter + 2 * spacing }
        public static let close = RGBA(hex: 0xFF5F57)
        public static let minimize = RGBA(hex: 0xFEBC2E)
        public static let zoom = RGBA(hex: 0x28C840)
        /// The buttons' hairline edge over each colour.
        public static let edge = RGBA(hex: 0x000000, alpha: 0.12)
    }
}
