import Foundation
import Testing
@testable import NovaStationCore

@Suite("NovaStationTableTests")
struct NovaStationTableTests {
    @Test("production mechanics share the authoritative 2048x1536 ImageGen guide anchors")
    func mechanicsMatchVisualGuideAnchors() throws {
        let table = NovaStationTable.definition
        #expect(TableVisualLayout.canvasWidth == 2_048)
        #expect(TableVisualLayout.canvasHeight == 1_536)
        #expect(TableVisualLayout.tablePixelWidth == 1_433.6)

        let expectedBumpers: [String: Vector2] = [
            "bumper-orbit": TableVisualLayout.bumpers[0].logicalPoint,
            "bumper-relay": TableVisualLayout.bumpers[1].logicalPoint,
            "bumper-core": TableVisualLayout.bumpers[2].logicalPoint
        ]
        for bumper in table.bumpers {
            let expected = try #require(expectedBumpers[bumper.id])
            #expect(bumper.collider.center.distance(to: expected) < 0.000_001)
        }
        #expect(table.flippers[0].pivot.distance(to: TableVisualLayout.leftFlipperPivot.logicalPoint) < 0.000_001)
        #expect(table.flippers[1].pivot.distance(to: TableVisualLayout.rightFlipperPivot.logicalPoint) < 0.000_001)
        #expect(table.plunger?.position.distance(to: TableVisualLayout.plunger.logicalPoint) ?? 1 < 0.000_001)

        for mechanic in NovaStationTable.mechanics {
            let actual = try #require(NovaStationTable.anchor(for: mechanic.elementKind, id: mechanic.elementID))
            #expect(actual.distance(to: mechanic.anchor) < 0.000_001,
                    "descriptor \(mechanic.id) must resolve to a real table element")
        }
    }

    @Test("the versioned production table carries every visible mechanical category")
    func completeMechanicalInventory() throws {
        let table = NovaStationTable.definition
        let mechanics = NovaStationTable.mechanics

        #expect(table.version == NovaStationTable.version)
        #expect(table.flippers.map(\.id) == ["flipper-left", "flipper-right"])
        #expect(table.bumpers.map(\.id) == ["bumper-orbit", "bumper-relay", "bumper-core"])
        #expect(table.plunger != nil)
        #expect(Set(mechanics.map(\.id)).count == mechanics.count)
        #expect(Set(mechanics.map(\.role)).isSuperset(of: [
            .rail, .arc, .ramp, .drain, .bumper, .targetBank, .missionLane,
            .portal, .bonus, .scoreMultiplier, .bonusMultiplier,
            .extraBall, .multiball, .stationPower
        ]))

        _ = try PinballSimulation(table: table)
    }

    @Test("all colliders and sensors stay inside the logical playfield while the drain remains open")
    func geometryBoundsAndOpenDrain() {
        let table = NovaStationTable.definition
        let allShapes = table.collisionShapes
            + table.bumpers.map { .circle($0.collider) }
            + table.targets.map { .segment($0.collider) }
            + table.sensors.map(\.shape)

        for shape in allShapes {
            for point in representativePoints(of: shape) {
                #expect(point.x >= 0 && point.x <= table.playfieldSize.x)
                #expect(point.y >= 0 && point.y <= table.playfieldSize.y)
            }
        }

        let bottomBlockingSegments = table.collisionShapes.compactMap { shape -> SegmentCollider? in
            guard case let .segment(segment) = shape,
                  segment.start.y <= NovaStationTable.drainY,
                  segment.end.y <= NovaStationTable.drainY
            else { return nil }
            return segment
        }
        #expect(bottomBlockingSegments.allSatisfy { segment in
            max(segment.start.x, segment.end.x) <= NovaStationTable.drainRange.lowerBound
                || min(segment.start.x, segment.end.x) >= NovaStationTable.drainRange.upperBound
        })
    }

    @Test("ordinary legal in-play shots reach every visible generic mechanic through GameSession.step")
    func everyGenericMechanicHasAnOrdinaryShot() throws {
        let routeEvents = Set(NovaStationTable.mechanicShotRoutes.map(\.eventName))
        let tableEvents = Set(NovaStationTable.mechanics.compactMap(\.eventName))
        #expect(routeEvents == tableEvents.subtracting([NovaStationTable.Event.drain]))

        for route in NovaStationTable.mechanicShotRoutes {
            var session = try GameSession()
            _ = try session.startNewGame()
            do {
                let frames = try NovaStationGameplayScript.shoot(route.eventName, in: &session)
                #expect(frames.contains { frame in
                    frame.events.contains(where: { $0.name == route.eventName })
                }, "ordinary app-control shot did not reach \(route.id)")
            } catch {
                Issue.record("ordinary app-control shot failed for \(route.id) [\(route.eventName)]: \(error); phase=\(session.phase), inputs=\(session.recording.inputs.count), balls=\(session.snapshot.balls)")
            }
        }
    }

    private func representativePoints(of shape: CollisionShape) -> [Vector2] {
        switch shape {
        case .segment(let segment):
            [segment.start, segment.end]
        case .circle(let circle):
            [
                Vector2(x: circle.center.x - circle.radius, y: circle.center.y),
                Vector2(x: circle.center.x + circle.radius, y: circle.center.y),
                Vector2(x: circle.center.x, y: circle.center.y - circle.radius),
                Vector2(x: circle.center.x, y: circle.center.y + circle.radius)
            ]
        case .arc(let arc):
            [
                arc.center + Vector2(x: cos(arc.startAngle), y: sin(arc.startAngle)) * arc.radius,
                arc.center + Vector2(x: cos(arc.endAngle), y: sin(arc.endAngle)) * arc.radius
            ]
        }
    }
}
