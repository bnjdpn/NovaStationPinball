import NovaStationCore
import XCTest
@testable import NovaStationPinball

final class SimulationDriverTests: XCTestCase {
    func testAccumulatesDisplayFractionsIntoExact240HzStep() {
        var driver = SimulationDriver()

        let first = driver.advance(elapsed: 1.0 / 480.0, input: .idle)
        let second = driver.advance(elapsed: 1.0 / 480.0, input: .idle)

        XCTAssertEqual(first.stepsExecuted, 0)
        XCTAssertEqual(second.stepsExecuted, 1)
        XCTAssertEqual(second.frame.elapsedTime, 1.0 / 240.0, accuracy: 1e-12)
    }

    func testLongFrameCatchUpIsBoundedAndDropsExcessTime() {
        var driver = SimulationDriver(maximumCatchUpSteps: 8)

        let result = driver.advance(elapsed: 1, input: .idle)

        XCTAssertEqual(result.stepsExecuted, 8)
        XCTAssertEqual(result.frame.elapsedTime, 8.0 / 240.0, accuracy: 1e-12)
        XCTAssertGreaterThan(result.droppedTime, 0.9)
    }

    func testNegativeAndNonFiniteElapsedTimeDoNotAdvance() {
        var driver = SimulationDriver()

        XCTAssertEqual(driver.advance(elapsed: -1, input: .idle).stepsExecuted, 0)
        XCTAssertEqual(driver.advance(elapsed: .infinity, input: .idle).stepsExecuted, 0)
    }

    @MainActor
    func testAppModelKeepsReleaseStrengthAndOneShotCommandsSeparateFromContinuousState() {
        let model = AppModel(audioEngine: NullAudioEngine(), hapticsService: NullHapticsService())
        activateGameplayForTesting(model)

        model.apply([
            .flipper(side: .left, isPressed: true),
            .plungerPull(0.75),
            .plungerReleased(0.75),
            .nudge(x: 0.4)
        ])
        let batch = model.takeSimulationInput()

        XCTAssertTrue(batch.continuous.leftFlipperIsPressed)
        XCTAssertEqual(batch.continuous.plungerPull, 0)
        XCTAssertEqual(
            batch.commands,
            [
                .releasePlunger(strength: 0.75),
                .nudge(Vector2(x: 0.4, y: 0))
            ]
        )
        XCTAssertTrue(model.takeSimulationInput().commands.isEmpty)
    }

    func testNudgeSurvivesZeroTickAndIsNotRepeatedDuringCatchUp() throws {
        var retainedDriver = try makeImpulseDriver()
        let command = SimulationInputBatch(
            continuous: .idle,
            commands: [.nudge(Vector2(x: 0.5, y: 0))]
        )

        XCTAssertEqual(
            retainedDriver.advance(elapsed: 1.0 / 480.0, input: command).stepsExecuted,
            0
        )
        let retained = retainedDriver.advance(elapsed: 1.0 / 480.0, input: .idle)
        XCTAssertEqual(retained.frame.balls[0].velocity.x, 0.5, accuracy: 1e-12)

        var catchUpDriver = try makeImpulseDriver()
        let caughtUp = catchUpDriver.advance(elapsed: 1.0 / 60.0, input: command)
        XCTAssertEqual(caughtUp.stepsExecuted, 4)
        XCTAssertEqual(caughtUp.frame.balls[0].velocity.x, 0.5, accuracy: 1e-12)
    }

    @MainActor
    func testReleaseBeforeUpdateLaunchesWithExactStrengthAtEveryDisplayCadence() throws {
        for refreshRate in [480.0, 240.0, 120.0, 60.0] {
            let model = AppModel(audioEngine: NullAudioEngine(), hapticsService: NullHapticsService())
            activateGameplayForTesting(model)
            var driver = try makeImpulseDriver()
            model.apply([.plungerPull(0.75), .plungerReleased(0.75)])

            let displayFrames = Int(refreshRate / 60.0)
            var result: SimulationAdvanceResult?
            for frame in 0..<displayFrames {
                result = driver.advance(
                    elapsed: 1.0 / refreshRate,
                    input: frame == 0 ? model.takeSimulationInput() : .idle
                )
            }

            XCTAssertEqual(result?.frame.elapsedTime ?? -1, 1.0 / 60.0, accuracy: 1e-12)
            XCTAssertEqual(result?.frame.balls[0].velocity.y ?? -1, 7.5, accuracy: 1e-12)
        }
    }

    func testNudgeOutcomeIsIdenticalAt480_240_120And60Hz() throws {
        var velocities: [Double] = []

        for refreshRate in [480.0, 240.0, 120.0, 60.0] {
            var driver = try makeImpulseDriver()
            let displayFrames = Int(refreshRate / 60.0)
            var result: SimulationAdvanceResult?
            for frame in 0..<displayFrames {
                let input = frame == 0
                    ? SimulationInputBatch(
                        continuous: .idle,
                        commands: [.nudge(Vector2(x: 0.4, y: 0))]
                    )
                    : .idle
                result = driver.advance(elapsed: 1.0 / refreshRate, input: input)
            }
            velocities.append(result?.frame.balls[0].velocity.x ?? -1)
        }

        XCTAssertEqual(velocities, [0.4, 0.4, 0.4, 0.4])
    }

    private func makeImpulseDriver() throws -> SimulationDriver {
        let plunger = PlungerDefinition(
            position: Vector2(x: 0.9, y: 0.1),
            launchRadius: 0.08,
            launchDirection: Vector2(x: 0, y: 1),
            maximumImpulse: 10
        )
        let table = TableDefinition(
            version: 701,
            playfieldSize: Vector2(x: 1, y: 2),
            gravity: .zero,
            plunger: plunger,
            nudgeImpulseScale: 1
        )
        let simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [BallState(id: 1, position: plunger.position, velocity: .zero)]
            )
        )
        return SimulationDriver(simulation: simulation)
    }
}
