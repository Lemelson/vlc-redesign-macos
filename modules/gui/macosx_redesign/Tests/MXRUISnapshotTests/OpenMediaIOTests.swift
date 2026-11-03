import Foundation
import MXRCore
import MXRDesign
import MXRMockBackend
@testable import MXRUI
import XCTest

/// Open Disc and the output formats (J-06, J-07, J-01).
final class OpenMediaIOTests: XCTestCase {
    func testDiscKindsBuildTheMRLsVLCOpens() throws {
        XCTAssertEqual(try DialogInput.discURL(kind: .dvd, path: "/Volumes/My DVD").absoluteString, "dvd:///Volumes/My%20DVD")
        XCTAssertEqual(try DialogInput.discURL(kind: .bluray, path: "/Volumes/MOVIE").absoluteString, "bluray:///Volumes/MOVIE")
        // An audio CD is read through its raw device (modules/access/vcd/cdrom.c), as VLC's macOS interface does.
        XCTAssertEqual(try DialogInput.discURL(kind: .cdda, path: "/dev/rdisk4").absoluteString, "cdda:///dev/rdisk4")
    }

    func testVolumeDeviceIsTheRawBSDNode() throws {
        let device = try XCTUnwrap(OpticalDiscs.device(forVolumeAt: "/"))
        XCTAssertTrue(device.hasPrefix("/dev/rdisk"), device)
        XCTAssertNil(OpticalDiscs.device(forVolumeAt: "/nonexistent-\(UUID().uuidString)"))
        XCTAssertNotEqual(OpticalDiscs.fileSystemType(ofVolumeAt: "/"), "cddafs")
    }

    func testFixedDisksAreNeverOfferedAsDiscs() {
        XCTAssertFalse(OpticalDiscs.discs().contains { $0.url.path == "/" })
    }

    func testDefaultFormatIsVerifiedMP4AndStreamTitlesNameTheirCodec() {
        XCTAssertEqual(OutputFormat.all.first?.id, "h264")
        XCTAssertEqual(OutputFormat.available(engine: [], mode: .stream).map { $0.title(for: .stream) },
                       ["Video — H.264", "Video — original quality, no re-encoding"])
        XCTAssertEqual(OutputFormat.all.first?.title(for: .convert), "Video — MP4 (H.264)")
    }

    // MARK: Convert form (J-03): the object the dialog forwards every action to

    private let movie = URL(fileURLWithPath: "/Movies/Show.mkv")
    private let mp4 = URL(fileURLWithPath: "/Movies/Show.mp4")
    private var mp3: URL { mp4.deletingPathExtension().appendingPathExtension("mp3") }

    /// A format change renames the destination, and the new name was never confirmed: converting
    /// over an existing file there asks instead of overwriting it.
    @MainActor func testAFormatChangeRenamesTheDestinationAndAsksBeforeReplacing() async throws {
        let backend = MockOutput()
        backend.existingDestinations = [mp4, mp3]
        let output = OutputModel(backend: backend)
        let form = OutputForm(mode: .convert)
        form.resume(in: output, pendingSource: movie)
        form.chooseDestination(mp4, in: output)
        XCTAssertTrue(form.isValid(in: output))

        form.selectFormat("audio", in: output)
        XCTAssertEqual(form.destination?.lastPathComponent, "Show.mp3")
        await form.startOrStop(in: output)
        XCTAssertEqual(form.replaceCandidate, mp3, "the renamed file is not overwritten without asking")
        XCTAssertTrue(output.jobs.isEmpty)

        form.keepExistingFile()
        XCTAssertNil(form.replaceCandidate)
        XCTAssertTrue(output.jobs.isEmpty, "Cancel keeps the file and starts nothing")

        await form.startOrStop(in: output)
        await form.replace(in: output)
        XCTAssertEqual(output.jobs.map(\.destinationURL), [mp3])
        XCTAssertEqual(output.jobs.map(\.profile), ["audio"])
        XCTAssertTrue(form.isRunning(in: output))
    }

    /// The save panel confirmed the name, so that file is replaced without a second question.
    @MainActor func testTheSavePanelsNameIsReplacedWithoutAsking() async throws {
        let backend = MockOutput()
        backend.existingDestinations = [mp4]
        let output = OutputModel(backend: backend)
        let form = OutputForm(mode: .convert)
        form.resume(in: output, pendingSource: movie)
        form.chooseDestination(mp4, in: output)
        await form.startOrStop(in: output)
        XCTAssertNil(form.replaceCandidate)
        XCTAssertEqual(output.jobs.map(\.destinationURL), [mp4])
    }

    /// A finished file is the user's: converting to it again asks, even after the format went
    /// away and back to the name the save panel once confirmed; Replace is then not undone.
    @MainActor func testAFinishedFileIsNotReplacedSilently() async throws {
        let backend = MockOutput()
        let output = OutputModel(backend: backend)
        let form = OutputForm(mode: .convert)
        form.resume(in: output, pendingSource: movie)
        form.chooseDestination(mp4, in: output)
        await form.startOrStop(in: output)
        let first = try XCTUnwrap(output.jobs.last)
        backend.finish(first.id)
        XCTAssertEqual(form.job(in: output)?.state, .completed)

        // Convert again at once.
        await form.startOrStop(in: output)
        XCTAssertEqual(form.replaceCandidate, mp4, "the finished file is not overwritten silently")
        form.keepExistingFile()

        // To MP3 and back: the panel's old confirmation of Show.mp4 does not come back.
        form.selectFormat("audio", in: output)
        form.selectFormat("h264", in: output)
        XCTAssertEqual(form.destination, mp4)
        await form.startOrStop(in: output)
        XCTAssertEqual(form.replaceCandidate, mp4)

        await form.replace(in: output)
        XCTAssertNil(form.replaceCandidate)
        XCTAssertEqual(output.jobs.count, 2, "Replace starts the second conversion")
        XCTAssertTrue(form.isRunning(in: output))
    }

    /// The alert as SwiftUI runs it: the alert goes away first (its binding is set to false), then
    /// the chosen button's action runs. Replace must still overwrite the file the alert named
    /// (live J-overwrite: Replace did nothing and the alert came back).
    @MainActor func testReplaceOverwritesAfterTheAlertWentAway() async throws {
        let backend = MockOutput()
        backend.existingDestinations = [mp3]
        let output = OutputModel(backend: backend)
        let form = OutputForm(mode: .convert)
        form.resume(in: output, pendingSource: movie)
        form.chooseDestination(mp4, in: output)
        form.selectFormat("audio", in: output)
        await form.startOrStop(in: output)
        XCTAssertTrue(form.isAskingToReplace)

        form.isAskingToReplace = false          // SwiftUI dismisses the alert…
        await form.replace(in: output)          // …then runs Replace.
        XCTAssertEqual(output.jobs.map(\.destinationURL), [mp3], "Replace starts the conversion over the existing file")
        XCTAssertFalse(form.isAskingToReplace, "the alert does not come back")
        XCTAssertTrue(form.isRunning(in: output))

        // Cancel the same way: dismissal, then Cancel; nothing starts and nothing is asked again.
        backend.finish(try XCTUnwrap(output.jobs.last).id)
        await form.startOrStop(in: output)
        XCTAssertTrue(form.isAskingToReplace)
        form.isAskingToReplace = false
        form.keepExistingFile()
        XCTAssertNil(form.replaceCandidate)
        XCTAssertEqual(output.jobs.count, 1)
    }

    /// After a conversion finished, Convert asks, and Replace goes through: the finished job's
    /// settling happens once, so it does not take the Replace confirmation back.
    @MainActor func testReplaceAfterAFinishedConversionIsNotUndone() async throws {
        let backend = MockOutput()
        let output = OutputModel(backend: backend)
        let form = OutputForm(mode: .convert)
        form.resume(in: output, pendingSource: movie)
        form.chooseDestination(mp4, in: output)
        await form.startOrStop(in: output)
        backend.finish(try XCTUnwrap(output.jobs.last).id)

        await form.startOrStop(in: output)
        XCTAssertEqual(form.replaceCandidate, mp4)
        await form.replace(in: output)
        XCTAssertNil(form.replaceCandidate, "Replace is not asked again")
        XCTAssertEqual(output.jobs.count, 2, "the second conversion runs over the finished file")
        XCTAssertTrue(form.isRunning(in: output))
    }

    /// Reopening the dialog on a running conversion shows it, and its destination is not confirmed.
    @MainActor func testReopeningShowsTheRunningJobWithoutConfirmingItsFile() async throws {
        let backend = MockOutput()
        let output = OutputModel(backend: backend)
        backend.add(OutputJob(id: "running", sourceURL: movie, destinationURL: mp3, mode: .convert, profile: "audio", state: .running, progress: 0.4))
        let form = OutputForm(mode: .convert)
        form.resume(in: output, pendingSource: nil)
        XCTAssertEqual(form.source, movie)
        XCTAssertEqual(form.destination, mp3)
        XCTAssertEqual(form.selectedFormat(in: output).id, "audio")
        XCTAssertTrue(form.isRunning(in: output))
        XCTAssertFalse(form.target.mayReplace)
        await form.startOrStop(in: output)
        XCTAssertEqual(output.jobs.first?.state, .stopping, "the main button stops the running job")
    }

    /// The forms' sheets are whole points tall, so their edges never land between pixels at 1x.
    @MainActor func testOpenMediaSheetsAreWholePointsTall() {
        for size in [MXRDiscView.preferredSize, MXRCaptureView.preferredSize, MXRStreamView.preferredSize] {
            XCTAssertEqual(size.height, size.height.rounded(), "\(size)")
            XCTAssertEqual(size.width, Theme.Metric.DialogForms.formSize.width)
        }
        // Rounding adds less than a point: the layout inside keeps its Figma measures.
        let unrounded = Theme.Metric.dialogHeaderSimpleHeight + Theme.Metric.Dialogs.dialogBody.padding.top
            + Theme.Metric.DialogForms.sectionHeight + Theme.Metric.Dialogs.dialogBody.gap + Theme.Metric.DialogForms.choiceFieldHeight
            + Theme.Metric.Dialogs.dialogBody.gap * 2 + Theme.Font.dialogHint.lineHeight
            + Theme.Metric.Dialogs.dialogBody.padding.bottom + Theme.Metric.dialogFooterHeight
        XCTAssertLessThan(MXRCaptureView.preferredSize.height - unrounded, 1)
        XCTAssertGreaterThanOrEqual(MXRCaptureView.preferredSize.height - unrounded, 0)
    }
}
