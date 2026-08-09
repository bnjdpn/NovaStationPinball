import NovaStationCore
import XCTest
#if SWIFT_PACKAGE
@testable import NovaStationLifecycle
#else
@testable import NovaStationPinball
#endif

final class SimulationDriverSessionTests: XCTestCase {
    func testGameCompletionGateAllowsExactlyOneRecordPerGame() {
        var gate = GameCompletionGate()

        XCTAssertFalse(gate.shouldRecord(phase: .launch))
        XCTAssertFalse(gate.shouldRecord(phase: .playing))
        XCTAssertTrue(gate.shouldRecord(phase: .gameOver))
        XCTAssertFalse(gate.shouldRecord(phase: .gameOver))

        gate.startNewGame()
        XCTAssertFalse(gate.shouldRecord(phase: .playing))
        XCTAssertTrue(gate.shouldRecord(phase: .gameOver))
        XCTAssertFalse(gate.shouldRecord(phase: .gameOver))
    }

    func testCatchUpAggregatesEveryTickEventAndReducesItExactlyOnce() throws {
        let table = TableDefinition(
            version: 790,
            playfieldSize: Vector2(x: 1, y: 2),
            gravity: .zero,
            sensors: [
                SensorDefinition(
                    id: "lane",
                    shape: .segment(SegmentCollider(
                        start: Vector2(x: 0.2, y: 0),
                        end: Vector2(x: 0.2, y: 1),
                        radius: 0
                    ))
                )
            ]
        )
        let simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [BallState(id: 9, position: Vector2(x: 0.19, y: 0.5), velocity: Vector2(x: 4, y: 0))]
            )
        )
        var driver = SimulationDriver(
            session: GameSession(simulation: simulation, phase: .playing)
        )

        let result = driver.advance(elapsed: 1.0 / 60.0, input: .idle)

        XCTAssertEqual(result.stepsExecuted, 4)
        XCTAssertEqual(result.frame.events, [GameEvent(name: "sensor:lane", ballID: 9)])
        XCTAssertEqual(result.rules.score, NovaStationTable.Score.lane)
        XCTAssertEqual(
            result.effects.filter { if case .scoreAwarded = $0 { true } else { false } }.count,
            1
        )
    }

    func testNewGameAndRestoreCarryRulesAndPhaseWithTheSnapshot() throws {
        var driver = SimulationDriver(session: try GameSession())
        XCTAssertEqual(driver.phase, .launch)
        XCTAssertTrue(driver.snapshot.balls.isEmpty)

        let start = try driver.startNewGame()
        XCTAssertEqual(start.phase, .playing)
        XCTAssertEqual(driver.rules.ballSaveTicksRemaining, GameRulesState.ballSaveDurationTicks)

        let savedSnapshot = driver.snapshot
        var savedRules = driver.rules
        _ = savedRules.addBonusUnit()
        try driver.restore(snapshot: savedSnapshot, rules: savedRules)

        XCTAssertEqual(driver.snapshot, savedSnapshot)
        XCTAssertEqual(driver.rules, savedRules)
        XCTAssertEqual(driver.phase, .playing)
    }

    func testPauseDropsQueuedCommandsWithoutChangingSessionState() throws {
        var driver = SimulationDriver(session: try GameSession())
        _ = try driver.startNewGame()
        let before = driver.currentSessionFrame
        driver.setPaused(true)

        let paused = driver.advance(
            elapsed: 1,
            input: SimulationInputBatch(
                continuous: .idle,
                commands: [.nudge(Vector2(x: 0.8, y: 0))]
            )
        )

        XCTAssertEqual(paused.stepsExecuted, 0)
        XCTAssertEqual(paused.sessionFrame, before)
    }

    func testCheckpointReplayRestoresThePreciseDriverAnchorAndContinuesRecording() throws {
        var driver = SimulationDriver(session: try GameSession())
        _ = try driver.startNewGame()
        let tick = PinballSimulation.fixedTimeStep
        _ = driver.advance(
            elapsed: tick,
            input: SimulationInputBatch(
                continuous: ContinuousPlayerInput(
                    leftFlipperIsPressed: false,
                    rightFlipperIsPressed: false,
                    plungerPull: 0.8
                ),
                commands: []
            )
        )
        _ = driver.advance(elapsed: tick, input: .idle)

        let snapshot = driver.snapshot
        let rules = driver.rules
        let replay = driver.recording
        XCTAssertEqual(replay.inputs.count, 2)

        _ = driver.advance(elapsed: tick * 4, input: .idle)
        try driver.restore(snapshot: snapshot, rules: rules, replay: replay)
        XCTAssertEqual(driver.snapshot, snapshot)
        XCTAssertEqual(driver.rules, rules)
        XCTAssertEqual(driver.recording, replay)

        _ = driver.advance(elapsed: tick, input: .idle)
        XCTAssertEqual(driver.recording.inputs.count, 3)
        let replayed = try driver.recording.replay()
        XCTAssertEqual(replayed.snapshot, driver.snapshot)
        XCTAssertEqual(replayed.rules, driver.rules)
        XCTAssertEqual(replayed.phase, driver.phase)
    }
}
