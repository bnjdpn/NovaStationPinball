import Foundation

enum PhysicsTuning {
    static let stepsPerSecond = 240.0
    static let fixedTimeStep = 1.0 / stepsPerSecond
    static let standardGravity = Vector2(x: 0, y: -9.6)
    static let maximumCollisionsPerStep = 4
    static let collisionEpsilon = 1e-12
    static let maximumFlipperSweepSubsteps = 256
    static let flipperSweepGeometricErrorFraction = 0.5

    static func requiredFlipperSweepSubsteps(
        ballRadius: Double,
        flipper: FlipperDefinition,
        angularTravel: Double
    ) -> Double {
        let contactRadius = ballRadius + flipper.radius
        let maximumGeometricError = contactRadius * flipperSweepGeometricErrorFraction
        let maximumAngularStep = 2 * asin(min(1, maximumGeometricError / flipper.length))
        guard angularTravel > 0, maximumAngularStep > 0 else { return 1 }
        return max(1, ceil(angularTravel / maximumAngularStep))
    }

    static func maximumFlipperAngularTravel(_ flipper: FlipperDefinition) -> Double {
        min(
            abs(flipper.activeAngle - flipper.restAngle),
            flipper.angularSpeed * fixedTimeStep
        )
    }
}

public struct PinballSimulation: Sendable {
    public static let fixedTimeStep = PhysicsTuning.fixedTimeStep

    public let table: TableDefinition
    public private(set) var snapshot: SimulationSnapshot
    public private(set) var flipperStates: [FlipperState]
    public private(set) var plungerState: PlungerState
    public private(set) var tiltState: TiltState
    public var runtimeState: SimulationRuntimeState {
        SimulationRuntimeState(
            snapshot: snapshot,
            flipperStates: flipperStates,
            plungerState: plungerState,
            tiltState: tiltState
        )
    }

    public init() {
        self.init(uncheckedTable: .standard)
    }

    public init(table: TableDefinition) throws {
        try SimulationValidation.validate(table: table)
        self.init(uncheckedTable: table)
    }

    private init(uncheckedTable table: TableDefinition) {
        self.table = table
        self.snapshot = SimulationSnapshot(
            tableVersion: table.version,
            elapsedTime: 0,
            balls: []
        )
        self.flipperStates = table.flippers.map(FlipperState.init)
        self.plungerState = PlungerState()
        self.tiltState = TiltState()
    }

    public init(
        table: TableDefinition,
        snapshot: SimulationSnapshot
    ) throws {
        try SimulationValidation.validate(table: table)
        guard snapshot.tableVersion == table.version else {
            throw SimulationError.tableVersionMismatch(
                expected: table.version,
                actual: snapshot.tableVersion
            )
        }
        try SimulationValidation.validate(snapshot: snapshot)

        self.table = table
        self.snapshot = snapshot
        self.flipperStates = table.flippers.map(FlipperState.init)
        self.plungerState = PlungerState()
        self.tiltState = TiltState()
    }

    public init(table: TableDefinition, runtimeState: SimulationRuntimeState) throws {
        try SimulationValidation.validate(table: table)
        guard runtimeState.snapshot.tableVersion == table.version else {
            throw SimulationError.tableVersionMismatch(
                expected: table.version,
                actual: runtimeState.snapshot.tableVersion
            )
        }
        try SimulationValidation.validate(snapshot: runtimeState.snapshot)
        guard runtimeState.flipperStates.count == table.flippers.count,
              zip(runtimeState.flipperStates, table.flippers).allSatisfy({ $0.definition == $1 }),
              runtimeState.flipperStates.allSatisfy({ $0.angle.isFinite && $0.angularVelocity.isFinite }),
              runtimeState.plungerState.pull.isFinite,
              runtimeState.tiltState.accumulatedNudge.isFinite
        else { throw SimulationError.invalidValue(path: "runtimeState") }
        self.table = table
        self.snapshot = runtimeState.snapshot
        self.flipperStates = runtimeState.flipperStates
        self.plungerState = runtimeState.plungerState
        self.tiltState = runtimeState.tiltState
    }

    public mutating func step(_ input: PlayerInput) -> SimulationFrame {
        let timeStep = Self.fixedTimeStep
        var events: [GameEvent] = []
        let previousFlipperStates = flipperStates
        let safeInput = PlayerInput(
            leftFlipperIsPressed: input.leftFlipperIsPressed,
            rightFlipperIsPressed: input.rightFlipperIsPressed,
            plungerPull: input.plungerPull.isFinite ? input.plungerPull : plungerState.pull,
            nudge: input.nudge.isFinite ? input.nudge : .zero
        )

        if let tilt = table.tilt,
           tiltState.update(
               nudgeMagnitude: safeInput.nudge.length,
               definition: tilt,
               timeStep: timeStep
           ) {
            events.append(GameEvent(name: "tilt"))
        }

        for index in flipperStates.indices {
            let requested = flipperStates[index].definition.control == .left
                ? safeInput.leftFlipperIsPressed : safeInput.rightFlipperIsPressed
            let pressed = !tiltState.isTilted && requested
            flipperStates[index].update(isPressed: pressed, timeStep: timeStep)
        }
        let animatedFlipperIndices = Set(
            flipperStates.indices.filter {
                previousFlipperStates[$0].angle != flipperStates[$0].angle
            }
        )

        if let plunger = table.plunger,
           let impulse = plungerState.update(pull: safeInput.plungerPull, definition: plunger) {
            let launchDistance = max(0, plunger.launchRadius) + max(0, table.ballRadius)
            for index in snapshot.balls.indices
            where (snapshot.balls[index].position - plunger.position).lengthSquared
                <= launchDistance * launchDistance {
                snapshot.balls[index].velocity = snapshot.balls[index].velocity + impulse
            }
        }

        let nudgeImpulse = safeInput.nudge * max(0, table.nudgeImpulseScale)
        for index in snapshot.balls.indices {
            snapshot.balls[index].velocity = snapshot.balls[index].velocity + nudgeImpulse
        }

        for index in snapshot.balls.indices {
            snapshot.balls[index].velocity.x += table.gravity.x * timeStep
            snapshot.balls[index].velocity.y += table.gravity.y * timeStep
            let damping = max(0, 1 - max(0, table.linearFriction) * timeStep)
            snapshot.balls[index].velocity = snapshot.balls[index].velocity * damping
            advanceBall(
                at: index,
                timeStep: timeStep,
                previousFlipperStates: previousFlipperStates,
                animatedFlipperIndices: animatedFlipperIndices,
                events: &events
            )
        }

        snapshot.elapsedTime += timeStep
        return SimulationFrame(snapshot: snapshot, events: events)
    }

    private mutating func advanceBall(
        at index: Int,
        timeStep: Double,
        previousFlipperStates: [FlipperState],
        animatedFlipperIndices: Set<Int>,
        events: inout [GameEvent]
    ) {
        var remainingTime = timeStep
        var collisionCount = 0
        let surfaces = collisionSurfaces(excludingFlippers: animatedFlipperIndices)
        var effectedSurfaceIndices: Set<Int> = []
        var effectedAnimatedFlipperIndices: Set<Int> = []

        while remainingTime > 0, collisionCount < PhysicsTuning.maximumCollisionsPerStep {
            let displacement = snapshot.balls[index].velocity * remainingTime
            let start = snapshot.balls[index].position
            let staticCandidate = surfaces.enumerated().compactMap {
                surfaceIndex, surface -> CollisionCandidate? in
                guard let hit = ContinuousCollision.sweepCircle(
                    from: start,
                    displacement: displacement,
                    radius: table.ballRadius,
                    against: surface.shape
                ) else {
                    return nil
                }
                let surfaceVelocity = surface.flipperIndex.map {
                    flipperStates[$0].surfaceVelocity(at: hit.point)
                } ?? .zero
                let relativeDisplacement = displacement - surfaceVelocity * remainingTime
                guard hit.startedOverlapping
                    || relativeDisplacement.dot(hit.normal) < -PhysicsTuning.collisionEpsilon else {
                    return nil
                }
                return CollisionCandidate(
                    time: hit.time,
                    tieBreakGroup: 0,
                    tieBreakIndex: surfaceIndex,
                    contact: .staticSurface(index: surfaceIndex, hit: hit)
                )
            }.min { lhs, rhs in
                lhs.precedes(rhs)
            }
            let elapsedTime = timeStep - remainingTime
            let animatedCandidate = animatedFlipperCandidate(
                for: snapshot.balls[index],
                from: previousFlipperStates,
                animatedFlipperIndices: animatedFlipperIndices,
                elapsedTime: elapsedTime,
                remainingTime: remainingTime,
                timeStep: timeStep
            )
            let candidate = [staticCandidate, animatedCandidate]
                .compactMap { $0 }
                .min { $0.precedes($1) }

            guard let candidate else {
                recordSensorCrossings(
                    from: start,
                    displacement: displacement,
                    velocity: snapshot.balls[index].velocity,
                    ballID: snapshot.balls[index].id,
                    events: &events
                )
                snapshot.balls[index].position = start + displacement
                return
            }

            recordSensorCrossings(
                from: start,
                displacement: displacement * candidate.time,
                velocity: snapshot.balls[index].velocity,
                ballID: snapshot.balls[index].id,
                events: &events
            )

            switch candidate.contact {
            case .staticSurface(let surfaceIndex, let hit):
                let surface = surfaces[surfaceIndex]
                snapshot.balls[index].position = hit.center
                let isFirstEffect = effectedSurfaceIndices.insert(surfaceIndex).inserted
                if let flipperIndex = surface.flipperIndex {
                    snapshot.balls[index].velocity = resolvedFlipperVelocity(
                        state: flipperStates[flipperIndex],
                        ballVelocity: snapshot.balls[index].velocity,
                        contactPoint: hit.point,
                        normal: hit.normal,
                        includeBoost: isFirstEffect
                    )
                } else {
                    snapshot.balls[index].velocity = ContinuousCollision.resolvedVelocity(
                        snapshot.balls[index].velocity,
                        normal: hit.normal,
                        restitution: surface.shape.restitution
                    )
                }
                if isFirstEffect {
                    snapshot.balls[index].velocity = snapshot.balls[index].velocity
                        + hit.normal * max(0, surface.impulse)
                }
                if isFirstEffect, let eventName = surface.eventName {
                    events.append(GameEvent(name: eventName))
                }

            case .animatedFlipper(let hit):
                snapshot.balls[index].position = hit.center
                let isFirstEffect = effectedAnimatedFlipperIndices
                    .insert(hit.flipperIndex).inserted
                snapshot.balls[index].velocity = resolvedFlipperVelocity(
                    state: flipperStates[hit.flipperIndex],
                    ballVelocity: snapshot.balls[index].velocity,
                    contactPoint: hit.contactPoint,
                    normal: hit.normal,
                    includeBoost: isFirstEffect
                )
            }

            remainingTime *= max(0, 1 - candidate.time)
            collisionCount += 1
        }

        // Reaching the deterministic contact budget freezes the unused fraction
        // of this tick instead of applying unchecked motion through geometry.
    }

    private func collisionSurfaces(excludingFlippers excludedFlipperIndices: Set<Int>)
        -> [CollisionSurface] {
        table.collisionShapes.map {
            CollisionSurface(shape: $0, impulse: 0, eventName: nil, flipperIndex: nil)
        } + table.bumpers.map {
            CollisionSurface(
                shape: .circle($0.collider),
                impulse: $0.impulse,
                eventName: "bumper:\($0.id)",
                flipperIndex: nil
            )
        } + table.targets.map {
            CollisionSurface(
                shape: .segment($0.collider),
                impulse: 0,
                eventName: "target:\($0.id)",
                flipperIndex: nil
            )
        } + flipperStates.enumerated().compactMap { index, state in
            guard !excludedFlipperIndices.contains(index) else { return nil }
            let direction = Vector2(x: cos(state.angle), y: sin(state.angle))
            return CollisionSurface(
                shape: .segment(
                    SegmentCollider(
                        start: state.definition.pivot,
                        end: state.definition.pivot + direction * state.definition.length,
                        radius: state.definition.radius,
                        restitution: 0
                    )
                ),
                impulse: 0,
                eventName: nil,
                flipperIndex: index
            )
        }
    }

    private func animatedFlipperCandidate(
        for ball: BallState,
        from previousStates: [FlipperState],
        animatedFlipperIndices: Set<Int>,
        elapsedTime: Double,
        remainingTime: Double,
        timeStep: Double
    ) -> CollisionCandidate? {
        let elapsedFraction = elapsedTime / timeStep
        var earliestCandidate: CollisionCandidate?

        for flipperIndex in animatedFlipperIndices.sorted() {
            let previous = previousStates[flipperIndex]
            let current = flipperStates[flipperIndex]
            let substepCount = Int(
                PhysicsTuning.requiredFlipperSweepSubsteps(
                    ballRadius: table.ballRadius,
                    flipper: current.definition,
                    angularTravel: abs(current.angle - previous.angle)
                )
            )
            let firstStep = max(
                1,
                Int(floor(elapsedFraction * Double(substepCount)
                    + PhysicsTuning.collisionEpsilon)) + 1
            )
            guard firstStep <= substepCount else { continue }

            for step in firstStep ... substepCount {
                let intervalEndFraction = Double(step) / Double(substepCount)
                let intervalStartFraction = max(
                    elapsedFraction,
                    Double(step - 1) / Double(substepCount)
                )
                let intervalStartDelay = intervalStartFraction * timeStep - elapsedTime
                let intervalDuration = (intervalEndFraction - intervalStartFraction) * timeStep
                let intervalBallStart = ball.position + ball.velocity * intervalStartDelay
                let intervalBallDisplacement = ball.velocity * intervalDuration
                let intervalEndAngle = previous.angle
                    + (current.angle - previous.angle) * intervalEndFraction
                let intervalEndDirection = Vector2(
                    x: cos(intervalEndAngle),
                    y: sin(intervalEndAngle)
                )
                let intervalEndShape = CollisionShape.segment(
                    SegmentCollider(
                        start: current.definition.pivot,
                        end: current.definition.pivot
                            + intervalEndDirection * current.definition.length,
                        radius: current.definition.radius,
                        restitution: 0
                    )
                )
                guard let intervalHit = ContinuousCollision.sweepCircle(
                    from: intervalBallStart,
                    displacement: intervalBallDisplacement,
                    radius: table.ballRadius,
                    against: intervalEndShape
                ) else {
                    continue
                }

                let intervalHitFraction = intervalHit.startedOverlapping ? 1 : intervalHit.time
                let absoluteFraction = intervalStartFraction
                    + (intervalEndFraction - intervalStartFraction) * intervalHitFraction
                let contactDelay = absoluteFraction * timeStep - elapsedTime
                let localTime = min(max(contactDelay / remainingTime, 0), 1)
                let contactAngle = previous.angle
                    + (current.angle - previous.angle) * absoluteFraction
                let contactDirection = Vector2(x: cos(contactAngle), y: sin(contactAngle))
                let contactEndpoint = current.definition.pivot
                    + contactDirection * current.definition.length
                let contactAxis = contactEndpoint - current.definition.pivot
                let contactLength = contactAxis.length
                guard contactLength > PhysicsTuning.collisionEpsilon else { break }
                let tangent = contactAxis / contactLength
                let ballPosition = intervalBallStart
                    + intervalBallDisplacement * intervalHitFraction
                let projection = min(
                    max((ballPosition - current.definition.pivot).dot(tangent), 0),
                    contactLength
                )
                let contactPoint = current.definition.pivot + tangent * projection
                let offset = ballPosition - contactPoint
                let contactRadius = table.ballRadius + current.definition.radius
                guard offset.lengthSquared
                    <= contactRadius * contactRadius + PhysicsTuning.collisionEpsilon else {
                    continue
                }

                let surfaceVelocity = current.surfaceVelocity(at: contactPoint)
                let fallback = surfaceVelocity.normalized
                let normal = offset.length > PhysicsTuning.collisionEpsilon
                    ? offset.normalized
                    : (fallback == .zero ? tangent.leftPerpendicular : fallback)
                guard (surfaceVelocity - ball.velocity).dot(normal)
                    > PhysicsTuning.collisionEpsilon else {
                    continue
                }

                let hit = AnimatedFlipperHit(
                    absoluteFraction: absoluteFraction,
                    flipperIndex: flipperIndex,
                    center: contactPoint + normal * contactRadius,
                    contactPoint: contactPoint,
                    normal: normal
                )
                let candidate = CollisionCandidate(
                    time: localTime,
                    tieBreakGroup: 1,
                    tieBreakIndex: flipperIndex,
                    contact: .animatedFlipper(hit)
                )
                if let currentEarliest = earliestCandidate {
                    if candidate.precedes(currentEarliest) {
                        earliestCandidate = candidate
                    }
                } else {
                    earliestCandidate = candidate
                }
                break
            }
        }

        return earliestCandidate
    }

    private func resolvedFlipperVelocity(
        state: FlipperState,
        ballVelocity: Vector2,
        contactPoint: Vector2,
        normal: Vector2,
        includeBoost: Bool
    ) -> Vector2 {
        let surfaceVelocity = state.surfaceVelocity(at: contactPoint)
        let relativeVelocity = ballVelocity - surfaceVelocity
        var resolved = ContinuousCollision.resolvedVelocity(
            relativeVelocity,
            normal: normal,
            restitution: 0
        ) + surfaceVelocity
        if includeBoost {
            resolved = resolved + (
                state.transferredVelocity(
                    ballVelocity: ballVelocity,
                    contactPoint: contactPoint,
                    normal: normal
                ) - ballVelocity
            )
        }
        return resolved
    }

    private func recordSensorCrossings(
        from start: Vector2,
        displacement: Vector2,
        velocity: Vector2,
        ballID: UInt64,
        events: inout [GameEvent]
    ) {
        for sensor in table.sensors {
            let speed = velocity.length
            guard sensor.crossingDirection == .any
                    || (sensor.crossingDirection == .upward && velocity.y > 0)
                    || (sensor.crossingDirection == .downward && velocity.y < 0),
                  sensor.minimumSpeed.map({ speed >= $0 }) ?? true,
                  sensor.maximumSpeed.map({ speed <= $0 }) ?? true
            else { continue }
            guard let hit = ContinuousCollision.sweepCircle(
                from: start,
                displacement: displacement,
                radius: 0,
                against: sensor.shape
            ), !hit.startedOverlapping else { continue }
            let event = GameEvent(name: sensor.eventName ?? "sensor:\(sensor.id)", ballID: ballID)
            if !events.contains(event) {
                events.append(event)
            }
        }
    }
}

private struct CollisionSurface {
    var shape: CollisionShape
    var impulse: Double
    var eventName: String?
    var flipperIndex: Int?
}

private struct AnimatedFlipperHit {
    var absoluteFraction: Double
    var flipperIndex: Int
    var center: Vector2
    var contactPoint: Vector2
    var normal: Vector2
}

private enum CollisionContact {
    case staticSurface(index: Int, hit: SweepHit)
    case animatedFlipper(AnimatedFlipperHit)
}

private struct CollisionCandidate {
    var time: Double
    var tieBreakGroup: Int
    var tieBreakIndex: Int
    var contact: CollisionContact

    func precedes(_ other: CollisionCandidate) -> Bool {
        if abs(time - other.time) > PhysicsTuning.collisionEpsilon {
            return time < other.time
        }
        if tieBreakGroup != other.tieBreakGroup {
            return tieBreakGroup < other.tieBreakGroup
        }
        return tieBreakIndex < other.tieBreakIndex
    }
}
