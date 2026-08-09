import Foundation
import XCTest

@MainActor
final class AccessibilityAuditUITests: XCTestCase {
    func testEnglishVoiceOverSurfaceAndSystemAccessibilityAudit() throws {
        let app = launch(language: "en", locale: "en_US")

        XCTAssertEqual(app.otherElements["art.frame.4x3"].label, "Complete Nova Station playfield")
        XCTAssertEqual(app.otherElements["art.table"].label, "Nova Station pinball table")
        XCTAssertEqual(app.otherElements["art.console"].label, "Nova Station status console")
        let value = try XCTUnwrap(app.otherElements["art.console"].value as? String)
        XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        try app.performAccessibilityAudit()
    }

    func testFrenchVoiceOverSurfaceAndSystemAccessibilityAudit() throws {
        let app = launch(language: "fr", locale: "fr_FR")

        XCTAssertEqual(app.otherElements["art.frame.4x3"].label, "Plateau complet de Nova Station")
        XCTAssertEqual(app.otherElements["art.table"].label, "Flipper Nova Station")
        XCTAssertEqual(app.otherElements["art.console"].label, "Console d’état Nova Station")
        let value = try XCTUnwrap(app.otherElements["art.console"].value as? String)
        XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        try app.performAccessibilityAudit()
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
}
