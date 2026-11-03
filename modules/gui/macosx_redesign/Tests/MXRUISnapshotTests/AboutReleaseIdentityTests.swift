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
}
