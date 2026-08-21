import Foundation

/// One recorded keyframe of a live game. A mark is a complete
/// `GameSessionState`, so restoring it costs no physics at all: the session
/// continues on the exact next 240 Hz tick, and the truncated input stream
/// keeps `GameSession.recording` a byte-exact replayable Replay v3.
public struct RewindMark: Sendable, Equatable {
    /// Number of recorded inputs that produced `state`.
    public let inputIndex: Int
    /// Simulation clock at the mark, in seconds.
    public let elapsedTime: Double
    /// True when the mark was laid on a `.ballSpawned` effect.
    public let isBallStart: Bool
    public let state: GameSessionState

    public init(inputIndex: Int, elapsedTime: Double, isBallStart: Bool, state: GameSessionState) {
        self.inputIndex = inputIndex
        self.elapsedTime = elapsedTime
        self.isBallStart = isBallStart
        self.state = state
    }
}

/// In-memory ring of state keyframes backing the Workshop rewind.
///
/// Nothing here is persisted: `ActiveCheckpoint` and every other on-disk
/// format stay exactly where they were. The buffer holds one keyframe per
/// second over the last two minutes plus the last sixteen ball starts, which
/// is a few tens of kilobytes of `GameSessionState`.
public struct RewindBuffer: Sendable, Equatable {
    /// 240 Hz simulation: one keyframe per simulated second.
    public static let ticksPerKeyframe = 240
    /// Two minutes of periodic history.
    public static let keyframeCapacity = 120
    /// Ball starts are kept separately so "start of ball" is always exact.
    public static let ballStartCapacity = 16

    private var keyframes: [RewindMark] = []
    private var ballStarts: [RewindMark] = []

    public init() {}

    public var keyframeCount: Int { keyframes.count }
    public var ballStartCount: Int { ballStarts.count }
    public var isEmpty: Bool { keyframes.isEmpty && ballStarts.isEmpty }

    /// Every mark held by the buffer, oldest first. Used by budget tests.
    public var marks: [RewindMark] {
        (keyframes + ballStarts).sorted { $0.inputIndex < $1.inputIndex }
    }

    public mutating func removeAll() {
        keyframes.removeAll(keepingCapacity: true)
        ballStarts.removeAll(keepingCapacity: true)
    }

    /// Records the state produced by the tick at `inputIndex`. Called once per
    /// simulated tick; only periodic ticks and ball starts are retained.
    public mutating func record(
        state: GameSessionState,
        inputIndex: Int,
        isBallStart: Bool
    ) {
        let mark = RewindMark(
            inputIndex: inputIndex,
            elapsedTime: state.simulation.snapshot.elapsedTime,
            isBallStart: isBallStart,
            state: state
        )
        if isBallStart {
            append(mark, to: &ballStarts, capacity: Self.ballStartCapacity)
        }
        if inputIndex % Self.ticksPerKeyframe == 0 {
            append(mark, to: &keyframes, capacity: Self.keyframeCapacity)
        }
    }

    /// Drops every mark laid after `inputIndex`. Called on rewind so the
    /// abandoned timeline can never be restored again.
    public mutating func discardMarks(after inputIndex: Int) {
        keyframes.removeAll { $0.inputIndex > inputIndex }
        ballStarts.removeAll { $0.inputIndex > inputIndex }
    }

    /// Nearest keyframe at or before `secondsBack` seconds of simulation.
    /// Returns nil when no earlier keyframe exists yet.
    public func mark(secondsBack: Double, at inputIndex: Int) -> RewindMark? {
        guard secondsBack.isFinite, secondsBack > 0 else { return nil }
        let ticksBack = Int((secondsBack * Double(Self.ticksPerKeyframe)).rounded())
        let target = inputIndex - ticksBack
        let candidates = marks.filter { $0.inputIndex < inputIndex }
        guard !candidates.isEmpty else { return nil }
        return candidates.last { $0.inputIndex <= target } ?? candidates.first
    }

    /// Start of the ball currently in play, exact — zero ticks to replay.
    public func ballStartMark(at inputIndex: Int) -> RewindMark? {
        ballStarts.last { $0.inputIndex < inputIndex }
    }

    private func append(
        _ mark: RewindMark,
        to ring: inout [RewindMark],
        capacity: Int
    ) {
        if let last = ring.last, last.inputIndex == mark.inputIndex {
            ring[ring.count - 1] = mark
            return
        }
        ring.append(mark)
        if ring.count > capacity {
            ring.removeFirst(ring.count - capacity)
        }
    }
}
