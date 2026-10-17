import MXRCore
import MXRDesign
import SwiftUI

/// Small library dialogs (rename, delete, remove, info, failures) in the design system's dialog chrome:
/// the Open Network Stream header (6216:13615), Figma Buttons (500:3063) and the dialog footer
/// (1915:8662). Rows and menus ask for one through ``LibrarySheetCenter``; ``MXRLibraryView`` presents it.
@MainActor
@Observable
final class LibrarySheetCenter {
    enum Sheet: Identifiable {
        case renamePlaylist(Playlist)
        case renameStream(NetworkStream)
        case deletePlaylist(Playlist)
        case removeStream(NetworkStream)
        case removeFolder(LibraryFolder)
        case info(title: String, lines: [String])
        case failure(title: String, message: String)

        var id: String {
            switch self {
            case .renamePlaylist(let p): "rename-playlist:" + p.id
            case .renameStream(let s): "rename-stream:" + s.id
            case .deletePlaylist(let p): "delete-playlist:" + p.id
            case .removeStream(let s): "remove-stream:" + s.id
            case .removeFolder(let f): "remove-folder:" + f.id
            case .info(let title, _): "info:" + title
            case .failure(let title, _): "failure:" + title
            }
        }
    }

    var sheet: Sheet?

    func present(_ sheet: Sheet) { self.sheet = sheet }

    /// Reports a failed action in words: what could not be done, and VLC's reason.
    func fail(_ title: String, _ error: Error) {
        sheet = .failure(title: title, message: LibraryModel.message(for: error))
    }
}

struct LibrarySheetView: View {
    @Environment(AppModel.self) private var app
    let sheet: LibrarySheetCenter.Sheet
    let center: LibrarySheetCenter
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            DialogHeader(title: title) { close() }
            content
                .padding(Theme.Spacing.gap20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            DialogFooter(saveTitle: saveTitle, cancelTitle: saveAction == nil ? "Close" : "Cancel",
                         enabled: canSave, busy: busy, error: error, cancel: close, save: saveAction)
        }
        .frame(width: Theme.Metric.Dialogs.newPlaylist.width)
        .background { MXRDialogSurface(tint: Theme.Color.bgA3Transparent, cornerRadius: Theme.Radius.xxl) }
        .clipShape(.rect(cornerRadius: Theme.Radius.xxl))
        .onExitCommand { close() }
        .onAppear {
            if case .renamePlaylist(let playlist) = sheet { name = playlist.name }
            if case .renameStream(let stream) = sheet { name = stream.name }
        }
    }

    private var title: String {
        switch sheet {
        case .renamePlaylist: "Rename Playlist"
        case .renameStream: "Rename Stream"
        case .deletePlaylist: "Delete Playlist"
        case .removeStream: "Remove Stream"
        case .removeFolder: "Remove Folder from Library"
        case .info(let title, _): title
        case .failure(let title, _): title
        }
    }

    @ViewBuilder private var content: some View {
        switch sheet {
        case .renamePlaylist, .renameStream:
            DialogSectionHeading(title: "Name", hint: "The library shows it with this name.")
            DialogField(placeholder: "Name", text: $name).onSubmit { saveAction?() }
        case .deletePlaylist(let playlist):
            message("“\(playlist.name)” and its order will be deleted. The files stay where they are.")
        case .removeStream(let stream):
            message("“\(stream.name)” will be removed from Network. You can add the address again at any time.")
        case .removeFolder(let folder):
            message("“\(folder.name)” will no longer be scanned and its media leave the library. The files stay on disk.")
        case .info(_, let lines):
            VStack(alignment: .leading, spacing: Theme.Spacing.gap10) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in message(line) }
            }
        case .failure(_, let text):
            message(text)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text).mxrTextStyle(Theme.Font.dialogHint).foregroundStyle(Theme.Color.fgA1)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool {
        switch sheet {
        case .renamePlaylist, .renameStream: !trimmedName.isEmpty
        default: true
        }
    }
    private var saveTitle: String {
        switch sheet {
        case .deletePlaylist: "Delete"
        case .removeStream, .removeFolder: "Remove"
        default: "Save"
        }
    }

    private var saveAction: (() -> Void)? {
        switch sheet {
        case .renamePlaylist(let playlist): { run { try await app.library.renamePlaylist(playlist, to: trimmedName) } }
        case .renameStream(let stream): { run { try await app.library.renameNetworkStream(stream, to: trimmedName) } }
        case .deletePlaylist(let playlist): { run { try await app.library.deletePlaylist(playlist) } }
        case .removeStream(let stream): { run { try await app.library.removeNetworkStream(stream) } }
        case .removeFolder(let folder): { app.library.removeFolder(folder); close() }
        case .info, .failure: nil
        }
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        guard canSave, !busy else { return }
        busy = true
        error = nil
        Task {
            do { try await work(); busy = false; close() }
            catch { busy = false; self.error = LibraryModel.message(for: error) }
        }
    }

    private func close() { if !busy { center.sheet = nil } }
}
