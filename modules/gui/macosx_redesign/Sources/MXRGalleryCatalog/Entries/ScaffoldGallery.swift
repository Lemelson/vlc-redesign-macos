import AppKit
import MXRDesign
import SwiftUI

/// Tooling demonstration: a token-built stand-in for the Figma `play` component set (848:1712),
/// used to prove the render → Figma crop → compare loop (`mxr-snapshot check --id X.PlayDemo/play`).
/// Delete once `C.PlayButton` exists; it is not the product component.
final class ScaffoldGallery: NSObject, GalleryProvider {
    @MainActor static func galleryEntries() -> [Any] {
        let play = Theme.Metric.ControlBar.playButton
        return [
            GalleryEntry(
                id: "X.PlayDemo/play", title: "Play button (tooling demo)", size: play.size, figmaNode: play.node,
                screens: ["S01"],
                notes: "Tooling demo built from tokens (Theme.Metric.ControlBar.playButton). Not the product component."
            ) {
                PlayDemoButton(box: play, icon: .play, fill: Theme.Color.accentMain)
            },
        ]
    }
}

/// The play cell as Figma lays it out: a padded auto-layout box with a 24 pt glyph.
private struct PlayDemoButton: View {
    let box: Theme.Box
    let icon: MXRIcon.Name
    let fill: ThemeColor

    var body: some View {
        MXRIcon(icon, tint: Theme.Color.fgB1)
            .padding(box.padding.edgeInsets)
            .frame(width: box.width, height: box.height)
            .background(fill, in: .rect(cornerRadius: box.radius ?? Theme.Radius.lg))
    }
}
