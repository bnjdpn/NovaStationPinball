import Foundation
import Observation
import StoreKit

/// The single thing Nova Station sells: the Workshop, a one-time unlock.
/// There is no subscription, no consumable and no tip in the binary.
enum WorkshopCatalog {
    static let workshopProductID = "com.bnjdpn.NovaStationPinball.workshop"

    /// Every product whose ownership unlocks the Workshop. Identifiers are
    /// never removed from this set, so a past purchase always keeps working.
    static let entitlementProductIDs: Set<String> = [workshopProductID]

    /// Free tier, forever, for everyone: three rewinds per game.
    static let freeRewindsPerGame = 3
    /// Founders — players who already had the game before the Workshop
    /// existed — keep ten per game, for good.
    static let founderRewindsPerGame = 10

    /// Apple's standard EULA, used because the app ships no custom terms.
    static let termsOfUseURL = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    static let supportURL = "https://bnjdpn.github.io/NovaStationPinball/#contact"
    static let privacyURL = "https://bnjdpn.github.io/NovaStationPinball/privacy.html"
}

/// Fair grandfathering: a device that already played Nova Station before the
/// Workshop existed is flagged Founder, permanently, and gets a larger free
/// rewind allowance. It never takes anything away — a device that is not
/// detected simply keeps the standard free tier.
///
/// The signal is only ever READ here. It is a set of keys that the 1.0 build
/// wrote through `LocalGameStore`, plus the saved-game file. This check must
/// run before any service of the current launch writes to UserDefaults, which
/// `NovaStationPinballApp.init` guarantees.
enum LegacyEntitlement {
    enum Keys {
        static let founder = "NovaStation.founder"
        static let migrationCompleted = "NovaStation.founderMigrationCompleted"
    }

    /// Keys only a real earlier play session can have written. None of them is
    /// ever written by this type.
    static let usageSignalKeys: [String] = [
        "nova-station.high-scores",
        "nova-station.settings"
    ]

    /// Saved game left by an interrupted 1.0 session.
    static func legacyCheckpointURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("NovaStationPinball", isDirectory: true)
            .appendingPathComponent("active-checkpoint.json", isDirectory: false)
    }

    static func hasExistingUsageSignals(
        userDefaults: UserDefaults,
        checkpointExists: Bool
    ) -> Bool {
        checkpointExists || usageSignalKeys.contains { userDefaults.object(forKey: $0) != nil }
    }

    /// Runs exactly once per install, and is safe to call again at any time.
    /// A granted Founder flag is never cleared.
    static func migrateIfNeeded(
        userDefaults: UserDefaults = .standard,
        checkpointExists: @autoclosure () -> Bool = FileManager.default.fileExists(
            atPath: LegacyEntitlement.legacyCheckpointURL().path
        )
    ) {
        guard !userDefaults.bool(forKey: Keys.migrationCompleted) else { return }
        if hasExistingUsageSignals(
            userDefaults: userDefaults,
            checkpointExists: checkpointExists()
        ) {
            userDefaults.set(true, forKey: Keys.founder)
        }
        userDefaults.set(true, forKey: Keys.migrationCompleted)
    }

    static func isFounder(userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.bool(forKey: Keys.founder)
    }
}

/// Everything the paywall needs to display an offer, with no StoreKit type in
/// the view layer. Names and prices always come from `StoreKit.Product`.
struct WorkshopOffer: Sendable, Equatable {
    let productIdentifier: String
    let displayName: String
    let displayPrice: String
    let localizedDescription: String
}

enum WorkshopPurchaseOutcome: Sendable, Equatable {
    case purchased
    case pending
    case cancelled
    case unavailable
    case unverified
    case nothingToRestore
}

/// Seam between the observable store state and StoreKit 2, so unit tests can
/// drive entitlements, purchases and restores without a store.
protocol WorkshopStoreBackend: Sendable {
    func loadOffer() async -> WorkshopOffer?
    func ownedEntitlementProductIDs() async -> Set<String>
    func purchase() async -> WorkshopPurchaseOutcome
    func restore() async -> WorkshopPurchaseOutcome
    func transactionUpdates() -> AsyncStream<Void>
}

enum WorkshopStoreBackendFactory {
#if DEBUG
    static func applicationDefault(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> any WorkshopStoreBackend {
        if arguments.contains("-ui-testing"),
           environment["NOVA_STORE_FIXTURE"] == "available" {
            return UITestingWorkshopStoreBackend(
                languageCode: preferredLanguages.first ?? "en"
            )
        }
        return StoreKitWorkshopStoreBackend()
    }
#else
    /// The App Store build has no launch-argument or environment-controlled
    /// backend. Its only application default is the real StoreKit adapter.
    static func applicationDefault() -> any WorkshopStoreBackend {
        StoreKitWorkshopStoreBackend()
    }
#endif
}

struct NullWorkshopStoreBackend: WorkshopStoreBackend {
    func loadOffer() async -> WorkshopOffer? { nil }
    func ownedEntitlementProductIDs() async -> Set<String> { [] }
    func purchase() async -> WorkshopPurchaseOutcome { .unavailable }
    func restore() async -> WorkshopPurchaseOutcome { .nothingToRestore }
    func transactionUpdates() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

/// Shipping StoreKit 2 adapter.
struct StoreKitWorkshopStoreBackend: WorkshopStoreBackend {
    func loadOffer() async -> WorkshopOffer? {
        do {
            guard let product = try await Product.products(
                for: [WorkshopCatalog.workshopProductID]
            ).first else { return nil }
            return WorkshopOffer(
                productIdentifier: product.id,
                displayName: product.displayName,
                displayPrice: product.displayPrice,
                localizedDescription: product.description
            )
        } catch {
            return nil
        }
    }

    func ownedEntitlementProductIDs() async -> Set<String> {
        var owned: Set<String> = []
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  transaction.revocationDate == nil,
                  WorkshopCatalog.entitlementProductIDs.contains(transaction.productID)
            else { continue }
            owned.insert(transaction.productID)
        }
        return owned
    }

    func purchase() async -> WorkshopPurchaseOutcome {
        do {
            guard let product = try await Product.products(
                for: [WorkshopCatalog.workshopProductID]
            ).first else { return .unavailable }
            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    return .purchased
                case .unverified:
                    return .unverified
                }
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .unavailable
            }
        } catch {
            return .unavailable
        }
    }

    func restore() async -> WorkshopPurchaseOutcome {
        do {
            try await AppStore.sync()
            return await ownedEntitlementProductIDs().isEmpty ? .nothingToRestore : .purchased
        } catch {
            return .unavailable
        }
    }

    func transactionUpdates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .utility) {
                for await update in Transaction.updates {
                    if case .verified(let transaction) = update {
                        await transaction.finish()
                    }
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

#if DEBUG
/// Deterministic UI-test and review-capture data only. Shipping launches never
/// set both gates, so their names and prices always come from
/// `StoreKit.Product`.
struct UITestingWorkshopStoreBackend: WorkshopStoreBackend {
    let offer: WorkshopOffer

    init(languageCode: String) {
        let french = languageCode.hasPrefix("fr")
        offer = WorkshopOffer(
            productIdentifier: WorkshopCatalog.workshopProductID,
            displayName: french ? "L’Atelier" : "The Workshop",
            displayPrice: french ? "4,99 €" : "$4.99",
            localizedDescription: french
                ? "Rembobinage illimité et atelier de tir."
                : "Unlimited rewind and shot drills."
        )
    }

    func loadOffer() async -> WorkshopOffer? { offer }
    func ownedEntitlementProductIDs() async -> Set<String> { [] }
    func purchase() async -> WorkshopPurchaseOutcome { .purchased }
    func restore() async -> WorkshopPurchaseOutcome { .nothingToRestore }
    func transactionUpdates() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}
#endif

enum WorkshopLoadState: Equatable {
    case idle
    case loading
    case available
    case unavailable
}

@Observable
@MainActor
final class StoreService {
    private(set) var offer: WorkshopOffer?
    private(set) var ownedEntitlementProductIDs: Set<String> = []
    private(set) var loadState = WorkshopLoadState.idle
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var lastOutcome: WorkshopPurchaseOutcome?

    private let backend: any WorkshopStoreBackend
    private let userDefaults: UserDefaults
#if DEBUG
    private let bypassesStore: Bool
#endif
    @ObservationIgnored private var transactionUpdatesTask: Task<Void, Never>?

#if DEBUG
    /// UI tests and the screenshot pipeline exercise the Workshop past the
    /// free allowance, with no StoreKit dependency. The paywall capture is
    /// deliberately excluded: it must show the real locked paywall. This
    /// entire hook, including its launch-argument strings, is absent from a
    /// Release/App Store compilation.
    static func isStoreBypassEnabled(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        guard arguments.contains("-ui-testing") else { return false }
        guard !arguments.contains("-paywall-screenshot") else { return false }
        return true
    }

    init(
        backend: any WorkshopStoreBackend = WorkshopStoreBackendFactory.applicationDefault(),
        userDefaults: UserDefaults = .standard,
        bypassesStore: Bool = StoreService.isStoreBypassEnabled()
    ) {
        self.backend = backend
        self.userDefaults = userDefaults
        self.bypassesStore = bypassesStore
    }
#else
    init(
        backend: any WorkshopStoreBackend = WorkshopStoreBackendFactory.applicationDefault(),
        userDefaults: UserDefaults = .standard
    ) {
        self.backend = backend
        self.userDefaults = userDefaults
    }
#endif

    deinit {
        transactionUpdatesTask?.cancel()
    }

    // MARK: - Access

    /// Device-local Founder flag, read only. Never written by this type.
    var isFounder: Bool {
        LegacyEntitlement.isFounder(userDefaults: userDefaults)
    }

    var hasWorkshop: Bool {
#if DEBUG
        bypassesStore || !ownedEntitlementProductIDs.isEmpty
#else
        !ownedEntitlementProductIDs.isEmpty
#endif
    }

    /// Free rewinds granted for every single game, forever, with no purchase.
    var freeRewindsPerGame: Int {
        isFounder ? WorkshopCatalog.founderRewindsPerGame : WorkshopCatalog.freeRewindsPerGame
    }

    // MARK: - Lifecycle

    func start() {
        guard transactionUpdatesTask == nil else { return }
        transactionUpdatesTask = Task { [weak self] in
            guard let updates = self?.backend.transactionUpdates() else { return }
            for await _ in updates {
                await self?.refreshEntitlements()
            }
        }
        Task { await refreshEntitlements() }
    }

    func refreshEntitlements() async {
        ownedEntitlementProductIDs = await backend.ownedEntitlementProductIDs()
    }

    func loadOfferIfNeeded() async {
        // `.unavailable` is recoverable. The paywall copy asks the player to
        // check their connection and reopen the Workshop; reopening creates a
        // new paywall task and therefore retries this exact load. Available
        // and in-flight offers remain idempotent.
        guard loadState == .idle || loadState == .unavailable else { return }
        loadState = .loading
        offer = nil
        let loaded = await backend.loadOffer()
        offer = loaded
        loadState = loaded == nil ? .unavailable : .available
    }

    // MARK: - Purchase

    func purchase() async {
        guard !isPurchasing, offer != nil else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        let outcome = await backend.purchase()
        lastOutcome = outcome
        if outcome == .purchased {
            await refreshEntitlements()
        }
    }

    func restorePurchases() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        let outcome = await backend.restore()
        await refreshEntitlements()
        lastOutcome = ownedEntitlementProductIDs.isEmpty ? outcome : .purchased
    }
}
