import Foundation
import Testing
@testable import NovaStationCore

@Suite("ReplayDeterminismTests")
struct ReplayDeterminismTests {
    @Test("GameSession records ordered production inputs and replays physical events ten times")
    func productionSessionReplayIsStableAcrossTenRuns() throws {
        let route = try #require(NovaStationTable.mechanicShotRoutes.first(where: {
            $0.eventName == "bumper:bumper-orbit"
        }))
        var session = try GameSession(
            snapshot: SimulationSnapshot(
                tableVersion: NovaStationTable.version,
                elapsedTime: 0,
                balls: [BallState(id: 7, position: route.start, velocity: route.velocity)]
            ),
            rules: GameRulesState(),
            phase: .playing
        )
        for tick in 0 ..< 180 {
            _ = session.step(PlayerInput(
                leftFlipperIsPressed: tick % 60 < 8,
                rightFlipperIsPressed: tick % 75 < 8,
                plungerPull: 0,
                nudge: tick == 120 ? Vector2(x: 0.001, y: 0) : .zero
            ))
        }

        let replay = session.recording
        let stableJSON = try replay.stableJSON()
        let decoded = try Replay(stableJSON: stableJSON)
        let results = try (0 ..< 10).map { _ in try decoded.replay() }

        #expect(replay.inputs.count == 180)
        #expect(session.rules.score >= NovaStationTable.Score.bumper)
        #expect(decoded == replay)
        #expect(Set(results.map(\.hash)).count == 1)
        #expect(results.allSatisfy { result in
            result.snapshot == session.snapshot
                && result.rules == session.rules
                && result.phase == session.phase
                && result.recording == replay
        })
    }

    @Test("canonical replay rejects synthetic legacy action format explicitly")
    func legacyReplayIsRejected() throws {
        let replay = try startedSession().recording
        let json = try replay.stableJSON()
        let legacy = json.replacingOccurrences(of: "\"formatVersion\":3", with: "\"formatVersion\":2")

        #expect(throws: ReplayError.unsupportedFormatVersion(2)) {
            try Replay(stableJSON: legacy)
        }
        #expect(throws: ReplayError.self) { try Replay(stableJSON: " " + json) }
        #expect(try Replay.decodeJSON(Data(json.utf8)) == replay)
    }

    @Test("restoring a precise replay anchor continues the same recording")
    func restoreContinuesRecording() throws {
        var original = try startedSession()
        for _ in 0 ..< 12 { _ = original.step(.idle) }
        let checkpointReplay = original.recording
        let checkpointSnapshot = original.snapshot
        let checkpointRules = original.rules

        var restored = try GameSession()
        try restored.restore(
            snapshot: checkpointSnapshot,
            rules: checkpointRules,
            replay: checkpointReplay
        )
        _ = restored.step(PlayerInput(
            leftFlipperIsPressed: true,
            rightFlipperIsPressed: false,
            plungerPull: 0,
            nudge: .zero
        ))

        #expect(restored.recording.inputs.count == checkpointReplay.inputs.count + 1)
        let result = try restored.recording.replay()
        #expect(result.snapshot == restored.snapshot)
        #expect(result.rules == restored.rules)
        #expect(result.phase == restored.phase)
    }

    @Test("checkpoint v3 continues exactly with a charged plunger, moving flipper and partial tilt")
    func transientCheckpointContinuesTickForTick() throws {
        var original = try startedSession()
        _ = original.step(PlayerInput(
            leftFlipperIsPressed: true,
            rightFlipperIsPressed: false,
            plungerPull: 0.8,
            nudge: Vector2(x: 0.5, y: 0)
        ))
        let checkpoint = original.checkpoint
        let transient = checkpoint.currentState.simulation
        #expect(transient.plungerState.pull == 0.8)
        #expect(transient.flipperStates[0].angle != transient.flipperStates[0].definition.restAngle)
        #expect(transient.flipperStates[0].angle != transient.flipperStates[0].definition.activeAngle)
        #expect(transient.tiltState.accumulatedNudge > 0)
        #expect(!transient.tiltState.isTilted)

        var restored = try GameSession(checkpoint: checkpoint)
        let continuation = (0 ..< 360).map { tick in
            PlayerInput(
                leftFlipperIsPressed: tick < 24,
                rightFlipperIsPressed: (80 ..< 112).contains(tick),
                plungerPull: 0,
                nudge: tick == 160 ? Vector2(x: 0.15, y: -0.05) : .zero
            )
        }
        for input in continuation {
            #expect(original.step(input) == restored.step(input))
            #expect(original.checkpoint.currentState == restored.checkpoint.currentState)
        }
        #expect(original.checkpoint == restored.checkpoint)
        #expect(try original.recording.stableJSON() == restored.recording.stableJSON())
        #expect(try original.recording.replay().hash == restored.recording.replay().hash)
    }

    @Test("versioned stable hashers keep their own versions and reject invalid versions")
    func stableHasherVersionsAreIndependent() throws {
        var versionOne = try StableHasher(version: 1)
        var versionTwo = try StableHasher(version: 2)
        versionOne.combine("same replay bytes")
        versionTwo.combine("same replay bytes")
        #expect(versionOne.finalize().hasPrefix("nova-station-h1-"))
        #expect(versionTwo.finalize().hasPrefix("nova-station-h2-"))
        #expect(versionOne.finalize() != versionTwo.finalize())
        #expect(throws: StableHasherError.self) { try StableHasher(version: 0) }
    }

    private func startedSession() throws -> GameSession {
        var session = try GameSession()
        _ = try session.startNewGame()
        return session
    }
}
