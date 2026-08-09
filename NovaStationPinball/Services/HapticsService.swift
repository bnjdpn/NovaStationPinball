import CoreHaptics
import Foundation

enum PinballHapticCue: Sendable, Equatable {
    case ballLaunch
    case nudge
}

@MainActor
protocol PinballHapticsService: AnyObject {
    var isAvailable: Bool { get }
    func prepare()
    func play(_ cue: PinballHapticCue)
    func suspend()
}

@MainActor
final class NullHapticsService: PinballHapticsService {
    let isAvailable = false

    func prepare() {}
    func play(_ cue: PinballHapticCue) {}
    func suspend() {}
}

@MainActor
final class CoreHapticsService: PinballHapticsService {
    private var engine: CHHapticEngine?
    private(set) var isAvailable = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    func prepare() {
        guard isAvailable else { return }
        do {
            if engine == nil { engine = try CHHapticEngine() }
            try engine?.start()
        } catch {
            engine = nil
            isAvailable = false
        }
    }

    func play(_ cue: PinballHapticCue) {
        prepare()
        guard isAvailable, let engine else { return }
        let values: (intensity: Float, sharpness: Float) = switch cue {
        case .ballLaunch: (0.65, 0.75)
        case .nudge: (0.45, 0.25)
        }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: values.intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: values.sharpness)
            ],
            relativeTime: 0
        )
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            // Haptic feedback is optional; gameplay must continue unchanged.
        }
    }

    func suspend() {
        engine?.stop(completionHandler: nil)
    }
}
