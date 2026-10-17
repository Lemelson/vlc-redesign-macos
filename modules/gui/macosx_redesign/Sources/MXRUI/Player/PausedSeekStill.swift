import MXRCore
import MXRDesign
import SwiftUI

/// D031 UI mitigation for the stock engine's paused-seek bug: after a seek while paused, the exact
/// frame at the new time is drawn as a still over the video until the next real frame arrives
/// (see ``PausedSeekFrameModel``).
///
/// Place it directly over the video surface, filling the same rect as the video, below the bars and
/// panels. It is transparent and ignores the pointer when there is nothing to show.
///
/// The decoded frame precedes the playback vout, so the still reproduces the vout's geometry itself
/// (flip, rotation, pixel crop, crop ratio, aspect ratio, zoom: ``PausedStillLayout``). Only pixel
/// filters it cannot reproduce turn it off (D038 amendment, ``PausedStillLayout/allowsStill(effects:)``);
/// a selected subtitle track does not: a correct frame without its cue is better than the stale
/// pre-seek frame under a new time.
public struct MXRPausedSeekStill: View {
    @Environment(AppModel.self) private var app
    @Environment(\.displayScale) private var displayScale
    @State private var model: PausedSeekFrameModel?
    public init() {}

    /// Upper bound for the requested still (the decode and conversion cost grow with it).
    private static let maximumPixels = CGSize(width: 3840, height: 2160)

    public var body: some View {
        let effects = app.videoEffects.effects
        if PausedStillLayout.allowsStill(effects: effects) {
            still(effects: effects)
        }
    }

    private func still(effects: VideoEffects) -> some View {
        GeometryReader { geometry in
            ZStack {
                if let image = model?.image {
                    let source = app.tracks.selectedTrack(of: .video)?.videoSize ?? app.player.media?.videoSize
                    let layout = PausedStillLayout(image: CGSize(width: image.width, height: image.height), source: source,
                                                   effects: effects, container: geometry.size)
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: layout.imageSize.width, height: layout.imageSize.height)
                        .scaleEffect(x: layout.flipsHorizontally ? -1 : 1, y: layout.flipsVertically ? -1 : 1)
                        .rotationEffect(layout.rotation)
                        .frame(width: layout.imageSize.width, height: layout.imageSize.height)
                        .clipped()
                        .offset(x: -layout.cropOrigin.x, y: -layout.cropOrigin.y)
                        .frame(width: layout.displaySize.width, height: layout.displaySize.height, alignment: .topLeading)
                        .clipped()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .onAppear {
                if model == nil {
                    model = PausedSeekFrameModel(thumbnails: app.backends.thumbnails, player: app.player, clock: app.clock)
                }
                model?.maxPixelSize = pixelSize(for: geometry.size)
            }
            .onChange(of: geometry.size) { _, size in model?.maxPixelSize = pixelSize(for: size) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onDisappear { model?.invalidate(); model = nil }
    }

    private func pixelSize(for size: CGSize) -> CGSize {
        CGSize(width: min(max(1, size.width * displayScale), Self.maximumPixels.width),
               height: min(max(1, size.height * displayScale), Self.maximumPixels.height))
    }
}

/// Where the vout would draw a picture, for the paused-seek still (B-04).
///
/// Order follows the engine: the `transform`/`rotate` filters act on the decoded picture (rotation
/// keeps the picture's size), `croppadd` removes pixels, then the vout applies the crop ratio and
/// the aspect-ratio override and scales (fit to window, or a fixed zoom of the source size).
/// Square source pixels are assumed when the source size is unknown.
struct PausedStillLayout: Equatable {
    /// Size of the whole (uncropped) decoded picture as drawn.
    let imageSize: CGSize
    /// Top-left of the visible crop inside ``imageSize``.
    let cropOrigin: CGPoint
    /// Size of the visible picture, centred in the container.
    let displaySize: CGSize
    let flipsHorizontally: Bool
    let flipsVertically: Bool
    let rotation: Angle

    /// Pixel filters the still cannot reproduce. Geometry, the renderer, the stream resolution and
    /// deinterlacing do not change what a still frame shows; HDR overrides are never applied (D039).
    static func allowsStill(effects: VideoEffects) -> Bool {
        let essential = effects.essential
        let essentialActive = essential.isEnabled && essential != EssentialVideoFilters(isEnabled: true)
        let colors = effects.colors
        let colorsActive = colors.colorExtraction || colors.colorThreshold || colors.negate || colors.posterize
            || colors.gradient || colors.sepia
        return !essentialActive && !colorsActive
    }

    /// `"16:9"` / `"2.35:1"` → 16/9 / 2.35; nil for "Default" or an unreadable value.
    static func ratio(_ text: String?) -> CGFloat? {
        guard let parts = text?.split(separator: ":"), parts.count == 2,
              let a = Double(parts[0]), let b = Double(parts[1]), a > 0, b > 0 else { return nil }
        return CGFloat(a / b)
    }

    /// - Parameters:
    ///   - image: the decoded still's pixel size (its aspect is the source's display aspect).
    ///   - source: the video track's pixel size, for converting the `croppadd` insets; nil uses `image`.
    init(image: CGSize, source: CGSize?, effects: VideoEffects, container: CGSize) {
        let image = CGSize(width: max(image.width, 1), height: max(image.height, 1))
        let pixels = source.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil } ?? image
        // Picture in normalized units of the decoded frame (0...1 on both axes).
        let insets = effects.cropInsets
        var crop = CGRect(x: CGFloat(insets.left) / pixels.width, y: CGFloat(insets.top) / pixels.height,
                          width: 1 - CGFloat(insets.left + insets.right) / pixels.width,
                          height: 1 - CGFloat(insets.top + insets.bottom) / pixels.height)
        if crop.width <= 0 || crop.height <= 0 { crop = CGRect(x: 0, y: 0, width: 1, height: 1) }
        // Display aspect of the whole frame: the override, else the decoded frame's own.
        let frameAspect = Self.ratio(effects.aspectRatio) ?? image.width / image.height
        // Width of one normalized unit relative to one normalized height unit, on screen.
        func aspect(_ rect: CGRect) -> CGFloat { rect.width * frameAspect / rect.height }
        if let target = Self.ratio(effects.crop) {
            let current = aspect(crop)
            if current > target {
                let width = crop.width * target / current
                crop = CGRect(x: crop.midX - width / 2, y: crop.minY, width: width, height: crop.height)
            } else if current < target {
                let height = crop.height * current / target
                crop = CGRect(x: crop.minX, y: crop.midY - height / 2, width: crop.width, height: height)
            }
        }
        let visibleAspect = aspect(crop)
        var display: CGSize
        if let factor = effects.zoom.factor {
            // A fixed zoom draws the source's visible height at `factor` points per source pixel.
            let height = pixels.height * crop.height * factor
            display = CGSize(width: height * visibleAspect, height: height)
        } else if container.width / max(container.height, 1) > visibleAspect {
            display = CGSize(width: container.height * visibleAspect, height: container.height)
        } else {
            display = CGSize(width: container.width, height: container.width / visibleAspect)
        }
        display = CGSize(width: max(display.width, 0), height: max(display.height, 0))
        let full = CGSize(width: display.width / crop.width, height: display.height / crop.height)
        imageSize = full
        cropOrigin = CGPoint(x: crop.minX * full.width, y: crop.minY * full.height)
        displaySize = display
        flipsHorizontally = effects.flip == .horizontal
        flipsVertically = effects.flip == .vertical
        // VLC's `rotate` angle turns counter-clockwise; SwiftUI's rotation is clockwise.
        rotation = .degrees(-effects.rotation)
    }
}
