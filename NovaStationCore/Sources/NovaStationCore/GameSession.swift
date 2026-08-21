public enum GameSessionPhase: String, Sendable, Codable, Equatable {
    case launch
    case playing
    case gameOver
}

public struct GameSessionState: Sendable, Codable, Equatable {
    public var simulation: SimulationRuntimeState
    public var rules: GameRulesState
    public var phase: GameSessionPhase
    public var nextBallID: UInt64
    public var pendingPlungerPull: Double
    public var armedShooterCommand: String?

    public init(
        simulation: SimulationRuntimeState,
        rules: GameRulesState,
        phase: GameSessionPhase,
        nextBallID: UInt64,
        pendingPlungerPull: Double = 0,
        armedShooterCommand: String? = nil
    ) {
        self.simulation = simulation
        self.rules = rules
        self.phase = phase
        self.nextBallID = nextBallID
        self.pendingPlungerPull = pendingPlungerPull
        self.armedShooterCommand = armedShooterCommand
    }
}

public struct GameSessionCheckpoint: Sendable, Codable, Equatable {
    public var currentState: GameSessionState
    public var recordingInitialState: GameSessionState
    public var recordedInputs: [ReplayInput]

    public init(
        currentState: GameSessionState,
        recordingInitialState: GameSessionState,
        recordedInputs: [ReplayInput]
    ) {
        self.currentState = currentState
        self.recordingInitialState = recordingInitialState
        self.recordedInputs = recordedInputs
    }
}

public enum GameSessionEffect: Sendable, Codable, Equatable {
    case scoreAwarded(Int)
    case bonusChanged(Int)
    case scoreMultiplierChanged(Int)
    case bonusMultiplierChanged(Int)
    case stationPowerChanged(Int)
    case extraBallAwarded
    case multiballStarted
    case ballDrained(UInt64)
    case ballSaved
    case ballSpawned(UInt64)
    case missionSelected(MissionID)
    case missionStarted(MissionID)
    case missionCompleted(MissionID)
    case missionFailed(MissionID)
    case clearanceAwarded(ClearanceLevel)
    case tilt
    case gameOver(Int)
}

public struct GameSessionFrame: Sendable, Codable, Equatable {
    public let snapshot: SimulationSnapshot
    public let rules: GameRulesState
    public let phase: GameSessionPhase
    public let events: [GameEvent]
    public let effects: [GameSessionEffect]

    public init(
        snapshot: SimulationSnapshot,
        rules: GameRulesState,
        phase: GameSessionPhase,
        events: [GameEvent],
        effects: [GameSessionEffect]
    ) {
        self.snapshot = snapshot
        self.rules = rules
        self.phase = phase
        self.events = events
        self.effects = effects
    }
}

/// Authoritative deterministic bridge between 240 Hz physics and pinball rules.
/// Every physics tick passes through this reducer exactly once.
public struct GameSession: Sendable {
    public private(set) var rules: GameRulesState
    public private(set) var phase: GameSessionPhase
    /// True as soon as the run used the Workshop (a rewind, a review or a
    /// shot drill). Irreversible for the whole run: only `startNewGame()`
    /// clears it. Assisted runs never reach the ranked high scores or Game
    /// Center, which is what keeps the leaderboard honest.
    public private(set) var isAssisted = false
    private var simulation: PinballSimulation
    private var nextBallID: UInt64
    private var recordingInitialState: GameSessionState
    private var recordedInputs: [ReplayInput]
    private var pendingPlungerPull: Double
    private var armedShooterCommand: String?

    public var snapshot: SimulationSnapshot { simulation.snapshot }
    /// Complete state of the session on the current tick, suitable for a
    /// rewind keyframe.
    public var sessionState: GameSessionState { currentState }
    public var recordedInputCount: Int { recordedInputs.count }
    public var physicsTiltState: TiltState { simulation.tiltState }
    public var table: TableDefinition { simulation.table }
    public var checkpoint: GameSessionCheckpoint {
        GameSessionCheckpoint(
            currentState: currentState,
            recordingInitialState: recordingInitialState,
            recordedInputs: recordedInputs
        )
    }
    public var recording: Replay {
        Replay(
            tableVersion: simulation.table.version,
            initialState: recordingInitialState,
            inputs: recordedInputs
        )
    }

    public init() throws {
        let simulation = try PinballSimulation(table: NovaStationTable.definition)
        self.init(simulation: simulation, rules: GameRulesState(), phase: .launch)
    }

    public init(
        simulation: PinballSimulation,
        rules: GameRulesState = GameRulesState(),
        phase: GameSessionPhase = .playing
    ) {
        self.simulation = simulation
        self.rules = rules
        self.phase = phase
        self.nextBallID = (simulation.snapshot.balls.map(\.id).max() ?? 0) + 1
        self.pendingPlungerPull = 0
        self.armedShooterCommand = nil
        self.recordingInitialState = GameSessionState(
            simulation: simulation.runtimeState,
            rules: rules,
            phase: phase,
            nextBallID: self.nextBallID
        )
        self.recordedInputs = []
    }

    public init(
        snapshot: SimulationSnapshot,
        rules: GameRulesState,
        phase: GameSessionPhase
    ) throws {
        let simulation = try PinballSimulation(table: NovaStationTable.definition, snapshot: snapshot)
        self.init(simulation: simulation, rules: rules, phase: phase)
    }

    public init(checkpoint: GameSessionCheckpoint) throws {
        let state = checkpoint.currentState
        simulation = try PinballSimulation(table: NovaStationTable.definition, runtimeState: state.simulation)
        rules = state.rules
        phase = state.phase
        nextBallID = state.nextBallID
        pendingPlungerPull = state.pendingPlungerPull
        armedShooterCommand = state.armedShooterCommand
        recordingInitialState = checkpoint.recordingInitialState
        recordedInputs = checkpoint.recordedInputs
    }

    /// Player inputs recorded from `index` onwards, in order. Drives the
    /// Workshop review playback.
    public func recordedInputs(from index: Int) -> [PlayerInput] {
        let start = min(max(0, index), recordedInputs.count)
        return recordedInputs[start...].map(\.input)
    }

    /// Restores the exact state captured by `mark` and truncates the input
    /// stream to it, so the resulting session is both playable on the next
    /// tick and still a valid Replay v3 recording. The result is always
    /// flagged assisted.
    public func rewound(to mark: RewindMark) throws -> GameSession {
        let index = min(max(0, mark.inputIndex), recordedInputs.count)
        var session = try GameSession(checkpoint: GameSessionCheckpoint(
            currentState: mark.state,
            recordingInitialState: recordingInitialState,
            recordedInputs: Array(recordedInputs.prefix(index))
        ))
        session.isAssisted = true
        return session
    }

    /// Flags the run as assisted without changing any simulation state. Used
    /// when a drill starts and when an assisted run is restored from its
    /// device-local marker after a relaunch.
    public mutating func markAssisted() {
        isAssisted = true
    }

    @discardableResult
    public mutating func startNewGame() throws -> GameSessionFrame {
        isAssisted = false
        rules = GameRulesState()
        rules.activateBallSave()
        phase = .playing
        nextBallID = 1
        pendingPlungerPull = 0
        armedShooterCommand = nil
        let ball = makeBall(position: NovaStationTable.launchPosition, velocity: .zero)
        simulation = try PinballSimulation(
            table: NovaStationTable.definition,
            snapshot: SimulationSnapshot(
                tableVersion: NovaStationTable.version,
                elapsedTime: 0,
                balls: [ball]
            )
        )
        resetRecordingAnchor()
        return currentFrame(effects: [.ballSpawned(ball.id)])
    }

    public mutating func restore(snapshot: SimulationSnapshot, rules: GameRulesState) throws {
        simulation = try PinballSimulation(table: simulation.table, snapshot: snapshot)
        self.rules = rules
        phase = rules.isGameOver ? .gameOver : (snapshot.balls.isEmpty ? .launch : .playing)
        nextBallID = (snapshot.balls.map(\.id).max() ?? 0) + 1
        pendingPlungerPull = 0
        armedShooterCommand = nil
        resetRecordingAnchor()
    }

    public mutating func restore(checkpoint: GameSessionCheckpoint) throws {
        self = try GameSession(checkpoint: checkpoint)
    }

    public mutating func restore(
        snapshot: SimulationSnapshot,
        rules: GameRulesState,
        replay: Replay
    ) throws {
        let result = try replay.replay()
        guard result.snapshot == snapshot,
              result.rules == rules,
              result.phase == (rules.isGameOver ? .gameOver : (snapshot.balls.isEmpty ? .launch : .playing))
        else { throw ReplayError.checkpointStateMismatch }
        self = try GameSession(checkpoint: result.checkpoint)
    }

    public mutating func step(_ input: PlayerInput) -> GameSessionFrame {
        guard phase == .playing else { return currentFrame() }
        recordedInputs.append(ReplayInput(input))
        updateShooterCommand(input.plungerPull)
        let physicsFrame = simulation.step(input)
        return reduce(steps: 1, events: physicsFrame.events)
    }

    /// Internal reducer seam for focused rule-unit tests only.
    mutating func process(steps: Int, events: [GameEvent]) -> GameSessionFrame {
        guard phase == .playing else { return currentFrame(events: events) }
        return reduce(steps: max(0, steps), events: events)
    }

    private mutating func reduce(steps: Int, events: [GameEvent]) -> GameSessionFrame {
        var effects: [GameSessionEffect] = []
        let missionBeforeAdvance = rules.missionState
        let powerBeforeAdvance = rules.stationPower
        rules.advance(ticks: steps)
        if powerBeforeAdvance != rules.stationPower {
            effects.append(.stationPowerChanged(rules.stationPower))
        }
        appendMissionFailureTransition(from: missionBeforeAdvance, effects: &effects)

        for event in events {
            consume(event, effects: &effects)
        }
        return currentFrame(events: events, effects: effects)
    }

    private mutating func consume(_ event: GameEvent, effects: inout [GameSessionEffect]) {
        let activeMission: MissionID? = {
            guard case let .active(id) = rules.missionState else { return nil }
            return id
        }()
        let clearanceBeforeObjective = rules.clearance
        if let activeMission,
           MissionCatalog.definition(for: activeMission).objectiveEvents.contains(event.name) {
            rules.activateBallSave()
        }
        if let activeMission,
           let award = rules.recordMissionObjective(eventName: event.name) {
            effects.append(.scoreAwarded(award.points))
            effects.append(.missionCompleted(activeMission))
            if rules.clearance != clearanceBeforeObjective, let clearance = rules.clearance {
                effects.append(.clearanceAwarded(clearance))
            }
        }

        if event.name.hasPrefix("bumper:") {
            awardTableScore(NovaStationTable.Score.bumper, effects: &effects)
            return
        }

        switch event.name {
        case NovaStationTable.Event.missionSelect:
            guard armedShooterCommand == event.name else { return }
            armedShooterCommand = nil
            if let mission = rules.selectNextMission() {
                rules.activateBallSave()
                effects.append(.missionSelected(mission))
            }

        case NovaStationTable.Event.missionStart:
            guard armedShooterCommand == event.name else { return }
            armedShooterCommand = nil
            guard let mission = rules.selectedMission,
                  let award = rules.startSelectedMission()
            else { return }
            rules.activateBallSave()
            effects.append(.scoreAwarded(award.points))
            effects.append(.missionStarted(mission))

        case NovaStationTable.Event.missionAcknowledge:
            guard armedShooterCommand == event.name else { return }
            armedShooterCommand = nil
            rules.activateBallSave()
            rules.acknowledgeMissionResult()

        case NovaStationTable.Event.bonus:
            awardTableScore(NovaStationTable.Score.target, effects: &effects)
            if rules.addBonusUnit() { effects.append(.bonusChanged(rules.bonusUnits)) }

        case NovaStationTable.Event.scoreMultiplier:
            awardTableScore(NovaStationTable.Score.target, effects: &effects)
            if rules.increaseScoreMultiplier() {
                effects.append(.scoreMultiplierChanged(rules.scoreMultiplier))
            }

        case NovaStationTable.Event.bonusMultiplier:
            awardTableScore(NovaStationTable.Score.target, effects: &effects)
            if rules.increaseBonusMultiplier() {
                effects.append(.bonusMultiplierChanged(rules.bonusMultiplier))
            }

        case NovaStationTable.Event.extraBall:
            awardTableScore(NovaStationTable.Score.target, effects: &effects)
            if rules.awardExtraBall() { effects.append(.extraBallAwarded) }

        case NovaStationTable.Event.multiball:
            awardTableScore(NovaStationTable.Score.target, effects: &effects)
            activateMultiball(effects: &effects)

        case NovaStationTable.Event.stationPower:
            awardTableScore(NovaStationTable.Score.target, effects: &effects)
            if rules.replenishStationPower() {
                effects.append(.stationPowerChanged(rules.stationPower))
            }

        case NovaStationTable.Event.drain:
            guard let ballID = event.ballID else { return }
            drain(ballID: ballID, effects: &effects)

        case "tilt":
            let missionBeforeTilt = rules.missionState
            guard !rules.isTilted else { return }
            rules.tilt()
            effects.append(.tilt)
            appendMissionFailureTransition(from: missionBeforeTilt, effects: &effects)

        default:
            if event.name.hasPrefix("target:") || event.name.hasPrefix("sensor:") {
                awardTableScore(NovaStationTable.Score.lane, effects: &effects)
            }
        }
    }

    private mutating func awardTableScore(
        _ points: Int,
        effects: inout [GameSessionEffect]
    ) {
        if let award = rules.awardTableScore(baseScore: points) {
            effects.append(.scoreAwarded(award.points))
        }
    }

    private mutating func updateShooterCommand(_ requestedPull: Double) {
        let pull = requestedPull.isFinite ? min(max(requestedPull, 0), 1) : 0
        if pull > 0.01 {
            pendingPlungerPull = pull
            return
        }
        guard pendingPlungerPull > 0 else { return }
        if pendingPlungerPull <= 0.45 {
            armedShooterCommand = NovaStationTable.Event.missionSelect
        } else if pendingPlungerPull <= 0.75 {
            armedShooterCommand = NovaStationTable.Event.missionAcknowledge
        } else {
            armedShooterCommand = NovaStationTable.Event.missionStart
        }
        pendingPlungerPull = 0
    }

    private mutating func activateMultiball(effects: inout [GameSessionEffect]) {
        guard rules.activateMultiball(), let primary = snapshot.balls.first else { return }
        let left = makeBall(
            position: primary.position + Vector2(x: -0.045, y: 0.03),
            velocity: Vector2(x: -0.7, y: 1.4)
        )
        let right = makeBall(
            position: primary.position + Vector2(x: 0.045, y: 0.03),
            velocity: Vector2(x: 0.7, y: 1.4)
        )
        replaceBalls(snapshot.balls + [left, right])
        effects += [.multiballStarted, .ballSpawned(left.id), .ballSpawned(right.id)]
    }

    private mutating func drain(ballID: UInt64, effects: inout [GameSessionEffect]) {
        guard snapshot.balls.contains(where: { $0.id == ballID }) else { return }
        if case .active = rules.missionState, !rules.isTilted {
            // Missions are played as multi-shot sequences. A clean outlane
            // returns the ball to the launcher without erasing that sequence;
            // tilt and the mission-specific abort conditions still fail it.
            rules.activateBallSave()
        }
        let hadBallSave = rules.ballSaveTicksRemaining > 0 && !rules.isTilted
        let missionBeforeDrain = rules.missionState
        var remainingBalls = snapshot.balls.filter { $0.id != ballID }
        let bonusAward = rules.drainBall()
        effects.append(.ballDrained(ballID))
        if let bonusAward { effects.append(.scoreAwarded(bonusAward.points)) }
        appendMissionFailureTransition(from: missionBeforeDrain, effects: &effects)

        if rules.isGameOver {
            phase = .gameOver
            replaceBalls([])
            effects.append(.gameOver(rules.score))
            return
        }

        if remainingBalls.isEmpty {
            let replacement = makeBall(position: NovaStationTable.launchPosition, velocity: .zero)
            remainingBalls = [replacement]
            if hadBallSave {
                effects.append(.ballSaved)
            } else {
                rules.activateBallSave()
            }
            effects.append(.ballSpawned(replacement.id))
        }
        replaceBalls(remainingBalls)
    }

    private mutating func appendMissionFailureTransition(
        from previous: MissionState,
        effects: inout [GameSessionEffect]
    ) {
        guard case let .active(previousID) = previous,
              rules.missionState == .failed(previousID)
        else { return }
        effects.append(.missionFailed(previousID))
    }

    private mutating func makeBall(position: Vector2, velocity: Vector2) -> BallState {
        defer { nextBallID += 1 }
        return BallState(id: nextBallID, position: position, velocity: velocity)
    }

    private mutating func replaceBalls(_ balls: [BallState]) {
        let replacementSnapshot = SimulationSnapshot(
            tableVersion: simulation.table.version,
            elapsedTime: simulation.snapshot.elapsedTime,
            balls: balls
        )
        do {
            simulation = try PinballSimulation(table: simulation.table, snapshot: replacementSnapshot)
        } catch {
            preconditionFailure("Nova Station generated an invalid internal ball state: \(error)")
        }
    }

    private func currentFrame(
        events: [GameEvent] = [],
        effects: [GameSessionEffect] = []
    ) -> GameSessionFrame {
        GameSessionFrame(
            snapshot: simulation.snapshot,
            rules: rules,
            phase: phase,
            events: events,
            effects: effects
        )
    }

    private mutating func resetRecordingAnchor() {
        recordingInitialState = currentState
        recordedInputs.removeAll(keepingCapacity: true)
    }

    private var currentState: GameSessionState {
        GameSessionState(
            simulation: simulation.runtimeState,
            rules: rules,
            phase: phase,
            nextBallID: nextBallID,
            pendingPlungerPull: pendingPlungerPull,
            armedShooterCommand: armedShooterCommand
        )
    }
}
