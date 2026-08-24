import Foundation
import NovaStationCore
import XCTest
@testable import NovaStationPinball

// MARK: - Grandfathering

/// The four checks that keep the Founder flag honest. The expensive bug this
/// guards against is a "legacy user" signal that the new build writes itself:
/// every fresh install would then be flagged legacy and silently receive the
/// paid tier.
final class LegacyEntitlementTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    override func setUpWithError() throws {
        suiteName = "LegacyEntitlementTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// 1. A brand new install is NOT a Founder — and stays that way after all
    /// of the app's services have run and written their own state.
    @MainActor
    func testAFreshInstallIsNotAFounderAfterEveryServiceHasStarted() throws {
        LegacyEntitlement.migrateIfNeeded(userDefaults: defaults, checkpointExists: false)

        XCTAssertFalse(LegacyEntitlement.isFounder(userDefaults: defaults))

        // Start everything the real app starts, then let it write its state.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let localGameStore = LocalGameStore(defaults: defaults, directory: directory)
        let store = StoreService(
            backend: NullWorkshopStoreBackend(),
            userDefaults: defaults,
            bypassesStore: false
        )
        let model = AppModel(
            audioEngine: NullAudioEngine(),
            hapticsService: NullHapticsService(),
            gameCenterClient: NullGameCenterClient(),
            localGameStore: localGameStore,
            store: store,
            mediaLaunchConfiguration: MediaLaunchConfiguration(arguments: ["app"])
        )
        model.start()
        model.setApplicationActivity(.active)
        model.apply([.plungerReleased(1)])
        try localGameStore.saveSettings(SettingsState())
        try localGameStore.saveHighScores([
            HighScoreEntry(identifier: "a", playerName: "NOVA", score: 1, achievedAt: Date())
        ])

        // The usage signals now exist, but they were written by THIS launch,
        // after the one-shot check: the install is still not a Founder.
        XCTAssertFalse(LegacyEntitlement.isFounder(userDefaults: defaults))
        XCTAssertFalse(store.isFounder)
        XCTAssertFalse(store.hasWorkshop)
        XCTAssertEqual(store.freeRewindsPerGame, WorkshopCatalog.freeRewindsPerGame)
    }

    /// 2. An install that already carries pre-update usage data is a Founder.
    @MainActor
    func testAnInstallWithEarlierUsageDataIsAFounder() throws {
        defaults.set(Data("[]".utf8), forKey: "nova-station.high-scores")

        LegacyEntitlement.migrateIfNeeded(userDefaults: defaults, checkpointExists: false)

        XCTAssertTrue(LegacyEntitlement.isFounder(userDefaults: defaults))
        let store = StoreService(
            backend: NullWorkshopStoreBackend(),
            userDefaults: defaults,
            bypassesStore: false
        )
        XCTAssertTrue(store.isFounder)
        XCTAssertEqual(store.freeRewindsPerGame, WorkshopCatalog.founderRewindsPerGame)
    }

    func testAnInterruptedEarlierGameAloneIsEnoughToBeAFounder() {
        LegacyEntitlement.migrateIfNeeded(userDefaults: defaults, checkpointExists: true)

        XCTAssertTrue(LegacyEntitlement.isFounder(userDefaults: defaults))
    }

    /// 3. The migration runs once and is safe to call any number of times.
    func testMigrationIsIdempotent() {
        LegacyEntitlement.migrateIfNeeded(userDefaults: defaults, checkpointExists: false)
        XCTAssertFalse(LegacyEntitlement.isFounder(userDefaults: defaults))

        // A signal appearing later — written by this very version — must not
        // retroactively turn a new install into a Founder.
        defaults.set(Data("[]".utf8), forKey: "nova-station.high-scores")
        LegacyEntitlement.migrateIfNeeded(userDefaults: defaults, checkpointExists: true)
        LegacyEntitlement.migrateIfNeeded(userDefaults: defaults, checkpointExists: true)

        XCTAssertFalse(LegacyEntitlement.isFounder(userDefaults: defaults))
        XCTAssertTrue(defaults.bool(forKey: LegacyEntitlement.Keys.migrationCompleted))
    }

    /// 4. Access granted is access kept: nothing ever revokes the flag.
    @MainActor
    func testGrantedAccessIsNeverRevoked() {
        defaults.set(Data("{}".utf8), forKey: "nova-station.settings")
        LegacyEntitlement.migrateIfNeeded(userDefaults: defaults, checkpointExists: false)
        XCTAssertTrue(LegacyEntitlement.isFounder(userDefaults: defaults))

        // Every signal disappears — a wiped save, a cleared setting…
        defaults.removeObject(forKey: "nova-station.settings")
        defaults.removeObject(forKey: "nova-station.high-scores")
        for _ in 0 ..< 5 {
            LegacyEntitlement.migrateIfNeeded(userDefaults: defaults, checkpointExists: false)
        }

        XCTAssertTrue(LegacyEntitlement.isFounder(userDefaults: defaults))
        XCTAssertEqual(
            StoreService(
                backend: NullWorkshopStoreBackend(),
                userDefaults: defaults,
                bypassesStore: false
            ).freeRewindsPerGame,
            WorkshopCatalog.founderRewindsPerGame
        )
    }

    func testTheFounderFlagIsNeverWrittenByTheUsageSignalReader() {
        XCTAssertFalse(LegacyEntitlement.usageSignalKeys.contains(LegacyEntitlement.Keys.founder))
        XCTAssertFalse(
            LegacyEntitlement.usageSignalKeys.contains(LegacyEntitlement.Keys.migrationCompleted)
        )

        _ = LegacyEntitlement.hasExistingUsageSignals(
            userDefaults: defaults,
            checkpointExists: false
        )

        XCTAssertNil(defaults.object(forKey: LegacyEntitlement.Keys.founder))
        XCTAssertNil(defaults.object(forKey: LegacyEntitlement.Keys.migrationCompleted))
    }
}

// MARK: - Store plumbing

@MainActor
final class StoreServiceTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    override func setUpWithError() throws {
        suiteName = "StoreServiceTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeStore(_ backend: StubWorkshopStoreBackend) -> StoreService {
        StoreService(backend: backend, userDefaults: defaults, bypassesStore: false)
    }

    func testTheCatalogSellsExactlyOneNonConsumableAndNoTip() {
        XCTAssertEqual(
            WorkshopCatalog.entitlementProductIDs,
            ["com.bnjdpn.NovaStationPinball.workshop"]
        )
        XCTAssertEqual(WorkshopCatalog.freeRewindsPerGame, 3)
        XCTAssertEqual(WorkshopCatalog.founderRewindsPerGame, 10)
    }

    func testAnOwnedEntitlementUnlocksTheWorkshop() async {
        let backend = StubWorkshopStoreBackend()
        let store = makeStore(backend)

        await store.refreshEntitlements()
        XCTAssertFalse(store.hasWorkshop)

        backend.owned = [WorkshopCatalog.workshopProductID]
        await store.refreshEntitlements()

        XCTAssertTrue(store.hasWorkshop)
    }

    func testAForeignEntitlementNeverUnlocksTheWorkshop() async {
        let backend = StubWorkshopStoreBackend()
        backend.owned = ["com.bnjdpn.NovaStationPinball.tip.cafe"]
        let store = makeStore(backend)

        await store.refreshEntitlements()

        XCTAssertFalse(store.hasWorkshop)
    }

    func testTheOfferIsLoadedOnceAndCarriesTheStoreKitNameAndPrice() async {
        let backend = StubWorkshopStoreBackend()
        let store = makeStore(backend)

        await store.loadOfferIfNeeded()
        await store.loadOfferIfNeeded()

        XCTAssertEqual(store.loadState, .available)
        XCTAssertEqual(store.offer?.displayPrice, "4,99 €")
        XCTAssertEqual(store.offer?.displayName, "L’Atelier")
        XCTAssertEqual(backend.loadOfferCallCount, 1)
    }

    func testAnUnavailableOfferIsAnExplicitState() async {
        let backend = StubWorkshopStoreBackend()
        backend.offer = nil
        let store = makeStore(backend)

        await store.loadOfferIfNeeded()

        XCTAssertEqual(store.loadState, .unavailable)
        XCTAssertNil(store.offer)
        XCTAssertFalse(store.hasWorkshop)
    }

    func testReopeningAfterAnUnavailableOfferRetriesAndRecovers() async {
        let backend = StubWorkshopStoreBackend()
        backend.offer = nil
        let store = makeStore(backend)

        await store.loadOfferIfNeeded()
        XCTAssertEqual(store.loadState, .unavailable)
        XCTAssertEqual(backend.loadOfferCallCount, 1)

        backend.offer = WorkshopOffer(
            productIdentifier: WorkshopCatalog.workshopProductID,
            displayName: "L’Atelier",
            displayPrice: "4,99 €",
            localizedDescription: "Rembobinage illimité et atelier de tir."
        )
        await store.loadOfferIfNeeded()

        XCTAssertEqual(store.loadState, .available)
        XCTAssertEqual(store.offer?.displayName, "L’Atelier")
        XCTAssertEqual(backend.loadOfferCallCount, 2)

        await store.loadOfferIfNeeded()
        XCTAssertEqual(backend.loadOfferCallCount, 2, "an available offer must remain cached")
    }

    func testPurchasingUnlocksTheWorkshopAndReportsIt() async {
        let backend = StubWorkshopStoreBackend()
        let store = makeStore(backend)
        await store.loadOfferIfNeeded()

        await store.purchase()

        XCTAssertTrue(store.hasWorkshop)
        XCTAssertEqual(store.lastOutcome, .purchased)
    }

    func testACancelledPurchaseChangesNothing() async {
        let backend = StubWorkshopStoreBackend()
        backend.purchaseOutcome = .cancelled
        let store = makeStore(backend)
        await store.loadOfferIfNeeded()

        await store.purchase()

        XCTAssertFalse(store.hasWorkshop)
        XCTAssertEqual(store.lastOutcome, .cancelled)
    }

    func testRestoringSyncsTheAppStoreAndRecoversTheEntitlement() async {
        let backend = StubWorkshopStoreBackend()
        backend.restoreGrantsEntitlement = true
        let store = makeStore(backend)

        await store.restorePurchases()

        XCTAssertEqual(backend.restoreCallCount, 1)
        XCTAssertTrue(store.hasWorkshop)
        XCTAssertEqual(store.lastOutcome, .purchased)
    }

    func testRestoringWithNothingToRestoreSaysSo() async {
        let backend = StubWorkshopStoreBackend()
        let store = makeStore(backend)

        await store.restorePurchases()

        XCTAssertFalse(store.hasWorkshop)
        XCTAssertEqual(store.lastOutcome, .nothingToRestore)
    }

    func testTransactionUpdatesRefreshTheEntitlementWithoutAPurchase() async {
        let backend = StubWorkshopStoreBackend()
        let store = makeStore(backend)
        store.start()
        XCTAssertFalse(store.hasWorkshop)

        backend.owned = [WorkshopCatalog.workshopProductID]
        backend.emitTransactionUpdate()

        let unlocked = await waitForWorkshop(store)
        XCTAssertTrue(unlocked)
    }

    func testTheStoreBypassRequiresTheDebugUITestGateAndNeverAppliesToPaywallCapture() {
        XCTAssertTrue(StoreService.isStoreBypassEnabled(arguments: ["app", "-ui-testing"]))
        XCTAssertFalse(StoreService.isStoreBypassEnabled(arguments: ["app", "-screenshots"]))
        XCTAssertFalse(StoreService.isStoreBypassEnabled(arguments: ["app"]))
        XCTAssertFalse(
            StoreService.isStoreBypassEnabled(arguments: ["app", "-ui-testing", "-paywall-screenshot"]),
            "the paywall capture must show the real locked paywall"
        )
    }

    func testTheLaunchArgumentThatOpensThePaywallIsRecognized() {
        XCTAssertFalse(
            MediaLaunchConfiguration(arguments: ["app", "-paywall-screenshot"]).opensPaywall,
            "test-only paywall launch behavior requires the explicit UI-test gate"
        )
        XCTAssertTrue(
            MediaLaunchConfiguration(arguments: ["app", "-ui-testing", "-paywall-screenshot"]).opensPaywall
        )
        XCTAssertFalse(MediaLaunchConfiguration(arguments: ["app"]).opensPaywall)
    }

    /// Guideline 3.1.2: the shipped binary states, in every shipped language,
    /// that the purchase is one-time and that there is nothing to renew or
    /// cancel. The structural checks on the paywall view (price read from
    /// `StoreKit.Product`, Restore button, terms and privacy links, no
    /// hard-coded price) live in `scripts/release_contract.rb`, which can read
    /// the repository; a test bundle running in the simulator sandbox cannot.
    func testTheShippedPaywallCopyDisclosesAOneTimePurchaseInEveryLanguage() throws {
        XCTAssertEqual(
            WorkshopCatalog.termsOfUseURL,
            "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
        )
        XCTAssertEqual(
            WorkshopCatalog.privacyURL,
            "https://bnjdpn.github.io/NovaStationPinball/privacy.html"
        )

        let english = try compiledStrings(locale: "en")
        let french = try compiledStrings(locale: "fr")

        let englishDisclosure = try XCTUnwrap(english["paywall.one_time"]).lowercased()
        XCTAssertTrue(englishDisclosure.contains("one-time purchase"), englishDisclosure)
        XCTAssertTrue(englishDisclosure.contains("not a subscription"), englishDisclosure)
        XCTAssertTrue(englishDisclosure.contains("nothing renews"), englishDisclosure)

        let frenchDisclosure = try XCTUnwrap(french["paywall.one_time"]).lowercased()
        XCTAssertTrue(frenchDisclosure.contains("achat unique"), frenchDisclosure)
        XCTAssertTrue(frenchDisclosure.contains("pas un abonnement"), frenchDisclosure)

        let englishUnavailable = try XCTUnwrap(english["paywall.unavailable"]).lowercased()
        XCTAssertTrue(englishUnavailable.contains("reopen the workshop"), englishUnavailable)
        let frenchUnavailable = try XCTUnwrap(french["paywall.unavailable"]).lowercased()
        XCTAssertTrue(frenchUnavailable.contains("rouvrez l’atelier"), frenchUnavailable)

        for locale in [english, french] {
            XCTAssertFalse(try XCTUnwrap(locale["paywall.restore"]).isEmpty)
            XCTAssertFalse(try XCTUnwrap(locale["paywall.link.terms"]).isEmpty)
            XCTAssertFalse(try XCTUnwrap(locale["paywall.link.privacy"]).isEmpty)
            XCTAssertFalse(try XCTUnwrap(locale["paywall.unavailable"]).isEmpty)
            // The free tier is stated on the paywall itself, before paying.
            XCTAssertFalse(try XCTUnwrap(locale["paywall.free_forever"]).isEmpty)
        }
    }

    /// An app that sells a product does not also ask for tips: no tip string
    /// survives in any shipped language.
    func testNoTipCopySurvivesInTheShippedBundle() throws {
        for locale in ["en", "fr"] {
            let strings = try compiledStrings(locale: locale)
            XCTAssertTrue(
                strings.keys.allSatisfy { !$0.hasPrefix("tips.") },
                "tip strings still ship in \(locale)"
            )
            for (key, value) in strings {
                let lowercased = value.lowercased()
                XCTAssertFalse(lowercased.contains("pourboire"), "\(key) [\(locale)]")
                XCTAssertFalse(lowercased.contains("tip jar"), "\(key) [\(locale)]")
            }
        }
    }

    // MARK: - Helpers

    private func waitForWorkshop(_ store: StoreService) async -> Bool {
        for _ in 0 ..< 200 {
            if store.hasWorkshop { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return store.hasWorkshop
    }

    private func compiledStrings(locale: String) throws -> [String: String] {
        let applicationBundle = Bundle(for: AppModel.self)
        let localizationPath = try XCTUnwrap(
            applicationBundle.path(forResource: locale, ofType: "lproj"),
            "Missing compiled \(locale) localization"
        )
        let localizationBundle = try XCTUnwrap(Bundle(path: localizationPath))
        let stringsURL = try XCTUnwrap(
            localizationBundle.url(forResource: "Localizable", withExtension: "strings")
        )
        return try XCTUnwrap(NSDictionary(contentsOf: stringsURL) as? [String: String])
    }
}

final class StubWorkshopStoreBackend: WorkshopStoreBackend, @unchecked Sendable {
    var offer: WorkshopOffer? = WorkshopOffer(
        productIdentifier: WorkshopCatalog.workshopProductID,
        displayName: "L’Atelier",
        displayPrice: "4,99 €",
        localizedDescription: "Rembobinage illimité et atelier de tir."
    )
    var owned: Set<String> = []
    var purchaseOutcome = WorkshopPurchaseOutcome.purchased
    var restoreGrantsEntitlement = false
    private(set) var loadOfferCallCount = 0
    private(set) var restoreCallCount = 0
    private let continuationLock = NSLock()
    private var continuation: AsyncStream<Void>.Continuation?

    func loadOffer() async -> WorkshopOffer? {
        loadOfferCallCount += 1
        return offer
    }

    func ownedEntitlementProductIDs() async -> Set<String> {
        owned.intersection(WorkshopCatalog.entitlementProductIDs)
    }

    func purchase() async -> WorkshopPurchaseOutcome {
        if purchaseOutcome == .purchased {
            owned.insert(WorkshopCatalog.workshopProductID)
        }
        return purchaseOutcome
    }

    func restore() async -> WorkshopPurchaseOutcome {
        restoreCallCount += 1
        if restoreGrantsEntitlement {
            owned.insert(WorkshopCatalog.workshopProductID)
            return .purchased
        }
        return .nothingToRestore
    }

    func transactionUpdates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            continuationLock.withLock { self.continuation = continuation }
        }
    }

    func emitTransactionUpdate() {
        continuationLock.withLock { continuation }?.yield(())
    }
}
