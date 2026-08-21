import Foundation
import Testing
@testable import NovaStationCore

@Suite("ShotDrillCatalogTests")
struct ShotDrillCatalogTests {
    @Test("the shipped catalog is fourteen unique drills on real table mechanics")
    func catalogIsGroundedInTheTable() {
        let drills = ShotDrillCatalog.drills
        let tableEvents = Set(NovaStationTable.mechanicShotRoutes.map(\.eventName))

        #expect(drills.count == 14)
        #expect(Set(drills.map(\.id)).count == drills.count)
        #expect(Set(drills.map(\.eventName)).count == drills.count)
        for drill in drills {
            #expect(tableEvents.contains(drill.eventName), "drill \(drill.id) targets no real mechanic")
            #expect(drill.maximumTicks > 0)
        }
    }

    @Test("every drill serves a bit-identical assisted session")
    func serveIsDeterministicAndAssisted() throws {
        let first = try ShotDrillCatalog.makeSession()
        let second = try ShotDrillCatalog.makeSession()

        #expect(first.sessionState == second.sessionState)
        #expect(first.isAssisted)
        #expect(second.isAssisted)
        #expect(first.snapshot.balls.count == 1)
        #expect(first.phase == .playing)
    }

    @Test("every shipped drill is winnable with ordinary app controls")
    func everyDrillIsWinnable() throws {
        for drill in ShotDrillCatalog.drills {
            var session = try ShotDrillCatalog.makeSession()
            var evaluator = ShotDrillEvaluator(drill: drill)
            do {
                let frames = try NovaStationGameplayScript.shoot(
                    drill.eventName,
                    in: &session,
                    maximumTicks: drill.maximumTicks
                )
                for frame in frames {
                    evaluator.consume(frame, steps: 1)
                }
                #expect(
                    evaluator.outcome == .succeeded,
                    "drill \(drill.id) ended \(evaluator.outcome.rawValue) instead of succeeded"
                )
            } catch {
                Issue.record("drill \(drill.id) [\(drill.eventName)] is not winnable: \(error)")
            }
        }
    }

    @Test("an attempt fails on a tilt, a game over or the tick budget, never on a re-served drain")
    func failureConditionsAreExplicit() throws {
        let drill = try #require(ShotDrillCatalog.drill(id: "ramp-left"))
        let session = try ShotDrillCatalog.makeSession()
        let idleFrame = GameSessionFrame(
            snapshot: session.snapshot,
            rules: session.rules,
            phase: .playing,
            events: [],
            effects: []
        )

        var drained = ShotDrillEvaluator(drill: drill)
        #expect(drained.consume(
            GameSessionFrame(
                snapshot: session.snapshot,
                rules: session.rules,
                phase: .playing,
                events: [],
                effects: [.ballDrained(1), .ballSpawned(2)]
            ),
            steps: 1
        ) == .running)

        var ended = ShotDrillEvaluator(drill: drill)
        #expect(ended.consume(
            GameSessionFrame(
                snapshot: session.snapshot,
                rules: session.rules,
                phase: .gameOver,
                events: [],
                effects: [.gameOver(0)]
            ),
            steps: 1
        ) == .failed)

        var tilted = ShotDrillEvaluator(drill: drill)
        #expect(tilted.consume(
            GameSessionFrame(
                snapshot: session.snapshot,
                rules: session.rules,
                phase: .playing,
                events: [],
                effects: [.tilt]
            ),
            steps: 1
        ) == .failed)

        var expired = ShotDrillEvaluator(drill: drill)
        #expect(expired.consume(idleFrame, steps: drill.maximumTicks) == .failed)

        var won = ShotDrillEvaluator(drill: drill)
        #expect(won.consume(
            GameSessionFrame(
                snapshot: session.snapshot,
                rules: session.rules,
                phase: .playing,
                events: [GameEvent(name: drill.eventName)],
                effects: []
            ),
            steps: 1
        ) == .succeeded)
        // A settled attempt never changes outcome again.
        #expect(won.consume(idleFrame, steps: drill.maximumTicks) == .succeeded)
    }

    @Test("drill progress counts attempts, success rate and best streak")
    func progressAccounting() throws {
        var progress = DrillProgress()

        progress.record(drillID: "ramp-left", succeeded: true)
        progress.record(drillID: "ramp-left", succeeded: true)
        progress.record(drillID: "ramp-left", succeeded: false)
        progress.record(drillID: "ramp-left", succeeded: true)

        let entry = progress.entry(for: "ramp-left")
        #expect(entry.attempts == 4)
        #expect(entry.successes == 3)
        #expect(entry.bestStreak == 2)
        #expect(entry.currentStreak == 1)
        #expect(abs(entry.successRate - 0.75) < 0.000_001)
        #expect(progress.entry(for: "portal").attempts == 0)
        #expect(progress.entry(for: "portal").successRate == 0)

        let data = try JSONEncoder().encode(progress)
        #expect(String(decoding: data, as: UTF8.self).contains("\"formatVersion\":1"))
        #expect(try JSONDecoder().decode(DrillProgress.self, from: data) == progress)
    }
}
