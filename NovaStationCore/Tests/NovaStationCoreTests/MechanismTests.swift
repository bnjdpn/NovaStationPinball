import Foundation
import Testing
@testable import NovaStationCore

@Suite("MechanismTests")
struct MechanismTests {
    @Test("flipper moves from rest toward active and transfers surface impulse")
    func flipperRestActiveAndImpulse() {
        let definition = FlipperDefinition(
            id: "left",
            pivot: .zero,
            length: 0.3,
            radius: 0.03,
            restAngle: 0,
            activeAngle: Double.pi / 2,
            angularSpeed: 12,
            impulseScale: 0.75
        )
        var state = FlipperState(definition: definition)

        #expect(state.angle == definition.restAngle)
        #expect(state.angularVelocity == 0)

        state.update(isPressed: true, timeStep: 1.0 / 240.0)
        let activeVelocity = state.surfaceVelocity(at: Vector2(x: definition.length, y: 0))
        let boosted = state.transferredVelocity(
            ballVelocity: .zero,
            contactPoint: Vector2(x: definition.length, y: 0),
            normal: Vector2(x: 0, y: 1)
        )

        #expect(state.angle == 12.0 / 240.0)
        #expect(state.angularVelocity == 12)
        #expect(activeVelocity.x == 0)
        #expect(abs(activeVelocity.y - 3.6) < 1e-12)
        #expect(boosted.x == 0)
        #expect(abs(boosted.y - 2.7) < 1e-12)

        state.update(isPressed: false, timeStep: 1)
        #expect(state.angle == definition.restAngle)
        #expect(state.angularVelocity < 0)
    }

    @Test("simulation updates configured left and right flippers from input")
    func simulationUpdatesFlippers() throws {
        let left = FlipperDefinition(
            id: "left",
            pivot: .zero,
            length: 0.2,
            radius: 0.02,
            restAngle: 0,
            activeAngle: 1,
            angularSpeed: 10,
            impulseScale: 1
        )
        let right = FlipperDefinition(
            id: "right",
            control: .right,
            pivot: Vector2(x: 1, y: 0),
            length: 0.2,
            radius: 0.02,
            restAngle: Double.pi,
            activeAngle: Double.pi - 1,
            angularSpeed: 10,
            impulseScale: 1
        )
        let table = TableDefinition(
            version: 41,
            playfieldSize: Vector2(x: 1, y: 2),
            gravity: .zero,
            flippers: [left, right]
        )
        var simulation = try PinballSimulation(table: table)

        _ = simulation.step(
            PlayerInput(
                leftFlipperIsPressed: true,
                rightFlipperIsPressed: false,
                plungerPull: 0,
                nudge: .zero
            )
        )

        #expect(simulation.flipperStates[0].angle > left.restAngle)
        #expect(simulation.flipperStates[1].angle == right.restAngle)
    }

    @Test("plunger clamps pull and releases its stored impulse once")
    func plungerPullAndRelease() {
        let definition = PlungerDefinition(
            position: Vector2(x: 0.9, y: 0.1),
            launchRadius: 0.08,
            launchDirection: Vector2(x: 0, y: 2),
            maximumImpulse: 12
        )
        var state = PlungerState()

        #expect(state.update(pull: 1.5, definition: definition) == nil)
        #expect(state.pull == 1)
        #expect(state.update(pull: 0, definition: definition) == Vector2(x: 0, y: 12))
        #expect(state.update(pull: 0, definition: definition) == nil)
    }

    @Test("plunger releases stored charge below an explicit analog threshold")
    func plungerReleaseThreshold() {
        let definition = PlungerDefinition(
            position: .zero,
            launchRadius: 0.1,
            launchDirection: Vector2(x: 0, y: 1),
            maximumImpulse: 12,
            releaseThreshold: 0.01
        )
        var state = PlungerState()

        #expect(state.update(pull: 0.5, definition: definition) == nil)
        let released = state.update(pull: 0.001, definition: definition)

        #expect(released == Vector2(x: 0, y: 6))
        #expect(state.pull == 0)
    }

    @Test("simulation launches only a ball in the plunger zone on release")
    func simulationReleasesPlunger() throws {
        let plunger = PlungerDefinition(
            position: Vector2(x: 0.9, y: 0.1),
            launchRadius: 0.08,
            launchDirection: Vector2(x: 0, y: 1),
            maximumImpulse: 24
        )
        let table = TableDefinition(
            version: 42,
            playfieldSize: Vector2(x: 1, y: 2),
            gravity: .zero,
            plunger: plunger
        )
        var simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [
                    BallState(id: 1, position: plunger.position, velocity: .zero),
                    BallState(id: 2, position: Vector2(x: 0.5, y: 1), velocity: .zero)
                ]
            )
        )

        _ = simulation.step(
            PlayerInput(
                leftFlipperIsPressed: false,
                rightFlipperIsPressed: false,
                plungerPull: 0.5,
                nudge: .zero
            )
        )
        let released = simulation.step(.idle)

        #expect(released.balls[0].velocity == Vector2(x: 0, y: 12))
        #expect(released.balls[1].velocity == .zero)
    }

    @Test("bumper collision reflects the ball and adds its radial impulse")
    func bumperCollisionAndImpulse() throws {
        let bumper = BumperDefinition(
            id: "reactor",
            collider: CircleCollider(
                center: Vector2(x: 0.5, y: 1),
                radius: 0.05,
                restitution: 1
            ),
            impulse: 2
        )
        let table = TableDefinition(
            version: 43,
            playfieldSize: Vector2(x: 1, y: 2),
            gravity: .zero,
            ballRadius: 0.05,
            bumpers: [bumper]
        )
        var simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [
                    BallState(
                        id: 1,
                        position: Vector2(x: 0, y: 1),
                        velocity: Vector2(x: 240, y: 0)
                    )
                ]
            )
        )

        let frame = simulation.step(.idle)

        #expect(frame.balls[0].velocity == Vector2(x: -242, y: 0))
        #expect(frame.events == [GameEvent(name: "bumper:reactor")])
    }

    @Test("target is a continuous physical surface and emits a hit event")
    func targetCollision() throws {
        let target = TargetDefinition(
            id: "alpha",
            collider: SegmentCollider(
                start: Vector2(x: 0.6, y: 0.8),
                end: Vector2(x: 0.6, y: 1.2),
                radius: 0.01,
                restitution: 0.5
            )
        )
        let table = TableDefinition(
            version: 44,
            playfieldSize: Vector2(x: 1, y: 2),
            gravity: .zero,
            ballRadius: 0.04,
            targets: [target]
        )
        var simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [
                    BallState(
                        id: 1,
                        position: Vector2(x: 0.1, y: 1),
                        velocity: Vector2(x: 240, y: 0)
                    )
                ]
            )
        )

        let frame = simulation.step(.idle)

        #expect(frame.balls[0].position.x < target.collider.start.x)
        #expect(frame.balls[0].velocity == Vector2(x: -120, y: 0))
        #expect(frame.events == [GameEvent(name: "target:alpha")])
    }

    @Test("sensor reports a high-speed crossing without changing motion")
    func sensorCrossing() throws {
        let sensor = SensorDefinition(
            id: "lane-exit",
            shape: .circle(
                CircleCollider(center: Vector2(x: 0.5, y: 1), radius: 0.05)
            )
        )
        let table = TableDefinition(
            version: 45,
            playfieldSize: Vector2(x: 1, y: 2),
            gravity: .zero,
            ballRadius: 0.03,
            sensors: [sensor]
        )
        var simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [
                    BallState(
                        id: 1,
                        position: Vector2(x: 0, y: 1),
                        velocity: Vector2(x: 240, y: 0)
                    )
                ]
            )
        )

        let frame = simulation.step(.idle)

        #expect(frame.balls[0].position == Vector2(x: 1, y: 1))
        #expect(frame.balls[0].velocity == Vector2(x: 240, y: 0))
        #expect(frame.events == [GameEvent(name: "sensor:lane-exit", ballID: 1)])
    }

    @Test("stationary ball already inside a sensor does not emit occupancy events")
    func stationaryBallInsideSensorDoesNotTrigger() throws {
        let sensor = SensorDefinition(
            id: "occupied",
            shape: .circle(CircleCollider(center: Vector2(x: 0.5, y: 1), radius: 0.1))
        )
        let table = TableDefinition(
            version: 452,
            playfieldSize: Vector2(x: 1, y: 2),
            gravity: .zero,
            sensors: [sensor]
        )
        var simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [BallState(id: 7, position: Vector2(x: 0.5, y: 1), velocity: .zero)]
            )
        )

        let first = simulation.step(.idle)
        let second = simulation.step(.idle)

        #expect(first.events.isEmpty)
        #expect(second.events.isEmpty)
    }

    @Test("two balls crossing one sensor emit distinct identified events")
    func twoBallsCrossingSensorRemainDistinct() throws {
        let table = TableDefinition(
            version: 453,
            playfieldSize: Vector2(x: 1, y: 2),
            gravity: .zero,
            sensors: [
                SensorDefinition(
                    id: "shared",
                    shape: .circle(
                        CircleCollider(center: Vector2(x: 0.5, y: 1), radius: 0.25)
                    )
                )
            ]
        )
        var simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [
                    BallState(
                        id: 11,
                        position: Vector2(x: 0, y: 0.9),
                        velocity: Vector2(x: 240, y: 0)
                    ),
                    BallState(
                        id: 22,
                        position: Vector2(x: 0, y: 1.1),
                        velocity: Vector2(x: 240, y: 0)
                    )
                ]
            )
        )

        let frame = simulation.step(.idle)

        #expect(
            frame.events == [
                GameEvent(name: "sensor:shared", ballID: 11),
                GameEvent(name: "sensor:shared", ballID: 22)
            ]
        )
    }

    @Test("sensor behind an earlier physical impact is not reported")
    func physicalImpactOccludesSensor() throws {
        let table = TableDefinition(
            version: 451,
            playfieldSize: Vector2(x: 1, y: 2),
            gravity: .zero,
            ballRadius: 0.05,
            collisionShapes: [
                .segment(
                    SegmentCollider(
                        start: Vector2(x: 0.4, y: 0),
                        end: Vector2(x: 0.4, y: 2),
                        radius: 0,
                        restitution: 1
                    )
                )
            ],
            sensors: [
                SensorDefinition(
                    id: "behind-rail",
                    shape: .circle(
                        CircleCollider(center: Vector2(x: 0.8, y: 1), radius: 0.05)
                    )
                )
            ]
        )
        var simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [
                    BallState(
                        id: 1,
                        position: Vector2(x: 0, y: 1),
                        velocity: Vector2(x: 240, y: 0)
                    )
                ]
            )
        )

        let frame = simulation.step(.idle)

        #expect(frame.events.isEmpty)
        #expect(frame.balls[0].velocity.x < 0)
    }

    @Test("linear friction damps velocity once per fixed tick")
    func frictionDampsVelocity() throws {
        let table = TableDefinition(
            version: 46,
            playfieldSize: Vector2(x: 1, y: 2),
            gravity: .zero,
            linearFriction: 24
        )
        var simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [
                    BallState(id: 1, position: .zero, velocity: Vector2(x: 10, y: 0))
                ]
            )
        )

        let frame = simulation.step(.idle)

        #expect(frame.balls[0].velocity == Vector2(x: 9, y: 0))
        #expect(frame.balls[0].position == Vector2(x: 9.0 / 240.0, y: 0))
    }

    @Test("nudge applies the configured impulse to every ball")
    func nudgeAppliesImpulse() throws {
        let table = TableDefinition(
            version: 47,
            playfieldSize: Vector2(x: 1, y: 2),
            gravity: .zero,
            nudgeImpulseScale: 4
        )
        var simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [BallState(id: 1, position: .zero, velocity: Vector2(x: 1, y: 1))]
            )
        )

        let frame = simulation.step(
            PlayerInput(
                leftFlipperIsPressed: false,
                rightFlipperIsPressed: false,
                plungerPull: 0,
                nudge: Vector2(x: 0.5, y: -0.25)
            )
        )

        #expect(frame.balls[0].velocity == Vector2(x: 3, y: 0))
    }

    @Test("tilt accumulates nudges against a deterministic threshold")
    func tiltThreshold() {
        let definition = TiltDefinition(threshold: 1, decayPerSecond: 0)
        var state = TiltState()

        let firstTransition = state.update(
            nudgeMagnitude: 0.6,
            definition: definition,
            timeStep: 1.0 / 240.0
        )
        #expect(!firstTransition)
        #expect(!state.isTilted)
        let secondTransition = state.update(
            nudgeMagnitude: 0.5,
            definition: definition,
            timeStep: 1.0 / 240.0
        )
        #expect(secondTransition)
        #expect(state.isTilted)
        let repeatedTransition = state.update(
            nudgeMagnitude: 1,
            definition: definition,
            timeStep: 1.0 / 240.0
        )
        #expect(!repeatedTransition)
    }

    @Test("tilt transition emits once and suppresses flipper activation")
    func tiltDisablesFlippers() throws {
        let flipper = FlipperDefinition(
            id: "left",
            pivot: .zero,
            length: 0.2,
            radius: 0.02,
            restAngle: 0,
            activeAngle: 1,
            angularSpeed: 10,
            impulseScale: 1
        )
        let table = TableDefinition(
            version: 48,
            playfieldSize: Vector2(x: 1, y: 2),
            gravity: .zero,
            flippers: [flipper],
            tilt: TiltDefinition(threshold: 0.5, decayPerSecond: 0)
        )
        var simulation = try PinballSimulation(table: table)
        let input = PlayerInput(
            leftFlipperIsPressed: true,
            rightFlipperIsPressed: false,
            plungerPull: 0,
            nudge: Vector2(x: 1, y: 0)
        )

        let tilted = simulation.step(input)
        let next = simulation.step(input)

        #expect(simulation.tiltState.isTilted)
        #expect(simulation.flipperStates[0].angle == flipper.restAngle)
        #expect(tilted.events == [GameEvent(name: "tilt")])
        #expect(next.events.isEmpty)
    }

    @Test("active flipper collider transfers motion to a ball during simulation")
    func simulationTransfersFlipperImpulse() throws {
        let flipper = FlipperDefinition(
            id: "left",
            pivot: .zero,
            length: 1,
            radius: 0.05,
            restAngle: 0,
            activeAngle: Double.pi / 2,
            angularSpeed: 120 * Double.pi,
            impulseScale: 0.01
        )
        let table = TableDefinition(
            version: 49,
            playfieldSize: Vector2(x: 2, y: 2),
            gravity: .zero,
            ballRadius: 0.05,
            flippers: [flipper]
        )
        var simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [
                    BallState(
                        id: 1,
                        position: Vector2(x: -0.2, y: 0.5),
                        velocity: Vector2(x: 48, y: 0)
                    )
                ]
            )
        )

        let frame = simulation.step(
            PlayerInput(
                leftFlipperIsPressed: true,
                rightFlipperIsPressed: false,
                plungerPull: 0,
                nudge: .zero
            )
        )

        #expect(abs(simulation.flipperStates[0].angle - Double.pi / 2) < 1e-12)
        #expect(frame.balls[0].velocity.x < -1)
        #expect(frame.balls[0].position.x < 0)
    }

    @Test("rotating flipper strikes a stationary ball along its swept path")
    func rotatingFlipperStrikesStationaryBall() throws {
        let flipper = FlipperDefinition(
            id: "left",
            pivot: .zero,
            length: 1,
            radius: 0.04,
            restAngle: 0,
            activeAngle: Double.pi / 2,
            angularSpeed: 120 * Double.pi,
            impulseScale: 0.02
        )
        let table = TableDefinition(
            version: 50,
            playfieldSize: Vector2(x: 2, y: 2),
            gravity: .zero,
            ballRadius: 0.04,
            flippers: [flipper]
        )
        var simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [
                    BallState(id: 1, position: Vector2(x: 0, y: 0.5), velocity: .zero)
                ]
            )
        )

        let frame = simulation.step(
            PlayerInput(
                leftFlipperIsPressed: true,
                rightFlipperIsPressed: false,
                plungerPull: 0,
                nudge: .zero
            )
        )

        #expect(frame.balls[0].velocity.length > 0)
        #expect(frame.balls[0].position != Vector2(x: 0, y: 0.5))
    }

    @Test("rotating flipper does not catch a ball separating faster than its surface")
    func rotatingFlipperIgnoresFasterSeparatingBall() throws {
        let flipper = FlipperDefinition(
            id: "left",
            pivot: .zero,
            length: 1,
            radius: 0.04,
            restAngle: 0,
            activeAngle: Double.pi / 2,
            angularSpeed: 120 * Double.pi,
            impulseScale: 0.02
        )
        let table = TableDefinition(
            version: 51,
            playfieldSize: Vector2(x: 8, y: 2),
            gravity: .zero,
            ballRadius: 0.04,
            flippers: [flipper]
        )
        var simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [
                    BallState(
                        id: 1,
                        position: Vector2(x: 0, y: 0.5),
                        velocity: Vector2(x: -1_000, y: 0)
                    )
                ]
            )
        )

        let frame = simulation.step(
            PlayerInput(
                leftFlipperIsPressed: true,
                rightFlipperIsPressed: false,
                plungerPull: 0,
                nudge: .zero
            )
        )

        #expect(frame.balls[0].velocity == Vector2(x: -1_000, y: 0))
        #expect(frame.balls[0].position.x < -4)
    }

    @Test("rotating flipper does not hit a ball that leaves before the swept pose arrives")
    func rotatingFlipperUsesBallPositionAtEachSweepTime() throws {
        let flipper = FlipperDefinition(
            id: "left",
            pivot: .zero,
            length: 1,
            radius: 0.04,
            restAngle: 0,
            activeAngle: Double.pi / 2,
            angularSpeed: 120 * Double.pi,
            impulseScale: 0.02
        )
        let table = TableDefinition(
            version: 53,
            playfieldSize: Vector2(x: 2, y: 8),
            gravity: .zero,
            ballRadius: 0.04,
            flippers: [flipper]
        )
        let startingPosition = Vector2(x: 0, y: 0.5)
        let startingVelocity = Vector2(x: 0, y: 1_000)
        var simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [
                    BallState(
                        id: 1,
                        position: startingPosition,
                        velocity: startingVelocity
                    )
                ]
            )
        )

        let frame = simulation.step(
            PlayerInput(
                leftFlipperIsPressed: true,
                rightFlipperIsPressed: false,
                plungerPull: 0,
                nudge: .zero
            )
        )

        #expect(frame.balls[0].velocity == startingVelocity)
        #expect(
            frame.balls[0].position
                == startingPosition + startingVelocity * PinballSimulation.fixedTimeStep
        )
    }

    @Test("earlier rail wins over a rotating flipper behind it")
    func staticRailPrecedesAnimatedFlipperOnOneTimeline() throws {
        let flipper = FlipperDefinition(
            id: "behind-rail",
            pivot: Vector2(x: 0.5, y: 0.5),
            length: 1,
            radius: 0.04,
            restAngle: 0,
            activeAngle: Double.pi / 2,
            angularSpeed: 120 * Double.pi,
            impulseScale: 0.02
        )
        let table = TableDefinition(
            version: 54,
            playfieldSize: Vector2(x: 2, y: 2),
            gravity: .zero,
            ballRadius: 0.05,
            collisionShapes: [
                .segment(
                    SegmentCollider(
                        start: Vector2(x: 0.4, y: 0),
                        end: Vector2(x: 0.4, y: 1),
                        radius: 0,
                        restitution: 1
                    )
                )
            ],
            flippers: [flipper]
        )
        var simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [
                    BallState(
                        id: 1,
                        position: Vector2(x: 0, y: 0.5),
                        velocity: Vector2(x: 240, y: 0)
                    )
                ]
            )
        )

        let frame = simulation.step(
            PlayerInput(
                leftFlipperIsPressed: true,
                rightFlipperIsPressed: false,
                plungerPull: 0,
                nudge: .zero
            )
        )

        #expect(frame.balls[0].velocity == Vector2(x: -240, y: 0))
        #expect(abs(frame.balls[0].position.x - -0.3) < 1e-12)
        #expect(frame.balls[0].position.y == 0.5)
    }

    @Test("fast ball crosses a slow flipper between curvature poses")
    func animatedFlipperIntervalsUseContinuousBallSweep() throws {
        let flipper = FlipperDefinition(
            id: "slow",
            pivot: .zero,
            length: 1,
            radius: 0.01,
            restAngle: 0,
            activeAngle: 0.01,
            angularSpeed: 2.4,
            impulseScale: 0.02
        )
        let table = TableDefinition(
            version: 55,
            playfieldSize: Vector2(x: 2, y: 2),
            gravity: .zero,
            ballRadius: 0.01,
            flippers: [flipper]
        )
        var simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [
                    BallState(
                        id: 1,
                        position: Vector2(x: 0.5, y: -0.5),
                        velocity: Vector2(x: 0, y: 240)
                    )
                ]
            )
        )

        let frame = simulation.step(
            PlayerInput(
                leftFlipperIsPressed: true,
                rightFlipperIsPressed: false,
                plungerPull: 0,
                nudge: .zero
            )
        )

        #expect(abs(simulation.flipperStates[0].angle - 0.01) < 1e-12)
        #expect(frame.balls[0].velocity.y < 0)
        #expect(frame.balls[0].position.y < 0)
    }

    @Test("adaptive flipper sweep catches a ball between legacy fixed poses")
    func adaptiveFlipperSweepAvoidsPoseAliasing() throws {
        let flipper = FlipperDefinition(
            id: "left",
            pivot: .zero,
            length: 1,
            radius: 0.01,
            restAngle: 0,
            activeAngle: Double.pi,
            angularSpeed: 240 * Double.pi,
            impulseScale: 0.02
        )
        let table = TableDefinition(
            version: 52,
            playfieldSize: Vector2(x: 2, y: 2),
            gravity: .zero,
            ballRadius: 0.01,
            flippers: [flipper]
        )
        let legacyHalfStepAngle = Double.pi / 64
        let startingPosition = Vector2(
            x: 0.5 * cos(legacyHalfStepAngle),
            y: 0.5 * sin(legacyHalfStepAngle)
        )
        var simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [BallState(id: 1, position: startingPosition, velocity: .zero)]
            )
        )

        let frame = simulation.step(
            PlayerInput(
                leftFlipperIsPressed: true,
                rightFlipperIsPressed: false,
                plungerPull: 0,
                nudge: .zero
            )
        )

        #expect(frame.balls[0].velocity.length > 0)
        #expect(frame.balls[0].position != startingPosition)
    }
}
