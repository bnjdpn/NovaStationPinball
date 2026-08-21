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

        // SwiftUI collapses the navigation row's identifier onto its buttons
        // on current iOS, so the forward control is resolved through the row
        // itself — the same way AppPreviewUITests already does.
        let next = guideForwardControl(in: app)
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        next.tap()
        XCTAssertTrue(app.otherElements["tableGuideStep.missions"].waitForExistence(timeout: 3))
        let missionBody = app.staticTexts["tableGuideStepBody"]
        XCTAssertTrue(missionBody.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(missionBody.frame.maxY, next.frame.minY - 8)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "interactive-table-guide-missions"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        next.tap()
        XCTAssertTrue(app.otherElements["tableGuideStep.progress"].waitForExistence(timeout: 3))

        let done = guideForwardControl(in: app)
        XCTAssertTrue(done.exists)
        done.tap()

        XCTAssertFalse(app.otherElements["tableGuide"].waitForExistence(timeout: 1))
        XCTAssertTrue(open.waitForExistence(timeout: 2))
    }

    func testWorkshopExposesRewindReviewAndDrillsAndCloses() {
        XCUIDevice.shared.orientation = .landscapeRight
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        let open = app.buttons["workshopOpen"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()

        XCTAssertTrue(app.alerts["workshop"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["art.frame.4x3"].exists)
        XCTAssertFalse(app.otherElements["art.table"].exists)
        XCTAssertFalse(app.otherElements["art.console"].exists)
        XCTAssertGreaterThanOrEqual(app.buttons["workshopClose"].frame.width.rounded(), 44)
        XCTAssertGreaterThanOrEqual(app.buttons["workshopClose"].frame.height.rounded(), 44)

        for identifier in ["back-3", "back-5", "ball-start"] {
            XCTAssertTrue(
                app.buttons["workshopRewind.\(identifier)"].waitForExistence(timeout: 3),
                identifier
            )
        }
        XCTAssertTrue(app.buttons["workshopReview.ball-start"].exists)
        for identifier in ["ramp-left", "portal", "multiball"] {
            XCTAssertTrue(
                app.buttons["workshopDrill.\(identifier)"].waitForExistence(timeout: 3),
                identifier
            )
        }
        // Drill names are looked up in the catalog: a raw key on the screen
        // that sells the Workshop is a shipping defect, not a placeholder.
        XCTAssertTrue(app.buttons["workshopDrill.ramp-left"].label.contains("Left ramp"),
                      app.buttons["workshopDrill.ramp-left"].label)
        XCTAssertFalse(app.staticTexts["drill.ramp-left"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "workshop-overlay"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["workshopClose"].tap()
        XCTAssertFalse(app.alerts["workshop"].waitForExistence(timeout: 1))
        XCTAssertTrue(open.waitForExistence(timeout: 2))
    }

    /// The whole sold loop, on the device: start an attempt, watch it reach a
    /// verdict on screen, serve the same shot again, then leave the drill.
    func testDrillAttemptShowsItsCountdownVerdictRetryAndExit() {
        XCUIDevice.shared.orientation = .landscapeRight
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        let open = app.buttons["workshopOpen"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        startDrill("ramp-left", in: app)

        let hud = app.otherElements["workshopDrillHUD"]
        XCTAssertTrue(hud.exists)
        let status = app.staticTexts["workshopDrillStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("left in this attempt"), status.label)
        XCTAssertTrue(app.staticTexts["workshopDrillRecord"].exists)
        XCTAssertEqual(app.staticTexts["workshopDrillName"].label, "Left ramp")

        let retry = app.buttons["workshopDrillRetry"]
        let exit = app.buttons["workshopDrillExit"]
        XCTAssertTrue(retry.exists)
        XCTAssertTrue(exit.exists)
        XCTAssertGreaterThanOrEqual(retry.frame.height.rounded(), 44)
        XCTAssertGreaterThanOrEqual(exit.frame.height.rounded(), 44)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "drill-attempt-running"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        // The attempt budget is twenty simulated seconds and the table runs in
        // real time, so the verdict is waited for, never assumed.
        let decided = expectation(
            for: NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "Attempt over", "Target hit"),
            evaluatedWith: status
        )
        wait(for: [decided], timeout: 45)

        let verdict = XCTAttachment(screenshot: app.screenshot())
        verdict.name = "drill-attempt-decided"
        verdict.lifetime = .keepAlways
        add(verdict)

        retry.tap()
        let restarted = expectation(
            for: NSPredicate(format: "label CONTAINS %@", "left in this attempt"),
            evaluatedWith: status
        )
        wait(for: [restarted], timeout: 10)

        exit.tap()
        let left = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: hud)
        wait(for: [left], timeout: 10)
        XCTAssertTrue(open.waitForExistence(timeout: 5))
    }

    func testPaywallRendersProviderNameAndPriceWithRestoreAndLegalLinks() {
        XCUIDevice.shared.orientation = .landscapeRight
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-paywall-screenshot",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launchEnvironment["NOVA_STORE_FIXTURE"] = "available"
        app.launch()

        XCTAssertTrue(app.alerts["paywall"].waitForExistence(timeout: 8))
        let purchase = app.buttons["paywallPurchase"]
        XCTAssertTrue(purchase.waitForExistence(timeout: 8))
        XCTAssertTrue(purchase.label.contains("The Workshop"), purchase.label)
        XCTAssertTrue(purchase.label.contains("4.99"), purchase.label)
        XCTAssertTrue(app.buttons["paywallRestore"].exists)
        XCTAssertTrue(app.staticTexts["paywallTerms"].exists)
        XCTAssertTrue(element(app, "paywallTermsLink").waitForExistence(timeout: 3))
        XCTAssertTrue(element(app, "paywallPrivacyLink").waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(app.buttons["paywallClose"].frame.width.rounded(), 44)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "workshop-paywall"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["paywallClose"].tap()
        XCTAssertFalse(app.alerts["paywall"].waitForExistence(timeout: 1))
    }

    /// SwiftUI exposes `Link` as a button on some releases and as a link on
    /// others; the contract is the stable identifier, not the element type.
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Last control of the guide navigation row: "next" on the first steps,
    /// "done" on the last one.
    private func guideForwardControl(in app: XCUIApplication) -> XCUIElement {
        let named = app.buttons["tableGuideNext"]
        if named.exists { return named }
        let row = app.buttons.matching(identifier: "tableGuideNavigation")
        return row.element(boundBy: max(0, row.count - 1))
    }
}
