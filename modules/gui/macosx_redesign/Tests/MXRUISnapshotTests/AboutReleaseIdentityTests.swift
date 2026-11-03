@testable import MXRUI
import XCTest

/// Release 1.0 (D058): About names the app's own version and, separately, the VLC engine's, and says
/// the build is unofficial and not affiliated with VideoLAN while keeping VideoLAN's copyright.
final class AboutReleaseIdentityTests: XCTestCase {
    func testAboutShowsAppVersionThenEngineVersion() {
        XCTAssertEqual(MXRAboutView.versionLines(app: "1.0.0", engine: "4.0.0-dev"),
                       ["Version 1.0.0", "VLC engine 4.0.0-dev"])
        XCTAssertEqual(MXRAboutView.versionLines(app: nil, engine: "4.0.0-dev"), ["VLC engine 4.0.0-dev"],
                       "outside a bundle (gallery, tests) the engine version still shows")
        XCTAssertEqual(MXRAboutView.versionLines(app: "1.0.0", engine: nil), ["Version 1.0.0"])
    }

    func testAboutSaysUnofficialAndKeepsVideoLANCopyright() {
        XCTAssertTrue(MXRAboutView.unofficialNotice.contains("Unofficial"))
        XCTAssertTrue(MXRAboutView.unofficialNotice.lowercased().contains("not affiliated"))
        XCTAssertTrue(MXRAboutView.unofficialNotice.contains("VideoLAN"))
        XCTAssertTrue(MXRAboutView.engineCopyright.contains("© 1996–2026 VLC authors and VideoLAN"))
    }

    /// The years must follow upstream's `COPYRIGHT_YEARS`, or About would contradict Info.plist.
    func testEngineCopyrightYearsMatchConfigure() throws {
        let configure = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("../../../../../configure.ac").standardized
        let text = try String(contentsOf: configure, encoding: .utf8)
        let years = try XCTUnwrap(text.firstMatch(of: /COPYRIGHT_YEARS="([0-9]{4})-([0-9]{4})"/))
        XCTAssertTrue(MXRAboutView.engineCopyright.contains("\(years.1)–\(years.2)"))
    }

    /// 1.0.1: About ▸ Licenses opens the notices the packaging hook writes into the app.
    func testAboutLicensesLinkOpensBundledAcknowledgements() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("mxr-about-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: scratch.appendingPathComponent("Contents/Resources"),
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let notices = scratch.appendingPathComponent("Contents/Resources/Acknowledgements.txt")
        try Data("notices".utf8).write(to: notices)
        let bundle = try XCTUnwrap(Bundle(url: scratch))
        XCTAssertEqual(MXRAboutView.licensesURL(in: bundle).standardizedFileURL.path,
                       notices.standardizedFileURL.path)
        let fallback = MXRAboutView.licensesURL(in: Bundle(for: Self.self))
        XCTAssertEqual(fallback.host, "github.com", "without the file the link points at the same texts in the source")
        XCTAssertTrue(fallback.path.hasSuffix("macosx_redesign/Resources/licenses"))
    }
}
