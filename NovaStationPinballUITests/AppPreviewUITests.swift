import XCTest

@MainActor
final class AppPreviewUITests: XCTestCase {
    func testDeterministicTwentyFourSecondPreviewTimeline() {
        XCUIDevice.shared.orientation = .landscapeRight
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
        }
        Thread.sleep(forTimeInterval: 4)
    }
}
