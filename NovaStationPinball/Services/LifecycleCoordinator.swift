import Foundation
import NovaStationCore

enum LifecycleApplicationActivity: Equatable, Sendable {
    case active
    case inactive
    case background
}

enum LifecycleCheckpointOperation: Equatable, Sendable {
    case none
    case restored(identifier: String)
    case saved(identifier: String)
    case failed
}

@MainActor
protocol LifecycleCheckpointStore: AnyObject {
    func saveCheckpoint(_ checkpoint: ActiveCheckpoint) throws
    func restoreCheckpointOnce() throws -> ActiveCheckpoint?
}

/// Deterministic coordinator for every source that may stop simulation time.
/// Repeated events are idempotent and wall-clock time is used only as checkpoint
/// metadata, never to advance or reconstruct gameplay.
@MainActor
final class LifecycleCoordinator {
    typealias PauseHandler = @MainActor (Bool) -> Void
    typealias CaptureCheckpoint = @MainActor (String, Date) throws -> ActiveCheckpoint
    typealias RestoreCheckpoint = @MainActor (ActiveCheckpoint) throws -> Void

    private let prepareAudio: @MainActor () -> Void
    private let suspendAudio: @MainActor () -> Void
    private let checkpointStore: any LifecycleCheckpointStore
    private let setSimulationPaused: PauseHandler
    private let captureCheckpoint: CaptureCheckpoint
    private let restoreCheckpoint: RestoreCheckpoint
    private let now: @MainActor () -> Date
    private let makeCheckpointIdentifier: @MainActor () -> String

    private(set) var applicationActivity: LifecycleApplicationActivity = .inactive
    private(set) var isSimulationPaused = true
    private(set) var checkpointOperation: LifecycleCheckpointOperation = .none
    var allowsOptionalGameplayEffects: Bool { isStarted && !isSimulationPaused }
    var allowsGameplayInput: Bool { allowsOptionalGameplayEffects }
    private var isStarted = false
    private var isUserPaused = false
    private var isAudioInterrupted = false
    private var appliedPauseState: Bool?

    init(
        prepareAudio: @escaping @MainActor () -> Void,
        suspendAudio: @escaping @MainActor () -> Void,
        checkpointStore: any LifecycleCheckpointStore,
        setSimulationPaused: @escaping PauseHandler,
        captureCheckpoint: @escaping CaptureCheckpoint,
        restoreCheckpoint: @escaping RestoreCheckpoint,
        now: @escaping @MainActor () -> Date = Date.init,
        makeCheckpointIdentifier: @escaping @MainActor () -> String = { UUID().uuidString }
    ) {
        self.prepareAudio = prepareAudio
        self.suspendAudio = suspendAudio
        self.checkpointStore = checkpointStore
        self.setSimulationPaused = setSimulationPaused
        self.captureCheckpoint = captureCheckpoint
        self.restoreCheckpoint = restoreCheckpoint
        self.now = now
        self.makeCheckpointIdentifier = makeCheckpointIdentifier
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        restoreSavedCheckpoint()
        reconcilePauseState()
    }

    func setApplicationActivity(_ activity: LifecycleApplicationActivity) {
        guard applicationActivity != activity else { return }
        let entersBackground = isStarted && activity == .background
        applicationActivity = activity
        guard isStarted else { return }

        reconcilePauseState()
        if entersBackground {
            saveCurrentCheckpoint()
        }
    }

    func setUserPaused(_ paused: Bool) {
        guard isUserPaused != paused else { return }
        isUserPaused = paused
        guard isStarted else { return }
        reconcilePauseState()
    }

    func audioInterruptionBegan() {
        guard !isAudioInterrupted else { return }
        isAudioInterrupted = true
        guard isStarted else { return }
        reconcilePauseState()
    }

    func audioInterruptionEnded(shouldResume: Bool) {
        guard isAudioInterrupted else { return }
        isAudioInterrupted = false
        if !shouldResume {
            isUserPaused = true
        }
        guard isStarted else { return }
        reconcilePauseState()
    }

    private func reconcilePauseState() {
        let shouldPause = applicationActivity != .active || isUserPaused || isAudioInterrupted
        isSimulationPaused = shouldPause
        guard appliedPauseState != shouldPause else { return }
        appliedPauseState = shouldPause
        setSimulationPaused(shouldPause)
        if shouldPause {
            suspendAudio()
        } else {
            prepareAudio()
        }
    }

    private func restoreSavedCheckpoint() {
        do {
            guard let checkpoint = try checkpointStore.restoreCheckpointOnce() else { return }
            try restoreCheckpoint(checkpoint)
            checkpointOperation = .restored(identifier: checkpoint.identifier)
        } catch {
            checkpointOperation = .failed
        }
    }

    private func saveCurrentCheckpoint() {
        do {
            let identifier = makeCheckpointIdentifier()
            let checkpoint = try captureCheckpoint(identifier, now())
            try checkpointStore.saveCheckpoint(checkpoint)
            checkpointOperation = .saved(identifier: checkpoint.identifier)
        } catch {
            checkpointOperation = .failed
        }
    }
}
