import AVFAudio
import Foundation

enum PinballAudioCue: Sendable, Equatable {
    case ballLaunch
    case nudge
}

@MainActor
protocol PinballAudioEngine: AnyObject {
    var isAvailable: Bool { get }
    func prepare()
    func play(_ cue: PinballAudioCue)
    func suspend()
}

@MainActor
final class NullAudioEngine: PinballAudioEngine {
    let isAvailable = false

    func prepare() {}
    func play(_ cue: PinballAudioCue) {}
    func suspend() {}
}

/// A deliberately small, self-contained AVAudioEngine adapter. It synthesizes
/// short original feedback tones and converts every engine failure into silence.
@MainActor
final class AVAudioPinballEngine: PinballAudioEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private(set) var isAvailable = true

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func prepare() {
        guard isAvailable, !engine.isRunning else { return }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            isAvailable = false
        }
    }

    func play(_ cue: PinballAudioCue) {
        prepare()
        guard isAvailable, let buffer = makeBuffer(for: cue) else { return }
        player.scheduleBuffer(buffer)
        if !player.isPlaying { player.play() }
    }

    func suspend() {
        player.stop()
        engine.pause()
    }

    private func makeBuffer(for cue: PinballAudioCue) -> AVAudioPCMBuffer? {
        let specification: (frequency: Double, duration: Double, amplitude: Float) = switch cue {
        case .ballLaunch: (520, 0.085, 0.20)
        case .nudge: (105, 0.045, 0.16)
        }
        let frameCount = AVAudioFrameCount(format.sampleRate * specification.duration)
        guard
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            let samples = buffer.floatChannelData?[0]
        else { return nil }

        buffer.frameLength = frameCount
        for frame in 0..<Int(frameCount) {
            let progress = Double(frame) / Double(max(1, Int(frameCount) - 1))
            let envelope = Float(1 - progress)
            let phase = 2 * Double.pi * specification.frequency * Double(frame) / format.sampleRate
            samples[frame] = sin(Float(phase)) * specification.amplitude * envelope
        }
        return buffer
    }
}
