import Foundation
import Testing
@testable import NovaStationCore

@Suite("RewindBufferTests")
struct RewindBufferTests {
    /// Drives a real session and lays keyframes exactly the way
    /// `SimulationDriver` does in production.
    private func playRecordingMarks(
        ticks: Int,
        into buffer: inout RewindBuffer,
        session: inout GameSession
    ) {
        for tick in 0 ..< ticks {
            let frame = session.step(PlayerInput(
                leftFlipperIsPressed: tick % 97 < 6,
                rightFlipperIsPressed: tick % 131 < 6,
                plungerPull: 0,
                nudge: .zero
            ))
            buffer.record(
                state: session.sessionState,
                inputIndex: session.recordedInputCount,
                isBallStart: frame.effects.contains { effect in
                    if case .ballSpawned = effect { return true }
                    return false
                }
            )
        }
    }

    @Test("a rewind restores the exact recorded state and keeps a replayable recording")
    func rewindRestoresExactState() throws {
        var session = try GameSession()
        _ = try session.startNewGame()
        var buffer = RewindBuffer()
        playRecordingMarks(ticks: 1_500, into: &buffer, session: &session)

        let mark = try #require(buffer.mark(secondsBack: 3, at: session.recordedInputCount))
        #expect(mark.inputIndex < session.recordedInputCount)

        let rewound = try session.rewound(to: mark)

        #expect(rewound.sessionState == mark.state)
        #expect(rewound.recordedInputCount == mark.inputIndex)
        #expect(rewound.isAssisted)
        // The truncated stream is still a valid Replay v3 that reproduces the
        // restored state exactly.
        let result = try rewound.recording.replay()
        #expect(result.snapshot == rewound.snapshot)
        #expect(result.rules == rewound.rules)
    }

    @Test("start of ball is an exact keyframe, never an approximation")
    func ballStartIsExact() throws {
        var session = try GameSession()
        let opening = try session.startNewGame()
        var buffer = RewindBuffer()
        buffer.record(
            state: session.sessionState,
            inputIndex: session.recordedInputCount,
            isBallStart: opening.effects.contains { effect in
                if case .ballSpawned = effect { return true }
                return false
            }
        )
        playRecordingMarks(ticks: 900, into: &buffer, session: &session)

        let mark = try #require(buffer.ballStartMark(at: session.recordedInputCount))

        #expect(mark.isBallStart)
        let rewound = try session.rewound(to: mark)
        #expect(rewound.snapshot == mark.state.simulation.snapshot)
        #expect(rewound.recordedInputCount == mark.inputIndex)
    }

    @Test("rewinding discards the abandoned timeline")
    func discardsAbandonedMarks() throws {
        var session = try GameSession()
        _ = try session.startNewGame()
        var buffer = RewindBuffer()
        playRecordingMarks(ticks: 1_200, into: &buffer, session: &session)

        let mark = try #require(buffer.mark(secondsBack: 3, at: session.recordedInputCount))
        buffer.discardMarks(after: mark.inputIndex)

        #expect(buffer.marks.allSatisfy { $0.inputIndex <= mark.inputIndex })
    }

    @Test("an empty buffer offers no rewind instead of a wrong one")
    func emptyBufferHasNoMarks() {
        let buffer = RewindBuffer()

        #expect(buffer.isEmpty)
        #expect(buffer.mark(secondsBack: 3, at: 0) == nil)
        #expect(buffer.mark(secondsBack: 5, at: 4_000) == nil)
        #expect(buffer.ballStartMark(at: 4_000) == nil)
    }

    @Test("the ring stays bounded and cheap after a long game")
    func boundedFootprintAfterALongGame() throws {
        var session = try GameSession()
        _ = try session.startNewGame()
        var buffer = RewindBuffer()
        // Five simulated minutes: more than four times the retained window.
        playRecordingMarks(ticks: 72_000, into: &buffer, session: &session)

        #expect(buffer.keyframeCount <= RewindBuffer.keyframeCapacity)
        #expect(buffer.ballStartCount <= RewindBuffer.ballStartCapacity)

        let encoder = JSONEncoder()
        let bytes = try buffer.marks.reduce(0) { total, mark in
            total + (try encoder.encode(mark.state).count)
        }
        #expect(bytes < 256 * 1_024, "rewind ring grew to \(bytes) bytes")

        // A rewind restores a stored state: no physics is replayed at all.
        let mark = try #require(buffer.mark(secondsBack: 5, at: session.recordedInputCount))
        let rewound = try session.rewound(to: mark)
        #expect(rewound.sessionState == mark.state)
    }

    @Test("a rewound run is assisted for good, and only a new game clears it")
    func assistedFlagIsIrreversibleWithinTheRun() throws {
        var session = try GameSession()
        _ = try session.startNewGame()
        #expect(!session.isAssisted)
        var buffer = RewindBuffer()
        playRecordingMarks(ticks: 600, into: &buffer, session: &session)

        let mark = try #require(buffer.mark(secondsBack: 1, at: session.recordedInputCount))
        var rewound = try session.rewound(to: mark)
        #expect(rewound.isAssisted)

        for _ in 0 ..< 240 { _ = rewound.step(.idle) }
        #expect(rewound.isAssisted)

        _ = try rewound.startNewGame()
        #expect(!rewound.isAssisted)
    }
}
