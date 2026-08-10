import Foundation
import NovaStationCore
import Observation

@Observable @MainActor
final class AppModel {
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
    private let tipJarSupport: any TipJarSupport
    private let mediaLaunchConfiguration: MediaLaunchConfiguration
    private var didStartOptionalServices = false
    private var gameCompletionGate = GameCompletionGate()
    private(set) var mediaScenario: MediaScenario?
    var runsMediaPreviewSequence: Bool { mediaLaunchConfiguration.runsPreviewSequence }

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

    init(
        audioEngine: any PinballAudioEngine = AVAudioPinballEngine(),
        hapticsService: any PinballHapticsService = CoreHapticsService(),
        gameCenterClient: any GameCenterClient = GameKitGameCenterClient(),
        localGameStore: LocalGameStore = .applicationDefault(),
        tipJarSupport: any TipJarSupport = StoreKitTipJarSupport(),
        mediaLaunchConfiguration: MediaLaunchConfiguration = .current
    ) {
        self.audioEngine = audioEngine
        self.hapticsService = hapticsService
        self.gameCenterClient = gameCenterClient
        self.localGameStore = localGameStore
        self.tipJarSupport = tipJarSupport
        self.mediaLaunchConfiguration = mediaLaunchConfiguration
        mediaScenario = mediaLaunchConfiguration.scenario
        if let mediaScenario, let session = try? mediaScenario.makeSession() {
            rulesState = session.rules
            gamePhase = session.phase
        }
    }

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
                    gameCompletionGate.startNewGame()
                    receive(sessionFrame: scene.startNewGame())
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
    }

    func start() {
        startOptionalServices()
        lifecycleCoordinator.start()
    }

    func applyMediaScenario(_ scenario: MediaScenario) {
        guard mediaLaunchConfiguration.scenario != nil else { return }
        mediaScenario = scenario
        gameCompletionGate.startNewGame()
        let frame = scene.applyMediaScenario(scenario)
        receive(sessionFrame: frame)
    }

    func runMediaPreviewSequenceIfRequested() async {
        guard mediaLaunchConfiguration.runsPreviewSequence,
              let token = mediaLaunchConfiguration.handshakeToken,
              let handshake = try? MediaPreviewHandshake(token: token) else { return }
        do {
            try handshake.prepareAndSignalReady()
            try await handshake.waitForRecording()
            let clock = ContinuousClock()
            let timelineStart = clock.now
            try handshake.signalStarted()
            for (offset, scenario) in MediaScenario.allCases.dropFirst().enumerated() {
                try await clock.sleep(until: timelineStart.advanced(by: .seconds((offset + 1) * 4)))
                applyMediaScenario(scenario)
            }
            try await clock.sleep(until: timelineStart.advanced(by: .seconds(24)))
            try handshake.signalComplete()
        } catch {
            return
        }
    }

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

    func beginTableGuide() {
        lifecycleCoordinator.setTableGuidePresented(true)
        scene.setTableGuidePresented(true)
    }

    func endTableGuide() {
        scene.setTableGuidePresented(false)
        lifecycleCoordinator.setTableGuidePresented(false)
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

    func receive(sessionFrame: GameSessionFrame) {
        rulesState = sessionFrame.rules
        gamePhase = sessionFrame.phase

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

        guard gameCompletionGate.shouldRecord(phase: gamePhase) else { return }
        let entry = HighScoreEntry(
            identifier: UUID().uuidString,
            playerName: "NOVA",
            score: rulesState.score,
            achievedAt: Date()
        )
        try? recordCompletedGame(entry)
    }

    /// Records the authoritative local result before making a best-effort Game Center submission.
    func recordCompletedGame(_ entry: HighScoreEntry) throws {
        var scores = try localGameStore.loadHighScores()
        scores.removeAll(where: { $0.identifier == entry.identifier })
        scores.append(entry)
        try localGameStore.saveHighScores(scores)

        let retainedScores = try localGameStore.loadHighScores()
        guard retainedScores.contains(where: { $0.identifier == entry.identifier }) else { return }
        gameCenterClient.submit(score: entry.score)
    }

    func availableTips() async -> [AvailableTip] {
        await tipJarSupport.availableTips()
    }

    func purchaseTip(productIdentifier: String) async -> TipPurchaseOutcome {
        await tipJarSupport.purchase(productIdentifier: productIdentifier)
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
