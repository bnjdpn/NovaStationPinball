import Foundation

public enum TableMechanicRole: String, CaseIterable, Sendable, Codable, Hashable {
    case rail, arc, ramp, drain, bumper, targetBank, missionLane, portal
    case bonus, scoreMultiplier, bonusMultiplier, extraBall, multiball, stationPower
}

public enum TableElementKind: String, Sendable, Codable, Equatable {
    case collisionShape, flipper, plunger, bumper, target, sensor
}

public struct TableMechanicDescriptor: Sendable, Codable, Equatable {
    public let id: String
    public let role: TableMechanicRole
    public let elementKind: TableElementKind
    public let elementID: String
    public let anchor: Vector2
    public let eventName: String?

    public init(
        id: String,
        role: TableMechanicRole,
        elementKind: TableElementKind,
        elementID: String,
        anchor: Vector2,
        eventName: String? = nil
    ) {
        self.id = id
        self.role = role
        self.elementKind = elementKind
        self.elementID = elementID
        self.anchor = anchor
        self.eventName = eventName
    }
}

public struct MechanicShotRoute: Sendable, Codable, Equatable {
    public let id: String
    public let eventName: String
    public let start: Vector2
    public let velocity: Vector2
    public let maximumTicks: Int

    public init(id: String, eventName: String, start: Vector2, velocity: Vector2, maximumTicks: Int = 180) {
        self.id = id
        self.eventName = eventName
        self.start = start
        self.velocity = velocity
        self.maximumTicks = maximumTicks
    }
}

/// Production table geometry. Every interactive anchor comes from
/// `TableVisualLayout`, which is the 2048×1536 ImageGen/greybox contract.
public enum NovaStationTable {
    public static let version = 721
    public static let launchPosition = TableVisualLayout.plunger.logicalPoint
    public static let drainY = TableVisualLayout.drain.logicalPoint.y
    public static let drainRange = (TableVisualLayout.drain.logicalPoint.x - 0.26)
        ... (TableVisualLayout.drain.logicalPoint.x + 0.26)

    public enum Event {
        public static let missionSelect = "sensor:mission-select"
        public static let missionStart = "sensor:mission-start"
        public static let missionAcknowledge = "sensor:mission-acknowledge"
        public static let targetBank = "target:target-bank"
        public static let portal = "sensor:portal"
        public static let rampLeft = "sensor:ramp-left"
        public static let rampRight = "sensor:ramp-right"
        public static let returnLeft = "sensor:return-left"
        public static let returnCenter = "sensor:return-center"
        public static let returnRight = "sensor:return-right"
        public static let rolloverLeft = "sensor:rollover-left"
        public static let rolloverCenter = "sensor:rollover-center"
        public static let rolloverRight = "sensor:rollover-right"
        public static let outerLeft = "sensor:outer-left"
        public static let outerRight = "sensor:outer-right"
        public static let bonus = "sensor:bonus-bank"
        public static let scoreMultiplier = "sensor:score-multiplier"
        public static let bonusMultiplier = "sensor:bonus-multiplier"
        public static let extraBall = "sensor:extra-ball"
        public static let multiball = "sensor:multiball"
        public static let stationPower = "sensor:station-power"
        public static let drain = "sensor:drain"
    }

    public enum Score {
        public static let bumper = 1_000
        public static let target = 2_500
        public static let lane = 5_000
    }

    private static let guideTargets = TableVisualLayout.targetBank.map { anchor in
        TargetDefinition(
            id: anchor.id,
            collider: SegmentCollider(
                start: anchor.logicalPoint + Vector2(x: -0.026, y: 0),
                end: anchor.logicalPoint + Vector2(x: 0.026, y: 0),
                radius: 0.014,
                restitution: 0.25
            )
        )
    }

    private static let guideSensors = TableVisualLayout.genericSensors.map { anchor in
        let radius: Double
        switch anchor.id {
        case "portal": radius = 0.052
        case "drain": radius = 0.008
        default: radius = 0.024
        }
        if anchor.id == "drain" {
            return SensorDefinition(
                id: anchor.id,
                shape: .segment(SegmentCollider(
                    start: Vector2(x: drainRange.lowerBound, y: anchor.logicalPoint.y),
                    end: Vector2(x: drainRange.upperBound, y: anchor.logicalPoint.y),
                    radius: radius,
                    restitution: 0
                ))
            )
        }
        if ["ramp-left", "ramp-right", "rollover-right"].contains(anchor.id) {
            let halfLength = anchor.id == "rollover-right" ? 0.20 : 0.30
            return SensorDefinition(
                id: anchor.id,
                shape: .segment(SegmentCollider(
                    start: anchor.logicalPoint + Vector2(x: 0, y: -halfLength),
                    end: anchor.logicalPoint + Vector2(x: 0, y: halfLength),
                    radius: anchor.id == "ramp-left" ? 0.15 : 0.024,
                    restitution: 0
                ))
            )
        }
        return SensorDefinition(
            id: anchor.id,
            shape: .circle(CircleCollider(center: anchor.logicalPoint, radius: radius, restitution: 0))
        )
    }

    public static let definition = TableDefinition(
        version: version,
        playfieldSize: Vector2(x: 1, y: 2),
        gravity: Vector2(x: 0, y: -1.2),
        ballRadius: 0.025,
        collisionShapes: [
            .segment(SegmentCollider(start: Vector2(x: 0.04, y: drainY), end: Vector2(x: 0.04, y: 1.72), radius: 0.012, restitution: 0.82)),
            // The launch centre is the exact 1,342.6 px guide anchor. This wall
            // leaves one ball radius inside the 70% table safe edge.
            .segment(SegmentCollider(start: Vector2(x: 0.975, y: drainY), end: Vector2(x: 0.975, y: 1.72), radius: 0.012, restitution: 0.82)),
            .arc(ArcCollider(center: Vector2(x: 0.50, y: 1.52), radius: 0.46, startAngle: 0, endAngle: .pi, thickness: 0.024, restitution: 0.82)),
            .segment(SegmentCollider(start: Vector2(x: 0.04, y: drainY), end: Vector2(x: drainRange.lowerBound, y: drainY), radius: 0.012, restitution: 0.75)),
            .segment(SegmentCollider(start: Vector2(x: drainRange.upperBound, y: drainY), end: Vector2(x: 0.96, y: drainY), radius: 0.012, restitution: 0.75)),
            .segment(SegmentCollider(start: Vector2(x: 0.16, y: 0.24), end: Vector2(x: 0.27, y: 0.40), radius: 0.014, restitution: 0.9)),
            .segment(SegmentCollider(start: Vector2(x: 0.84, y: 0.24), end: Vector2(x: 0.73, y: 0.40), radius: 0.014, restitution: 0.9)),
            .segment(SegmentCollider(start: Vector2(x: 0.75, y: 1.00), end: Vector2(x: 0.82, y: 1.50), radius: 0.010, restitution: 0.78)),
            .segment(SegmentCollider(start: Vector2(x: 0.88, y: 1.00), end: Vector2(x: 0.89, y: 1.48), radius: 0.010, restitution: 0.78)),
            .arc(ArcCollider(center: TableVisualLayout.portal.logicalPoint, radius: 0.12, startAngle: .pi * 0.08, endAngle: .pi * 0.92, thickness: 0.014, restitution: 0.8))
        ],
        flippers: [
            FlipperDefinition(id: "flipper-left", control: .left, pivot: TableVisualLayout.leftFlipperPivot.logicalPoint, length: 0.18, radius: 0.025, restAngle: 0.15, activeAngle: 0.60, angularSpeed: 16, impulseScale: 1),
            FlipperDefinition(id: "flipper-right", control: .right, pivot: TableVisualLayout.rightFlipperPivot.logicalPoint, length: 0.18, radius: 0.025, restAngle: .pi - 0.15, activeAngle: .pi - 0.60, angularSpeed: 16, impulseScale: 1)
        ],
        plunger: PlungerDefinition(position: launchPosition, launchRadius: 0.15, launchDirection: Vector2(x: 0, y: 1), maximumImpulse: 3),
        bumpers: TableVisualLayout.bumpers.map {
            BumperDefinition(id: $0.id, collider: CircleCollider(center: $0.logicalPoint, radius: 0.072, restitution: 0.86), impulse: 0.5)
        },
        targets: guideTargets,
        sensors: guideSensors + [
            SensorDefinition(
                id: "mission-select",
                shape: .segment(SegmentCollider(
                    start: Vector2(x: launchPosition.x - 0.035, y: 0.48),
                    end: Vector2(x: launchPosition.x + 0.035, y: 0.48),
                    radius: 0.006,
                    restitution: 0
                )),
                crossingDirection: .upward,
                maximumSpeed: 1.40
            ),
            SensorDefinition(
                id: "mission-start",
                shape: .segment(SegmentCollider(
                    start: Vector2(x: launchPosition.x - 0.035, y: 0.68),
                    end: Vector2(x: launchPosition.x + 0.035, y: 0.68),
                    radius: 0.006,
                    restitution: 0
                )),
                crossingDirection: .upward,
                minimumSpeed: 1.50
            ),
            SensorDefinition(
                id: "mission-acknowledge",
                shape: .segment(SegmentCollider(
                    start: Vector2(x: launchPosition.x - 0.035, y: 0.55),
                    end: Vector2(x: launchPosition.x + 0.035, y: 0.55),
                    radius: 0.006,
                    restitution: 0
                )),
                crossingDirection: .upward,
                minimumSpeed: 1.35,
                maximumSpeed: 1.75
            ),
            SensorDefinition(
                id: "drain-left-outlane",
                shape: .segment(SegmentCollider(
                    start: Vector2(x: 0.04, y: 0.55),
                    end: Vector2(x: 0.50, y: 0.55),
                    radius: 0.006,
                    restitution: 0
                )),
                eventName: Event.drain,
                crossingDirection: .downward
            ),
            SensorDefinition(
                id: "drain-right-outlane",
                shape: .segment(SegmentCollider(
                    start: Vector2(x: 0.50, y: 0.55),
                    end: Vector2(x: 0.975, y: 0.55),
                    radius: 0.006,
                    restitution: 0
                )),
                eventName: Event.drain,
                crossingDirection: .downward
            )
        ],
        linearFriction: 0.02,
        nudgeImpulseScale: 1.5,
        tilt: TiltDefinition(threshold: 4, decayPerSecond: 4)
    )

    public static let mechanics: [TableMechanicDescriptor] = {
        var values: [TableMechanicDescriptor] = [
            descriptor("left-rail", .rail, .collisionShape, "0", representativeAnchor(definition.collisionShapes[0])),
            descriptor("upper-orbit", .arc, .collisionShape, "2", representativeAnchor(definition.collisionShapes[2])),
            descriptor("transit-ramp", .ramp, .collisionShape, "7", representativeAnchor(definition.collisionShapes[7])),
            descriptor("flipper-left", .missionLane, .flipper, "flipper-left", TableVisualLayout.leftFlipperPivot.logicalPoint),
            descriptor("flipper-right", .missionLane, .flipper, "flipper-right", TableVisualLayout.rightFlipperPivot.logicalPoint),
            descriptor("plunger", .missionLane, .plunger, "plunger", launchPosition)
        ]
        values += TableVisualLayout.bumpers.map {
            descriptor($0.id, .bumper, .bumper, $0.id, $0.logicalPoint, "bumper:\($0.id)")
        }
        values += TableVisualLayout.targetBank.map { anchor in
            let event = "target:\(anchor.id)"
            return descriptor(anchor.id, .targetBank, .target, anchor.id, anchor.logicalPoint, event)
        }
        values += [
            descriptor(
                "mission-select-lane", .missionLane, .sensor, "mission-select",
                TableVisualLayout.missionSelectLane.logicalPoint, Event.missionSelect
            ),
            descriptor(
                "mission-start-lane", .missionLane, .sensor, "mission-start",
                TableVisualLayout.missionStartLane.logicalPoint, Event.missionStart
            ),
            descriptor(
                "mission-acknowledge-lane", .missionLane, .sensor, "mission-acknowledge",
                TableVisualLayout.missionAcknowledgeLane.logicalPoint, Event.missionAcknowledge
            )
        ]
        let roles: [String: TableMechanicRole] = [
            "portal": .portal, "ramp-left": .ramp, "ramp-right": .ramp,
            "bonus-bank": .bonus, "score-multiplier": .scoreMultiplier,
            "bonus-multiplier": .bonusMultiplier, "extra-ball": .extraBall,
            "multiball": .multiball, "station-power": .stationPower,
            "drain": .drain
        ]
        values += TableVisualLayout.genericSensors.map { anchor in
            descriptor(
                anchor.id,
                roles[anchor.id] ?? .missionLane,
                .sensor,
                anchor.id,
                anchor.logicalPoint,
                "sensor:\(anchor.id)"
            )
        }
        return values
    }()

    public static let mechanicShotRoutes: [MechanicShotRoute] = {
        let interactive = mechanics.filter { descriptor in
            descriptor.eventName != nil && descriptor.role != .drain
        }
        return interactive.map { descriptor in
            let target = descriptor.anchor
            let start: Vector2
            let velocity: Vector2
            switch descriptor.elementKind {
            case .target:
                start = target + Vector2(x: 0, y: 0.18)
                velocity = Vector2(x: 0, y: -1.6)
            case .sensor:
                if descriptor.id == "rollover-left" {
                    start = target + Vector2(x: 0, y: -0.22)
                    velocity = Vector2(x: 0, y: 1.6)
                } else if descriptor.id == "return-right" {
                    start = target + Vector2(x: -0.18, y: 0)
                    velocity = Vector2(x: 1.4, y: 0)
                } else if descriptor.id == "rollover-right" {
                    start = target + Vector2(x: -0.16, y: 0)
                    velocity = Vector2(x: 1.2, y: 0)
                } else if descriptor.id == "ramp-right" {
                    start = target + Vector2(x: -0.02, y: -0.22)
                    velocity = Vector2(x: 0.15, y: 1.6)
                } else if descriptor.id == "outer-right" {
                    start = target + Vector2(x: -0.017, y: -0.22)
                    velocity = Vector2(x: 0.12, y: 1.6)
                } else if descriptor.id == "multiball" {
                    start = target + Vector2(x: 0, y: 0.22)
                    velocity = Vector2(x: 0, y: -1.6)
                } else {
                    let shootFromRight = target.x < 0.24
                    start = target + Vector2(x: shootFromRight ? 0.22 : -0.22, y: 0)
                    velocity = Vector2(x: shootFromRight ? -1.6 : 1.6, y: 0)
                }
            case .bumper:
                start = target + Vector2(x: 0, y: -0.22)
                velocity = Vector2(x: 0, y: 1.6)
            case .collisionShape, .flipper, .plunger:
                preconditionFailure("non-event mechanic cannot create a shot route")
            }
            return MechanicShotRoute(
                id: descriptor.id,
                eventName: descriptor.eventName!,
                start: start,
                velocity: velocity
            )
        }
    }()

    public static func anchor(for kind: TableElementKind, id: String) -> Vector2? {
        switch kind {
        case .collisionShape:
            guard let index = Int(id), definition.collisionShapes.indices.contains(index) else { return nil }
            return representativeAnchor(definition.collisionShapes[index])
        case .flipper:
            return definition.flippers.first(where: { $0.id == id })?.pivot
        case .plunger:
            return definition.plunger?.position
        case .bumper:
            return definition.bumpers.first(where: { $0.id == id })?.collider.center
        case .target:
            guard let target = definition.targets.first(where: { $0.id == id }) else { return nil }
            return (target.collider.start + target.collider.end) / 2
        case .sensor:
            guard let sensor = definition.sensors.first(where: { $0.id == id }) else { return nil }
            return representativeAnchor(sensor.shape)
        }
    }

    private static func descriptor(
        _ id: String,
        _ role: TableMechanicRole,
        _ kind: TableElementKind,
        _ elementID: String,
        _ anchor: Vector2,
        _ event: String? = nil
    ) -> TableMechanicDescriptor {
        TableMechanicDescriptor(id: id, role: role, elementKind: kind, elementID: elementID, anchor: anchor, eventName: event)
    }

    private static func representativeAnchor(_ shape: CollisionShape) -> Vector2 {
        switch shape {
        case .segment(let segment): (segment.start + segment.end) / 2
        case .circle(let circle): circle.center
        case .arc(let arc): arc.center + Vector2(x: cos((arc.startAngle + arc.endAngle) / 2), y: sin((arc.startAngle + arc.endAngle) / 2)) * arc.radius
        }
    }
}
