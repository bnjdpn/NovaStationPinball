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

struct NullTipJarSupport: TipJarSupport {
    func availableTips() async -> [AvailableTip] { [] }
    func purchase(productIdentifier: String) async -> TipPurchaseOutcome { .unavailable }
}

actor StoreKitTipJarSupport: TipJarSupport {
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
