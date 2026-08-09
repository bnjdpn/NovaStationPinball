import NovaStationCore
import XCTest
@testable import NovaStationPinball

@MainActor
final class HapticsServiceTests: XCTestCase {
    func testNullHapticsDoesNotBlockGameplayCommands() {
        let model = AppModel(audioEngine: NullAudioEngine(), hapticsService: NullHapticsService())
        activateGameplayForTesting(model)

        model.apply([.nudge(x: -0.4)])

        XCTAssertEqual(model.takeSimulationInput().commands, [.nudge(Vector2(x: -0.4, y: 0))])
    }

    func testAppModelEmitsHapticCuesWithoutChangingSimulationInput() {
        let haptics = RecordingHapticsService()
        let model = AppModel(audioEngine: NullAudioEngine(), hapticsService: haptics)
        activateGameplayForTesting(model)
        haptics.reset()

        model.apply([.plungerReleased(0.5), .nudge(x: 0.2)])

        XCTAssertEqual(haptics.cues, [.ballLaunch, .nudge])
        XCTAssertEqual(model.takeSimulationInput().commands.count, 2)
    }
}

@MainActor
private final class RecordingHapticsService: PinballHapticsService {
    private(set) var cues: [PinballHapticCue] = []
    var isAvailable: Bool { true }

    func prepare() {}
    func play(_ cue: PinballHapticCue) { cues.append(cue) }
    func suspend() {}
    func reset() { cues.removeAll() }
}
