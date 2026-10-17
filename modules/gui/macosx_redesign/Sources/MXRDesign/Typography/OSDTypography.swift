import SwiftUI

extension Theme {
    /// D027 / PLAYER-V02: action at 5% of the video height with 24/20 pt minimums.
    /// The video gives relative sizing only; minimum faces reuse existing Figma Inter styles.
    public enum OSD {
        public static let titleHeightFraction: CGFloat = 0.05

        public static func styles(videoHeight: CGFloat) -> (title: TextStyle, key: TextStyle) {
            let title = max(Font.osdTitle.size, max(0, videoHeight) * titleHeightFraction)
            let factor = title / Font.osdTitle.size
            return (Font.osdTitle.size(title), Font.osdKey.size(Font.osdKey.size * factor))
        }

        /// The OSD's inset from the picture edge grows with its text, half the action line's size
        /// (key frame 15m27.1s keeps a clear margin; B-08). At the 24 pt minimum this is `gap12`.
        public static let marginToTitle: CGFloat = 0.5

        public static func margin(videoHeight: CGFloat) -> CGFloat {
            styles(videoHeight: videoHeight).title.size * marginToTitle
        }

        /// The picture the vout draws: `videoSize` aspect-fit and centred in `canvas` (the media
        /// canvas, which never moves when panels open, D021); the whole canvas when the size is unknown.
        public static func pictureRect(canvas: CGRect, videoSize: CGSize?) -> CGRect {
            guard let videoSize, videoSize.width > 0, videoSize.height > 0,
                  canvas.width > 0, canvas.height > 0 else { return canvas }
            let scale = min(canvas.width / videoSize.width, canvas.height / videoSize.height)
            let size = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
            return CGRect(x: canvas.midX - size.width / 2, y: canvas.midY - size.height / 2,
                          width: size.width, height: size.height)
        }

        /// The height of the picture the vout draws: `videoSize` aspect-fit in `container`; the whole
        /// container when the size is unknown. The OSD scales with the picture, not the letterbox.
        public static func pictureHeight(container: CGSize, videoSize: CGSize?) -> CGFloat {
            max(0, pictureRect(canvas: CGRect(origin: .zero, size: container), videoSize: videoSize).height)
        }

        /// Where the OSD may draw: the visible part of the picture (`picture` ∩ `bounds`, the player
        /// information rect clear of the bars, the compact library and the right panels). The OSD
        /// keeps ``margin(videoHeight:)`` inside this rect's top-trailing corner, so a pillarboxed
        /// picture keeps it on the picture, as VLC's own OSD is (B-08).
        public static func anchorRect(picture: CGRect, bounds: CGRect) -> CGRect {
            let visible = picture.intersection(bounds)
            return visible.isNull || visible.isEmpty ? bounds : visible
        }

        /// VLC's text renderer defaults (modules/text_renderer/freetype: `freetype-outline-thickness`
        /// 4 → a black outline of 4 % of the glyph height; `freetype-shadow-opacity` 128,
        /// `-distance` 0.06 of the glyph size, `-angle` −45°, i.e. down and right). Key frame 15m27.1s
        /// is VLC's OSD with this crisp dark edge, which keeps the text readable on white frames.
        public static let outlineFraction: CGFloat = 0.04
        public static let outlineColor = RGBA(red: 0, green: 0, blue: 0)
        public static let shadowDistanceFraction: CGFloat = 0.06
        public static let shadowColor = RGBA(red: 0, green: 0, blue: 0, alpha: 128.0 / 255.0)

        /// The outline width for text of `size` points.
        public static func outlineWidth(size: CGFloat) -> CGFloat { size * outlineFraction }

        /// The drop-shadow offset for text of `size` points (VLC's −45° vector, y down on screen).
        public static func shadowOffset(size: CGFloat) -> CGSize {
            let component = size * shadowDistanceFraction * cos(CGFloat.pi / 4)
            return CGSize(width: component, height: component)
        }
    }
}
