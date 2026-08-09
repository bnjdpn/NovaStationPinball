import NovaStationCore
import XCTest
@testable import NovaStationPinball

@MainActor
final class GameCenterClientTests: XCTestCase {
    func testLiveClientAlwaysHasAnAuthenticationPresenter() {
        XCTAssertTrue(GameKitGameCenterClient().canPresentAuthentication)
    }

    func testStartingOptionalServicesAuthenticatesOnlyOnce() {
        let client = RecordingGameCenterClient()
        let model = AppModel(gameCenterClient: client)

        model.startOptionalServices()
        model.startOptionalServices()

        XCTAssertEqual(client.authenticationCount, 1)
    }

    func testNullGameCenterIsUnavailableAndNeverBlocksLocalScores() throws {
        let client = NullGameCenterClient()
        let suite = "NovaStationPinballTests.GameCenter.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NovaStationPinballTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = LocalGameStore(defaults: defaults, directory: directory)
        let localScore = HighScoreEntry(
            identifier: "offline",
            playerName: "NOVA",
            score: 42_000,
            achievedAt: Date(timeIntervalSince1970: 1)
        )

        client.authenticate()
        client.submit(score: localScore.score)
        try store.saveHighScores([localScore])

        XCTAssertFalse(client.isAvailable)
        XCTAssertFalse(client.isAuthenticated)
        XCTAssertEqual(try store.loadHighScores(), [localScore])
    }

    func testAppModelAcceptsUnavailableGameCenterWithoutAffectingPlay() {
        let model = AppModel(
            audioEngine: NullAudioEngine(),
            hapticsService: NullHapticsService(),
            gameCenterClient: NullGameCenterClient()
        )
        activateGameplayForTesting(model)

        model.apply([.plungerReleased(1)])

        XCTAssertEqual(model.takeSimulationInput().commands, [.releasePlunger(strength: 1)])
    }

    func testCompletedGameIsSavedLocallyBeforeBestEffortSubmission() throws {
        let suite = "NovaStationPinballTests.GameCenter.Completion.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NovaStationPinballTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = LocalGameStore(defaults: defaults, directory: directory)
        let entry = HighScoreEntry(
            identifier: "completed-game",
            playerName: "NOVA",
            score: 99_000,
            achievedAt: Date(timeIntervalSince1970: 2)
        )
        let client = RecordingGameCenterClient()
        client.onSubmit = { submittedScore in
            XCTAssertEqual(try? store.loadHighScores(), [entry])
            XCTAssertEqual(submittedScore, entry.score)
        }
        let model = AppModel(gameCenterClient: client, localGameStore: store)

        try model.recordCompletedGame(entry)

        XCTAssertEqual(client.submittedScores, [entry.score])
    }
}

@MainActor
private final class RecordingGameCenterClient: GameCenterClient {
    var onSubmit: ((Int) -> Void)?
    private(set) var authenticationCount = 0
    private(set) var submittedScores: [Int] = []
    var isAvailable: Bool { true }
    var isAuthenticated: Bool { true }

    func authenticate() { authenticationCount += 1 }
    func submit(score: Int) {
        submittedScores.append(score)
        onSubmit?(score)
    }
}
