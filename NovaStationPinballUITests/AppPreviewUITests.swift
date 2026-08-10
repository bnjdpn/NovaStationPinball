import XCTest

@MainActor
final class AppPreviewUITests: XCTestCase {
    private enum SpringBoardSettle {
        static let initialDelaySeconds: TimeInterval = 30
        static let requiredContinuousAbsenceSeconds: TimeInterval = 5
        static let maximumObservationSeconds: TimeInterval = 30
        static let pollIntervalSeconds: TimeInterval = 0.25
        static let notificationIdentifier = "NotificationShortLookView"
    }

    func testDeterministicTwentyFourSecondPreviewTimeline() {
        XCUIDevice.shared.orientation = .landscapeRight
        guard waitForSpringBoardToSettle() else {
            XCTFail(
                "SpringBoard did not remain free of \(SpringBoardSettle.notificationIdentifier) " +
                "for \(SpringBoardSettle.requiredContinuousAbsenceSeconds) continuous seconds"
            )
            return
        }
        let scenarios = ["launch", "mission", "promotion", "multiball", "tilt", "game-over"]
        let token = ProcessInfo.processInfo.environment["NOVA_MEDIA_HANDSHAKE_TOKEN"] ?? ""
        let mediaLocale = ProcessInfo.processInfo.environment["NOVA_MEDIA_LOCALE"] ?? ""
        XCTAssertNotNil(token.range(of: #"\A[0-9a-f]{32}\z"#, options: .regularExpression))
        let language: String
        let appleLocale: String
        switch mediaLocale {
        case "en-US":
            language = "en"
            appleLocale = "en_US"
        case "fr-FR":
            language = "fr"
            appleLocale = "fr_FR"
        default:
            XCTFail("Unsupported App Preview locale: \(mediaLocale)")
            return
        }
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", appleLocale,
            "-media-preview-sequence",
            "-media-handshake-token", token
        ]
        app.launch()

        XCTAssertTrue(app.otherElements["art.frame.4x3"].waitForExistence(timeout: 8))
        for scenario in scenarios {
            XCTAssertTrue(
                app.otherElements["media.scenario.\(scenario)"].waitForExistence(timeout: 5),
                "Preview timeline did not reach \(scenario)"
            )
            if scenario == "mission" {
                XCTAssertTrue(
                    app.otherElements["tableGuideStep.missions"].waitForExistence(timeout: 2),
                    "Mission media segment must show the interactive table guide"
                )
                assertGuideCopyFitsAboveNavigation(in: app)
            } else {
                XCTAssertTrue(
                    app.buttons["tipJarOpen"].waitForExistence(timeout: 2),
                    "Shipping tips access must remain visible in \(scenario) media"
                )
            }
        }
        Thread.sleep(forTimeInterval: 4)
    }

    private func assertGuideCopyFitsAboveNavigation(in app: XCUIApplication) {
        let title = app.staticTexts["tableGuideStepTitle"]
        let body = app.staticTexts["tableGuideStepBody"]
        let navigation = app.descendants(matching: .any)
            .matching(identifier: "tableGuideNavigation")
            .firstMatch

        XCTAssertTrue(title.exists)
        XCTAssertTrue(body.exists)
        XCTAssertTrue(navigation.exists)
        XCTAssertFalse(title.frame.isEmpty)
        XCTAssertFalse(body.frame.isEmpty)
        XCTAssertLessThanOrEqual(
            body.frame.maxY,
            navigation.frame.minY - 8,
            "The complete mission guide copy must remain above the fixed navigation controls."
        )
    }

    private func waitForSpringBoardToSettle() -> Bool {
        let springBoard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        Thread.sleep(forTimeInterval: SpringBoardSettle.initialDelaySeconds)

        let deadline = Date().addingTimeInterval(SpringBoardSettle.maximumObservationSeconds)
        var continuouslyClearSince: Date?
        repeat {
            let notificationVisible =
                springBoard.otherElements[SpringBoardSettle.notificationIdentifier].exists
            let now = Date()
            if notificationVisible {
                continuouslyClearSince = nil
            } else if let clearSince = continuouslyClearSince {
                if now.timeIntervalSince(clearSince) >= SpringBoardSettle.requiredContinuousAbsenceSeconds {
                    return true
                }
            } else {
                continuouslyClearSince = now
            }
            Thread.sleep(forTimeInterval: SpringBoardSettle.pollIntervalSeconds)
        } while Date() < deadline
        return false
    }
}
