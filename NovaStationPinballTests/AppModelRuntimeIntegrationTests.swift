import Foundation
import NovaStationCore
import XCTest
@testable import NovaStationPinball

@MainActor
final class AppModelRuntimeIntegrationTests: XCTestCase {
    func testOrdinaryLaunchGestureStartsTheAuthoritativeGameSession() throws {
        let harness = try RuntimeHarness()
        defer { harness.cleanup() }
        harness.activate()

        XCTAssertEqual(harness.model.gamePhase, .launch)
        XCTAssertTrue(harness.model.scene.currentSnapshot.balls.isEmpty)

        harness.model.apply([.plungerReleased(0.8)])

        XCTAssertEqual(harness.model.gamePhase, .playing)
        XCTAssertEqual(harness.model.scene.currentSnapshot.balls.count, 1)
        XCTAssertEqual(harness.model.ballsInPlay, 1)
        XCTAssertEqual(harness.model.takeSimulationInput().commands, [.releasePlunger(strength: 0.8)])
    }

    func testModelConsumesLiveRulesMissionAndClearanceFromSessionFrame() throws {
        let harness = try RuntimeHarness()
        defer { harness.cleanup() }
        let session = try MediaScenario.promotion.makeSession()

        harness.model.receive(sessionFrame: GameSessionFrame(
            snapshot: session.snapshot,
            rules: session.rules,
            phase: session.phase,
            events: [],
            effects: []
        ))

        XCTAssertEqual(harness.model.score, session.rules.score)
        XCTAssertEqual(harness.model.missionState, .completed(.orbitalWake))
        XCTAssertEqual(harness.model.clearance, .dockKey)
    }

    func testGameOverPersistsAndSubmitsExactlyOnceBeforeAllowingANewGame() throws {
        let client = RuntimeRecordingGameCenterClient()
        let harness = try RuntimeHarness(gameCenterClient: client)
        defer { harness.cleanup() }
        let session = try MediaScenario.gameOver.makeSession()
        let frame = GameSessionFrame(
            snapshot: session.snapshot,
            rules: session.rules,
            phase: session.phase,
            events: [],
            effects: [.gameOver(session.rules.score)]
        )

        harness.model.receive(sessionFrame: frame)
        harness.model.receive(sessionFrame: frame)

        XCTAssertEqual(try harness.store.loadHighScores().count, 1)
        XCTAssertEqual(client.submittedScores, [session.rules.score])
        XCTAssertEqual(harness.model.gamePhase, .gameOver)

        harness.activate()
        harness.model.apply([.plungerReleased(1)])
        XCTAssertEqual(harness.model.gamePhase, .playing)
    }

    func testMediaScenarioReplacesTheRealDriverSessionWithoutDecorativeState() throws {
        let harness = try RuntimeHarness(
            mediaLaunchConfiguration: MediaLaunchConfiguration(
                arguments: ["app", "-ui-testing", "-media-scenario", "multiball"]
            )
        )
        defer { harness.cleanup() }

        harness.model.applyMediaScenario(.multiball)

        XCTAssertEqual(harness.model.gamePhase, .playing)
        XCTAssertEqual(harness.model.ballsInPlay, 3)
        XCTAssertEqual(harness.model.scene.currentSnapshot.balls.count, 3)
    }

    func testTableGuidePausesAndResumesATableThatWasRunning() throws {
        let harness = try RuntimeHarness()
        defer { harness.cleanup() }
        harness.activate()

        XCTAssertFalse(harness.model.isSimulationPaused)

        harness.model.beginTableGuide()

        XCTAssertTrue(harness.model.isSimulationPaused)

        harness.model.endTableGuide()

        XCTAssertFalse(harness.model.isSimulationPaused)
    }

    func testTableGuidePreservesAnExistingUserPause() throws {
        let harness = try RuntimeHarness()
        defer { harness.cleanup() }
        harness.activate()
        harness.model.togglePauseFromAccessibility()

        XCTAssertTrue(harness.model.isSimulationPaused)

        harness.model.beginTableGuide()
        harness.model.endTableGuide()

        XCTAssertTrue(harness.model.isSimulationPaused)
    }

    func testTableGuideKeepsSystemPausedTableStoppedUntilDismissal() throws {
        let harness = try RuntimeHarness()
        defer { harness.cleanup() }
        harness.model.lifecycleCoordinator.start()

        XCTAssertTrue(harness.model.isSimulationPaused)

        harness.model.beginTableGuide()
        harness.model.setApplicationActivity(.active)

        XCTAssertTrue(harness.model.isSimulationPaused)

        harness.model.endTableGuide()

        XCTAssertFalse(harness.model.isSimulationPaused)
    }

    func testTableGuideDoesNotOverrideAnAudioInterruptionThatForbidsResume() throws {
        let harness = try RuntimeHarness()
        defer { harness.cleanup() }
        harness.activate()
        harness.model.beginTableGuide()

        harness.model.audioInterruptionBegan()
        harness.model.audioInterruptionEnded(shouldResume: false)
        harness.model.endTableGuide()

        XCTAssertTrue(harness.model.isSimulationPaused)
        XCTAssertTrue(harness.model.lifecycleCoordinator.isUserPaused)
        XCTAssertFalse(harness.model.lifecycleCoordinator.isTableGuidePresented)
    }
}

@MainActor
private final class RuntimeHarness {
    let model: AppModel
    let store: LocalGameStore
    private let defaults: UserDefaults
    private let suiteName: String
    private let directory: URL

    init(
        gameCenterClient: any GameCenterClient = NullGameCenterClient(),
        mediaLaunchConfiguration: MediaLaunchConfiguration = MediaLaunchConfiguration(arguments: ["app"])
    ) throws {
        suiteName = "AppModelRuntimeIntegrationTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName)
        store = LocalGameStore(defaults: defaults, directory: directory)
        model = AppModel(
            audioEngine: NullAudioEngine(),
            hapticsService: NullHapticsService(),
            gameCenterClient: gameCenterClient,
            localGameStore: store,
            tipJarSupport: NullTipJarSupport(),
            mediaLaunchConfiguration: mediaLaunchConfiguration
        )
    }

    func activate() {
        model.setApplicationActivity(.active)
        model.lifecycleCoordinator.start()
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class RuntimeRecordingGameCenterClient: GameCenterClient {
    var isAvailable: Bool { true }
    var isAuthenticated: Bool { true }
    private(set) var submittedScores: [Int] = []
    func authenticate() {}
    func submit(score: Int) { submittedScores.append(score) }
}
