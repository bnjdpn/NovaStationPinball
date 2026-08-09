import Foundation
import Testing
@testable import NovaStationCore

struct PersistenceModelsTests {
    @Test("settings preserve their versioned payload")
    func settingsRoundTrip() throws {
        let settings = SettingsState(
            musicEnabled: false,
            soundEffectsEnabled: true,
            hapticsEnabled: false
        )

        let data = try JSONEncoder().encode(settings)

        #expect(try JSONDecoder().decode(SettingsState.self, from: data) == settings)
        #expect(String(decoding: data, as: UTF8.self).contains("\"formatVersion\":1"))
    }

    @Test("high score entries preserve their versioned identity")
    func highScoreRoundTrip() throws {
        let entry = HighScoreEntry(
            identifier: "station-01",
            playerName: "NOVA",
            score: 125_000,
            achievedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try JSONEncoder().encode(entry)

        #expect(try JSONDecoder().decode(HighScoreEntry.self, from: data) == entry)
        #expect(String(decoding: data, as: UTF8.self).contains("\"formatVersion\":1"))
    }

    @Test("checkpoint envelopes restore all active game state")
    func checkpointEnvelopeRoundTrip() throws {
        var session = try GameSession()
        for tick in 0 ..< 120 {
            _ = session.step(PlayerInput(
                leftFlipperIsPressed: tick % 40 < 8,
                rightFlipperIsPressed: tick % 60 < 8,
                plungerPull: tick == 0 ? 0.8 : 0,
                nudge: .zero
            ))
        }
        let snapshot = session.snapshot
        let replay = session.recording
        let checkpoint = ActiveCheckpoint(
            identifier: "checkpoint-01",
            savedAt: Date(timeIntervalSince1970: 1_700_000_001),
            snapshot: snapshot,
            rules: session.rules,
            replay: replay
        )
        let envelope = CheckpointEnvelope(checkpoint: checkpoint)

        let data = try JSONEncoder().encode(envelope)

        #expect(try JSONDecoder().decode(CheckpointEnvelope.self, from: data) == envelope)
        #expect(String(decoding: data, as: UTF8.self).contains("\"formatVersion\":1"))
        let replayed = try replay.replay()
        #expect(replayed.snapshot == checkpoint.snapshot)
        #expect(replayed.rules == checkpoint.rules)
    }

    @Test("unsupported persistence versions are rejected")
    func unsupportedVersionIsRejected() throws {
        let payload = Data("{\"formatVersion\":2,\"musicEnabled\":true,\"soundEffectsEnabled\":true,\"hapticsEnabled\":true}".utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SettingsState.self, from: payload)
        }
    }

    @Test("all remaining persistence models reject unsupported versions")
    func remainingUnsupportedVersionsAreRejected() throws {
        let score = HighScoreEntry(
            identifier: "invalid-version-score",
            playerName: "NOVA",
            score: 10,
            achievedAt: Date(timeIntervalSince1970: 1)
        )
        let snapshot = SimulationSnapshot(tableVersion: 1, elapsedTime: 0, balls: [])
        let checkpoint = ActiveCheckpoint(
            identifier: "invalid-version-checkpoint",
            savedAt: Date(timeIntervalSince1970: 2),
            snapshot: snapshot,
            rules: GameRulesState(),
            replay: Replay(tableVersion: 1, initialSnapshot: snapshot, inputs: [])
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(HighScoreEntry.self, from: try unsupportedVersionPayload(for: score))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ActiveCheckpoint.self, from: try unsupportedVersionPayload(for: checkpoint))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                CheckpointEnvelope.self,
                from: try unsupportedVersionPayload(for: CheckpointEnvelope(checkpoint: checkpoint))
            )
        }
    }

    private func unsupportedVersionPayload<Value: Encodable>(for value: Value) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        object["formatVersion"] = 999
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
