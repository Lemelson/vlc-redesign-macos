import Foundation
import XCTest
@testable import MXRCore
@testable import MXRMockBackend

/// Convert, Stream and renderer models over the mock services (J-09).
@MainActor
final class OutputModelTests: XCTestCase {
    private let source = URL(fileURLWithPath: "/Movies/Show.mkv")
    private let destination = URL(fileURLWithPath: "/Movies/Show.mp4")

    func testStopKeepsTheJobActiveUntilTheEngineEndsIt() async throws {
        let backend = MockOutput()
        let model = OutputModel(backend: backend)
        XCTAssertTrue(model.isAvailable)
        let job = try await model.start(sourceURL: source, destinationURL: destination, mode: .convert, profile: "h264")
        XCTAssertEqual(model.jobs.map(\.state), [.running])
        do {
            _ = try await model.start(sourceURL: source, destinationURL: destination, mode: .convert, profile: "copy")
            XCTFail("one job at a time")
        } catch {}
        try model.stop(id: job.id)
        XCTAssertEqual(model.jobs.first?.state, .stopping)
        XCTAssertTrue(model.jobs.first?.state.isActive ?? false, "the form stays locked while VLC closes the output")
        backend.finish(job.id)
        XCTAssertEqual(model.jobs.first?.state, .cancelled)
        XCTAssertFalse(model.jobs.first?.state.isActive ?? true)
    }

    func testReplacingAFileNeedsConfirmation() async throws {
        let backend = MockOutput()
        let model = OutputModel(backend: backend)
        let first = try await model.start(sourceURL: source, destinationURL: destination, mode: .convert, profile: "h264")
        backend.finish(first.id)
        XCTAssertEqual(model.jobs.last?.state, .completed)
        do {
            _ = try await model.start(sourceURL: source, destinationURL: destination, mode: .convert, profile: "h264", overwrite: false)
            XCTFail("a finished file is not replaced silently")
        } catch {
            XCTAssertEqual(error as? OutputError, .destinationExists(destination))
        }
        let second = try await model.start(sourceURL: source, destinationURL: destination, mode: .convert, profile: "h264", overwrite: true)
        XCTAssertEqual(second.state, .running)
    }

    /// The Convert form's overwrite decision (J-03), against the mock's EEXIST behaviour: only the
    /// name the save panel or Replace confirmed is replaced without asking.
    func testOnlyAConfirmedDestinationIsReplacedSilently() async throws {
        let backend = MockOutput()
        let model = OutputModel(backend: backend)
        backend.existingDestinations = [destination, destination.deletingPathExtension().appendingPathExtension("mp3")]
        var target = ConversionDestination()
        XCTAssertFalse(target.mayReplace, "no destination, nothing to replace")

        // The save panel asked about replacing Show.mp4 already.
        target.choose(destination)
        XCTAssertTrue(target.mayReplace)

        // A format change renames the file to Show.mp3, a name nobody confirmed.
        target.changeExtension(to: "mp3")
        XCTAssertEqual(target.url?.lastPathComponent, "Show.mp3")
        XCTAssertFalse(target.mayReplace)
        do {
            _ = try await model.start(sourceURL: source, destinationURL: target.url, mode: .convert, profile: "audio", overwrite: target.mayReplace)
            XCTFail("the renamed destination must not be replaced without asking")
        } catch {
            XCTAssertEqual(error as? OutputError, .destinationExists(try XCTUnwrap(target.url)))
        }
        // Replace in the alert confirms that name.
        target.confirmReplacing(try XCTUnwrap(target.url))
        let job = try await model.start(sourceURL: source, destinationURL: target.url, mode: .convert, profile: "audio", overwrite: target.mayReplace)
        backend.finish(job.id)
        XCTAssertEqual(model.jobs.last?.state, .completed)

        // The finished file is the user's: converting to it again asks first.
        target.completed()
        XCTAssertEqual(target.url?.lastPathComponent, "Show.mp3", "completion keeps the destination")
        XCTAssertFalse(target.mayReplace)
        do {
            _ = try await model.start(sourceURL: source, destinationURL: target.url, mode: .convert, profile: "audio", overwrite: target.mayReplace)
            XCTFail("a finished file is not replaced silently")
        } catch {
            XCTAssertEqual(error as? OutputError, .destinationExists(try XCTUnwrap(target.url)))
        }

        // Going back to the format whose name the panel confirmed restores that confirmation only
        // until the next completion.
        target.choose(destination)
        target.changeExtension(to: "mp3")
        target.changeExtension(to: "mp4")
        XCTAssertTrue(target.mayReplace, "the panel confirmed Show.mp4")
    }

    func testAResumedJobsDestinationIsNotConfirmed() {
        let resumed = ConversionDestination(url: destination)
        XCTAssertEqual(resumed.url, destination)
        XCTAssertFalse(resumed.mayReplace, "reopening the dialog on a running job confirms nothing")
    }

    func testTheStreamAddressUsesTheBackendsHostName() {
        let backend = MockOutput()
        XCTAssertEqual(OutputModel(backend: backend).localHostName, "Studio-Mac", "renders never show the build machine's name")
        backend.localHostName = nil
        XCTAssertNil(OutputModel(backend: backend).localHostName)
        XCTAssertNil(OutputModel(backend: nil).localHostName)
    }

    func testStreamJobReportsItsAddress() async throws {
        let model = OutputModel(backend: MockOutput())
        let address = try XCTUnwrap(URL(string: "http://0.0.0.0:8080/live"))
        let job = try await model.start(sourceURL: source, streamURL: address, mode: .stream, profile: "copy")
        XCTAssertEqual(job.destinationURL, address)
    }

    func testRediscoveryKeepsTheRendererInUse() async throws {
        let backend = MockRenderers()
        let tv = RendererInfo(id: "renderer:chromecast:tv", name: "Living Room TV", type: "chromecast")
        backend.discoverable = [tv]
        let model = RendererModel(backend: backend)
        XCTAssertTrue(model.items.isEmpty)
        try await model.discover()
        XCTAssertEqual(model.items, [tv])
        XCTAssertFalse(model.isDiscovering, "discovery does not stay 'Discovering…' forever")
        try model.select(id: tv.id)
        backend.discoverable = []
        try await model.discover()
        XCTAssertEqual(model.selectedID, tv.id)
        XCTAssertEqual(model.items, [tv], "the selected renderer stays listed and checked")
        try model.select(id: nil)
        XCTAssertNil(model.selectedID)
    }
}
