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

/// Which recorded moment the player asked to go back to.
enum RewindTarget: Equatable, Sendable {
    case secondsBack(Double)
    case ballStart

    static let threeSeconds = RewindTarget.secondsBack(3)
    static let fiveSeconds = RewindTarget.secondsBack(5)

    var identifier: String {
        switch self {
        case .secondsBack(let seconds): "back-\(Int(seconds))"
        case .ballStart: "ball-start"
        }
    }
}

enum RewindError: Error, Equatable {
    /// Nothing has been recorded yet for that distance.
    case noKeyframe
}

struct SimulationDriver {
    private enum PlungerReleasePhase {
        case releaseOnNextTick
    }

    /// Deterministic playback of the inputs the player actually made, used by
    /// the Workshop "watch it again" pass.
    private struct ReviewPlayback: Equatable {
        var inputs: [PlayerInput]
        var index: Int
        var speed: Double

        var isFinished: Bool { index >= inputs.count }
    }

    private var session: GameSession
    private var accumulator = 0.0
    private let maximumCatchUpSteps: Int
    private var pendingNudges: [Vector2] = []
    private var pendingPlungerReleases: [Double] = []
    private var plungerReleasePhase: PlungerReleasePhase?
    private var isPaused = false
    private var rewindBuffer = RewindBuffer()
    private var review: ReviewPlayback?

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

    var isAssisted: Bool { session.isAssisted }
    var isReviewing: Bool { review != nil }
    var recordedInputCount: Int { session.recordedInputCount }
    var rewindKeyframeCount: Int { rewindBuffer.keyframeCount }

    /// The keyframe a rewind target resolves to right now, or nil when the
    /// run has not recorded that far back yet.
    func rewindMark(for target: RewindTarget) -> RewindMark? {
        switch target {
        case .secondsBack(let seconds):
            rewindBuffer.mark(secondsBack: seconds, at: session.recordedInputCount)
        case .ballStart:
            rewindBuffer.ballStartMark(at: session.recordedInputCount)
        }
    }

    func canRewind(to target: RewindTarget) -> Bool {
        rewindMark(for: target) != nil
    }

    /// Restores the keyframe and hands control straight back to the player.
    @discardableResult
    mutating func rewind(to target: RewindTarget) throws -> GameSessionFrame {
        guard let mark = rewindMark(for: target) else { throw RewindError.noKeyframe }
        session = try session.rewound(to: mark)
        rewindBuffer.discardMarks(after: mark.inputIndex)
        review = nil
        resetTransientState()
        return currentSessionFrame
    }

    /// Restores the keyframe and replays the player's own inputs from it, at
    /// `speed` (1.0 or 0.5). Playback ends by itself at the live moment.
    @discardableResult
    mutating func beginReview(from target: RewindTarget, speed: Double) throws -> GameSessionFrame {
        guard let mark = rewindMark(for: target) else { throw RewindError.noKeyframe }
        let tail = session.recordedInputs(from: mark.inputIndex)
        session = try session.rewound(to: mark)
        rewindBuffer.discardMarks(after: mark.inputIndex)
        resetTransientState()
        review = ReviewPlayback(
            inputs: tail,
            index: 0,
            speed: speed.isFinite ? min(2, max(0.25, speed)) : 1
        )
        return currentSessionFrame
    }

    /// Takes over from the review at the exact moment currently on screen.
    mutating func endReview() {
        guard review != nil else { return }
        review = nil
        resetTransientState()
    }

    @discardableResult
    mutating func startNewGame() throws -> GameSessionFrame {
        let frame = try session.startNewGame()
        review = nil
        rewindBuffer.removeAll()
        resetTransientState()
        recordRewindMark(for: frame)
        return frame
    }

    mutating func replaceSession(_ replacement: GameSession) {
        session = replacement
        review = nil
        rewindBuffer.removeAll()
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
        review = nil
        rewindBuffer.removeAll()
        resetTransientState()
    }

    /// Flags a restored run as assisted again after a relaunch, from the
    /// device-local marker. Never clears the flag.
    mutating func markAssisted() {
        session.markAssisted()
    }

    private mutating func resetTransientState() {
        accumulator = 0
        pendingNudges.removeAll(keepingCapacity: true)
        pendingPlungerReleases.removeAll(keepingCapacity: true)
        plungerReleasePhase = nil
    }

    private mutating func recordRewindMark(for frame: GameSessionFrame) {
        rewindBuffer.record(
            state: session.sessionState,
            inputIndex: session.recordedInputCount,
            isBallStart: frame.effects.contains { effect in
                if case .ballSpawned = effect { return true }
                return false
            }
        )
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
        if review != nil {
            // Live gestures are ignored while the recorded ball plays back;
            // they must not fire the moment the player takes over.
            pendingNudges.removeAll(keepingCapacity: true)
            pendingPlungerReleases.removeAll(keepingCapacity: true)
            plungerReleasePhase = nil
        }

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
        // A review plays the recorded ticks at its own rate; slow motion asks
        // the simulation for fewer ticks per real second, never for different
        // physics.
        accumulator += acceptedTime * (review?.speed ?? 1)
        var stepsExecuted = 0
        var allEvents: [GameEvent] = []
        var allEffects: [GameSessionEffect] = []

        while accumulator + Double.ulpOfOne >= fixedStep,
              stepsExecuted < maximumCatchUpSteps {
            let tickInput: PlayerInput
            if var playback = review {
                guard !playback.isFinished else {
                    review = nil
                    break
                }
                tickInput = playback.inputs[playback.index]
                playback.index += 1
                review = playback
            } else {
                tickInput = inputForNextTick(continuous: input.continuous)
            }
            let frame = session.step(tickInput)
            recordRewindMark(for: frame)
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
