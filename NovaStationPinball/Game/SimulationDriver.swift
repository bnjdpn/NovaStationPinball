import Foundation
import NovaStationCore

struct ContinuousPlayerInput: Equatable, Sendable {
    var leftFlipperIsPressed: Bool
    var rightFlipperIsPressed: Bool
    var plungerPull: Double

    static let idle = ContinuousPlayerInput(
        leftFlipperIsPressed: false,
        rightFlipperIsPressed: false,
        plungerPull: 0
    )

    fileprivate var coreInput: PlayerInput {
        PlayerInput(
            leftFlipperIsPressed: leftFlipperIsPressed,
            rightFlipperIsPressed: rightFlipperIsPressed,
            plungerPull: plungerPull,
            nudge: .zero
        )
    }
}

enum SimulationCommand: Equatable, Sendable {
    case releasePlunger(strength: Double)
    case nudge(Vector2)
}

struct SimulationInputBatch: Equatable, Sendable {
    var continuous: ContinuousPlayerInput
    var commands: [SimulationCommand]

    static let idle = SimulationInputBatch(continuous: .idle, commands: [])
}

struct SimulationAdvanceResult {
    let sessionFrame: GameSessionFrame
    let stepsExecuted: Int
    let droppedTime: TimeInterval

    var frame: SimulationFrame {
        SimulationFrame(snapshot: sessionFrame.snapshot, events: sessionFrame.events)
    }

    var rules: GameRulesState { sessionFrame.rules }
    var phase: GameSessionPhase { sessionFrame.phase }
    var effects: [GameSessionEffect] { sessionFrame.effects }
}

struct SimulationDriver {
    private enum PlungerReleasePhase {
        case releaseOnNextTick
    }

    private var session: GameSession
    private var accumulator = 0.0
    private let maximumCatchUpSteps: Int
    private var pendingNudges: [Vector2] = []
    private var pendingPlungerReleases: [Double] = []
    private var plungerReleasePhase: PlungerReleasePhase?
    private var isPaused = false

    init(
        simulation: PinballSimulation = PinballSimulation(),
        maximumCatchUpSteps: Int = 8
    ) {
        self.session = GameSession(simulation: simulation, phase: .playing)
        self.maximumCatchUpSteps = max(1, maximumCatchUpSteps)
    }

    init(session: GameSession, maximumCatchUpSteps: Int = 8) {
        self.session = session
        self.maximumCatchUpSteps = max(1, maximumCatchUpSteps)
    }

    var snapshot: SimulationSnapshot { session.snapshot }
    var rules: GameRulesState { session.rules }
    var phase: GameSessionPhase { session.phase }
    var recording: Replay { session.recording }
    var checkpoint: GameSessionCheckpoint { session.checkpoint }
    var currentSessionFrame: GameSessionFrame {
        GameSessionFrame(
            snapshot: session.snapshot,
            rules: session.rules,
            phase: session.phase,
            events: [],
            effects: []
        )
    }

    @discardableResult
    mutating func startNewGame() throws -> GameSessionFrame {
        let frame = try session.startNewGame()
        resetTransientState()
        return frame
    }

    mutating func replaceSession(_ replacement: GameSession) {
        session = replacement
        resetTransientState()
    }

    mutating func setPaused(_ paused: Bool) {
        guard isPaused != paused else { return }
        isPaused = paused
        accumulator = 0
        pendingNudges.removeAll(keepingCapacity: true)
        pendingPlungerReleases.removeAll(keepingCapacity: true)
        plungerReleasePhase = nil
    }

    mutating func restore(snapshot: SimulationSnapshot) throws {
        try restore(snapshot: snapshot, rules: session.rules)
    }

    mutating func restore(snapshot: SimulationSnapshot, rules: GameRulesState) throws {
        try session.restore(snapshot: snapshot, rules: rules)
        resetTransientState()
    }

    mutating func restore(
        snapshot: SimulationSnapshot,
        rules: GameRulesState,
        replay: Replay
    ) throws {
        try session.restore(snapshot: snapshot, rules: rules, replay: replay)
        resetTransientState()
    }

    mutating func restore(checkpoint: GameSessionCheckpoint) throws {
        try session.restore(checkpoint: checkpoint)
        resetTransientState()
    }

    private mutating func resetTransientState() {
        accumulator = 0
        pendingNudges.removeAll(keepingCapacity: true)
        pendingPlungerReleases.removeAll(keepingCapacity: true)
        plungerReleasePhase = nil
    }

    mutating func advance(
        elapsed: TimeInterval,
        input: SimulationInputBatch
    ) -> SimulationAdvanceResult {
        guard !isPaused else {
            return SimulationAdvanceResult(
                sessionFrame: currentSessionFrame,
                stepsExecuted: 0,
                droppedTime: 0
            )
        }
        enqueue(input.commands)

        guard elapsed.isFinite, elapsed > 0 else {
            return SimulationAdvanceResult(
                sessionFrame: currentSessionFrame,
                stepsExecuted: 0,
                droppedTime: 0
            )
        }

        let fixedStep = PinballSimulation.fixedTimeStep
        let acceptedTime = min(elapsed, fixedStep * Double(maximumCatchUpSteps))
        var droppedTime = elapsed - acceptedTime
        accumulator += acceptedTime
        var stepsExecuted = 0
        var allEvents: [GameEvent] = []
        var allEffects: [GameSessionEffect] = []

        while accumulator + Double.ulpOfOne >= fixedStep,
              stepsExecuted < maximumCatchUpSteps {
            let frame = session.step(inputForNextTick(continuous: input.continuous))
            allEvents += frame.events
            allEffects += frame.effects
            accumulator -= fixedStep
            stepsExecuted += 1
        }

        if accumulator >= fixedStep {
            let remainder = accumulator.truncatingRemainder(dividingBy: fixedStep)
            droppedTime += accumulator - remainder
            accumulator = remainder
        }

        return SimulationAdvanceResult(
            sessionFrame: GameSessionFrame(
                snapshot: session.snapshot,
                rules: session.rules,
                phase: session.phase,
                events: allEvents,
                effects: allEffects
            ),
            stepsExecuted: stepsExecuted,
            droppedTime: droppedTime
        )
    }

    private mutating func enqueue(_ commands: [SimulationCommand]) {
        for command in commands {
            switch command {
            case .releasePlunger(let strength):
                pendingPlungerReleases.append(
                    strength.isFinite ? min(1, max(0, strength)) : 0
                )
            case .nudge(let vector):
                pendingNudges.append(vector.isFinite ? vector : .zero)
            }
        }
    }

    private mutating func inputForNextTick(
        continuous: ContinuousPlayerInput
    ) -> PlayerInput {
        var input = continuous.coreInput

        if !pendingNudges.isEmpty {
            input.nudge = pendingNudges.reduce(.zero, +)
            pendingNudges.removeAll(keepingCapacity: true)
        }

        switch plungerReleasePhase {
        case .releaseOnNextTick:
            input.plungerPull = 0
            plungerReleasePhase = nil
        case nil:
            if !pendingPlungerReleases.isEmpty {
                input.plungerPull = pendingPlungerReleases.removeFirst()
                plungerReleasePhase = .releaseOnNextTick
            }
        }

        return input
    }
}
