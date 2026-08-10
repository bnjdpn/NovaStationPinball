import XCTest

@MainActor
final class LayoutUITests: XCTestCase {
    func testCompleteFourByThreeFrameAndTableConsoleRatio() {
        XCUIDevice.shared.orientation = .landscapeRight
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing"]
        app.launch()

        XCTAssertFalse(app.statusBars.firstMatch.exists, "Immersive pinball must not expose system status chrome")

        let frame = app.otherElements["art.frame.4x3"]
        let table = app.otherElements["art.table"]
        let console = app.otherElements["art.console"]

        XCTAssertTrue(frame.waitForExistence(timeout: 5))
        XCTAssertTrue(table.exists)
        XCTAssertTrue(console.exists)
        XCTAssertEqual(frame.frame.width / frame.frame.height, 4.0 / 3.0, accuracy: 0.02)
        XCTAssertEqual(table.frame.width / frame.frame.width, 0.70, accuracy: 0.02)
        XCTAssertEqual(console.frame.width / frame.frame.width, 0.30, accuracy: 0.02)
        XCTAssertEqual(table.frame.height, frame.frame.height, accuracy: 1)
        XCTAssertEqual(console.frame.height, frame.frame.height, accuracy: 1)
        XCTAssertGreaterThanOrEqual(frame.frame.minX, app.frame.minX - 1)
        XCTAssertGreaterThanOrEqual(frame.frame.minY, app.frame.minY - 1)
        XCTAssertLessThanOrEqual(frame.frame.maxX, app.frame.maxX + 1)
        XCTAssertLessThanOrEqual(frame.frame.maxY, app.frame.maxY + 1)
        XCTAssertEqual(table.frame.minX, frame.frame.minX, accuracy: 1)
        XCTAssertEqual(console.frame.maxX, frame.frame.maxX, accuracy: 1)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "raster-layout-landscape"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testTableGuideNavigatesEveryStepAndCloses() {
        XCUIDevice.shared.orientation = .landscapeRight
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing"]
        app.launch()

        let open = app.buttons["tableGuideOpen"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()

        XCTAssertTrue(app.otherElements["tableGuideStep.controls"].waitForExistence(timeout: 3))

        let next = app.buttons["tableGuideNext"]
        XCTAssertTrue(next.exists)
        next.tap()
        XCTAssertTrue(app.otherElements["tableGuideStep.missions"].waitForExistence(timeout: 3))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "interactive-table-guide-missions"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        next.tap()
        XCTAssertTrue(app.otherElements["tableGuideStep.progress"].waitForExistence(timeout: 3))

        let done = app.buttons["tableGuideDone"]
        XCTAssertTrue(done.exists)
        done.tap()

        XCTAssertFalse(app.otherElements["tableGuide"].waitForExistence(timeout: 1))
        XCTAssertTrue(open.waitForExistence(timeout: 2))
    }
}
