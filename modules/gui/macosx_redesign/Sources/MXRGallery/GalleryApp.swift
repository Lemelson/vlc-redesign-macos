import AppKit
import MXRGalleryCatalog
import SwiftUI

/// The Gallery: every component and screen with mock data, next to its Figma render.
///
/// Run with `swift run MXRGallery` from modules/gui/macosx_redesign. Optional arguments:
/// `--entry <id>` selects an entry, `--mode render|side|overlay|difference|figma|heatmap`
/// picks the comparison mode, `--measure` measures the selected entry against Figma at launch,
/// `--font-smoothing` keeps macOS text rasterization (by default
/// the Gallery draws text like Figma, see `GalleryRenderer.matchFigmaTextRasterization()`).
@main
struct GalleryApp: App {
    @NSApplicationDelegateAdaptor(GalleryAppDelegate.self) private var appDelegate
    @State private var model: GalleryModel

    init() {
        if !CommandLine.arguments.contains("--font-smoothing") {
            GalleryRenderer.matchFigmaTextRasterization()
        }
        GalleryCatalog.bootstrap()
        _model = State(initialValue: GalleryModel(arguments: CommandLine.arguments))
    }

    var body: some Scene {
        WindowGroup("MXR Gallery") {
            GalleryWindow(model: model)
        }
        .defaultSize(width: GalleryChrome.defaultWindowSize.width, height: GalleryChrome.defaultWindowSize.height)
        .commands { GalleryCommands(model: model) }
    }
}

/// Makes the SwiftPM executable behave like a regular app (Dock icon, key window).
///
/// `--snapshot-window <file.png>` draws the window into a PNG after it settles and quits, so
/// the Gallery itself can be checked without screen-recording permission.
@MainActor
final class GalleryAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot-window"), index + 1 < arguments.count {
            let url = URL(fileURLWithPath: arguments[index + 1])
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                Self.snapshotKeyWindow(to: url)
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private static func snapshotKeyWindow(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds)
        else {
            FileHandle.standardError.write(Data("snapshot-window: no window to capture\n".utf8))
            return
        }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        guard let image = rep.cgImage else { return }
        do {
            try GalleryImageIO.writePNG(image, to: url)
            print("snapshot-window: \(url.path)")
        } catch {
            FileHandle.standardError.write(Data("snapshot-window: \(error.localizedDescription)\n".utf8))
        }
    }
}

/// Menu commands: comparison modes, zoom, color scheme and entry navigation.
struct GalleryCommands: Commands {
    let model: GalleryModel

    var body: some Commands {
        CommandMenu("Compare") {
            ForEach(Array(GalleryModel.Mode.allCases.enumerated()), id: \.element) { index, mode in
                Button(mode.title) { model.mode = mode }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Divider()
            Button("Measure Against Figma") { model.measure() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(model.selectedEntry?.figmaNode == nil)
            Button("Save Comparison Files") { model.saveComparison() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model.selectedEntry?.figmaNode == nil)
        }
        CommandGroup(after: .toolbar) {
            Button("Zoom In") { model.zoomIn() }.keyboardShortcut("=", modifiers: .command)
            Button("Zoom Out") { model.zoomOut() }.keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { model.zoom = 1 }.keyboardShortcut("0", modifiers: .command)
            Divider()
            Button("Toggle Light/Dark") { model.toggleScheme() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Next Entry") { model.selectAdjacent(1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button("Previous Entry") { model.selectAdjacent(-1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
        }
    }
}

/// Layout constants of the Gallery's own (developer-tool) chrome. These are not product design
/// values, so they don't come from the Figma tokens; product views never use them.
enum GalleryChrome {
    static let defaultWindowSize = CGSize(width: 1500, height: 950)
    static let sidebarWidth: CGFloat = 260
    static let inspectorWidth: CGFloat = 300
    static let canvasPadding: CGFloat = 24
    static let paneGap: CGFloat = 24
    static let labelGap: CGFloat = 6
    static let checkerCell: CGFloat = 8
    static let swatchSize: CGFloat = 10
    static let zoomSteps: [CGFloat] = [0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.5, 2, 3, 4, 6, 8]
}
