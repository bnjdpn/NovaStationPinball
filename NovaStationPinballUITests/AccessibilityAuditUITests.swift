import Foundation
import XCTest

@MainActor
final class AccessibilityAuditUITests: XCTestCase {
    func testEnglishVoiceOverSurfaceAndSystemAccessibilityAudit() throws {
        let app = launch(language: "en", locale: "en_US")

        XCTAssertEqual(app.otherElements["art.frame.4x3"].label, "Complete Nova Station playfield")
        XCTAssertEqual(app.otherElements["art.table"].label, "Nova Station pinball table")
        XCTAssertEqual(app.otherElements["art.console"].label, "Nova Station status console")
        XCTAssertEqual(app.buttons["workshopOpen"].label, "Workshop")
        let value = try XCTUnwrap(app.otherElements["art.console"].value as? String)
        XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        try performStrictAccessibilityAudit(in: app)

        app.buttons["workshopOpen"].tap()
        XCTAssertTrue(app.alerts["workshop"].waitForExistence(timeout: 3))
        assertWorkshopSurface(
            in: app,
            title: "Workshop",
            close: "Close the Workshop",
            drillIdentifier: "ramp-left"
        )
        try performStrictAccessibilityAudit(in: app, clippedBy: scrollRegion(app, "workshopScroll"))
    }

    func testFrenchVoiceOverSurfaceAndSystemAccessibilityAudit() throws {
        let app = launch(language: "fr", locale: "fr_FR")

        XCTAssertEqual(app.otherElements["art.frame.4x3"].label, "Plateau complet de Nova Station")
        XCTAssertEqual(app.otherElements["art.table"].label, "Flipper Nova Station")
        XCTAssertEqual(app.otherElements["art.console"].label, "Console d’état Nova Station")
        XCTAssertEqual(app.buttons["workshopOpen"].label, "Atelier")
        let value = try XCTUnwrap(app.otherElements["art.console"].value as? String)
        XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        try performStrictAccessibilityAudit(in: app)

        app.buttons["workshopOpen"].tap()
        XCTAssertTrue(app.alerts["workshop"].waitForExistence(timeout: 3))
        assertWorkshopSurface(
            in: app,
            title: "Atelier",
            close: "Fermer l’Atelier",
            drillIdentifier: "ramp-left"
        )
        try performStrictAccessibilityAudit(in: app, clippedBy: scrollRegion(app, "workshopScroll"))
    }

    func testEnglishPaywallSurfaceAndSystemAccessibilityAudit() throws {
        let app = launchPaywall(language: "en", locale: "en_US")

        assertPaywallSurface(
            in: app,
            title: "The Workshop",
            close: "Close",
            offerLabel: "The Workshop, $4.99"
        )
        try performStrictAccessibilityAudit(in: app, clippedBy: scrollRegion(app, "paywallScroll"))
    }

    func testFrenchPaywallSurfaceAndSystemAccessibilityAudit() throws {
        let app = launchPaywall(language: "fr", locale: "fr_FR")

        assertPaywallSurface(
            in: app,
            title: "L’Atelier",
            close: "Fermer",
            offerLabel: "L’Atelier, 4,99 €"
        )
        try performStrictAccessibilityAudit(in: app, clippedBy: scrollRegion(app, "paywallScroll"))
    }

    /// The running drill is a screen of its own: it appears over the table,
    /// it is read by VoiceOver, and it carries the two controls that end the
    /// attempt. It is audited in both shipped languages.
    func testDecidedDrillSurfaceAndSystemAccessibilityAudit() throws {
        for (language, locale, name, retry, exit, verdict) in [
            ("en", "en_US", "Left ramp", "Serve again", "Leave the drill", "Attempt over"),
            ("fr", "fr_FR", "Rampe gauche", "Recommencer", "Quitter l’atelier", "Tentative terminée")
        ] {
            let app = launch(language: language, locale: locale)
            startDrill("ramp-left", in: app)

            let status = app.staticTexts["workshopDrillStatus"]
            XCTAssertEqual(app.staticTexts["workshopDrillName"].label, name)
            XCTAssertEqual(app.buttons["workshopDrillRetry"].label, retry)
            XCTAssertEqual(app.buttons["workshopDrillExit"].label, exit)
            XCTAssertFalse(status.label.contains("%"), status.label)
            for identifier in ["workshopDrillRetry", "workshopDrillExit"] {
                XCTAssertGreaterThanOrEqual(app.buttons[identifier].frame.height.rounded(), 44, identifier)
            }

            // The audit is run on the decided attempt: the panel is then a
            // still surface, and it is the state the player actually reads
            // before deciding to serve again or leave.
            let decided = expectation(
                for: NSPredicate(format: "label CONTAINS %@", verdict),
                evaluatedWith: status
            )
            wait(for: [decided], timeout: 45)
            // Apple's audit crashes in its own logging path
            // (-[AXAuditCategoryResult appendLog:] -> strlen(NULL)) as soon as
            // it resizes text on a screen carrying this panel, so the two
            // resizing categories are replaced below by an explicit
            // large-text pass rather than silently skipped.
            // Apple's own audit crashes in its logging path
            // (-[AXAuditCategoryResult appendLog:] reaching strlen(NULL)) as
            // soon as it resizes text on a screen carrying this panel, on
            // Xcode 26.2. The two resizing categories are therefore replaced
            // by testDrillPanelStaysReachableAtTheLargestTextSize below, which
            // checks the same property explicitly, instead of being skipped.
            try performStrictAccessibilityAudit(
                in: app,
                types: [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription]
            )

            app.buttons["workshopDrillExit"].tap()
            XCTAssertFalse(app.otherElements["workshopDrillHUD"].waitForExistence(timeout: 3))
            app.terminate()
        }
    }

    /// What the resizing audit categories would have checked, checked here:
    /// at the largest accessibility text size the panel still fits the screen
    /// and both of its controls stay reachable.
    func testDrillPanelStaysReachableAtTheLargestTextSize() {
        XCUIDevice.shared.orientation = .landscapeRight
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-AppleLanguages", "(fr)",
            "-AppleLocale", "fr_FR",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        XCTAssertTrue(app.otherElements["art.frame.4x3"].waitForExistence(timeout: 5))
        startDrill("ramp-left", in: app)

        let screen = app.frame
        for identifier in ["workshopDrillName", "workshopDrillStatus", "workshopDrillRecord"] {
            let element = app.staticTexts[identifier]
            XCTAssertTrue(element.exists, identifier)
            XCTAssertTrue(screen.contains(element.frame), "\(identifier) \(element.frame) leaves \(screen)")
            XCTAssertFalse(element.label.hasSuffix("…"), element.label)
        }
        for identifier in ["workshopDrillRetry", "workshopDrillExit"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.exists, identifier)
            XCTAssertTrue(screen.contains(button.frame), "\(identifier) \(button.frame) leaves \(screen)")
            XCTAssertGreaterThanOrEqual(button.frame.height.rounded(), 44, identifier)
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "drill-panel-accessibility-text"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["workshopDrillExit"].tap()
        XCTAssertFalse(app.otherElements["workshopDrillHUD"].waitForExistence(timeout: 3))
    }

    private func assertWorkshopSurface(
        in app: XCUIApplication,
        title: String,
        close: String,
        drillIdentifier: String
    ) {
        XCTAssertEqual(app.alerts["workshop"].label, title)
        XCTAssertEqual(app.staticTexts["workshopTitle"].label, title)
        XCTAssertEqual(app.buttons["workshopClose"].label, close)
        XCTAssertGreaterThanOrEqual(app.buttons["workshopClose"].frame.width.rounded(), 44)
        XCTAssertGreaterThanOrEqual(app.buttons["workshopClose"].frame.height.rounded(), 44)
        XCTAssertTrue(app.buttons["workshopRewind.ball-start"].exists)
        XCTAssertTrue(app.buttons["workshopDrill.\(drillIdentifier)"].exists)
        // The playfield leaves the accessibility surface entirely.
        XCTAssertFalse(app.otherElements["art.frame.4x3"].exists)
        XCTAssertFalse(app.otherElements["art.table"].exists)
        XCTAssertFalse(app.otherElements["art.console"].exists)
    }

    private func assertPaywallSurface(
        in app: XCUIApplication,
        title: String,
        close: String,
        offerLabel: String
    ) {
        XCTAssertTrue(app.alerts["paywall"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts["paywall"].label, title)
        XCTAssertEqual(app.staticTexts["paywallTitle"].label, title)
        XCTAssertEqual(app.buttons["paywallClose"].label, close)
        XCTAssertGreaterThanOrEqual(app.buttons["paywallClose"].frame.width.rounded(), 44)
        XCTAssertGreaterThanOrEqual(app.buttons["paywallClose"].frame.height.rounded(), 44)

        let purchase = app.buttons["paywallPurchase"]
        XCTAssertTrue(purchase.waitForExistence(timeout: 5))
        XCTAssertEqual(purchase.label, offerLabel)
        XCTAssertTrue(app.buttons["paywallRestore"].exists)
        XCTAssertTrue(app.staticTexts["paywallTerms"].exists)
        XCTAssertTrue(element(app, "paywallTermsLink").waitForExistence(timeout: 3))
        XCTAssertTrue(element(app, "paywallPrivacyLink").waitForExistence(timeout: 3))
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The scrolling region of a modal, identified in `RootView`, so the clip
    /// edge below is measured instead of guessed.
    private func scrollRegion(_ app: XCUIApplication, _ identifier: String) -> CGRect? {
        let region = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        guard region.exists else { return nil }
        let frame = region.frame
        // A collapsed scroll region would excuse every issue on the screen, so
        // it is a layout bug to report, never an exemption to grant.
        XCTAssertGreaterThan(frame.height, 44, "\(identifier) collapsed: its content is not reachable")
        XCTAssertGreaterThan(frame.width, 44, "\(identifier) collapsed: its content is not reachable")
        return frame
    }

    /// Nothing is excused on a screen the player reads in full. The single
    /// exception is a row cut in half by the bottom edge of a modal's scroll
    /// area: the system contrast sampler reads a partial glyph run there and
    /// reports a failure for a control the player scrolls into view intact.
    /// The exception is measured, never assumed — the element frame has to
    /// actually leave the scroll region's own rectangle, and it only ever
    /// applies to contrast.
    private func performStrictAccessibilityAudit(
        in app: XCUIApplication,
        clippedBy contentRect: CGRect? = nil,
        types: XCUIAccessibilityAuditType = .all
    ) throws {

        try app.performAccessibilityAudit(for: types) { issue in
            let elementFrame = issue.element?.frame
            let isClippedByScrollEdge = issue.auditType == .contrast
                && contentRect.map { rect in
                    elementFrame.map { !rect.contains($0) } ?? false
                } ?? false

            let diagnostic = [
                "auditType=\(String(describing: issue.auditType))",
                "compact=\(issue.compactDescription)",
                "detail=\(issue.detailedDescription)",
                "clippedByScrollEdge=\(isClippedByScrollEdge)",
                "contentRect=\(String(describing: contentRect))",
                "element=\(issue.element?.debugDescription ?? "<nil>")"
            ].joined(separator: "\n")

            print("NOVA_ACCESSIBILITY_AUDIT_ISSUE\n\(diagnostic)")
            guard !isClippedByScrollEdge else { return true }

            XCTContext.runActivity(named: "Unexpected accessibility audit issue") { activity in
                let attachment = XCTAttachment(string: diagnostic)
                attachment.name = "accessibility-audit-issue.txt"
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
            return false
        }
    }

    private func launch(language: String, locale: String) -> XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeRight
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale
        ]
        app.launch()
        XCTAssertTrue(app.otherElements["art.frame.4x3"].waitForExistence(timeout: 5))
        return app
    }

    /// The paywall capture never uses the store bypass: it must show the real
    /// locked offer, with its name and price coming from the fixture the way
    /// they come from StoreKit.Product in production.
    private func launchPaywall(language: String, locale: String) -> XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeRight
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-paywall-screenshot",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale
        ]
        app.launchEnvironment["NOVA_STORE_FIXTURE"] = "available"
        app.launch()
        return app
    }
}
