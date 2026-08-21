import Foundation
import NovaStationCore

/// All accesses to the injected persistence dependencies are serialized by `lock`.
/// Callers own validation and deduplication of score identifiers, names and values.
final class LocalGameStore: @unchecked Sendable {
    private enum Key {
        static let settings = "nova-station.settings"
        static let highScores = "nova-station.high-scores"
        /// Assisted runs are ranked apart from the honest ladder.
        static let trainingScores = "nova-station.training-scores"
        static let drillProgress = "nova-station.drill-progress"
        /// Survives backgrounding so an assisted run stays assisted after a
        /// relaunch, without touching the checkpoint format.
        static let assistedSession = "nova-station.assisted-session"
    }

    private let defaults: UserDefaults
    private let directory: URL
    private let fileManager: FileManager
    private let maximumHighScores: Int
    private let lock = NSLock()

    static func applicationDefault(fileManager: FileManager = .default) -> LocalGameStore {
        let baseDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return LocalGameStore(
            defaults: .standard,
            directory: baseDirectory.appendingPathComponent("NovaStationPinball", isDirectory: true),
            fileManager: fileManager
        )
    }

    init(defaults: UserDefaults, directory: URL, fileManager: FileManager = .default, maximumHighScores: Int = 10) {
        self.defaults = defaults
        self.directory = directory
        self.fileManager = fileManager
        self.maximumHighScores = max(0, maximumHighScores)
    }

    func loadSettings() throws -> SettingsState {
        try lock.withLock {
            guard let data = defaults.data(forKey: Key.settings) else { return SettingsState() }
            return try JSONDecoder().decode(SettingsState.self, from: data)
        }
    }

    func saveSettings(_ settings: SettingsState) throws {
        try lock.withLock {
            defaults.set(try JSONEncoder().encode(settings), forKey: Key.settings)
        }
    }

    func loadHighScores() throws -> [HighScoreEntry] {
        try lock.withLock {
            guard let data = defaults.data(forKey: Key.highScores) else { return [] }
            return try JSONDecoder().decode([HighScoreEntry].self, from: data)
        }
    }

    func saveHighScores(_ scores: [HighScoreEntry]) throws {
        try lock.withLock {
            let retainedScores = scores.sorted(by: Self.isHigherRanked).prefix(maximumHighScores)
            defaults.set(try JSONEncoder().encode(Array(retainedScores)), forKey: Key.highScores)
        }
    }

    /// Separate ladder for runs that used the Workshop. Same `HighScoreEntry`
    /// format, a brand new key: the ranked scores never migrate.
    func loadTrainingScores() throws -> [HighScoreEntry] {
        try lock.withLock {
            guard let data = defaults.data(forKey: Key.trainingScores) else { return [] }
            return try JSONDecoder().decode([HighScoreEntry].self, from: data)
        }
    }

    func saveTrainingScores(_ scores: [HighScoreEntry]) throws {
        try lock.withLock {
            let retainedScores = scores.sorted(by: Self.isHigherRanked).prefix(maximumHighScores)
            defaults.set(try JSONEncoder().encode(Array(retainedScores)), forKey: Key.trainingScores)
        }
    }

    func loadDrillProgress() throws -> DrillProgress {
        try lock.withLock {
            guard let data = defaults.data(forKey: Key.drillProgress) else { return DrillProgress() }
            return try JSONDecoder().decode(DrillProgress.self, from: data)
        }
    }

    func saveDrillProgress(_ progress: DrillProgress) throws {
        try lock.withLock {
            defaults.set(try JSONEncoder().encode(progress), forKey: Key.drillProgress)
        }
    }

    var isAssistedSessionMarked: Bool {
        lock.withLock { defaults.bool(forKey: Key.assistedSession) }
    }

    func setAssistedSessionMarked(_ marked: Bool) {
        lock.withLock {
            if marked {
                defaults.set(true, forKey: Key.assistedSession)
            } else {
                defaults.removeObject(forKey: Key.assistedSession)
            }
        }
    }

    func saveCheckpoint(_ checkpoint: ActiveCheckpoint) throws {
        try lock.withLock {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(CheckpointEnvelope(checkpoint: checkpoint))
            try data.write(to: checkpointURL, options: .atomic)
        }
    }

    /// Decodes first and only then removes the file. A saved game that cannot
    /// be read is quarantined, never destroyed: the player keeps a copy and
    /// the failure leaves a trace on disk.
    func restoreCheckpointOnce() throws -> ActiveCheckpoint? {
        try lock.withLock {
            guard fileManager.fileExists(atPath: checkpointURL.path) else { return nil }
            let data = try Data(contentsOf: checkpointURL)
            let checkpoint: ActiveCheckpoint
            do {
                checkpoint = try JSONDecoder().decode(CheckpointEnvelope.self, from: data).checkpoint
            } catch is DecodingError {
                try quarantineCheckpoint()
                return nil
            } catch is ReplayError {
                try quarantineCheckpoint()
                return nil
            }
            try fileManager.removeItem(at: checkpointURL)
            return checkpoint
        }
    }

    private func quarantineCheckpoint() throws {
        if fileManager.fileExists(atPath: quarantinedCheckpointURL.path) {
            try fileManager.removeItem(at: quarantinedCheckpointURL)
        }
        try fileManager.moveItem(at: checkpointURL, to: quarantinedCheckpointURL)
    }

    private var checkpointURL: URL {
        directory.appendingPathComponent("active-checkpoint.json", isDirectory: false)
    }

    private var quarantinedCheckpointURL: URL {
        directory.appendingPathComponent("active-checkpoint.bak", isDirectory: false)
    }

    private static func isHigherRanked(_ lhs: HighScoreEntry, _ rhs: HighScoreEntry) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.achievedAt != rhs.achievedAt { return lhs.achievedAt < rhs.achievedAt }
        if lhs.playerName != rhs.playerName { return lhs.playerName < rhs.playerName }
        return lhs.identifier < rhs.identifier
    }
}

extension LocalGameStore: LifecycleCheckpointStore {}
