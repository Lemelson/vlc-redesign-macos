// swift-tools-version: 6.0
// SwiftPM manifest for the macosx_redesign interface module.
// See redesign/docs/ARCHITECTURE.md §2 and §7. Owned by the orchestrator:
// add targets here only through redesign/docs/DECISIONS.md.
import PackageDescription

let package = Package(
    name: "MacOSXRedesign",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MXRPlugin", type: .static, targets: ["MXRPlugin"]),
        .executable(name: "MXRGallery", targets: ["MXRGallery"]),
        .executable(name: "mxr-snapshot", targets: ["MXRSnapshot"]),
    ],
    targets: [
        // Objective-C interface of the bridge (Foundation types only, never <vlc_*.h>).
        .target(name: "MXRBridgeAPI", publicHeadersPath: "include"),
        // Backend protocols, @MainActor @Observable models, settings schema.
        .target(name: "MXRCore", resources: [.process("Resources")]),
        // Tokens (generated), fonts, icons, design-system components.
        .target(name: "MXRDesign", dependencies: ["MXRCore"], resources: [.process("Resources")]),
        // Windows, player chrome, panels, library, settings, dialogs, menus.
        .target(name: "MXRUI", dependencies: ["MXRCore", "MXRDesign"]),
        // Scripted fake data implementing every MXRCore protocol.
        .target(name: "MXRMockBackend", dependencies: ["MXRCore"], resources: [.process("Resources")]),
        // Adapts the Objective-C bridge to the MXRCore protocols.
        .target(name: "MXRVLCBackend", dependencies: ["MXRCore", "MXRBridgeAPI"]),
        // @_cdecl entry points; static library force-loaded into the VLC plugin.
        .target(name: "MXRPlugin", dependencies: ["MXRUI", "MXRVLCBackend"]),
        // Gallery entries (one provider class per component/screen, discovered at runtime).
        .target(name: "MXRGalleryCatalog", dependencies: ["MXRUI", "MXRDesign", "MXRMockBackend"]),
        // Standalone app to browse every component/screen with mock data, next to its Figma render.
        .executableTarget(name: "MXRGallery", dependencies: ["MXRGalleryCatalog"]),
        // CLI: render gallery entries to PNG and compare them with Figma renders.
        .executableTarget(name: "MXRSnapshot", dependencies: ["MXRGalleryCatalog"]),
        .testTarget(name: "MXRCoreTests", dependencies: ["MXRCore", "MXRMockBackend"]),
        .testTarget(name: "MXRVLCBackendTests", dependencies: ["MXRVLCBackend", "MXRCore", "MXRBridgeAPI"],
                    resources: [.copy("Resources")]),
        .testTarget(name: "MXRUISnapshotTests", dependencies: ["MXRGalleryCatalog"]),
    ],
    swiftLanguageModes: [.v6]
)
