@testable import NovaStationPinball

@MainActor
func activateGameplayForTesting(_ model: AppModel) {
    model.setApplicationActivity(.active)
    model.lifecycleCoordinator.start()
    if model.gamePhase != .playing {
        model.apply([.plungerReleased(1)])
        _ = model.takeSimulationInput()
    }
}
