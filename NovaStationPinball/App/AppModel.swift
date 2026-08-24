import Foundation
import NovaStationCore
import Observation

@Observable @MainActor
final class AppModel {
#if DEBUG
    private enum MediaPreviewSequenceError: Error {
        case missingPreparedSession
    }
#endif

    private enum GameStatus {
        case systemReady
        case plungerCharging
        case ballLaunched
        case nudge
        case gestureCancelled
        case paused
        case audioInterrupted
        case restored
        case mission
        case promotion
        case multiball
        case tilt
        case gameOver
        case rewound
        case reviewing
        case drill

        var localizedText: String {
            switch self {
            case .systemReady: String(localized: "status.system_ready")
            case .plungerCharging: String(localized: "status.plunger_charging")
            case .ballLaunched: String(localized: "status.ball_launched")
            case .nudge: String(localized: "status.nudge")
            case .gestureCancelled: String(localized: "status.gesture_cancelled")
            case .paused: String(localized: "status.paused")
            case .audioInterrupted: String(localized: "status.audio_interrupted")
            case .restored: String(localized: "status.restored")
            case .mission: String(localized: "status.mission")
            case .promotion: String(localized: "status.promotion")
            case .multiball: String(localized: "status.multiball")
            case .tilt: String(localized: "status.tilt")
            case .gameOver: String(localized: "status.game_over")
            case .rewound: String(localized: "status.rewound")
            case .reviewing: String(localized: "status.reviewing")
            case .drill: String(localized: "status.drill")
            }
        }
    }

    private(set) var rulesState = GameRulesState()
    private(set) var gamePhase = GameSessionPhase.launch
    private var gameStatus = GameStatus.systemReady
    var score: Int { rulesState.score }
    var ballsRemaining: Int { rulesState.ballsRemaining }
    var ballsInPlay: Int { rulesState.ballsInPlay }
    var missionState: MissionState { rulesState.missionState }
    var clearance: ClearanceLevel? { rulesState.clearance }
    var scoreMultiplier: Int { rulesState.scoreMultiplier }
    var bonusMultiplier: Int { rulesState.bonusMultiplier }
    var statusText: String { gameStatus.localizedText }
    private(set) var continuousInput = ContinuousPlayerInput.idle
    private var pendingCommands: [SimulationCommand] = []
    private let audioEngine: any PinballAudioEngine
    private let hapticsService: any PinballHapticsService
    private let gameCenterClient: any GameCenterClient
    private let localGameStore: LocalGameStore
#if DEBUG
    private let mediaLaunchConfiguration: MediaLaunchConfiguration
#endif
    private var didStartOptionalServices = false
    private var gameCompletionGate = GameCompletionGate()
#if DEBUG
    private(set) var mediaScenario: MediaScenario?
    private(set) var mediaPreviewTimelineStarted = false
    var runsMediaPreviewSequence: Bool { mediaLaunchConfiguration.runsPreviewSequence }
#endif

    // MARK: - Workshop

    let store: StoreService
    private(set) var rewindsUsedThisGame = 0
    private(set) var drillProgress = DrillProgress()
    private(set) var activeDrill: ShotDrill?
    private(set) var activeDrillOutcome = ShotDrillEvaluator.Outcome.running
    /// Seconds left in the attempt on screen. Written once per whole second so
    /// the countdown drives the HUD without re-rendering it 240 times a second.
    private(set) var activeDrillRemainingSeconds = 0
    private var drillEvaluator: ShotDrillEvaluator?
    /// True as soon as this run used a rewind, a review or a drill.
    private(set) var isAssistedRun = false
#if DEBUG
    var opensPaywallOnLaunch: Bool { mediaLaunchConfiguration.opensPaywall }
#endif

    var hasWorkshop: Bool { store.hasWorkshop }
    /// Device already played Nova Station before the Workshop existed. It only
    /// ever adds free rewinds, and is disclosed in the Workshop sheet as the
    /// device-local flag it is.
    var isFounder: Bool { store.isFounder }
    var isReviewingBall: Bool { scene.isReviewing }
    var freeRewindsPerGame: Int { store.freeRewindsPerGame }
    var remainingFreeRewinds: Int { max(0, freeRewindsPerGame - rewindsUsedThisGame) }
    var canUseAnotherRewind: Bool { hasWorkshop || remainingFreeRewinds > 0 }

    func canRewind(to target: RewindTarget) -> Bool {
        scene.canRewind(to: target)
    }

    func drillEntry(for drill: ShotDrill) -> DrillProgressEntry {
        drillProgress.entry(for: drill.id)
    }

    /// True while the attempt currently on the table is still undecided.
    var isRunningDrillAttempt: Bool {
        activeDrill != nil && activeDrillOutcome == .running
    }

    @ObservationIgnored lazy var scene = PinballScene(model: self)
    @ObservationIgnored lazy var lifecycleCoordinator = LifecycleCoordinator(
        prepareAudio: { [weak self] in self?.audioEngine.prepare() },
        suspendAudio: { [weak self] in self?.audioEngine.suspend() },
        checkpointStore: localGameStore,
        setSimulationPaused: { [weak self] paused in self?.setSimulationPaused(paused) },
        captureCheckpoint: { [weak self] identifier, date in
            guard let self else { throw LifecycleSessionError.unavailable }
            return self.captureCheckpoint(identifier: identifier, savedAt: date)
        },
        restoreCheckpoint: { [weak self] checkpoint in
            guard let self else { throw LifecycleSessionError.unavailable }
            try self.restore(checkpoint: checkpoint)
        }
    )

#if DEBUG
    init(
        audioEngine: any PinballAudioEngine = AVAudioPinballEngine(),
        hapticsService: any PinballHapticsService = CoreHapticsService(),
        gameCenterClient: any GameCenterClient = GameKitGameCenterClient(),
        localGameStore: LocalGameStore = .applicationDefault(),
        store: StoreService = StoreService(),
        mediaLaunchConfiguration: MediaLaunchConfiguration = .current
    ) {
        self.audioEngine = audioEngine
        self.hapticsService = hapticsService
        self.gameCenterClient = gameCenterClient
        self.localGameStore = localGameStore
        self.store = store
        self.mediaLaunchConfiguration = mediaLaunchConfiguration
        mediaScenario = mediaLaunchConfiguration.scenario
        if let mediaScenario, let session = try? mediaScenario.makeSession() {
            rulesState = session.rules
            gamePhase = session.phase
        }
        drillProgress = (try? localGameStore.loadDrillProgress()) ?? DrillProgress()
        isAssistedRun = localGameStore.isAssistedSessionMarked
    }
#else
    init(
        audioEngine: any PinballAudioEngine = AVAudioPinballEngine(),
        hapticsService: any PinballHapticsService = CoreHapticsService(),
        gameCenterClient: any GameCenterClient = GameKitGameCenterClient(),
        localGameStore: LocalGameStore = .applicationDefault(),
        store: StoreService = StoreService()
    ) {
        self.audioEngine = audioEngine
        self.hapticsService = hapticsService
        self.gameCenterClient = gameCenterClient
        self.localGameStore = localGameStore
        self.store = store
        drillProgress = (try? localGameStore.loadDrillProgress()) ?? DrillProgress()
        isAssistedRun = localGameStore.isAssistedSessionMarked
    }
#endif

    func apply(_ events: [PinballControlEvent]) {
        guard lifecycleCoordinator.allowsGameplayInput else { return }
        for event in events {
            switch event {
            case .flipper(let side, let pressed):
                guard gamePhase == .playing else { continue }
                if side == .left { continuousInput.leftFlipperIsPressed = pressed }
                else { continuousInput.rightFlipperIsPressed = pressed }
            case .plungerPull(let pull):
                continuousInput.plungerPull = pull
                gameStatus = pull > 0 ? .plungerCharging : .systemReady
            case .plungerReleased(let strength):
                if gamePhase != .playing {
                    beginFreshGame()
                }
                continuousInput.plungerPull = 0
                pendingCommands.append(.releasePlunger(strength: strength))
                emitOptionalEffects(audio: .ballLaunch, haptic: .ballLaunch)
                gameStatus = .ballLaunched
            case .nudge(let x):
                guard gamePhase == .playing else { continue }
                pendingCommands.append(.nudge(Vector2(x: x, y: 0)))
                emitOptionalEffects(audio: .nudge, haptic: .nudge)
                gameStatus = .nudge
            case .cancelGestures:
                continuousInput.plungerPull = 0
                gameStatus = .gestureCancelled
            }
        }
    }

    func takeSimulationInput() -> SimulationInputBatch {
        let input = SimulationInputBatch(
            continuous: continuousInput,
            commands: pendingCommands
        )
        pendingCommands.removeAll(keepingCapacity: true)
        return input
    }

    func startOptionalServices() {
        guard !didStartOptionalServices else { return }
        didStartOptionalServices = true
        gameCenterClient.authenticate()
        store.start()
        if isAssistedRun { scene.markAssisted() }
    }

    func start() {
        startOptionalServices()
        lifecycleCoordinator.start()
    }

#if DEBUG
    func applyMediaScenario(_ scenario: MediaScenario, preparedSession: GameSession? = nil) {
        guard mediaLaunchConfiguration.scenario != nil else { return }
        mediaScenario = scenario
        gameCompletionGate.startNewGame()
        let frame = scene.applyMediaScenario(scenario, preparedSession: preparedSession)
        receive(sessionFrame: frame)
    }

    func runMediaPreviewSequenceIfRequested() async {
        guard mediaLaunchConfiguration.runsPreviewSequence,
              let token = mediaLaunchConfiguration.handshakeToken,
              let handshake = try? MediaPreviewHandshake(token: token) else { return }
        do {
            let preparedSessions = try MediaScenario.preparePreviewSessions()
            try handshake.prepareAndSignalReady()
            try await handshake.waitForRecording()
            let clock = ContinuousClock()
            let timelineStart = clock.now
            try handshake.signalStarted()
            mediaPreviewTimelineStarted = true
            for (offset, scenario) in MediaScenario.allCases.dropFirst().enumerated() {
                try await clock.sleep(until: timelineStart.advanced(by: .seconds((offset + 1) * 4)))
                guard let preparedSession = preparedSessions[scenario] else {
                    throw MediaPreviewSequenceError.missingPreparedSession
                }
                applyMediaScenario(scenario, preparedSession: preparedSession)
            }
            try await clock.sleep(until: timelineStart.advanced(by: .seconds(24)))
            try handshake.signalComplete()
        } catch {
            return
        }
    }
#endif

    func setApplicationActivity(_ activity: LifecycleApplicationActivity) {
        lifecycleCoordinator.setApplicationActivity(activity)
    }

    func audioInterruptionBegan() {
        gameStatus = .audioInterrupted
        lifecycleCoordinator.audioInterruptionBegan()
    }

    func audioInterruptionEnded(shouldResume: Bool) {
        lifecycleCoordinator.audioInterruptionEnded(shouldResume: shouldResume)
    }

    var isSimulationPaused: Bool { lifecycleCoordinator.isSimulationPaused }

    var accessibilityPauseActionTitle: String {
        if isSimulationPaused {
            String(localized: "accessibility.action.resume")
        } else {
            String(localized: "accessibility.action.pause")
        }
    }

    var accessibilityConsoleValue: String {
        String.localizedStringWithFormat(
            String(localized: "accessibility.console.value"),
            Int64(score),
            Int64(ballsRemaining),
            statusText
        )
    }

    func togglePauseFromAccessibility() {
        lifecycleCoordinator.setUserPaused(!lifecycleCoordinator.isSimulationPaused)
    }

    func beginModalOverlay() {
        lifecycleCoordinator.setModalOverlayPresented(true)
        scene.setModalOverlayPresented(true)
    }

    func endModalOverlay() {
        scene.setModalOverlayPresented(false)
        lifecycleCoordinator.setModalOverlayPresented(false)
    }

    func toggleFlipperFromAccessibility(_ side: FlipperSide) {
        guard gamePhase == .playing else { return }
        let isPressed = side == .left
            ? !continuousInput.leftFlipperIsPressed
            : !continuousInput.rightFlipperIsPressed
        apply([.flipper(side: side, isPressed: isPressed)])
    }

    func launchBallFromAccessibility() {
        apply([.plungerReleased(1)])
    }

    func nudgeFromAccessibility() {
        apply([.nudge(x: 0.35)])
    }

    func receive(sessionFrame: GameSessionFrame, steps: Int = 1) {
        rulesState = sessionFrame.rules
        gamePhase = sessionFrame.phase
        advanceDrill(with: sessionFrame, steps: steps)

        for effect in sessionFrame.effects {
            switch effect {
            case .missionStarted:
                gameStatus = .mission
            case .missionCompleted, .clearanceAwarded:
                gameStatus = .promotion
            case .multiballStarted:
                gameStatus = .multiball
            case .tilt:
                gameStatus = .tilt
            case .gameOver:
                gameStatus = .gameOver
            case .scoreAwarded, .bonusChanged, .scoreMultiplierChanged,
                 .bonusMultiplierChanged, .stationPowerChanged, .extraBallAwarded,
                 .ballDrained, .ballSaved, .ballSpawned, .missionSelected,
                 .missionFailed:
                break
            }
        }

        guard activeDrill == nil, gameCompletionGate.shouldRecord(phase: gamePhase) else { return }
        let entry = HighScoreEntry(
            identifier: UUID().uuidString,
            playerName: "NOVA",
            score: rulesState.score,
            achievedAt: Date()
        )
        try? recordCompletedGame(entry)
    }

    /// Records the authoritative local result before making a best-effort Game
    /// Center submission. A run that used the Workshop is ranked on the
    /// separate training board and is never submitted anywhere: rewinding is
    /// assistance, and the ladder has to stay honest.
    func recordCompletedGame(_ entry: HighScoreEntry) throws {
        guard !isAssistedRun, !scene.isAssisted else {
            var trainingScores = try localGameStore.loadTrainingScores()
            trainingScores.removeAll(where: { $0.identifier == entry.identifier })
            trainingScores.append(entry)
            try localGameStore.saveTrainingScores(trainingScores)
            return
        }
        var scores = try localGameStore.loadHighScores()
        scores.removeAll(where: { $0.identifier == entry.identifier })
        scores.append(entry)
        try localGameStore.saveHighScores(scores)

        let retainedScores = try localGameStore.loadHighScores()
        guard retainedScores.contains(where: { $0.identifier == entry.identifier }) else { return }
        gameCenterClient.submit(score: entry.score)
    }

    // MARK: - Workshop actions

    enum WorkshopRequestOutcome: Equatable {
        case done
        /// The free allowance for this game is spent; show the paywall.
        case needsWorkshop
        /// Nothing has been recorded that far back yet.
        case noKeyframe
    }

    /// Rewinds the ball to a recorded keyframe and gives control straight
    /// back. Costs one of the free rewinds unless the Workshop is owned.
    @discardableResult
    func rewind(to target: RewindTarget) -> WorkshopRequestOutcome {
        guard canUseAnotherRewind else { return .needsWorkshop }
        guard scene.canRewind(to: target) else { return .noKeyframe }
        do {
            let frame = try scene.rewind(to: target)
            if !hasWorkshop { rewindsUsedThisGame += 1 }
            markRunAssisted()
            receive(sessionFrame: frame)
            gameStatus = .rewound
            return .done
        } catch {
            return .noKeyframe
        }
    }

    /// Replays the player's own inputs from a keyframe. Reviewing the current
    /// ball is free for everyone; reviewing further back is part of the
    /// Workshop.
    @discardableResult
    func reviewBall(from target: RewindTarget, speed: Double) -> WorkshopRequestOutcome {
        if target != .ballStart && !hasWorkshop { return .needsWorkshop }
        guard scene.canRewind(to: target) else { return .noKeyframe }
        do {
            let frame = try scene.beginReview(from: target, speed: speed)
            markRunAssisted()
            receive(sessionFrame: frame)
            gameStatus = .reviewing
            return .done
        } catch {
            return .noKeyframe
        }
    }

    /// Takes the table back at the exact instant currently on screen.
    func resumeFromReview() {
        scene.endReview()
        gameStatus = .systemReady
    }

    /// Starts a drill. Every attempt serves the identical state.
    @discardableResult
    func startDrill(_ drill: ShotDrill) -> WorkshopRequestOutcome {
        guard hasWorkshop else { return .needsWorkshop }
        do {
            let frame = try scene.startDrill(drill)
            let evaluator = ShotDrillEvaluator(drill: drill)
            activeDrill = drill
            drillEvaluator = evaluator
            activeDrillOutcome = .running
            activeDrillRemainingSeconds = Self.seconds(fromTicks: evaluator.remainingTicks)
            gameCompletionGate.startNewGame()
            markRunAssisted()
            receive(sessionFrame: frame)
            gameStatus = .drill
            return .done
        } catch {
            return .noKeyframe
        }
    }

    /// Serves the very same drill again, from the very same position. This is
    /// the control the player reaches for after an attempt is decided.
    @discardableResult
    func restartActiveDrill() -> WorkshopRequestOutcome {
        guard let drill = activeDrill else { return .noKeyframe }
        return startDrill(drill)
    }

    /// Leaves the Workshop and returns the table to the launch screen.
    func endDrill() {
        guard activeDrill != nil else { return }
        activeDrill = nil
        drillEvaluator = nil
        activeDrillOutcome = .running
        activeDrillRemainingSeconds = 0
        beginFreshGame()
    }

    private func beginFreshGame() {
        gameCompletionGate.startNewGame()
        rewindsUsedThisGame = 0
        isAssistedRun = false
        localGameStore.setAssistedSessionMarked(false)
        activeDrill = nil
        drillEvaluator = nil
        activeDrillOutcome = .running
        activeDrillRemainingSeconds = 0
        receive(sessionFrame: scene.startNewGame())
        gameStatus = .systemReady
    }

    private func markRunAssisted() {
        guard !isAssistedRun else { return }
        isAssistedRun = true
        localGameStore.setAssistedSessionMarked(true)
    }

    private func advanceDrill(with frame: GameSessionFrame, steps: Int) {
        guard var evaluator = drillEvaluator, let drill = activeDrill else { return }
        let outcome = evaluator.consume(frame, steps: steps)
        drillEvaluator = evaluator
        let remaining = Self.seconds(fromTicks: evaluator.remainingTicks)
        if remaining != activeDrillRemainingSeconds { activeDrillRemainingSeconds = remaining }
        guard outcome != .running, activeDrillOutcome == .running else { return }
        activeDrillOutcome = outcome
        drillProgress.record(drillID: drill.id, succeeded: outcome == .succeeded)
        try? localGameStore.saveDrillProgress(drillProgress)
    }

    /// Rounds up, so a budget that still has a fraction of a second left never
    /// reads as zero while the attempt is still live.
    private static func seconds(fromTicks ticks: Int) -> Int {
        guard ticks > 0 else { return 0 }
        let ticksPerSecond = Int((1.0 / PinballSimulation.fixedTimeStep).rounded())
        return (ticks + ticksPerSecond - 1) / max(1, ticksPerSecond)
    }

    private func emitOptionalEffects(audio audioCue: PinballAudioCue, haptic hapticCue: PinballHapticCue) {
        guard lifecycleCoordinator.allowsOptionalGameplayEffects else { return }
        audioEngine.play(audioCue)
        hapticsService.play(hapticCue)
    }

    private func setSimulationPaused(_ paused: Bool) {
        continuousInput = .idle
        pendingCommands.removeAll(keepingCapacity: true)
        scene.setLifecyclePaused(paused)
        if paused {
            if gameStatus != .audioInterrupted && gameStatus != .restored {
                gameStatus = .paused
            }
        } else if gameStatus == .paused || gameStatus == .audioInterrupted {
            gameStatus = .systemReady
        }
    }

    private func captureCheckpoint(identifier: String, savedAt: Date) -> ActiveCheckpoint {
        return ActiveCheckpoint(
            identifier: identifier,
            savedAt: savedAt,
            sessionCheckpoint: scene.currentCheckpoint
        )
    }

    private func restore(checkpoint: ActiveCheckpoint) throws {
        try scene.restore(checkpoint: checkpoint.sessionCheckpoint)
        receive(sessionFrame: scene.currentSessionFrame)
        gameStatus = .restored
    }
}

private enum LifecycleSessionError: Error {
    case unavailable
}
