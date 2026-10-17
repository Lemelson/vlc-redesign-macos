import AppKit
import MXRCore
import MXRDesign
import SwiftUI

// SD-19: the design is silent about these dialogs, so they reuse the Open Network Stream chrome, the
// dialog dropdown of Add Subtitles, the Settings segmented control, and speak in plain words
// (PHILOSOPHY §4).

extension Theme.Metric.DialogForms {
    /// A 713-wide form as tall as what it holds instead of the Convert frame with empty space
    /// under it (S37): the header, the body's padding, one section per entry of `controls` (a
    /// heading and its control, 20 pt apart) with a divider and a 20 pt gap each side between
    /// sections, a `note` line under a last divider, and the footer. The 24.5 pt hint line would
    /// leave the sheet on a half point, so the frame is rounded up to whole points: the extra
    /// fraction is space above the footer, and the layout inside does not move.
    static func fittedFormSize(controls: [CGFloat], note: CGFloat? = nil) -> CGSize {
        let body = Theme.Metric.Dialogs.dialogBody
        let sections = controls.map { sectionHeight + body.gap + $0 }.reduce(0, +)
        let dividers = CGFloat(controls.count - 1 + (note == nil ? 0 : 1)) * body.gap * 2
        let height = Theme.Metric.dialogHeaderSimpleHeight + body.padding.top + sections + dividers + (note ?? 0)
            + body.padding.bottom + Theme.Metric.dialogFooterHeight
        return CGSize(width: formSize.width, height: height.rounded(.up))
    }

    /// The forms' dropdown: Figma's dialog dropdown (Add Subtitles, 1959:5324).
    static var choiceFieldHeight: CGFloat { Theme.Metric.Controls.dialogHeaderDropdown.height }
}

/// A dropdown in the Open, Convert and Stream forms. Figma draws no such form, so it is the dialog
/// family's own dropdown (Add Subtitles, 1959:5324: a BG/A5 field, FG/A1 title, FG/A2 chevron),
/// stretched to the form's width, rather than the Settings well, which reads as a pressed control
/// on the opaque Light dialog (D045).
private struct DialogChoiceField: View {
    let label: String
    let title: String
    let choices: [DialogMenuChoice]
    var body: some View {
        DialogMenu { choices } label: { DialogChoiceFieldLabel(title: title) }
            .accessibilityLabel(label)
            .accessibilityValue(title)
    }
}

private struct DialogChoiceFieldLabel: View {
    let title: String
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        let box = Theme.Metric.Controls.dialogHeaderDropdown
        HStack(spacing: box.gap) {
            Text(title).mxrTextStyle(Theme.Font.body).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(isEnabled ? Theme.Color.fgA1 : Theme.Color.fgA4)
            Spacer(minLength: 0)
            MXRIcon(.chevronDown, tint: isEnabled ? Theme.Color.fgA2 : Theme.Color.fgA4)
        }
        .padding(box.padding)
        .frame(maxWidth: .infinity)
        .frame(height: box.height)
        .background(Theme.Color.bgA5, in: .rect(cornerRadius: Theme.Radius.lg))
    }
}

public struct MXRDiscView: View {
    /// Two sections: the disc type's segmented control and the disc row.
    public static let preferredSize = Theme.Metric.DialogForms.fittedFormSize(
        controls: [Theme.Metric.SettingsDetail.controlHeight,
                   max(Theme.Metric.DialogForms.choiceFieldHeight, Theme.Metric.buttonHeight)])
    @Environment(AppModel.self) private var app
    @State private var kind: DiscKind = .dvd
    @State private var path = ""
    /// The disc's raw BSD device (`/dev/rdiskN`), which VLC's audio CD access opens (cdrom.c).
    @State private var device: String?
    @State private var discs: [MountedDisc] = []
    @State private var scan = 0
    @State private var error: String?
    public init() {}

    /// DVDs and Blu-ray discs open by their volume or folder path; an audio CD has no files to
    /// open, VLC reads it through its device.
    private var discURL: URL? { try? DialogInput.discURL(kind: kind, path: kind == .cdda ? (device ?? path) : path) }

    public var body: some View {
        DialogShell(title: "Open Disc", size: Self.preferredSize, saveTitle: "Open", enabled: discURL != nil, error: error, save: open) {
            VStack(alignment: .leading, spacing: Theme.Spacing.gap20) {
                DialogSectionHeading(title: "Disc Type", hint: "VLC plays DVDs, Blu-ray discs and audio CDs, including their menus.")
                SettingsSegmentedControl(choices: DiscKind.allCases.map { ($0, $0.title) }, selection: kind,
                                         select: { kind = $0 }, label: "Disc type")
                DialogDivider()
                DialogSectionHeading(title: "Disc", hint: discs.isEmpty
                    ? "No disc found. Insert a disc, or choose a disc folder (VIDEO_TS or BDMV) on your Mac."
                    : "Choose a disc, or a disc folder (VIDEO_TS or BDMV) on your Mac.")
                HStack(spacing: Theme.Spacing.gap20) {
                    DialogChoiceField(label: "Disc",
                                      title: path.isEmpty ? (discs.isEmpty ? "No disc found" : "Choose a disc") : URL(fileURLWithPath: path).lastPathComponent,
                                      choices: discs.map { disc in
                                          DialogMenuChoice(title: disc.url.lastPathComponent, isSelected: disc.url.path == path) { choose(disc) }
                                      })
                    .disabled(discs.isEmpty)
                    DialogButton(title: "Choose…") {
                        Task { @MainActor in
                            if let url = await DialogFilePicker.open(multiple: false, directories: true).first { chooseFolder(url) }
                        }
                    }
                }
            }.padding(Theme.Metric.Dialogs.dialogBody.padding)
        }
        // Volumes are probed off the main thread, and again whenever a disc is inserted or ejected.
        .task(id: scan) {
            let found = await Task.detached(priority: .userInitiated) { OpticalDiscs.discs() }.value
            guard !Task.isCancelled else { return }
            let previous = Set(discs.map(\.url.path))
            discs = found
            // Keep a disc or folder that is still there; replace one that was ejected.
            guard path.isEmpty || (previous.contains(path) && !found.contains { $0.url.path == path }) else { return }
            if let first = found.first { choose(first) } else { path = ""; device = nil }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in scan += 1 }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in scan += 1 }
    }

    private func choose(_ disc: MountedDisc) {
        path = disc.url.path
        kind = disc.kind
        device = disc.device
        error = nil
    }

    /// A folder chosen by hand: a disc's volume or a VIDEO_TS / BDMV folder copied to the Mac.
    private func chooseFolder(_ url: URL) {
        if let disc = discs.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) { choose(disc); return }
        path = url.path
        device = OpticalDiscs.device(forVolumeAt: url.path)
        error = nil
        let manager = FileManager.default
        if manager.fileExists(atPath: url.appendingPathComponent("BDMV").path) || url.lastPathComponent == "BDMV" { kind = .bluray }
        else if manager.fileExists(atPath: url.appendingPathComponent("VIDEO_TS").path) || url.lastPathComponent == "VIDEO_TS" { kind = .dvd }
    }

    private func open() {
        do {
            try app.open(urls: [try DialogInput.discURL(kind: kind, path: kind == .cdda ? (device ?? path) : path)], inputOptions: [])
            app.interface.dismissSheet()
        } catch { self.error = error.localizedDescription }
    }
}

/// A mounted optical disc: its volume, what it holds and its device.
struct MountedDisc: Hashable, Sendable {
    let url: URL
    let kind: DiscKind
    /// The raw BSD device (`/dev/rdiskN`), nil for a disc image that is not backed by one.
    let device: String?
}

extension OpticalDiscs {
    /// Local removable or ejectable volumes that hold a DVD, a Blu-ray disc or an audio CD. Network
    /// shares and fixed disks are skipped before any of their folders are probed. Reads the file
    /// system, so call it off the main thread.
    nonisolated static func discs() -> [MountedDisc] {
        let manager = FileManager()
        let keys: Set<URLResourceKey> = [.volumeIsLocalKey, .volumeIsEjectableKey, .volumeIsRemovableKey]
        let volumes = manager.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        return volumes.compactMap { volume in
            guard let values = try? volume.resourceValues(forKeys: keys), values.volumeIsLocal == true,
                  values.volumeIsEjectable == true || values.volumeIsRemovable == true else { return nil }
            let device = device(forVolumeAt: volume.path)
            // macOS mounts an audio CD with its own file system (cddafs), the test VLC's macOS
            // interface also makes (kVLCMediaAudioCD).
            if fileSystemType(ofVolumeAt: volume.path) == "cddafs" { return MountedDisc(url: volume, kind: .cdda, device: device) }
            if manager.fileExists(atPath: volume.appendingPathComponent("BDMV").path) { return MountedDisc(url: volume, kind: .bluray, device: device) }
            if ["VIDEO_TS", "AUDIO_TS"].contains(where: { manager.fileExists(atPath: volume.appendingPathComponent($0).path) }) {
                return MountedDisc(url: volume, kind: .dvd, device: device)
            }
            return nil
        }
    }

    /// The raw device of the volume mounted at `path` (`/dev/disk4` → `/dev/rdisk4`), as VLC's
    /// macOS interface passes it to `cdda://` (getBSDNodeFromMountPath).
    nonisolated static func device(forVolumeAt path: String) -> String? {
        var info = statfs()
        guard statfs(path, &info) == 0 else { return nil }
        let source = withUnsafeBytes(of: &info.f_mntfromname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        guard source.hasPrefix("/dev/disk") else { return nil }
        return "/dev/r" + (source as NSString).lastPathComponent
    }

    nonisolated static func fileSystemType(ofVolumeAt path: String) -> String? {
        var info = statfs()
        guard statfs(path, &info) == 0 else { return nil }
        return withUnsafeBytes(of: &info.f_fstypename) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

public struct MXRCaptureView: View {
    /// The camera section and the permission note under it.
    public static let preferredSize = Theme.Metric.DialogForms.fittedFormSize(
        controls: [Theme.Metric.DialogForms.choiceFieldHeight], note: Theme.Font.dialogHint.lineHeight)
    @Environment(AppModel.self) private var app
    @State private var deviceID = ""
    @State private var devices: [MediaDevice] = []
    @State private var error: String?
    public init() {}

    public var body: some View {
        // Named like the File menu command and its shortcut (AppCommand.openCaptureDevice).
        DialogShell(title: "Open Capture Device", size: Self.preferredSize, saveTitle: "Open", enabled: (try? DialogInput.captureURL(deviceID: deviceID)) != nil,
                    error: error, save: open) {
            VStack(alignment: .leading, spacing: Theme.Spacing.gap20) {
                DialogSectionHeading(title: "Camera", hint: devices.isEmpty
                    ? "No camera found. Connect a camera or turn on Continuity Camera on your iPhone."
                    : "Shows a camera, or a capture card that appears as one, in the player.")
                DialogChoiceField(label: "Camera",
                                  title: devices.first { $0.id == deviceID }?.name ?? (devices.isEmpty ? "No camera found" : "Choose a camera"),
                                  choices: devices.map { device in
                                      DialogMenuChoice(title: device.name, isSelected: device.id == deviceID) { deviceID = device.id }
                                  })
                .disabled(devices.isEmpty)
                DialogDivider()
                Text("The first time, macOS asks whether VLC may use the camera.")
                    .mxrTextStyle(Theme.Font.dialogHint).foregroundStyle(Theme.Color.fgA3)
            }.padding(Theme.Metric.Dialogs.dialogBody.padding)
        }.task {
            let available = await app.settings.backend.availableDevices(for: .videoCapture)
            guard !Task.isCancelled else { return }
            devices = available
            deviceID = MediaDevice.captureSelection(currentID: deviceID, devices: available)
        }
    }
    private func open() {
        do { try app.open(urls: [try DialogInput.captureURL(deviceID: deviceID)], inputOptions: []); app.interface.dismissSheet() }
        catch { self.error = error.localizedDescription }
    }
}

public struct MXRConvertView: View {
    public init() {}
    public var body: some View { OutputMediaForm(mode: .convert) }
}

public struct MXRStreamView: View {
    /// The shared form frame plus one labelled field row: the Stream form has one more row (the
    /// destination address) than the other 713-wide forms, and it must be visible without
    /// scrolling (SD-19).
    /// Rounded up to whole points like ``Theme/Metric/DialogForms/fittedFormSize(controls:note:)``.
    public static let preferredSize = CGSize(
        width: Theme.Metric.DialogForms.formSize.width,
        height: (Theme.Metric.DialogForms.formSize.height + StreamAddressField.height + Theme.Spacing.gap20).rounded(.up))
    public init() {}
    public var body: some View { OutputMediaForm(mode: .stream) }
}

/// A conversion or streaming format in plain words. `id` is the engine profile.
struct OutputFormat: Hashable {
    let id: String
    let title: String
    /// The title in the Stream dialog, where video always travels as MPEG-TS.
    let streamTitle: String
    let fileExtension: String
    let streams: Bool

    /// Formats verified to convert and stream in this VLC build (D036, MXRMediaServices.m).
    static let all: [OutputFormat] = [
        OutputFormat(id: "h264", title: "Video — MP4 (H.264)", streamTitle: "Video — H.264", fileExtension: "mp4", streams: true),
        OutputFormat(id: "copy", title: "Video — original quality, no re-encoding (TS)", streamTitle: "Video — original quality, no re-encoding",
                     fileExtension: "ts", streams: true),
        OutputFormat(id: "audio", title: "Audio — MP3", streamTitle: "Audio — MP3", fileExtension: "mp3", streams: false),
        OutputFormat(id: "aac", title: "Audio — AAC (M4A)", streamTitle: "Audio — AAC", fileExtension: "m4a", streams: false),
        OutputFormat(id: "wav", title: "Audio — WAV (uncompressed)", streamTitle: "Audio — WAV", fileExtension: "wav", streams: false),
    ]

    /// The formats the engine offers (all of them when it does not list any, as in previews).
    static func available(engine: [OutputProfile], mode: OutputMode) -> [OutputFormat] {
        let ids = Set(engine.map(\.id))
        return all.filter { (ids.isEmpty || ids.contains($0.id)) && (mode == .convert || $0.streams) }
    }

    func title(for mode: OutputMode) -> String { mode == .convert ? title : streamTitle }
}

/// How much of the file VLC has written: the accent fill of the library's watch progress
/// (LibrarySupport) on the dialog fields' outline colour.
private struct OutputProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Color.bgA4)
                Capsule().fill(Theme.Color.accentMain).frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: Theme.Metric.outputProgressHeight)
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("Conversion progress")
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
    }
}

/// A field of the stream's address under its name, so a filled field still says what it holds.
private struct StreamAddressField: View {
    /// The name line, its gap and the field.
    static let height = Theme.Font.dialogHint.lineHeight + Theme.Spacing.gap5 + Theme.Metric.DialogForms.fieldSlotHeight
    let label: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.gap5) {
            Text(label).mxrTextStyle(Theme.Font.dialogHint).foregroundStyle(Theme.Color.fgA3)
                .accessibilityHidden(true) // the field is named by it already
            DialogField(placeholder: label, text: $text)
        }
    }
}

/// Stream destinations VLC can send to (the bridge accepts HTTP, UDP and RTP).
enum StreamDestination: String, CaseIterable {
    case http, udp, rtp
    var title: String { switch self { case .http: "Web (HTTP)"; case .udp: "Network (UDP)"; case .rtp: "RTP" } }
    var hint: String {
        switch self {
        case .http: "Devices on your network open this Mac's address and port in VLC or a web browser."
        case .udp: "Sends to one computer or a multicast group. To watch, open udp://@:port in VLC."
        case .rtp: "Sends to one computer or a multicast group whose player expects RTP."
        }
    }
    var defaultHost: String { self == .http ? "0.0.0.0" : "239.255.0.1" }
}

/// What the Convert and Stream form holds and does. The dialog draws it and forwards each action
/// to it unchanged, so a test drives the same object the dialog does (J-03).
@MainActor @Observable
final class OutputForm {
    let mode: OutputMode
    var source: URL?
    /// Where the file goes and whether VLC may replace one already there (J-03).
    private(set) var target = ConversionDestination()
    /// A destination VLC reported as existing, waiting for Replace or Cancel.
    private(set) var replaceCandidate: URL?
    private(set) var format = OutputFormat.all[0].id
    private(set) var streamKind: StreamDestination = .http
    var host = StreamDestination.http.defaultHost
    var port = "8080"
    var path = "/live"
    var error: String?
    private(set) var submitting = false
    private(set) var submittedJobID: String?
    /// The finished job whose file was handed to the user already (``settle(_:)``).
    @ObservationIgnored private var settledJobID: String?

    init(mode: OutputMode) { self.mode = mode }

    var isConversion: Bool { mode == .convert }
    var destination: URL? { target.url }
    var streamURL: URL? { try? DialogInput.streamURL(kind: streamKind, host: host, port: port, path: path) }

    func formats(in output: OutputModel) -> [OutputFormat] { OutputFormat.available(engine: output.profiles, mode: mode) }
    func selectedFormat(in output: OutputModel) -> OutputFormat {
        let formats = formats(in: output)
        return formats.first { $0.id == format } ?? formats.first ?? OutputFormat.all[0]
    }
    func job(in output: OutputModel) -> OutputJob? { output.jobs.first { $0.id == submittedJobID } }
    func isRunning(in output: OutputModel) -> Bool { job(in: output)?.state.isActive ?? false }

    func isValid(in output: OutputModel) -> Bool {
        guard let source else { return false }
        if isConversion {
            let fileExtension = selectedFormat(in: output).fileExtension
            return destination.map { $0 != source && (try? DialogInput.conversionDestination($0, fileExtension: fileExtension)) != nil } ?? false
        }
        return streamURL != nil
    }

    // MARK: Opening

    /// The dialog opened: it shows the running job of its kind, or starts on the file the user
    /// chose Convert or Stream for.
    func resume(in output: OutputModel, pendingSource: URL?) {
        guard let activeJob = output.jobs.last(where: { $0.mode == mode && $0.state.isActive }) else {
            source = pendingSource
            return
        }
        submittedJobID = activeJob.id
        source = activeJob.sourceURL
        format = activeJob.profile
        if isConversion { target = ConversionDestination(url: activeJob.destinationURL) }
        else if let url = activeJob.destinationURL { showStreamDestination(url) }
    }

    // MARK: Editing

    func chooseSource(_ url: URL, in output: OutputModel) {
        settle(output)
        source = url
        forgetFinishedJob(output)
    }

    /// A new format renames the destination to the format's extension; that name was never
    /// confirmed (J-03).
    func selectFormat(_ id: String, in output: OutputModel) {
        guard let chosen = formats(in: output).first(where: { $0.id == id }) else { return }
        settle(output)
        format = chosen.id
        target.changeExtension(to: chosen.fileExtension)
        forgetFinishedJob(output)
    }

    /// The save panel returned `url`; it asked about replacing a file there already.
    func chooseDestination(_ url: URL, in output: OutputModel) {
        settle(output)
        target.choose(url)
        forgetFinishedJob(output)
    }

    func selectStreamKind(_ kind: StreamDestination, in output: OutputModel) {
        settle(output)
        if host == streamKind.defaultHost { host = kind.defaultHost }
        streamKind = kind
        forgetFinishedJob(output)
    }

    // MARK: Running

    /// The main button: stops the running job, or starts one. A destination nobody confirmed that
    /// already exists is not replaced; it becomes ``replaceCandidate`` and the dialog asks.
    func startOrStop(in output: OutputModel) async {
        settle(output)
        if isRunning(in: output), let id = submittedJobID {
            do { try output.stop(id: id) } catch { self.error = error.localizedDescription }
            return
        }
        guard let source, !submitting else { return }
        let profile = selectedFormat(in: output).id
        let destination = isConversion ? destination : nil
        submitting = true
        error = nil
        defer { submitting = false }
        do {
            if isConversion, destination == source { throw DialogInputError.invalid("Choose a destination different from the source file.") }
            let stream = isConversion ? nil : try DialogInput.streamURL(kind: streamKind, host: host, port: port, path: path)
            let job = try await output.start(sourceURL: source, destinationURL: destination, streamURL: stream, mode: mode,
                                             profile: profile, overwrite: isConversion && target.mayReplace)
            submittedJobID = job.id
        } catch OutputError.destinationExists(let url) {
            // A name the save panel never confirmed (a new format, or a second conversion): ask.
            replaceCandidate = url
        } catch { self.error = error.localizedDescription }
    }

    /// Replace in the alert: VLC may overwrite that file, and the job starts.
    func replace(in output: OutputModel) async {
        if let replaceCandidate { target.confirmReplacing(replaceCandidate) }
        replaceCandidate = nil
        await startOrStop(in: output)
    }

    func keepExistingFile() { replaceCandidate = nil }

    // MARK: Private

    /// A finished file is the user's now: converting to that name again asks first. Applied once
    /// per job, before any action, so a later Replace for the same name is not undone.
    private func settle(_ output: OutputModel) {
        guard let job = job(in: output), job.state == .completed, settledJobID != job.id else { return }
        settledJobID = job.id
        target.completed()
    }

    /// After a job ended, editing the form starts over instead of showing the old result.
    private func forgetFinishedJob(_ output: OutputModel) {
        if !isRunning(in: output) { submittedJobID = nil; error = nil }
    }

    /// The fields of a running stream's address (the bridge reports it as the job's destination).
    private func showStreamDestination(_ url: URL) {
        guard let kind = url.scheme.flatMap({ StreamDestination(rawValue: $0.lowercased()) }), let urlHost = url.host, let urlPort = url.port else { return }
        streamKind = kind
        host = urlHost
        port = String(urlPort)
        if kind == .http { path = url.path }
    }
}

private struct OutputMediaForm: View {
    @Environment(AppModel.self) private var app
    @State private var form: OutputForm

    init(mode: OutputMode) { _form = State(initialValue: OutputForm(mode: mode)) }

    private var output: OutputModel { app.output }
    private var isConversion: Bool { form.isConversion }
    private var selectedFormat: OutputFormat { form.selectedFormat(in: output) }
    private var job: OutputJob? { form.job(in: output) }
    private var isRunning: Bool { form.isRunning(in: output) }
    private var unavailableMessage: String? {
        output.isAvailable ? nil : "\(isConversion ? "Converting" : "Streaming") isn't available in this copy of VLC."
    }

    var body: some View {
        DialogShell(title: isConversion ? "Convert" : "Stream",
                    size: isConversion ? Theme.Metric.DialogForms.formSize : MXRStreamView.preferredSize,
                    saveTitle: isRunning ? "Stop" : isConversion ? "Convert" : "Start",
                    enabled: isRunning ? job?.state != .stopping : (form.isValid(in: output) && output.isAvailable), busy: form.submitting,
                    error: form.error ?? job?.error ?? unavailableMessage, save: { run { await form.startOrStop(in: output) } }) {
            VStack(alignment: .leading, spacing: Theme.Spacing.gap20) {
                DialogSectionHeading(title: "Source File", hint: "The file to \(isConversion ? "convert" : "stream").")
                HStack(spacing: Theme.Spacing.gap20) {
                    Text(form.source?.lastPathComponent ?? "No file selected").mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA1)
                        .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                        .help(form.source?.path ?? "")
                    DialogButton(title: "Choose…") {
                        run { if let url = await DialogFilePicker.open(multiple: false).first { form.chooseSource(url, in: output) } }
                    }
                }
                .disabled(isRunning || form.submitting)
                DialogDivider()
                DialogSectionHeading(title: "Format", hint: isConversion ? "MP4 plays almost everywhere. Audio formats keep only the sound."
                                                                        : "Original quality sends the file as it is. H.264 re-encodes it so more devices can play it.")
                DialogChoiceField(label: "Format", title: selectedFormat.title(for: form.mode),
                                  choices: form.formats(in: output).map { format in
                                      DialogMenuChoice(title: format.title(for: form.mode), isSelected: format.id == selectedFormat.id) {
                                          form.selectFormat(format.id, in: output)
                                      }
                                  })
                .disabled(isRunning || form.submitting)
                DialogDivider()
                if isConversion { saveAsSection } else { sendToSection }
            }
            .padding(Theme.Metric.Dialogs.dialogBody.padding)
        }
        .alert(replaceTitle, isPresented: Binding(get: { form.replaceCandidate != nil }, set: { if !$0 { form.keepExistingFile() } })) {
            Button("Replace", role: .destructive) { run { await form.replace(in: output) } }
            Button("Cancel", role: .cancel) { form.keepExistingFile() }
        } message: {
            Text("A file with the same name already exists in “\(form.replaceCandidate?.deletingLastPathComponent().lastPathComponent ?? "")”. Replacing it will overwrite its current contents.")
        }
        .onAppear { form.resume(in: output, pendingSource: app.interface.pendingOutputSource.flatMap { URL(string: $0.mrl) }) }
        .onDisappear { app.interface.pendingOutputSource = nil }
    }

    private func run(_ action: @escaping @MainActor () async -> Void) { Task { @MainActor in await action() } }

    // MARK: Save As (Convert)

    @ViewBuilder private var saveAsSection: some View {
        let name = form.destination?.lastPathComponent ?? "No destination selected"
        DialogSectionHeading(title: "Save As", hint: saveAsHint)
        HStack(spacing: Theme.Spacing.gap20) {
            if let job, job.state.isActive {
                // While VLC writes the file, the row shows how far it is.
                OutputProgressBar(value: job.progress)
                Text(job.progress, format: .percent.precision(.fractionLength(0)))
                    .mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA2).monospacedDigit()
                    .frame(width: Theme.Metric.buttonWidth, alignment: .trailing)
            } else {
                Text(name).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA1)
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                    .help(form.destination?.path ?? "")
                if let job, job.state == .completed, let url = job.destinationURL {
                    DialogButton(title: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                DialogButton(title: "Choose…") {
                    let fileExtension = selectedFormat.fileExtension
                    let name = (form.source?.deletingPathExtension().lastPathComponent ?? "Converted") + "." + fileExtension
                    run {
                        if let url = await DialogFilePicker.save(fileExtension: fileExtension, name: name) { form.chooseDestination(url, in: output) }
                    }
                }
                .disabled(form.submitting)
            }
        }
        // The progress and the file row take the place of each other at the button's height.
        .frame(height: Theme.Metric.buttonHeight)
    }

    private var saveAsHint: String {
        let name = form.destination?.lastPathComponent ?? ""
        switch job?.state {
        case .queued?, .running?: return "Converting to “\(name)”…"
        case .finishing?: return "Finishing “\(name)”…"
        case .stopping?: return "Stopping…"
        case .completed?: return "Saved “\(name)”."
        case .cancelled?: return "Stopped. Nothing was saved."
        case .failed?: return "The file wasn't saved."
        case nil: return "Where the converted file is saved."
        }
    }

    // MARK: Send To (Stream)

    @ViewBuilder private var sendToSection: some View {
        @Bindable var form = form
        DialogSectionHeading(title: "Send To", hint: sendToHint)
        Group {
            SettingsSegmentedControl(choices: StreamDestination.allCases.map { ($0, $0.title) }, selection: form.streamKind,
                                     select: { form.selectStreamKind($0, in: output) }, label: "Stream destination")
            HStack(spacing: Theme.Spacing.gap10) {
                StreamAddressField(label: "Address", text: $form.host)
                StreamAddressField(label: "Port", text: $form.port).frame(width: Theme.Metric.buttonWidth)
                if form.streamKind == .http { StreamAddressField(label: "Path", text: $form.path).frame(width: Theme.Metric.streamPathFieldWidth) }
            }
        }
        .disabled(isRunning || form.submitting)
    }

    private var sendToHint: String {
        switch job?.state {
        case .queued?, .running?, .finishing?:
            if form.streamKind == .http, let url = receivingURL { return "Streaming. Other devices open \(url) in VLC or a web browser." }
            return "Streaming to \(form.streamURL?.absoluteString ?? form.host)."
        case .stopping?: return "Stopping…"
        case .completed?: return "The stream ended."
        case .cancelled?: return "Stopped."
        case .failed?: return "The stream stopped."
        case nil: return form.streamKind.hint
        }
    }

    /// The address other devices open for an HTTP stream that listens on every interface.
    private var receivingURL: String? {
        guard ["0.0.0.0", "::", "[::]"].contains(form.host.trimmingCharacters(in: .whitespaces)),
              let name = output.localHostName else { return form.streamURL?.absoluteString }
        var components = URLComponents()
        components.scheme = "http"
        components.host = name + ".local"
        components.port = Int(form.port.trimmingCharacters(in: .whitespaces))
        let trimmed = form.path.trimmingCharacters(in: .whitespaces)
        components.path = trimmed.isEmpty || trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
        return components.url?.absoluteString
    }

    private var replaceTitle: String { "“\(form.replaceCandidate?.lastPathComponent ?? "")” already exists. Do you want to replace it?" }
}
