import Foundation
import XCTest

@MainActor
final class AccessibilityAuditUITests: XCTestCase {
    func testEnglishVoiceOverSurfaceAndSystemAccessibilityAudit() throws {
        let app = launch(language: "en", locale: "en_US")

        XCTAssertEqual(app.otherElements["art.frame.4x3"].label, "Complete Nova Station playfield")
        XCTAssertEqual(app.otherElements["art.table"].label, "Nova Station pinball table")
        XCTAssertEqual(app.otherElements["art.console"].label, "Nova Station status console")
        XCTAssertEqual(app.buttons["tipJarOpen"].label, "Support")
        let value = try XCTUnwrap(app.otherElements["art.console"].value as? String)
        XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        try performStrictAccessibilityAudit(in: app)

        app.buttons["tipJarOpen"].tap()
        XCTAssertTrue(app.alerts["tipJar"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["tipJarPurchase.tip.cafe"].waitForExistence(timeout: 3))
        assertTipJarSurface(
            in: app,
            title: "Optional tips",
            body: "Tips are optional and repeatable. They unlock no features or gameplay content.",
            close: "Close tips",
            offers: [
                ("tip.cafe", "Coffee", "$0.99"),
                ("tip.merci", "Big thanks", "$2.99"),
                ("tip.soutien", "Strong support", "$5.99")
            ]
        )
        try performStrictAccessibilityAudit(in: app)
    }

    func testFrenchVoiceOverSurfaceAndSystemAccessibilityAudit() throws {
        let app = launch(language: "fr", locale: "fr_FR")

        XCTAssertEqual(app.otherElements["art.frame.4x3"].label, "Plateau complet de Nova Station")
        XCTAssertEqual(app.otherElements["art.table"].label, "Flipper Nova Station")
        XCTAssertEqual(app.otherElements["art.console"].label, "Console d’état Nova Station")
        XCTAssertEqual(app.buttons["tipJarOpen"].label, "Soutenir")
        let value = try XCTUnwrap(app.otherElements["art.console"].value as? String)
        XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        try performStrictAccessibilityAudit(in: app)

        app.buttons["tipJarOpen"].tap()
        XCTAssertTrue(app.alerts["tipJar"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["tipJarPurchase.tip.cafe"].waitForExistence(timeout: 3))
        assertTipJarSurface(
            in: app,
            title: "Pourboires facultatifs",
            body: "Les pourboires sont facultatifs et répétables. Ils ne débloquent aucune fonctionnalité ni aucun contenu de jeu.",
            close: "Fermer les pourboires",
            offers: [
                ("tip.cafe", "Café", "0,99 €"),
                ("tip.merci", "Grand merci", "2,99 €"),
                ("tip.soutien", "Beau soutien", "5,99 €")
            ]
        )
        try performStrictAccessibilityAudit(in: app)
    }

    private func assertTipJarSurface(
        in app: XCUIApplication,
        title: String,
        body: String,
        close: String,
        offers: [(id: String, name: String, price: String)]
    ) {
        XCTAssertEqual(app.alerts["tipJar"].label, title)
        XCTAssertEqual(app.staticTexts["tipJarTitle"].label, title)
        XCTAssertEqual(app.staticTexts["tipJarBody"].label, body)
        XCTAssertEqual(app.buttons["tipJarClose"].label, close)

        for offer in offers {
            let button = app.buttons["tipJarPurchase.\(offer.id)"]
            XCTAssertEqual(button.label, "\(offer.name), \(offer.price)")
            XCTAssertTrue(button.isHittable)
        }
    }

    private func performStrictAccessibilityAudit(in app: XCUIApplication) throws {
        try app.performAccessibilityAudit { issue in
            let diagnostic = [
                "auditType=\(String(describing: issue.auditType))",
                "compact=\(issue.compactDescription)",
                "detail=\(issue.detailedDescription)",
                "element=\(issue.element?.debugDescription ?? "<nil>")"
            ].joined(separator: "\n")

            print("NOVA_ACCESSIBILITY_AUDIT_ISSUE\n\(diagnostic)")
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
        app.launchEnvironment["NOVA_TIP_JAR_FIXTURE"] = "available"
        app.launch()
        XCTAssertTrue(app.otherElements["art.frame.4x3"].waitForExistence(timeout: 5))
        return app
    }
}
