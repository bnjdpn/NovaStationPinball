import Foundation
import Testing
@testable import NovaStationCore

@Suite("CollisionTests")
struct CollisionTests {
    @Test("a moving circle reports the first impact against a segment capsule")
    func sweepsCircleAgainstSegmentCapsule() {
        let shape = CollisionShape.segment(
            SegmentCollider(
                start: Vector2(x: 1, y: -1),
                end: Vector2(x: 1, y: 1),
                radius: 0
            )
        )

        let hit = ContinuousCollision.sweepCircle(
            from: .zero,
            displacement: Vector2(x: 2, y: 0),
            radius: 0.25,
            against: shape
        )

        #expect(hit != nil)
        #expect(abs((hit?.time ?? 0) - 0.375) < 1e-12)
        #expect(hit?.center == Vector2(x: 0.75, y: 0))
        #expect(hit?.point == Vector2(x: 1, y: 0))
        #expect(hit?.normal == Vector2(x: -1, y: 0))
        #expect((0 ... 1).contains(hit?.time ?? -1))
    }

    @Test("a moving circle collides with a segment endpoint")
    func sweepsCircleAgainstSegmentEndpoint() {
        let shape = CollisionShape.segment(
            SegmentCollider(
                start: Vector2(x: 1, y: 1),
                end: Vector2(x: 1, y: 2),
                radius: 0
            )
        )

        let hit = ContinuousCollision.sweepCircle(
            from: .zero,
            displacement: Vector2(x: 2, y: 2),
            radius: 0.2,
            against: shape
        )

        let expectedTime = (1 - 0.2 / sqrt(2)) / 2
        #expect(hit != nil)
        #expect(abs((hit?.time ?? 0) - expectedTime) < 1e-12)
        #expect(abs((hit?.normal.x ?? 0) + 1 / sqrt(2)) < 1e-12)
        #expect(abs((hit?.normal.y ?? 0) + 1 / sqrt(2)) < 1e-12)
        #expect(hit?.point == Vector2(x: 1, y: 1))
    }

    @Test("circle and arc shapes participate in continuous collision")
    func sweepsCircleAndArcShapes() {
        let circleHit = ContinuousCollision.sweepCircle(
            from: .zero,
            displacement: Vector2(x: 4, y: 0),
            radius: 0.25,
            against: .circle(CircleCollider(center: Vector2(x: 2, y: 0), radius: 0.5))
        )
        let arcHit = ContinuousCollision.sweepCircle(
            from: Vector2(x: 0, y: 2),
            displacement: Vector2(x: 4, y: 0),
            radius: 0.25,
            against: .arc(
                ArcCollider(
                    center: Vector2(x: 2, y: 0),
                    radius: 2,
                    startAngle: Double.pi / 4,
                    endAngle: 3 * Double.pi / 4,
                    thickness: 0
                )
            )
        )

        #expect(abs((circleHit?.time ?? 0) - 0.3125) < 1e-12)
        #expect(arcHit != nil)
        #expect((arcHit?.normal.y ?? 0) > 0)
    }

    @Test("arc collision resolves the inner face instead of treating its interior as solid")
    func sweepsInnerFaceOfArc() {
        let hit = ContinuousCollision.sweepCircle(
            from: .zero,
            displacement: Vector2(x: 2, y: 0),
            radius: 0.1,
            against: .arc(
                ArcCollider(
                    center: .zero,
                    radius: 1,
                    startAngle: -Double.pi / 4,
                    endAngle: Double.pi / 4,
                    thickness: 0
                )
            )
        )

        #expect(hit != nil)
        #expect(abs((hit?.time ?? 0) - 0.45) < 1e-12)
        #expect(hit?.center == Vector2(x: 0.9, y: 0))
        #expect(hit?.point == Vector2(x: 1, y: 0))
        #expect(hit?.normal == Vector2(x: -1, y: 0))
    }

    @Test("initial arc overlap depenetrates deterministically at time zero")
    func initialArcOverlapDepenetrates() throws {
        let arc = ArcCollider(
            center: .zero,
            radius: 1,
            startAngle: -Double.pi / 4,
            endAngle: Double.pi / 4,
            thickness: 0.1,
            restitution: 1
        )
        let hit = ContinuousCollision.sweepCircle(
            from: Vector2(x: 1, y: 0),
            displacement: .zero,
            radius: 0.05,
            against: .arc(arc)
        )

        #expect(hit?.time == 0)
        #expect(hit?.startedOverlapping == true)
        #expect(hit?.center == Vector2(x: 1.1, y: 0))

        let table = TableDefinition(
            version: 35,
            playfieldSize: Vector2(x: 3, y: 3),
            gravity: .zero,
            ballRadius: 0.05,
            collisionShapes: [.arc(arc)]
        )
        var simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [BallState(id: 1, position: Vector2(x: 1, y: 0), velocity: .zero)]
            )
        )

        let frame = simulation.step(.idle)

        #expect(frame.balls[0].position == Vector2(x: 1.1, y: 0))
        #expect(frame.balls[0].velocity == .zero)
    }

    @Test("thick arc with no inner free region depenetrates through the outer face")
    func thickArcDepenetratesOutwardFromCenter() throws {
        let arc = ArcCollider(
            center: .zero,
            radius: 0.05,
            startAngle: -Double.pi / 4,
            endAngle: Double.pi / 4,
            thickness: 0.2,
            restitution: 1
        )
        let hit = ContinuousCollision.sweepCircle(
            from: .zero,
            displacement: .zero,
            radius: 0.05,
            against: .arc(arc)
        )

        #expect(hit?.time == 0)
        #expect(hit?.startedOverlapping == true)
        #expect(hit?.center == Vector2(x: 0.2, y: 0))
        #expect(hit?.normal == Vector2(x: 1, y: 0))

        let table = TableDefinition(
            version: 36,
            playfieldSize: Vector2(x: 1, y: 1),
            gravity: .zero,
            ballRadius: 0.05,
            collisionShapes: [.arc(arc)]
        )
        var simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [BallState(id: 1, position: .zero, velocity: .zero)]
            )
        )

        let frame = simulation.step(.idle)

        #expect(frame.balls[0].position == Vector2(x: 0.2, y: 0))
    }

    @Test("restitution reflects only the velocity entering the surface")
    func restitutionReflectsIncomingVelocity() {
        let reflected = ContinuousCollision.resolvedVelocity(
            Vector2(x: 4, y: -3),
            normal: Vector2(x: -1, y: 0),
            restitution: 0.5
        )
        let separating = ContinuousCollision.resolvedVelocity(
            Vector2(x: -4, y: -3),
            normal: Vector2(x: -1, y: 0),
            restitution: 1
        )

        #expect(reflected == Vector2(x: -2, y: -3))
        #expect(separating == Vector2(x: -4, y: -3))
    }

    @Test("simulation prevents high-speed tunneling through a rail")
    func simulationPreventsHighSpeedTunneling() throws {
        let table = TableDefinition(
            version: 31,
            playfieldSize: Vector2(x: 2, y: 2),
            gravity: .zero,
            ballRadius: 0.05,
            collisionShapes: [
                .segment(
                    SegmentCollider(
                        start: Vector2(x: 1, y: 0),
                        end: Vector2(x: 1, y: 2),
                        radius: 0,
                        restitution: 1
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
                        position: Vector2(x: 0.25, y: 1),
                        velocity: Vector2(x: 600, y: 0)
                    )
                ]
            )
        )

        let frame = simulation.step(.idle)

        #expect(frame.balls[0].position.x < 1)
        #expect(frame.balls[0].velocity.x == -600)
    }

    @Test("collision budget never falls back to unchecked motion")
    func collisionBudgetStopsUncheckedMotion() throws {
        let table = TableDefinition(
            version: 32,
            playfieldSize: Vector2(x: 1, y: 2),
            gravity: .zero,
            ballRadius: 0.05,
            collisionShapes: [
                .segment(
                    SegmentCollider(
                        start: Vector2(x: 0, y: 0),
                        end: Vector2(x: 0, y: 2),
                        radius: 0,
                        restitution: 1
                    )
                ),
                .segment(
                    SegmentCollider(
                        start: Vector2(x: 1, y: 0),
                        end: Vector2(x: 1, y: 2),
                        radius: 0,
                        restitution: 1
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
                        position: Vector2(x: 0.5, y: 1),
                        velocity: Vector2(x: 2_400, y: 0)
                    )
                ]
            )
        )

        let frame = simulation.step(.idle)

        #expect(frame.balls[0].position.x >= table.ballRadius)
        #expect(frame.balls[0].position.x <= 1 - table.ballRadius)
    }

    @Test("singular circle overlap depenetrates once with a stable normal")
    func singularCircleOverlapDepenetratesOnce() throws {
        let center = Vector2(x: 0.5, y: 1)
        let table = TableDefinition(
            version: 33,
            playfieldSize: Vector2(x: 1, y: 2),
            gravity: .zero,
            ballRadius: 0.05,
            bumpers: [
                BumperDefinition(
                    id: "center",
                    collider: CircleCollider(center: center, radius: 0.05, restitution: 1),
                    impulse: 2
                )
            ]
        )
        var simulation = try PinballSimulation(
            table: table,
            snapshot: SimulationSnapshot(
                tableVersion: table.version,
                elapsedTime: 0,
                balls: [BallState(id: 1, position: center, velocity: Vector2(x: 12, y: 0))]
            )
        )

        let frame = simulation.step(.idle)
        let offset = frame.balls[0].position - center

        #expect(frame.events == [GameEvent(name: "bumper:center")])
        #expect(offset.length >= 0.1)
        #expect(frame.balls[0].velocity.dot(offset) >= 0)
        #expect(frame.balls[0].position.x.isFinite)
    }

    @Test("singular segment overlap depenetrates once without normal ping pong")
    func singularSegmentOverlapDepenetratesOnce() throws {
        let railX = 0.5
        let table = TableDefinition(
            version: 34,
            playfieldSize: Vector2(x: 1, y: 2),
            gravity: .zero,
            ballRadius: 0.05,
            targets: [
                TargetDefinition(
                    id: "axis",
                    collider: SegmentCollider(
                        start: Vector2(x: railX, y: 0),
                        end: Vector2(x: railX, y: 2),
                        radius: 0.01,
                        restitution: 1
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
                        position: Vector2(x: railX, y: 1),
                        velocity: Vector2(x: 12, y: 0)
                    )
                ]
            )
        )

        let frame = simulation.step(.idle)
        let horizontalOffset = frame.balls[0].position.x - railX

        #expect(frame.events == [GameEvent(name: "target:axis")])
        #expect(abs(horizontalOffset) >= 0.06)
        #expect(frame.balls[0].velocity.x * horizontalOffset >= 0)
    }

    @Test("collision value types are sendable")
    func collisionTypesAreSendable() {
        requireSendable(SweepHit.self)
        requireSendable(SegmentCollider.self)
        requireSendable(CircleCollider.self)
        requireSendable(ArcCollider.self)
        requireSendable(CollisionShape.self)
    }

    private func requireSendable<T: Sendable>(_: T.Type) {}
}
