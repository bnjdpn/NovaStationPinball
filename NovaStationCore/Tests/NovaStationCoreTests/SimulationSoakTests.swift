import Foundation
import Testing
@testable import NovaStationCore

@Suite("SimulationSoakTests")
struct SimulationSoakTests {
    @Test("the production Nova GameSession remains finite and rules-consistent for thirty simulated minutes")
    func thirtyMinuteProductionSessionSoak() throws {
        var session = try GameSession()
        _ = try session.startNewGame()
        var eventNames: Set<String> = []
        _ = try NovaStationGameplayScript.shoot(NovaStationTable.Event.missionSelect, in: &session)
        _ = try NovaStationGameplayScript.shoot(NovaStationTable.Event.missionStart, in: &session)
        for event in MissionCatalog.definition(for: .orbitalWake).objectiveEvents {
            let frames = try NovaStationGameplayScript.shoot(event, in: &session)
            eventNames.formUnion(frames.flatMap(\.events).map(\.name))
        }
        let completedMissionDuringSoak = session.rules.missionState == .completed(.orbitalWake)
        let ticks = 30 * 60 * Int(1 / PinballSimulation.fixedTimeStep)
        var gamesPlayed = 1
        var activeInputTicks = 0
        var maximumScore = 0
        var drainCount = 0
        var spawnCount = 0

        for tick in 0 ..< ticks {
            if session.phase == .gameOver {
                _ = try session.startNewGame()
                gamesPlayed += 1
            }

            let cycle = tick % 480
            let exercisesFlippers = tick < 60_000
            let input = PlayerInput(
                leftFlipperIsPressed: exercisesFlippers
                    && ((72 ..< 112).contains(cycle) || (280 ..< 302).contains(cycle)),
                rightFlipperIsPressed: exercisesFlippers
                    && ((96 ..< 136).contains(cycle) || (300 ..< 322).contains(cycle)),
                plungerPull: cycle == 0 ? 0.82 : 0,
                nudge: cycle == 220
                    ? Vector2(x: NovaStationGameplayScript.minimumTouchNudge, y: 0)
                    : .zero
            )
            let frame = session.step(input)
            if input != .idle { activeInputTicks += 1 }
            eventNames.formUnion(frame.events.map(\.name))
            for effect in frame.effects {
                switch effect {
                case .ballDrained: drainCount += 1
                case .ballSpawned: spawnCount += 1
                default: break
                }
            }
            maximumScore = max(maximumScore, frame.rules.score)

            if tick % 120 == 0 {
                #expect(frame.snapshot.tableVersion == NovaStationTable.definition.version)
                #expect(frame.snapshot.elapsedTime.isFinite)
                #expect(frame.snapshot.balls.allSatisfy { $0.position.isFinite && $0.velocity.isFinite })
                #expect(rulesAreValid(frame.rules))
                #expect(frame.snapshot.balls.count == frame.rules.ballsInPlay)
            }
        }

        #expect(ticks == 432_000)
        #expect(completedMissionDuringSoak)
        #expect(activeInputTicks > 0)
        #expect(eventNames.contains { $0.hasPrefix("bumper:") })
        #expect(eventNames.contains { $0.hasPrefix("sensor:") && $0 != NovaStationTable.Event.drain })
        #expect(drainCount > 0)
        #expect(spawnCount > 0)
        #expect(maximumScore > 0)
        #expect(gamesPlayed > 1, "ordinary play must physically reach game over before restarting")
        #expect(session.recording.inputs.count <= ticks)
    }

    private func rulesAreValid(_ rules: GameRulesState) -> Bool {
        guard (0 ... ScoreEngine.maximumScore).contains(rules.score),
              (0 ... GameRulesState.regularBallCount).contains(rules.ballsRemaining),
              (0 ... GameRulesState.regularBallCount).contains(rules.ballsInPlay),
              (0 ... GameRulesState.maximumExtraBalls).contains(rules.extraBalls),
              (0 ... GameRulesState.maximumBonusUnits).contains(rules.bonusUnits),
              (1 ... GameRulesState.maximumBonusMultiplier).contains(rules.bonusMultiplier),
              (1 ... GameRulesState.maximumScoreMultiplier).contains(rules.scoreMultiplier),
              (0 ... GameRulesState.ballSaveDurationTicks).contains(rules.ballSaveTicksRemaining),
              !rules.isGameOver || (rules.ballsRemaining == 0 && rules.ballsInPlay == 0)
        else { return false }

        switch rules.missionState {
        case .idle, .completed, .failed:
            return rules.missionTicksRemaining == nil
        case .active:
            return rules.missionTicksRemaining == nil || rules.missionTicksRemaining! > 0
        }
    }
}
