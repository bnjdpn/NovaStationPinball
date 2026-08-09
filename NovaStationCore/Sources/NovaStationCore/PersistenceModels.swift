import Foundation

public struct SettingsState: Sendable, Codable, Equatable {
    public static let formatVersion = 1

    public var musicEnabled: Bool
    public var soundEffectsEnabled: Bool
    public var hapticsEnabled: Bool

    public init(
        musicEnabled: Bool = true,
        soundEffectsEnabled: Bool = true,
        hapticsEnabled: Bool = true
    ) {
        self.musicEnabled = musicEnabled
        self.soundEffectsEnabled = soundEffectsEnabled
        self.hapticsEnabled = hapticsEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case musicEnabled
        case soundEffectsEnabled
        case hapticsEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try PersistenceVersion.validate(
            try container.decode(Int.self, forKey: .formatVersion),
            expected: Self.formatVersion,
            codingPath: container.codingPath
        )
        musicEnabled = try container.decode(Bool.self, forKey: .musicEnabled)
        soundEffectsEnabled = try container.decode(Bool.self, forKey: .soundEffectsEnabled)
        hapticsEnabled = try container.decode(Bool.self, forKey: .hapticsEnabled)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.formatVersion, forKey: .formatVersion)
        try container.encode(musicEnabled, forKey: .musicEnabled)
        try container.encode(soundEffectsEnabled, forKey: .soundEffectsEnabled)
        try container.encode(hapticsEnabled, forKey: .hapticsEnabled)
    }
}

public struct HighScoreEntry: Sendable, Codable, Equatable {
    public static let formatVersion = 1

    public var identifier: String
    public var playerName: String
    public var score: Int
    public var achievedAt: Date

    public init(identifier: String, playerName: String, score: Int, achievedAt: Date) {
        self.identifier = identifier
        self.playerName = playerName
        self.score = score
        self.achievedAt = achievedAt
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case identifier
        case playerName
        case score
        case achievedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try PersistenceVersion.validate(
            try container.decode(Int.self, forKey: .formatVersion),
            expected: Self.formatVersion,
            codingPath: container.codingPath
        )
        identifier = try container.decode(String.self, forKey: .identifier)
        playerName = try container.decode(String.self, forKey: .playerName)
        score = try container.decode(Int.self, forKey: .score)
        achievedAt = try container.decode(Date.self, forKey: .achievedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.formatVersion, forKey: .formatVersion)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(playerName, forKey: .playerName)
        try container.encode(score, forKey: .score)
        try container.encode(achievedAt, forKey: .achievedAt)
    }
}

public struct ActiveCheckpoint: Sendable, Codable, Equatable {
    public static let formatVersion = 3

    public var identifier: String
    public var savedAt: Date
    public var sessionCheckpoint: GameSessionCheckpoint
    public var snapshot: SimulationSnapshot { sessionCheckpoint.currentState.simulation.snapshot }
    public var rules: GameRulesState { sessionCheckpoint.currentState.rules }
    public var replay: Replay {
        Replay(
            tableVersion: sessionCheckpoint.currentState.simulation.snapshot.tableVersion,
            initialState: sessionCheckpoint.recordingInitialState,
            inputs: sessionCheckpoint.recordedInputs
        )
    }

    public init(identifier: String, savedAt: Date, sessionCheckpoint: GameSessionCheckpoint) {
        self.identifier = identifier
        self.savedAt = savedAt
        self.sessionCheckpoint = sessionCheckpoint
    }

    public init(
        identifier: String,
        savedAt: Date,
        snapshot: SimulationSnapshot,
        rules: GameRulesState,
        replay: Replay
    ) {
        self.identifier = identifier
        self.savedAt = savedAt
        let current = GameSessionState(
            simulation: SimulationRuntimeState(
                snapshot: snapshot,
                flipperStates: NovaStationTable.definition.flippers.map(FlipperState.init),
                plungerState: PlungerState(),
                tiltState: TiltState()
            ),
            rules: rules,
            phase: rules.isGameOver ? .gameOver : (snapshot.balls.isEmpty ? .launch : .playing),
            nextBallID: (snapshot.balls.map(\.id).max() ?? 0) + 1
        )
        self.sessionCheckpoint = GameSessionCheckpoint(
            currentState: current,
            recordingInitialState: replay.initialState,
            recordedInputs: replay.inputs
        )
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case identifier
        case savedAt
        case sessionCheckpoint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try PersistenceVersion.validate(
            try container.decode(Int.self, forKey: .formatVersion),
            expected: Self.formatVersion,
            codingPath: container.codingPath
        )
        identifier = try container.decode(String.self, forKey: .identifier)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        sessionCheckpoint = try container.decode(GameSessionCheckpoint.self, forKey: .sessionCheckpoint)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.formatVersion, forKey: .formatVersion)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(savedAt, forKey: .savedAt)
        try container.encode(sessionCheckpoint, forKey: .sessionCheckpoint)
    }
}

public struct CheckpointEnvelope: Sendable, Codable, Equatable {
    public static let formatVersion = 1

    public var checkpoint: ActiveCheckpoint

    public init(checkpoint: ActiveCheckpoint) {
        self.checkpoint = checkpoint
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case checkpoint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try PersistenceVersion.validate(
            try container.decode(Int.self, forKey: .formatVersion),
            expected: Self.formatVersion,
            codingPath: container.codingPath
        )
        checkpoint = try container.decode(ActiveCheckpoint.self, forKey: .checkpoint)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.formatVersion, forKey: .formatVersion)
        try container.encode(checkpoint, forKey: .checkpoint)
    }
}

private enum PersistenceVersion {
    static func validate(_ actual: Int, expected: Int, codingPath: [CodingKey]) throws {
        guard actual == expected else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: codingPath,
                    debugDescription: "Unsupported persistence format version \(actual); expected \(expected)."
                )
            )
        }
    }
}
