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

    func testPreparedMediaScenarioReplacesTheDriverWithoutRebuildingTheSession() throws {
        let harness = try RuntimeHarness(
            mediaLaunchConfiguration: MediaLaunchConfiguration(
                arguments: ["app", "-ui-testing", "-media-scenario", "game-over"]
            )
        )
        defer { harness.cleanup() }
        let preparedSession = try MediaScenario.gameOver.makeSession()

        harness.model.applyMediaScenario(.gameOver, preparedSession: preparedSession)

        XCTAssertEqual(harness.model.gamePhase, .gameOver)
        XCTAssertEqual(harness.model.scene.currentPhase, .gameOver)
        XCTAssertTrue(harness.model.scene.currentSnapshot.balls.isEmpty)
    }

    // MARK: - Workshop

    func testAFreeRunGetsThreeRewindsAndThenMeetsThePaywall() throws {
        let harness = try RuntimeHarness()
        defer { harness.cleanup() }
        harness.activate()
        harness.model.apply([.plungerReleased(1)])
        harness.playForOneSecond(times: 8)

        XCTAssertEqual(harness.model.freeRewindsPerGame, 3)
        XCTAssertTrue(harness.model.canRewind(to: .threeSeconds))

        for expected in [2, 1, 0] {
            XCTAssertEqual(harness.model.rewind(to: .threeSeconds), .done)
            XCTAssertEqual(harness.model.remainingFreeRewinds, expected)
            harness.playForOneSecond(times: 8)
        }

        XCTAssertFalse(harness.model.canUseAnotherRewind)
        XCTAssertEqual(harness.model.rewind(to: .threeSeconds), .needsWorkshop)
    }

    func testAnOwnedWorkshopRewindsWithoutSpendingAnAllowance() throws {
        let harness = try RuntimeHarness(ownsWorkshop: true)
        defer { harness.cleanup() }
        harness.activate()
        harness.model.apply([.plungerReleased(1)])
        harness.playForOneSecond(times: 8)

        for _ in 0 ..< 5 {
            XCTAssertEqual(harness.model.rewind(to: .threeSeconds), .done)
            harness.playForOneSecond(times: 8)
        }

        XCTAssertEqual(harness.model.rewindsUsedThisGame, 0)
        XCTAssertTrue(harness.model.canUseAnotherRewind)
    }

    func testRewindingBeforeAnythingIsRecordedIsRefusedWithoutChargingTheAllowance() throws {
        let harness = try RuntimeHarness()
        defer { harness.cleanup() }
        harness.activate()

        XCTAssertEqual(harness.model.rewind(to: .fiveSeconds), .noKeyframe)
        XCTAssertEqual(harness.model.remainingFreeRewinds, 3)
    }

    func testARewoundGameIsRankedApartAndNeverSubmittedToGameCenter() throws {
        let client = RuntimeRecordingGameCenterClient()
        let harness = try RuntimeHarness(gameCenterClient: client)
        defer { harness.cleanup() }
        harness.activate()
        harness.model.apply([.plungerReleased(1)])
        harness.playForOneSecond(times: 8)
        XCTAssertEqual(harness.model.rewind(to: .threeSeconds), .done)

        let session = try MediaScenario.gameOver.makeSession()
        harness.model.receive(sessionFrame: GameSessionFrame(
            snapshot: session.snapshot,
            rules: session.rules,
            phase: session.phase,
            events: [],
            effects: [.gameOver(session.rules.score)]
        ))

        XCTAssertTrue(harness.model.isAssistedRun)
        XCTAssertTrue(try harness.store.loadHighScores().isEmpty)
        XCTAssertEqual(try harness.store.loadTrainingScores().count, 1)
        XCTAssertEqual(client.submittedScores, [])
        XCTAssertTrue(harness.store.isAssistedSessionMarked)
    }

    func testAnHonestGameStillReachesTheRankedBoardAndGameCenter() throws {
        let client = RuntimeRecordingGameCenterClient()
        let harness = try RuntimeHarness(gameCenterClient: client)
        defer { harness.cleanup() }
        let session = try MediaScenario.gameOver.makeSession()

        harness.model.receive(sessionFrame: GameSessionFrame(
            snapshot: session.snapshot,
            rules: session.rules,
            phase: session.phase,
            events: [],
            effects: [.gameOver(session.rules.score)]
        ))

        XCTAssertFalse(harness.model.isAssistedRun)
        XCTAssertEqual(try harness.store.loadHighScores().count, 1)
        XCTAssertTrue(try harness.store.loadTrainingScores().isEmpty)
        XCTAssertEqual(client.submittedScores, [session.rules.score])
    }

    func testStartingANewGameClearsTheAssistedMarkerAndTheAllowance() throws {
        let harness = try RuntimeHarness()
        defer { harness.cleanup() }
        harness.activate()
        harness.model.apply([.plungerReleased(1)])
        harness.playForOneSecond(times: 8)
        XCTAssertEqual(harness.model.rewind(to: .threeSeconds), .done)
        XCTAssertTrue(harness.model.isAssistedRun)

        let session = try MediaScenario.gameOver.makeSession()
        harness.model.receive(sessionFrame: GameSessionFrame(
            snapshot: session.snapshot,
            rules: session.rules,
            phase: .gameOver,
            events: [],
            effects: [.gameOver(session.rules.score)]
        ))
        harness.model.apply([.plungerReleased(1)])

        XCTAssertFalse(harness.model.isAssistedRun)
        XCTAssertFalse(harness.store.isAssistedSessionMarked)
        XCTAssertEqual(harness.model.rewindsUsedThisGame, 0)
        XCTAssertEqual(harness.model.gamePhase, .playing)
    }

    func testADrillNeedsTheWorkshopAndRecordsItsOwnStatistics() throws {
        let locked = try RuntimeHarness()
        defer { locked.cleanup() }
        let drill = try XCTUnwrap(ShotDrillCatalog.drill(id: "ramp-left"))
        XCTAssertEqual(locked.model.startDrill(drill), .needsWorkshop)

        let harness = try RuntimeHarness(ownsWorkshop: true)
        defer { harness.cleanup() }
        harness.activate()

        XCTAssertEqual(harness.model.startDrill(drill), .done)
        XCTAssertEqual(harness.model.activeDrill, drill)
        XCTAssertTrue(harness.model.isAssistedRun)
        XCTAssertEqual(harness.model.drillEntry(for: drill).attempts, 0)

        // Let the attempt run out of budget: the failure is recorded.
        harness.model.receive(
            sessionFrame: harness.model.scene.currentSessionFrame,
            steps: drill.maximumTicks
        )

        XCTAssertEqual(harness.model.activeDrillOutcome, .failed)
        XCTAssertEqual(harness.model.drillEntry(for: drill).attempts, 1)
        XCTAssertEqual(harness.model.drillEntry(for: drill).successes, 0)
        XCTAssertEqual(try harness.store.loadDrillProgress().entry(for: drill.id).attempts, 1)
        XCTAssertTrue(try harness.store.loadHighScores().isEmpty)
    }

    func testTheAttemptCountdownRetryAndExitCloseTheDrillLoop() throws {
        let harness = try RuntimeHarness(ownsWorkshop: true)
        defer { harness.cleanup() }
        harness.activate()
        let drill = try XCTUnwrap(ShotDrillCatalog.drill(id: "ramp-left"))

        XCTAssertEqual(harness.model.startDrill(drill), .done)
        XCTAssertEqual(harness.model.activeDrillRemainingSeconds, drill.maximumSeconds)
        XCTAssertTrue(harness.model.isRunningDrillAttempt)

        // Halfway through the budget the countdown is visibly running down.
        harness.model.receive(
            sessionFrame: harness.model.scene.currentSessionFrame,
            steps: drill.maximumTicks / 2
        )
        XCTAssertEqual(harness.model.activeDrillRemainingSeconds, drill.maximumSeconds / 2)
        XCTAssertTrue(harness.model.isRunningDrillAttempt)

        harness.model.receive(
            sessionFrame: harness.model.scene.currentSessionFrame,
            steps: drill.maximumTicks
        )
        XCTAssertEqual(harness.model.activeDrillOutcome, .failed)
        XCTAssertEqual(harness.model.activeDrillRemainingSeconds, 0)
        XCTAssertFalse(harness.model.isRunningDrillAttempt)
        XCTAssertEqual(harness.model.drillEntry(for: drill).attempts, 1)

        // Serving the same drill again restarts a full, undecided attempt.
        XCTAssertEqual(harness.model.restartActiveDrill(), .done)
        XCTAssertEqual(harness.model.activeDrill, drill)
        XCTAssertEqual(harness.model.activeDrillOutcome, .running)
        XCTAssertEqual(harness.model.activeDrillRemainingSeconds, drill.maximumSeconds)
        XCTAssertTrue(harness.model.isRunningDrillAttempt)

        // A second run out of budget is a second recorded attempt, so the
        // evaluator is genuinely reset and not latched.
        harness.model.receive(
            sessionFrame: harness.model.scene.currentSessionFrame,
            steps: drill.maximumTicks
        )
        XCTAssertEqual(harness.model.drillEntry(for: drill).attempts, 2)

        // Leaving hands back an ordinary, unassisted game.
        harness.model.endDrill()
        XCTAssertNil(harness.model.activeDrill)
        XCTAssertFalse(harness.model.isRunningDrillAttempt)
        XCTAssertEqual(harness.model.activeDrillRemainingSeconds, 0)
        XCTAssertFalse(harness.model.isAssistedRun)
        XCTAssertEqual(harness.model.rewindsUsedThisGame, 0)
        XCTAssertEqual(harness.model.restartActiveDrill(), .noKeyframe)
    }

    func testReviewingTheCurrentBallIsFreeAndTakingOverEndsIt() throws {
        let harness = try RuntimeHarness()
        defer { harness.cleanup() }
        harness.activate()
        harness.model.apply([.plungerReleased(1)])
        harness.playForOneSecond(times: 6)

        XCTAssertEqual(harness.model.reviewBall(from: .ballStart, speed: 0.5), .done)
        XCTAssertTrue(harness.model.isReviewingBall)
        XCTAssertEqual(harness.model.remainingFreeRewinds, 3, "reviewing must not cost a rewind")

        harness.model.resumeFromReview()
        XCTAssertFalse(harness.model.isReviewingBall)
    }

    func testReviewingFurtherBackIsPartOfTheWorkshop() throws {
        let harness = try RuntimeHarness()
        defer { harness.cleanup() }
        harness.activate()
        harness.model.apply([.plungerReleased(1)])
        harness.playForOneSecond(times: 8)

        XCTAssertEqual(harness.model.reviewBall(from: .fiveSeconds, speed: 1), .needsWorkshop)
    }

    func testTableGuidePausesAndResumesATableThatWasRunning() throws {
        let harness = try RuntimeHarness()
        defer { harness.cleanup() }
        harness.activate()

        XCTAssertFalse(harness.model.isSimulationPaused)

        harness.model.beginModalOverlay()

        XCTAssertTrue(harness.model.isSimulationPaused)

        harness.model.endModalOverlay()

        XCTAssertFalse(harness.model.isSimulationPaused)
    }

    func testTableGuidePreservesAnExistingUserPause() throws {
        let harness = try RuntimeHarness()
        defer { harness.cleanup() }
        harness.activate()
        harness.model.togglePauseFromAccessibility()

        XCTAssertTrue(harness.model.isSimulationPaused)

        harness.model.beginModalOverlay()
        harness.model.endModalOverlay()

        XCTAssertTrue(harness.model.isSimulationPaused)
    }

    func testTableGuideKeepsSystemPausedTableStoppedUntilDismissal() throws {
        let harness = try RuntimeHarness()
        defer { harness.cleanup() }
        harness.model.lifecycleCoordinator.start()

        XCTAssertTrue(harness.model.isSimulationPaused)

        harness.model.beginModalOverlay()
        harness.model.setApplicationActivity(.active)

        XCTAssertTrue(harness.model.isSimulationPaused)

        harness.model.endModalOverlay()

        XCTAssertFalse(harness.model.isSimulationPaused)
    }

    func testTableGuideDoesNotOverrideAnAudioInterruptionThatForbidsResume() throws {
        let harness = try RuntimeHarness()
        defer { harness.cleanup() }
        harness.activate()
        harness.model.beginModalOverlay()

        harness.model.audioInterruptionBegan()
        harness.model.audioInterruptionEnded(shouldResume: false)
        harness.model.endModalOverlay()

        XCTAssertTrue(harness.model.isSimulationPaused)
        XCTAssertTrue(harness.model.lifecycleCoordinator.isUserPaused)
        XCTAssertFalse(harness.model.lifecycleCoordinator.isModalOverlayPresented)
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
        mediaLaunchConfiguration: MediaLaunchConfiguration = MediaLaunchConfiguration(arguments: ["app"]),
        ownsWorkshop: Bool = false
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
            store: StoreService(
                backend: NullWorkshopStoreBackend(),
                userDefaults: defaults,
                bypassesStore: ownsWorkshop
            ),
            mediaLaunchConfiguration: mediaLaunchConfiguration
        )
    }

    func activate() {
        model.setApplicationActivity(.active)
        model.lifecycleCoordinator.start()
    }

    /// Runs the real scene loop for `times` simulated seconds so the rewind
    /// ring actually fills with keyframes.
    func playForOneSecond(times: Int) {
        var clock = 0.0
        for _ in 0 ..< (times * 240 / 8) {
            clock += 8.0 / 240.0
            model.scene.update(clock)
        }
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
