import Foundation

/// Per-drill training record. A brand new type under a brand new key: no
/// existing persisted format is touched, so nothing can migrate wrong.
public struct DrillProgressEntry: Sendable, Codable, Equatable {
    public var attempts: Int
    public var successes: Int
    public var bestStreak: Int
    public var currentStreak: Int

    public init(attempts: Int = 0, successes: Int = 0, bestStreak: Int = 0, currentStreak: Int = 0) {
        self.attempts = max(0, attempts)
        self.successes = max(0, successes)
        self.bestStreak = max(0, bestStreak)
        self.currentStreak = max(0, currentStreak)
    }

    /// 0...1. Zero attempts reads as zero, never as a division by zero.
    public var successRate: Double {
        attempts > 0 ? Double(successes) / Double(attempts) : 0
    }

    public mutating func record(succeeded: Bool) {
        attempts += 1
        if succeeded {
            successes += 1
            currentStreak += 1
            bestStreak = max(bestStreak, currentStreak)
        } else {
            currentStreak = 0
        }
    }
}

public struct DrillProgress: Sendable, Codable, Equatable {
    public static let formatVersion = 1

    public private(set) var entries: [String: DrillProgressEntry]

    public init(entries: [String: DrillProgressEntry] = [:]) {
        self.entries = entries
    }

    public func entry(for drillID: String) -> DrillProgressEntry {
        entries[drillID] ?? DrillProgressEntry()
    }

    public mutating func record(drillID: String, succeeded: Bool) {
        var entry = entry(for: drillID)
        entry.record(succeeded: succeeded)
        entries[drillID] = entry
    }

    public var totalAttempts: Int { entries.values.reduce(0) { $0 + $1.attempts } }
    public var totalSuccesses: Int { entries.values.reduce(0) { $0 + $1.successes } }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case entries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try PersistenceVersion.validate(
            try container.decode(Int.self, forKey: .formatVersion),
            expected: Self.formatVersion,
            codingPath: container.codingPath
        )
        entries = try container.decode([String: DrillProgressEntry].self, forKey: .entries)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.formatVersion, forKey: .formatVersion)
        try container.encode(entries, forKey: .entries)
    }
}
