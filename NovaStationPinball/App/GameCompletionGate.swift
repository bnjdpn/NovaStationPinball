import NovaStationCore

/// Small deterministic edge detector for the game-over transition.
/// AppModel owns one gate per live game so local persistence and the optional
/// Game Center submission can only be initiated once.
struct GameCompletionGate: Sendable {
    private var didRecordCurrentGame = false

    mutating func startNewGame() {
        didRecordCurrentGame = false
    }

    mutating func shouldRecord(phase: GameSessionPhase) -> Bool {
        guard phase == .gameOver, !didRecordCurrentGame else { return false }
        didRecordCurrentGame = true
        return true
    }
}
