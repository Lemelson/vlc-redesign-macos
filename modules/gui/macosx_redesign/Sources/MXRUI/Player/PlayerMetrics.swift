import CoreGraphics
import Foundation
import MXRDesign

/// Additional Figma geometry used only by the player. All measurements are from the local
/// `figma_file.json`; keeping them here makes their source explicit until token generation covers them.
public enum MXRPlayerMetrics {
    /// 4777:24028, the square artwork in Player - Music.
    public static let artwork = Theme.Box(node: "4777:24028", width: 738, height: 737, radius: 20)
    /// 4777:24034, enlarged artwork behind the player.
    public static let backdropSize: CGFloat = 1952
    /// 4778:24351 starts 73.333 pt below 4777:24028.
    public static let artworkTitleGap: CGFloat = 73.333333
    /// D042: Figma has no PiP placeholder frame; its glyph is the 24 pt PiP icon drawn at twice the
    /// icon artwork size so it reads as a placeholder, not a control.
    static let pictureInPictureIcon: CGFloat = Theme.Metric.iconSize * 2
    /// 244:239: gradient vector bounds relative to 244:235.
    static let coneInset: CGFloat = 1.5
    static let coneTrackSize = CGSize(width: 89, height: 28)
    static let coneFillSize = CGSize(width: 86, height: 25)
    /// 244:239 gradient handles map to x=-1 and x=89 in the 88 pt component.
    static let coneGradientStartX = -2.5 / Double(coneFillSize.width)
    static let coneGradientEndX = 87.5 / Double(coneFillSize.width)
    /// 4778:26192, the music thumb; video uses the generated 8 pt playhead.
    static let musicPlayhead = Theme.Box(node: "4778:26192", width: 4, height: 24, radius: 4)
    /// 4778:26191: the 4 pt thumb plus a 3 pt gap occupy the slot between waveform samples.
    static let waveformHeadSlotWidth: CGFloat = 7
    /// 4778:26193...: fixed waveform pitch in the Controls music variant.
    static let waveformPitch: CGFloat = 5
    static let waveformWidth: CGFloat = 2
    static let waveformBins = 244
    static let waveformInset: CGFloat = 6
    /// 6586:17371 begins at y=31; its child inset places video at y=41, below the 40 pt title bar.
    static let videoInset = Theme.Insets(top: Theme.Stroke.hairline, leading: Theme.Metric.Window.videoArea.padding.leading,
                                        bottom: 0, trailing: Theme.Metric.Window.videoArea.padding.trailing)
    /// 6586:17371's 20 pt centered stroke reduces its 19 pt outer radius by the 10 pt inset.
    static let videoClipRadius = max(0, (Theme.Metric.Window.videoArea.radius ?? Theme.Radius.videoFrame) -
                                       Theme.Metric.Window.videoArea.padding.leading)
    /// 247:454/456 and 247:461 are 28 pt cells, with 24 pt artwork.
    static let headerIcon = Theme.Box(node: "247:454", width: 28, height: 28)
    /// 2160:8419 "Frame 229": a title placed in a control-bar row (customize-7) is a hugging cell with
    /// 6 pt side padding, so it keeps its distance from the folder chip and the favourite heart.
    static let rowTitleCell = Theme.Box(node: "2160:8419", width: 129, height: 25, gap: 10,
                                        padding: Theme.Insets(top: 0, leading: 6, bottom: 0, trailing: 6))
    /// A-07: the narrowest readable centred title, about ten characters of `Theme.Font.body`
    /// (the 300 pt left group 247:448 holds the cone, menu, sidebar toggle and an 82 pt folder chip).
    static let headerTitleMinWidth = Theme.Font.body.size * 6
    /// A-07: below about four characters a truncated folder label is dropped and the chip keeps its icon.
    static let headerFolderLabelMinWidth = Theme.Font.body.size * 3
    /// PHILOSOPHY §3.2: immediate hover reveal; spec §03 permits a short fade (D023).
    static let revealDuration = 0.13
    /// D019: below the canonical 1920 pt width the compact library (S27) gives up width so the video,
    /// and an open right panel, stay usable. Shares of the window width; Figma's 427 pt is the cap.
    static let compactLibraryShare: CGFloat = 0.45
    static let compactLibraryShareWithPanel: CGFloat = 0.32
    /// Player - customize* (2107:5604 …, key frames 19m12.4/19m26.3): edit mode always shows two
    /// control-bar rows (972–1080); a one-row layout gets an empty band above the bar, the slot a
    /// dragged item fills to start a new row.
    static let customizeControlRows = 2
    /// VLC's `mouse-hide-timeout` default: the pointer hides over video after one second (WT-11).
    static let cursorHideDelay = 1.0
}

/// Player copy that is not in Figma (D042).
enum MXRPlayerCopy {
    /// A-06: the placeholder left in the window while the video plays in the PiP window.
    static let pictureInPicturePlaceholder = "This video is playing in Picture in Picture"
    static let pictureInPictureReturn = "Returns the video to this window"
    /// 1922:9585, the resume toast's action.
    static let continueWatching = "Continue Watching"
    /// VLC 4's own resume button title (modules/gui/qt/player/qml/ResumeDialog.qml, "Continue"),
    /// for a toast too narrow for Figma's label (D051).
    static let continueShort = "Continue"
}

/// D024 popup motion for MXRUI panels; the values are the design-system popup constants
/// (``Theme/Popup``) so panels and menus move the same way.
public enum MXRPopupMotion {
    public static let insertion = Theme.Popup.appearDuration
    public static let removal = Theme.Popup.disappearDuration
    /// Slide distance from the anchor.
    public static let offset = Theme.Popup.slideDistance
}
