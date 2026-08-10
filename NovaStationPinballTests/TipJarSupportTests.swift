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

    @MainActor
    func testExplicitTipAccessUsesStoreKitNamesAndPricesWithoutChangingGameplay() async {
        let tips = [
            AvailableTip(
                definition: TipJarCatalog.tips[0],
                displayName: "Coffee",
                displayPrice: "$0.99"
            ),
            AvailableTip(
                definition: TipJarCatalog.tips[1],
                displayName: "Big thanks",
                displayPrice: "$2.99"
            ),
            AvailableTip(
                definition: TipJarCatalog.tips[2],
                displayName: "Strong support",
                displayPrice: "$5.99"
            )
        ]
        let tipJar = RecordingTipJarSupport(
            available: tips,
            purchaseOutcome: .purchased
        )
        let model = AppModel(
            audioEngine: NullAudioEngine(),
            hapticsService: NullHapticsService(),
            gameCenterClient: NullGameCenterClient(),
            tipJarSupport: tipJar
        )
        let gameplayBeforePurchase = model.rulesState
        let loadedTips = await model.availableTips()
        let purchaseOutcome = await model.purchaseTip(
            productIdentifier: TipJarCatalog.tips[1].productIdentifier
        )
        let requestedProductIdentifiers = await tipJar.requestedProductIdentifiers

        XCTAssertEqual(loadedTips, tips)
        XCTAssertEqual(purchaseOutcome, .purchased)
        XCTAssertEqual(model.rulesState, gameplayBeforePurchase)
        XCTAssertEqual(
            requestedProductIdentifiers,
            [TipJarCatalog.tips[1].productIdentifier]
        )
    }

#if DEBUG
    func testUITestingFixtureRequiresBothDebugRuntimeGates() async {
        let noArgument = TipJarSupportFactory.applicationDefault(
            arguments: [],
            environment: ["NOVA_TIP_JAR_FIXTURE": "available"]
        )
        let noEnvironment = TipJarSupportFactory.applicationDefault(
            arguments: ["-ui-testing"],
            environment: [:]
        )
        XCTAssertTrue(noArgument is StoreKitTipJarSupport)
        XCTAssertTrue(noEnvironment is StoreKitTipJarSupport)

        let fixture = TipJarSupportFactory.applicationDefault(
            arguments: ["-ui-testing"],
            environment: ["NOVA_TIP_JAR_FIXTURE": "available"],
            preferredLanguages: ["en"]
        )
        XCTAssertTrue(fixture is UITestingTipJarSupport)
        let fixtureTips = await fixture.availableTips()
        XCTAssertEqual(
            fixtureTips,
            [
                AvailableTip(
                    definition: TipJarCatalog.tips[0],
                    displayName: "Coffee",
                    displayPrice: "$0.99"
                ),
                AvailableTip(
                    definition: TipJarCatalog.tips[1],
                    displayName: "Big thanks",
                    displayPrice: "$2.99"
                ),
                AvailableTip(
                    definition: TipJarCatalog.tips[2],
                    displayName: "Strong support",
                    displayPrice: "$5.99"
                )
            ]
        )
    }
#endif

    func testStoreKitConfigurationIsAbsentFromRuntimeBundle() {
        XCTAssertNil(Bundle.main.url(forResource: "NovaStationPinball", withExtension: "storekit"))
    }

    func testDelayedApprovalFinishesOnlyVerifiedCatalogTransactionUpdate() async {
        let updates = AsyncStream<any TipTransactionFinishing>.makeStream()
        let approvedTip = RecordingTipTransaction(
            productIdentifier: TipJarCatalog.tips[0].productIdentifier
        )
        let unrelatedPurchase = RecordingTipTransaction(
            productIdentifier: "com.bnjdpn.NovaStationPinball.not-a-tip"
        )
        let support = StoreKitTipJarSupport(transactionUpdates: { updates.stream })

        updates.continuation.yield(unrelatedPurchase)
        updates.continuation.yield(approvedTip)

        for _ in 0..<100 {
            if await approvedTip.finishCount == 1 { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        updates.continuation.finish()

        let approvedFinishCount = await approvedTip.finishCount
        let unrelatedFinishCount = await unrelatedPurchase.finishCount
        XCTAssertEqual(approvedFinishCount, 1)
        XCTAssertEqual(unrelatedFinishCount, 0)
        withExtendedLifetime(support) {}
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

private actor RecordingTipTransaction: TipTransactionFinishing {
    nonisolated let productIdentifier: String
    private(set) var finishCount = 0

    init(productIdentifier: String) {
        self.productIdentifier = productIdentifier
    }

    func finish() async {
        finishCount += 1
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
    private(set) var requestedProductIdentifiers: [String] = []
    private let available: [AvailableTip]
    private let purchaseOutcome: TipPurchaseOutcome

    init(
        available: [AvailableTip] = [],
        purchaseOutcome: TipPurchaseOutcome = .unavailable
    ) {
        self.available = available
        self.purchaseOutcome = purchaseOutcome
    }

    func availableTips() async -> [AvailableTip] {
        callCount += 1
        return available
    }

    func purchase(productIdentifier: String) async -> TipPurchaseOutcome {
        callCount += 1
        requestedProductIdentifiers.append(productIdentifier)
        return purchaseOutcome
    }
}
