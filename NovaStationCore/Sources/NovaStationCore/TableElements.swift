public enum FlipperControl: String, Sendable, Codable, Equatable {
    case left
    case right
}

public struct FlipperDefinition: Sendable, Codable, Equatable {
    public var id: String
    public var control: FlipperControl
    public var pivot: Vector2
    public var length: Double
    public var radius: Double
    public var restAngle: Double
    public var activeAngle: Double
    public var angularSpeed: Double
    public var impulseScale: Double

    public init(
        id: String,
        control: FlipperControl = .left,
        pivot: Vector2,
        length: Double,
        radius: Double,
        restAngle: Double,
        activeAngle: Double,
        angularSpeed: Double,
        impulseScale: Double
    ) {
        self.id = id
        self.control = control
        self.pivot = pivot
        self.length = length
        self.radius = radius
        self.restAngle = restAngle
        self.activeAngle = activeAngle
        self.angularSpeed = angularSpeed
        self.impulseScale = impulseScale
    }
}

public struct FlipperState: Sendable, Codable, Equatable {
    public var definition: FlipperDefinition
    public private(set) var angle: Double
    public private(set) var angularVelocity: Double

    public init(definition: FlipperDefinition) {
        self.definition = definition
        self.angle = definition.restAngle
        self.angularVelocity = 0
    }

    public init(definition: FlipperDefinition, angle: Double, angularVelocity: Double) {
        self.definition = definition
        self.angle = angle
        self.angularVelocity = angularVelocity
    }

    public mutating func update(isPressed: Bool, timeStep: Double) {
        let target = isPressed ? definition.activeAngle : definition.restAngle
        let difference = target - angle
        guard timeStep > 0, difference != 0 else {
            angularVelocity = 0
            return
        }
        let maximumChange = max(0, definition.angularSpeed) * timeStep
        let change = min(abs(difference), maximumChange) * (difference > 0 ? 1 : -1)
        angle += change
        angularVelocity = change / timeStep
    }

    public func surfaceVelocity(at contactPoint: Vector2) -> Vector2 {
        let radius = contactPoint - definition.pivot
        return Vector2(x: -angularVelocity * radius.y, y: angularVelocity * radius.x)
    }

    public func transferredVelocity(
        ballVelocity: Vector2,
        contactPoint: Vector2,
        normal: Vector2
    ) -> Vector2 {
        let unitNormal = normal.normalized
        let transfer = max(
            0,
            (surfaceVelocity(at: contactPoint) - ballVelocity).dot(unitNormal)
        )
            * max(0, definition.impulseScale)
        return ballVelocity + unitNormal * transfer
    }
}

public struct PlungerDefinition: Sendable, Codable, Equatable {
    public var position: Vector2
    public var launchRadius: Double
    public var launchDirection: Vector2
    public var maximumImpulse: Double
    public var releaseThreshold: Double

    public init(
        position: Vector2,
        launchRadius: Double,
        launchDirection: Vector2,
        maximumImpulse: Double,
        releaseThreshold: Double = 0.01
    ) {
        self.position = position
        self.launchRadius = launchRadius
        self.launchDirection = launchDirection
        self.maximumImpulse = maximumImpulse
        self.releaseThreshold = releaseThreshold
    }
}

public struct PlungerState: Sendable, Codable, Equatable {
    public private(set) var pull: Double

    public init(pull: Double = 0) {
        self.pull = min(max(pull, 0), 1)
    }

    public mutating func update(pull requestedPull: Double, definition: PlungerDefinition) -> Vector2? {
        let clampedPull = min(max(requestedPull, 0), 1)
        let nextPull = clampedPull <= definition.releaseThreshold ? 0 : clampedPull
        let releasedPull = nextPull == 0 ? pull : 0
        pull = nextPull
        guard releasedPull > 0 else { return nil }
        return definition.launchDirection.normalized
            * (releasedPull * max(0, definition.maximumImpulse))
    }
}

public struct BumperDefinition: Sendable, Codable, Equatable {
    public var id: String
    public var collider: CircleCollider
    public var impulse: Double

    public init(id: String, collider: CircleCollider, impulse: Double) {
        self.id = id
        self.collider = collider
        self.impulse = impulse
    }
}

public struct TargetDefinition: Sendable, Codable, Equatable {
    public var id: String
    public var collider: SegmentCollider

    public init(id: String, collider: SegmentCollider) {
        self.id = id
        self.collider = collider
    }
}

public enum SensorCrossingDirection: String, Sendable, Codable, Equatable {
    case any, upward, downward
}

public struct SensorDefinition: Sendable, Codable, Equatable {
    public var id: String
    public var shape: CollisionShape
    public var eventName: String?
    public var crossingDirection: SensorCrossingDirection
    public var minimumSpeed: Double?
    public var maximumSpeed: Double?

    public init(
        id: String,
        shape: CollisionShape,
        eventName: String? = nil,
        crossingDirection: SensorCrossingDirection = .any,
        minimumSpeed: Double? = nil,
        maximumSpeed: Double? = nil
    ) {
        self.id = id
        self.shape = shape
        self.eventName = eventName
        self.crossingDirection = crossingDirection
        self.minimumSpeed = minimumSpeed
        self.maximumSpeed = maximumSpeed
    }

    private enum CodingKeys: String, CodingKey {
        case id, shape, eventName, crossingDirection, minimumSpeed, maximumSpeed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            shape: try container.decode(CollisionShape.self, forKey: .shape),
            eventName: try container.decodeIfPresent(String.self, forKey: .eventName),
            crossingDirection: try container.decodeIfPresent(
                SensorCrossingDirection.self,
                forKey: .crossingDirection
            ) ?? .any,
            minimumSpeed: try container.decodeIfPresent(Double.self, forKey: .minimumSpeed),
            maximumSpeed: try container.decodeIfPresent(Double.self, forKey: .maximumSpeed)
        )
    }
}

public struct TiltDefinition: Sendable, Codable, Equatable {
    public var threshold: Double
    public var decayPerSecond: Double

    public init(threshold: Double, decayPerSecond: Double) {
        self.threshold = threshold
        self.decayPerSecond = decayPerSecond
    }
}

public struct TiltState: Sendable, Codable, Equatable {
    public private(set) var accumulatedNudge: Double
    public private(set) var isTilted: Bool

    public init(accumulatedNudge: Double = 0, isTilted: Bool = false) {
        self.accumulatedNudge = max(0, accumulatedNudge)
        self.isTilted = isTilted
    }

    @discardableResult
    public mutating func update(
        nudgeMagnitude: Double,
        definition: TiltDefinition,
        timeStep: Double
    ) -> Bool {
        guard !isTilted else { return false }
        accumulatedNudge = max(
            0,
            accumulatedNudge - max(0, definition.decayPerSecond) * max(0, timeStep)
        ) + max(0, nudgeMagnitude)
        guard accumulatedNudge >= max(0, definition.threshold) else { return false }
        isTilted = true
        return true
    }
}
