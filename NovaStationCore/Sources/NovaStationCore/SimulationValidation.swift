enum SimulationValidation {
    static func validate(table: TableDefinition) throws {
        try finiteVector(table.playfieldSize, path: "table.playfieldSize")
        try positive(table.playfieldSize.x, path: "table.playfieldSize.x")
        try positive(table.playfieldSize.y, path: "table.playfieldSize.y")
        try finiteVector(table.gravity, path: "table.gravity")
        try positive(table.ballRadius, path: "table.ballRadius")

        for (index, shape) in table.collisionShapes.enumerated() {
            try validate(shape: shape, path: "table.collisionShapes[\(index)]")
        }
        for (index, flipper) in table.flippers.enumerated() {
            let path = "table.flippers[\(index)]"
            try finiteVector(flipper.pivot, path: "\(path).pivot")
            try positive(flipper.length, path: "\(path).length")
            try nonNegative(flipper.radius, path: "\(path).radius")
            try finite(flipper.restAngle, path: "\(path).restAngle")
            try finite(flipper.activeAngle, path: "\(path).activeAngle")
            try nonNegative(flipper.angularSpeed, path: "\(path).angularSpeed")
            try nonNegative(flipper.impulseScale, path: "\(path).impulseScale")
            let sweepSubsteps = PhysicsTuning.requiredFlipperSweepSubsteps(
                ballRadius: table.ballRadius,
                flipper: flipper,
                angularTravel: PhysicsTuning.maximumFlipperAngularTravel(flipper)
            )
            guard sweepSubsteps <= Double(PhysicsTuning.maximumFlipperSweepSubsteps) else {
                throw SimulationError.invalidValue(path: "\(path).sweepSubsteps")
            }
        }
        if let plunger = table.plunger {
            try finiteVector(plunger.position, path: "table.plunger.position")
            try nonNegative(plunger.launchRadius, path: "table.plunger.launchRadius")
            try finiteVector(plunger.launchDirection, path: "table.plunger.launchDirection")
            guard plunger.launchDirection.lengthSquared > 0 else {
                throw SimulationError.invalidValue(path: "table.plunger.launchDirection")
            }
            try nonNegative(plunger.maximumImpulse, path: "table.plunger.maximumImpulse")
            try finite(plunger.releaseThreshold, path: "table.plunger.releaseThreshold")
            guard (0 ..< 1).contains(plunger.releaseThreshold) else {
                throw SimulationError.invalidValue(path: "table.plunger.releaseThreshold")
            }
        }
        for (index, bumper) in table.bumpers.enumerated() {
            try validate(circle: bumper.collider, path: "table.bumpers[\(index)].collider")
            try nonNegative(bumper.impulse, path: "table.bumpers[\(index)].impulse")
        }
        for (index, target) in table.targets.enumerated() {
            try validate(segment: target.collider, path: "table.targets[\(index)].collider")
        }
        for (index, sensor) in table.sensors.enumerated() {
            try validate(shape: sensor.shape, path: "table.sensors[\(index)].shape")
        }
        try nonNegative(table.linearFriction, path: "table.linearFriction")
        try nonNegative(table.nudgeImpulseScale, path: "table.nudgeImpulseScale")
        if let tilt = table.tilt {
            try positive(tilt.threshold, path: "table.tilt.threshold")
            try nonNegative(tilt.decayPerSecond, path: "table.tilt.decayPerSecond")
        }
    }

    static func validate(snapshot: SimulationSnapshot) throws {
        try nonNegative(snapshot.elapsedTime, path: "snapshot.elapsedTime")
        var firstIndexByBallID: [UInt64: Int] = [:]
        for (index, ball) in snapshot.balls.enumerated() {
            if let firstIndex = firstIndexByBallID[ball.id] {
                throw SimulationError.invalidValue(
                    path: "snapshot.balls[\(index)].id (duplicate \(ball.id); first at snapshot.balls[\(firstIndex)].id)"
                )
            }
            firstIndexByBallID[ball.id] = index
            try finiteVector(ball.position, path: "snapshot.balls[\(index)].position")
            try finiteVector(ball.velocity, path: "snapshot.balls[\(index)].velocity")
        }
    }

    private static func validate(shape: CollisionShape, path: String) throws {
        switch shape {
        case .segment(let segment):
            try validate(segment: segment, path: path)
        case .circle(let circle):
            try validate(circle: circle, path: path)
        case .arc(let arc):
            try finiteVector(arc.center, path: "\(path).center")
            try positive(arc.radius, path: "\(path).radius")
            try finite(arc.startAngle, path: "\(path).startAngle")
            try finite(arc.endAngle, path: "\(path).endAngle")
            try nonNegative(arc.thickness, path: "\(path).thickness")
            try restitution(arc.restitution, path: "\(path).restitution")
        }
    }

    private static func validate(segment: SegmentCollider, path: String) throws {
        try finiteVector(segment.start, path: "\(path).start")
        try finiteVector(segment.end, path: "\(path).end")
        try nonNegative(segment.radius, path: "\(path).radius")
        try restitution(segment.restitution, path: "\(path).restitution")
    }

    private static func validate(circle: CircleCollider, path: String) throws {
        try finiteVector(circle.center, path: "\(path).center")
        try nonNegative(circle.radius, path: "\(path).radius")
        try restitution(circle.restitution, path: "\(path).restitution")
    }

    private static func finiteVector(_ value: Vector2, path: String) throws {
        try finite(value.x, path: "\(path).x")
        try finite(value.y, path: "\(path).y")
    }

    private static func finite(_ value: Double, path: String) throws {
        guard value.isFinite else { throw SimulationError.nonFiniteValue(path: path) }
    }

    private static func positive(_ value: Double, path: String) throws {
        try finite(value, path: path)
        guard value > 0 else { throw SimulationError.invalidValue(path: path) }
    }

    private static func nonNegative(_ value: Double, path: String) throws {
        try finite(value, path: path)
        guard value >= 0 else { throw SimulationError.invalidValue(path: path) }
    }

    private static func restitution(_ value: Double, path: String) throws {
        try finite(value, path: path)
        guard (0 ... 1).contains(value) else {
            throw SimulationError.invalidValue(path: path)
        }
    }
}
