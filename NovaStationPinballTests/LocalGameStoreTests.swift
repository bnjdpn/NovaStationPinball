import Foundation
import XCTest
import NovaStationCore
@testable import NovaStationPinball

final class LocalGameStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var directory: URL!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "NovaStationPinballTests.LocalGameStore.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NovaStationPinballTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        defaults = nil
        directory = nil
        suiteName = nil
    }

    func testSettingsPersistSeparatelyFromHighScores() throws {
        let store = LocalGameStore(defaults: defaults, directory: directory)
        let settings = SettingsState(musicEnabled: false, soundEffectsEnabled: true, hapticsEnabled: false)
        let scores = [score(identifier: "first", name: "ACE", score: 50_000, seconds: 2)]

        try store.saveSettings(settings)
        try store.saveHighScores(scores)

        XCTAssertEqual(try store.loadSettings(), settings)
        XCTAssertEqual(try store.loadHighScores(), scores)
    }

    func testHighScoresAreSortedDeterministicallyAndLimited() throws {
        let store = LocalGameStore(defaults: defaults, directory: directory, maximumHighScores: 2)
        let earliest = score(identifier: "earliest", name: "BETA", score: 100, seconds: 1)
        let latest = score(identifier: "latest", name: "ALFA", score: 100, seconds: 2)
        let highest = score(identifier: "highest", name: "NOVA", score: 200, seconds: 3)

        try store.saveHighScores([latest, earliest, highest])

        XCTAssertEqual(try store.loadHighScores(), [highest, earliest])
    }

    func testCheckpointIsRestoredOnlyOnce() throws {
        let store = LocalGameStore(defaults: defaults, directory: directory)
        let checkpoint = makeCheckpoint(identifier: "resume-once")

        try store.saveCheckpoint(checkpoint)

        XCTAssertEqual(try store.restoreCheckpointOnce(), checkpoint)
        XCTAssertNil(try store.restoreCheckpointOnce())
    }

    func testSavingCheckpointCreatesMissingDirectoryThenRestoresIt() throws {
        let missingDirectory = directory.appendingPathComponent("missing", isDirectory: true)
        let store = LocalGameStore(defaults: defaults, directory: missingDirectory)
        let checkpoint = makeCheckpoint(identifier: "create-directory")

        try store.saveCheckpoint(checkpoint)

        XCTAssertEqual(try store.restoreCheckpointOnce(), checkpoint)
    }

    func testCheckpointDirectoryCreationErrorIsPropagated() throws {
        let fileInsteadOfDirectory = directory.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: fileInsteadOfDirectory)
        let store = LocalGameStore(defaults: defaults, directory: fileInsteadOfDirectory)

        XCTAssertThrowsError(try store.saveCheckpoint(makeCheckpoint(identifier: "creation-error")))
    }

    func testConcurrentRestoreReturnsCheckpointExactlyOnceWithoutReadErrors() async throws {
        let store = LocalGameStore(defaults: defaults, directory: directory)
        let checkpoint = makeCheckpoint(identifier: "concurrent-resume")
        try store.saveCheckpoint(checkpoint)
        async let firstRestore: ActiveCheckpoint? = try store.restoreCheckpointOnce()
        async let secondRestore: ActiveCheckpoint? = try store.restoreCheckpointOnce()
        let results = try await [firstRestore, secondRestore]

        XCTAssertEqual(results.compactMap { $0 }, [checkpoint])
        XCTAssertEqual(results.filter { $0 == nil }.count, 1)
    }

    func testCorruptCheckpointIsDiscardedWithoutChangingHighScores() throws {
        let store = LocalGameStore(defaults: defaults, directory: directory)
        let scores = [score(identifier: "safe", name: "SAFE", score: 80_000, seconds: 1)]
        try store.saveHighScores(scores)
        try Data("not valid checkpoint JSON".utf8).write(
            to: directory.appendingPathComponent("active-checkpoint.json"),
            options: .atomic
        )

        XCTAssertNil(try store.restoreCheckpointOnce())

        XCTAssertEqual(try store.loadHighScores(), scores)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("active-checkpoint.json").path))
    }

    private func makeCheckpoint(identifier: String) -> ActiveCheckpoint {
        let snapshot = SimulationSnapshot(tableVersion: 1, elapsedTime: 3, balls: [])
        return ActiveCheckpoint(
            identifier: identifier,
            savedAt: Date(timeIntervalSince1970: 3),
            snapshot: snapshot,
            rules: GameRulesState(score: 3_000),
            replay: Replay(tableVersion: 1, initialSnapshot: snapshot, inputs: [])
        )
    }

    private func score(identifier: String, name: String, score: Int, seconds: TimeInterval) -> HighScoreEntry {
        HighScoreEntry(
            identifier: identifier,
            playerName: name,
            score: score,
            achievedAt: Date(timeIntervalSince1970: seconds)
        )
    }
}
