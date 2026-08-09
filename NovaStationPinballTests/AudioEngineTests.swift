import NovaStationCore
import XCTest
@testable import NovaStationPinball

@MainActor
final class AudioEngineTests: XCTestCase {
    func testNullAudioEngineDoesNotBlockGameplayCommands() {
        let model = AppModel(audioEngine: NullAudioEngine(), hapticsService: NullHapticsService())
        activateGameplayForTesting(model)

        model.apply([.plungerReleased(0.8)])

        XCTAssertEqual(model.takeSimulationInput().commands, [.releasePlunger(strength: 0.8)])
    }

    func testAppModelEmitsAudioCuesWithoutChangingSimulationInput() {
        let audio = RecordingAudioEngine()
        let model = AppModel(audioEngine: audio, hapticsService: NullHapticsService())
        activateGameplayForTesting(model)
        audio.reset()

        model.apply([.plungerReleased(0.6), .nudge(x: 0.25)])

        XCTAssertEqual(audio.cues, [.ballLaunch, .nudge])
        XCTAssertEqual(
            model.takeSimulationInput().commands,
            [.releasePlunger(strength: 0.6), .nudge(Vector2(x: 0.25, y: 0))]
        )
    }
}

@MainActor
private final class RecordingAudioEngine: PinballAudioEngine {
    private(set) var cues: [PinballAudioCue] = []
    var isAvailable: Bool { true }

    func prepare() {}
    func play(_ cue: PinballAudioCue) { cues.append(cue) }
    func suspend() {}
    func reset() { cues.removeAll() }
}
