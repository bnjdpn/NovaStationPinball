public enum MissionState: Sendable, Codable, Equatable {
    case idle
    case active(MissionID)
    case completed(MissionID)
    case failed(MissionID)
}

public struct GameRulesState: Sendable, Codable, Equatable {
    public static let regularBallCount = 3
    public static let maximumBonusUnits = 20
    public static let maximumBonusMultiplier = 5
    public static let maximumScoreMultiplier = 4
    public static let maximumExtraBalls = 2
    public static let ballSaveDurationTicks = 2_400
    public static let maximumStationPower = 100
    public static let stationPowerTicksPerUnit = 240
    public static let stationPowerRechargeUnits = 20

    public private(set) var score: Int
    public private(set) var ballsRemaining: Int
    public private(set) var ballsInPlay: Int
    public private(set) var extraBalls: Int
    public private(set) var bonusUnits: Int
    public private(set) var bonusMultiplier: Int
    public private(set) var scoreMultiplier: Int
    public private(set) var ballSaveTicksRemaining: Int
    public private(set) var isTilted: Bool
    public private(set) var isGameOver: Bool
    public private(set) var missionState: MissionState
    public private(set) var clearance: ClearanceLevel?
    public private(set) var missionTicksRemaining: Int?
    public private(set) var selectedMission: MissionID?
    public private(set) var completedMissions: [MissionID]
    public private(set) var missionObjectiveProgress: Int
    public private(set) var stationPower: Int
    private var stationPowerTickRemainder: Int

    public init(score: Int = 0) {
        self.score = min(max(0, score), ScoreEngine.maximumScore)
        self.ballsRemaining = Self.regularBallCount
        self.ballsInPlay = 1
        self.extraBalls = 0
        self.bonusUnits = 0
        self.bonusMultiplier = 1
        self.scoreMultiplier = 1
        self.ballSaveTicksRemaining = 0
        self.isTilted = false
        self.isGameOver = false
        self.missionState = .idle
        self.clearance = nil
        self.missionTicksRemaining = nil
        self.selectedMission = nil
        self.completedMissions = []
        self.missionObjectiveProgress = 0
        self.stationPower = Self.maximumStationPower
        self.stationPowerTickRemainder = 0
    }

    @discardableResult
    public mutating func awardTableScore(baseScore: Int) -> ScoreAward? {
        guard canScore else { return nil }
        return applyScore(source: .table, baseScore: baseScore, multiplier: scoreMultiplier)
    }

    @discardableResult
    public mutating func addBonusUnit() -> Bool {
        guard canScore, bonusUnits < Self.maximumBonusUnits else { return false }
        bonusUnits += 1
        return true
    }

    @discardableResult
    public mutating func increaseBonusMultiplier() -> Bool {
        guard canScore, bonusMultiplier < Self.maximumBonusMultiplier else { return false }
        bonusMultiplier += 1
        return true
    }

    @discardableResult
    public mutating func increaseScoreMultiplier() -> Bool {
        guard canScore, scoreMultiplier < Self.maximumScoreMultiplier else { return false }
        scoreMultiplier += 1
        return true
    }

    @discardableResult
    public mutating func awardExtraBall() -> Bool {
        guard canScore, extraBalls < Self.maximumExtraBalls else { return false }
        extraBalls += 1
        return true
    }

    @discardableResult
    public mutating func activateMultiball() -> Bool {
        guard canScore, ballsInPlay == 1 else { return false }
        ballsInPlay = 3
        return true
    }

    public mutating func activateBallSave() {
        guard canScore else { return }
        ballSaveTicksRemaining = Self.ballSaveDurationTicks
    }

    public mutating func advance(ticks: Int) {
        guard ticks > 0 else { return }
        ballSaveTicksRemaining = max(0, ballSaveTicksRemaining - ticks)
        guard case let .active(missionID) = missionState,
              !isGameOver else { return }

        let definition = MissionCatalog.definition(for: missionID)
        switch definition.timing {
        case .fixedWindow:
            guard let missionTicksRemaining else { return }
            self.missionTicksRemaining = max(0, missionTicksRemaining - ticks)
            if self.missionTicksRemaining == 0 {
                missionState = .failed(missionID)
            }
        case .resourceDriven:
            let total = stationPowerTickRemainder + ticks
            let consumed = total / Self.stationPowerTicksPerUnit
            stationPowerTickRemainder = total % Self.stationPowerTicksPerUnit
            stationPower = max(0, stationPower - consumed)
            if stationPower == 0 {
                missionState = .failed(missionID)
                stationPowerTickRemainder = 0
            }
        }
    }

    @discardableResult
    public mutating func replenishStationPower(units: Int = stationPowerRechargeUnits) -> Bool {
        guard !isGameOver, units > 0, stationPower < Self.maximumStationPower else { return false }
        stationPower = min(Self.maximumStationPower, stationPower + units)
        return true
    }

    @discardableResult
    public mutating func selectNextMission() -> MissionID? {
        guard canScore, missionState == .idle else { return nil }
        let eligible = MissionCatalog.all.filter { mission in
            clearanceMatches(mission.requiredClearance)
                && !completedMissions.contains(mission.id)
        }
        guard !eligible.isEmpty else {
            selectedMission = nil
            return nil
        }
        if let selectedMission,
           let currentIndex = eligible.firstIndex(where: { $0.id == selectedMission }) {
            self.selectedMission = eligible[(currentIndex + 1) % eligible.count].id
        } else {
            selectedMission = eligible[0].id
        }
        return selectedMission
    }

    @discardableResult
    public mutating func startSelectedMission() -> ScoreAward? {
        guard let selectedMission else { return nil }
        return startMission(selectedMission)
    }

    public mutating func tilt() {
        guard !isGameOver else { return }
        isTilted = true
        ballSaveTicksRemaining = 0
        failMission()
    }

    @discardableResult
    public mutating func startMission(_ id: MissionID) -> ScoreAward? {
        let definition = MissionCatalog.definition(for: id)
        guard canScore,
              missionState == .idle,
              clearanceMatches(definition.requiredClearance),
              !completedMissions.contains(id)
        else {
            return nil
        }
        selectedMission = id
        missionState = .active(id)
        missionTicksRemaining = definition.timing.novaTicks
        missionObjectiveProgress = 0
        stationPowerTickRemainder = 0
        return applyScore(source: .missionStart, baseScore: definition.startScore, multiplier: 1)
    }

    @discardableResult
    public mutating func completeMission(trigger: String) -> ScoreAward? {
        guard canScore, case let .active(id) = missionState else { return nil }
        let definition = MissionCatalog.definition(for: id)
        guard trigger == definition.completionTrigger else { return nil }

        missionState = .completed(id)
        missionTicksRemaining = nil
        missionObjectiveProgress = 0
        stationPowerTickRemainder = 0
        if !completedMissions.contains(id) {
            completedMissions.append(id)
        }
        if clearance == nil || definition.awardedClearance.rank > clearance!.rank {
            clearance = definition.awardedClearance
        }
        return applyScore(source: .missionComplete, baseScore: definition.completionScore, multiplier: 1)
    }

    public mutating func failMission() {
        guard case let .active(id) = missionState else { return }
        missionState = .failed(id)
        missionTicksRemaining = nil
        missionObjectiveProgress = 0
        stationPowerTickRemainder = 0
    }

    @discardableResult
    public mutating func applyMissionAbort(_ trigger: MissionAbortTrigger) -> Bool {
        guard case let .active(id) = missionState,
              MissionCatalog.definition(for: id).timing.abortTrigger == trigger
        else {
            return false
        }
        failMission()
        return true
    }

    public mutating func acknowledgeMissionResult() {
        switch missionState {
        case .completed, .failed:
            missionState = .idle
            selectedMission = nil
            missionObjectiveProgress = 0
        case .idle, .active:
            break
        }
    }

    /// Advances the active mission only from an ordered physical table event.
    /// A mismatching event resets the sequence, except when it is also the
    /// first event of the objective.
    @discardableResult
    public mutating func recordMissionObjective(eventName: String) -> ScoreAward? {
        guard canScore, case let .active(id) = missionState else { return nil }
        let definition = MissionCatalog.definition(for: id)
        let events = definition.objectiveEvents
        guard !events.isEmpty else { return nil }

        if eventName == events[missionObjectiveProgress] {
            missionObjectiveProgress += 1
        }
        guard missionObjectiveProgress == events.count else { return nil }
        return completeMission(trigger: definition.completionTrigger)
    }

    @discardableResult
    public mutating func drainBall() -> ScoreAward? {
        guard !isGameOver else { return nil }

        guard ballsInPlay == 1 else {
            ballsInPlay -= 1
            return nil
        }

        if ballSaveTicksRemaining > 0 && !isTilted {
            ballSaveTicksRemaining = 0
            return nil
        }

        failMission()

        let bonusAward = isTilted || bonusUnits == 0
            ? nil
            : applyScore(
                source: .drainBonus,
                baseScore: bonusUnits * 1_000,
                multiplier: bonusMultiplier
            )
        bonusUnits = 0
        bonusMultiplier = 1
        scoreMultiplier = 1
        ballSaveTicksRemaining = 0
        isTilted = false
        stationPowerTickRemainder = 0

        if extraBalls > 0 {
            extraBalls -= 1
        } else {
            ballsRemaining -= 1
        }
        isGameOver = ballsRemaining == 0
        if isGameOver {
            ballsInPlay = 0
        }
        return bonusAward
    }

    private var canScore: Bool {
        !isGameOver && !isTilted
    }

    private func clearanceMatches(_ required: ClearanceLevel?) -> Bool {
        switch (required, clearance) {
        case (nil, nil): true
        case let (required?, active?): required == active
        default: false
        }
    }

    private mutating func applyScore(
        source: ScoreSource,
        baseScore: Int,
        multiplier: Int
    ) -> ScoreAward {
        let award = ScoreEngine.award(
            source: source,
            currentScore: score,
            baseScore: baseScore,
            multiplier: multiplier
        )
        score = award.resultingScore
        return award
    }
}
