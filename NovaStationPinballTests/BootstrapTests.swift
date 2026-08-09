import XCTest

final class BootstrapTests: XCTestCase {
    func testUnitTestBundleLoads() {
        XCTAssertNotNil(Bundle.main.bundleIdentifier)
    }
}
