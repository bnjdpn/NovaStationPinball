import Foundation

public enum NovaStationGameplayScriptError: Error, Sendable, Equatable {
    case unavailableEvent(String)
    case shotDidNotReach(String)
    case ballDidNotReturn
    case gameEnded
}

/// Deterministic ordinary-control scripts shared by acceptance tests and media
/// capture. They never restore state or inject physics/rules events: all state
/// changes come from `GameSession.startNewGame()` and `GameSession.step(_:)`.
public enum NovaStationGameplayScript {
    /// Mirrors TouchInterpreter's accepted 4...12% horizontal swipe divided
    /// by its 10% normalization distance. The app's accessibility nudge (0.35)
    /// is also legal, but automated shots use only the touch interval.
    public static let minimumTouchNudge = 0.4
    public static let maximumTouchNudge = 1.2
    public static let accessibilityNudge = 0.35

    public static func startMission(in session: inout GameSession) throws {
        _ = try shoot(NovaStationTable.Event.missionSelect, in: &session)
        _ = try shoot(NovaStationTable.Event.missionStart, in: &session)
    }

    public static func completeOrbitalWake(in session: inout GameSession) throws {
        try startMission(in: &session)
        for event in MissionCatalog.definition(for: .orbitalWake).objectiveEvents {
            _ = try shoot(event, in: &session)
        }
    }

    public static func tilt(in session: inout GameSession) {
        for _ in 0 ..< 5 {
            _ = session.step(PlayerInput(
                leftFlipperIsPressed: false,
                rightFlipperIsPressed: false,
                plungerPull: 0,
                nudge: Vector2(x: 1, y: 0)
            ))
        }
    }

    public static func playUntilGameOver(in session: inout GameSession) throws {
        while session.phase == .playing {
            for _ in 0 ..< GameRulesState.ballSaveDurationTicks { _ = session.step(.idle) }
            _ = session.step(PlayerInput(
                leftFlipperIsPressed: false,
                rightFlipperIsPressed: false,
                plungerPull: 1,
                nudge: .zero
            ))
            _ = session.step(.idle)
            do {
                try returnBallToLauncher(in: &session)
            } catch NovaStationGameplayScriptError.gameEnded {
                return
            }
        }
    }

    public static func startIfNeeded(_ session: inout GameSession) throws {
        if session.phase == .launch {
            _ = try session.startNewGame()
        }
    }

    @discardableResult
    public static func shoot(
        _ eventName: String,
        in session: inout GameSession,
        maximumTicks: Int = 4_800
    ) throws -> [GameSessionFrame] {
        try startIfNeeded(&session)
        guard let mechanic = NovaStationTable.mechanics.first(where: { $0.eventName == eventName }) else {
            throw NovaStationGameplayScriptError.unavailableEvent(eventName)
        }
        try returnBallToLauncher(in: &session, maximumTicks: maximumTicks)

        var frames: [GameSessionFrame] = []
        let isShooterLaneCommand = eventName == NovaStationTable.Event.missionSelect
            || eventName == NovaStationTable.Event.missionStart
            || eventName == NovaStationTable.Event.missionAcknowledge
        let pull: Double
        switch eventName {
        case NovaStationTable.Event.missionSelect: pull = 0.35
        case NovaStationTable.Event.missionAcknowledge: pull = 0.55
        default: pull = 1.0
        }
        frames.append(session.step(PlayerInput(
            leftFlipperIsPressed: false,
            rightFlipperIsPressed: false,
            plungerPull: pull,
            nudge: .zero
        )))
        frames.append(session.step(.idle))
        var closestDistance = Double.greatestFiniteMagnitude
        let openingNudge = openingNudge(for: eventName)
        var didAim = openingNudge != nil

        for tick in 0 ..< maximumTicks {
            guard session.phase == .playing else { throw NovaStationGameplayScriptError.gameEnded }
            let ball = session.snapshot.balls.first
            if let ball {
                closestDistance = min(closestDistance, ball.position.distance(to: mechanic.anchor))
            }
            let nudge: Vector2
            if tick == 0, let openingNudge {
                nudge = Vector2(x: openingNudge, y: 0)
            } else if let ball, !isShooterLaneCommand, openingNudge == nil,
               (!didAim && ball.position.y >= 0.52)
                || (didAim && tick > 0 && tick % 60 == 0 && ball.position.y < mechanic.anchor.y + 0.20) {
                let verticalDistance = max(0.01, mechanic.anchor.y - ball.position.y)
                let gravity = abs(NovaStationTable.definition.gravity.y)
                let discriminant = max(0.01, ball.velocity.y * ball.velocity.y - 2 * gravity * verticalDistance)
                let flightTime = max(0.08, (ball.velocity.y - sqrt(discriminant)) / gravity)
                let lead = didAim ? 0.8 : 1.25
                let desiredVelocity = min(1.8, max(-1.8, (mechanic.anchor.x - ball.position.x) / flightTime * lead))
                let correction = (desiredVelocity - ball.velocity.x) / NovaStationTable.definition.nudgeImpulseScale
                nudge = reachableHorizontalNudge(
                    correction,
                    usesAccessibilityMinimum: eventName != NovaStationTable.Event.returnCenter
                )
                didAim = true
            } else {
                nudge = .zero
            }
            let frame = session.step(PlayerInput(
                leftFlipperIsPressed: false,
                rightFlipperIsPressed: false,
                plungerPull: 0,
                nudge: nudge
            ))
            frames.append(frame)
            if frame.events.contains(where: { $0.name == eventName }) {
                return frames
            }
        }
        throw NovaStationGameplayScriptError.shotDidNotReach(eventName)
    }

    public static func returnBallToLauncher(
        in session: inout GameSession,
        maximumTicks: Int = 4_800
    ) throws {
        let launch = NovaStationTable.launchPosition
        for _ in 0 ..< maximumTicks {
            guard session.phase == .playing else { throw NovaStationGameplayScriptError.gameEnded }
            if let ball = session.snapshot.balls.first,
               ball.position.distance(to: launch) <= 0.15,
               ball.velocity.length <= 0.15 {
                return
            }
            guard session.snapshot.balls.first != nil else { continue }
            _ = session.step(PlayerInput(
                leftFlipperIsPressed: false,
                rightFlipperIsPressed: false,
                plungerPull: 0,
                nudge: .zero
            ))
        }
        throw NovaStationGameplayScriptError.ballDidNotReturn
    }

    /// Some visible shots use the launch-lane rebound instead of a direct
    /// ballistic line. These are ordinary horizontal swipes made immediately
    /// after releasing the plunger, expressed in the same normalized domain as
    /// `TouchInterpreter`.
    private static func openingNudge(for eventName: String) -> Double? {
        switch eventName {
        case "target:mission-select", NovaStationTable.Event.multiball,
             NovaStationTable.Event.stationPower:
            -1.0
        case "target:mission-start", "target:mission-acknowledge":
            minimumTouchNudge
        case NovaStationTable.Event.bonusMultiplier:
            -0.75
        default:
            nil
        }
    }

    private static func reachableHorizontalNudge(
        _ requestedX: Double,
        usesAccessibilityMinimum: Bool = true
    ) -> Vector2 {
        guard requestedX.isFinite, abs(requestedX) >= 0.01 else { return .zero }
        let magnitude = abs(requestedX) < minimumTouchNudge
            ? (usesAccessibilityMinimum ? accessibilityNudge : minimumTouchNudge)
            : min(maximumTouchNudge, abs(requestedX))
        return Vector2(x: requestedX < 0 ? -magnitude : magnitude, y: 0)
    }
}
