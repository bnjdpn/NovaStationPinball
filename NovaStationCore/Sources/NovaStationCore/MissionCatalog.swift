public enum ClearanceLevel: String, CaseIterable, Sendable, Codable, Equatable {
    case dockKey
    case relayKey
    case cargoKey
    case prismKey
    case ionKey
    case transitKey
    case shieldKey
    case commandKey
    case novaKey

    public var rank: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

public enum MissionID: String, CaseIterable, Sendable, Codable, Equatable {
    case orbitalWake
    case relayBloom
    case cargoDrift
    case prismSurvey
    case ionChoir
    case duskCourier
    case helixLatch
    case polarVane
    case novaCrown
    case harborEmber
    case echoSpire
    case lanternRoute
    case riftContainment
    case auroraQuarantine
    case vaultSignal
    case phaseTide
    case stationTempest
}

public enum MissionAbortTrigger: String, Sendable, Codable, Equatable {
    case stationPowerDepleted
    case signalInterlock
}

public enum MissionTiming: Sendable, Codable, Equatable {
    case resourceDriven(abortTrigger: MissionAbortTrigger)
    case fixedWindow(baselineTicks: Int, novaTicks: Int)

    public static let ticksPerSecond = 240

    public static func ticks(seconds: Int) -> Int {
        max(0, seconds) * ticksPerSecond
    }

    public var baselineTicks: Int? {
        guard case let .fixedWindow(baselineTicks, _) = self else { return nil }
        return baselineTicks
    }

    public var abortTrigger: MissionAbortTrigger? {
        guard case let .resourceDriven(abortTrigger) = self else { return nil }
        return abortTrigger
    }

    public var novaTicks: Int? {
        guard case let .fixedWindow(_, novaTicks) = self else { return nil }
        return novaTicks
    }

    public var deltaTicks: Int? {
        guard let baselineTicks, let novaTicks, baselineTicks > 0 else { return nil }
        return novaTicks - baselineTicks
    }

    public var deltaPercentage: Double? {
        guard let baselineTicks, let deltaTicks, baselineTicks > 0 else { return nil }
        return Double(deltaTicks) * 100 / Double(baselineTicks)
    }

    public var isWithinFivePercent: Bool? {
        guard let deltaPercentage else { return nil }
        return abs(deltaPercentage) <= 5
    }
}

public struct MissionDefinition: Sendable, Codable, Equatable {
    public let id: MissionID
    public let title: String
    public let requiredClearance: ClearanceLevel?
    public let awardedClearance: ClearanceLevel
    public let completionTrigger: String
    public let startScore: Int
    public let completionScore: Int
    public let timing: MissionTiming

    /// Ordered visible table events required to complete the active mission.
    /// `completionTrigger` is internal and is emitted only after this objective.
    public var objectiveEvents: [String] {
        MissionCatalog.objectiveEvents(for: id)
    }

    public init(
        id: MissionID,
        title: String,
        requiredClearance: ClearanceLevel?,
        awardedClearance: ClearanceLevel,
        completionTrigger: String,
        startScore: Int,
        completionScore: Int,
        timing: MissionTiming
    ) {
        self.id = id
        self.title = title
        self.requiredClearance = requiredClearance
        self.awardedClearance = awardedClearance
        self.completionTrigger = completionTrigger
        self.startScore = startScore
        self.completionScore = completionScore
        self.timing = timing
    }
}

public enum MissionCatalog {
    public static let all: [MissionDefinition] = [
        MissionDefinition(
            id: .orbitalWake,
            title: "Orbital Wake",
            requiredClearance: nil,
            awardedClearance: .dockKey,
            completionTrigger: "mission:complete:orbital-wake",
            startScore: 10_000,
            completionScore: 500_000,
            timing: .resourceDriven(abortTrigger: .stationPowerDepleted)
        ),
        MissionDefinition(
            id: .relayBloom,
            title: "Relay Bloom",
            requiredClearance: .dockKey,
            awardedClearance: .relayKey,
            completionTrigger: "mission:complete:relay-bloom",
            startScore: 10_000,
            completionScore: 500_000,
            timing: .resourceDriven(abortTrigger: .stationPowerDepleted)
        ),
        MissionDefinition(
            id: .cargoDrift,
            title: "Cargo Drift",
            requiredClearance: .relayKey,
            awardedClearance: .cargoKey,
            completionTrigger: "mission:complete:cargo-drift",
            startScore: 10_000,
            completionScore: 500_000,
            timing: .resourceDriven(abortTrigger: .stationPowerDepleted)
        ),
        MissionDefinition(
            id: .prismSurvey,
            title: "Prism Survey",
            requiredClearance: .cargoKey,
            awardedClearance: .prismKey,
            completionTrigger: "mission:complete:prism-survey",
            startScore: 10_000,
            completionScore: 750_000,
            timing: .resourceDriven(abortTrigger: .stationPowerDepleted)
        ),
        MissionDefinition(
            id: .ionChoir,
            title: "Ion Choir",
            requiredClearance: .prismKey,
            awardedClearance: .ionKey,
            completionTrigger: "mission:complete:ion-choir",
            startScore: 20_000,
            completionScore: 1_000_000,
            timing: .resourceDriven(abortTrigger: .stationPowerDepleted)
        ),
        MissionDefinition(
            id: .duskCourier,
            title: "Dusk Courier",
            requiredClearance: .ionKey,
            awardedClearance: .transitKey,
            completionTrigger: "mission:complete:dusk-courier",
            startScore: 20_000,
            completionScore: 1_000_000,
            timing: .resourceDriven(abortTrigger: .stationPowerDepleted)
        ),
        MissionDefinition(
            id: .helixLatch,
            title: "Helix Latch",
            requiredClearance: .transitKey,
            awardedClearance: .shieldKey,
            completionTrigger: "mission:complete:helix-latch",
            startScore: 20_000,
            completionScore: 1_000_000,
            timing: .resourceDriven(abortTrigger: .stationPowerDepleted)
        ),
        MissionDefinition(
            id: .polarVane,
            title: "Polar Vane",
            requiredClearance: .shieldKey,
            awardedClearance: .commandKey,
            completionTrigger: "mission:complete:polar-vane",
            startScore: 20_000,
            completionScore: 750_000,
            timing: .resourceDriven(abortTrigger: .stationPowerDepleted)
        ),
        MissionDefinition(
            id: .novaCrown,
            title: "Nova Crown",
            requiredClearance: .commandKey,
            awardedClearance: .novaKey,
            completionTrigger: "mission:complete:nova-crown",
            startScore: 20_000,
            completionScore: 750_000,
            timing: .resourceDriven(abortTrigger: .stationPowerDepleted)
        ),
        MissionDefinition(
            id: .harborEmber,
            title: "Harbor Ember",
            requiredClearance: .relayKey,
            awardedClearance: .cargoKey,
            completionTrigger: "mission:complete:harbor-ember",
            startScore: 20_000,
            completionScore: 750_000,
            timing: .resourceDriven(abortTrigger: .stationPowerDepleted)
        ),
        MissionDefinition(
            id: .echoSpire,
            title: "Echo Spire",
            requiredClearance: .prismKey,
            awardedClearance: .ionKey,
            completionTrigger: "mission:complete:echo-spire",
            startScore: 20_000,
            completionScore: 1_250_000,
            timing: .resourceDriven(abortTrigger: .stationPowerDepleted)
        ),
        MissionDefinition(
            id: .lanternRoute,
            title: "Lantern Route",
            requiredClearance: .transitKey,
            awardedClearance: .shieldKey,
            completionTrigger: "mission:complete:lantern-route",
            startScore: 20_000,
            completionScore: 1_250_000,
            timing: .resourceDriven(abortTrigger: .stationPowerDepleted)
        ),
        MissionDefinition(
            id: .riftContainment,
            title: "Rift Containment",
            requiredClearance: .shieldKey,
            awardedClearance: .commandKey,
            completionTrigger: "mission:complete:rift-containment",
            startScore: 20_000,
            completionScore: 1_250_000,
            timing: .resourceDriven(abortTrigger: .stationPowerDepleted)
        ),
        MissionDefinition(
            id: .auroraQuarantine,
            title: "Aurora Quarantine",
            requiredClearance: .commandKey,
            awardedClearance: .novaKey,
            completionTrigger: "mission:complete:aurora-quarantine",
            startScore: 30_000,
            completionScore: 1_750_000,
            timing: .resourceDriven(abortTrigger: .stationPowerDepleted)
        ),
        MissionDefinition(
            id: .vaultSignal,
            title: "Vault Signal",
            requiredClearance: .commandKey,
            awardedClearance: .novaKey,
            completionTrigger: "mission:complete:vault-signal",
            startScore: 30_000,
            completionScore: 1_500_000,
            timing: .resourceDriven(abortTrigger: .stationPowerDepleted)
        ),
        MissionDefinition(
            id: .phaseTide,
            title: "Phase Tide",
            requiredClearance: .commandKey,
            awardedClearance: .novaKey,
            completionTrigger: "mission:complete:phase-tide",
            startScore: 30_000,
            completionScore: 2_000_000,
            timing: .resourceDriven(abortTrigger: .stationPowerDepleted)
        ),
        MissionDefinition(
            id: .stationTempest,
            title: "Station Tempest",
            requiredClearance: .commandKey,
            awardedClearance: .novaKey,
            completionTrigger: "mission:complete:station-tempest",
            startScore: 30_000,
            completionScore: 5_000_000,
            timing: .resourceDriven(abortTrigger: .stationPowerDepleted)
        )
    ]

    public static func definition(for id: MissionID) -> MissionDefinition {
        all.first(where: { $0.id == id })!
    }

    public static func objectiveEvents(for id: MissionID) -> [String] {
        switch id {
        case .orbitalWake:
            ["bumper:bumper-orbit", "bumper:bumper-relay", "bumper:bumper-core"]
        case .relayBloom:
            [NovaStationTable.Event.rampLeft, NovaStationTable.Event.rampRight, NovaStationTable.Event.rampLeft]
        case .cargoDrift:
            [NovaStationTable.Event.returnLeft, NovaStationTable.Event.returnCenter, NovaStationTable.Event.returnRight]
        case .prismSurvey:
            [NovaStationTable.Event.targetBank, NovaStationTable.Event.rampLeft, NovaStationTable.Event.targetBank, NovaStationTable.Event.rampRight]
        case .ionChoir:
            [NovaStationTable.Event.rolloverLeft, NovaStationTable.Event.rolloverCenter, NovaStationTable.Event.rolloverRight, NovaStationTable.Event.portal]
        case .duskCourier:
            ["bumper:bumper-orbit", "bumper:bumper-relay", NovaStationTable.Event.portal]
        case .helixLatch:
            [NovaStationTable.Event.outerLeft, NovaStationTable.Event.targetBank, NovaStationTable.Event.outerRight, NovaStationTable.Event.portal]
        case .polarVane:
            [NovaStationTable.Event.outerLeft, NovaStationTable.Event.targetBank, NovaStationTable.Event.outerRight, NovaStationTable.Event.targetBank]
        case .novaCrown:
            ["bumper:bumper-core", "bumper:bumper-orbit", "bumper:bumper-relay", "bumper:bumper-core"]
        case .harborEmber:
            [NovaStationTable.Event.targetBank, NovaStationTable.Event.portal, NovaStationTable.Event.targetBank]
        case .echoSpire:
            ["bumper:bumper-core", "bumper:bumper-core", "bumper:bumper-core"]
        case .lanternRoute:
            [NovaStationTable.Event.rolloverLeft, NovaStationTable.Event.rolloverCenter, NovaStationTable.Event.rolloverRight]
        case .riftContainment:
            [NovaStationTable.Event.outerLeft, NovaStationTable.Event.outerRight, NovaStationTable.Event.outerLeft, NovaStationTable.Event.outerRight]
        case .auroraQuarantine:
            [NovaStationTable.Event.targetBank, NovaStationTable.Event.rolloverCenter, NovaStationTable.Event.targetBank]
        case .vaultSignal:
            [NovaStationTable.Event.returnLeft, NovaStationTable.Event.returnCenter, NovaStationTable.Event.returnRight, NovaStationTable.Event.portal]
        case .phaseTide:
            ["bumper:bumper-orbit", "bumper:bumper-relay", "bumper:bumper-orbit", "bumper:bumper-relay"]
        case .stationTempest:
            [NovaStationTable.Event.targetBank, NovaStationTable.Event.rolloverLeft, NovaStationTable.Event.targetBank, NovaStationTable.Event.rolloverRight]
        }
    }
}
