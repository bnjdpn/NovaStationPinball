public enum ScoreSource: String, Sendable, Codable, Equatable {
    case table
    case drainBonus
    case missionStart
    case missionComplete
}

public struct ScoreAward: Sendable, Codable, Equatable {
    public let source: ScoreSource
    public let baseScore: Int
    public let multiplier: Int
    public let points: Int
    public let resultingScore: Int
    public let didSaturate: Bool

    public init(
        source: ScoreSource,
        baseScore: Int,
        multiplier: Int,
        points: Int,
        resultingScore: Int,
        didSaturate: Bool
    ) {
        self.source = source
        self.baseScore = baseScore
        self.multiplier = multiplier
        self.points = points
        self.resultingScore = resultingScore
        self.didSaturate = didSaturate
    }
}

public enum ScoreEngine {
    public static let maximumScore = 999_999_999

    public static func award(
        source: ScoreSource,
        currentScore: Int,
        baseScore: Int,
        multiplier: Int = 1
    ) -> ScoreAward {
        let normalizedScore = min(max(0, currentScore), maximumScore)
        let normalizedBaseScore = max(0, baseScore)
        let normalizedMultiplier = max(1, multiplier)
        let (rawPoints, overflowed) = normalizedBaseScore.multipliedReportingOverflow(
            by: normalizedMultiplier
        )
        let requestedPoints = overflowed ? Int.max : rawPoints
        let availablePoints = maximumScore - normalizedScore
        let points = min(requestedPoints, availablePoints)
        let resultingScore = normalizedScore + points

        return ScoreAward(
            source: source,
            baseScore: normalizedBaseScore,
            multiplier: normalizedMultiplier,
            points: points,
            resultingScore: resultingScore,
            didSaturate: requestedPoints > availablePoints
        )
    }
}
