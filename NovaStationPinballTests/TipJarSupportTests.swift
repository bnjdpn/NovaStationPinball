import XCTest
@testable import NovaStationPinball

final class TipJarSupportTests: XCTestCase {
    func testCatalogContainsExactlyThreeOptionalTipsAndNoFeatureGates() {
        XCTAssertEqual(TipJarCatalog.tips.map(\.id), ["tip.cafe", "tip.merci", "tip.soutien"])
        XCTAssertEqual(
            TipJarCatalog.tips.map(\.productIdentifier),
            [
                "com.bnjdpn.NovaStationPinball.tip.cafe",
                "com.bnjdpn.NovaStationPinball.tip.merci",
                "com.bnjdpn.NovaStationPinball.tip.soutien"
            ]
        )
        XCTAssertTrue(TipJarCatalog.isOptional)
        XCTAssertFalse(TipJarCatalog.grantsGameplayContent)
    }

    func testNullTipJarReturnsUnavailableWithoutThrowing() async {
        let tipJar = NullTipJarSupport()
        let tips = await tipJar.availableTips()
        let outcome = await tipJar.purchase(productIdentifier: "tip.cafe")

        XCTAssertEqual(tips, [])
        XCTAssertEqual(outcome, .unavailable)
    }

    func testStoreKitConfigurationIsAbsentFromRuntimeBundle() {
        XCTAssertNil(Bundle.main.url(forResource: "NovaStationPinball", withExtension: "storekit"))
    }

    @MainActor
    func testOrdinaryGameplayDoesNotStartGameCenterOrStoreKit() async {
        let gameCenter = RecordingGameCenterClient()
        let tipJar = RecordingTipJarSupport()
        let model = AppModel(
            audioEngine: NullAudioEngine(),
            hapticsService: NullHapticsService(),
            gameCenterClient: gameCenter,
            tipJarSupport: tipJar
        )
        activateGameplayForTesting(model)

        model.apply([.plungerReleased(0.7), .nudge(x: 0.2)])

        let tipCallCount = await tipJar.callCount
        XCTAssertEqual(gameCenter.callCount, 0)
        XCTAssertEqual(tipCallCount, 0)
    }
}

@MainActor
private final class RecordingGameCenterClient: GameCenterClient {
    private(set) var callCount = 0
    var isAvailable: Bool { true }
    var isAuthenticated: Bool { false }

    func authenticate() { callCount += 1 }
    func submit(score: Int) { callCount += 1 }
}

private actor RecordingTipJarSupport: TipJarSupport {
    private(set) var callCount = 0

    func availableTips() async -> [AvailableTip] {
        callCount += 1
        return []
    }

    func purchase(productIdentifier: String) async -> TipPurchaseOutcome {
        callCount += 1
        return .unavailable
    }
}
