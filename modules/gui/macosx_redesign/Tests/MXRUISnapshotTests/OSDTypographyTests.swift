import MXRDesign
import XCTest

final class OSDTypographyTests: XCTestCase {
    func testOSDUsesReadableMinimumAndScalesWithVideoHeight() {
        let minimum = Theme.OSD.styles(videoHeight: 200)
        XCTAssertEqual(minimum.title.size, 24)
        XCTAssertEqual(minimum.key.size, 20)
        let large = Theme.OSD.styles(videoHeight: 1080)
        XCTAssertEqual(large.title.size, 54)
        XCTAssertEqual(large.key.size, 45)
        XCTAssertEqual(large.title.name, "osdTitle")
        XCTAssertEqual(large.key.name, "osdKey")
    }
}
