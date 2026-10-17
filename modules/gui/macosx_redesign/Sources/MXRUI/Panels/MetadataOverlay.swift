import MXRCore
import MXRDesign
import SwiftUI

/// "Show Metadata" (Playback tab, video 09m17.5): what is playing and how, over the video.
///
/// Figma has no frame for it (VIDEO_BREAKDOWN §07 OPEN suggests a file-info panel), so it reuses
/// the side-panel surface and type: a caption grid of the title, file, tracks and live input
/// statistics. It never takes clicks, so the video below stays interactive.
public struct MXRMetadataOverlayView: View {
    @Environment(AppModel.self) private var app
    public init() {}

    public var body: some View {
        if app.interface.showMetadata, let media = app.player.media {
            HuggingWidth(maxWidth: Theme.Metric.SidePanels.tracksPopup.width) {
            VStack(alignment: .leading, spacing: Theme.Spacing.gap8) {
                Text(media.displayTitle).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA1).lineLimit(1)
                Grid(alignment: .leading, horizontalSpacing: PanelSpace.md, verticalSpacing: Theme.Spacing.gap4) {
                    ForEach(rows(for: media), id: \.title) { row in
                        GridRow {
                            Text(row.title).foregroundStyle(Theme.Color.fgA3)
                            Text(row.value).foregroundStyle(Theme.Color.fgA2).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }.mxrTextStyle(Theme.Font.caption)
            }
            .padding(.horizontal, PanelSpace.lg).padding(.vertical, PanelSpace.md)
            }
            .background {
                MXRBackdropSurface(tint: Theme.Color.bgB1Transparent, cornerRadius: Theme.Metric.SidePanels.tracksPopup.radius ?? Theme.Radius.xl)
            }
            .clipShape(.rect(cornerRadius: Theme.Metric.SidePanels.tracksPopup.radius ?? Theme.Radius.xl))
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Media information")
        }
    }

    private struct Row { let title: String; let value: String }

    private func rows(for media: MediaItem) -> [Row] {
        var rows: [Row] = []
        func add(_ title: String, _ value: String?) {
            if let value, !value.isEmpty { rows.append(Row(title: title, value: value)) }
        }
        add("File", media.fileName)
        if media.kind == .audio {
            add("Artist", media.artist)
            add("Album", [media.album, media.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
        }
        let video = app.tracks.selectedTrack(of: .video)
        let size = video?.videoSize ?? media.videoSize
        add("Video", [video?.codec, size.map { "\(Int($0.width)) × \(Int($0.height))" }].compactMap { $0 }.joined(separator: " · "))
        let audio = app.tracks.selectedTrack(of: .audio)
        add("Audio", [audio?.codec, audio?.language ?? audio?.name].compactMap { $0 }.joined(separator: " · "))
        add("Subtitles", app.tracks.selectedTrack(of: .subtitle)?.name)
        if app.player.rate != 1 { add("Speed", String(format: "%gx", app.player.rate)) }
        if let statistics = app.player.statistics {
            if statistics.inputBitrate > 0 {
                // input_stats_t reports kB/s; people read stream rates in Mb/s.
                add("Bitrate", String(format: "%.1f Mb/s", statistics.inputBitrate * 8 / 1000))
            }
            if statistics.displayedPictures > 0 || statistics.lostPictures > 0 {
                add("Frames", "\(statistics.displayedPictures) shown, \(statistics.lostPictures) dropped")
            }
        }
        return rows
    }
}

/// Sizes its content to its ideal width, at most `maxWidth` (long file names truncate).
private struct HuggingWidth: Layout {
    let maxWidth: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let width = min(child.sizeThatFits(.unspecified).width, maxWidth, proposal.width ?? .infinity)
        return child.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
