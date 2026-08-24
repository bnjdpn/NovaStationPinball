import Foundation
import NovaStationCore

#if DEBUG
/// Deterministic App Store media support. The whole implementation is
/// conditionally compiled so none of its launch arguments or scripted game
/// states exist in the signed Release binary.
enum MediaScenario: String, CaseIterable, Hashable, Sendable {
    case launch = "launch"
    case mission = "mission"
    case promotion = "promotion"
    case multiball = "multiball"
    case tilt = "tilt"
    case gameOver = "game-over"

    static let previewSegmentDuration: TimeInterval = 4

    static func preparePreviewSessions() throws -> [MediaScenario: GameSession] {
        try Dictionary(uniqueKeysWithValues: allCases.map { scenario in
            (scenario, try scenario.makeSession())
        })
    }

    /// Drives the same public production controls used by normal gameplay.
    func makeSession() throws -> GameSession {
        var session = try GameSession()
        guard self != .launch else { return session }
        _ = try session.startNewGame()
        switch self {
        case .launch:
            break
        case .mission:
            try NovaStationGameplayScript.startMission(in: &session)
        case .promotion:
            try NovaStationGameplayScript.completeOrbitalWake(in: &session)
        case .multiball:
            _ = try NovaStationGameplayScript.shoot(NovaStationTable.Event.multiball, in: &session)
        case .tilt:
            NovaStationGameplayScript.tilt(in: &session)
        case .gameOver:
            try NovaStationGameplayScript.playUntilGameOver(in: &session)
        }
        return session
    }
}

struct MediaLaunchConfiguration: Equatable, Sendable {
    let scenario: MediaScenario?
    let runsPreviewSequence: Bool
    let handshakeToken: String?
    /// `-paywall-screenshot` opens the Workshop paywall on launch. Both the
    /// store screenshot pipeline and the App Store Connect in-app-purchase
    /// review capture depend on it.
    let opensPaywall: Bool

    init(arguments: [String]) {
        let isUITesting = arguments.contains("-ui-testing")
        opensPaywall = isUITesting && arguments.contains("-paywall-screenshot")
        guard isUITesting else {
            scenario = nil
            runsPreviewSequence = false
            handshakeToken = nil
            return
        }

        if let flagIndex = arguments.firstIndex(of: "-media-scenario"),
           arguments.indices.contains(flagIndex + 1) {
            scenario = MediaScenario(rawValue: arguments[flagIndex + 1])
        } else if arguments.contains("-media-preview-sequence") {
            scenario = .launch
        } else {
            scenario = nil
        }
        runsPreviewSequence = arguments.contains("-media-preview-sequence")
        if runsPreviewSequence,
           let tokenIndex = arguments.firstIndex(of: "-media-handshake-token"),
           arguments.indices.contains(tokenIndex + 1) {
            let value = arguments[tokenIndex + 1]
            handshakeToken = value.range(of: #"\A[0-9a-f]{32}\z"#, options: .regularExpression) == nil ? nil : value
        } else {
            handshakeToken = nil
        }
    }

    static var current: MediaLaunchConfiguration {
        MediaLaunchConfiguration(arguments: ProcessInfo.processInfo.arguments)
    }
}
#endif
