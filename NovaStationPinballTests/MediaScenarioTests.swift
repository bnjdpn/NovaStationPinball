import XCTest
#if SWIFT_PACKAGE
@testable import NovaStationLifecycle
#else
@testable import NovaStationPinball
#endif

@MainActor
final class MediaScenarioTests: XCTestCase {
    func testScenarioCatalogIsExactAndStable() {
        XCTAssertEqual(
            MediaScenario.allCases.map(\.rawValue),
            ["launch", "mission", "promotion", "multiball", "tilt", "game-over"]
        )
        XCTAssertEqual(MediaScenario.previewSegmentDuration, 4)
    }

    func testLaunchConfigurationAcceptsScenarioOnlyBehindUITestingFlag() {
        XCTAssertEqual(
            MediaLaunchConfiguration(arguments: ["app", "-ui-testing", "-media-scenario", "mission"]).scenario,
            .mission
        )
        XCTAssertNil(MediaLaunchConfiguration(arguments: ["app", "-media-scenario", "mission"]).scenario)
        XCTAssertNil(MediaLaunchConfiguration(arguments: ["app", "-ui-testing", "-media-scenario", "unknown"]).scenario)
    }

    func testPreviewSequenceIsAvailableOnlyToUITests() {
        XCTAssertTrue(MediaLaunchConfiguration(arguments: ["app", "-ui-testing", "-media-preview-sequence"]).runsPreviewSequence)
        XCTAssertFalse(MediaLaunchConfiguration(arguments: ["app", "-media-preview-sequence"]).runsPreviewSequence)
    }

    func testPaywallLaunchIsAvailableOnlyToUITests() {
        XCTAssertTrue(
            MediaLaunchConfiguration(arguments: ["app", "-ui-testing", "-paywall-screenshot"]).opensPaywall
        )
        XCTAssertFalse(
            MediaLaunchConfiguration(arguments: ["app", "-paywall-screenshot"]).opensPaywall
        )
    }

    func testPreviewHandshakeRequiresUITestingSequenceAndStrictToken() {
        let token = String(repeating: "a", count: 32)
        XCTAssertEqual(
            MediaLaunchConfiguration(arguments: ["app", "-ui-testing", "-media-preview-sequence", "-media-handshake-token", token]).handshakeToken,
            token
        )
        XCTAssertNil(MediaLaunchConfiguration(arguments: ["app", "-ui-testing", "-media-handshake-token", token]).handshakeToken)
        XCTAssertNil(MediaLaunchConfiguration(arguments: ["app", "-ui-testing", "-media-preview-sequence", "-media-handshake-token", "../forged"]).handshakeToken)
    }

    func testEveryScenarioDrivesTheRealSessionAndPhysicalBallSet() throws {
        let launch = try MediaScenario.launch.makeSession()
        XCTAssertEqual(launch.phase, .launch)
        XCTAssertTrue(launch.snapshot.balls.isEmpty)

        let mission = try MediaScenario.mission.makeSession()
        XCTAssertEqual(mission.phase, .playing)
        XCTAssertEqual(mission.rules.missionState, .active(.orbitalWake))
        XCTAssertEqual(mission.snapshot.balls.count, 1)

        let promotion = try MediaScenario.promotion.makeSession()
        XCTAssertEqual(promotion.rules.missionState, .completed(.orbitalWake))
        XCTAssertEqual(promotion.rules.clearance, .dockKey)

        let multiball = try MediaScenario.multiball.makeSession()
        XCTAssertEqual(multiball.rules.ballsInPlay, 3)
        XCTAssertEqual(multiball.snapshot.balls.count, 3)
        XCTAssertEqual(Set(multiball.snapshot.balls.map(\.id)).count, 3)

        let tilt = try MediaScenario.tilt.makeSession()
        XCTAssertTrue(tilt.rules.isTilted)
        XCTAssertEqual(tilt.snapshot.balls.count, 1)

        let gameOver = try MediaScenario.gameOver.makeSession()
        XCTAssertEqual(gameOver.phase, .gameOver)
        XCTAssertTrue(gameOver.rules.isGameOver)
        XCTAssertEqual(gameOver.rules.ballsRemaining, 0)
        XCTAssertTrue(gameOver.snapshot.balls.isEmpty)
    }

    func testPreviewSessionsArePreparedAsTheExactScenarioCatalog() throws {
        let sessions = try MediaScenario.preparePreviewSessions()

        XCTAssertEqual(Set(sessions.keys), Set(MediaScenario.allCases))
        XCTAssertEqual(sessions[.launch]?.phase, .launch)
        XCTAssertEqual(sessions[.mission]?.rules.missionState, .active(.orbitalWake))
        XCTAssertEqual(sessions[.multiball]?.rules.ballsInPlay, 3)
        XCTAssertEqual(sessions[.gameOver]?.phase, .gameOver)
    }

}
