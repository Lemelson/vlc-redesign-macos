import CoreGraphics

// Sizes of the Convert and Stream forms (SD-19). Figma has no frame for them, so they are built
// from the design's own measures rather than read from a node.
extension Theme.Metric {
    /// The Stream dialog's HTTP path field: one and a half dialog buttons, so "/live" and similar
    /// short paths show in full beside the address and port.
    public static let streamPathFieldWidth: CGFloat = buttonWidth * 1.5
    /// The Convert progress line: as thick as the watch progress of a large library card.
    public static let outputProgressHeight: CGFloat = 4
}
