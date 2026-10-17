import AppKit
import MXRCore
import Observation
import UniformTypeIdentifiers

/// Serializes native file panels and engine dialogs with the SwiftUI scene's sheets.
@MainActor
final class MXRNativePresentations {
    private let model: AppModel
    private weak var window: NSWindow?
    private var openPanel: NSOpenPanel?
    private var alert: NSAlert?
    private var alertRequest: DialogRequest?
    private var progress: NSProgressIndicator?
    private var isRunning = false
    private var observationGeneration = 0
    private var sheetObserver: (any NSObjectProtocol)?

    init(model: AppModel, window: NSWindow) {
        self.model = model
        self.window = window
    }

    func start() {
        isRunning = true
        sheetObserver = NotificationCenter.default.addObserver(forName: NSWindow.didEndSheetNotification,
            object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isRunning else { return }
                    // SwiftUI can clear its sheet model before the native sheet
                    // detaches. Retry queued panels only after that detach.
                    self.refresh()
                }
            }
        refresh()
    }
    func stop() {
        isRunning = false
        observationGeneration += 1
        if let sheetObserver { NotificationCenter.default.removeObserver(sheetObserver) }
        sheetObserver = nil
        openPanel?.cancel(nil)
        if let alert, let window { window.endSheet(alert.window, returnCode: .abort) }
        alert?.window.orderOut(nil)
        progress?.stopAnimation(nil)
        openPanel = nil
        alert = nil
        alertRequest = nil
    }

    private func refresh() {
        guard isRunning else { return }
        observationGeneration += 1
        let generation = observationGeneration
        let pending = withObservationTracking {
            (model.interface.fileRequest, model.dialogs.current, model.interface.sheet)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.observationGeneration == generation else { return }
                self.refresh()
            }
        }
        guard let window else { return }
        if let alert, let shown = alertRequest {
            guard pending.1?.id == shown.id else {
                window.endSheet(alert.window, returnCode: .abort)
                return
            }
            alert.informativeText = pending.1?.text ?? shown.text
            if case .progress(_, let value, _) = pending.1?.kind { progress?.doubleValue = value }
            return
        }
        // "Show confirmation and error dialogs" off (SD-M3): an error is shown briefly over the video
        // instead of in a dialog. Questions, logins and progress always need the dialog.
        if let request = pending.1, case .error = request.kind,
           model.backends.settings.value(for: Self.showErrorsOption)?.boolValue == false {
            model.osd.showNotice([request.title, request.text].filter { !$0.isEmpty }.joined(separator: ": "))
            model.dialogs.dismiss(request)
            return
        }
        guard openPanel == nil, window.attachedSheet == nil, pending.2 == nil else { return }
        if let request = pending.1 { present(request, on: window) }
        else if let request = pending.0 { present(request, on: window) }
    }

    private func present(_ request: FileRequest, on window: NSWindow) {
        let panel = NSOpenPanel()
        panel.title = switch request {
        case .openFiles: "Open File(s)"
        case .openFolder: "Open Folder"
        case .addSubtitleFile: "Add Subtitle File"
        case .addAudioFile: "Add Audio File"
        case .addLibraryFolder: "Add Library Folder"
        case .addFilesToQueue: "Add Files to Queue"
        case .addLibraryFiles: "Add Files to Library"
        }
        panel.canChooseDirectories = request == .openFolder || request == .addLibraryFolder
        panel.canChooseFiles = !panel.canChooseDirectories
        panel.allowsMultipleSelection = request != .openFolder
        if request == .addSubtitleFile {
            panel.allowedContentTypes = ["srt", "ass", "ssa", "vtt", "sub", "idx"].compactMap { UTType(filenameExtension: $0) }
        }
        openPanel = panel
        window.makeKeyAndOrderFront(nil)
        panel.beginSheetModal(for: window) { [weak self, weak panel] response in
            guard let self else { return }
            self.openPanel = nil
            if self.isRunning, self.model.interface.fileRequest == request {
                let urls = response == .OK ? panel?.urls ?? [] : []
                self.model.complete(request, urls: urls)
                if request == .openFiles || request == .openFolder {
                    MXRNativeRecents.record(urls, model: self.model)
                }
            }
            self.refresh()
        }
    }

    static let showErrorsOption = "macosx-redesign-show-errors"

    private enum Answer { case dismiss, action(Int), login }

    private func present(_ request: DialogRequest, on window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = request.title
        alert.informativeText = request.text
        var answers: [Answer] = []
        var username: NSTextField?
        var password: NSSecureTextField?
        var remember: NSButton?
        switch request.kind {
        case .error:
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            answers = [.dismiss]
        case .question(let severity, let action1, let action2, let cancel):
            alert.alertStyle = severity == .critical ? .critical : severity == .warning ? .warning : .informational
            for (index, title) in [action1, action2].enumerated() {
                if let title, !title.isEmpty { alert.addButton(withTitle: title); answers.append(.action(index + 1)) }
            }
            if let cancel, !cancel.isEmpty {
                alert.addButton(withTitle: cancel).keyEquivalent = "\u{1b}"
                answers.append(.dismiss)
            }
            if answers.isEmpty { alert.addButton(withTitle: "OK"); answers = [.dismiss] }
        case .login(let defaultUsername, let canStore):
            let user = NSTextField(string: defaultUsername)
            user.placeholderString = "Username"
            let pass = NSSecureTextField(string: "")
            pass.placeholderString = "Password"
            let store = NSButton(checkboxWithTitle: "Remember password", target: nil, action: nil)
            let fields = NSStackView(views: canStore ? [user, pass, store] : [user, pass])
            fields.orientation = .vertical
            fields.alignment = .leading
            fields.spacing = 8
            fields.frame.size = NSSize(width: 320, height: canStore ? 88 : 58)
            user.widthAnchor.constraint(equalToConstant: 320).isActive = true
            pass.widthAnchor.constraint(equalToConstant: 320).isActive = true
            alert.accessoryView = fields
            username = user; password = pass; remember = store
            alert.addButton(withTitle: "Log In")
            alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
            answers = [.login, .dismiss]
        case .progress(let indeterminate, let value, let cancel):
            let indicator = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 320, height: 18))
            indicator.style = .bar
            indicator.isIndeterminate = indeterminate
            indicator.minValue = 0
            indicator.maxValue = 1
            indicator.doubleValue = value
            if indeterminate { indicator.startAnimation(nil) }
            progress = indicator
            alert.accessoryView = indicator
            let button = alert.addButton(withTitle: cancel ?? "Cancel")
            button.isHidden = cancel == nil
            button.isEnabled = cancel != nil
            answers = [.dismiss]
        }
        self.alert = alert
        alertRequest = request
        window.makeKeyAndOrderFront(nil)
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.alert = nil
            self.alertRequest = nil
            self.progress?.stopAnimation(nil)
            self.progress = nil
            if self.isRunning, self.model.dialogs.requests.contains(where: { $0.id == request.id }) {
                let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
                let answer = answers.indices.contains(index) ? answers[index] : .dismiss
                switch answer {
                case .dismiss: self.model.dialogs.dismiss(request)
                case .action(let index): self.model.dialogs.choose(request, action: index)
                case .login:
                    self.model.dialogs.submitLogin(request, username: username?.stringValue ?? "",
                        password: password?.stringValue ?? "", store: remember?.state == .on)
                }
            }
            self.refresh()
        }
        if let username { alert.window.makeFirstResponder(username) }
    }
}
