import Testing
@testable import NovaStationCore

@Suite("GameRulesTests")
struct GameRulesTests {
    @Test("a new game has three regular balls and a neutral score state")
    func newGameDefaults() {
        let state = GameRulesState()

        #expect(state.ballsRemaining == 3)
        #expect(state.ballsInPlay == 1)
        #expect(state.score == 0)
        #expect(state.bonusUnits == 0)
        #expect(state.bonusMultiplier == 1)
        #expect(state.scoreMultiplier == 1)
    }

    @Test("a table award applies the current score multiplier")
    func tableAwardUsesMultiplier() {
        var state = GameRulesState()

        let first = state.awardTableScore(baseScore: 2_500)
        _ = state.increaseScoreMultiplier()
        let second = state.awardTableScore(baseScore: 2_500)

        #expect(first?.points == 2_500)
        #expect(second?.points == 5_000)
        #expect(state.score == 7_500)
    }

    @Test("score awards saturate at the Nova score ceiling")
    func scoreCeiling() {
        let cases = [
            (startingScore: 0, baseScore: 40, expectedPoints: 40, didSaturate: false),
            (
                startingScore: ScoreEngine.maximumScore - 20,
                baseScore: 40,
                expectedPoints: 20,
                didSaturate: true
            ),
            (
                startingScore: ScoreEngine.maximumScore,
                baseScore: 40,
                expectedPoints: 0,
                didSaturate: true
            )
        ]

        for testCase in cases {
            var state = GameRulesState(score: testCase.startingScore)
            let award = state.awardTableScore(baseScore: testCase.baseScore)

            #expect(award?.points == testCase.expectedPoints)
            #expect(award?.didSaturate == testCase.didSaturate)
            #expect(state.score == min(
                ScoreEngine.maximumScore,
                testCase.startingScore + testCase.baseScore
            ))
        }
    }

    @Test("bonus units and multiplier stop at their published caps")
    func bonusCaps() {
        var state = GameRulesState()

        for _ in 0 ..< 24 {
            _ = state.addBonusUnit()
            _ = state.increaseBonusMultiplier()
        }

        #expect(state.bonusUnits == GameRulesState.maximumBonusUnits)
        #expect(state.bonusMultiplier == GameRulesState.maximumBonusMultiplier)
    }

    @Test("draining a single ball awards its banked bonus then resets the bank")
    func drainAwardsBonus() {
        var state = GameRulesState()
        _ = state.addBonusUnit()
        _ = state.addBonusUnit()
        _ = state.increaseBonusMultiplier()

        let award = state.drainBall()

        #expect(award?.points == 4_000)
        #expect(state.score == 4_000)
        #expect(state.bonusUnits == 0)
        #expect(state.bonusMultiplier == 1)
        #expect(state.ballsRemaining == 2)
    }

    @Test("extra balls are limited and replace a drained regular ball")
    func extraBallLimit() {
        var state = GameRulesState()
        let first = state.awardExtraBall()
        let second = state.awardExtraBall()
        let rejected = state.awardExtraBall()

        #expect(first)
        #expect(second)
        #expect(!rejected)
        _ = state.drainBall()

        #expect(state.extraBalls == 1)
        #expect(state.ballsRemaining == 3)
    }

    @Test("multiball starts with three balls and cannot stack")
    func multiball() {
        var state = GameRulesState()
        let activated = state.activateMultiball()

        #expect(activated)
        #expect(state.ballsInPlay == 3)
        let stacked = state.activateMultiball()
        #expect(!stacked)
        _ = state.drainBall()

        #expect(state.ballsInPlay == 2)
        #expect(state.ballsRemaining == 3)
    }

    @Test("ball save relaunches one drain during its fixed deterministic window")
    func ballSave() {
        var state = GameRulesState()
        state.activateBallSave()
        state.advance(ticks: GameRulesState.ballSaveDurationTicks - 1)

        _ = state.drainBall()

        #expect(state.ballsRemaining == 3)
        #expect(state.ballSaveTicksRemaining == 0)
        state.advance(ticks: 1)
        _ = state.drainBall()
        #expect(state.ballsRemaining == 2)
    }

    @Test("tilt suppresses scoring and ends the current ball without a bonus")
    func tilt() {
        var state = GameRulesState()
        _ = state.addBonusUnit()

        state.tilt()
        let award = state.awardTableScore(baseScore: 500)
        let wasTiltedBeforeDrain = state.isTilted
        let drainAward = state.drainBall()

        #expect(wasTiltedBeforeDrain)
        #expect(award == nil)
        #expect(drainAward == nil)
        #expect(state.score == 0)
        #expect(state.ballsRemaining == 2)
    }

    @Test("the third unsaved drain ends a three-ball game")
    func gameEndsAfterThreeDrains() {
        var state = GameRulesState()

        _ = state.drainBall()
        _ = state.drainBall()
        _ = state.drainBall()

        #expect(state.isGameOver)
        #expect(state.ballsRemaining == 0)
        #expect(state.ballsInPlay == 0)
        #expect(state.drainBall() == nil)
    }

    @Test("a mission starts only for the current clearance and completes on its trigger")
    func missionStartAndCompletion() {
        var state = GameRulesState()
        let mission = MissionCatalog.definition(for: .orbitalWake)
        let prematureStart = state.startMission(.relayBloom)
        let startAward = state.startMission(.orbitalWake)
        let completionAward = state.completeMission(trigger: mission.completionTrigger)

        #expect(prematureStart == nil)
        #expect(startAward?.points == mission.startScore)
        #expect(completionAward?.points == mission.completionScore)
        #expect(state.missionState == .completed(.orbitalWake))
        #expect(state.clearance == .dockKey)
    }

    @Test("promotion rejects lower-rank missions and accepts only the exact active clearance")
    func missionRequiresExactClearance() {
        var state = GameRulesState()
        _ = state.startMission(.orbitalWake)
        _ = state.completeMission(trigger: MissionCatalog.definition(for: .orbitalWake).completionTrigger)
        state.acknowledgeMissionResult()

        #expect(state.clearance == .dockKey)
        #expect(state.startMission(.orbitalWake) == nil)
        #expect(state.startMission(.cargoDrift) == nil)
        #expect(state.startMission(.relayBloom) != nil)
    }

    @Test("a mission completes only after its ordered physical objective events")
    func physicalMissionObjectiveProgress() {
        var state = GameRulesState()
        let mission = MissionCatalog.definition(for: .orbitalWake)
        _ = state.startMission(mission.id)

        #expect(mission.objectiveEvents.count >= 3)
        #expect(state.recordMissionObjective(eventName: mission.objectiveEvents[0]) == nil)
        #expect(state.recordMissionObjective(eventName: "sensor:unrelated") == nil)
        #expect(state.missionState == .active(mission.id))
        for event in mission.objectiveEvents {
            _ = state.recordMissionObjective(eventName: event)
        }

        #expect(state.missionState == .completed(mission.id))
        #expect(state.clearance == .dockKey)
    }

    @Test("an active mission can fail without promoting the player")
    func missionFailure() {
        var state = GameRulesState()
        _ = state.startMission(.orbitalWake)

        state.failMission()

        #expect(state.missionState == .failed(.orbitalWake))
        #expect(state.clearance == nil)
        state.acknowledgeMissionResult()
        #expect(state.missionState == .idle)
    }

    @Test("draining the last active ball fails its mission")
    func drainFailsMission() {
        var state = GameRulesState()
        _ = state.startMission(.orbitalWake)

        _ = state.drainBall()

        #expect(state.missionState == .failed(.orbitalWake))
    }

    @Test("resource-driven missions fail deterministically when station power depletes")
    func resourceDrivenMissionAbort() {
        var state = GameRulesState()
        let mission = MissionCatalog.definition(for: .orbitalWake)
        _ = state.startMission(.orbitalWake)

        #expect(mission.timing == .resourceDriven(abortTrigger: .stationPowerDepleted))
        state.advance(ticks: GameRulesState.maximumStationPower * GameRulesState.stationPowerTicksPerUnit)
        #expect(state.missionState == .failed(.orbitalWake))
        let didAbort = state.applyMissionAbort(.stationPowerDepleted)
        #expect(!didAbort)
        #expect(state.missionState == .failed(.orbitalWake))
    }

    @Test("wrong or inactive mission abort triggers leave state unchanged")
    func ignoredMissionAbortTriggers() {
        var idleState = GameRulesState()
        let idleAbort = idleState.applyMissionAbort(.stationPowerDepleted)

        var activeState = GameRulesState()
        _ = activeState.startMission(.orbitalWake)
        let wrongAbort = activeState.applyMissionAbort(.signalInterlock)

        var completedState = GameRulesState()
        let mission = MissionCatalog.definition(for: .orbitalWake)
        _ = completedState.startMission(.orbitalWake)
        _ = completedState.completeMission(trigger: mission.completionTrigger)
        let completedAbort = completedState.applyMissionAbort(.stationPowerDepleted)

        var gameOverState = GameRulesState()
        _ = gameOverState.drainBall()
        _ = gameOverState.drainBall()
        _ = gameOverState.drainBall()
        let gameOverAbort = gameOverState.applyMissionAbort(.stationPowerDepleted)

        #expect(!idleAbort)
        #expect(idleState.missionState == .idle)
        #expect(!wrongAbort)
        #expect(activeState.missionState == .active(.orbitalWake))
        #expect(!completedAbort)
        #expect(completedState.missionState == .completed(.orbitalWake))
        #expect(!gameOverAbort)
        #expect(gameOverState.isGameOver)
        #expect(gameOverState.missionState == .idle)
    }

    @Test("tilt fails an active mission and prevents completion awards")
    func tiltFailsMission() {
        var state = GameRulesState()
        let mission = MissionCatalog.definition(for: .orbitalWake)
        _ = state.startMission(.orbitalWake)

        state.tilt()
        let award = state.completeMission(trigger: mission.completionTrigger)

        #expect(state.missionState == .failed(.orbitalWake))
        #expect(award == nil)
    }

    @Test("every clearance is earned in its catalog order")
    func allClearancePromotions() {
        var state = GameRulesState()
        let cases = MissionCatalog.all.prefix(ClearanceLevel.allCases.count)

        for mission in cases {
            let startAward = state.startMission(mission.id)
            let completionAward = state.completeMission(trigger: mission.completionTrigger)

            #expect(startAward?.points == mission.startScore)
            #expect(completionAward?.points == mission.completionScore)
            #expect(state.clearance == mission.awardedClearance)
            state.acknowledgeMissionResult()
            #expect(state.missionState == .idle)
        }

        #expect(ClearanceLevel.allCases.count == 9)
        #expect(state.clearance == ClearanceLevel.allCases.last)
    }
}
