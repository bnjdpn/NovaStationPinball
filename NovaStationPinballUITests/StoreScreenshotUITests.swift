import XCTest

@MainActor
final class StoreScreenshotUITests: XCTestCase {
    func test01Launch() { capture("launch") }
    func test02Mission() { capture("mission", opensTableGuide: true) }
    func test03Promotion() { capture("promotion") }
    func test04Multiball() { capture("multiball") }
    func test05Tilt() { capture("tilt") }
    func test06GameOver() { capture("game-over") }

    private func capture(_ scenario: String, opensTableGuide: Bool = false) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeRight
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-media-scenario", scenario]
        app.launch()

        XCTAssertTrue(app.otherElements["art.frame.4x3"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.otherElements["media.scenario.\(scenario)"].waitForExistence(timeout: 3))
        if opensTableGuide {
            let open = app.buttons["tableGuideOpen"]
            XCTAssertTrue(open.waitForExistence(timeout: 3))
            open.tap()
            XCTAssertTrue(app.otherElements["tableGuideStep.controls"].waitForExistence(timeout: 3))
            app.buttons["tableGuideNext"].tap()
            XCTAssertTrue(app.otherElements["tableGuideStep.missions"].waitForExistence(timeout: 3))
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "screenshot-\(scenario)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
