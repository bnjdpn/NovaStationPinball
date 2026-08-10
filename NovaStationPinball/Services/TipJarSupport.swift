import Foundation
import StoreKit

struct TipDefinition: Sendable, Equatable {
    let id: String
    let productIdentifier: String
}

enum TipJarCatalog {
    static let tips = [
        TipDefinition(id: "tip.cafe", productIdentifier: "com.bnjdpn.NovaStationPinball.tip.cafe"),
        TipDefinition(id: "tip.merci", productIdentifier: "com.bnjdpn.NovaStationPinball.tip.merci"),
        TipDefinition(id: "tip.soutien", productIdentifier: "com.bnjdpn.NovaStationPinball.tip.soutien")
    ]
    static let isOptional = true
    static let grantsGameplayContent = false
}

struct AvailableTip: Sendable, Equatable {
    let definition: TipDefinition
    let displayName: String
    let displayPrice: String
}

enum TipPurchaseOutcome: Sendable, Equatable {
    case purchased
    case pending
    case cancelled
    case unavailable
    case unverified
}

protocol TipJarSupport: Sendable {
    func availableTips() async -> [AvailableTip]
    func purchase(productIdentifier: String) async -> TipPurchaseOutcome
}

enum TipJarSupportFactory {
    static func applicationDefault(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> any TipJarSupport {
#if DEBUG
        if arguments.contains("-ui-testing"),
           environment["NOVA_TIP_JAR_FIXTURE"] == "available" {
            return UITestingTipJarSupport(
                languageCode: preferredLanguages.first ?? "en"
            )
        }
#endif
        return StoreKitTipJarSupport()
    }
}

struct NullTipJarSupport: TipJarSupport {
    func availableTips() async -> [AvailableTip] { [] }
    func purchase(productIdentifier: String) async -> TipPurchaseOutcome { .unavailable }
}

protocol TipTransactionFinishing: Sendable {
    var productIdentifier: String { get }
    func finish() async
}

typealias TipTransactionUpdates = AsyncStream<any TipTransactionFinishing>

private struct StoreKitTipTransaction: TipTransactionFinishing {
    let transaction: Transaction

    var productIdentifier: String { transaction.productID }

    func finish() async {
        await transaction.finish()
    }
}

private func verifiedStoreKitTipTransactionUpdates() -> TipTransactionUpdates {
    AsyncStream { continuation in
        let task = Task.detached(priority: .utility) {
            for await result in Transaction.unfinished {
                guard case .verified(let transaction) = result else { continue }
                continuation.yield(StoreKitTipTransaction(transaction: transaction))
            }
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                continuation.yield(StoreKitTipTransaction(transaction: transaction))
            }
            continuation.finish()
        }
        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
    }
}

actor StoreKitTipJarSupport: TipJarSupport {
    private let transactionUpdatesTask: Task<Void, Never>

    init() {
        self.init(transactionUpdates: verifiedStoreKitTipTransactionUpdates)
    }

    init(transactionUpdates: @escaping @Sendable () -> TipTransactionUpdates) {
        let knownProductIdentifiers = Set(TipJarCatalog.tips.map(\.productIdentifier))
        transactionUpdatesTask = Task.detached(priority: .utility) {
            for await transaction in transactionUpdates() {
                guard !Task.isCancelled else { break }
                guard knownProductIdentifiers.contains(transaction.productIdentifier) else { continue }
                await transaction.finish()
            }
        }
    }

    deinit {
        transactionUpdatesTask.cancel()
    }

    func availableTips() async -> [AvailableTip] {
        let definitionsByIdentifier = Dictionary(
            uniqueKeysWithValues: TipJarCatalog.tips.map { ($0.productIdentifier, $0) }
        )
        do {
            let products = try await Product.products(for: Array(definitionsByIdentifier.keys))
            return products.compactMap { product in
                definitionsByIdentifier[product.id].map {
                    AvailableTip(definition: $0, displayName: product.displayName, displayPrice: product.displayPrice)
                }
            }.sorted { $0.definition.id < $1.definition.id }
        } catch {
            return []
        }
    }

    func purchase(productIdentifier: String) async -> TipPurchaseOutcome {
        guard TipJarCatalog.tips.contains(where: { $0.productIdentifier == productIdentifier }) else {
            return .unavailable
        }
        do {
            guard let product = try await Product.products(for: [productIdentifier]).first else {
                return .unavailable
            }
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
}

#if DEBUG
/// Deterministic UI-test data only. Production and media launches never set
/// both gates, so their names and prices always come from StoreKit.Product.
actor UITestingTipJarSupport: TipJarSupport {
    private let tips: [AvailableTip]

    init(languageCode: String) {
        let french = languageCode.hasPrefix("fr")
        tips = [
            AvailableTip(
                definition: TipJarCatalog.tips[0],
                displayName: french ? "Café" : "Coffee",
                displayPrice: french ? "0,99 €" : "$0.99"
            ),
            AvailableTip(
                definition: TipJarCatalog.tips[1],
                displayName: french ? "Grand merci" : "Big thanks",
                displayPrice: french ? "2,99 €" : "$2.99"
            ),
            AvailableTip(
                definition: TipJarCatalog.tips[2],
                displayName: french ? "Beau soutien" : "Strong support",
                displayPrice: french ? "5,99 €" : "$5.99"
            )
        ]
    }

    func availableTips() async -> [AvailableTip] { tips }

    func purchase(productIdentifier: String) async -> TipPurchaseOutcome {
        TipJarCatalog.tips.contains(where: { $0.productIdentifier == productIdentifier })
            ? .purchased
            : .unavailable
    }
}
#endif
