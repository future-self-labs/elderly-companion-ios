import StoreKit
import SwiftUI

/// Subscription status for the selected older person.
struct SubscriptionView: View {
    @EnvironmentObject private var session: CaregiverSession
    @EnvironmentObject private var router: CaregiverRouter
    @EnvironmentObject private var store: SubscriptionStore
    @State private var state: Loadable<Subscription> = .idle
    @State private var restoreMessage: String?

    var body: some View {
        NoahScrollScreen {
            LoadableView(state: state, retry: { Task { await load() } }) { subscription in
                let name = session.selected?.preferredName ?? ""
                NoahCard(padding: NoahSpacing.l) {
                    NoahEyebrow(text: "\(Plan.displayName) voor \(name)")
                    Text(verbatim: subscription.status.label)
                        .font(NoahFont.title).noahTitleScaling()
                        .foregroundColor(subscription.status.grantsAccess ? NoahColor.positive : NoahColor.accent)
                    if let renews = subscription.renewsAt {
                        Text("Wordt verlengd op \(DutchFormat.shortDate(renews))")
                            .font(NoahFont.callout).foregroundColor(NoahColor.textSoft)
                    } else if let expires = subscription.expiresAt {
                        Text("Loopt af op \(DutchFormat.shortDate(expires))")
                            .font(NoahFont.callout).foregroundColor(NoahColor.textSoft)
                    }
                    if !subscription.isPaidOrBeta, let free = subscription.freeConversationsLeft, free > 0 {
                        Text(free == 1 ? "\(name) kan nog 1 gratis gesprek met Noah voeren. Start het abonnement om daarna door te praten." : "\(name) kan nog \(free) gratis gesprekken met Noah voeren. Start het abonnement om daarna door te praten.")
                            .font(NoahFont.callout).foregroundColor(NoahColor.textSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if subscription.status == .beta {
                        Text("\(name) doet mee aan de bètatest. Noah is in die periode gratis.")
                            .font(NoahFont.callout).foregroundColor(NoahColor.textSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if subscription.paidByMe == false, subscription.status != .beta, subscription.status.grantsAccess {
                        Text("Een andere mantelzorger betaalt dit abonnement.")
                            .font(NoahFont.footnote).foregroundColor(NoahColor.textSecondary)
                    }
                    if subscription.platform == "google_play" {
                        Text("Afgesloten via Google Play.")
                            .font(NoahFont.footnote).foregroundColor(NoahColor.textSecondary)
                    }
                }

                if let usage = subscription.usage {
                    UsageCard(usage: usage, name: name)
                }

                if !subscription.isPaidOrBeta {
                    if session.permissions.canManageSubscription, let id = session.selected?.id {
                        Button { router.present(.paywall(elderlyId: id)) } label: {
                            NoahButtonLabel(title: "Abonnement starten", systemImage: "sparkles")
                        }
                        .buttonStyle(.noah(.primary))
                    } else {
                        ReadOnlyNotice()
                    }
                }

                if subscription.platform == "app_store" || subscription.platform == nil {
                    Button {
                        Task { await manage() }
                    } label: {
                        NoahButtonLabel(title: "Abonnement beheren", systemImage: "gearshape")
                    }
                    .buttonStyle(.noah(.secondary))
                    NoahAsyncButton(kind: .quiet, action: restore) { Text("Aankopen herstellen") }
                    if let restoreMessage { NoahNotice(kind: .info, text: restoreMessage) }
                }
                Text("Opzeggen kan altijd, via Instellingen › je naam › Abonnementen. Het abonnement loopt dan door tot het einde van de betaalde maand.")
                    .font(NoahFont.footnote)
                    .foregroundColor(NoahColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("Abonnement")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.reloadKey) { await load() }
    }

    private func load() async {
        guard let id = session.selected?.id else { return }
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await session.api.subscription(elderlyId: id))
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
        restoreMessage = count > 0 ? "Je abonnement is hersteld." : store.errorMessage
        await load()
    }
}

/// Minutes this month against the fair-use allowance, and when it resets (contract v2.1).
struct UsageCard: View {
    let usage: Subscription.Usage
    let name: String

    var body: some View {
        NoahCard(padding: NoahSpacing.l) {
            NoahEyebrow(text: "Gebruik deze maand")
            Text(verbatim: "\(Int(usage.minutesThisMonth.rounded())) van \(Int(usage.allowanceMinutes.rounded())) minuten")
                .font(NoahFont.title2).noahTitleScaling()
                .foregroundColor(NoahColor.text)
                .accessibilityIdentifier("subscription.usage")
            ProgressView(value: usage.fraction)
                .tint(usage.overAllowance ? NoahColor.textSoft : NoahColor.accent)
                .accessibilityHidden(true)
            if let resets = usage.resetsAt {
                Text("De teller begint opnieuw op \(DutchFormat.shortDate(resets))")
                    .font(NoahFont.footnote)
                    .foregroundColor(NoahColor.textSecondary)
            }
            if usage.overAllowance {
                NoahNotice(kind: .info, text: "Het redelijk gebruik van deze maand is bereikt. Noah blijft gewoon bereikbaar voor \(name), met gesprekken van maximaal \(Plan.cappedConversationMinutes) minuten. Volgende maand is alles weer zoals gewoonlijk.")
            } else {
                Text("Er geldt een redelijk-gebruikbeleid van \(DutchFormat.hours(minutes: Int(usage.allowanceMinutes.rounded()))) per maand. Is dat op, dan blijft Noah gewoon bereikbaar, met kortere gesprekken.")
                    .font(NoahFont.callout)
                    .foregroundColor(NoahColor.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The paywall: the HelloNoah-abonnement, intro €9,99/maand × 6, then €59,99/maand, fair use
/// explained plainly. App Store disclosures. Never claims "onbeperkt".
struct PaywallView: View {
    let elderlyId: String
    var elderlyName: String?
    var showsLater = false
    /// Inside another scroll view (the wizard): no own ScrollView, no extra padding.
    var embedded = false
    let onDone: () -> Void

    @EnvironmentObject private var session: CaregiverSession
    @EnvironmentObject private var store: SubscriptionStore
    @EnvironmentObject private var app: AppModel
    @State private var activated = false
    @State private var trial: Subscription?
    /// v2.3: which of the three products this Apple ID can still buy for this profile.
    @State private var choice: ProductChoice?

    private var productID: String? { choice?.productID }

    private var name: String {
        elderlyName ?? session.elderly.first { $0.id == elderlyId }?.preferredName ?? "je naaste"
    }

    var body: some View {
        if embedded {
            content.task { await prepare() }
        } else {
            ScrollView {
                content
                    .padding(.horizontal, NoahSpacing.screen)
                    .padding(.vertical, NoahSpacing.l)
                    .noahReadableWidth()
            }
            .noahScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .task { await prepare() }
        }
    }

    private func prepare() async {
        async let products: Void = store.loadProducts()
        trial = try? await session.api.subscription(elderlyId: elderlyId)
        choice = await store.choice(for: elderlyId)
        await products
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            if activated {
                successView
            } else {
                offerView
            }
        }
    }

    private var successView: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundColor(NoahColor.positive)
                .accessibilityHidden(true)
            Text("Noah is actief voor \(name)")
                .font(NoahFont.largeTitle).noahTitleScaling()
                .foregroundColor(NoahColor.text)
            Text("\(name) kan nu met Noah praten, via de app en via het telefoonnummer.")
                .font(NoahFont.bodyText)
                .foregroundColor(NoahColor.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            Button("Verder", action: onDone)
                .buttonStyle(.noah(.primary))
        }
    }

    private var offerView: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            HStack(spacing: NoahSpacing.s) {
                NoahOrb(activity: .idle, diameter: 40).frame(width: 54, height: 54)
                Text(verbatim: Plan.displayName)
                    .font(NoahFont.title).noahTitleScaling()
                    .foregroundColor(NoahColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Eén plan, maandelijks opzegbaar.")
                .font(NoahFont.title3)
                .foregroundColor(NoahColor.accent)
            if let free = trial?.freeConversationsLeft, free > 0, trial?.isPaidOrBeta == false {
                Text(free == 1 ? "\(name) kan eerst 1 gratis gesprek met Noah voeren, om Noah rustig te leren kennen." : "\(name) kan eerst \(free) gratis gesprekken met Noah voeren, om Noah rustig te leren kennen.")
                    .font(NoahFont.callout)
                    .foregroundColor(NoahColor.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            NoahCard(padding: NoahSpacing.l) {
                if store.isEligibleForIntro(productID) {
                    Text(verbatim: "\(store.introPriceText(for: productID)) per maand")
                        .font(NoahFont.display(36, relativeTo: .largeTitle)).noahTitleScaling()
                        .foregroundColor(NoahColor.text)
                    Text("de eerste \(store.introPeriodCount(for: productID)) maanden, daarna \(store.regularPriceText(for: productID)) per maand")
                        .font(NoahFont.callout)
                        .foregroundColor(NoahColor.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(verbatim: "\(store.regularPriceText(for: productID)) per maand")
                        .font(NoahFont.display(36, relativeTo: .largeTitle)).noahTitleScaling()
                        .foregroundColor(NoahColor.text)
                }
                Text("Voor \(name).")
                    .font(NoahFont.footnote)
                    .foregroundColor(NoahColor.textSecondary)
            }

            NoahCard {
                Label("Redelijk gebruik", systemImage: "clock.fill")
                    .font(NoahFont.headline)
                    .foregroundColor(NoahColor.text)
                Text(verbatim: ProductCopy.fairUse(name: name, allowanceMinutes: Int(trial?.usage?.allowanceMinutes ?? Double(Plan.fairUseMonthlyMinutes))))
                    .font(NoahFont.callout)
                    .foregroundColor(NoahColor.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("paywall.fairUse")
            }

            VStack(alignment: .leading, spacing: NoahSpacing.s) {
                feature("Praten met Noah via de app en via een gewoon telefoonnummer")
                feature("Samenvattingen, stemming en meldingen voor jou en je familie")
                feature("Het levensverhaal, en als jij dat aanzet ook de eigen stem")
                feature("Een extra geheugensteuntje voor afspraken, verjaardagen en medicijnen")
                feature("Gesprekken en gegevens versleuteld opgeslagen in de EU. Voor het gesprek zelf gebruikt Noah gespecialiseerde spraak- en AI-diensten.")
            }


            switch choice {
            case .alreadyForThisProfile?:
                alreadyPaidCard
            case .allInUse(let owned)?:
                allInUseCard(owned)
            case .buy?, nil:
                if let error = store.errorMessage { NoahNotice(kind: .warning, text: error) }

                NoahAsyncButton(kind: .primary, action: purchase) {
                    Text(store.isEligibleForIntro(productID) ? "Start voor \(store.introPriceText(for: productID)) per maand" : "Start voor \(store.regularPriceText(for: productID)) per maand")
                }
                .accessibilityIdentifier("paywall.purchase")
            }

            #if DEBUG
            if app.isMock {
                Text("Demo-modus: de aankoop wordt gesimuleerd, er wordt niets afgeschreven.")
                    .font(NoahFont.footnote).foregroundColor(NoahColor.textSecondary)
            }
            #endif

            if showsLater {
                Button("Later starten", action: onDone)
                    .buttonStyle(.noah(.secondary))
            }

            NoahAsyncButton(kind: .quiet, action: restore) { Text("Aankopen herstellen") }

            disclosures
        }
    }

    /// This Apple ID already pays for this profile: restore, never a second payment.
    private var alreadyPaidCard: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            NoahCard(padding: NoahSpacing.l) {
                Label {
                    Text("Je hebt al een abonnement voor \(name)")
                        .font(NoahFont.headline)
                        .foregroundColor(NoahColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle.fill").foregroundColor(NoahColor.accent)
                }
                Text("Met deze Apple ID loopt het \(Plan.displayName) voor \(name) al. Tik op Aankopen herstellen om Noah voor \(name) te activeren. Er wordt niets extra afgeschreven.")
                    .font(NoahFont.callout)
                    .foregroundColor(NoahColor.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("paywall.existingSubscription")
            if let error = store.errorMessage { NoahNotice(kind: .info, text: error) }
        }
    }

    /// A fourth profile on the same Apple ID (v2.3: at most three, one per subscription group).
    private func allInUseCard(_ owned: [OwnedSubscription]) -> some View {
        NoahCard(padding: NoahSpacing.l) {
            Label {
                Text("Deze Apple ID betaalt al voor \(Plan.maxPerAppleID) naasten")
                    .font(NoahFont.headline)
                    .foregroundColor(NoahColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle.fill").foregroundColor(NoahColor.accent)
            }
            Text(verbatim: store.allInUseExplanation(owned: owned, targetName: name))
                .font(NoahFont.callout)
                .foregroundColor(NoahColor.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            Text("Wat wel kan: een andere mantelzorger van \(name) wordt beheerder en start het abonnement met een eigen Apple ID. Nodig diegene uit via Meer › Mantelzorgers. Of stop een abonnement dat je niet meer nodig hebt via Instellingen › je naam › Abonnementen. Vragen? Ons supportteam helpt je graag.")
                .font(NoahFont.callout)
                .foregroundColor(NoahColor.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: app.environment.config.supportURL) {
                Text("Hulp en contact")
            }
            .font(NoahFont.semibold(15, relativeTo: .subheadline))
            .foregroundColor(NoahColor.accent)
            .frame(minHeight: NoahSize.minTap)
        }
        .accessibilityIdentifier("paywall.allInUse")
    }

    private func feature(_ text: LocalizedStringKey) -> some View {
        Label {
            Text(text).font(NoahFont.callout).foregroundColor(NoahColor.text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundColor(NoahColor.accent)
        }
    }

    private var disclosures: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.s) {
            Text(disclosureText)
                .font(NoahFont.footnote)
                .foregroundColor(NoahColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: NoahSpacing.m) {
                Link("Gebruiksvoorwaarden (EULA)", destination: app.environment.config.termsURL)
                Link("Privacybeleid", destination: app.environment.config.privacyURL)
            }
            .font(NoahFont.semibold(13, relativeTo: .footnote))
            .foregroundColor(NoahColor.accent)
            .frame(minHeight: NoahSize.minTap)
        }
    }

    private var disclosureText: String {
        let intro = store.isEligibleForIntro(productID)
            ? "Je betaalt de eerste \(store.introPeriodCount(for: productID)) maanden \(store.introPriceText(for: productID)) per maand, daarna \(store.regularPriceText(for: productID)) per maand. "
            : "Je betaalt \(store.regularPriceText(for: productID)) per maand. "
        return intro + "De betaling loopt via je Apple ID. Het abonnement wordt elke maand automatisch verlengd, tenzij je het minstens 24 uur voor het einde van de periode opzegt. Opzeggen en beheren doe je in de instellingen van je Apple ID."
    }

    private func purchase() async {
        if let subscription = await store.purchase(elderlyId: elderlyId), subscription.status.grantsAccess {
            await session.reloadMe()
            session.dataChanged()
            activated = true
        } else {
            // Ownership may have changed meanwhile (another device, another profile).
            choice = await store.choice(for: elderlyId)
        }
    }

    private func restore() async {
        if await store.restore() > 0 {
            await session.reloadMe()
            session.dataChanged()
            if session.elderly.first(where: { $0.id == elderlyId })?.access == .active { activated = true }
        }
    }
}
