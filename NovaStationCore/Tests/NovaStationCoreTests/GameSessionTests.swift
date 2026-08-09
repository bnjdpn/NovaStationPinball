import Testing
@testable import NovaStationCore

@Suite("GameSessionTests")
struct GameSessionTests {
    @Test("every production gameplay script stays inside the real app control domain")
    func gameplayScriptsUseAppReachableInputsOnly() throws {
        var recordings: [[ReplayInput]] = []
        let events = Set(MissionID.allCases.flatMap { MissionCatalog.definition(for: $0).objectiveEvents })
        for event in events.sorted() {
            var session = try startedSession()
            _ = try NovaStationGameplayScript.shoot(event, in: &session)
            recordings.append(session.recording.inputs)
        }

        var mission = try startedSession()
        try NovaStationGameplayScript.completeOrbitalWake(in: &mission)
        _ = try NovaStationGameplayScript.shoot(NovaStationTable.Event.missionAcknowledge, in: &mission)
        recordings.append(mission.recording.inputs)

        var tilted = try startedSession()
        NovaStationGameplayScript.tilt(in: &tilted)
        recordings.append(tilted.recording.inputs)

        var gameOver = try startedSession()
        try NovaStationGameplayScript.playUntilGameOver(in: &gameOver)
        recordings.append(gameOver.recording.inputs)

        for replayInput in recordings.flatMap({ $0 }) {
            let input = replayInput.input
            #expect(input.plungerPull.isFinite && (0 ... 1).contains(input.plungerPull))
            #expect(input.nudge.y == 0)
            #expect(input.nudge.x.isFinite)
            let magnitude = abs(input.nudge.x)
            let isReachableNudge = magnitude == 0
                || magnitude == NovaStationGameplayScript.accessibilityNudge
                || (NovaStationGameplayScript.minimumTouchNudge ... NovaStationGameplayScript.maximumTouchNudge)
                    .contains(magnitude)
            #expect(isReachableNudge)
        }
    }

    @Test("ordinary launcher scripts reach every mission objective mechanic")
    func ordinaryScriptsReachObjectiveMechanics() throws {
        let events = Set(MissionID.allCases.flatMap { MissionCatalog.definition(for: $0).objectiveEvents })
        for event in events.sorted() {
            var session = try startedSession()
            do {
                _ = try NovaStationGameplayScript.shoot(event, in: &session)
            } catch {
                Issue.record("\(event): \(error)")
            }
        }
    }

    @Test("ordinary launcher controls physically select and start the first mission")
    func ordinaryLauncherStartsMission() throws {
        var session = try GameSession()
        _ = try session.startNewGame()
        _ = try NovaStationGameplayScript.shoot(NovaStationTable.Event.missionSelect, in: &session)
        #expect(session.rules.selectedMission == .orbitalWake)
        _ = try NovaStationGameplayScript.shoot(NovaStationTable.Event.missionStart, in: &session)
        #expect(session.rules.missionState == .active(.orbitalWake))
        for eventName in MissionCatalog.definition(for: .orbitalWake).objectiveEvents {
            _ = try NovaStationGameplayScript.shoot(eventName, in: &session)
        }
        #expect(session.rules.missionState == .completed(.orbitalWake))
        #expect(session.rules.clearance == .dockKey)
    }

    @Test("a session has honest launch, playing, game over and fresh new-game phases")
    func lifecyclePhases() throws {
        var session = try GameSession()

        #expect(session.phase == .launch)
        #expect(session.snapshot.balls.isEmpty)

        let started = try session.startNewGame()
        #expect(started.phase == .playing)
        #expect(started.snapshot.balls.count == 1)
        #expect(started.rules.ballSaveTicksRemaining == GameRulesState.ballSaveDurationTicks)

        for _ in 0 ..< GameRulesState.regularBallCount {
            _ = session.process(steps: GameRulesState.ballSaveDurationTicks, events: [])
            let ballID = try #require(session.snapshot.balls.first?.id)
            _ = session.process(steps: 0, events: [GameEvent(name: NovaStationTable.Event.drain, ballID: ballID)])
        }
        #expect(session.phase == .gameOver)
        #expect(session.rules.isGameOver)
        #expect(session.snapshot.balls.isEmpty)

        let restarted = try session.startNewGame()
        #expect(restarted.phase == .playing)
        #expect(restarted.rules.score == 0)
        #expect(restarted.rules.ballsRemaining == 3)
        #expect(restarted.snapshot.balls.count == 1)
    }

    @Test("steps and each physical event mutate rules exactly once")
    func exactOnceEventConsumption() throws {
        var session = try startedSession()
        let initialSave = session.rules.ballSaveTicksRemaining

        let frame = session.process(
            steps: 4,
            events: [
                GameEvent(name: "bumper:bumper-orbit", ballID: 1),
                GameEvent(name: NovaStationTable.Event.bonus, ballID: 1),
                GameEvent(name: NovaStationTable.Event.scoreMultiplier, ballID: 1),
                GameEvent(name: NovaStationTable.Event.bonusMultiplier, ballID: 1),
                GameEvent(name: NovaStationTable.Event.stationPower, ballID: 1)
            ]
        )

        #expect(frame.rules.score == 16_000)
        #expect(frame.rules.bonusUnits == 1)
        #expect(frame.rules.scoreMultiplier == 2)
        #expect(frame.rules.bonusMultiplier == 2)
        #expect(frame.rules.ballSaveTicksRemaining == initialSave - 4)
        #expect(frame.effects.filter { if case .scoreAwarded = $0 { true } else { false } }.count == 5)
    }

    @Test("all 17 missions complete through physical shots across exact-clearance branch playthroughs")
    func allMissionsAndClearancesReachable() throws {
        for missionID in MissionID.allCases {
            var session = try startedSession()
            try advancePhysically(
                &session,
                to: MissionCatalog.definition(for: missionID).requiredClearance
            )
            try completePhysically(missionID, in: &session, acknowledge: false)

            #expect(session.rules.missionState == .completed(missionID))
            #expect(session.rules.clearance == MissionCatalog.definition(for: missionID).awardedClearance)
        }
    }

    @Test("advertised multiball and tilt states are reachable through production physics inputs")
    func advertisedSpecialStatesArePhysicallyReachable() throws {
        var multiball = try startedSession()
        try shoot(NovaStationTable.Event.multiball, in: &multiball)
        #expect(multiball.rules.ballsInPlay == 3)
        #expect(multiball.snapshot.balls.count == 3)

        var tilted = try startedSession()
        for _ in 0 ..< 5 {
            _ = tilted.step(PlayerInput(
                leftFlipperIsPressed: false,
                rightFlipperIsPressed: false,
                plungerPull: 0,
                nudge: Vector2(x: 1, y: 0)
            ))
        }
        #expect(tilted.rules.isTilted)
        #expect(tilted.physicsTiltState.isTilted)
    }

    @Test("station power is rechargeable and depletion fails an active mission")
    func stationPowerLifecycle() throws {
        var session = try startedSession()
        try NovaStationGameplayScript.startMission(in: &session)

        _ = session.process(
            steps: GameRulesState.stationPowerTicksPerUnit * GameRulesState.maximumStationPower,
            events: []
        )
        #expect(session.rules.stationPower == 0)
        #expect(session.rules.missionState == .failed(.orbitalWake))

        _ = try NovaStationGameplayScript.shoot(NovaStationTable.Event.stationPower, in: &session)
        #expect(session.rules.stationPower == GameRulesState.stationPowerRechargeUnits)
    }

    @Test("multiball creates three physical balls and drains remove them individually")
    func multiballAndIndividualDrains() throws {
        var session = try startedSession()
        let activated = session.process(
            steps: 0,
            events: [GameEvent(name: NovaStationTable.Event.multiball, ballID: 1)]
        )
        #expect(activated.rules.ballsInPlay == 3)
        #expect(activated.snapshot.balls.count == 3)
        #expect(Set(activated.snapshot.balls.map(\.id)).count == 3)

        let firstID = try #require(session.snapshot.balls.first?.id)
        _ = session.process(steps: 0, events: [GameEvent(name: NovaStationTable.Event.drain, ballID: firstID)])
        #expect(session.rules.ballsInPlay == 2)
        #expect(session.snapshot.balls.count == 2)
        #expect(!session.snapshot.balls.contains(where: { $0.id == firstID }))

        let secondID = try #require(session.snapshot.balls.first?.id)
        _ = session.process(steps: 0, events: [GameEvent(name: NovaStationTable.Event.drain, ballID: secondID)])
        #expect(session.rules.ballsInPlay == 1)
        #expect(session.snapshot.balls.count == 1)
    }

    @Test("ball save, extra ball, tilt reset and game over all act on physical balls")
    func ballLifecycleSystems() throws {
        var session = try startedSession()
        let savedBallID = try #require(session.snapshot.balls.first?.id)
        _ = session.process(steps: 0, events: [GameEvent(name: NovaStationTable.Event.drain, ballID: savedBallID)])
        #expect(session.rules.ballsRemaining == 3)
        #expect(session.snapshot.balls.count == 1)
        #expect(session.snapshot.balls.first?.id != savedBallID)

        _ = session.process(steps: 0, events: [GameEvent(name: NovaStationTable.Event.extraBall)])
        #expect(session.rules.extraBalls == 1)

        _ = session.process(steps: 0, events: [GameEvent(name: "tilt")])
        #expect(session.rules.isTilted)
        let tiltedID = try #require(session.snapshot.balls.first?.id)
        _ = session.process(steps: 0, events: [GameEvent(name: NovaStationTable.Event.drain, ballID: tiltedID)])
        #expect(!session.rules.isTilted)
        #expect(!session.physicsTiltState.isTilted)
        #expect(session.rules.extraBalls == 0)
        #expect(session.rules.ballsRemaining == 3)
    }

    @Test("normal simulation frames flow through the same session event reducer")
    func physicalSimulationIntegration() throws {
        let route = try #require(NovaStationTable.mechanicShotRoutes.first(where: {
            $0.eventName.hasPrefix("bumper:")
        }))
        var session = try GameSession(
            snapshot: SimulationSnapshot(
                tableVersion: NovaStationTable.version,
                elapsedTime: 0,
                balls: [BallState(id: 41, position: route.start, velocity: route.velocity)]
            ),
            rules: GameRulesState(),
            phase: .playing
        )
        let scoreBefore = session.rules.score
        var effects: [GameSessionEffect] = []
        for _ in 0 ..< route.maximumTicks {
            let frame = session.step(.idle)
            effects += frame.effects
            if session.rules.score > scoreBefore { break }
        }

        #expect(session.rules.score == scoreBefore + NovaStationTable.Score.bumper)
        #expect(effects.contains(.scoreAwarded(NovaStationTable.Score.bumper)))
    }

    @Test("session restore preserves rules and snapshot while clearing transient mechanics")
    func deterministicRestore() throws {
        var original = try startedSession()
        _ = original.process(steps: 37, events: [GameEvent(name: NovaStationTable.Event.bonus)])
        let snapshot = original.snapshot
        let rules = original.rules

        var restored = try GameSession()
        try restored.restore(snapshot: snapshot, rules: rules)

        #expect(restored.snapshot == snapshot)
        #expect(restored.rules == rules)
        #expect(restored.phase == .playing)
        #expect(restored.step(.idle) == original.step(.idle))
    }

    private func startedSession() throws -> GameSession {
        var session = try GameSession()
        _ = try session.startNewGame()
        return session
    }

    private func advancePhysically(
        _ session: inout GameSession,
        to required: ClearanceLevel?
    ) throws {
        let canonical: [MissionID] = [
            .orbitalWake, .relayBloom, .cargoDrift, .prismSurvey, .ionChoir,
            .duskCourier, .helixLatch, .polarVane
        ]
        guard let required else { return }
        for mission in canonical {
            if session.rules.clearance == required { return }
            try completePhysically(mission, in: &session, acknowledge: true)
        }
        #expect(session.rules.clearance == required)
    }

    private func completePhysically(
        _ missionID: MissionID,
        in session: inout GameSession,
        acknowledge: Bool
    ) throws {
        let definition = MissionCatalog.definition(for: missionID)
        var selectionAttempts = 0
        while session.rules.selectedMission != missionID {
            try shoot(NovaStationTable.Event.missionSelect, in: &session)
            selectionAttempts += 1
            guard selectionAttempts <= MissionID.allCases.count else {
                throw PhysicalMissionTestError.cannotSelect(missionID, session.rules.clearance)
            }
        }
        try shoot(NovaStationTable.Event.missionStart, in: &session)
        #expect(session.rules.missionState == .active(missionID))
        for event in definition.objectiveEvents {
            if session.rules.missionState == .completed(missionID) { break }
            _ = try NovaStationGameplayScript.shoot(event, in: &session)
        }
        #expect(session.rules.missionState == .completed(missionID))
        if acknowledge {
            try shoot(NovaStationTable.Event.missionAcknowledge, in: &session)
            #expect(session.rules.missionState == .idle)
        }
    }

    private func shoot(_ eventName: String, in session: inout GameSession) throws {
        _ = try NovaStationGameplayScript.shoot(eventName, in: &session)
    }
}

private enum PhysicalMissionTestError: Error {
    case cannotSelect(MissionID, ClearanceLevel?)
}
