import Foundation
import Testing
@testable import NovaStationCore

@Suite("PinballSimulationTests")
struct PinballSimulationTests {
    @Test("the public simulation API is value based and sendable")
    func publicAPIIsValueBasedAndSendable() throws {
        requireSendable(Vector2.self)
        requireSendable(BallState.self)
        requireSendable(PlayerInput.self)
        requireSendable(GameEvent.self)
        requireSendable(SimulationFrame.self)
        requireSendable(SimulationSnapshot.self)
        requireSendable(TableDefinition.self)
        requireSendable(PinballSimulation.self)
        requireSendable(SimulationError.self)

        let table = TableDefinition.standard
        var simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [
                    BallState(
                        id: 1,
                        position: Vector2(x: 0.5, y: 1.5),
                        velocity: .zero
                    )
                ]
            )
        )

        let frame: SimulationFrame = simulation.step(.idle)

        #expect(PinballSimulation.fixedTimeStep == 1.0 / 240.0)
        #expect(table.version == 1)
        #expect(table.playfieldSize == Vector2(x: 1, y: 2))
        #expect(frame.events.isEmpty)
    }

    @Test("gravity changes velocity by exactly one fixed tick")
    func gravityChangesVelocityForOneTick() throws {
        let table = TableDefinition(
            version: 7,
            playfieldSize: Vector2(x: 1, y: 2),
            gravity: Vector2(x: 0, y: -9.6)
        )
        var simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [
                    BallState(
                        id: 42,
                        position: Vector2(x: 0.5, y: 1.5),
                        velocity: .zero
                    )
                ]
            )
        )

        let frame = simulation.step(.idle)

        #expect(frame.snapshot.balls[0].velocity.x == 0)
        #expect(frame.snapshot.balls[0].velocity.y == -9.6 / 240.0)
    }

    @Test("elapsed time accumulates fixed ticks")
    func elapsedTimeAccumulatesFixedTicks() {
        var simulation = PinballSimulation()

        _ = simulation.step(.idle)
        let secondFrame = simulation.step(.idle)

        #expect(secondFrame.snapshot.elapsedTime == 2.0 / 240.0)
    }

    @Test("snapshot encoding is stable and round trips")
    func snapshotEncodingIsStable() throws {
        let snapshot = SimulationSnapshot(
            tableVersion: 3,
            elapsedTime: 1.25,
            balls: [
                BallState(
                    id: 9,
                    position: Vector2(x: 0.25, y: 1.75),
                    velocity: Vector2(x: -2, y: 4.5)
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let encoded = try encoder.encode(snapshot)

        #expect(
            String(decoding: encoded, as: UTF8.self)
                == #"{"balls":[{"id":9,"position":{"x":0.25,"y":1.75},"velocity":{"x":-2,"y":4.5}}],"elapsedTime":1.25,"tableVersion":3}"#
        )
        #expect(try JSONDecoder().decode(SimulationSnapshot.self, from: encoded) == snapshot)
    }

    @Test("table decoding preserves legacy v1 defaults and current data round trips")
    func tableCodingIsBackwardCompatible() throws {
        let legacyJSON = Data(
            #"{"version":1,"playfieldSize":{"x":1,"y":2},"gravity":{"x":0,"y":-9.6}}"#.utf8
        )

        let legacyTable = try JSONDecoder().decode(TableDefinition.self, from: legacyJSON)

        #expect(legacyTable == .standard)
        #expect(legacyTable.ballRadius == 0.025)
        #expect(legacyTable.collisionShapes.isEmpty)
        #expect(legacyTable.flippers.isEmpty)
        #expect(legacyTable.plunger == nil)
        #expect(legacyTable.bumpers.isEmpty)
        #expect(legacyTable.targets.isEmpty)
        #expect(legacyTable.sensors.isEmpty)
        #expect(legacyTable.linearFriction == 0)
        #expect(legacyTable.nudgeImpulseScale == 1)
        #expect(legacyTable.tilt == nil)

        let currentTable = TableDefinition(
            version: 9,
            playfieldSize: Vector2(x: 3, y: 5),
            gravity: Vector2(x: 0.1, y: -8),
            ballRadius: 0.04,
            collisionShapes: [
                .arc(
                    ArcCollider(
                        center: Vector2(x: 1, y: 2),
                        radius: 0.5,
                        startAngle: 0,
                        endAngle: 1,
                        thickness: 0.02,
                        restitution: 0.8
                    )
                )
            ],
            flippers: [
                FlipperDefinition(
                    id: "right",
                    control: .right,
                    pivot: Vector2(x: 2, y: 1),
                    length: 0.3,
                    radius: 0.02,
                    restAngle: 2,
                    activeAngle: 1,
                    angularSpeed: 10,
                    impulseScale: 0.75
                )
            ],
            plunger: PlungerDefinition(
                position: Vector2(x: 2.8, y: 0.2),
                launchRadius: 0.08,
                launchDirection: Vector2(x: 0, y: 1),
                maximumImpulse: 20,
                releaseThreshold: 0.02
            ),
            bumpers: [
                BumperDefinition(
                    id: "reactor",
                    collider: CircleCollider(
                        center: Vector2(x: 1.5, y: 3),
                        radius: 0.1,
                        restitution: 0.9
                    ),
                    impulse: 2
                )
            ],
            targets: [
                TargetDefinition(
                    id: "alpha",
                    collider: SegmentCollider(
                        start: Vector2(x: 0.5, y: 2),
                        end: Vector2(x: 0.7, y: 2),
                        radius: 0.01,
                        restitution: 0.5
                    )
                )
            ],
            sensors: [
                SensorDefinition(
                    id: "lane",
                    shape: .circle(
                        CircleCollider(center: Vector2(x: 2, y: 4), radius: 0.2)
                    )
                )
            ],
            linearFriction: 0.2,
            nudgeImpulseScale: 1.5,
            tilt: TiltDefinition(threshold: 2, decayPerSecond: 0.25)
        )

        let encoded = try JSONEncoder().encode(currentTable)

        #expect(try JSONDecoder().decode(TableDefinition.self, from: encoded) == currentTable)
    }

    @Test("a snapshot for another table version is rejected explicitly")
    func rejectsSnapshotFromAnotherTableVersion() {
        let table = TableDefinition.standard
        let snapshot = SimulationSnapshot(
            tableVersion: table.version + 1,
            elapsedTime: 0,
            balls: []
        )

        do {
            _ = try PinballSimulation(table: table, snapshot: snapshot)
            Issue.record("Expected a table-version mismatch error")
        } catch let error as SimulationError {
            #expect(
                error == .tableVersionMismatch(
                    expected: table.version,
                    actual: snapshot.tableVersion
                )
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("non-finite runtime input is neutralized without contaminating state")
    func nonFiniteInputIsNeutralized() throws {
        let table = TableDefinition(
            version: 8,
            playfieldSize: Vector2(x: 1, y: 2),
            gravity: .zero,
            tilt: TiltDefinition(threshold: 1, decayPerSecond: 0)
        )
        var simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [BallState(id: 1, position: Vector2(x: 0.5, y: 1), velocity: .zero)]
            )
        )
        let invalidInput = PlayerInput(
            leftFlipperIsPressed: false,
            rightFlipperIsPressed: false,
            plungerPull: .nan,
            nudge: Vector2(x: .infinity, y: -.infinity)
        )

        let frame = simulation.step(invalidInput)

        #expect(frame.balls[0].position == Vector2(x: 0.5, y: 1))
        #expect(frame.balls[0].velocity == .zero)
        #expect(frame.balls[0].position.x.isFinite)
        #expect(frame.balls[0].velocity.y.isFinite)
        #expect(!simulation.tiltState.isTilted)
    }

    @Test("invalid table definitions are rejected with a precise field path")
    func rejectsInvalidTableDefinitions() {
        var nonFiniteDimensions = TableDefinition.standard
        nonFiniteDimensions.playfieldSize.x = .nan
        var zeroDimension = TableDefinition.standard
        zeroDimension.playfieldSize.y = 0
        var nonFiniteGravity = TableDefinition.standard
        nonFiniteGravity.gravity.y = .infinity
        var invalidBallRadius = TableDefinition.standard
        invalidBallRadius.ballRadius = 0
        var invalidSegmentRadius = TableDefinition.standard
        invalidSegmentRadius.collisionShapes = [
            .segment(
                SegmentCollider(start: .zero, end: Vector2(x: 1, y: 0), radius: -1)
            )
        ]
        var invalidRestitution = TableDefinition.standard
        invalidRestitution.collisionShapes = [
            .circle(CircleCollider(center: .zero, radius: 1, restitution: 1.1))
        ]
        var invalidArcAngle = TableDefinition.standard
        invalidArcAngle.collisionShapes = [
            .arc(
                ArcCollider(
                    center: .zero,
                    radius: 1,
                    startAngle: .nan,
                    endAngle: 1,
                    thickness: 0.1
                )
            )
        ]
        var invalidFlipper = TableDefinition.standard
        invalidFlipper.flippers = [
            FlipperDefinition(
                id: "bad",
                pivot: .zero,
                length: 0,
                radius: 0.1,
                restAngle: 0,
                activeAngle: 1,
                angularSpeed: 1,
                impulseScale: 1
            )
        ]
        var invalidPlungerVector = TableDefinition.standard
        invalidPlungerVector.plunger = PlungerDefinition(
            position: .zero,
            launchRadius: 0.1,
            launchDirection: .zero,
            maximumImpulse: 1
        )
        var invalidBumperImpulse = TableDefinition.standard
        invalidBumperImpulse.bumpers = [
            BumperDefinition(
                id: "bad",
                collider: CircleCollider(center: .zero, radius: 0.1),
                impulse: -1
            )
        ]
        var invalidPlungerThreshold = TableDefinition.standard
        invalidPlungerThreshold.plunger = PlungerDefinition(
            position: .zero,
            launchRadius: 0.1,
            launchDirection: Vector2(x: 0, y: 1),
            maximumImpulse: 1,
            releaseThreshold: 1
        )
        var invalidFriction = TableDefinition.standard
        invalidFriction.linearFriction = -1
        var invalidNudge = TableDefinition.standard
        invalidNudge.nudgeImpulseScale = .infinity
        var invalidTilt = TableDefinition.standard
        invalidTilt.tilt = TiltDefinition(threshold: 0, decayPerSecond: 0)

        let cases: [(TableDefinition, SimulationError)] = [
            (nonFiniteDimensions, .nonFiniteValue(path: "table.playfieldSize.x")),
            (zeroDimension, .invalidValue(path: "table.playfieldSize.y")),
            (nonFiniteGravity, .nonFiniteValue(path: "table.gravity.y")),
            (invalidBallRadius, .invalidValue(path: "table.ballRadius")),
            (invalidSegmentRadius, .invalidValue(path: "table.collisionShapes[0].radius")),
            (invalidRestitution, .invalidValue(path: "table.collisionShapes[0].restitution")),
            (invalidArcAngle, .nonFiniteValue(path: "table.collisionShapes[0].startAngle")),
            (invalidFlipper, .invalidValue(path: "table.flippers[0].length")),
            (invalidPlungerVector, .invalidValue(path: "table.plunger.launchDirection")),
            (invalidPlungerThreshold, .invalidValue(path: "table.plunger.releaseThreshold")),
            (invalidBumperImpulse, .invalidValue(path: "table.bumpers[0].impulse")),
            (invalidFriction, .invalidValue(path: "table.linearFriction")),
            (invalidNudge, .nonFiniteValue(path: "table.nudgeImpulseScale")),
            (invalidTilt, .invalidValue(path: "table.tilt.threshold"))
        ]

        for (table, expectedError) in cases {
            do {
                _ = try PinballSimulation(table: table)
                Issue.record("Expected rejection for \(expectedError)")
            } catch let error as SimulationError {
                #expect(error == expectedError)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test("table validation rejects a flipper sweep above the deterministic work cap")
    func rejectsExcessiveFlipperSweepWork() {
        var table = TableDefinition.standard
        table.ballRadius = 0.000_001
        table.flippers = [
            FlipperDefinition(
                id: "pathological",
                pivot: .zero,
                length: 1,
                radius: 0,
                restAngle: 0,
                activeAngle: Double.pi,
                angularSpeed: 240 * Double.pi,
                impulseScale: 1
            )
        ]

        do {
            _ = try PinballSimulation(table: table)
            Issue.record("Expected excessive flipper sweep work to be rejected")
        } catch let error as SimulationError {
            #expect(error == .invalidValue(path: "table.flippers[0].sweepSubsteps"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("non-finite snapshot state is rejected before assignment")
    func rejectsNonFiniteSnapshot() {
        let table = TableDefinition.standard
        let snapshot = SimulationSnapshot(
            tableVersion: table.version,
            elapsedTime: 0,
            balls: [
                BallState(
                    id: 1,
                    position: Vector2(x: .infinity, y: 1),
                    velocity: .zero
                )
            ]
        )

        do {
            _ = try PinballSimulation(table: table, snapshot: snapshot)
            Issue.record("Expected non-finite snapshot rejection")
        } catch let error as SimulationError {
            #expect(error == .nonFiniteValue(path: "snapshot.balls[0].position.x"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("duplicate ball identifiers are rejected before simulation")
    func rejectsDuplicateBallIdentifiers() {
        let table = TableDefinition.standard
        let snapshot = SimulationSnapshot(
            tableVersion: table.version,
            elapsedTime: 0,
            balls: [
                BallState(id: 7, position: Vector2(x: 0.25, y: 1), velocity: .zero),
                BallState(id: 7, position: Vector2(x: 0.75, y: 1), velocity: .zero)
            ]
        )

        do {
            _ = try PinballSimulation(table: table, snapshot: snapshot)
            Issue.record("Expected duplicate ball identifiers to be rejected")
        } catch let error as SimulationError {
            #expect(
                error == .invalidValue(
                    path: "snapshot.balls[1].id (duplicate 7; first at snapshot.balls[0].id)"
                )
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func requireSendable<T: Sendable>(_: T.Type) {}
}
