import Foundation
import StoreKit

/// The one plan HelloNoah sells. Its display name lives only here, so the founder can rename it in one place.
enum Plan {
    /// Shown everywhere the plan is named (paywall, subscription screen, settings, wizard).
    static let displayName = "HelloNoah-abonnement"
    /// v2.3: three identical App Store products (same price, same intro offer: €9,99 × 6 months,
    /// then €59,99 per month), each in its own subscription group ("Noah", "Noah 2", "Noah 3"), so
    /// one Apple ID can pay for up to three profiles. The app buys the first one this Apple ID does
    /// not own yet.
    static let productIDs = [
        "ai.hellonoah.abonnement.maand",
        "ai.hellonoah.abonnement.maand.2",
        "ai.hellonoah.abonnement.maand.3",
    ]
    /// The first product (group "Noah").
    static let productID = productIDs[0]
    /// At most this many HelloNoah-abonnementen per Apple ID (one per group).
    static var maxPerAppleID: Int { productIDs.count }
    /// Fair use per month when the backend sends no `usage` (contract v2.1, `FAIR_USE_MONTHLY_MINUTES`).
    static let fairUseMonthlyMinutes = 600
    /// Conversation length once the monthly fair use is used up. Noah never cuts anyone off.
    static let cappedConversationMinutes = 10

    static func isPlanProduct(_ productID: String) -> Bool { productIDs.contains(productID) }
}

/// A HelloNoah-abonnement this Apple ID currently pays for.
struct OwnedSubscription: Equatable, Hashable {
    let productID: String
    /// The profile it was bought for (`appAccountToken`), nil when the transaction has none.
    let elderlyId: String?
}

/// Which product the paywall offers for one profile (v2.3).
enum ProductChoice: Equatable {
    /// The first product this Apple ID doesn't own yet.
    case buy(productID: String)
    /// This Apple ID already pays for this very profile: restore instead of buying.
    case alreadyForThisProfile(productID: String)
    /// All products are in use (a 4th profile on the same Apple ID).
    case allInUse(owned: [OwnedSubscription])

    static func choose(owned: [OwnedSubscription], elderlyId: String, productIDs: [String] = Plan.productIDs) -> ProductChoice {
        let target = elderlyId.lowercased()
        let planOwned = owned.filter { productIDs.contains($0.productID) }
        if let mine = planOwned.first(where: { $0.elderlyId?.lowercased() == target }) {
            return .alreadyForThisProfile(productID: mine.productID)
        }
        let taken = Set(planOwned.map(\.productID))
        if let free = productIDs.first(where: { !taken.contains($0) }) {
            return .buy(productID: free)
        }
        return .allInUse(owned: planOwned)
    }

    var productID: String? {
        switch self {
        case .buy(let id), .alreadyForThisProfile(let id): return id
        case .allInUse: return nil
        }
    }
}

/// StoreKit 2 flow for the HelloNoah-abonnement (per elderly profile).
///
/// - `appAccountToken` is the elderly profile id, so the backend knows which profile was paid for.
/// - v2.3: one Apple ID can pay for up to three profiles: every profile gets the first of the
///   three identical products (separate subscription groups) that this Apple ID doesn't own yet
///   (`Transaction.currentEntitlements`). A fourth gets a clear explanation, never a purchase.
/// - A transaction is only finished after the backend accepted its JWS (caregiver:
///   `POST /subscriptions/app-store`, older person: `POST /device/subscriptions/app-store`); if that
///   fails (no connection, server error) it stays unfinished and is retried from
///   `Transaction.unfinished`/`updates`. A definitive rejection (4xx) is finished, so it is not
///   re-delivered forever.
/// - Transactions without `appAccountToken` (offer codes, resubscribing from iOS Settings, Family
///   Sharing) can't be mapped to a profile. The backend learns about them through App Store Server
///   Notifications; they are finished once a profile shows an active App Store subscription.
@MainActor
final class SubscriptionStore: ObservableObject {
    nonisolated static let productID = Plan.productID

    /// Who reads the store's messages: the caregiver ("je") or the older person ("u").
    enum Audience { case caregiver, elder }

    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var introEligibility: [String: Bool] = [:]
    @Published private(set) var isPurchasing = false
    @Published private(set) var isLoadingProduct = false
    @Published var errorMessage: String?

    /// Sends a signed transaction to the backend. Set by the caregiver or older person's session.
    var submit: ((_ elderlyId: String, _ jws: String) async throws -> Subscription)?
    /// Known elderly ids, to map an `appAccountToken` back to the id casing the backend uses.
    var knownElderlyIds: [String] = []
    /// First names of the known profiles (to say for whom this Apple ID already pays).
    var knownElderlyNames: [String: String] = [:]
    /// Only redeem transactions of `knownElderlyIds` and leave others alone (the older person's
    /// phone: the same Apple ID may pay for other people elsewhere; those are not ours to finish).
    var redeemsOnlyKnownProfiles = false
    /// Whether one of the session's profiles has an active App Store subscription (used to finish
    /// transactions that carry no `appAccountToken`). Set by the session.
    var hasActiveAppStoreSubscription: (() async -> Bool)?
    var audience: Audience = .caregiver
    /// Mock mode (Debug builds only): purchases are always simulated and real StoreKit
    /// transactions are never sent to, or finished against, the mock backend (audit H3/M9).
    var usesMockBackend = false

    private var updatesTask: Task<Void, Never>?
    #if DEBUG
    /// Mock mode: what this (pretend) Apple ID owns. Seeded from `-mockAppleIDPaysFor id1,id2,…`
    /// (one product per id, in order) and extended by simulated purchases.
    private(set) var demoOwned: [OwnedSubscription] = []
    #endif

    // Offline fallbacks; the App Store's localized prices win as soon as the product loads.
    static let fallbackIntroPrice = "€ 9,99"
    static let fallbackRegularPrice = "€ 59,99"
    static let introMonths = 6

    func start() {
        #if DEBUG
        if usesMockBackend { seedDemoOwnership() }
        #endif
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task {
            await loadProducts()
            for await result in Transaction.unfinished { await handle(result) }
        }
    }

    // MARK: Prices (all three products have the same price and intro offer)

    private func product(_ productID: String?) -> Product? {
        products[productID ?? Plan.productID] ?? products[Plan.productID] ?? products.values.first
    }

    func introPriceText(for productID: String? = nil) -> String {
        product(productID)?.subscription?.introductoryOffer?.displayPrice ?? Self.fallbackIntroPrice
    }

    func regularPriceText(for productID: String? = nil) -> String {
        product(productID)?.displayPrice ?? Self.fallbackRegularPrice
    }

    func introPeriodCount(for productID: String? = nil) -> Int {
        guard let offer = product(productID)?.subscription?.introductoryOffer else { return Self.introMonths }
        return offer.periodCount * (offer.period.unit == .month ? offer.period.value : 1)
    }

    /// Intro eligibility is per subscription group, so every new group gets the intro offer again.
    func isEligibleForIntro(_ productID: String? = nil) -> Bool {
        introEligibility[productID ?? Plan.productID] ?? true
    }

    func loadProducts() async {
        guard products.count < Plan.productIDs.count else { return }
        #if DEBUG
        if usesMockBackend { return }
        #endif
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            let loaded = try await Product.products(for: Plan.productIDs)
            for product in loaded {
                products[product.id] = product
                if let subscription = product.subscription {
                    introEligibility[product.id] = await subscription.isEligibleForIntroOffer
                }
            }
        } catch {
            #if DEBUG
            NSLog("[StoreKit] product load failed: %@", error.localizedDescription)
            #endif
        }
    }

    // MARK: Which product

    /// The HelloNoah-abonnementen this Apple ID currently pays for.
    func ownedSubscriptions() async -> [OwnedSubscription] {
        #if DEBUG
        if usesMockBackend { return demoOwned }
        #endif
        var owned: [OwnedSubscription] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, Plan.isPlanProduct(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            if let expiry = transaction.expirationDate, expiry < Date() { continue }
            owned.append(OwnedSubscription(productID: transaction.productID,
                                           elderlyId: transaction.appAccountToken?.uuidString.lowercased()))
        }
        return owned
    }

    /// What the paywall can offer for this profile.
    func choice(for elderlyId: String) async -> ProductChoice {
        ProductChoice.choose(owned: await ownedSubscriptions(), elderlyId: elderlyId)
    }

    // MARK: Buying

    /// Buys the subscription for one elderly profile with the first product this Apple ID doesn't
    /// own yet. Returns the backend subscription on success.
    func purchase(elderlyId: String) async -> Subscription? {
        errorMessage = nil
        let choice = await choice(for: elderlyId)
        let productID: String
        switch choice {
        case .buy(let id):
            productID = id
        case .alreadyForThisProfile:
            errorMessage = text(
                "Met deze Apple ID loopt het \(Plan.displayName) voor dit profiel al. Tik op Aankopen herstellen om het te activeren. Er wordt niets extra afgeschreven.",
                "Met deze Apple ID loopt uw \(Plan.displayName) al. Tik op Aankopen herstellen om het te activeren. Er wordt niets extra afgeschreven.")
            return nil
        case .allInUse(let owned):
            errorMessage = allInUseExplanation(owned: owned, targetName: knownElderlyNames[elderlyId.lowercased()])
            return nil
        }

        #if DEBUG
        if usesMockBackend { return await demoPurchase(elderlyId: elderlyId, productID: productID) }
        #endif
        if products[productID] == nil { await loadProducts() }
        guard let product = products[productID] else {
            errorMessage = text(
                "Het abonnement kan nu niet worden geladen. Controleer je internetverbinding en probeer het opnieuw.",
                "Het abonnement kan nu niet worden geladen. Kijkt u of er internet is en probeert u het nog eens.")
            return nil
        }
        guard let token = UUID(uuidString: elderlyId) else {
            errorMessage = text("Dit profiel kan niet worden gekoppeld aan een abonnement.", "Dit account kan niet worden gekoppeld aan een abonnement.")
            return nil
        }

        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase(options: [.appAccountToken(token)]) {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    errorMessage = text("De aankoop kon niet worden gecontroleerd. Probeer het opnieuw.", "De aankoop kon niet worden gecontroleerd. Probeert u het nog eens.")
                    return nil
                }
                return await redeem(transaction, jws: verification.jwsRepresentation, elderlyId: elderlyId)
            case .userCancelled:
                return nil
            case .pending:
                errorMessage = text(
                    "De aankoop wacht op goedkeuring (bijvoorbeeld via Delen met gezin). Je krijgt bericht zodra hij rond is.",
                    "De aankoop wacht nog op goedkeuring (bijvoorbeeld via Delen met gezin). Zodra hij rond is, wordt Noah actief.")
                return nil
            @unknown default:
                return nil
            }
        } catch {
            errorMessage = text("De aankoop is niet gelukt: \(error.localizedDescription)", "De aankoop is niet gelukt. Probeert u het nog eens.")
            return nil
        }
    }

    /// Restores purchases and re-sends every current entitlement of a known profile to the backend.
    func restore() async -> Int {
        errorMessage = nil
        #if DEBUG
        if usesMockBackend { return await demoRestore() }
        #endif
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = text("Herstellen is niet gelukt. Controleer of je bent ingelogd met je Apple ID.", "Herstellen is niet gelukt. Kijkt u of u bent ingelogd met uw Apple ID.")
            return 0
        }
        var restored = 0
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, Plan.isPlanProduct(transaction.productID),
                  let elderlyId = elderlyId(for: transaction) else { continue }
            if await redeem(transaction, jws: result.jwsRepresentation, elderlyId: elderlyId) != nil { restored += 1 }
        }
        if restored == 0, errorMessage == nil {
            errorMessage = text("Er is geen actief abonnement gevonden voor deze Apple ID.", "Er is geen abonnement gevonden bij deze Apple ID.")
        }
        return restored
    }

    // MARK: Copy

    private func text(_ caregiver: String, _ elder: String) -> String {
        audience == .elder ? elder : caregiver
    }

    /// "Wim, Riet en een ander profiel".
    func ownedDescription(_ owned: [OwnedSubscription]) -> String {
        let names = owned.compactMap { $0.elderlyId.flatMap { knownElderlyNames[$0.lowercased()] } }
        let unknown = owned.count - names.count
        var parts = names
        if unknown == 1 { parts.append(names.isEmpty ? "één profiel" : "een ander profiel") }
        if unknown > 1 { parts.append(names.isEmpty ? "\(unknown) profielen" : "\(unknown) andere profielen") }
        return DutchList.join(parts)
    }

    /// The fourth profile on one Apple ID (v2.3): explained, never sold.
    func allInUseExplanation(owned: [OwnedSubscription], targetName: String?) -> String {
        let max = Plan.maxPerAppleID
        switch audience {
        case .caregiver:
            let target = targetName ?? "deze naaste"
            return "Met deze Apple ID betaal je al \(max) abonnementen, voor \(ownedDescription(owned)). Meer dan \(max) abonnementen per Apple ID kan niet, dus voor \(target) kan er met deze Apple ID geen abonnement bij. Er is niets afgeschreven."
        case .elder:
            return "Met deze Apple ID worden al \(max) abonnementen betaald. Meer dan \(max) kan niet met één Apple ID, dus er kan er nu geen bij. Er is niets afgeschreven."
        }
    }

    // MARK: Mock (Debug only)

    #if DEBUG
    private func seedDemoOwnership() {
        guard demoOwned.isEmpty, let raw = UserDefaults.standard.string(forKey: "mockAppleIDPaysFor") else { return }
        let ids = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        demoOwned = zip(Plan.productIDs, ids).map { OwnedSubscription(productID: $0, elderlyId: $1) }
    }

    /// Never StoreKit: the mock backend gets a fake JWS that names the product.
    private func demoPurchase(elderlyId: String, productID: String) async -> Subscription? {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let subscription = try await submit?(elderlyId, "mock-signed-transaction:\(productID)")
            if subscription != nil { demoOwned.append(OwnedSubscription(productID: productID, elderlyId: elderlyId.lowercased())) }
            return subscription
        } catch {
            errorMessage = audience == .elder ? APIError.from(error).elderMessage : APIError.from(error).userMessage
            return nil
        }
    }

    private func demoRestore() async -> Int {
        var restored = 0
        for owned in demoOwned {
            guard let elderlyId = owned.elderlyId,
                  let known = knownElderlyIds.first(where: { $0.caseInsensitiveCompare(elderlyId) == .orderedSame }) else { continue }
            if (try? await submit?(known, "mock-signed-transaction:\(owned.productID)")) != nil { restored += 1 }
        }
        if restored == 0 {
            errorMessage = text("Demo-modus: er is niets om te herstellen.", "Demo-modus: er is niets om te herstellen.")
        }
        return restored
    }
    #endif

    // MARK: Backend

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
            let outcome = Self.redeemOutcome(for: apiError, formal: audience == .elder)
            if outcome.finish { await transaction.finish() }
            errorMessage = outcome.message
            return nil
        }
    }

    /// What to tell the reader when the backend did not accept a transaction, and whether the
    /// transaction is done with. Only a temporary problem keeps it for a retry — and only then
    /// is "betaling ontvangen, we activeren zodra er verbinding is" true.
    nonisolated static func redeemOutcome(for error: APIError, formal: Bool = false) -> (message: String, finish: Bool) {
        func pick(_ caregiver: String, _ elder: String) -> String { formal ? elder : caregiver }
        switch error {
        case .offline, .unexpected, .decoding, .cancelled:
            return (pick("Betaling ontvangen. We activeren Noah zodra er weer verbinding is met HelloNoah.",
                         "Betaling ontvangen. Noah wordt actief zodra er weer internet is."), false)
        case .server(let status, _, _) where status >= 500 || status == 429 || status == 408:
            return (pick("Betaling ontvangen. We activeren Noah zodra HelloNoah weer bereikbaar is.",
                         "Betaling ontvangen. Noah wordt actief zodra HelloNoah weer bereikbaar is."), false)
        case .sessionExpired, .server(401, _, _):
            return (pick("Log opnieuw in om je abonnement te activeren. Je betaling blijft bewaard.",
                         "Uw betaling is bewaard, maar kon nog niet worden gekoppeld. Probeert u het later nog eens."), false)
        case .server(_, "abonnement_ander_profiel", _):
            return (pick("Dit abonnement van je Apple ID hoort al bij een ander profiel. Er is niets extra afgeschreven.",
                         "Dit abonnement van uw Apple ID hoort al bij iemand anders. Er is niets extra afgeschreven."), true)
        case .server(_, "ongeldig_abonnement", _):
            return (pick("Deze aankoop kon niet worden gecontroleerd. Neem contact op met ons supportteam als er wel is afgeschreven.",
                         "Deze aankoop kon niet worden gecontroleerd. Neemt u contact met ons op als er wel geld is afgeschreven."), true)
        case .server(let status, _, _) where (400..<500).contains(status):
            return (formal ? error.elderMessage : error.userMessage, true)
        default:
            return (formal ? error.elderMessage : error.userMessage, false)
        }
    }

    private func elderlyId(for transaction: Transaction) -> String? {
        guard let token = transaction.appAccountToken?.uuidString else { return nil }
        if let known = knownElderlyIds.first(where: { $0.caseInsensitiveCompare(token) == .orderedSame }) { return known }
        return redeemsOnlyKnownProfiles ? nil : token.lowercased()
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        // Real transactions stay unfinished until the real backend has them.
        guard !usesMockBackend else { return }
        guard case .verified(let transaction) = result, Plan.isPlanProduct(transaction.productID) else { return }
        if transaction.revocationDate != nil {
            await transaction.finish()
            return
        }
        guard let elderlyId = elderlyId(for: transaction) else {
            // Another profile's purchase on the older person's phone: not ours to finish.
            if redeemsOnlyKnownProfiles, transaction.appAccountToken != nil { return }
            // No profile id on it (offer code, resubscribed in iOS Settings, Family Sharing): the
            // backend links it through App Store Server Notifications. Finish it once it shows up.
            if let check = hasActiveAppStoreSubscription, await check() { await transaction.finish() }
            return
        }
        _ = await redeem(transaction, jws: result.jwsRepresentation, elderlyId: elderlyId)
    }
}
