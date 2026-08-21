import Foundation
import NovaStationCore
import XCTest
@testable import NovaStationPinball

@MainActor
final class OptionalEffectsLifecycleTests: XCTestCase {
    func testManualPauseBlocksDirectAndAccessibilityEffectsUntilResume() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        harness.activate()
        let readyStatus = harness.model.statusText
        XCTAssertEqual(readyStatus, String(localized: "status.system_ready"))

        harness.model.togglePauseFromAccessibility()
        let pausedStatus = harness.model.statusText
        XCTAssertEqual(pausedStatus, String(localized: "status.paused"))
        harness.resetEffects()
        harness.model.apply([.plungerReleased(0.7), .nudge(x: -0.2)])
        harness.model.launchBallFromAccessibility()
        harness.model.nudgeFromAccessibility()

        XCTAssertEqual(harness.audio.operations, [])
        XCTAssertEqual(harness.haptics.operations, [])
        XCTAssertEqual(harness.model.takeSimulationInput(), .idle)
        XCTAssertEqual(harness.model.statusText, pausedStatus)

        harness.model.togglePauseFromAccessibility()
        XCTAssertEqual(harness.model.statusText, readyStatus)
        XCTAssertEqual(harness.model.takeSimulationInput(), .idle)
        harness.resetEffects()
        harness.model.launchBallFromAccessibility()
        let launchedStatus = harness.model.statusText
        harness.model.nudgeFromAccessibility()

        XCTAssertEqual(harness.audio.operations, [.play(.ballLaunch), .play(.nudge)])
        XCTAssertEqual(harness.haptics.operations, [.play(.ballLaunch), .play(.nudge)])
        XCTAssertEqual(launchedStatus, String(localized: "status.ball_launched"))
        XCTAssertEqual(harness.model.statusText, String(localized: "status.nudge"))
    }

    func testInactiveAndBackgroundStatesBlockEffectsAndClearQueuedCommandsOnResume() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        harness.activate()
        let readyStatus = harness.model.statusText
        XCTAssertEqual(readyStatus, String(localized: "status.system_ready"))

        for activity in [LifecycleApplicationActivity.inactive, .background] {
            harness.model.setApplicationActivity(activity)
            let pausedStatus = harness.model.statusText
            XCTAssertEqual(pausedStatus, String(localized: "status.paused"))
            harness.resetEffects()
            harness.model.apply([.plungerReleased(0.8), .nudge(x: 0.3)])

            XCTAssertEqual(harness.audio.operations, [])
            XCTAssertEqual(harness.haptics.operations, [])
            XCTAssertEqual(harness.model.takeSimulationInput(), .idle)
            XCTAssertEqual(harness.model.statusText, pausedStatus)

            harness.model.setApplicationActivity(.active)
            XCTAssertEqual(harness.model.statusText, readyStatus)
            XCTAssertEqual(harness.model.takeSimulationInput(), .idle)
            harness.resetEffects()
            harness.model.apply([.plungerReleased(0.8), .nudge(x: 0.3)])

            XCTAssertEqual(harness.audio.operations, [.play(.ballLaunch), .play(.nudge)])
            XCTAssertEqual(harness.haptics.operations, [.play(.ballLaunch), .play(.nudge)])
            XCTAssertEqual(harness.model.statusText, String(localized: "status.nudge"))
        }
    }

    func testAudioInterruptionBlocksEffectsAndResumeRestoresThem() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        harness.activate()
        let readyStatus = harness.model.statusText
        XCTAssertEqual(readyStatus, String(localized: "status.system_ready"))

        harness.model.audioInterruptionBegan()
        let interruptionStatus = harness.model.statusText
        XCTAssertEqual(interruptionStatus, String(localized: "status.audio_interrupted"))
        harness.resetEffects()
        harness.model.launchBallFromAccessibility()
        harness.model.nudgeFromAccessibility()

        XCTAssertEqual(harness.audio.operations, [])
        XCTAssertEqual(harness.haptics.operations, [])
        XCTAssertEqual(harness.model.takeSimulationInput(), .idle)
        XCTAssertEqual(harness.model.statusText, interruptionStatus)

        harness.model.audioInterruptionEnded(shouldResume: true)
        XCTAssertEqual(harness.model.statusText, readyStatus)
        XCTAssertEqual(harness.model.takeSimulationInput(), .idle)
        harness.resetEffects()
        harness.model.launchBallFromAccessibility()
        harness.model.nudgeFromAccessibility()

        XCTAssertEqual(harness.audio.operations, [.play(.ballLaunch), .play(.nudge)])
        XCTAssertEqual(harness.haptics.operations, [.play(.ballLaunch), .play(.nudge)])
        XCTAssertEqual(harness.model.statusText, String(localized: "status.nudge"))
    }

    private func makeHarness() throws -> OptionalEffectsHarness {
        let identifier = UUID().uuidString
        let suiteName = "OptionalEffectsLifecycleTests.\(identifier)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        let audio = RecordingOptionalEffectsAudioEngine()
        let haptics = RecordingOptionalEffectsHapticsService()
        let model = AppModel(
            audioEngine: audio,
            hapticsService: haptics,
            gameCenterClient: NullGameCenterClient(),
            localGameStore: LocalGameStore(defaults: defaults, directory: directory),
            store: StoreService(
                backend: NullWorkshopStoreBackend(),
                userDefaults: defaults,
                bypassesStore: false
            )
        )
        return OptionalEffectsHarness(
            model: model,
            audio: audio,
            haptics: haptics,
            cleanup: {
                defaults.removePersistentDomain(forName: suiteName)
                try? FileManager.default.removeItem(at: directory)
            }
        )
    }
}

@MainActor
private struct OptionalEffectsHarness {
    let model: AppModel
    let audio: RecordingOptionalEffectsAudioEngine
    let haptics: RecordingOptionalEffectsHapticsService
    let cleanup: () -> Void

    func activate() {
        model.setApplicationActivity(.active)
        model.lifecycleCoordinator.start()
        resetEffects()
    }

    func resetEffects() {
        audio.reset()
        haptics.reset()
    }
}

@MainActor
private final class RecordingOptionalEffectsAudioEngine: PinballAudioEngine {
    enum Operation: Equatable {
        case prepare
        case suspend
        case play(PinballAudioCue)
    }

    private(set) var operations: [Operation] = []
    let isAvailable = true

    func prepare() { operations.append(.prepare) }
    func play(_ cue: PinballAudioCue) { operations.append(.play(cue)) }
    func suspend() { operations.append(.suspend) }
    func reset() { operations.removeAll(keepingCapacity: true) }
}

@MainActor
private final class RecordingOptionalEffectsHapticsService: PinballHapticsService {
    enum Operation: Equatable {
        case prepare
        case suspend
        case play(PinballHapticCue)
    }

    private(set) var operations: [Operation] = []
    let isAvailable = true

    func prepare() { operations.append(.prepare) }
    func play(_ cue: PinballHapticCue) { operations.append(.play(cue)) }
    func suspend() { operations.append(.suspend) }
    func reset() { operations.removeAll(keepingCapacity: true) }
}
