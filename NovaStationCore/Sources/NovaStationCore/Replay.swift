import Foundation

public struct ReplayInput: Sendable, Codable, Equatable {
    public let input: PlayerInput

    public init(_ input: PlayerInput) {
        self.input = input
    }

    private enum CodingKeys: String, CodingKey { case input }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = try container.decode(StablePlayerInput.self, forKey: .input).value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(StablePlayerInput(value: input), forKey: .input)
    }
}

public enum ReplayError: Error, Sendable, Equatable {
    case tableVersionMismatch(expected: Int, actual: Int)
    case nonFiniteValue(path: String)
    case invalidStableJSON(path: String)
    case unsupportedFormatVersion(Int)
    case checkpointStateMismatch
}

public struct ReplayResult: Sendable, Codable, Equatable {
    public let snapshot: SimulationSnapshot
    public let rules: GameRulesState
    public let phase: GameSessionPhase
    public let recording: Replay
    public let checkpoint: GameSessionCheckpoint
    public let hash: String

    public init(
        snapshot: SimulationSnapshot,
        rules: GameRulesState,
        phase: GameSessionPhase,
        recording: Replay,
        checkpoint: GameSessionCheckpoint,
        hash: String
    ) {
        self.snapshot = snapshot
        self.rules = rules
        self.phase = phase
        self.recording = recording
        self.checkpoint = checkpoint
        self.hash = hash
    }
}

/// Canonical production recording. Version 3 contains only ordered input ticks;
/// rules are reconstructed exclusively from physical SimulationFrame events.
public struct Replay: Sendable, Codable, Equatable {
    public static let formatVersion = 3

    public let tableVersion: Int
    public let initialState: GameSessionState
    public let inputs: [ReplayInput]
    public var initialSnapshot: SimulationSnapshot { initialState.simulation.snapshot }
    public var initialRules: GameRulesState { initialState.rules }
    public var initialPhase: GameSessionPhase { initialState.phase }

    public init(tableVersion: Int, initialState: GameSessionState, inputs: [ReplayInput]) {
        self.tableVersion = tableVersion
        self.initialState = initialState
        self.inputs = inputs
    }

    public init(
        tableVersion: Int,
        initialSnapshot: SimulationSnapshot,
        initialRules: GameRulesState = GameRulesState(),
        initialPhase: GameSessionPhase = .playing,
        inputs: [ReplayInput]
    ) {
        self.tableVersion = tableVersion
        self.initialState = GameSessionState(
            simulation: SimulationRuntimeState(
                snapshot: initialSnapshot,
                flipperStates: NovaStationTable.definition.flippers.map(FlipperState.init),
                plungerState: PlungerState(),
                tiltState: TiltState()
            ),
            rules: initialRules,
            phase: initialPhase,
            nextBallID: (initialSnapshot.balls.map(\.id).max() ?? 0) + 1
        )
        self.inputs = inputs
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, tableVersion, initialState, inputs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .formatVersion)
        guard version == Self.formatVersion else {
            throw ReplayError.unsupportedFormatVersion(version)
        }
        tableVersion = try container.decode(Int.self, forKey: .tableVersion)
        initialState = try container.decode(GameSessionState.self, forKey: .initialState)
        inputs = try container.decode([ReplayInput].self, forKey: .inputs)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.formatVersion, forKey: .formatVersion)
        try container.encode(tableVersion, forKey: .tableVersion)
        try container.encode(initialState, forKey: .initialState)
        try container.encode(inputs, forKey: .inputs)
    }

    public func stableJSON() throws -> String {
        String(decoding: try encodedJSON(), as: UTF8.self)
    }

    public func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decodeJSON(_ data: Data) throws -> Replay {
        guard let json = String(data: data, encoding: .utf8) else {
            throw ReplayError.invalidStableJSON(path: "root")
        }
        return try Replay(stableJSON: json)
    }

    public init(stableJSON: String) throws {
        guard let data = stableJSON.data(using: .utf8) else {
            throw ReplayError.invalidStableJSON(path: "root")
        }
        do {
            self = try JSONDecoder().decode(Replay.self, from: data)
        } catch let error as ReplayError {
            throw error
        } catch {
            throw ReplayError.invalidStableJSON(path: "root")
        }
        guard try encodedJSON() == data else {
            throw ReplayError.invalidStableJSON(path: "noncanonical")
        }
    }

    public func replay() throws -> ReplayResult {
        guard tableVersion == NovaStationTable.version else {
            throw ReplayError.tableVersionMismatch(expected: NovaStationTable.version, actual: tableVersion)
        }
        let anchor = GameSessionCheckpoint(
            currentState: initialState,
            recordingInitialState: initialState,
            recordedInputs: []
        )
        var session = try GameSession(checkpoint: anchor)
        for input in inputs {
            _ = session.step(input.input)
        }
        let resultRecording = session.recording
        var hasher = try StableHasher()
        hasher.combine(try stableJSON())
        hasher.combine(try stableSessionResult(
            snapshot: session.snapshot,
            rules: session.rules,
            phase: session.phase
        ))
        return ReplayResult(
            snapshot: session.snapshot,
            rules: session.rules,
            phase: session.phase,
            recording: resultRecording,
            checkpoint: session.checkpoint,
            hash: hasher.finalize()
        )
    }

    private func validate() throws {
        guard tableVersion == initialSnapshot.tableVersion else {
            throw ReplayError.tableVersionMismatch(expected: tableVersion, actual: initialSnapshot.tableVersion)
        }
        try finite(initialSnapshot.elapsedTime, path: "initialSnapshot.elapsedTime")
        for (index, ball) in initialSnapshot.balls.enumerated() {
            try finite(ball.position.x, path: "initialSnapshot.balls[\(index)].position.x")
            try finite(ball.position.y, path: "initialSnapshot.balls[\(index)].position.y")
            try finite(ball.velocity.x, path: "initialSnapshot.balls[\(index)].velocity.x")
            try finite(ball.velocity.y, path: "initialSnapshot.balls[\(index)].velocity.y")
        }
        for (index, flipper) in initialState.simulation.flipperStates.enumerated() {
            try finite(flipper.angle, path: "initialState.flippers[\(index)].angle")
            try finite(flipper.angularVelocity, path: "initialState.flippers[\(index)].angularVelocity")
        }
        try finite(initialState.simulation.plungerState.pull, path: "initialState.plunger.pull")
        try finite(initialState.simulation.tiltState.accumulatedNudge, path: "initialState.tilt.accumulatedNudge")
        try finite(initialState.pendingPlungerPull, path: "initialState.pendingPlungerPull")
        for (index, replayInput) in inputs.enumerated() {
            try finite(replayInput.input.plungerPull, path: "inputs[\(index)].plungerPull")
            try finite(replayInput.input.nudge.x, path: "inputs[\(index)].nudge.x")
            try finite(replayInput.input.nudge.y, path: "inputs[\(index)].nudge.y")
        }
    }
}

private func stableSessionResult(
    snapshot: SimulationSnapshot,
    rules: GameRulesState,
    phase: GameSessionPhase
) throws -> String {
    struct Payload: Encodable {
        let phase: GameSessionPhase
        let rules: GameRulesState
        let snapshot: StableSnapshot
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(Payload(
        phase: phase,
        rules: rules,
        snapshot: StableSnapshot(value: snapshot)
    )), as: UTF8.self)
}

private func finite(_ value: Double, path: String) throws {
    guard value.isFinite else { throw ReplayError.nonFiniteValue(path: path) }
}

private struct StableVector: Codable {
    let value: Vector2
    private enum CodingKeys: String, CodingKey { case x, y }
    init(value: Vector2) { self.value = value }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = Vector2(
            x: try decodeDouble(container, .x),
            y: try decodeDouble(container, .y)
        )
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encodeDouble(value.x, into: &container, key: .x)
        try encodeDouble(value.y, into: &container, key: .y)
    }
}

private struct StablePlayerInput: Codable {
    let value: PlayerInput
    private enum CodingKeys: String, CodingKey {
        case leftFlipperIsPressed, rightFlipperIsPressed, plungerPull, nudge
    }
    init(value: PlayerInput) { self.value = value }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = PlayerInput(
            leftFlipperIsPressed: try container.decode(Bool.self, forKey: .leftFlipperIsPressed),
            rightFlipperIsPressed: try container.decode(Bool.self, forKey: .rightFlipperIsPressed),
            plungerPull: try decodeDouble(container, .plungerPull),
            nudge: try container.decode(StableVector.self, forKey: .nudge).value
        )
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value.leftFlipperIsPressed, forKey: .leftFlipperIsPressed)
        try container.encode(value.rightFlipperIsPressed, forKey: .rightFlipperIsPressed)
        try encodeDouble(value.plungerPull, into: &container, key: .plungerPull)
        try container.encode(StableVector(value: value.nudge), forKey: .nudge)
    }
}

private struct StableSnapshot: Codable {
    let value: SimulationSnapshot
    private enum CodingKeys: String, CodingKey { case tableVersion, elapsedTime, balls }
    init(value: SimulationSnapshot) { self.value = value }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = SimulationSnapshot(
            tableVersion: try container.decode(Int.self, forKey: .tableVersion),
            elapsedTime: try decodeDouble(container, .elapsedTime),
            balls: try container.decode([StableBall].self, forKey: .balls).map(\.value)
        )
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value.tableVersion, forKey: .tableVersion)
        try encodeDouble(value.elapsedTime, into: &container, key: .elapsedTime)
        try container.encode(value.balls.map(StableBall.init), forKey: .balls)
    }
}

private struct StableBall: Codable {
    let value: BallState
    private enum CodingKeys: String, CodingKey { case id, position, velocity }
    init(value: BallState) { self.value = value }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = BallState(
            id: try decodeHex(container.decode(String.self, forKey: .id)),
            position: try container.decode(StableVector.self, forKey: .position).value,
            velocity: try container.decode(StableVector.self, forKey: .velocity).value
        )
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hex(value.id), forKey: .id)
        try container.encode(StableVector(value: value.position), forKey: .position)
        try container.encode(StableVector(value: value.velocity), forKey: .velocity)
    }
}

private func hex(_ value: UInt64) -> String {
    let raw = String(value, radix: 16)
    return String(repeating: "0", count: max(0, 16 - raw.count)) + raw
}

private func decodeHex(_ string: String) throws -> UInt64 {
    guard string.count == 16,
          string.allSatisfy({ $0.isNumber || ("a" ... "f").contains($0) }),
          let value = UInt64(string, radix: 16)
    else { throw ReplayError.invalidStableJSON(path: "hex") }
    return value
}

private func encodeDouble<Key>(
    _ value: Double,
    into container: inout KeyedEncodingContainer<Key>,
    key: Key
) throws where Key: CodingKey {
    try finite(value, path: key.stringValue)
    try container.encode(hex(value.bitPattern), forKey: key)
}

private func decodeDouble<Key>(
    _ container: KeyedDecodingContainer<Key>,
    _ key: Key
) throws -> Double where Key: CodingKey {
    let value = Double(bitPattern: try decodeHex(container.decode(String.self, forKey: key)))
    try finite(value, path: key.stringValue)
    return value
}
