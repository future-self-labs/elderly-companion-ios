import Foundation
import StoreKit

/// The one plan HelloNoah sells. Its display name lives only here, so the founder can rename it in one place.
enum Plan {
    /// Shown everywhere the plan is named (paywall, subscription screen, settings, wizard).
    static let displayName = "HelloNoah-abonnement"
    /// App Store product (auto-renewable, group "Noah"): intro €9,99 × 6 months, then €59,99 per month.
    static let productID = "ai.hellonoah.abonnement.maand"
    /// Fair use per month when the backend sends no `usage` (contract v2.1, `FAIR_USE_MONTHLY_MINUTES`).
    static let fairUseMonthlyMinutes = 600
    /// Conversation length once the monthly fair use is used up. Noah never cuts anyone off.
    static let cappedConversationMinutes = 10
}

/// StoreKit 2 flow for the HelloNoah-abonnement (one auto-renewable product, per elderly profile).
///
/// - `appAccountToken` is the elderly profile id, so the backend knows which profile was paid for.
/// - A transaction is only finished after `POST /subscriptions/app-store` accepted its JWS; if that
///   fails (no connection, server error) it stays unfinished and is retried from
///   `Transaction.unfinished`/`updates`. A definitive rejection (4xx) is finished, so it is not
///   re-delivered forever.
/// - One Apple ID can hold one subscription in group "Noah". Until product decides how a second
///   profile is paid, buying for another profile while one is active is blocked up front with a
///   clear explanation (StoreKit would otherwise return the existing transaction of the first
///   profile, which the backend rejects with `abonnement_ander_profiel`).
/// - Transactions without `appAccountToken` (offer codes, resubscribing from iOS Settings, Family
///   Sharing) can't be mapped to a profile. The backend learns about them through App Store Server
///   Notifications; they are finished once a profile of this caregiver shows an active App Store
///   subscription.
@MainActor
final class SubscriptionStore: ObservableObject {
    nonisolated static let productID = Plan.productID

    @Published private(set) var product: Product?
    @Published private(set) var isEligibleForIntro = true
    @Published private(set) var isPurchasing = false
    @Published private(set) var isLoadingProduct = false
    @Published var errorMessage: String?

    /// Sends a signed transaction to the backend. Set by the caregiver session.
    var submit: ((_ elderlyId: String, _ jws: String) async throws -> Subscription)?
    /// Known elderly ids, to map an `appAccountToken` back to the id casing the backend uses.
    var knownElderlyIds: [String] = []
    /// First names of the known profiles (to say for whom this Apple ID already pays).
    var knownElderlyNames: [String: String] = [:]
    /// Whether one of this caregiver's profiles has an active App Store subscription (used to
    /// finish transactions that carry no `appAccountToken`). Set by the caregiver session.
    var hasActiveAppStoreSubscription: (() async -> Bool)?
    /// Mock mode (Debug builds only): purchases are always simulated and real StoreKit
    /// transactions are never sent to, or finished against, the mock backend (audit H3/M9).
    var usesMockBackend = false

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
            #if DEBUG
            NSLog("[StoreKit] product load failed: %@", error.localizedDescription)
            #endif
        }
    }

    /// Buys the subscription for one elderly profile. Returns the backend subscription on success.
    func purchase(elderlyId: String) async -> Subscription? {
        errorMessage = nil
        #if DEBUG
        if usesMockBackend { return await demoPurchase(elderlyId: elderlyId) }
        #endif
        guard let product else {
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
        // One Apple ID, one subscription: never let StoreKit hand back another profile's purchase
        // as if it were a new payment.
        if let existing = await existingEntitlement(for: elderlyId), !existing.isForThisProfile {
            errorMessage = existing.explanation(for: knownElderlyNames[elderlyId.lowercased()])
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
        #if DEBUG
        if usesMockBackend {
            errorMessage = "Demo-modus: er worden geen echte aankopen hersteld."
            return 0
        }
        #endif
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

    /// An active HelloNoah-abonnement of this Apple ID.
    struct ExistingEntitlement: Equatable {
        /// The profile it was bought for (`appAccountToken`), nil when the transaction has none.
        let elderlyId: String?
        let elderlyName: String?
        let isForThisProfile: Bool

        /// Caregiver copy ("je") for the paywall.
        func explanation(for name: String?) -> String {
            let other = elderlyName.map { "voor \($0)" } ?? "voor een ander profiel"
            let target = name ?? "deze naaste"
            return "Met deze Apple ID betaal je al het \(Plan.displayName) \(other). Met één Apple ID kun je op dit moment voor één naaste betalen, dus een tweede abonnement voor \(target) kan nog niet. Er is niets afgeschreven."
        }
    }

    /// The current entitlement of this Apple ID, if any, seen from the profile on the paywall.
    func existingEntitlement(for elderlyId: String) async -> ExistingEntitlement? {
        #if DEBUG
        if usesMockBackend {
            // `-mockAppleIDPaysFor <elderlyId>` simulates an Apple ID that already pays for a profile.
            guard let paidFor = UserDefaults.standard.string(forKey: "mockAppleIDPaysFor")?.lowercased() else { return nil }
            return ExistingEntitlement(elderlyId: paidFor, elderlyName: knownElderlyNames[paidFor], isForThisProfile: paidFor == elderlyId.lowercased())
        }
        #endif
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.productID == Self.productID,
                  transaction.revocationDate == nil else { continue }
            if let expiry = transaction.expirationDate, expiry < Date() { continue }
            let token = transaction.appAccountToken?.uuidString.lowercased()
            return ExistingEntitlement(
                elderlyId: token,
                elderlyName: token.flatMap { knownElderlyNames[$0] },
                isForThisProfile: token == elderlyId.lowercased()
            )
        }
        return nil
    }

    #if DEBUG
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
    #endif

    private func redeem(_ transaction: Transaction, jws: String, elderlyId: String) async -> Subscription? {
        guard let submit else { return nil }
        do {
            let subscription = try await submit(elderlyId, jws)
            await transaction.finish()
            return subscription
        } catch {
            let apiError = APIError.from(error)
            #if DEBUG
            NSLog("[StoreKit] not redeemed: %@", String(describing: apiError))
            #endif
            let outcome = Self.redeemOutcome(for: apiError)
            if outcome.finish { await transaction.finish() }
            errorMessage = outcome.message
            return nil
        }
    }

    /// What to tell the caregiver when the backend did not accept a transaction, and whether the
    /// transaction is done with. Only a temporary problem keeps it for a retry — and only then
    /// is "betaling ontvangen, we activeren zodra er verbinding is" true.
    nonisolated static func redeemOutcome(for error: APIError) -> (message: String, finish: Bool) {
        switch error {
        case .offline, .unexpected, .decoding, .cancelled:
            return ("Betaling ontvangen. We activeren Noah zodra er weer verbinding is met HelloNoah.", false)
        case .server(let status, _, _) where status >= 500 || status == 429 || status == 408:
            return ("Betaling ontvangen. We activeren Noah zodra HelloNoah weer bereikbaar is.", false)
        case .sessionExpired, .server(401, _, _):
            return ("Log opnieuw in om je abonnement te activeren. Je betaling blijft bewaard.", false)
        case .server(_, "abonnement_ander_profiel", _):
            return ("Dit abonnement van je Apple ID hoort al bij een ander profiel. Met één Apple ID kun je op dit moment voor één naaste betalen. Er is niets extra afgeschreven.", true)
        case .server(_, "ongeldig_abonnement", _):
            return ("Deze aankoop kon niet worden gecontroleerd. Neem contact op met ons supportteam als er wel is afgeschreven.", true)
        case .server(let status, _, _) where (400..<500).contains(status):
            return (error.userMessage, true)
        default:
            return (error.userMessage, false)
        }
    }

    private func elderlyId(for transaction: Transaction) -> String? {
        guard let token = transaction.appAccountToken?.uuidString else { return nil }
        return knownElderlyIds.first { $0.caseInsensitiveCompare(token) == .orderedSame } ?? token.lowercased()
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        // Real transactions stay unfinished until the real backend has them.
        guard !usesMockBackend else { return }
        guard case .verified(let transaction) = result, transaction.productID == Self.productID else { return }
        if transaction.revocationDate != nil {
            await transaction.finish()
            return
        }
        guard let elderlyId = elderlyId(for: transaction) else {
            // No profile id on it (offer code, resubscribed in iOS Settings, Family Sharing): the
            // backend links it through App Store Server Notifications. Finish it once it shows up.
            if let check = hasActiveAppStoreSubscription, await check() { await transaction.finish() }
            return
        }
        _ = await redeem(transaction, jws: result.jwsRepresentation, elderlyId: elderlyId)
    }
}
