import AppKit
import Foundation
import os

/// Entry point of the design system. Tokens are generated into `Generated/Tokens.swift`
/// by `tools/gen-tokens.py` from `redesign/design/tokens/`; icons into `Generated/Icons.swift` and
/// `Resources/Icons.xcassets` by `tools/gen-icons.py`.
public enum DesignSystem {
    /// Registers bundled fonts (Inter, DM Mono). Call once at app start, before any view renders.
    /// Idempotent. Fonts are also registered lazily on first use of a `Theme.TextStyle`, so this only
    /// moves the work to startup and makes `Font.custom("Inter", …)` / `NSFont(name:)` work early.
    @MainActor public static func bootstrap() {
        _ = FontRegistry.fonts
    }

    /// The bundle holding MXRDesign's resources (fonts, `Icons.xcassets`), or `nil` when it cannot be
    /// found; then text falls back to the system font and icons draw nothing.
    ///
    /// SwiftPM's generated `Bundle.module` calls `fatalError` when the bundle is missing, which must
    /// never happen inside VLC, so the bundle is located here (ARCHITECTURE.md §7.6), trying in order:
    /// `$MXR_RESOURCES_PATH`, `$PACKAGE_RESOURCE_BUNDLE_PATH`, the main bundle's resources, the bundle
    /// of this code, the main bundle itself, and the directories around the binary that contains
    /// this code (plugin dylib → `Contents/Resources`; test bundle → the products directory).
    public static let resourceBundle: Bundle? = ResourceLocator.locate(bundleNamed: "MacOSXRedesign_MXRDesign")

    static let log = Logger(subsystem: "org.videolan.vlc-redesign", category: "design")
}

enum ResourceLocator {
    private final class Token {}

    static func locate(bundleNamed name: String) -> Bundle? {
        let fileName = name + ".bundle"
        let env = ProcessInfo.processInfo.environment
        var candidates: [URL] = []
        if let dir = env["MXR_RESOURCES_PATH"] {
            candidates.append(URL(fileURLWithPath: dir).appendingPathComponent(fileName))
        }
        if let path = env["PACKAGE_RESOURCE_BUNDLE_PATH"] {
            candidates.append(URL(fileURLWithPath: path))
            candidates.append(URL(fileURLWithPath: path).appendingPathComponent(fileName))
        }
        candidates += [Bundle.main.resourceURL, Bundle(for: Token.self).resourceURL, Bundle.main.bundleURL]
            .compactMap { $0?.appendingPathComponent(fileName) }
        if let image = imageDirectory() {
            candidates.append(image.appendingPathComponent(fileName))
            // VLC.app/Contents/MacOS/plugins/<dylib> → VLC.app/Contents/Resources
            candidates.append(image.appendingPathComponent("../../Resources/\(fileName)").standardizedFileURL)
            // <products>/X.xctest/Contents/MacOS/<binary> → <products>
            candidates.append(image.appendingPathComponent("../../../\(fileName)").standardizedFileURL)
        }
        for url in candidates {
            if let bundle = Bundle(url: url), bundle.resourceURL != nil {
                return bundle
            }
        }
        DesignSystem.log.error("MXRDesign resources not found (\(fileName, privacy: .public)); using fallbacks")
        return nil
    }

    /// Directory of the Mach-O image (app, plugin dylib, test bundle) that contains this code.
    private static func imageDirectory() -> URL? {
        var info = Dl_info()
        guard dladdr(#dsohandle, &info) != 0, let path = info.dli_fname else { return nil }
        return URL(fileURLWithPath: String(cString: path)).deletingLastPathComponent()
    }
}
