import Foundation
import StoreKit

/// StoreKit 2 flow for Noah Unlimited (one auto-renewable product, per elderly profile).
///
/// - `appAccountToken` is the elderly profile id, so the backend knows which profile was paid for.
/// - A transaction is only finished after `POST /subscriptions/app-store` accepted its JWS; if that
///   fails (no connection) it stays unfinished and is retried from `Transaction.unfinished`/`updates`.
@MainActor
final class SubscriptionStore: ObservableObject {
    nonisolated static let productID = "ai.hellonoah.unlimited.monthly"

    @Published private(set) var product: Product?
    @Published private(set) var isEligibleForIntro = true
    @Published private(set) var isPurchasing = false
    @Published private(set) var isLoadingProduct = false
    @Published var errorMessage: String?

    /// Sends a signed transaction to the backend. Set by the caregiver session.
    var submit: ((_ elderlyId: String, _ jws: String) async throws -> Subscription)?
    /// Known elderly ids, to map an `appAccountToken` back to the id casing the backend uses.
    var knownElderlyIds: [String] = []
    /// Mock mode without a StoreKit configuration (e.g. launched from the command line).
    var allowsDemoPurchase = false

    private var updatesTask: Task<Void, Never>?

    // Offline fallbacks; the App Store's localized prices win as soon as the product loads.
    static let fallbackIntroPrice = "€ 9,99"
    static let fallbackRegularPrice = "€ 59,99"
    static let introMonths = 6

    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task {
            await loadProduct()
            for await result in Transaction.unfinished { await handle(result) }
        }
    }

    var introPriceText: String {
        product?.subscription?.introductoryOffer?.displayPrice ?? Self.fallbackIntroPrice
    }

    var regularPriceText: String {
        product?.displayPrice ?? Self.fallbackRegularPrice
    }

    var introPeriodCount: Int {
        guard let offer = product?.subscription?.introductoryOffer else { return Self.introMonths }
        return offer.periodCount * (offer.period.unit == .month ? offer.period.value : 1)
    }

    func loadProduct() async {
        guard product == nil else { return }
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            product = try await Product.products(for: [Self.productID]).first
            if let subscription = product?.subscription {
                isEligibleForIntro = await subscription.isEligibleForIntroOffer
            }
        } catch {
            NSLog("[StoreKit] product load failed: %@", error.localizedDescription)
        }
    }

    /// Buys Noah Unlimited for one elderly profile. Returns the backend subscription on success.
    func purchase(elderlyId: String) async -> Subscription? {
        errorMessage = nil
        guard let product else {
            if allowsDemoPurchase { return await demoPurchase(elderlyId: elderlyId) }
            await loadProduct()
            if self.product == nil {
                errorMessage = "Het abonnement kan nu niet worden geladen. Controleer je internetverbinding en probeer het opnieuw."
                return nil
            }
            return await purchase(elderlyId: elderlyId)
        }
        guard let token = UUID(uuidString: elderlyId) else {
            errorMessage = "Dit profiel kan niet worden gekoppeld aan een abonnement."
            return nil
        }

        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase(options: [.appAccountToken(token)]) {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    errorMessage = "De aankoop kon niet worden gecontroleerd. Probeer het opnieuw."
                    return nil
                }
                return await redeem(transaction, jws: verification.jwsRepresentation, elderlyId: elderlyId)
            case .userCancelled:
                return nil
            case .pending:
                errorMessage = "De aankoop wacht op goedkeuring (bijvoorbeeld via Delen met gezin). Je krijgt bericht zodra hij rond is."
                return nil
            @unknown default:
                return nil
            }
        } catch {
            errorMessage = "De aankoop is niet gelukt: \(error.localizedDescription)"
            return nil
        }
    }

    /// Restores purchases and re-sends every current entitlement to the backend.
    func restore() async -> Int {
        errorMessage = nil
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = "Herstellen is niet gelukt. Controleer of je bent ingelogd met je Apple ID."
            return 0
        }
        var restored = 0
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.productID == Self.productID,
                  let elderlyId = elderlyId(for: transaction) else { continue }
            if await redeem(transaction, jws: result.jwsRepresentation, elderlyId: elderlyId) != nil { restored += 1 }
        }
        if restored == 0, errorMessage == nil {
            errorMessage = "Er is geen actief abonnement gevonden voor deze Apple ID."
        }
        return restored
    }

    private func demoPurchase(elderlyId: String) async -> Subscription? {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            return try await submit?(elderlyId, "mock-signed-transaction")
        } catch {
            errorMessage = APIError.from(error).userMessage
            return nil
        }
    }

    private func redeem(_ transaction: Transaction, jws: String, elderlyId: String) async -> Subscription? {
        guard let submit else { return nil }
        do {
            let subscription = try await submit(elderlyId, jws)
            await transaction.finish()
            return subscription
        } catch {
            NSLog("[StoreKit] not redeemed yet: %@", error.localizedDescription)
            errorMessage = "Betaling ontvangen. We activeren Noah zodra er verbinding is met HelloNoah."
            return nil
        }
    }

    private func elderlyId(for transaction: Transaction) -> String? {
        guard let token = transaction.appAccountToken?.uuidString else { return nil }
        return knownElderlyIds.first { $0.caseInsensitiveCompare(token) == .orderedSame } ?? token.lowercased()
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result, transaction.productID == Self.productID else { return }
        if transaction.revocationDate != nil {
            await transaction.finish()
            return
        }
        guard let elderlyId = elderlyId(for: transaction) else { return }
        _ = await redeem(transaction, jws: result.jwsRepresentation, elderlyId: elderlyId)
    }
}
