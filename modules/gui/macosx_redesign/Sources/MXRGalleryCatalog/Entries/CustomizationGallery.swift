import AppKit
import MXRCore
import MXRDesign
import MXRMockBackend
import MXRUI
import SwiftUI

/// Isolated S66–S71 surfaces at their exact Figma boxes. S72 verifies shared theme tokens.
final class CustomizationGallery: NSObject, GalleryProvider {
    @MainActor static func galleryEntries() -> [Any] {
        var entries: [GalleryEntry] = [
            GalleryEntry(id: "S66.Customization/default", title: "Customize Player — default",
                         size: MXRCustomizationView.preferredSize, figmaNode: "6587:18867", screens: ["S66"],
                         notes: "The isolated palette uses a neutral backdrop; the source canvas has blurred playing media behind its translucent panel.",
                         background: Theme.Color.bgA3.color(scheme: .dark, accent: .orange),
                         renderEngine: .hostingView) {
                let app = AppModel.mock(.pausedEpisode)
                app.beginCustomizing()
                return MXRCustomizationView().appModel(app)
            },
            GalleryEntry(id: "S67.Customization/two-row-edit", title: "Customize Player — two-row draft",
                         size: MXRCustomizationView.preferredSize, figmaNode: "6587:19979", screens: ["S66", "S67"],
                         notes: "The isolated palette uses a neutral backdrop; the source canvas has blurred playing media behind its translucent panel.",
                         background: Theme.Color.bgA3.color(scheme: .dark, accent: .orange),
                         renderEngine: .hostingView) {
                let app = AppModel.mock(.pausedEpisode)
                app.beginCustomizing()
                app.layouts.updateDraft { $0 = .twoRowExample }
                return MXRCustomizationView().appModel(app)
            },
            GalleryEntry(id: "S66.App/customization-compact", title: "Customize Player — 960 × 540 window (shipping composition)",
                         size: CGSize(width: 960, height: 540), screens: ["S66"],
                         notes: "SD-M2: inside the real MXRAppView the palette shows whole rows, the next row's icons peek out, and it scrolls.",
                         renderEngine: .hostingView) {
                let app = AppModel.mock(.pausedEpisode)
                app.beginCustomizing()
                return ShippingGallery.host(app) { MXRAppView(videoView: PlayerGallery.catVideo(windowSize: CGSize(width: 960, height: 540)), onPictureInPicture: {}) }
            },
            GalleryEntry(id: "S68.Profiles/movies", title: "Profiles — Movies selected",
                         size: MXRProfilesView.preferredSize, figmaNode: "6648:20514", screens: ["S68"],
                         notes: "The profile list scrolls in an AppKit-backed view that ImageRenderer draws as a placeholder; render it hosted.",
                         renderEngine: .hostingView) {
                MXRProfilesView().appModel(AppModel.mock(.pausedEpisode))
            },
            GalleryEntry(id: "S68.App/manage-profiles", title: "Profile ▸ Manage Profiles (shipping composition)",
                         size: Theme.Metric.Window.player.size, screens: ["S68"],
                         notes: "SD-15: a small card that closes after a choice, on Esc, ⌘W or a click outside.", renderEngine: .hostingView) {
                let app = AppModel.mock(.pausedEpisode)
                app.interface.present(.profiles)
                return ShippingGallery.host(app) { MXRAppView(videoView: PlayerGallery.catVideo(), onPictureInPicture: {}) }
            },
            GalleryEntry(id: "S69.Onboarding/welcome", title: "Onboarding — Welcome",
                         size: MXROnboardingView.preferredSize, figmaNode: "1899:3055", screens: ["S69"], renderEngine: .hostingView) {
                MXROnboardingView().appModel(AppModel.mock(.pausedEpisode))
            },
            GalleryEntry(id: "S71.Onboarding/shortcuts", title: "Onboarding — Keyboard shortcuts",
                         size: MXROnboardingView.preferredSize, figmaNode: "1902:6770", screens: ["S71"],
                         notes: "Keycaps show the bound keys, which are VLC's macOS engine defaults (⌘F, ⌥⌘← / ⌥⌘→, ⌘← / ⌘→, ⇧E / E, S, L, ⌘↑ / ⌘↓, ⌥⌘S, ⇧⌘R) and the app's Q and ⌘L, as the installed app shows them; Figma's keys are VLC's Windows defaults.",
                         renderEngine: .hostingView,
                         figmaDeviations: shortcutKeycapDeviations) {
                MXROnboardingView(initialStep: .shortcuts).appModel(AppModel.mock(.pausedEpisode))
            },
            GalleryEntry(id: "S72.Onboarding/light", title: "Onboarding — Light theme",
                         size: MXROnboardingView.preferredSize, screens: ["S70", "S72"], colorScheme: .light,
                         renderEngine: .hostingView) {
                let app = appearanceApp()
                app.appearance.setTheme(.light)
                return MXROnboardingView(initialStep: .appearance).appModel(app)
            },
            GalleryEntry(id: "S70.Onboarding/system", title: "Onboarding — System theme",
                         size: MXROnboardingView.preferredSize, screens: ["S70"], renderEngine: .hostingView) {
                let app = appearanceApp()
                app.appearance.setTheme(.system)
                return MXROnboardingView(initialStep: .appearance).appModel(app)
            },
        ]
        let nodes = ["1902:3670", "1902:4020", "1902:4325", "1902:4634", "1902:4940",
                     "1902:5245", "1902:5550", "1902:6160", "1902:6465"]
        for (accent, node) in zip(AccentChoice.allCases, nodes) {
            entries.append(GalleryEntry(id: "S70.Onboarding/\(accent.rawValue)",
                title: "Onboarding — \(accent.rawValue.capitalized) accent", size: MXROnboardingView.preferredSize,
                figmaNode: node, screens: ["S70"],
                notes: accent == .orange ? "" : "D049: the alternate-accent frames omit Back; the orange frame and the video keep it.",
                renderEngine: .hostingView,
                figmaDeviations: [previewTopBarDeviation] + (accent == .orange ? [] : [.differs(onboardingBackRect, decision: "D049",
                                                                    "Back kept on the alternate-accent frames")])) {
                let app = appearanceApp()
                app.appearance.setAccent(accent)
                return MXROnboardingView(initialStep: .appearance).appModel(app)
            })
        }
        return entries
    }

    /// The keycap columns of S71 (1904:7209): the product shows the Mac bindings (D026, D034).
    @MainActor private static var shortcutKeycapDeviations: [FigmaDeviation] {
        let o = Theme.Metric.Onboarding.self
        let top = o.shortcutTitleTop + o.shortcutTitle.height + o.shortcutColumnsGapAbove
        let keys = o.shortcutColumnsLabelWidth + o.shortcutColumnsLabelGap
        let width = o.shortcutColumnsColumnWidth + o.shortcutColumns.gap - keys
        return (0..<2).map { column in
            let x = o.shortcutColumnsLeading + CGFloat(column) * (o.shortcutColumnsColumnWidth + o.shortcutColumns.gap) + keys
            return .differs(CGRect(x: x, y: top, width: min(width, MXROnboardingView.preferredSize.width - x),
                                   height: o.shortcutColumns.height), decision: "D026",
                            "keycaps are VLC's macOS default bindings with Mac glyphs; Figma shows the Windows keys")
        }
    }

    /// The preview's top bar draws the Mac window's traffic lights, cone and fullscreen button (D022)
    /// where Figma draws Windows minimise, maximise, fullscreen and close.
    @MainActor private static var previewTopBarDeviation: FigmaDeviation {
        let o = Theme.Metric.Onboarding.self
        return .differs(CGRect(x: o.previewLeading, y: o.previewTop, width: o.preview.width,
                               height: Theme.Metric.topBarHeight * o.previewScale), decision: "D022",
                        "the preview shows the Mac player's top bar: traffic lights, cone, fullscreen only")
    }

    /// Where Back sits in the onboarding footer (6696:20706 at 820, 671 in 1902:3670): left of Next,
    /// centred in the footer row above its bottom inset.
    @MainActor private static var onboardingBackRect: CGRect {
        let o = Theme.Metric.Onboarding.self
        let button = Theme.Metric.Dialogs.onboardingButton
        let size = MXROnboardingView.preferredSize
        return CGRect(x: size.width - o.footerTrailing - 2 * button.width - o.footerGap,
                      y: size.height - o.footerBottom - (o.footerHeight + button.height) / 2,
                      width: button.width, height: button.height)
    }

    @MainActor private static func appearanceApp() -> AppModel {
        let app = AppModel.mock(.playingEpisode)
        app.player.pause()
        app.player.setVolume(0.5)
        return app
    }
}
