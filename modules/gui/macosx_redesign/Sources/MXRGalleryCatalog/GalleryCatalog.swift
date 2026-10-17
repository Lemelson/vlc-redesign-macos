import Accelerate
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import MXRDesign
import MXRUI
import ObjectiveC
import SwiftUI
import UniformTypeIdentifiers

// Gallery catalog and the visual-verification tooling shared by the Gallery app
// (`swift run MXRGallery`), the `mxr-snapshot` CLI and the snapshot tests.
//
// Sections:
//   1. Entries and provider discovery (the contract every `Entries/*.swift` file uses)
//   2. Environment and theme hook (color scheme, accent)
//   3. Repository paths
//   4. Rendering entries to images
//   5. Figma node index and reference crops
//   6. Image comparison
//
// See redesign/docs/WORKFLOW.md, "Compare to Figma", for how this is used.

// MARK: - 1. Entries and provider discovery

/// Top-level group of a gallery entry, taken from the first letter of its id.
public enum GalleryKind: String, CaseIterable, Sendable, Comparable {
    /// `D.*`: design-system foundations (tokens, type, icons).
    case designSystem = "D"
    /// `C.*`: reusable components.
    case component = "C"
    /// `S01.*` … : screens from redesign/design/SCREENS.md.
    case screen = "S"
    /// `X.*`: scaffolding and experiments.
    case other = "X"

    /// Human-readable group title.
    public var title: String {
        switch self {
        case .designSystem: "Design System"
        case .component: "Components"
        case .screen: "Screens"
        case .other: "Other"
        }
    }

    /// The kind of an entry id (`C.SeekBar/hover` → `.component`).
    public init(entryID: String) {
        switch entryID.first {
        case "D": self = .designSystem
        case "C": self = .component
        case "S": self = .screen
        default: self = .other
        }
    }

    public static func < (lhs: GalleryKind, rhs: GalleryKind) -> Bool {
        let order = allCases
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

/// How an entry is rasterized by `mxr-snapshot` and the snapshot tests.
public enum GalleryRenderEngine: String, CaseIterable, Sendable {
    /// SwiftUI `ImageRenderer`. Fast and fully headless, but it cannot draw AppKit-backed
    /// views (`NSViewRepresentable`, some native controls, materials); those show up as a
    /// placeholder. The default.
    case imageRenderer = "image"
    /// An `NSHostingView` in an off-screen window captured with `cacheDisplay(in:to:)`.
    /// Draws AppKit-backed views; needs a window-server session (any Terminal on the Mac).
    case hostingView = "hosting"
    /// Actual titled/fullSizeContentView host with native titlebar controls, captured offscreen.
    /// Exercises AppKit safe-area composition; does not establish installed-app/GPU appearance.
    case shippingWindow = "shipping-window"
}

/// One renderable state of a component or screen, shown in the Gallery app and
/// rendered to PNG by `mxr-snapshot` for comparison with the Figma render.
public enum GalleryBackdropMode: String, Sendable, Codable {
    /// An exported component has no WindowServer backdrop. Compare its tint and geometry.
    case isolatedTint
    /// A complete app scene retains live materials; offscreen pixels do not verify GPU blur.
    case liveMaterial
}

public struct GalleryEntry: Identifiable, Sendable {
    /// Stable id: `<kind>.<Name>/<state>`, e.g. `C.SeekBar/playing-hover`, `S01.Player/default`.
    public let id: String
    public let title: String
    /// Canvas size in points (the Figma node size).
    public let size: CGSize
    /// Figma node this entry reproduces (see redesign/design/figma/INDEX.md), if any.
    /// Point it at the exact node whose `absoluteBoundingBox` equals `size`, usually a
    /// variant inside a component set (e.g. `848:1711` "type=play" in the `play` set).
    public let figmaNode: String?
    /// Screen ids from redesign/design/SCREENS.md this entry belongs to.
    public let screens: [String]
    public let colorScheme: ColorScheme
    public let notes: String
    /// Surface drawn behind the entry (use a token color, e.g. the panel the component sits
    /// on in the Figma frame). `nil` keeps the canvas transparent, which is right for nodes
    /// inside transparent component sets.
    public let background: Color?
    /// Rasterizer used by `mxr-snapshot` and the snapshot tests.
    public let renderEngine: GalleryRenderEngine
    public let backdropMode: GalleryBackdropMode
    /// Where the entry intentionally differs from `figmaNode`, each with the decision behind it.
    /// `mxr-snapshot check` and the snapshot tests compare everything else strictly (see `FigmaDeviation`).
    public let figmaDeviations: [FigmaDeviation]
    public let make: @MainActor @Sendable () -> AnyView

    public init(
        id: String,
        title: String,
        size: CGSize,
        figmaNode: String? = nil,
        screens: [String] = [],
        colorScheme: ColorScheme = .dark,
        notes: String = "",
        background: Color? = nil,
        renderEngine: GalleryRenderEngine = .imageRenderer,
        backdropMode: GalleryBackdropMode = .isolatedTint,
        figmaDeviations: [FigmaDeviation] = [],
        make: @escaping @MainActor @Sendable () -> some View
    ) {
        self.id = id
        self.title = title
        self.size = size
        self.figmaNode = figmaNode
        self.screens = screens
        self.colorScheme = colorScheme
        self.notes = notes
        self.background = background
        self.renderEngine = renderEngine
        self.backdropMode = backdropMode
        self.figmaDeviations = figmaDeviations
        self.make = { AnyView(make()) }
    }

    /// `C`, `D`, `S` or `X` group of the id.
    public var kind: GalleryKind { GalleryKind(entryID: id) }
    /// The component or screen part of the id (`C.SeekBar` in `C.SeekBar/hover`).
    public var group: String { id.split(separator: "/", maxSplits: 1).first.map(String.init) ?? id }
    /// The state part of the id (`hover` in `C.SeekBar/hover`); empty when the id has no `/`.
    public var state: String {
        let parts = id.split(separator: "/", maxSplits: 1)
        return parts.count == 2 ? String(parts[1]) : ""
    }
    /// The id made safe for file names (`C.SeekBar/hover` → `C.SeekBar__hover`).
    public var fileSafeID: String {
        var result = ""
        for character in id {
            if character == "/" {
                result += "__"
            } else if character.isLetter || character.isNumber || "._-".contains(character) {
                result.append(character)
            } else {
                result += "_"
            }
        }
        return result
    }
}

/// Adopt this in one `final class <Name>Gallery: NSObject, GalleryProvider` per component or
/// screen, in its own file under `Sources/MXRGalleryCatalog/Entries/`. Providers are discovered
/// at runtime, so no shared list has to be edited when a new one is added.
@objc public protocol GalleryProvider: NSObjectProtocol {
    @MainActor static func galleryEntries() -> [Any]
}

// MARK: - 2. Environment and theme hook

/// The environment an entry is shown or rendered in.
/// What the canvas being built is rendered with, readable from an entry's factory while
/// ``GalleryCatalog/canvas(for:environment:engine:)`` calls it (nil outside that call).
public struct GalleryRenderContext: Sendable {
    public var environment: GalleryEnvironment
    public var engine: GalleryRenderEngine
    @MainActor public internal(set) static var current: GalleryRenderContext?
}

public struct GalleryEnvironment: Hashable, Sendable {
    public var colorScheme: ColorScheme
    /// Accent swatch name (`accentSwatches` in redesign/design/tokens/colors.json, e.g.
    /// `"orange"`); `nil` uses the design default.
    public var accent: String?

    public init(colorScheme: ColorScheme = .dark, accent: String? = nil) {
        self.colorScheme = colorScheme
        self.accent = accent
    }
}

/// One accent option offered by the Gallery and `mxr-snapshot --accent`.
public struct GalleryAccent: Identifiable, Hashable, Sendable {
    /// Swatch name, e.g. `"orange"`.
    public let id: String
    /// Swatch color, for the picker.
    public let color: Color

    public init(id: String, color: Color) {
        self.id = id
        self.color = color
    }
}

/// How entries are themed: the accents on offer and how to apply an environment to a view.
public struct GalleryTheme: Sendable {
    public let accents: [GalleryAccent]
    /// Swatch used when the environment has no accent.
    public let defaultAccent: String?
    /// Applies the accent (and anything else the design system needs) to an entry's view.
    /// The color scheme is applied by the catalog afterwards.
    public let apply: @MainActor @Sendable (AnyView, GalleryEnvironment) -> AnyView

    public init(
        accents: [GalleryAccent],
        defaultAccent: String?,
        apply: @escaping @MainActor @Sendable (AnyView, GalleryEnvironment) -> AnyView
    ) {
        self.accents = accents
        self.defaultAccent = defaultAccent
        self.apply = apply
    }
}

/// The design system adopts this once (`final class ThemeGallery: NSObject, GalleryThemeProvider`
/// under `Entries/`) to tell the Gallery and `mxr-snapshot` how to apply an accent. Return a
/// `GalleryTheme`. Without a provider the catalog falls back to `.tint(_:)` with the swatches
/// read from redesign/design/tokens/colors.json.
@objc public protocol GalleryThemeProvider: NSObjectProtocol {
    @MainActor static func galleryTheme() -> Any
}

public enum GalleryCatalog {
    /// Prepares the design system (registers fonts). Call once before showing or rendering entries.
    @MainActor
    public static func bootstrap() {
        DesignSystem.bootstrap()
    }

    /// All entries from every `GalleryProvider`, sorted by id.
    @MainActor
    public static func allEntries() -> [GalleryEntry] {
        classes(conformingTo: GalleryProvider.self)
            .compactMap { $0 as? GalleryProvider.Type }
            .flatMap { $0.galleryEntries().compactMap { $0 as? GalleryEntry } }
            .sorted { $0.id < $1.id }
    }

    @MainActor
    public static func entry(id: String) -> GalleryEntry? {
        allEntries().first { $0.id == id }
    }

    @MainActor private static var cachedTheme: GalleryTheme?

    /// The registered `GalleryThemeProvider`'s theme, or the token-file fallback.
    @MainActor
    public static func theme() -> GalleryTheme {
        if let cachedTheme { return cachedTheme }
        let provided = classes(conformingTo: GalleryThemeProvider.self)
            .compactMap { $0 as? GalleryThemeProvider.Type }
            .lazy
            .compactMap { $0.galleryTheme() as? GalleryTheme }
            .first
        let theme = provided ?? fallbackTheme()
        cachedTheme = theme
        return theme
    }

    /// The entry's view in `environment` (defaults to the entry's own color scheme), framed to
    /// `entry.size`, clipped, on `entry.background`. This is exactly what gets rendered. In the
    /// shipping window (the entry's engine or `engine`) the view is the window's content as is.
    @MainActor
    public static func canvas(for entry: GalleryEntry, environment: GalleryEnvironment? = nil,
                              engine: GalleryRenderEngine? = nil) -> AnyView {
        let environment = environment ?? GalleryEnvironment(colorScheme: entry.colorScheme)
        // Window and App scenes put the scheme and accent into their AppModel (MXRAppView themes
        // itself from it) and set up the native titlebar when they land in the shipping window.
        GalleryRenderContext.current = GalleryRenderContext(
            environment: environment, engine: GalleryRenderer.effectiveEngine(for: entry, override: engine))
        defer { GalleryRenderContext.current = nil }
        let themed = theme().apply(entry.make(), environment)
        let configured = themed
            .environment(\.colorScheme, environment.colorScheme)
            .mxrNativeBackdropEnabled(entry.backdropMode == .liveMaterial)
        // AppController gives MXRAppView directly to NSHostingView. A fixed frame + clip wrapper
        // would cut off the part that ignores the native titlebar safe area (the first 40 pt) and
        // centre the window content (and its dialogs) in the area below the titlebar. This also
        // holds for `--engine shipping-window` on an App entry (A-window parity trap).
        if GalleryRenderer.effectiveEngine(for: entry, override: engine) == .shippingWindow { return AnyView(configured) }
        return AnyView(
            configured
                .frame(width: entry.size.width, height: entry.size.height)
                .background { if let background = entry.background { background } }
                .clipped()
        )
    }

    private static func classes(conformingTo proto: Protocol) -> [AnyClass] {
        // objc_copyClassList returns a snapshot and its exact length. Sizing a buffer with
        // objc_getClassList(nil, 0) and filling it with a second call races with frameworks that
        // register classes on other threads in between: the second call returns the new, larger
        // total and the loop read past the buffer (SIGSEGV in swift_getObjCClassFromMetadata).
        var count: UInt32 = 0
        guard let copied = objc_copyClassList(&count) else { return [] }
        let raw = UnsafeMutableRawPointer(copied)
        defer { free(raw) }
        // Read the entries as plain metatypes: AutoreleasingUnsafeMutablePointer's subscript would
        // message them, and some root classes (__NSGenericDeallocHandler) implement no methods.
        let list = raw.assumingMemoryBound(to: AnyClass.self)
        var result: [AnyClass] = []
        for index in 0..<Int(count) where class_conformsToProtocol(list[index], proto) {
            result.append(list[index])
        }
        return result
    }

    private static func fallbackTheme() -> GalleryTheme {
        let swatches = (try? GalleryPaths.locate()).map(TokenSwatches.load) ?? []
        let accents = swatches.map { GalleryAccent(id: $0.name, color: $0.color) }
        let defaultAccent = swatches.first(where: \.isDefault)?.name ?? swatches.first?.name
        return GalleryTheme(accents: accents, defaultAccent: defaultAccent) { view, environment in
            let name = environment.accent ?? defaultAccent
            guard let accent = accents.first(where: { $0.id == name }) else { return view }
            return AnyView(view.tint(accent.color))
        }
    }
}

/// Accent swatches read from redesign/design/tokens/colors.json (fallback theme only).
private struct TokenSwatches {
    let name: String
    let color: Color
    let isDefault: Bool

    static func load(paths: GalleryPaths) -> [TokenSwatches] {
        let url = paths.tokensDirectory.appending(path: "colors.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let group = root["accentSwatches"] as? [String: Any],
              let swatches = group["swatches"] as? [[String: Any]]
        else { return [] }
        return swatches.compactMap { swatch in
            guard let name = swatch["name"] as? String, let hex = swatch["hex"] as? String,
                  let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16)
            else { return nil }
            let channel = { (shift: UInt32) in Double((value >> shift) & 0xFF) / 255 }
            return TokenSwatches(
                name: name,
                color: Color(.sRGB, red: channel(16), green: channel(8), blue: channel(0)),
                isDefault: swatch["default"] as? Bool ?? false
            )
        }
    }
}

// MARK: - 3. Repository paths

/// Error thrown by the gallery tooling, with a message meant for the terminal.
public struct GalleryToolingError: Error, CustomStringConvertible, LocalizedError {
    public let description: String
    public init(_ description: String) { self.description = description }
    public var errorDescription: String? { description }
}

/// Locations of the design data and the tool cache inside the repository.
public struct GalleryPaths: Sendable {
    public let repoRoot: URL

    public init(repoRoot: URL) { self.repoRoot = repoRoot }

    public var figmaDirectory: URL { repoRoot.appending(path: "redesign/design/figma", directoryHint: .isDirectory) }
    public var figmaJSON: URL { figmaDirectory.appending(path: "figma_file.json") }
    public var figmaIndexMarkdown: URL { figmaDirectory.appending(path: "INDEX.md") }
    public var rendersDirectory: URL { figmaDirectory.appending(path: "renders", directoryHint: .isDirectory) }
    public var tokensDirectory: URL { repoRoot.appending(path: "redesign/design/tokens", directoryHint: .isDirectory) }
    public var packageDirectory: URL {
        repoRoot.appending(path: "modules/gui/macosx_redesign", directoryHint: .isDirectory)
    }
    /// `<package>/.build/mxr-tools`: git-ignored cache and default output root of the tooling.
    public var toolsDirectory: URL { packageDirectory.appending(path: ".build/mxr-tools", directoryHint: .isDirectory) }
    /// Default output directory for one entry (`<tools>/snapshots/<file-safe id>`).
    public func snapshotDirectory(for entry: GalleryEntry) -> URL {
        toolsDirectory.appending(path: "snapshots/\(entry.fileSafeID)", directoryHint: .isDirectory)
    }

    /// Finds the repository: `$MXR_REPO_ROOT`, then the directories above this source file,
    /// the current directory and the executable.
    public static func locate() throws -> GalleryPaths {
        var starts: [URL] = []
        if let env = ProcessInfo.processInfo.environment["MXR_REPO_ROOT"], !env.isEmpty {
            starts.append(URL(fileURLWithPath: env, isDirectory: true))
        }
        starts.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent())
        starts.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
        if let executable = Bundle.main.executableURL { starts.append(executable.deletingLastPathComponent()) }
        let marker = "redesign/design/figma/figma_file.json"
        for start in starts {
            var dir = start.standardizedFileURL
            while true {
                if FileManager.default.fileExists(atPath: dir.appending(path: marker).path) {
                    return GalleryPaths(repoRoot: dir)
                }
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break }
                dir = parent
            }
        }
        throw GalleryToolingError("cannot find the repository (no \(marker) above \(starts.map(\.path))); set MXR_REPO_ROOT")
    }
}

// MARK: - 4. Rendering entries to images

/// Rasterizes gallery entries exactly as the Gallery canvas shows them.
public enum GalleryRenderer {
    /// Makes Core Text rasterize glyphs like Figma does, by turning off font smoothing (stem
    /// darkening) for this process. Font smoothing adds about 30 % ink to light text, which would
    /// make every text-bearing entry differ from its Figma render.
    ///
    /// Core Text reads the setting once, so call this before any text is drawn (first thing in
    /// `main`, or at app init); later calls change nothing for this process. On screen in the
    /// real app, text keeps the macOS default and looks slightly heavier than in Figma.
    @MainActor
    public static func matchFigmaTextRasterization() {
        let defaults = UserDefaults.standard
        var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        guard arguments["AppleFontSmoothing"] == nil else { return }
        arguments["AppleFontSmoothing"] = 0
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }

    /// Renders `entry` at `entry.size` × `scale` pixels (sRGB, transparent where the entry draws nothing).
    @MainActor
    public static func render(
        _ entry: GalleryEntry,
        scale: CGFloat = 2,
        environment: GalleryEnvironment? = nil,
        engine: GalleryRenderEngine? = nil
    ) throws -> CGImage {
        let environment = environment ?? GalleryEnvironment(colorScheme: entry.colorScheme)
        if effectiveEngine(for: entry, override: engine) != .imageRenderer { _ = NSApplication.shared }
        let content = GalleryCatalog.canvas(for: entry, environment: environment, engine: engine)
        let appearance = NSAppearance(named: environment.colorScheme == .dark ? .darkAqua : .aqua)
        switch effectiveEngine(for: entry, override: engine) {
        case .imageRenderer:
            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = ProposedViewSize(entry.size)
            renderer.scale = scale
            renderer.isOpaque = false
            var image: CGImage?
            if let appearance {
                appearance.performAsCurrentDrawingAppearance { image = renderer.cgImage }
            } else {
                image = renderer.cgImage
            }
            guard let image else { throw GalleryToolingError("ImageRenderer produced no image for \(entry.id)") }
            return image
        case .hostingView, .shippingWindow:
            return try renderWithHostingView(content, size: entry.size, scale: scale, appearance: appearance,
                                             id: entry.id, shippingWindow: effectiveEngine(for: entry, override: engine) == .shippingWindow)
        }
    }

    /// A screen claiming shipping composition cannot be downgraded to a component surrogate.
    public static func effectiveEngine(for entry: GalleryEntry, override: GalleryRenderEngine? = nil) -> GalleryRenderEngine {
        entry.renderEngine == .shippingWindow ? .shippingWindow : (override ?? entry.renderEngine)
    }

    /// Expected pixel size of a render of `size` points at `scale`.
    public static func pixelSize(of size: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        (Int((size.width * scale).rounded()), Int((size.height * scale).rounded()))
    }

    @MainActor
    private static func renderWithHostingView(
        _ content: AnyView, size: CGSize, scale: CGFloat, appearance: NSAppearance?, id: String, shippingWindow: Bool
    ) throws -> CGImage {
        _ = NSApplication.shared
        let rect = CGRect(origin: .zero, size: size)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = rect
        let style: NSWindow.StyleMask = shippingWindow
            ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView] : [.borderless]
        let window = NSWindow(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
        if shippingWindow {
            MXRWindowControls.configure(window)
            // Gallery sizes describe the complete Figma window, including its titlebar.
            window.setFrame(rect, display: false)
        }
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = appearance
        window.contentView = hosting
        defer {
            window.contentView = nil
            window.close()
        }
        hosting.layoutSubtreeIfNeeded()
        // Let SwiftUI commit its first transaction before capturing.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        hosting.layoutSubtreeIfNeeded()
        let pixels = pixelSize(of: size, scale: scale)
        guard let blank = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels.width, pixelsHigh: pixels.height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let rep = blank.retagging(with: .sRGB) else {
            throw GalleryToolingError("cannot allocate a \(pixels.width)×\(pixels.height) bitmap for \(id)")
        }
        rep.size = size
        // Capture the real frame view for shipping windows: traffic lights remain owned by AppKit.
        // No surrogate buttons or borderless host can hide titlebar safe-area regressions here.
        let captureView = shippingWindow ? (hosting.superview ?? hosting) : hosting
        captureView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        captureView.cacheDisplay(in: captureView.bounds, to: rep)
        guard let image = rep.cgImage else { throw GalleryToolingError("cacheDisplay produced no image for \(id)") }
        return image
    }
}

/// PNG reading and writing in sRGB.
public enum GalleryImageIO {
    /// The sRGB color space every tool image is drawn in.
    public static var sRGB: CGColorSpace { CGColorSpace(name: CGColorSpace.sRGB)! }

    /// Reads a PNG (or any ImageIO format).
    public static func read(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw GalleryToolingError("cannot read image \(url.path)") }
        return image
    }

    /// Writes `image` as PNG, creating the parent directory.
    public static func writePNG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw GalleryToolingError("cannot write \(url.path)") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw GalleryToolingError("cannot write \(url.path)") }
    }

    /// A transparent sRGB RGBA8 premultiplied bitmap context. Memory row 0 is the top row.
    static func makeContext(width: Int, height: Int, data: UnsafeMutableRawPointer? = nil) -> CGContext? {
        CGContext(
            data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// `image` drawn top-left aligned into a `width`×`height` RGBA8 premultiplied buffer,
    /// optionally over `backdrop`.
    static func rgba(_ image: CGImage?, width: Int, height: Int, backdrop: ComparisonBackdrop? = nil) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { raw in
            guard let context = makeContext(width: width, height: height, data: raw.baseAddress) else { return }
            context.interpolationQuality = .none
            if let backdrop { backdrop.fill(context, width: width, height: height) }
            if let image {
                context.draw(image, in: CGRect(x: 0, y: height - image.height, width: image.width, height: image.height))
            }
        }
        return data
    }

    /// The pixels of `image` inside `rect` (whole pixels, top-left origin) as an RGBA8
    /// premultiplied buffer of `rect`'s size, copied exactly; transparent outside the image.
    static func rgba(_ image: CGImage, cropping rect: CGRect) -> [UInt8] {
        let width = Int(rect.width), height = Int(rect.height)
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let visible = rect.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !visible.isNull, !visible.isEmpty, let piece = image.cropping(to: visible) else { return data }
        data.withUnsafeMutableBytes { raw in
            guard let context = makeContext(width: width, height: height, data: raw.baseAddress) else { return }
            context.interpolationQuality = .none
            let left = visible.minX - rect.minX, top = visible.minY - rect.minY
            // CGImage cropping uses top-left pixel coordinates; the context is bottom-left.
            context.draw(piece, in: CGRect(x: left, y: CGFloat(height) - top - visible.height,
                                           width: visible.width, height: visible.height))
        }
        return data
    }

    /// An image from an RGBA8 premultiplied buffer.
    static func image(fromRGBA data: [UInt8], width: Int, height: Int) -> CGImage? {
        var copy = data
        return copy.withUnsafeMutableBytes { raw in
            makeContext(width: width, height: height, data: raw.baseAddress)?.makeImage()
        }
    }
}

// MARK: - 5. Figma node index and reference crops

/// A top-level frame (or component set) of the Figma file and its render in `renders/`.
public struct FigmaFrame: Sendable, Equatable {
    public let id: String
    public let name: String
    public let type: String
    /// Path of the frame's PNG render relative to `redesign/design/figma/renders/`.
    public let renderFile: String
    public let boundingBox: CGRect
    /// `absoluteRenderBounds`: the bounding box plus effect bleed. The render covers exactly this.
    public let renderBounds: CGRect
}

/// A node of the Figma file (any depth).
public struct FigmaNode: Sendable, Equatable {
    public let id: String
    public let name: String
    public let type: String
    public let parentID: String?
    /// The top-level frame containing the node (the node itself for top-level frames).
    public let frameID: String
    /// 0 for top-level frames.
    public let depth: Int
    public let visible: Bool
    /// `absoluteBoundingBox` in canvas coordinates (Figma px = points).
    public let boundingBox: CGRect
    /// `absoluteRenderBounds` (includes shadows); `nil` for hidden or empty nodes.
    public let renderBounds: CGRect?
    /// Text of TEXT nodes (first 120 characters), otherwise empty.
    public let text: String
}

/// Which rectangle of a node to crop.
public enum FigmaCropBounds: String, CaseIterable, Sendable {
    /// `absoluteBoundingBox`: the node's own box, without shadows. Matches `GalleryEntry.size`.
    case boundingBox = "box"
    /// `absoluteRenderBounds`: includes drop-shadow bleed.
    case renderBounds = "render"
}

/// A node cropped out of its frame's render.
public struct FigmaReference: Sendable {
    public let node: FigmaNode
    public let frame: FigmaFrame
    public let renderURL: URL
    /// Crop rectangle in render pixels, top-left origin. Fractional when the frame's render
    /// bounds start between pixels; the crop is then resampled (see `isSubpixelShifted`).
    public let pixelRect: CGRect
    /// Pixels per Figma px of the frame render: the export scale (2), or the measured ratio
    /// when the PNG size doesn't fit `ceil(renderBounds × 2)`.
    public let renderScale: CGSize
    /// Scale of `image` (pixels per point).
    public let scale: CGFloat
    public let image: CGImage
    /// Things to keep in mind when comparing (hidden node, crop outside the render, …).
    public let warnings: [String]

    /// Whether the crop starts between render pixels and was resampled bilinearly so the
    /// node's content starts exactly at the top-left corner (its edges are slightly softer).
    public var isSubpixelShifted: Bool {
        !FigmaIndex.isIntegral(pixelRect.minX) || !FigmaIndex.isIntegral(pixelRect.minY)
    }
}

/// Index of every node in redesign/design/figma/figma_file.json, mapped to the frame renders.
///
/// Parsing the 25 MB JSON takes about a second, so the index is cached as a TSV in
/// `<package>/.build/mxr-tools/` and rebuilt when the JSON or INDEX.md changes.
public final class FigmaIndex: Sendable {
    public let paths: GalleryPaths
    /// Top-level frames by id.
    public let frames: [String: FigmaFrame]
    /// Top-level frame ids in layer order.
    public let frameOrder: [String]
    /// Every node by id.
    public let nodes: [String: FigmaNode]
    private let order: [String]
    private let childIDs: [String: [String]]

    private init(paths: GalleryPaths, frames: [FigmaFrame], nodes: [FigmaNode]) {
        self.paths = paths
        self.frames = Dictionary(frames.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.frameOrder = frames.map(\.id)
        self.nodes = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.order = nodes.map(\.id)
        var children: [String: [String]] = [:]
        for node in nodes { if let parent = node.parentID { children[parent, default: []].append(node.id) } }
        self.childIDs = children
    }

    @MainActor private static var sharedIndex: FigmaIndex?

    /// The index for the located repository, loaded once per process.
    @MainActor
    public static func shared() throws -> FigmaIndex {
        if let sharedIndex { return sharedIndex }
        let index = try load(paths: GalleryPaths.locate())
        sharedIndex = index
        return index
    }

    /// Loads the index from the cache, or parses figma_file.json and refreshes the cache.
    public static func load(paths: GalleryPaths) throws -> FigmaIndex {
        let stamp = try sourceStamp(paths)
        let cacheURL = paths.toolsDirectory.appending(path: "figma-node-index.tsv")
        if let cached = try? readCache(cacheURL, stamp: stamp, paths: paths) { return cached }
        let index = try parse(paths: paths)
        try? index.writeCache(cacheURL, stamp: stamp)
        return index
    }

    /// Accepts `848:1712`, `848-1712` (Figma URL form) and instance ids like `I848:1707;42:300`.
    public static func normalizedID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains(":"), trimmed.contains("-") { return trimmed.replacingOccurrences(of: "-", with: ":") }
        return trimmed
    }

    public func node(_ id: String) -> FigmaNode? { nodes[Self.normalizedID(id)] }

    public func frame(containing node: FigmaNode) -> FigmaFrame? { frames[node.frameID] }

    /// Direct children in layer order.
    public func children(of id: String) -> [FigmaNode] {
        (childIDs[Self.normalizedID(id)] ?? []).compactMap { nodes[$0] }
    }

    /// Path from the top-level frame down to the node.
    public func ancestry(of node: FigmaNode) -> [FigmaNode] {
        var chain = [node]
        var current = node
        while let parent = current.parentID.flatMap({ nodes[$0] }) {
            chain.insert(parent, at: 0)
            current = parent
        }
        return chain
    }

    /// The outermost hidden layer on the path to `node` (the node itself when only it is
    /// hidden), or `nil` when the node is visible. Figma renders nothing inside a hidden layer.
    public func hiddenAncestor(of node: FigmaNode) -> FigmaNode? {
        ancestry(of: node).first { !$0.visible }
    }

    /// Nodes whose name or text contains `query` (case-insensitive), in layer order.
    public func search(_ query: String, inFrame frameID: String? = nil, type: String? = nil, limit: Int = 50) -> [FigmaNode] {
        let frameID = frameID.map(Self.normalizedID)
        var result: [FigmaNode] = []
        for id in order {
            guard let node = nodes[id] else { continue }
            if let frameID, node.frameID != frameID { continue }
            if let type, node.type.caseInsensitiveCompare(type) != .orderedSame { continue }
            if query.isEmpty || node.name.localizedCaseInsensitiveContains(query)
                || node.text.localizedCaseInsensitiveContains(query) || node.id == query {
                result.append(node)
                if result.count >= limit { break }
            }
        }
        return result
    }

    public func renderURL(for frame: FigmaFrame) -> URL {
        paths.rendersDirectory.appending(path: frame.renderFile)
    }

    /// Crops `nodeID` out of its frame render at `scale` pixels per point.
    ///
    /// A frame's render covers its `absoluteRenderBounds` at the export scale (2): pixel (0, 0)
    /// is the render-bounds origin and the PNG is `ceil(bounds × 2)` pixels. A node's crop is
    /// its box minus that origin, times the export scale. When that lands between pixels (the
    /// Onboarding, Components and Designs frames have render bounds like x.2 / y.8), the crop is
    /// resampled bilinearly so the node's content starts exactly at its top-left corner. A
    /// `scale` other than the export scale resamples the crop. The output is always
    /// `round(box × scale)` pixels (halves rounded away from zero).
    public func reference(for nodeID: String, scale: CGFloat = 2, bounds: FigmaCropBounds = .boundingBox) throws -> FigmaReference {
        guard let node = node(nodeID) else { throw GalleryToolingError("unknown Figma node \(nodeID)") }
        guard let frame = frame(containing: node) else {
            throw GalleryToolingError("node \(node.id) has no top-level frame with a render")
        }
        let renderURL = renderURL(for: frame)
        let source = try GalleryImageIO.read(renderURL)
        let box = bounds == .renderBounds ? (node.renderBounds ?? node.boundingBox) : node.boundingBox
        let origin = frame.renderBounds.origin
        let export = Self.exportScale(of: frame, imageWidth: source.width, imageHeight: source.height)
        let renderScale = export.scale
        let output = GalleryRenderer.pixelSize(of: box.size, scale: scale)
        let exact = CGRect(
            x: Self.snapped((box.minX - origin.x) * renderScale.width),
            y: Self.snapped((box.minY - origin.y) * renderScale.height),
            width: box.width * renderScale.width,
            height: box.height * renderScale.height
        )
        guard output.width > 0, output.height > 0, exact.width > 0, exact.height > 0 else {
            throw GalleryToolingError("node \(node.id) has an empty box \(box)")
        }
        // At the export scale the crop is a 1:1 copy of `output` pixels (shifted bilinearly when
        // it starts between pixels); at another scale the exact rectangle is resampled.
        let native = abs(renderScale.width - scale) < 0.01 && abs(renderScale.height - scale) < 0.01
        let pixelRect = native
            ? CGRect(x: exact.minX, y: exact.minY, width: CGFloat(output.width), height: CGFloat(output.height))
            : CGRect(x: exact.minX, y: exact.minY, width: Self.snapped(exact.width), height: Self.snapped(exact.height))

        var warnings: [String] = []
        if let hidden = hiddenAncestor(of: node) {
            warnings.append(hidden.id == node.id
                ? "node is hidden in Figma (visible: false); the render doesn't show it"
                : "node is inside the hidden layer \"\(hidden.name)\" [\(hidden.id)]; the render doesn't show it")
        }
        let imageBounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        if !imageBounds.contains(pixelRect) {
            warnings.append("node extends beyond its frame render; the outside part is transparent")
        }
        if !export.fitsRule {
            warnings.append(String(format: "render size doesn't match its bounds at 2×; using the measured %.3f×%.3f px/pt",
                                   renderScale.width, renderScale.height))
        }
        if !native {
            warnings.append(String(format: "crop resampled from the %.4g× render to %.4g×", renderScale.width, scale))
        } else if !Self.isIntegral(pixelRect.minX) || !Self.isIntegral(pixelRect.minY) {
            warnings.append(String(
                format: "the frame render starts between pixels: crop shifted by %.2f, %.2f px (bilinear), so edges are slightly softer than in the render",
                pixelRect.minX - pixelRect.minX.rounded(.down), pixelRect.minY - pixelRect.minY.rounded(.down)
            ))
        }

        let image: CGImage?
        if native {
            image = Self.copyCrop(source, origin: pixelRect.origin, width: output.width, height: output.height)
        } else {
            image = Self.resampledCrop(source, rect: pixelRect, width: output.width, height: output.height)
        }
        guard let image else { throw GalleryToolingError("cannot crop node \(node.id) (\(output.width)×\(output.height) px)") }
        return FigmaReference(
            node: node, frame: frame, renderURL: renderURL, pixelRect: pixelRect,
            renderScale: renderScale, scale: scale, image: image, warnings: warnings
        )
    }

    // MARK: Crop math

    /// Whether `value` is a whole number (within float noise).
    static func isIntegral(_ value: CGFloat) -> Bool { abs(value - value.rounded()) < 0.001 }

    /// `value` with float noise around whole numbers removed (105.99999 → 106).
    static func snapped(_ value: CGFloat) -> CGFloat { isIntegral(value) ? value.rounded() : value }

    /// The scale a frame was exported at. Every render in renders/ is `ceil(renderBounds × 2)`
    /// pixels with pixel (0, 0) at the render-bounds origin, so the scale is exactly 2 even when
    /// the PNG/bounds ratio is 2.0007. `fitsRule` is false (and the measured ratio is returned)
    /// for a PNG that doesn't fit that rule at any quarter-step scale.
    static func exportScale(of frame: FigmaFrame, imageWidth: Int, imageHeight: Int) -> (scale: CGSize, fitsRule: Bool) {
        let bounds = frame.renderBounds
        let measured = CGSize(width: CGFloat(imageWidth) / bounds.width, height: CGFloat(imageHeight) / bounds.height)
        let nominal = (measured.width * 4).rounded() / 4
        func fits(_ length: CGFloat, _ pixels: Int) -> Bool {
            abs(Int((length * nominal - 0.001).rounded(.up)) - pixels) <= 1
        }
        guard nominal > 0, fits(bounds.width, imageWidth), fits(bounds.height, imageHeight) else {
            return (measured, false)
        }
        return (CGSize(width: nominal, height: nominal), true)
    }

    /// `width`×`height` render pixels starting at `origin` (top-left, in pixels), transparent
    /// outside the render. A whole-pixel origin is copied exactly; a fractional one is sampled
    /// bilinearly in premultiplied RGBA, so content starting at `origin` starts at pixel 0.
    static func copyCrop(_ source: CGImage, origin: CGPoint, width: Int, height: Int) -> CGImage? {
        let ix = Int(origin.x.rounded(.down)), iy = Int(origin.y.rounded(.down))
        let wx = Int(((origin.x - CGFloat(ix)) * 256).rounded())
        let wy = Int(((origin.y - CGFloat(iy)) * 256).rounded())
        guard wx > 0 || wy > 0 else {
            let padded = GalleryImageIO.rgba(source, cropping: CGRect(x: ix, y: iy, width: width, height: height))
            return GalleryImageIO.image(fromRGBA: padded, width: width, height: height)
        }
        // One extra column and row to interpolate towards; weights are in 1/256.
        let paddedWidth = width + 1
        let padded = GalleryImageIO.rgba(source, cropping: CGRect(x: ix, y: iy, width: paddedWidth, height: height + 1))
        var out = [UInt8](repeating: 0, count: width * height * 4)
        padded.withUnsafeBufferPointer { inBuffer in
            out.withUnsafeMutableBufferPointer { outBuffer in
                guard let s = inBuffer.baseAddress, let o = outBuffer.baseAddress else { return }
                let w00 = (256 &- wx) &* (256 &- wy), w10 = wx &* (256 &- wy)
                let w01 = (256 &- wx) &* wy, w11 = wx &* wy
                let rowBytes = paddedWidth &* 4
                var y = 0
                while y < height {
                    var si = y &* rowBytes
                    var oi = y &* width &* 4
                    let end = oi &+ width &* 4
                    while oi < end {
                        let sum = Int(s[si]) &* w00 &+ Int(s[si &+ 4]) &* w10
                            &+ Int(s[si &+ rowBytes]) &* w01 &+ Int(s[si &+ rowBytes &+ 4]) &* w11
                        o[oi] = UInt8(truncatingIfNeeded: (sum &+ 32_768) >> 16)
                        si = si &+ 1
                        oi = oi &+ 1
                    }
                    y = y &+ 1
                }
            }
        }
        return GalleryImageIO.image(fromRGBA: out, width: width, height: height)
    }

    /// The render pixels in `rect` (fractional, top-left origin) resampled to `width`×`height`
    /// by area averaging in premultiplied RGBA (each output pixel is the coverage-weighted mean
    /// of the render pixels under it; a 2× → 1× crop is an exact 2×2 average). Transparent
    /// outside the render.
    static func resampledCrop(_ source: CGImage, rect: CGRect, width: Int, height: Int) -> CGImage? {
        let ix = Int(rect.minX.rounded(.down)), iy = Int(rect.minY.rounded(.down))
        let sourceWidth = Int(rect.maxX.rounded(.up)) - ix, sourceHeight = Int(rect.maxY.rounded(.up)) - iy
        guard sourceWidth > 0, sourceHeight > 0, width > 0, height > 0 else { return nil }
        let pixels = GalleryImageIO.rgba(source, cropping: CGRect(x: ix, y: iy, width: sourceWidth, height: sourceHeight))
        let columns = AreaTaps(start: Double(rect.minX) - Double(ix), length: Double(rect.width), count: width, limit: sourceWidth)
        let rows = AreaTaps(start: Double(rect.minY) - Double(iy), length: Double(rect.height), count: height, limit: sourceHeight)
        // Horizontal pass (every source row, output columns), then vertical pass.
        var middle = [Double](repeating: 0, count: sourceHeight * width * 4)
        var out = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeBufferPointer { inBuffer in
        middle.withUnsafeMutableBufferPointer { midBuffer in
        out.withUnsafeMutableBufferPointer { outBuffer in
            guard let s = inBuffer.baseAddress, let m = midBuffer.baseAddress, let o = outBuffer.baseAddress else { return }
            var y = 0
            while y < sourceHeight {
                var u = 0
                while u < width {
                    let target = (y &* width &+ u) &* 4
                    var tap = columns.first[u]
                    let end = tap &+ columns.count[u]
                    while tap < end {
                        let from = (y &* sourceWidth &+ columns.index[tap]) &* 4
                        let weight = columns.weight[tap]
                        m[target] += Double(s[from]) * weight
                        m[target &+ 1] += Double(s[from &+ 1]) * weight
                        m[target &+ 2] += Double(s[from &+ 2]) * weight
                        m[target &+ 3] += Double(s[from &+ 3]) * weight
                        tap = tap &+ 1
                    }
                    u = u &+ 1
                }
                y = y &+ 1
            }
            var v = 0
            while v < height {
                var u = 0
                while u < width {
                    var sums = (0.0, 0.0, 0.0, 0.0)
                    var tap = rows.first[v]
                    let end = tap &+ rows.count[v]
                    while tap < end {
                        let from = (rows.index[tap] &* width &+ u) &* 4
                        let weight = rows.weight[tap]
                        sums.0 += m[from] * weight
                        sums.1 += m[from &+ 1] * weight
                        sums.2 += m[from &+ 2] * weight
                        sums.3 += m[from &+ 3] * weight
                        tap = tap &+ 1
                    }
                    let target = (v &* width &+ u) &* 4
                    func byte(_ value: Double) -> UInt8 { UInt8(min(255, max(0, value.rounded()))) }
                    o[target] = byte(sums.0)
                    o[target &+ 1] = byte(sums.1)
                    o[target &+ 2] = byte(sums.2)
                    o[target &+ 3] = byte(sums.3)
                    u = u &+ 1
                }
                v = v &+ 1
            }
        }}}
        return GalleryImageIO.image(fromRGBA: out, width: width, height: height)
    }

    /// Area-averaging weights along one axis: output pixel `u` covers source
    /// `[start + u·step, start + (u+1)·step)` with `step = length / count`.
    private struct AreaTaps {
        /// Per output pixel: first tap in `index`/`weight`, and the number of taps.
        var first: [Int] = []
        var count: [Int] = []
        /// Source pixel and its share of the output pixel (shares sum to 1 inside the source).
        var index: [Int] = []
        var weight: [Double] = []

        init(start: Double, length: Double, count outputCount: Int, limit: Int) {
            let step = length / Double(outputCount)
            for u in 0..<outputCount {
                let low = start + Double(u) * step, high = low + step
                first.append(index.count)
                var i = Int(low.rounded(.down))
                while Double(i) < high {
                    let coverage = min(high, Double(i + 1)) - max(low, Double(i))
                    if coverage > 1e-9, i >= 0, i < limit {
                        index.append(i)
                        weight.append(coverage / step)
                    }
                    i += 1
                }
                count.append(index.count - first[u])
            }
        }
    }

    // MARK: Parsing figma_file.json

    private static func parse(paths: GalleryPaths) throws -> FigmaIndex {
        let data = try Data(contentsOf: paths.figmaJSON, options: .mappedIfSafe)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let document = root["document"] as? [String: Any]
        else { throw GalleryToolingError("\(paths.figmaJSON.path) is not a Figma file dump") }
        let renderFiles = renderFilesFromIndexMarkdown(paths)
        var frames: [FigmaFrame] = []
        var nodes: [FigmaNode] = []
        var nameCounts: [String: Int] = [:]
        nodes.reserveCapacity(32_000)

        func walk(_ dict: [String: Any], parentID: String?, frameID: String, depth: Int) {
            guard let id = dict["id"] as? String else { return }
            let renderBounds = rect(dict["absoluteRenderBounds"])
            let text = (dict["type"] as? String) == "TEXT" ? String(((dict["characters"] as? String) ?? "").prefix(120)) : ""
            nodes.append(FigmaNode(
                id: id,
                name: dict["name"] as? String ?? "",
                type: dict["type"] as? String ?? "",
                parentID: parentID,
                frameID: frameID,
                depth: depth,
                visible: dict["visible"] as? Bool ?? true,
                boundingBox: rect(dict["absoluteBoundingBox"]) ?? renderBounds ?? .zero,
                renderBounds: renderBounds,
                text: text
            ))
            for child in dict["children"] as? [[String: Any]] ?? [] {
                walk(child, parentID: id, frameID: frameID, depth: depth + 1)
            }
        }

        for canvas in document["children"] as? [[String: Any]] ?? [] {
            for top in canvas["children"] as? [[String: Any]] ?? [] {
                guard let id = top["id"] as? String else { continue }
                let name = top["name"] as? String ?? id
                let box = rect(top["absoluteBoundingBox"]) ?? .zero
                // Fallback naming (same rule INDEX.md uses): duplicates numbered in layer order.
                let seen = nameCounts[name, default: 0]
                nameCounts[name] = seen + 1
                let fallbackFile = seen == 0 ? "\(name).png" : "\(name)-\(seen).png"
                frames.append(FigmaFrame(
                    id: id, name: name, type: top["type"] as? String ?? "",
                    renderFile: renderFiles[id] ?? fallbackFile,
                    boundingBox: box, renderBounds: rect(top["absoluteRenderBounds"]) ?? box
                ))
                walk(top, parentID: nil, frameID: id, depth: 0)
            }
        }
        return FigmaIndex(paths: paths, frames: frames, nodes: nodes)
    }

    private static func rect(_ value: Any?) -> CGRect? {
        guard let dict = value as? [String: Any],
              let x = (dict["x"] as? NSNumber)?.doubleValue, let y = (dict["y"] as? NSNumber)?.doubleValue,
              let width = (dict["width"] as? NSNumber)?.doubleValue, let height = (dict["height"] as? NSNumber)?.doubleValue
        else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Frame id → render file, from the table in redesign/design/figma/INDEX.md.
    private static func renderFilesFromIndexMarkdown(_ paths: GalleryPaths) -> [String: String] {
        guard let markdown = try? String(contentsOf: paths.figmaIndexMarkdown, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: #"^\|\s*\d+\s*\|\s*`([^`]+)`\s*\|.*?\|\s*\[([^\]]+)\]\(renders/"#)
        else { return [:] }
        var result: [String: String] = [:]
        for line in markdown.split(separator: "\n") {
            let text = String(line)
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let idRange = Range(match.range(at: 1), in: text),
                  let fileRange = Range(match.range(at: 2), in: text)
            else { continue }
            result[String(text[idRange])] = String(text[fileRange])
        }
        return result
    }

    // MARK: Cache

    private static let cacheMagic = "mxr-figma-index\t2"

    private static func sourceStamp(_ paths: GalleryPaths) throws -> String {
        func stamp(_ url: URL) -> String {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? -1
            let date = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
            return "\(size)\t\(Int64(date))"
        }
        guard FileManager.default.fileExists(atPath: paths.figmaJSON.path) else {
            throw GalleryToolingError("missing \(paths.figmaJSON.path)")
        }
        return "\(stamp(paths.figmaJSON))\t\(stamp(paths.figmaIndexMarkdown))"
    }

    private func writeCache(_ url: URL, stamp: String) throws {
        func clean(_ string: String) -> String {
            string.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
        }
        func numbers(_ rect: CGRect?) -> String {
            guard let rect else { return "\t\t\t" }
            return "\(rect.minX)\t\(rect.minY)\t\(rect.width)\t\(rect.height)"
        }
        var out = "\(Self.cacheMagic)\t\(stamp)\n"
        for id in frameOrder {
            guard let frame = frames[id] else { continue }
            out += "F\t\(frame.id)\t\(clean(frame.type))\t\(clean(frame.renderFile))\t\(numbers(frame.boundingBox))\t\(numbers(frame.renderBounds))\t\(clean(frame.name))\n"
        }
        for id in order {
            guard let node = nodes[id] else { continue }
            out += "N\t\(node.id)\t\(node.parentID ?? "")\t\(node.frameID)\t\(node.depth)\t\(node.type)\t\(node.visible ? 1 : 0)\t"
            out += "\(numbers(node.boundingBox))\t\(numbers(node.renderBounds))\t\(clean(node.name))\t\(clean(node.text))\n"
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try out.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func readCache(_ url: URL, stamp: String, paths: GalleryPaths) throws -> FigmaIndex? {
        let content = try String(contentsOf: url, encoding: .utf8)
        var lines = content.split(separator: "\n", omittingEmptySubsequences: true).makeIterator()
        guard let header = lines.next(), header == "\(cacheMagic)\t\(stamp)" else { return nil }
        func rect(_ fields: [Substring], _ start: Int) -> CGRect? {
            guard let x = Double(fields[start]), let y = Double(fields[start + 1]),
                  let width = Double(fields[start + 2]), let height = Double(fields[start + 3])
            else { return nil }
            return CGRect(x: x, y: y, width: width, height: height)
        }
        var frames: [FigmaFrame] = []
        var nodes: [FigmaNode] = []
        nodes.reserveCapacity(32_000)
        while let line = lines.next() {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            if fields.first == "F", fields.count == 13 {
                guard let box = rect(fields, 4), let render = rect(fields, 8) else { return nil }
                frames.append(FigmaFrame(
                    id: String(fields[1]), name: String(fields[12]), type: String(fields[2]),
                    renderFile: String(fields[3]), boundingBox: box, renderBounds: render
                ))
            } else if fields.first == "N", fields.count == 17 {
                guard let depth = Int(fields[4]), let box = rect(fields, 7) else { return nil }
                nodes.append(FigmaNode(
                    id: String(fields[1]), name: String(fields[15]), type: String(fields[5]),
                    parentID: fields[2].isEmpty ? nil : String(fields[2]), frameID: String(fields[3]),
                    depth: depth, visible: fields[6] == "1", boundingBox: box, renderBounds: rect(fields, 11),
                    text: String(fields[16])
                ))
            } else {
                return nil
            }
        }
        guard !frames.isEmpty, !nodes.isEmpty else { return nil }
        return FigmaIndex(paths: paths, frames: frames, nodes: nodes)
    }
}

// MARK: - 6. Image comparison

/// What transparent pixels are composited on in the visual outputs (metrics ignore it).
public enum ComparisonBackdrop: String, CaseIterable, Sendable {
    case checker, black, white

    func fill(_ context: CGContext, width: Int, height: Int) {
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        switch self {
        case .black:
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.fill(bounds)
        case .white:
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(bounds)
        case .checker:
            let cell = 8
            context.setFillColor(CGColor(srgbRed: 0.24, green: 0.24, blue: 0.24, alpha: 1))
            context.fill(bounds)
            context.setFillColor(CGColor(srgbRed: 0.31, green: 0.31, blue: 0.31, alpha: 1))
            for row in stride(from: 0, to: height, by: cell) {
                for column in stride(from: 0, to: width, by: cell) where (row / cell + column / cell) % 2 == 0 {
                    context.fill(CGRect(x: column, y: row, width: cell, height: cell))
                }
            }
        }
    }
}

/// Result of comparing a render (a) with a reference (b), aligned at their top-left corners.
///
/// All metrics use premultiplied sRGB RGBA, so a transparent pixel differs from an opaque one;
/// a pixel's delta is its largest channel difference (0–255). Three kinds of difference:
/// - **strict**: delta > `threshold`. Includes antialiasing and sub-pixel text differences.
/// - **structural**: still differs when the pixel may match anything within `toleranceRadius`
///   pixels (½ pt) in the other image. Missing, extra, moved (≥ 1 pt) or reshaped content.
/// - **flat color**: both images are locally solid there but the colors differ by more than
///   `ImageComparator.flatColorThreshold` (so by 2/255 or more): wrong token colors on surfaces.
///   Neighbouring dark surface tokens are only 2–5/255 apart.
/// The verdict uses the structural and flat-color differences, so text antialiasing doesn't fail it.
public struct ImageComparison: Sendable {
    public enum Verdict: String, Sendable {
        /// No visible difference.
        case pass = "PASS"
        /// Something small differs: look at the boxed regions in diff-heatmap.png.
        case review = "REVIEW"
        /// Wrong size, wrong colors or clearly misplaced/missing content.
        case fail = "FAIL"
    }

    /// Integer pixel offset of a.
    public struct Shift: Sendable, Equatable {
        public let dx: Int
        public let dy: Int
        /// Fraction of (sampled) pixels still strictly different after moving a by (dx, dy).
        public let remainingFraction: Double
        /// Fraction of (sampled) pixels strictly different without moving.
        public let originalFraction: Double
    }

    /// The most common pair of colors among a region's flat-color pixels.
    public struct ColorPair: Sendable, Equatable {
        /// Render (a) color as unpremultiplied sRGB `0xRRGGBBAA`.
        public let a: UInt32
        /// Reference (b) color as unpremultiplied sRGB `0xRRGGBBAA`.
        public let b: UInt32
        /// Largest channel difference of the pair (premultiplied, 0–255).
        public let delta: Int
        /// Fraction of the region's (sampled) flat-color pixels with exactly this pair.
        public let share: Double

        /// "render #1F1F1F (dark bgA2) vs Figma #1B1B1B (dark bgA3), Δ 4".
        public var summary: String {
            "render \(GalleryColorNames.describe(a)) vs Figma \(GalleryColorNames.describe(b)), Δ \(delta)"
        }
    }

    /// A connected area of differences.
    public struct Region: Sendable {
        /// Pixels, top-left origin, in a's coordinates.
        public let rect: CGRect
        /// Differing pixels in the region: structural and flat-color ones in `regions`,
        /// strict (Δ > threshold) ones in `largestStrictRegion`.
        public let differingPixels: Int
        /// Move a's content in this region by this much to match b better (if clearly better).
        public let suggestedShift: Shift?
        /// The dominant render/reference colors of the region's flat-color pixels, if it has any.
        public let flatColors: ColorPair?
        /// `differingPixels` ÷ rect area: near 1 is a solid difference, low is outlines.
        public var fill: Double { Double(differingPixels) / max(1, Double(rect.width * rect.height)) }
    }

    public let sizeA: CGSize
    public let sizeB: CGSize
    public var sizeMatches: Bool { sizeA == sizeB }
    /// Pixels per point the images were made at (regions are also reported in points).
    public let scale: CGFloat
    public let threshold: Int
    /// Neighborhood (pixels) a pixel may match within for the structural test.
    public let toleranceRadius: Int
    /// Mean absolute channel difference over the canvas, 0–255.
    public let meanAbsoluteDifference: Double
    public let totalPixels: Int
    /// Strictly different pixels (delta > threshold).
    public let differingPixels: Int
    public let structuralPixels: Int
    public let flatColorPixels: Int
    /// Global offset of a that would match b better, when there is a clear one.
    public let bestShift: Shift?
    /// Connected areas of structural and flat-color differences, largest first (at most 5).
    /// These drive the verdict.
    public let regions: [Region]
    /// Bounding box of the largest connected area of strict (Δ > threshold) differences,
    /// antialiasing included. Informational: it doesn't affect the verdict.
    public let largestStrictRegion: Region?
    public let verdict: Verdict
    /// Why the verdict was given.
    public let reason: String

    public var differingFraction: Double { Double(differingPixels) / max(1, Double(totalPixels)) }
    public var structuralFraction: Double { Double(structuralPixels) / max(1, Double(totalPixels)) }
    public var flatColorFraction: Double { Double(flatColorPixels) / max(1, Double(totalPixels)) }
    public var largestRegion: Region? { regions.first }

    /// `(dx, dy)` pixels as points, e.g. "+1, 0 pt".
    public func points(of shift: Shift) -> String {
        func value(_ pixels: Int) -> String {
            let points = CGFloat(pixels) / scale
            let text = points == points.rounded() ? String(Int(points)) : String(format: "%.1f", points)
            return pixels > 0 ? "+" + text : text
        }
        return "\(value(shift.dx)), \(value(shift.dy)) pt"
    }

    /// Multi-line report for the terminal.
    public func report() -> String {
        func px(_ size: CGSize) -> String { "\(Int(size.width))×\(Int(size.height))" }
        func percent(_ fraction: Double, _ count: Int) -> String { String(format: "%.3f %% (%d px)", fraction * 100, count) }
        func describe(_ region: Region) -> String {
            let r = region.rect
            var text = String(
                format: "x %d y %d  %d×%d px (= %.1f, %.1f  %.1f×%.1f pt)  %d px, fill %.0f%%",
                Int(r.minX), Int(r.minY), Int(r.width), Int(r.height),
                r.minX / scale, r.minY / scale, r.width / scale, r.height / scale,
                region.differingPixels, region.fill * 100
            )
            if let shift = region.suggestedShift { text += "; matches if moved \(points(of: shift))" }
            if let colors = region.flatColors {
                text += "\n               colors \(colors.summary)"
                if colors.share < 0.9 { text += String(format: " (%.0f %% of its flat-color pixels)", colors.share * 100) }
            }
            return text
        }
        let strictLabel = "Δ > \(threshold)".padding(toLength: 12, withPad: " ", startingAt: 0)
        var lines = [
            "size        a \(px(sizeA)) px · b \(px(sizeB)) px · \(sizeMatches ? "match" : "MISMATCH")",
            String(format: "mean |Δ|    %.2f / 255", meanAbsoluteDifference),
            "\(strictLabel)\(percent(differingFraction, differingPixels))  strict, includes antialiasing (informational)",
            "structural  \(percent(structuralFraction, structuralPixels))  differs even with \(toleranceRadius) px tolerance",
            "flat color  \(percent(flatColorFraction, flatColorPixels))  solid areas whose color differs by ≥ \(ImageComparator.flatColorThreshold + 1)/255",
        ]
        if let strict = largestStrictRegion {
            lines.append("Δ area      largest connected strict difference: " + describe(strict))
        }
        if let bestShift {
            lines.append(String(
                format: "offset      a matches better moved %@: strict Δ falls from %.2f %% to %.2f %%",
                points(of: bestShift), bestShift.originalFraction * 100, bestShift.remainingFraction * 100
            ))
        }
        if regions.isEmpty {
            lines.append("regions     none")
        } else {
            for (index, region) in regions.enumerated() {
                lines.append((index == 0 ? "regions     " : "            ") + "\(index + 1)) " + describe(region))
            }
        }
        lines.append("verdict     \(verdict.rawValue): \(reason)")
        return lines.joined(separator: "\n")
    }
}

/// Visual outputs of a comparison.
public struct ComparisonImages: Sendable {
    /// a (left) and b (right) on the backdrop.
    public let sideBySide: CGImage
    /// b at 50 % over a.
    public let overlay: CGImage
    /// a dimmed to gray. Blue: small deltas; yellow: strict-only (antialiasing); red: structural;
    /// magenta: flat-color differences. Boxes: regions (the first is thicker).
    public let heatmap: CGImage

    /// Writes side-by-side.png, overlay-50.png and diff-heatmap.png into `directory`.
    @discardableResult
    public func write(to directory: URL) throws -> [URL] {
        let files = [("side-by-side.png", sideBySide), ("overlay-50.png", overlay), ("diff-heatmap.png", heatmap)]
        return try files.map { name, image in
            let url = directory.appending(path: name)
            try GalleryImageIO.writePNG(image, to: url)
            return url
        }
    }
}

/// Color formatting for comparison reports, with the design tokens a color matches.
public enum GalleryColorNames {
    /// "#1F1F1F (dark bgA2)", "#191919@95% (dark bgA3Transparent)" or "transparent" for an
    /// unpremultiplied sRGB `0xRRGGBBAA`. Tokens are matched exactly, with the default accent.
    public static func describe(_ rgba: UInt32) -> String {
        let alpha = rgba & 0xFF
        guard alpha > 0 else { return "transparent" }
        var text = String(format: "#%06X", rgba >> 8)
        if alpha < 255 { text += String(format: "@%.0f%%", Double(alpha) / 255 * 100) }
        if let names = tokenNames[rgba] { text += " (\(names))" }
        return text
    }

    /// Token names by `0xRRGGBBAA`, e.g. "dark bgA2"; tokens sharing a value are joined with " / ".
    private static let tokenNames: [UInt32: String] = {
        var names: [UInt32: [String]] = [:]
        for (scheme, label) in [(ColorScheme.dark, "dark"), (ColorScheme.light, "light")] {
            for token in Theme.ColorToken.allCases {
                let value = ThemeColor(token).value(scheme: scheme)
                func byte(_ component: Double) -> UInt32 { UInt32((min(max(component, 0), 1) * 255).rounded()) }
                let key = byte(value.red) << 24 | byte(value.green) << 16 | byte(value.blue) << 8 | byte(value.alpha)
                names[key, default: []].append("\(label) \(token)")
            }
        }
        return names.mapValues { $0.joined(separator: " / ") }
    }()
}

/// Compares renders with Figma references. The thresholds are documented in WORKFLOW.md.
public enum ImageComparator {
    /// Channel delta above which a pixel differs (24/255 ≈ 9 %).
    public static let defaultThreshold = 24
    /// Channel delta above which a flat (solid) area has a different color: 2/255 or more.
    /// Neighbouring dark surface tokens are 2–5/255 apart (`bgA3` #1B1B1B, `bgA4` #191919,
    /// `bgA5` #151515), while Figma renders and SwiftUI agree exactly on solid token colors
    /// (Figma's own noise is ±1, e.g. alpha 254 instead of 255).
    public static let flatColorThreshold = 1
    /// FAIL above this fraction of structural pixels.
    public static let failStructuralFraction = 0.02
    /// FAIL above this fraction of flat-color pixels.
    public static let failFlatColorFraction = 0.01
    /// FAIL when one region has at least this many differing points² (20×20 pt).
    public static let failRegionArea = 400.0
    /// REVIEW above this fraction of structural pixels.
    public static let reviewStructuralFraction = 0.005
    /// REVIEW above this fraction of flat-color pixels.
    public static let reviewFlatColorFraction = 0.001
    /// REVIEW when one region has at least this many differing points² (4×4 pt).
    public static let reviewRegionArea = 16.0

    // Pixel classes stored in the class map (see `ComparisonImages.heatmap`).
    private static let classSame: UInt8 = 0
    private static let classSmall: UInt8 = 1
    private static let classAntialias: UInt8 = 2
    private static let classStructural: UInt8 = 3
    private static let classFlatColor: UInt8 = 4

    /// Counts produced by `classify`.
    private struct Counts {
        var sum = 0
        var differing = 0
        var structural = 0
        var flatColor = 0
    }

    /// Compares `a` (render) with `b` (reference). `scale` is pixels per point of both images.
    public static func compare(
        _ a: CGImage,
        _ b: CGImage,
        scale: CGFloat = 2,
        threshold: Int = defaultThreshold,
        backdrop: ComparisonBackdrop = .checker,
        makeImages: Bool = true
    ) -> (ImageComparison, ComparisonImages?) {
        let width = max(a.width, b.width)
        let height = max(a.height, b.height)
        let total = width * height
        let pixelA = GalleryImageIO.rgba(a, width: width, height: height)
        let pixelB = GalleryImageIO.rgba(b, width: width, height: height)
        let radius = max(1, Int((scale / 2).rounded()))
        let envelopeA = envelope(pixelA, width: width, height: height, kernel: 2 * radius + 1)
        let envelopeB = envelope(pixelB, width: width, height: height, kernel: 2 * radius + 1)

        let cellSize = max(2, Int((2 * scale).rounded()))
        let columns = (width + cellSize - 1) / cellSize
        let rows = (height + cellSize - 1) / cellSize
        var classes = [UInt8](repeating: 0, count: total)
        var deltas = [UInt8](repeating: 0, count: total)
        var cellCounts = [Int32](repeating: 0, count: columns * rows)
        var strictCellCounts = [Int32](repeating: 0, count: columns * rows)
        var counts = Counts()
        let t = threshold
        pixelA.withUnsafeBufferPointer { pa in
        pixelB.withUnsafeBufferPointer { pb in
        envelopeA.min.withUnsafeBufferPointer { minA in
        envelopeA.max.withUnsafeBufferPointer { maxA in
        envelopeB.min.withUnsafeBufferPointer { minB in
        envelopeB.max.withUnsafeBufferPointer { maxB in
        classes.withUnsafeMutableBufferPointer { cls in
        deltas.withUnsafeMutableBufferPointer { delta in
        cellCounts.withUnsafeMutableBufferPointer { cells in
        strictCellCounts.withUnsafeMutableBufferPointer { strictCells in
            guard let a = pa.baseAddress, let b = pb.baseAddress, let minA = minA.baseAddress, let maxA = maxA.baseAddress,
                  let minB = minB.baseAddress, let maxB = maxB.baseAddress, let cls = cls.baseAddress,
                  let delta = delta.baseAddress, let cells = cells.baseAddress, let strictCells = strictCells.baseAddress
            else { return }
            counts = classify(
                a: a, b: b, minA: minA, maxA: maxA, minB: minB, maxB: maxB, classes: cls, deltas: delta, cells: cells,
                strictCells: strictCells, width: width, height: height, cellSize: cellSize, columns: columns, threshold: t
            )
        }}}}}}}}}}

        let mean = Double(counts.sum) / Double(max(1, total * 4))
        let pointArea = Double(scale * scale)
        let shiftRange = max(1, Int((2 * scale).rounded()))
        let found = findRegions(cellCounts, columns: columns, rows: rows, cellSize: cellSize, width: width, height: height)
        let regions: [ImageComparison.Region] = found.prefix(5).enumerated().map { index, region in
            let shift = index < 3 && Double(region.count) >= reviewRegionArea * pointArea
                ? bestShift(pixelA, pixelB, width: width, height: height, in: region.rect, range: shiftRange, threshold: t, maxSamples: 20_000)
                : nil
            let colors = dominantFlatColors(pixelA, pixelB, classes: classes, width: width, in: region.rect, maxSamples: 20_000)
            return .init(rect: region.rect, differingPixels: region.count, suggestedShift: shift, flatColors: colors)
        }
        let largestStrict = findRegions(
            strictCellCounts, columns: columns, rows: rows, cellSize: cellSize, width: width, height: height
        ).first.map { ImageComparison.Region(rect: $0.rect, differingPixels: $0.count, suggestedShift: nil, flatColors: nil) }
        let globalShift = counts.differing > 0
            ? bestShift(pixelA, pixelB, width: width, height: height,
                        in: CGRect(x: 0, y: 0, width: width, height: height), range: shiftRange, threshold: t, maxSamples: 60_000)
            : nil
        let sizeA = CGSize(width: a.width, height: a.height)
        let sizeB = CGSize(width: b.width, height: b.height)
        func comparison(verdict: ImageComparison.Verdict, reason: String) -> ImageComparison {
            ImageComparison(
                sizeA: sizeA, sizeB: sizeB, scale: scale, threshold: t, toleranceRadius: radius,
                meanAbsoluteDifference: mean, totalPixels: total, differingPixels: counts.differing,
                structuralPixels: counts.structural, flatColorPixels: counts.flatColor, bestShift: globalShift,
                regions: regions, largestStrictRegion: largestStrict, verdict: verdict, reason: reason
            )
        }
        let (verdict, reason) = judge(comparison(verdict: .pass, reason: ""))
        let result = comparison(verdict: verdict, reason: reason)
        guard makeImages else { return (result, nil) }
        let images = makeVisuals(
            a: a, b: b, width: width, height: height, classes: classes, deltas: deltas,
            regions: regions, backdrop: backdrop, threshold: t
        )
        return (result, images)
    }

    // The per-pixel loops below are written with raw pointers, `while` loops and wrapping
    // arithmetic: SwiftPM builds the tools in debug, where generic `abs`/`max` and range
    // iterators make a 4K comparison take ~20× longer.

    /// Classifies every pixel (see `ImageComparison`), fills `deltas`, `classes` and the cell grid.
    private static func classify(
        a: UnsafePointer<UInt8>, b: UnsafePointer<UInt8>,
        minA: UnsafePointer<UInt8>, maxA: UnsafePointer<UInt8>, minB: UnsafePointer<UInt8>, maxB: UnsafePointer<UInt8>,
        classes: UnsafeMutablePointer<UInt8>, deltas: UnsafeMutablePointer<UInt8>, cells: UnsafeMutablePointer<Int32>,
        strictCells: UnsafeMutablePointer<Int32>, width: Int, height: Int, cellSize: Int, columns: Int, threshold t: Int
    ) -> Counts {
        // Deltas of 1 are rasterization noise (Figma's alpha is sometimes 254); everything above
        // is at least a "small" difference, and a flat-color one where both images are solid.
        let noise = 1
        let flatThreshold = flatColorThreshold
        var sum = 0, differing = 0, structural = 0, flatColor = 0
        var y = 0
        while y < height {
            let cellRow = (y / cellSize) &* columns
            var index = y &* width
            var x = 0
            while x < width {
                let o = index &* 4
                var d = 0
                var c = 0
                while c < 4 {
                    var diff = Int(a[o &+ c]) &- Int(b[o &+ c])
                    if diff < 0 { diff = 0 &- diff }
                    sum = sum &+ diff
                    if diff > d { d = diff }
                    c = c &+ 1
                }
                deltas[index] = UInt8(truncatingIfNeeded: d)
                if d > noise {
                    var kind = classSmall
                    if d > flatThreshold {
                        var flat = true
                        c = 0
                        while c < 4 {
                            let k = o &+ c
                            if Int(maxA[k]) &- Int(minA[k]) > 2 { flat = false; break }
                            if Int(maxB[k]) &- Int(minB[k]) > 2 { flat = false; break }
                            c = c &+ 1
                        }
                        if flat { kind = classFlatColor }
                    }
                    if d > t {
                        differing = differing &+ 1
                        strictCells[cellRow &+ x / cellSize] = strictCells[cellRow &+ x / cellSize] &+ 1
                        if kind != classFlatColor {
                            kind = classAntialias
                            c = 0
                            while c < 4 {
                                let k = o &+ c
                                let va = Int(a[k]), vb = Int(b[k])
                                if va < Int(minB[k]) &- t { kind = classStructural; break }
                                if va > Int(maxB[k]) &+ t { kind = classStructural; break }
                                if vb < Int(minA[k]) &- t { kind = classStructural; break }
                                if vb > Int(maxA[k]) &+ t { kind = classStructural; break }
                                c = c &+ 1
                            }
                        }
                    }
                    if kind == classStructural {
                        structural = structural &+ 1
                        cells[cellRow &+ x / cellSize] = cells[cellRow &+ x / cellSize] &+ 1
                    } else if kind == classFlatColor {
                        flatColor = flatColor &+ 1
                        cells[cellRow &+ x / cellSize] = cells[cellRow &+ x / cellSize] &+ 1
                    }
                    classes[index] = kind
                }
                x = x &+ 1
                index = index &+ 1
            }
            y = y &+ 1
        }
        return Counts(sum: sum, differing: differing, structural: structural, flatColor: flatColor)
    }

    private static func judge(_ c: ImageComparison) -> (ImageComparison.Verdict, String) {
        let pointArea = Double(c.scale * c.scale)
        func at(_ region: ImageComparison.Region) -> String {
            let r = region.rect
            var text = String(format: "%.0f,%.0f %.0f×%.0f pt", r.minX / c.scale, r.minY / c.scale, r.width / c.scale, r.height / c.scale)
            if let shift = region.suggestedShift { text += " (matches if moved \(c.points(of: shift)))" }
            if let colors = region.flatColors { text += " (\(colors.summary))" }
            return text
        }
        var hint = ""
        if let shift = c.bestShift { hint = "; everything matches better moved \(c.points(of: shift))" }
        if !c.sizeMatches {
            return (.fail, "sizes differ (\(Int(c.sizeA.width))×\(Int(c.sizeA.height)) vs \(Int(c.sizeB.width))×\(Int(c.sizeB.height)) px): fix the entry size or the layout first")
        }
        if c.flatColorFraction > failFlatColorFraction {
            let colors = c.regions.lazy.compactMap(\.flatColors).first
            let what = colors.map { ": \($0.summary)" } ?? " (wrong color token or opacity, or a filled shape missing/extra)"
            return (.fail, String(format: "%.2f %% of pixels are solid areas with a different color", c.flatColorFraction * 100) + what + hint)
        }
        if c.structuralFraction > failStructuralFraction {
            return (.fail, String(format: "%.2f %% of pixels differ structurally (layout, shape, font or content)", c.structuralFraction * 100) + hint)
        }
        if let big = c.regions.first(where: { Double($0.differingPixels) >= failRegionArea * pointArea }) {
            return (.fail, "large difference at \(at(big))" + hint)
        }
        if c.structuralFraction > reviewStructuralFraction || c.flatColorFraction > reviewFlatColorFraction {
            return (.review, "small differences: inspect the boxed regions in diff-heatmap.png" + hint)
        }
        if let region = c.regions.first(where: { Double($0.differingPixels) >= reviewRegionArea * pointArea }) {
            return (.review, "local difference at \(at(region))" + hint)
        }
        return (.pass, "no visible difference" + (c.differingPixels > 0 ? " (remaining deltas are antialiasing)" : ""))
    }

    /// The most common render/reference color pair among the flat-color pixels in `rect`
    /// (sampled on a grid of at most about `maxSamples` pixels), or `nil` if it has none.
    private static func dominantFlatColors(
        _ a: [UInt8], _ b: [UInt8], classes: [UInt8], width: Int, in rect: CGRect, maxSamples: Int
    ) -> ImageComparison.ColorPair? {
        let x0 = Int(rect.minX), x1 = Int(rect.maxX), y0 = Int(rect.minY), y1 = Int(rect.maxY)
        let area = max(1, (x1 - x0) * (y1 - y0))
        let step = max(1, Int(Double(area / maxSamples).squareRoot().rounded(.up)))
        var histogram: [UInt64: Int] = [:]
        var sampled = 0
        a.withUnsafeBufferPointer { pa in
        b.withUnsafeBufferPointer { pb in
        classes.withUnsafeBufferPointer { cls in
            guard let pa = pa.baseAddress, let pb = pb.baseAddress, let cls = cls.baseAddress else { return }
            func key(_ p: UnsafePointer<UInt8>, _ o: Int) -> UInt64 {
                UInt64(p[o]) << 24 | UInt64(p[o &+ 1]) << 16 | UInt64(p[o &+ 2]) << 8 | UInt64(p[o &+ 3])
            }
            var y = y0
            while y < y1 {
                var x = x0
                while x < x1 {
                    let index = y &* width &+ x
                    if cls[index] == classFlatColor {
                        let o = index &* 4
                        histogram[key(pa, o) << 32 | key(pb, o), default: 0] += 1
                        sampled += 1
                    }
                    x = x &+ step
                }
                y = y &+ step
            }
        }}}
        guard sampled > 0, let top = histogram.max(by: { $0.value < $1.value }) else { return nil }
        let premultipliedA = UInt32(truncatingIfNeeded: top.key >> 32)
        let premultipliedB = UInt32(truncatingIfNeeded: top.key)
        var delta = 0
        for shift in stride(from: 0, through: 24, by: 8) {
            let channelA = Int((premultipliedA >> UInt32(shift)) & 0xFF), channelB = Int((premultipliedB >> UInt32(shift)) & 0xFF)
            delta = max(delta, abs(channelA - channelB))
        }
        return .init(
            a: unpremultiplied(premultipliedA), b: unpremultiplied(premultipliedB),
            delta: delta, share: Double(top.value) / Double(sampled)
        )
    }

    /// `0xRRGGBBAA` premultiplied → unpremultiplied.
    private static func unpremultiplied(_ rgba: UInt32) -> UInt32 {
        let alpha = rgba & 0xFF
        guard alpha > 0, alpha < 255 else { return alpha == 0 ? 0 : rgba }
        var result = alpha
        for shift in [24, 16, 8] as [UInt32] {
            let channel = (rgba >> shift) & 0xFF
            result |= min(255, (channel * 255 + alpha / 2) / alpha) << shift
        }
        return result
    }

    /// Per-channel minimum and maximum over a `kernel`×`kernel` neighborhood.
    private static func envelope(_ pixels: [UInt8], width: Int, height: Int, kernel: Int) -> (min: [UInt8], max: [UInt8]) {
        var source = pixels
        var minimum = [UInt8](repeating: 0, count: pixels.count)
        var maximum = [UInt8](repeating: 0, count: pixels.count)
        source.withUnsafeMutableBytes { src in
            minimum.withUnsafeMutableBytes { low in
                maximum.withUnsafeMutableBytes { high in
                    func buffer(_ raw: UnsafeMutableRawBufferPointer) -> vImage_Buffer {
                        vImage_Buffer(data: raw.baseAddress, height: vImagePixelCount(height),
                                      width: vImagePixelCount(width), rowBytes: width * 4)
                    }
                    var input = buffer(src)
                    var lowBuffer = buffer(low)
                    var highBuffer = buffer(high)
                    let size = vImagePixelCount(kernel)
                    vImageMin_ARGB8888(&input, &lowBuffer, nil, 0, 0, size, size, vImage_Flags(kvImageNoFlags))
                    vImageMax_ARGB8888(&input, &highBuffer, nil, 0, 0, size, size, vImage_Flags(kvImageNoFlags))
                }
            }
        }
        return (minimum, maximum)
    }

    /// The integer offset of a within ±`range` px that minimizes strict differences inside `rect`
    /// (sampled; samples whose source falls outside a are ignored), if it at least halves them.
    private static func bestShift(
        _ a: [UInt8], _ b: [UInt8], width: Int, height: Int, in rect: CGRect, range: Int, threshold: Int, maxSamples: Int
    ) -> ImageComparison.Shift? {
        let x0 = max(0, Int(rect.minX) - range), x1 = min(width, Int(rect.maxX) + range)
        let y0 = max(0, Int(rect.minY) - range), y1 = min(height, Int(rect.maxY) + range)
        let area = (x1 - x0) * (y1 - y0)
        guard area > 0 else { return nil }
        let step = max(1, Int(Double(area / maxSamples).squareRoot().rounded(.up)))
        let side = 2 * range + 1
        var differing = [Int](repeating: 0, count: side * side)
        var valid = [Int](repeating: 0, count: side * side)
        a.withUnsafeBufferPointer { pa in
        b.withUnsafeBufferPointer { pb in
        differing.withUnsafeMutableBufferPointer { diffs in
        valid.withUnsafeMutableBufferPointer { valids in
            guard let pa = pa.baseAddress, let pb = pb.baseAddress,
                  let diffs = diffs.baseAddress, let valids = valids.baseAddress else { return }
            var y = y0
            while y < y1 {
                var x = x0
                while x < x1 {
                    let ob = (y &* width &+ x) &* 4
                    var slot = 0
                    var dy = -range
                    while dy <= range {
                        // a moved by (dx, dy): the pixel landing on (x, y) comes from (x - dx, y - dy).
                        let sy = y &- dy
                        var dx = -range
                        while dx <= range {
                            let sx = x &- dx
                            if sx >= 0 && sy >= 0 && sx < width && sy < height {
                                let oa = (sy &* width &+ sx) &* 4
                                var d = 0
                                var c = 0
                                while c < 4 {
                                    var diff = Int(pa[oa &+ c]) &- Int(pb[ob &+ c])
                                    if diff < 0 { diff = 0 &- diff }
                                    if diff > d { d = diff }
                                    c = c &+ 1
                                }
                                valids[slot] = valids[slot] &+ 1
                                if d > threshold { diffs[slot] = diffs[slot] &+ 1 }
                            }
                            slot = slot &+ 1
                            dx = dx &+ 1
                        }
                        dy = dy &+ 1
                    }
                    x = x &+ step
                }
                y = y &+ step
            }
        }}}}
        func fraction(_ slot: Int) -> Double { Double(differing[slot]) / Double(max(1, valid[slot])) }
        let center = range * side + range
        let original = fraction(center)
        guard original > 0,
              let best = differing.indices.filter({ valid[$0] * 2 >= valid[center] }).min(by: { fraction($0) < fraction($1) })
        else { return nil }
        let dx = best % side - range, dy = best / side - range
        guard dx != 0 || dy != 0, fraction(best) * 2 <= original else { return nil }
        return .init(dx: dx, dy: dy, remainingFraction: fraction(best), originalFraction: original)
    }

    /// 8-connected components of non-empty cells, largest (by differing pixels) first.
    private static func findRegions(
        _ cells: [Int32], columns: Int, rows: Int, cellSize: Int, width: Int, height: Int
    ) -> [(rect: CGRect, count: Int)] {
        var visited = [Bool](repeating: false, count: cells.count)
        var regions: [(rect: CGRect, count: Int)] = []
        var stack: [Int] = []
        for start in 0..<cells.count where cells[start] > 0 && !visited[start] {
            visited[start] = true
            stack.append(start)
            var count = 0
            var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
            while let cell = stack.popLast() {
                count += Int(cells[cell])
                let cx = cell % columns
                let cy = cell / columns
                minX = min(minX, cx); maxX = max(maxX, cx); minY = min(minY, cy); maxY = max(maxY, cy)
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = cx + dx, ny = cy + dy
                        guard nx >= 0, ny >= 0, nx < columns, ny < rows else { continue }
                        let neighbor = ny * columns + nx
                        if cells[neighbor] > 0 && !visited[neighbor] {
                            visited[neighbor] = true
                            stack.append(neighbor)
                        }
                    }
                }
            }
            let x0 = minX * cellSize, y0 = minY * cellSize
            let x1 = min(width, (maxX + 1) * cellSize), y1 = min(height, (maxY + 1) * cellSize)
            regions.append((CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0), count))
        }
        return regions.sorted { $0.count > $1.count }
    }

    private static func makeVisuals(
        a: CGImage, b: CGImage, width: Int, height: Int, classes: [UInt8], deltas: [UInt8],
        regions: [ImageComparison.Region], backdrop: ComparisonBackdrop, threshold: Int
    ) -> ComparisonImages? {
        let onBackdropA = GalleryImageIO.rgba(a, width: width, height: height, backdrop: backdrop)
        let onBackdropB = GalleryImageIO.rgba(b, width: width, height: height, backdrop: backdrop)
        guard let imageA = GalleryImageIO.image(fromRGBA: onBackdropA, width: width, height: height),
              let imageB = GalleryImageIO.image(fromRGBA: onBackdropB, width: width, height: height)
        else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)

        // Side by side, with a gap.
        let gap = 16
        guard let pair = GalleryImageIO.makeContext(width: width * 2 + gap, height: height) else { return nil }
        pair.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        pair.fill(CGRect(x: 0, y: 0, width: width * 2 + gap, height: height))
        pair.draw(imageA, in: bounds)
        pair.draw(imageB, in: bounds.offsetBy(dx: CGFloat(width + gap), dy: 0))

        // 50 % overlay.
        guard let overlay = GalleryImageIO.makeContext(width: width, height: height) else { return nil }
        overlay.draw(imageA, in: bounds)
        overlay.setAlpha(0.5)
        overlay.draw(imageB, in: bounds)

        // Heat map over a dimmed grayscale copy of a.
        var heat = [UInt8](repeating: 255, count: width * height * 4)
        onBackdropA.withUnsafeBufferPointer { base in
        classes.withUnsafeBufferPointer { cls in
        deltas.withUnsafeBufferPointer { delta in
        heat.withUnsafeMutableBufferPointer { out in
            guard let base = base.baseAddress, let cls = cls.baseAddress,
                  let delta = delta.baseAddress, let out = out.baseAddress else { return }
            let count = width &* height
            let scaleT = 1 / Double(max(1, threshold))
            var index = 0
            while index < count {
                let o = index &* 4
                let gray = (Int(base[o]) &* 3 &+ Int(base[o &+ 1]) &* 6 &+ Int(base[o &+ 2])) / 10 &* 3 / 10
                var r = gray, g = gray, bl = gray
                let kind = cls[index]
                if kind == classSmall {
                    let t = Double(delta[index]) * scaleT
                    let dim = Double(gray) * (1 - t * 0.6)
                    r = Int(dim)
                    g = Int(dim + 90 * t)
                    bl = Int(dim + 200 * t)
                } else if kind == classAntialias {
                    r = 200; g = 170; bl = 0
                } else if kind == classStructural {
                    r = 255; g = 40; bl = 20
                } else if kind == classFlatColor {
                    r = 255; g = 0; bl = 220
                }
                out[o] = UInt8(truncatingIfNeeded: r > 255 ? 255 : r)
                out[o &+ 1] = UInt8(truncatingIfNeeded: g > 255 ? 255 : g)
                out[o &+ 2] = UInt8(truncatingIfNeeded: bl > 255 ? 255 : bl)
                index = index &+ 1
            }
        }}}}
        guard let heatImage = GalleryImageIO.image(fromRGBA: heat, width: width, height: height),
              let heatContext = GalleryImageIO.makeContext(width: width, height: height)
        else { return nil }
        heatContext.draw(heatImage, in: bounds)
        heatContext.setStrokeColor(CGColor(srgbRed: 0, green: 1, blue: 1, alpha: 1))
        for (index, region) in regions.enumerated() {
            let r = region.rect
            heatContext.setLineWidth(index == 0 ? 2 : 1)
            heatContext.stroke(CGRect(x: r.minX, y: CGFloat(height) - r.maxY, width: r.width, height: r.height).insetBy(dx: -2, dy: -2))
        }
        guard let sideBySide = pair.makeImage(), let overlayImage = overlay.makeImage(), let heatmap = heatContext.makeImage()
        else { return nil }
        return ComparisonImages(sideBySide: sideBySide, overlay: overlayImage, heatmap: heatmap)
    }
}
