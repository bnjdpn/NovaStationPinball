import Foundation
import NovaStationCore
import XCTest
#if SWIFT_PACKAGE
@testable import NovaStationLifecycle
#else
@testable import NovaStationPinball
#endif

@MainActor
final class LifecycleCoordinatorTests: XCTestCase {
    func testStartRestoresCheckpointExactlyOnceAndAppliesInitialPause() throws {
        let checkpoint = makeCheckpoint(identifier: "restore-me", elapsedTime: 12)
        let store = RecordingCheckpointStore(restoredCheckpoint: checkpoint)
        let audio = RecordingLifecycleAudioEngine()
        var restored: [ActiveCheckpoint] = []
        var pauses: [Bool] = []
        let coordinator = makeCoordinator(
            store: store,
            audio: audio,
            setPaused: { pauses.append($0) },
            restore: { restored.append($0) }
        )

        coordinator.start()
        coordinator.start()

        XCTAssertEqual(store.restoreCount, 1)
        XCTAssertEqual(restored, [checkpoint])
        XCTAssertEqual(pauses, [true])
        XCTAssertEqual(audio.operations, [.suspend])
        XCTAssertEqual(coordinator.checkpointOperation, .restored(identifier: "restore-me"))
    }

    func testActiveInactiveTransitionsApplyPauseAndAudioOnlyOncePerState() {
        let store = RecordingCheckpointStore()
        let audio = RecordingLifecycleAudioEngine()
        var pauses: [Bool] = []
        let coordinator = makeCoordinator(store: store, audio: audio, setPaused: { pauses.append($0) })

        coordinator.start()
        coordinator.setApplicationActivity(.active)
        coordinator.setApplicationActivity(.active)
        coordinator.setApplicationActivity(.inactive)
        coordinator.setApplicationActivity(.inactive)
        coordinator.setApplicationActivity(.active)

        XCTAssertEqual(pauses, [true, false, true, false])
        XCTAssertEqual(audio.operations, [.suspend, .prepare, .suspend, .prepare])
        XCTAssertFalse(coordinator.isSimulationPaused)
    }

    func testUserPauseSurvivesApplicationActivityChurnUntilExplicitResume() {
        let coordinator = makeCoordinator()
        coordinator.start()
        coordinator.setApplicationActivity(.active)

        coordinator.setUserPaused(true)
        coordinator.setApplicationActivity(.inactive)
        coordinator.setApplicationActivity(.active)

        XCTAssertTrue(coordinator.isSimulationPaused)

        coordinator.setUserPaused(false)

        XCTAssertFalse(coordinator.isSimulationPaused)
    }

    func testEnteringBackgroundPausesBeforeSavingExactlyOneDeterministicCheckpoint() throws {
        var operations: [String] = []
        let store = RecordingCheckpointStore(onSave: { _ in operations.append("save") })
        let checkpoint = makeCheckpoint(identifier: "background-1", elapsedTime: 24)
        let coordinator = makeCoordinator(
            store: store,
            setPaused: { operations.append("pause:\($0)") },
            capture: { identifier, date in
                operations.append("capture:\(identifier):\(date.timeIntervalSince1970)")
                return checkpoint
            },
            identifier: { "background-1" },
            now: { Date(timeIntervalSince1970: 42) }
        )
        coordinator.start()
        coordinator.setApplicationActivity(.active)
        operations.removeAll()

        coordinator.setApplicationActivity(.background)
        coordinator.setApplicationActivity(.background)

        XCTAssertEqual(operations, ["pause:true", "capture:background-1:42.0", "save"])
        XCTAssertEqual(store.savedCheckpoints, [checkpoint])
        XCTAssertEqual(coordinator.checkpointOperation, .saved(identifier: "background-1"))
    }

    func testEachNewBackgroundEntryCreatesOneNewCheckpoint() {
        var nextIdentifier = 0
        let store = RecordingCheckpointStore()
        let coordinator = makeCoordinator(
            store: store,
            capture: { identifier, _ in self.makeCheckpoint(identifier: identifier) },
            identifier: {
                nextIdentifier += 1
                return "checkpoint-\(nextIdentifier)"
            }
        )
        coordinator.start()
        coordinator.setApplicationActivity(.active)

        coordinator.setApplicationActivity(.background)
        coordinator.setApplicationActivity(.active)
        coordinator.setApplicationActivity(.background)

        XCTAssertEqual(store.savedCheckpoints.map(\.identifier), ["checkpoint-1", "checkpoint-2"])
    }

    func testAudioInterruptionPausesAndResumesOnlyWhenEveryBlockerClears() {
        let coordinator = makeCoordinator()
        coordinator.start()
        coordinator.setApplicationActivity(.active)

        coordinator.audioInterruptionBegan()
        coordinator.audioInterruptionBegan()
        XCTAssertTrue(coordinator.isSimulationPaused)

        coordinator.setApplicationActivity(.inactive)
        coordinator.audioInterruptionEnded(shouldResume: true)
        XCTAssertTrue(coordinator.isSimulationPaused)

        coordinator.setApplicationActivity(.active)
        XCTAssertFalse(coordinator.isSimulationPaused)
    }

    func testAudioInterruptionWithoutResumeRequiresExplicitUserResume() {
        let coordinator = makeCoordinator()
        coordinator.start()
        coordinator.setApplicationActivity(.active)
        coordinator.audioInterruptionBegan()

        coordinator.audioInterruptionEnded(shouldResume: false)

        XCTAssertTrue(coordinator.isSimulationPaused)
        coordinator.setUserPaused(false)
        XCTAssertFalse(coordinator.isSimulationPaused)
    }

    func testOptionalGameplayEffectsPermissionTracksEveryLifecycleBlocker() {
        let coordinator = makeCoordinator()

        XCTAssertFalse(coordinator.allowsOptionalGameplayEffects)
        XCTAssertFalse(coordinator.allowsGameplayInput)
        coordinator.start()
        XCTAssertFalse(coordinator.allowsOptionalGameplayEffects)
        XCTAssertFalse(coordinator.allowsGameplayInput)

        coordinator.setApplicationActivity(.active)
        XCTAssertTrue(coordinator.allowsOptionalGameplayEffects)
        XCTAssertTrue(coordinator.allowsGameplayInput)

        coordinator.setUserPaused(true)
        XCTAssertFalse(coordinator.allowsOptionalGameplayEffects)
        XCTAssertFalse(coordinator.allowsGameplayInput)
        coordinator.setUserPaused(false)
        XCTAssertTrue(coordinator.allowsOptionalGameplayEffects)
        XCTAssertTrue(coordinator.allowsGameplayInput)

        coordinator.setApplicationActivity(.inactive)
        XCTAssertFalse(coordinator.allowsOptionalGameplayEffects)
        coordinator.setApplicationActivity(.background)
        XCTAssertFalse(coordinator.allowsOptionalGameplayEffects)
        coordinator.setApplicationActivity(.active)
        XCTAssertTrue(coordinator.allowsOptionalGameplayEffects)

        coordinator.audioInterruptionBegan()
        XCTAssertFalse(coordinator.allowsOptionalGameplayEffects)
        XCTAssertFalse(coordinator.allowsGameplayInput)
        coordinator.audioInterruptionEnded(shouldResume: true)
        XCTAssertTrue(coordinator.allowsOptionalGameplayEffects)
        XCTAssertTrue(coordinator.allowsGameplayInput)
    }

    func testCheckpointFailureIsContainedAndReportedWithoutChangingPauseState() {
        let store = RecordingCheckpointStore(saveError: TestError.expected)
        let coordinator = makeCoordinator(store: store)
        coordinator.start()
        coordinator.setApplicationActivity(.active)

        coordinator.setApplicationActivity(.background)

        XCTAssertTrue(coordinator.isSimulationPaused)
        XCTAssertEqual(coordinator.checkpointOperation, .failed)
    }

    func testSimulationDriverRestoreReturnsToExactSnapshotAndClearsDisplayAccumulator() throws {
        var driver = SimulationDriver()
        _ = driver.advance(elapsed: 1.0 / 240.0, input: .idle)
        let checkpointSnapshot = driver.snapshot
        _ = driver.advance(elapsed: 1.0 / 480.0, input: .idle)

        try driver.restore(snapshot: checkpointSnapshot)
        let halfStep = driver.advance(elapsed: 1.0 / 480.0, input: .idle)

        XCTAssertEqual(halfStep.stepsExecuted, 0)
        XCTAssertEqual(halfStep.frame.snapshot, checkpointSnapshot)
    }

    func testPausedSimulationDriverNeverAdvancesAndResumesWithoutCatchUp() {
        var driver = SimulationDriver()
        let initialSnapshot = driver.snapshot

        driver.setPaused(true)
        let paused = driver.advance(elapsed: 30, input: .idle)
        driver.setPaused(false)
        let resumed = driver.advance(elapsed: 1.0 / 240.0, input: .idle)

        XCTAssertEqual(paused.stepsExecuted, 0)
        XCTAssertEqual(paused.frame.snapshot, initialSnapshot)
        XCTAssertEqual(resumed.stepsExecuted, 1)
        XCTAssertEqual(resumed.frame.elapsedTime, 1.0 / 240.0, accuracy: 1e-12)
    }

    private func makeCoordinator(
        store: RecordingCheckpointStore = RecordingCheckpointStore(),
        audio: RecordingLifecycleAudioEngine = RecordingLifecycleAudioEngine(),
        setPaused: @escaping @MainActor (Bool) -> Void = { _ in },
        capture: @escaping @MainActor (String, Date) throws -> ActiveCheckpoint = { identifier, date in
            LifecycleCoordinatorTests.makeCheckpoint(identifier: identifier, savedAt: date)
        },
        restore: @escaping @MainActor (ActiveCheckpoint) throws -> Void = { _ in },
        identifier: @escaping @MainActor () -> String = { "checkpoint" },
        now: @escaping @MainActor () -> Date = { Date(timeIntervalSince1970: 10) }
    ) -> LifecycleCoordinator {
        LifecycleCoordinator(
            prepareAudio: { audio.prepare() },
            suspendAudio: { audio.suspend() },
            checkpointStore: store,
            setSimulationPaused: setPaused,
            captureCheckpoint: capture,
            restoreCheckpoint: restore,
            now: now,
            makeCheckpointIdentifier: identifier
        )
    }

    private func makeCheckpoint(identifier: String, elapsedTime: TimeInterval = 0) -> ActiveCheckpoint {
        Self.makeCheckpoint(identifier: identifier, elapsedTime: elapsedTime)
    }

    private static func makeCheckpoint(
        identifier: String,
        savedAt: Date = Date(timeIntervalSince1970: 1),
        elapsedTime: TimeInterval = 0
    ) -> ActiveCheckpoint {
        let snapshot = SimulationSnapshot(tableVersion: 1, elapsedTime: elapsedTime, balls: [])
        return ActiveCheckpoint(
            identifier: identifier,
            savedAt: savedAt,
            snapshot: snapshot,
            rules: GameRulesState(),
            replay: Replay(tableVersion: 1, initialSnapshot: snapshot, inputs: [])
        )
    }
}

@MainActor
private final class RecordingCheckpointStore: LifecycleCheckpointStore {
    private(set) var restoreCount = 0
    private(set) var savedCheckpoints: [ActiveCheckpoint] = []
    var restoredCheckpoint: ActiveCheckpoint?
    let saveError: Error?
    let onSave: (ActiveCheckpoint) -> Void

    init(
        restoredCheckpoint: ActiveCheckpoint? = nil,
        saveError: Error? = nil,
        onSave: @escaping (ActiveCheckpoint) -> Void = { _ in }
    ) {
        self.restoredCheckpoint = restoredCheckpoint
        self.saveError = saveError
        self.onSave = onSave
    }

    func saveCheckpoint(_ checkpoint: ActiveCheckpoint) throws {
        if let saveError { throw saveError }
        savedCheckpoints.append(checkpoint)
        onSave(checkpoint)
    }

    func restoreCheckpointOnce() throws -> ActiveCheckpoint? {
        restoreCount += 1
        defer { restoredCheckpoint = nil }
        return restoredCheckpoint
    }
}

@MainActor
private final class RecordingLifecycleAudioEngine {
    enum Operation: Equatable { case prepare, suspend }
    private(set) var operations: [Operation] = []
    func prepare() { operations.append(.prepare) }
    func suspend() { operations.append(.suspend) }
}

private enum TestError: Error { case expected }
