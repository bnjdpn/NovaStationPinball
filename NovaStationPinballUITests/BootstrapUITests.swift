import XCTest

@MainActor
final class BootstrapUITests: XCTestCase {
    func testApplicationCanBeDeclared() {
        XCTAssertNotNil(XCUIApplication())
    }
}
