import Foundation

/// One Workshop shot drill: the same serve, the same table, the same target,
/// as many times as the player wants. Every drill starts from
/// `ShotDrillCatalog.makeSession()`, which is bit-identical on every attempt,
/// so the only variable is the player's own aim.
public struct ShotDrill: Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    /// Physical event the drill is trying to produce, straight from the table
    /// definition — no drill-specific geometry is stored anywhere.
    public let eventName: String
    /// Attempt budget in 240 Hz ticks.
    public let maximumTicks: Int

    public init(id: String, eventName: String, maximumTicks: Int) {
        self.id = id
        self.eventName = eventName
        self.maximumTicks = maximumTicks
    }

    /// Attempt budget in seconds, for display.
    public var maximumSeconds: Int {
        Int((Double(maximumTicks) / 240.0).rounded())
    }
}

public enum ShotDrillCatalogError: Error, Sendable, Equatable {
    case unknownMechanic(String)
}

/// The fourteen shipped drills. Each one targets a mechanic that the table
/// itself declares (`NovaStationTable.mechanicShotRoutes`), so the catalog can
/// never drift away from the playfield.
public enum ShotDrillCatalog {
    /// Twenty simulated seconds per attempt, the same budget the acceptance
    /// scripts use to reach any mechanic from the serve.
    public static let attemptTicks = 4_800

    public static let drills: [ShotDrill] = [
        drill("ramp-left", NovaStationTable.Event.rampLeft),
        drill("ramp-right", NovaStationTable.Event.rampRight),
        drill("return-left", NovaStationTable.Event.returnLeft),
        drill("return-center", NovaStationTable.Event.returnCenter),
        drill("return-right", NovaStationTable.Event.returnRight),
        drill("portal", NovaStationTable.Event.portal),
        drill("target-bank", NovaStationTable.Event.targetBank),
        drill("bonus-bank", NovaStationTable.Event.bonus),
        drill("score-multiplier", NovaStationTable.Event.scoreMultiplier),
        drill("bonus-multiplier", NovaStationTable.Event.bonusMultiplier),
        drill("extra-ball", NovaStationTable.Event.extraBall),
        drill("multiball", NovaStationTable.Event.multiball),
        drill("station-power", NovaStationTable.Event.stationPower),
        drill("rollover-center", "sensor:rollover-center")
    ]

    public static func drill(id: String) -> ShotDrill? {
        drills.first { $0.id == id }
    }

    /// The identical serve every attempt of every drill starts from: a brand
    /// new game, ball parked on the launcher, flagged assisted so a drill can
    /// never leak into the ranked scores.
    public static func makeSession() throws -> GameSession {
        var session = try GameSession()
        _ = try session.startNewGame()
        session.markAssisted()
        return session
    }

    private static func drill(_ id: String, _ eventName: String) -> ShotDrill {
        ShotDrill(id: id, eventName: eventName, maximumTicks: attemptTicks)
    }
}

/// Pure reducer deciding whether an attempt is still running, won or lost.
/// It only reads frames the ordinary game loop already produces.
public struct ShotDrillEvaluator: Sendable, Equatable {
    public enum Outcome: String, Sendable, Equatable, Codable {
        case running
        case succeeded
        case failed
    }

    public let drill: ShotDrill
    public private(set) var outcome: Outcome = .running
    public private(set) var ticksElapsed = 0

    public init(drill: ShotDrill) {
        self.drill = drill
    }

    public var remainingTicks: Int {
        max(0, drill.maximumTicks - ticksElapsed)
    }

    @discardableResult
    public mutating func consume(_ frame: GameSessionFrame, steps: Int) -> Outcome {
        guard outcome == .running else { return outcome }
        ticksElapsed += max(0, steps)

        if frame.events.contains(where: { $0.name == drill.eventName }) {
            outcome = .succeeded
            return outcome
        }

        // A drain re-serves the ball at the launcher, which is exactly the
        // drill serve, so it only costs time. An attempt is lost when the
        // player tilts, runs out of balls, or runs out of budget.
        let runEnded = frame.effects.contains { effect in
            switch effect {
            case .tilt, .gameOver: true
            default: false
            }
        }
        if runEnded || ticksElapsed >= drill.maximumTicks {
            outcome = .failed
        }
        return outcome
    }
}
