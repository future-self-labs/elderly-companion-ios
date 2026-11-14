import StoreKit
import SwiftUI

// v2.4 and audit 2026-11-14, caregiver side: tell the older person that family reads along,
// the "volgende stappen" on the dashboard, pending invitations, paused calls and the honest
// subscription warning before deleting.

// MARK: - Vertel het Wim

/// The text a caregiver can read aloud to the older person, and "Ik heb het verteld"
/// (`POST /elderly/:id/told-elderly`). Used as a wizard step and as a screen.
struct TellElderlyPanel: View {
    let elderlyId: String
    let name: String
    /// The older person's address form: the read-aloud text follows it.
    var addressForm: AddressForm = .jij
    /// Called after "Ik heb het verteld" (also when an older backend doesn't know the call).
    var onTold: (() -> Void)?

    @EnvironmentObject private var session: CaregiverSession
    @State private var told = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            Text("Noah is er voor \(name). Dan hoort \(name) ook te weten wie er meeleest, en wat. Vertel het in je eigen woorden, of lees dit voor:")
                .font(NoahFont.bodyText)
                .foregroundColor(NoahColor.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            NoahCard(padding: NoahSpacing.l, background: NoahColor.surfaceDeep) {
                Label("Om voor te lezen", systemImage: "text.quote")
                    .font(NoahFont.headline)
                    .foregroundColor(NoahColor.accent)
                Text(verbatim: Self.readAloudText(name: name, caregiverName: session.firstName, formal: addressForm == .u))
                    .font(NoahFont.title3)
                    .foregroundColor(NoahColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("tell.readAloud")
            }
            Text("Noah vertelt het \(name) ook zelf in het eerste gesprek, en opnieuw als er iemand bij komt. Op de eigen telefoon ziet \(name) bij \u{201C}Wie kijkt er mee\u{201D} wie er meekijkt en kan \(name) zelf aanpassen wat de familie ziet.")
                .font(NoahFont.callout)
                .foregroundColor(NoahColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if told {
                Label("Fijn. Dit is bewaard.", systemImage: "checkmark.circle.fill")
                    .font(NoahFont.bodyStrong)
                    .foregroundColor(NoahColor.positive)
            } else {
                if let error { NoahNotice(kind: .error, text: error) }
                NoahAsyncButton("Ik heb het \(name) verteld") { await markTold() }
                    .accessibilityIdentifier("tell.done")
            }
        }
    }

    /// Plain, warm and complete: who, what, and that the older person decides.
    static func readAloudText(name: String, caregiverName: String, formal: Bool = false) -> String {
        let me = caregiverName.isEmpty ? "ik" : "ik (\(caregiverName))"
        if formal {
            return "\(name), u kunt met Noah praten wanneer u wilt. Noah is een computer, geen mens. Wat u met Noah bespreekt, kan \(me) teruglezen: een korte samenvatting, wat er woord voor woord is gezegd, en hoe u zich leek te voelen. Als Noah zich zorgen maakt, krijg ik een bericht. Wilt u dat iets alleen tussen u en Noah blijft? Zeg dan tegen Noah: \u{201C}dit gesprek is alleen voor mij.\u{201D} En op uw eigen telefoon kunt u zelf zien en aanpassen wie er meekijkt."
        }
        return "\(name), je kunt met Noah praten wanneer je wilt. Noah is een computer, geen mens. Wat je met Noah bespreekt, kan \(me) teruglezen: een korte samenvatting, wat er woord voor woord is gezegd, en hoe je je leek te voelen. Als Noah zich zorgen maakt, krijg ik een bericht. Wil je dat iets alleen tussen jou en Noah blijft? Zeg dan tegen Noah: \u{201C}dit gesprek is alleen voor mij.\u{201D} En op je eigen telefoon kun je zelf zien en aanpassen wie er meekijkt."
    }

    private func markTold() async {
        error = nil
        do {
            try await session.api.markToldElderly(elderlyId: elderlyId)
        } catch {
            let apiError = APIError.from(error)
            // An older backend doesn't know the call: telling still counts.
            if !apiError.isFeatureUnavailable {
                self.error = apiError.userMessage
                return
            }
        }
        told = true
        session.dataChanged()
        onTold?()
    }
}

struct TellElderlyView: View {
    @EnvironmentObject private var session: CaregiverSession
    @State private var addressForm: AddressForm = .u

    var body: some View {
        NoahScrollScreen {
            if let selected = session.selected {
                Text("Vertel het \(selected.preferredName)")
                    .font(NoahFont.largeTitle).noahTitleScaling()
                    .foregroundColor(NoahColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                TellElderlyPanel(elderlyId: selected.id, name: selected.preferredName, addressForm: addressForm)
            }
        }
        .navigationTitle("Vertel het")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let id = session.selected?.id, let profile = try? await session.api.elderly(id: id) {
                addressForm = profile.addressForm == .jij ? .jij : .u
            }
        }
    }
}

// MARK: - Volgende stappen

/// What still needs doing before Noah can do everything (audit H1): an unconfirmed number, no
/// paired phone, no emergency contact, the older person not told yet. Beheerders only.
struct NextStepsCard: View {
    let profile: ElderlyProfile
    let hasDevice: Bool?
    let hasEmergencyContact: Bool?

    @EnvironmentObject private var router: CaregiverRouter

    struct Step: Identifiable {
        let id: String
        let icon: String
        let title: String
        let detail: String
        let route: CaregiverRoute
    }

    static func steps(profile: ElderlyProfile, hasDevice: Bool?, hasEmergencyContact: Bool?) -> [Step] {
        let name = profile.preferredName
        var steps: [Step] = []
        if !profile.hasPhoneNumber {
            steps.append(Step(id: "phone", icon: "phone.fill", title: "Telefoonnummer toevoegen",
                              detail: "\(name) heeft nog geen telefoonnummer. Zonder nummer kan Noah niet bellen.", route: .profile))
        } else if profile.needsPhoneConfirmation {
            steps.append(Step(id: "confirm", icon: "checkmark.shield", title: "Bevestig het nummer van \(name)",
                              detail: "Tot dan belt Noah niet: geen ochtendgesprek, geen belherinneringen en geen \u{201C}Laat Noah nu bellen\u{201D}.", route: .profile))
        }
        if profile.needsTellingElderly {
            steps.append(Step(id: "tell", icon: "text.bubble", title: "Vertel \(name) dat je meeleest",
                              detail: "Met een tekst om voor te lezen.", route: .tellElderly))
        }
        if hasDevice == false {
            steps.append(Step(id: "pair", icon: "iphone.radiowaves.left.and.right", title: "Koppel de telefoon van \(name)",
                              detail: "Dan kan \(name) met één tik met Noah praten. Doe dit als je samen bent.", route: .pairDevice))
        }
        if hasEmergencyContact == false {
            steps.append(Step(id: "contacts", icon: "staroflife", title: "Voeg een noodcontact toe",
                              detail: "Wie moet Noah waarschuwen als het niet goed gaat?", route: .emergencyContacts))
        }
        return steps
    }

    var body: some View {
        let steps = Self.steps(profile: profile, hasDevice: hasDevice, hasEmergencyContact: hasEmergencyContact)
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: NoahSpacing.s) {
                NoahSectionHeader(title: "Volgende stappen")
                NoahCard(padding: NoahSpacing.s, border: NoahColor.accent.opacity(0.6)) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        if index > 0 { Divider().overlay(NoahColor.divider) }
                        Button { router.show(step.route, in: .overview) } label: {
                            NoahRow(icon: step.icon, title: step.title, subtitle: step.detail)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("nextStep.\(step.id)")
                    }
                }
            }
            .accessibilityIdentifier("dashboard.nextSteps")
        }
    }
}

// MARK: - Paused calls

/// The older person told Noah they want to stop: Noah doesn't call by itself until a beheerder
/// switches it back on (v2.4 `outboundPaused`).
struct OutboundPausedNotice: View {
    let profile: ElderlyProfile
    let onChanged: (ElderlyProfile) -> Void

    @EnvironmentObject private var session: CaregiverSession
    @State private var error: String?

    var body: some View {
        NoahCard(padding: NoahSpacing.l, border: NoahColor.accent.opacity(0.7)) {
            Label("Noah belt \(profile.preferredName) nu niet uit zichzelf", systemImage: "phone.down.fill")
                .font(NoahFont.headline)
                .foregroundColor(NoahColor.text)
            Text("\(profile.preferredName) heeft tegen Noah gezegd te willen stoppen. Daarom staan het ochtendgesprek, de belherinneringen en de belletjes bij geen contact stil. In de app praten kan gewoon. Praat er eerst samen over voordat je het weer aanzet.")
                .font(NoahFont.callout)
                .foregroundColor(NoahColor.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            if let error { NoahNotice(kind: .error, text: error) }
            if session.permissions.isBeheerder {
                NoahAsyncButton(kind: .secondary, action: resume) {
                    NoahButtonLabel(title: "Noah mag weer bellen", systemImage: "phone.arrow.up.right")
                }
                .accessibilityIdentifier("outbound.resume")
            }
        }
        .accessibilityIdentifier("outbound.paused")
    }

    private func resume() async {
        error = nil
        do {
            onChanged(try await session.api.setOutboundPaused(elderlyId: profile.id, paused: false))
            session.dataChanged()
        } catch {
            self.error = APIError.from(error).userMessage
        }
    }
}

// MARK: - Pending invitations

/// Invitations that were not used yet, with "Intrekken" (audit M5, v2.4). Hidden on an older
/// backend.
struct PendingInvitationsSection: View {
    let elderlyId: String
    /// Bumped by the parent after a new invitation.
    var reloadToken: Int = 0

    @EnvironmentObject private var session: CaregiverSession
    @State private var items: [PendingInvitation]?
    @State private var error: String?
    @State private var confirmRevoke: PendingInvitation?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Always present, so the task runs even while there is nothing to show.
            Color.clear.frame(height: 0)
            if let items, !items.isEmpty {
                VStack(alignment: .leading, spacing: NoahSpacing.s) {
                    NoahEyebrow(text: "Openstaande uitnodigingen")
                    NoahCard(padding: NoahSpacing.s) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, invitation in
                            if index > 0 { Divider().overlay(NoahColor.divider) }
                            row(invitation)
                        }
                    }
                    if let error { NoahNotice(kind: .error, text: error) }
                }
                .accessibilityIdentifier("caregivers.pendingInvitations")
            }
        }
        .task(id: "\(elderlyId)-\(reloadToken)-\(session.dataVersion)") { await load() }
        .confirmationDialog("Uitnodiging intrekken?", isPresented: Binding(get: { confirmRevoke != nil }, set: { if !$0 { confirmRevoke = nil } }), titleVisibility: .visible) {
            Button("Intrekken", role: .destructive) {
                if let invitation = confirmRevoke { Task { await revoke(invitation) } }
            }
            Button("Annuleren", role: .cancel) {}
        } message: {
            Text("De code werkt daarna niet meer.")
        }
    }

    private func row(_ invitation: PendingInvitation) -> some View {
        HStack(spacing: NoahSpacing.s) {
            NoahIconBadge(systemName: invitation.role == .beheerder ? "key.fill" : "eye.fill", tint: invitation.role == .beheerder ? NoahColor.accent : NoahColor.textSoft)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: [invitation.role.label, invitation.code].compactMap { $0 }.joined(separator: " · "))
                    .font(NoahFont.bodyStrong).foregroundColor(NoahColor.text)
                Text(verbatim: subtitle(invitation))
                    .font(NoahFont.footnote).foregroundColor(NoahColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Intrekken") { confirmRevoke = invitation }
                .font(NoahFont.subheadline)
                .foregroundColor(NoahColor.dangerText)
                .frame(minHeight: NoahSize.minTap)
                .accessibilityIdentifier("caregivers.revokeInvitation")
        }
        .frame(minHeight: NoahSize.minTap)
    }

    private func subtitle(_ invitation: PendingInvitation) -> String {
        var parts: [String] = []
        if invitation.isMadeByElderly {
            parts.append("Gemaakt door \(session.selected?.preferredName ?? "je naaste")")
        } else if let by = invitation.createdBy {
            parts.append("Gemaakt door \(by)")
        }
        if let expires = invitation.expiresAt { parts.append("geldig tot \(DutchFormat.shortDate(expires))") }
        return parts.joined(separator: ", ")
    }

    private func load() async {
        do {
            items = try await session.api.pendingInvitations(elderlyId: elderlyId)
        } catch {
            // Older backend or a lezer: show nothing.
            items = nil
        }
    }

    private func revoke(_ invitation: PendingInvitation) async {
        error = nil
        do {
            try await session.api.revokeInvitation(elderlyId: elderlyId, invitationId: invitation.id)
            await load()
        } catch {
            self.error = APIError.from(error).userMessage
        }
    }
}

// MARK: - Subscription warning before deleting

/// Deleting never stops an App Store subscription (audit M10): said plainly, with the way to stop it.
struct SubscriptionWarningCard: View {
    let text: String

    var body: some View {
        NoahCard(padding: NoahSpacing.l, border: NoahColor.accent.opacity(0.8)) {
            Label("Het abonnement stopt niet vanzelf", systemImage: "exclamationmark.triangle.fill")
                .font(NoahFont.headline)
                .foregroundColor(NoahColor.text)
            Text(verbatim: text)
                .font(NoahFont.callout)
                .foregroundColor(NoahColor.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await Self.manageSubscriptions() }
            } label: {
                NoahButtonLabel(title: "Abonnement beheren", systemImage: "gearshape")
            }
            .buttonStyle(.noah(.secondary))
            .accessibilityIdentifier("delete.manageSubscription")
        }
        .accessibilityIdentifier("delete.subscriptionWarning")
    }

    @MainActor
    static func manageSubscriptions() async {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
    }
}
