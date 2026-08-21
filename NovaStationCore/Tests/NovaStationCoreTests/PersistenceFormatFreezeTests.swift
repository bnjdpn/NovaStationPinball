import Foundation
import Testing
@testable import NovaStationCore

/// The Workshop release adds features, never a persistence migration. Every
/// shipped format version is frozen here: a bump breaks this test on purpose,
/// so nobody can silently orphan an in-progress game or a saved high score.
@Suite("PersistenceFormatFreezeTests")
struct PersistenceFormatFreezeTests {
    @Test("shipped persistence formats stay exactly where 1.0 left them")
    func formatVersionsAreFrozen() {
        #expect(Replay.formatVersion == 3)
        #expect(ActiveCheckpoint.formatVersion == 3)
        #expect(CheckpointEnvelope.formatVersion == 1)
        #expect(HighScoreEntry.formatVersion == 1)
        #expect(SettingsState.formatVersion == 1)
    }

    @Test("the Workshop stores are new types under new keys, at version 1")
    func newStoresStartAtVersionOne() throws {
        #expect(DrillProgress.formatVersion == 1)

        let data = try JSONEncoder().encode(DrillProgress())
        #expect(String(decoding: data, as: UTF8.self).contains("\"formatVersion\":1"))
    }

    @Test("a foreign version is rejected instead of being half-read")
    func foreignVersionsAreRejected() {
        let payload = Data(#"{"formatVersion":2,"entries":{}}"#.utf8)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(DrillProgress.self, from: payload)
        }
    }

    @Test("rewinding never touches the checkpoint format")
    func rewindKeepsCheckpointFormat() throws {
        var session = try GameSession()
        _ = try session.startNewGame()
        var buffer = RewindBuffer()
        for _ in 0 ..< 720 {
            _ = session.step(.idle)
            buffer.record(
                state: session.sessionState,
                inputIndex: session.recordedInputCount,
                isBallStart: false
            )
        }
        let mark = try #require(buffer.mark(secondsBack: 1, at: session.recordedInputCount))
        let rewound = try session.rewound(to: mark)

        let checkpoint = ActiveCheckpoint(
            identifier: "freeze",
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sessionCheckpoint: rewound.checkpoint
        )
        let data = try JSONEncoder().encode(CheckpointEnvelope(checkpoint: checkpoint))
        let restored = try JSONDecoder().decode(CheckpointEnvelope.self, from: data)

        #expect(restored.checkpoint == checkpoint)
        #expect(String(decoding: data, as: UTF8.self).contains("\"formatVersion\":3"))
    }
}
