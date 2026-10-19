import StoreKit
import SwiftUI

/// The older person's own paywall (v2.3 self route), in "u": the same HelloNoah-abonnement at the
/// same price (intro €9,99 × 6 months, then €59,99), fair use explained kindly, restore, the App
/// Store disclosures. The free first conversation lets them try Noah before paying.
struct ElderPaywallView: View {
    /// Onboarding: "Eerst gratis proberen" finishes the sign-up without paying.
    var showsTryFirst = false
    /// Shown inside the onboarding (step header) or on its own (settings).
    var step: (number: Int, total: Int)?
    /// Paid: the onboarding hides its back button.
    var onActivated: (() -> Void)?
    let onDone: () -> Void

    @EnvironmentObject private var session: ElderSession
    @EnvironmentObject private var store: SubscriptionStore
    @EnvironmentObject private var app: AppModel
    @State private var subscription: Subscription?
    @State private var choice: ProductChoice?
    @State private var activated = false
    @State private var localError: String?

    private var productID: String? { choice?.productID }
    private var freeLeft: Int {
        guard let subscription, !subscription.isPaidOrBeta else { return 0 }
        return subscription.freeConversationsLeft ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            if activated {
                successView
            } else {
                offerView
            }
        }
        .task { await prepare() }
    }

    private func prepare() async {
        store.errorMessage = nil
        if session.elderlyId == nil || !session.isSelfManaged { await session.load() }
        async let products: Void = store.loadProducts()
        subscription = try? await session.api.deviceSubscription()
        if let id = session.elderlyId { choice = await store.choice(for: id) }
        await products
    }

    // MARK: Parts

    private var successView: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundColor(NoahColor.positive)
                .accessibilityHidden(true)
            ElderScreenTitle(title: "Noah is actief")
            ElderText("Dank u wel. U kunt nu met \(session.noahName) praten wanneer u maar wilt.")
            Button("Verder", action: onDone)
                .buttonStyle(.noah(.primary, size: .elder))
                .accessibilityIdentifier("elderPaywall.done")
        }
    }

    private var offerView: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            if let step {
                ElderStepHeader(step: step.number, total: step.total, title: "Uw abonnement")
            } else {
                ElderScreenTitle(title: "Uw abonnement")
            }

            HStack(spacing: NoahSpacing.s) {
                NoahOrb(activity: .idle, diameter: 40).frame(width: 54, height: 54)
                Text(verbatim: Plan.displayName)
                    .font(NoahFont.Elder.title2).noahElderTitleScaling()
                    .foregroundColor(NoahColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if freeLeft > 0 {
                NoahNotice(kind: .success, text: freeLeft == 1
                    ? "Uw eerste gesprek met Noah is gratis. Zo kunt u Noah eerst rustig leren kennen, voordat u iets betaalt."
                    : "Uw eerste \(freeLeft) gesprekken met Noah zijn gratis. Zo kunt u Noah eerst rustig leren kennen, voordat u iets betaalt.",
                    large: true)
                    .accessibilityIdentifier("elderPaywall.free")
            }

            NoahCard(padding: NoahSpacing.l) {
                if store.isEligibleForIntro(productID) {
                    Text(verbatim: "\(store.introPriceText(for: productID)) per maand")
                        .font(NoahFont.display(40, relativeTo: .largeTitle)).noahElderTitleScaling()
                        .foregroundColor(NoahColor.text)
                    ElderText("de eerste \(store.introPeriodCount(for: productID)) maanden. Daarna \(store.regularPriceText(for: productID)) per maand.")
                } else {
                    Text(verbatim: "\(store.regularPriceText(for: productID)) per maand")
                        .font(NoahFont.display(40, relativeTo: .largeTitle)).noahElderTitleScaling()
                        .foregroundColor(NoahColor.text)
                }
                ElderText("Elke maand opzegbaar.", color: NoahColor.textSecondary)
            }

            NoahCard(padding: NoahSpacing.l) {
                Label {
                    Text("Redelijk gebruik").font(NoahFont.Elder.bodyStrong).foregroundColor(NoahColor.text)
                } icon: {
                    Image(systemName: "clock.fill").foregroundColor(NoahColor.accent)
                }
                ElderText(ProductCopy.elderFairUse(allowanceMinutes: Int(subscription?.usage?.allowanceMinutes ?? Double(Plan.fairUseMonthlyMinutes))))
                    .accessibilityIdentifier("elderPaywall.fairUse")
            }

            VStack(alignment: .leading, spacing: NoahSpacing.s) {
                feature("Met Noah praten in de app, wanneer u maar wilt")
                feature("Noah onthoudt wat u vertelt en vraagt er later naar")
                feature("Uw levensverhaal, om terug te lezen of door te geven")
                feature("Een extra geheugensteuntje voor afspraken en verjaardagen")
                feature("Familie kan meekijken als u dat wilt")
            }

            purchaseArea

            #if DEBUG
            if app.isMock {
                Text("Demo-modus: de aankoop wordt gesimuleerd, er wordt niets afgeschreven.")
                    .font(NoahFont.footnote).foregroundColor(NoahColor.textSecondary)
            }
            #endif

            if showsTryFirst {
                Button(action: onDone) {
                    Text(freeLeft > 0 ? "Eerst gratis proberen" : "Later beslissen")
                }
                .buttonStyle(.noah(.secondary, size: .elder))
                .accessibilityIdentifier("elderPaywall.tryFirst")
            }

            NoahAsyncButton(kind: .quiet, size: .elder, action: restore) { Text("Aankopen herstellen") }
                .accessibilityIdentifier("elderPaywall.restore")

            disclosures
        }
    }

    @ViewBuilder
    private var purchaseArea: some View {
        switch choice {
        case .alreadyForThisProfile?:
            NoahCard(padding: NoahSpacing.l) {
                Text("U heeft dit abonnement al").font(NoahFont.Elder.bodyStrong).foregroundColor(NoahColor.text)
                ElderText("Met deze Apple ID loopt uw \(Plan.displayName) al. Tik op Aankopen herstellen, dan wordt Noah actief. Er wordt niets extra afgeschreven.")
            }
            .accessibilityIdentifier("elderPaywall.existing")
            if let message = localError ?? store.errorMessage { NoahNotice(kind: .info, text: message, large: true) }
        case .allInUse(let owned)?:
            NoahCard(padding: NoahSpacing.l) {
                Text("Met deze Apple ID kan er geen abonnement bij").font(NoahFont.Elder.bodyStrong).foregroundColor(NoahColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                ElderText(store.allInUseExplanation(owned: owned, targetName: session.name))
                ElderText("Wat wel kan: iemand uit uw familie start het abonnement met een eigen Apple ID. U kunt diegene uitnodigen bij Instellingen › Familie uitnodigen. Of u belt of mailt ons, dan helpen we u graag.")
                Link(destination: app.environment.config.supportURL) { Text("Hulp en contact") }
                    .font(NoahFont.Elder.bodyStrong)
                    .foregroundColor(NoahColor.accent)
                    .frame(minHeight: NoahSize.elderMinTap)
            }
            .accessibilityIdentifier("elderPaywall.allInUse")
        case .buy?, nil:
            if let message = localError ?? store.errorMessage { NoahNotice(kind: .warning, text: message, large: true) }
            NoahAsyncButton(size: .elder, action: purchase) {
                Text(store.isEligibleForIntro(productID)
                    ? "Start voor \(store.introPriceText(for: productID)) per maand"
                    : "Start voor \(store.regularPriceText(for: productID)) per maand")
            }
            .accessibilityIdentifier("elderPaywall.purchase")
        }
    }

    private func feature(_ text: LocalizedStringKey) -> some View {
        Label {
            Text(text).font(NoahFont.Elder.label).foregroundColor(NoahColor.text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundColor(NoahColor.accent)
        }
    }

    private var disclosures: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.s) {
            Text(verbatim: disclosureText)
                .font(NoahFont.Elder.label)
                .foregroundColor(NoahColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("elderPaywall.disclosure")
            Text(verbatim: ProductCopy.elderPrivacy)
                .font(NoahFont.Elder.label)
                .foregroundColor(NoahColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            AdaptiveStack(spacing: NoahSpacing.l) {
                Link("Gebruiksvoorwaarden (EULA)", destination: app.environment.config.termsURL)
                Link("Privacybeleid", destination: app.environment.config.privacyURL)
            }
            .font(NoahFont.Elder.bodyStrong)
            .foregroundColor(NoahColor.accent)
            .frame(minHeight: NoahSize.elderMinTap)
        }
    }

    private var disclosureText: String {
        let price = store.isEligibleForIntro(productID)
            ? "U betaalt de eerste \(store.introPeriodCount(for: productID)) maanden \(store.introPriceText(for: productID)) per maand, daarna \(store.regularPriceText(for: productID)) per maand. "
            : "U betaalt \(store.regularPriceText(for: productID)) per maand. "
        return price + "De betaling loopt via uw Apple ID. Het abonnement wordt elke maand vanzelf verlengd, tenzij u het minstens 24 uur voor het einde van de maand opzegt. Opzeggen doet u in de instellingen van uw Apple ID: Instellingen › uw naam › Abonnementen."
    }

    // MARK: Actions

    private func purchase() async {
        localError = nil
        if !session.isSelfManaged { await session.load() }
        guard session.isSelfManaged, let id = session.elderlyId else {
            // Never take a payment that can't be linked to this account.
            localError = "Het lukt nu even niet om het abonnement te starten. Probeert u het over een paar minuten nog eens."
            return
        }
        if let result = await store.purchase(elderlyId: id), result.status.grantsAccess {
            await session.load()
            activated = true
            onActivated?()
        } else {
            choice = await store.choice(for: id)
        }
    }

    private func restore() async {
        localError = nil
        if await store.restore() > 0 {
            await session.load()
            subscription = try? await session.api.deviceSubscription()
            if subscription?.status.grantsAccess == true {
                activated = true
                onActivated?()
            }
        }
    }
}

/// "Abonnement" in the older person's settings.
struct ElderSubscriptionView: View {
    @Binding var path: [ElderRoute]
    @EnvironmentObject private var session: ElderSession
    @EnvironmentObject private var store: SubscriptionStore
    @State private var state: Loadable<Subscription> = .idle
    @State private var restoreMessage: String?

    var body: some View {
        ElderScrollScreen {
            ElderScreenTitle(title: "Abonnement")
            LoadableView(state: state, large: true, retry: { Task { await load() } }) { subscription in
                NoahCard(padding: NoahSpacing.l) {
                    NoahEyebrow(text: "Uw \(Plan.displayName)")
                    Text(verbatim: subscription.status.label)
                        .font(NoahFont.Elder.title2).noahElderTitleScaling()
                        .foregroundColor(subscription.status.grantsAccess ? NoahColor.positive : NoahColor.accent)
                        .accessibilityIdentifier("elderSubscription.status")
                    if let renews = subscription.renewsAt {
                        ElderText("Wordt verlengd op \(DutchFormat.shortDate(renews)).")
                    } else if let expires = subscription.expiresAt {
                        ElderText("Loopt af op \(DutchFormat.shortDate(expires)).")
                    }
                    if !subscription.isPaidOrBeta, let free = subscription.freeConversationsLeft, free > 0 {
                        ElderText(free == 1 ? "U heeft nog 1 gratis gesprek met Noah." : "U heeft nog \(free) gratis gesprekken met Noah.")
                    }
                    if subscription.status == .beta {
                        ElderText("U doet mee aan de bètatest. Noah is in die periode gratis.")
                    }
                    if subscription.paidByMe == false, subscription.status.grantsAccess, subscription.status != .beta {
                        ElderText("Iemand uit uw familie betaalt dit abonnement.", color: NoahColor.textSecondary)
                    }
                }

                if let usage = subscription.usage {
                    ElderUsageCard(usage: usage)
                }

                if !subscription.isPaidOrBeta {
                    Button { path.append(.settingsPaywall) } label: {
                        NoahButtonLabel(title: "Abonnement starten", systemImage: "sparkles")
                    }
                    .buttonStyle(.noah(.primary, size: .elder))
                    .accessibilityIdentifier("elderSubscription.start")
                }

                if subscription.platform == "app_store" || subscription.platform == nil {
                    Button { Task { await manage() } } label: {
                        NoahButtonLabel(title: "Abonnement beheren", systemImage: "gearshape")
                    }
                    .buttonStyle(.noah(.secondary, size: .elder))
                    NoahAsyncButton(kind: .quiet, size: .elder, action: restore) { Text("Aankopen herstellen") }
                    if let restoreMessage { NoahNotice(kind: .info, text: restoreMessage, large: true) }
                }
                ElderText("Opzeggen kan altijd, via Instellingen › uw naam › Abonnementen op uw iPhone. Het abonnement loopt dan door tot het einde van de betaalde maand.", color: NoahColor.textSecondary)
            }
        }
        .task { await load() }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await session.api.deviceSubscription())
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled { state = .failed(apiError) }
        }
    }

    private func manage() async {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
        await load()
    }

    private func restore() async {
        let count = await store.restore()
        restoreMessage = count > 0 ? "Uw abonnement is hersteld." : store.errorMessage
        await load()
    }
}

/// Fair use this month, for the older person.
struct ElderUsageCard: View {
    let usage: Subscription.Usage

    var body: some View {
        NoahCard(padding: NoahSpacing.l) {
            NoahEyebrow(text: "Deze maand")
            Text(verbatim: "\(Int(usage.minutesThisMonth.rounded())) van \(Int(usage.allowanceMinutes.rounded())) minuten")
                .font(NoahFont.Elder.title2).noahElderTitleScaling()
                .foregroundColor(NoahColor.text)
                .accessibilityIdentifier("elderSubscription.usage")
            ProgressView(value: usage.fraction)
                .tint(usage.overAllowance ? NoahColor.textSoft : NoahColor.accent)
                .accessibilityHidden(true)
            if usage.overAllowance {
                ElderText("U heeft deze maand al veel met Noah gepraat. Noah blijft gewoon voor u bereikbaar, met gesprekken van hooguit \(Plan.cappedConversationMinutes) minuten. Volgende maand is alles weer zoals gewoonlijk.")
            } else if let resets = usage.resetsAt {
                ElderText("De teller begint opnieuw op \(DutchFormat.shortDate(resets)).", color: NoahColor.textSecondary)
            }
        }
    }
}
