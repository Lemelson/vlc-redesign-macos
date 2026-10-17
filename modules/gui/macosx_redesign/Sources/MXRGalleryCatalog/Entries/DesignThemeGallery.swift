import AppKit
import MXRDesign
import SwiftUI

/// Tells the Gallery and `mxr-snapshot` how to apply an accent: the nine `Theme.Accent`s, applied
/// with `.mxrAccent(_:)` so accent-dependent tokens and two-tone icons follow it.
final class DesignThemeGallery: NSObject, GalleryThemeProvider {
    @MainActor static func galleryTheme() -> Any {
        GalleryTheme(
            accents: Theme.Accent.allCases.map { GalleryAccent(id: $0.rawValue, color: $0.swatch.color) },
            defaultAccent: Theme.Accent.orange.rawValue
        ) { view, environment in
            let accent = environment.accent.flatMap(Theme.Accent.init(rawValue:)) ?? .orange
            return AnyView(view.mxrAccent(accent))
        }
    }
}
