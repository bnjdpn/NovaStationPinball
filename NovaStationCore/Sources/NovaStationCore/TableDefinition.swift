/// Versioned table data expressed in logical table units, never display pixels.
public struct TableDefinition: Sendable, Codable, Equatable {
    public var version: Int
    public var playfieldSize: Vector2
    public var gravity: Vector2
    public var ballRadius: Double
    public var collisionShapes: [CollisionShape]
    public var flippers: [FlipperDefinition]
    public var plunger: PlungerDefinition?
    public var bumpers: [BumperDefinition]
    public var targets: [TargetDefinition]
    public var sensors: [SensorDefinition]
    public var linearFriction: Double
    public var nudgeImpulseScale: Double
    public var tilt: TiltDefinition?

    public init(
        version: Int,
        playfieldSize: Vector2,
        gravity: Vector2,
        ballRadius: Double = 0.025,
        collisionShapes: [CollisionShape] = [],
        flippers: [FlipperDefinition] = [],
        plunger: PlungerDefinition? = nil,
        bumpers: [BumperDefinition] = [],
        targets: [TargetDefinition] = [],
        sensors: [SensorDefinition] = [],
        linearFriction: Double = 0,
        nudgeImpulseScale: Double = 1,
        tilt: TiltDefinition? = nil
    ) {
        self.version = version
        self.playfieldSize = playfieldSize
        self.gravity = gravity
        self.ballRadius = ballRadius
        self.collisionShapes = collisionShapes
        self.flippers = flippers
        self.plunger = plunger
        self.bumpers = bumpers
        self.targets = targets
        self.sensors = sensors
        self.linearFriction = linearFriction
        self.nudgeImpulseScale = nudgeImpulseScale
        self.tilt = tilt
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case playfieldSize
        case gravity
        case ballRadius
        case collisionShapes
        case flippers
        case plunger
        case bumpers
        case targets
        case sensors
        case linearFriction
        case nudgeImpulseScale
        case tilt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try container.decode(Int.self, forKey: .version),
            playfieldSize: try container.decode(Vector2.self, forKey: .playfieldSize),
            gravity: try container.decode(Vector2.self, forKey: .gravity),
            ballRadius: try container.decodeIfPresent(Double.self, forKey: .ballRadius) ?? 0.025,
            collisionShapes: try container.decodeIfPresent(
                [CollisionShape].self,
                forKey: .collisionShapes
            ) ?? [],
            flippers: try container.decodeIfPresent([FlipperDefinition].self, forKey: .flippers) ?? [],
            plunger: try container.decodeIfPresent(PlungerDefinition.self, forKey: .plunger),
            bumpers: try container.decodeIfPresent([BumperDefinition].self, forKey: .bumpers) ?? [],
            targets: try container.decodeIfPresent([TargetDefinition].self, forKey: .targets) ?? [],
            sensors: try container.decodeIfPresent([SensorDefinition].self, forKey: .sensors) ?? [],
            linearFriction: try container.decodeIfPresent(
                Double.self,
                forKey: .linearFriction
            ) ?? 0,
            nudgeImpulseScale: try container.decodeIfPresent(
                Double.self,
                forKey: .nudgeImpulseScale
            ) ?? 1,
            tilt: try container.decodeIfPresent(TiltDefinition.self, forKey: .tilt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(playfieldSize, forKey: .playfieldSize)
        try container.encode(gravity, forKey: .gravity)
        try container.encode(ballRadius, forKey: .ballRadius)
        try container.encode(collisionShapes, forKey: .collisionShapes)
        try container.encode(flippers, forKey: .flippers)
        try container.encodeIfPresent(plunger, forKey: .plunger)
        try container.encode(bumpers, forKey: .bumpers)
        try container.encode(targets, forKey: .targets)
        try container.encode(sensors, forKey: .sensors)
        try container.encode(linearFriction, forKey: .linearFriction)
        try container.encode(nudgeImpulseScale, forKey: .nudgeImpulseScale)
        try container.encodeIfPresent(tilt, forKey: .tilt)
    }

    public static let standard = TableDefinition(
        version: 1,
        playfieldSize: Vector2(x: 1, y: 2),
        gravity: PhysicsTuning.standardGravity,
        ballRadius: 0.025,
        collisionShapes: [],
        flippers: [],
        plunger: nil,
        bumpers: [],
        targets: [],
        sensors: [],
        linearFriction: 0,
        nudgeImpulseScale: 1,
        tilt: nil
    )
}
