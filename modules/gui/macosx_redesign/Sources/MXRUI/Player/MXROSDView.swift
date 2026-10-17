import MXRCore
import MXRDesign
import SwiftUI

/// S13: the interface's only on-screen display (D027). Two left-aligned lines, the action
/// ("Crop: 2.35:1") and the key that caused it ("Pressed C"), the second slightly smaller, as
/// in VLC's classic OSD look (key frame 15m27.1s). VLC's own OSD is switched off by the bridge.
///
/// It is drawn over the video, so it always uses the dark palette's foreground, with VLC's black
/// outline and drop shadow (``Theme/OSD``), whatever the app theme.
public struct MXRPlayerOSD: View {
    @Environment(AppModel.self) private var app
    private let canvas: CGRect
    private let bounds: CGRect

    /// - Parameters:
    ///   - canvas: the media canvas in the window (where the vout draws). The text scales with the
    ///     picture drawn in it (aspect fit of the video size), not with the letterbox (B-08).
    ///   - bounds: the player information rect (clear of the bars, the library and the panels).
    ///     The view fills the window; the text sits at the top-trailing corner of the visible picture.
    public init(canvas: CGRect, bounds: CGRect) {
        self.canvas = canvas; self.bounds = bounds
    }

    public var body: some View {
        if let message = app.osd.message {
            let videoSize = app.tracks.selectedTrack(of: .video)?.videoSize ?? app.player.media?.videoSize
            let picture = Theme.OSD.pictureRect(canvas: canvas, videoSize: videoSize)
            let anchor = Theme.OSD.anchorRect(picture: picture, bounds: bounds)
            let styles = Theme.OSD.styles(videoHeight: picture.height)
            VStack(alignment: .leading, spacing: Theme.Spacing.gap4) {
                if let text = message.text { MXROSDLine(text: text, style: styles.title) }
                if let key = message.pressedKeyText { MXROSDLine(text: key, style: styles.key) }
            }
            .padding([.top, .trailing], Theme.OSD.margin(videoHeight: picture.height))
            .frame(width: anchor.width, height: anchor.height, alignment: .topTrailing)
            .offset(x: anchor.minX, y: anchor.minY)
            .environment(\.colorScheme, .dark)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

/// One OSD line drawn like VLC's text renderer: FG/1 glyphs over a black outline (eight offset
/// copies approximate the round stroke), with a half-opaque drop shadow down and to the right.
struct MXROSDLine: View {
    let text: String
    let style: Theme.TextStyle

    private static let directions: [CGSize] = (0..<8).map { index in
        let angle = CGFloat(index) * .pi / 4
        return CGSize(width: cos(angle), height: sin(angle))
    }

    var body: some View {
        let width = Theme.OSD.outlineWidth(size: style.size)
        let shadow = Theme.OSD.shadowOffset(size: style.size)
        ZStack {
            ForEach(Self.directions.indices, id: \.self) { index in
                Text(text).font(style.font)
                    .foregroundStyle(Theme.OSD.outlineColor.color)
                    .offset(x: Self.directions[index].width * width, y: Self.directions[index].height * width)
            }
            Text(text).font(style.font).foregroundStyle(Theme.Color.fg1)
        }
        // One shadow of the outlined text, as VLC casts it from the outlined glyph. Without the group
        // SwiftUI shadows each of the nine layers, and the overlapping 50 % shadows read as a solid
        // black halo below and right of every glyph.
        .compositingGroup()
        .shadow(color: Theme.OSD.shadowColor.color, radius: 0, x: shadow.width, y: shadow.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
