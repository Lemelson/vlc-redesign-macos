import AppKit
import MXRCore
import MXRDesign
import SwiftUI

public struct MXRMediaInfoView: View {
    /// The tallest Media Info gets: it fits its properties and tracks (as Disc and Capture fit their
    /// controls), and only a longer list than this scrolls (S65).
    public static let maximumSize = CGSize(width: Theme.Metric.DialogForms.formSize.width,
                                           height: Theme.Metric.Dialogs.addSubtitles.height)
    public let media: MediaItem
    @Environment(AppModel.self) private var app
    public init(media: MediaItem) { self.media = media }

    public var body: some View {
        // DialogShell scrolls the body. Properties and tracks share one grid, so every value starts
        // in the same column (S65).
        DialogShell(title: "Properties & Metadata", size: Self.maximumSize, fitsContent: true) {
            VStack(alignment: .leading, spacing: Theme.Spacing.gap20) {
                HStack(alignment: .top, spacing: Theme.Spacing.gap20) {
                    DialogSectionHeading(title: media.displayTitle, hint: media.listTitle)
                    if let file = URL(string: media.mrl), file.isFileURL {
                        DialogButton(title: "Show in Finder", width: nil) { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                    }
                }
                DialogDivider()
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Theme.Spacing.gap20, verticalSpacing: Theme.Spacing.gap12) {
                    GridRow {
                        label("Location")
                        Text(Self.location(of: media.mrl)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    info("Type", media.kind.rawValue.capitalized)
                    if let duration = media.duration { info("Duration", duration.formatted(.hoursMinutesSeconds)) }
                    if let size = media.videoSize { info("Resolution", "\(Int(size.width)) × \(Int(size.height))") }
                    if let artist = media.artist { info("Artist", artist) }
                    if let album = media.album { info("Album", album) }
                    if let genre = media.genre { info("Genre", genre) }
                    if let year = media.year { info("Year", String(year)) }
                    if let number = media.trackNumber { info("Track", String(number)) }
                    if let episode = media.episode { info("Episode", "\(episode.showName) \(episode.code)") }
                    if let folder = media.folder { info("Folder", folder.name) }
                    if app.player.media?.id == media.id {
                        GridRow {
                            VStack(alignment: .leading, spacing: Theme.Spacing.gap20) {
                                DialogDivider()
                                Text("Tracks").mxrTextStyle(Theme.Font.dialogSectionTitle).foregroundStyle(Theme.Color.fg2)
                            }
                            .padding(.vertical, Theme.Spacing.gap8)
                            .gridCellColumns(2)
                            .gridCellUnsizedAxes(.horizontal)
                        }
                        ForEach(TrackKind.allCases, id: \.self) { kind in
                            ForEach(app.tracks.embeddedTracks(of: kind) + app.tracks.externalTracks(of: kind)) { track in
                                info(kind.rawValue.capitalized, [track.name, track.codec].compactMap { $0 }.joined(separator: " · "))
                            }
                        }
                    }
                }.mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA1).textSelection(.enabled)
            }.padding(Theme.Metric.Dialogs.dialogBody.padding)
        }
    }

    /// A readable location: a file as its path (~ for the home folder), anything else decoded.
    static func location(of mrl: String) -> String {
        guard let url = URL(string: mrl) else { return mrl }
        if url.isFileURL { return (url.path as NSString).abbreviatingWithTildeInPath }
        return url.absoluteString.removingPercentEncoding ?? mrl
    }

    private func label(_ title: String) -> some View {
        Text(title).foregroundStyle(Theme.Color.fgA3).fixedSize().gridColumnAlignment(.leading)
    }

    private func info(_ title: String, _ value: String) -> some View {
        GridRow { label(title); Text(value).frame(maxWidth: .infinity, alignment: .leading) }
    }
}

public struct MXRAboutView: View {
    private let version: String?
    public init(version: String? = nil) { self.version = version }

    public var body: some View {
        DialogShell(title: "About VLC Redesign") {
            VStack(alignment: .leading, spacing: Theme.Spacing.gap20) {
                HStack(spacing: Theme.Spacing.gap20) {
                    MXRIcon(.vlc, size: Theme.Metric.panelSectionHeaderHeight)
                    VStack(alignment: .leading, spacing: Theme.Spacing.gap8) {
                        Text("VLC Redesign").mxrTextStyle(Theme.Font.dialogSectionTitle).foregroundStyle(Theme.Color.fg2)
                        if let version {
                            Text("VLC \(version)").mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA2)
                        }
                        Text("An unofficial native macOS interface for VLC media player.")
                            .mxrTextStyle(Theme.Font.dialogHint).foregroundStyle(Theme.Color.fgA3)
                    }
                }
                DialogDivider()
                Text("VLC media player is developed by VideoLAN and its contributors. This interface uses VLC’s unmodified playback engine.")
                    .mxrTextStyle(Theme.Font.dialogHint).foregroundStyle(Theme.Color.fgA1)
                Text("Design by Juxtopposed, adapted from “I Redesigned VLC After 25 Years.” The design is licensed under Creative Commons Attribution 4.0 (CC BY 4.0).")
                    .mxrTextStyle(Theme.Font.dialogHint).foregroundStyle(Theme.Color.fgA1)
                Text("The application and its source code are licensed under the GNU General Public License, version 2 or later.")
                    .mxrTextStyle(Theme.Font.dialogHint).foregroundStyle(Theme.Color.fgA1)
                HStack(spacing: Theme.Spacing.gap20) {
                    Link("VideoLAN", destination: URL(string: "https://www.videolan.org/vlc/")!)
                    Link("Design source", destination: URL(string: "https://www.figma.com/community/file/1691465999134370980")!)
                    Link("CC BY 4.0", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                    Link("GPL", destination: URL(string: "https://www.gnu.org/licenses/old-licenses/gpl-2.0.html")!)
                }.mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.accentMain)
                Spacer(minLength: 0)
            }.padding(Theme.Metric.Dialogs.dialogBody.padding)
        }
    }
}
