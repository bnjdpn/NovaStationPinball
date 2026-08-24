import XCTest

@MainActor
final class StoreScreenshotUITests: XCTestCase {
    func test01Launch() { capture("launch", checksOwnedWorkshopPrivacy: true) }
    func test02Mission() { capture("mission", opensTableGuide: true) }
    func test03Promotion() { capture("promotion") }
    func test04Multiball() { capture("multiball") }
    func test05Tilt() { capture("tilt") }
    func test06GameOver() { capture("game-over") }

    private func capture(
        _ scenario: String,
        opensTableGuide: Bool = false,
        checksOwnedWorkshopPrivacy: Bool = false
    ) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeRight
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-media-scenario", scenario]
        app.launch()

        XCTAssertTrue(app.otherElements["art.frame.4x3"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.otherElements["media.scenario.\(scenario)"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["workshopOpen"].waitForExistence(timeout: 3))
        if opensTableGuide {
            let open = app.buttons["tableGuideOpen"]
            XCTAssertTrue(open.waitForExistence(timeout: 3))
            open.tap()
            XCTAssertTrue(app.otherElements["tableGuideStep.controls"].waitForExistence(timeout: 3))
            let forward = guideForwardControl(in: app)
            XCTAssertTrue(forward.waitForExistence(timeout: 3))
            forward.tap()
            XCTAssertTrue(app.otherElements["tableGuideStep.missions"].waitForExistence(timeout: 3))
            assertGuideCopyFitsAboveNavigation(in: app)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "screenshot-\(scenario)"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        if checksOwnedWorkshopPrivacy {
            // `-ui-testing` owns the Workshop through the DEBUG-only bypass.
            // The privacy policy must therefore remain reachable after a
            // purchase, not only from the locked paywall.
            app.buttons["workshopOpen"].tap()
            let privacy = app.descendants(matching: .any)
                .matching(identifier: "workshopPrivacyLink")
                .firstMatch
            let support = app.descendants(matching: .any)
                .matching(identifier: "workshopSupportLink")
                .firstMatch
            XCTAssertTrue(privacy.waitForExistence(timeout: 3))
            XCTAssertTrue(privacy.isHittable)
            XCTAssertTrue(support.waitForExistence(timeout: 3))
            XCTAssertTrue(support.isHittable)
        }
    }

    private func assertGuideCopyFitsAboveNavigation(in app: XCUIApplication) {
        let title = app.staticTexts["tableGuideStepTitle"]
        let body = app.staticTexts["tableGuideStepBody"]
        let next = guideForwardControl(in: app)

        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertTrue(body.waitForExistence(timeout: 3))
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        XCTAssertFalse(title.frame.isEmpty)
        XCTAssertFalse(body.frame.isEmpty)
        XCTAssertLessThanOrEqual(
            body.frame.maxY,
            next.frame.minY - 8,
            "The complete mission guide copy must remain above the fixed navigation controls."
        )
    }

    /// Last control of the guide navigation row. SwiftUI collapses the child
    /// identifiers of the row into the row identifier on some runtimes, so the
    /// named button is only a fast path, never the contract.
    private func guideForwardControl(in app: XCUIApplication) -> XCUIElement {
        let row = app.buttons.matching(identifier: "tableGuideNavigation")
        if row.count > 0 { return row.element(boundBy: row.count - 1) }
        return app.buttons["tableGuideNext"]
    }
}
