public struct BallState: Sendable, Codable, Equatable {
    public var id: UInt64
    public var position: Vector2
    public var velocity: Vector2

    public init(id: UInt64, position: Vector2, velocity: Vector2) {
        self.id = id
        self.position = position
        self.velocity = velocity
    }
}

public struct PlayerInput: Sendable, Codable, Equatable {
    public var leftFlipperIsPressed: Bool
    public var rightFlipperIsPressed: Bool
    public var plungerPull: Double
    public var nudge: Vector2

    public init(
        leftFlipperIsPressed: Bool,
        rightFlipperIsPressed: Bool,
        plungerPull: Double,
        nudge: Vector2
    ) {
        self.leftFlipperIsPressed = leftFlipperIsPressed
        self.rightFlipperIsPressed = rightFlipperIsPressed
        self.plungerPull = plungerPull
        self.nudge = nudge
    }

    public static let idle = PlayerInput(
        leftFlipperIsPressed: false,
        rightFlipperIsPressed: false,
        plungerPull: 0,
        nudge: .zero
    )
}

public struct GameEvent: Sendable, Codable, Equatable {
    public var name: String
    public var ballID: UInt64?

    public init(name: String, ballID: UInt64? = nil) {
        self.name = name
        self.ballID = ballID
    }
}

public struct SimulationSnapshot: Sendable, Codable, Equatable {
    public var tableVersion: Int
    public var elapsedTime: Double
    public var balls: [BallState]

    public init(tableVersion: Int, elapsedTime: Double, balls: [BallState]) {
        self.tableVersion = tableVersion
        self.elapsedTime = elapsedTime
        self.balls = balls
    }
}

public struct SimulationFrame: Sendable, Codable, Equatable {
    public var snapshot: SimulationSnapshot
    public var events: [GameEvent]

    public init(snapshot: SimulationSnapshot, events: [GameEvent]) {
        self.snapshot = snapshot
        self.events = events
    }

    public var elapsedTime: Double {
        snapshot.elapsedTime
    }

    public var balls: [BallState] {
        snapshot.balls
    }
}

/// Complete deterministic physics state. Unlike a visual snapshot this keeps
/// every transient mechanism needed to continue on the exact next 240 Hz tick.
public struct SimulationRuntimeState: Sendable, Codable, Equatable {
    public var snapshot: SimulationSnapshot
    public var flipperStates: [FlipperState]
    public var plungerState: PlungerState
    public var tiltState: TiltState

    public init(
        snapshot: SimulationSnapshot,
        flipperStates: [FlipperState],
        plungerState: PlungerState,
        tiltState: TiltState
    ) {
        self.snapshot = snapshot
        self.flipperStates = flipperStates
        self.plungerState = plungerState
        self.tiltState = tiltState
    }
}

public enum SimulationError: Error, Sendable, Equatable {
    case tableVersionMismatch(expected: Int, actual: Int)
    case nonFiniteValue(path: String)
    case invalidValue(path: String)
}
