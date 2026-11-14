import SwiftUI
import UserNotifications

// v2.4: transparency and control for the older person, on both kinds of profile ("Wie kijkt er
// mee"). Who reads along and what, what they may decide themselves (what the family sees, who may
// help, which phones), their own data, and a way out that is never hidden.

/// What the screens show, from `GET /device/transparency` or, on an older backend, from
/// `GET /device/caregivers` (allowed for both kinds of profile since v2.3).
struct TransparencySnapshot: Equatable {
    var members: [DeviceTransparency.Member]
    var familySees: [String]
    var sharing: SharingLevel
    var pendingInvitations: [PendingInvitation]
    var caregiverRequests: [CaregiverRequest]
    var deletionRequest: DeletionRequest?
    var selfRegistered: Bool
    /// The backend supports the v2.4 controls (sharing, devices, deletion request, requests).
    var supportsControls: Bool

    static func from(_ transparency: DeviceTransparency) -> TransparencySnapshot {
        TransparencySnapshot(
            members: transparency.caregivers,
            familySees: transparency.familySees.isEmpty && !transparency.caregivers.isEmpty
                ? FamilySees.sentences(sharing: transparency.sharing ?? .alles, recording: transparency.recording ?? .uit)
                : transparency.familySees,
            sharing: transparency.sharing ?? .alles,
            pendingInvitations: transparency.pendingInvitations,
            caregiverRequests: transparency.caregiverRequests,
            deletionRequest: transparency.deletionRequest,
            selfRegistered: transparency.selfRegistered,
            supportsControls: true
        )
    }

    /// Older backend: only the list of caregivers is known; say honestly what they can read.
    static func fallback(members: [CaregiverMembership], isSelfManaged: Bool) -> TransparencySnapshot {
        var sees = FamilySees.sentences(sharing: .alles, recording: .uit)
        sees.append("Als opnemen aanstaat: opnames, alleen als u daar in dat gesprek ja op zegt.")
        return TransparencySnapshot(
            members: members.map { DeviceTransparency.Member(id: $0.caregiverId, name: $0.name, role: $0.role, joinedAt: $0.joinedAt) },
            familySees: members.isEmpty ? [] : sees,
            sharing: .alles,
            pendingInvitations: [],
            caregiverRequests: [],
            deletionRequest: nil,
            selfRegistered: isSelfManaged,
            supportsControls: false
        )
    }
}

extension ElderSession {
    /// Loads what "Wie kijkt er mee" shows; never an error page for an older backend.
    func transparencySnapshot() async throws -> TransparencySnapshot {
        await loadTransparency()
        if let transparency { return .from(transparency) }
        let members = try await api.deviceCaregivers()
        return .fallback(members: members, isSelfManaged: isSelfManaged)
    }

    /// The older person may remove someone: on a profile they manage or registered themselves.
    func canRemoveCaregivers(_ snapshot: TransparencySnapshot) -> Bool {
        isSelfManaged || snapshot.selfRegistered
    }
}

// MARK: - Wie kijkt er mee

struct ElderTransparencyView: View {
    @Binding var path: [ElderRoute]
    @EnvironmentObject private var session: ElderSession
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var push: PushManager
    @State private var state: Loadable<TransparencySnapshot> = .idle
    @State private var confirmRemove: DeviceTransparency.Member?
    @State private var confirmsUnpair = false
    @State private var message: (text: String, isError: Bool)?
    @State private var outboundPaused: Bool?

    var body: some View {
        ElderScrollScreen {
            ElderScreenTitle(title: "Wie kijkt er mee")
            if session.isRestricted { ElderRestrictedNotice() }
            if let message { ElderMessage(text: message.text, isError: message.isError) }
            LoadableView(state: state, large: true, retry: { Task { await load() } }) { snapshot in
                content(snapshot)
            }
        }
        .task { await load() }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }), titleVisibility: .visible) {
            Button("Ja, verwijderen", role: .destructive) {
                if let member = confirmRemove { Task { await remove(member) } }
            }
            Button("Nee", role: .cancel) {}
        } message: {
            Text("Diegene kan daarna niet meer zien hoe het met u gaat. U kunt diegene later opnieuw uitnodigen.")
        }
        .confirmationDialog("Deze telefoon ontkoppelen?", isPresented: $confirmsUnpair, titleVisibility: .visible) {
            Button("Ja, ontkoppelen", role: .destructive) { Task { await app.unpairThisDevice() } }
            Button("Nee", role: .cancel) {}
        } message: {
            Text(session.isSelfManaged
                 ? "Op deze telefoon kunt u daarna niet meer met Noah praten. Uw gegevens blijven bewaard; u kunt zich later opnieuw aanmelden met uw telefoonnummer."
                 : "Op deze telefoon kunt u daarna niet meer met Noah praten. Uw gegevens blijven bewaard en uw familie kan ze nog zien. Wilt u dat alles wordt gewist? Kies dan \u{201C}Stoppen met Noah\u{201D}.")
        }
    }

    @ViewBuilder
    private func content(_ snapshot: TransparencySnapshot) -> some View {
        // Requests first: someone waits for the older person's answer.
        ForEach(snapshot.caregiverRequests) { request in
            requestCard(request)
        }

        VStack(alignment: .leading, spacing: NoahSpacing.m) {
            ElderSectionTitle(text: snapshot.members.isEmpty ? "Er kijkt niemand mee" : "Deze mensen kijken met u mee")
            if snapshot.members.isEmpty {
                ElderText("Alleen u en Noah weten wat u vertelt. Er leest niemand mee.")
                if session.isSelfManaged {
                    Button { path.append(.settingsInvite) } label: {
                        NoahButtonLabel(title: "Familie uitnodigen", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.noah(.secondary, size: .elder))
                }
            }
            ForEach(snapshot.members) { member in
                memberCard(member, canRemove: session.canRemoveCaregivers(snapshot))
            }
        }

        if !snapshot.familySees.isEmpty {
            NoahCard(padding: NoahSpacing.l) {
                ElderSectionTitle(text: "Dit ziet uw familie")
                VStack(alignment: .leading, spacing: NoahSpacing.s) {
                    ForEach(snapshot.familySees, id: \.self) { line in
                        Label {
                            Text(verbatim: line).font(NoahFont.Elder.label).foregroundColor(NoahColor.text)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "eye.fill").foregroundColor(NoahColor.accent)
                        }
                    }
                }
                .accessibilityIdentifier("transparency.familySees")
                if snapshot.supportsControls {
                    Button { path.append(.sharing) } label: {
                        NoahButtonLabel(title: "Aanpassen wat uw familie ziet", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.noah(.secondary, size: .elder))
                    .accessibilityIdentifier("transparency.sharing")
                }
            }
        }

        NoahCard(padding: NoahSpacing.l, background: NoahColor.surfaceDeep) {
            Label {
                Text("U kunt het Noah ook zeggen").font(NoahFont.Elder.bodyStrong).foregroundColor(NoahColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "quote.bubble.fill").foregroundColor(NoahColor.accent)
            }
            ElderText("Zeg tijdens een gesprek: \u{201C}Dit gesprek is alleen voor mij.\u{201D} Dan ziet uw familie daar niets van. Alleen bij nood of grote zorgen krijgen ze wel een melding.")
            ElderText("Wilt u niet meer gebeld worden, of helemaal stoppen? Zeg het gewoon tegen Noah. Hieronder kunt u het ook zelf regelen.", color: NoahColor.textSecondary)
        }

        if outboundPaused == true {
            NoahCard(padding: NoahSpacing.l, border: NoahColor.accent.opacity(0.7)) {
                ElderText("Noah belt u nu niet meer uit zichzelf, omdat u zei dat u wilde stoppen. In de app praten kan gewoon.", color: NoahColor.text)
                if session.isSelfManaged, !session.isRestricted {
                    NoahAsyncButton(kind: .secondary, size: .elder, action: resumeCalls) {
                        Text("Noah mag mij weer bellen")
                    }
                    .accessibilityIdentifier("transparency.resumeCalls")
                } else if !session.isSelfManaged {
                    ElderText("Wilt u weer gebeld worden? Uw familie kan dat weer aanzetten.", color: NoahColor.textSecondary)
                }
            }
        }

        if !snapshot.pendingInvitations.isEmpty {
            VStack(alignment: .leading, spacing: NoahSpacing.m) {
                ElderSectionTitle(text: "Uitnodigingen die nog niet zijn gebruikt")
                ForEach(snapshot.pendingInvitations) { invitation in
                    // Backend v2.4 §10: self-managed may revoke any open invitation; a self-registered
                    // profile that a family member helps with only the ones made on the phone.
                    invitationCard(invitation, canRevoke: !session.isRestricted && (session.isSelfManaged || (snapshot.selfRegistered && invitation.isMadeByElderly)))
                }
            }
        }

        if !push.isAuthorized, push.authorization != .denied, !snapshot.members.isEmpty || session.isSelfManaged {
            NoahCard(padding: NoahSpacing.l) {
                ElderText("Wilt u een berichtje op deze telefoon als iemand wil meekijken, of als er een nieuwe telefoon wordt aangemeld?")
                NoahAsyncButton(kind: .secondary, size: .elder, action: allowNotices) {
                    NoahButtonLabel(title: "Ja, stuur mij een berichtje", systemImage: "bell.fill")
                }
            }
        }

        VStack(spacing: NoahSpacing.m) {
            if snapshot.supportsControls {
                ElderTileButton(title: "Uw telefoons", systemImage: "iphone") { path.append(.devices) }
                    .accessibilityIdentifier("transparency.devices")
            }
            ElderTileButton(title: "Uw gegevens downloaden", systemImage: "square.and.arrow.down") { path.append(.settingsExport) }
                .accessibilityIdentifier("transparency.export")
            if session.isSelfManaged || snapshot.selfRegistered {
                ElderTileButton(title: "Account verwijderen", systemImage: "trash.fill", iconTint: NoahColor.dangerText) { path.append(.settingsDelete) }
            } else if snapshot.supportsControls {
                ElderTileButton(title: "Stoppen met Noah", systemImage: "hand.raised.fill", iconTint: NoahColor.dangerText) { path.append(.stopNoah) }
                    .accessibilityIdentifier("transparency.stop")
            }
            Button { confirmsUnpair = true } label: {
                NoahButtonLabel(title: "Deze telefoon ontkoppelen", systemImage: "iphone.slash", iconTint: NoahColor.dangerText)
            }
            .buttonStyle(.noah(.secondary, size: .elder))
            .accessibilityIdentifier("transparency.unpair")
        }
        .padding(.top, NoahSpacing.s)

        if let request = snapshot.deletionRequest, let executes = request.executesAt {
            NoahNotice(kind: .warning, text: "U heeft gevraagd om alles te verwijderen. Dat gebeurt op \(DutchFormat.shortDate(executes)).",
                       large: true, actionTitle: "Toch niet stoppen") { path.append(.stopNoah) }
        }
    }

    private var confirmTitle: String {
        "Wilt u dat \(confirmRemove?.name ?? "deze persoon") niet meer meekijkt?"
    }

    private func requestCard(_ request: CaregiverRequest) -> some View {
        NoahCard(padding: NoahSpacing.l, border: NoahColor.accent.opacity(0.8)) {
            ElderSectionTitle(text: "\(request.name ?? "Iemand") wil helpen beheren")
            ElderText("Diegene kan dan alles lezen, instellen en verwijderen. U kunt diegene later zelf weer verwijderen. Kent u deze persoon en vindt u het goed?")
            if session.isRestricted {
                // Backend v2.4 §8: a phone that waits for approval cannot answer requests.
                ElderText("Op deze telefoon kunt u dit nog niet beantwoorden, want hij is net aangemeld. Doe het op uw andere telefoon, of wacht tot deze telefoon is goedgekeurd.", color: NoahColor.textSecondary)
            } else {
                NoahAsyncButton(size: .elder, action: { await answer(request, approve: true) }) { Text("Ja, dat is goed") }
                    .accessibilityIdentifier("transparency.approveRequest")
                NoahAsyncButton(kind: .secondary, size: .elder, action: { await answer(request, approve: false) }) { Text("Nee, liever niet") }
            }
        }
        .accessibilityIdentifier("transparency.request")
    }

    private func memberCard(_ member: DeviceTransparency.Member, canRemove: Bool) -> some View {
        VStack(alignment: .leading, spacing: NoahSpacing.m) {
            // Avatar above the name at large text, so the name keeps the full width.
            AdaptiveStack(verticalAlignment: .center, spacing: NoahSpacing.m) {
                NoahAvatar(name: member.name ?? "?", size: 52, tint: member.role == .beheerder ? NoahColor.accent : NoahColor.textSoft)
                VStack(alignment: .leading, spacing: NoahSpacing.xxs) {
                    Text(verbatim: member.name ?? "Familielid")
                        .font(NoahFont.Elder.bodyStrong)
                        .foregroundColor(NoahColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: member.role.elderLabel + (member.joinedAt.map { " · sinds \(DutchFormat.shortDate($0))" } ?? ""))
                        .font(NoahFont.Elder.label)
                        .foregroundColor(NoahColor.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if canRemove {
                Button { confirmRemove = member } label: {
                    NoahButtonLabel(title: "Verwijderen", systemImage: "person.badge.minus", iconTint: NoahColor.dangerText)
                }
                .buttonStyle(.noah(.secondary, size: .elder))
                .accessibilityLabel(Text("\(member.name ?? "Familielid") verwijderen"))
                .accessibilityIdentifier("caregivers.remove")
            }
        }
        .padding(NoahSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoahRadius.large, style: .continuous).fill(NoahColor.surface))
        .overlay(RoundedRectangle(cornerRadius: NoahRadius.large, style: .continuous).strokeBorder(NoahColor.cardBorder, lineWidth: 1))
    }

    private func invitationCard(_ invitation: PendingInvitation, canRevoke: Bool) -> some View {
        VStack(alignment: .leading, spacing: NoahSpacing.s) {
            Text(verbatim: invitation.role.elderLabel + (invitation.isMadeByElderly ? " · door u gemaakt" : invitation.createdBy.map { " · gemaakt door \($0)" } ?? ""))
                .font(NoahFont.Elder.bodyStrong)
                .foregroundColor(NoahColor.text)
                .fixedSize(horizontal: false, vertical: true)
            if let expires = invitation.expiresAt {
                ElderText("Geldig tot \(DutchFormat.dayAndTime(expires)).", color: NoahColor.textSoft)
            }
            if canRevoke {
                NoahAsyncButton(kind: .secondary, size: .elder, action: { await revoke(invitation) }) {
                    NoahButtonLabel(title: "Intrekken", systemImage: "xmark.circle", iconTint: NoahColor.dangerText)
                }
            }
        }
        .padding(NoahSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoahRadius.large, style: .continuous).fill(NoahColor.surface))
        .overlay(RoundedRectangle(cornerRadius: NoahRadius.large, style: .continuous).strokeBorder(NoahColor.border, lineWidth: 1))
    }

    // MARK: Actions

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await session.transparencySnapshot())
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled, state.value == nil { state = .failed(apiError) }
        }
        // Backend v2.4: on /device/me and /device/profile, for both kinds of profile.
        outboundPaused = session.outboundPaused
    }

    private func remove(_ member: DeviceTransparency.Member) async {
        message = nil
        do {
            try await session.api.removeDeviceCaregiver(caregiverId: member.id)
            message = ("\(member.name ?? "Diegene") kijkt niet meer mee.", false)
            await load()
            await session.load()
        } catch {
            message = (APIError.from(error).elderMessage(isSelfManaged: session.isSelfManaged), true)
        }
    }

    private func answer(_ request: CaregiverRequest, approve: Bool) async {
        message = nil
        do {
            if approve {
                try await session.api.approveCaregiverRequest(id: request.id)
                message = ("\(request.name ?? "Diegene") helpt nu mee. U kunt dit altijd weer veranderen.", false)
            } else {
                try await session.api.rejectCaregiverRequest(id: request.id)
                message = ("Goed. \(request.name ?? "Diegene") kijkt niet mee.", false)
            }
            await load()
            await session.load()
        } catch {
            message = (APIError.from(error).elderMessage(isSelfManaged: session.isSelfManaged), true)
        }
    }

    private func revoke(_ invitation: PendingInvitation) async {
        message = nil
        do {
            try await session.api.revokeDeviceInvitation(id: invitation.id)
            message = ("De uitnodiging is ingetrokken. De code werkt niet meer.", false)
            await load()
        } catch {
            message = (APIError.from(error).elderMessage(isSelfManaged: session.isSelfManaged), true)
        }
    }

    private func resumeCalls() async {
        message = nil
        var patch = NoahSettingsPatch()
        patch.outboundPaused = false
        do {
            let settings = try await session.api.updateDeviceSettings(patch)
            // The settings response has no `outboundPaused`; reload /device/me for the truth.
            outboundPaused = settings.outboundPaused ?? false
            await session.load()
            outboundPaused = session.outboundPaused ?? false
            message = ("Goed. Noah mag u weer bellen, zoals het was ingesteld.", false)
        } catch {
            message = (APIError.from(error).elderMessage(isSelfManaged: true), true)
        }
    }

    private func allowNotices() async {
        if await push.requestAuthorization() {
            session.registerForDeviceNotices(push: push)
        }
    }
}

/// A calm section title in the older person's size.
struct ElderSectionTitle: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(NoahFont.Elder.title2).noahElderTitleScaling()
            .foregroundColor(NoahColor.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// v2.4: a phone that was just signed in waits for approval (72 h at most).
struct ElderRestrictedNotice: View {
    @EnvironmentObject private var session: ElderSession

    var body: some View {
        let until = session.restrictedUntil.map { " tot \(DutchFormat.dayAndTime($0))" } ?? ""
        NoahNotice(kind: .info,
                   text: "Deze telefoon is net aangemeld. Daarom kunt u\(until) alleen kort met Noah praten; uw verhaal, herinneringen, noodcontacten, opnames en instellingen zijn nog even afgeschermd, en Noah belt u nog niet. \(session.isSelfManaged ? "Uw andere telefoon" : "Uw andere telefoon of uw familie") kan deze telefoon eerder goedkeuren.",
                   large: true)
            .accessibilityIdentifier("elder.restricted")
    }
}

// MARK: - Shown once

/// "Wie kijkt er mee" once after pairing or signing in (v2.4, while `appShownAt` is null).
struct ElderTransparencyIntroView: View {
    let onMore: () -> Void

    @EnvironmentObject private var session: ElderSession
    @State private var snapshot: TransparencySnapshot?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoahSpacing.l) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 52))
                    .foregroundColor(NoahColor.accent)
                    .accessibilityHidden(true)
                ElderScreenTitle(title: "Wie kijkt er mee")
                if let snapshot {
                    if snapshot.members.isEmpty {
                        ElderText("Op dit moment kijkt er niemand mee. Alleen u en Noah weten wat u vertelt.")
                    } else {
                        ElderText("Deze mensen kunnen zien hoe het met u gaat: \(DutchList.join(snapshot.members.compactMap(\.name))).")
                        NoahCard(padding: NoahSpacing.l) {
                            ElderSectionTitle(text: "Dit zien ze")
                            ForEach(snapshot.familySees, id: \.self) { line in
                                Label {
                                    Text(verbatim: line).font(NoahFont.Elder.label).foregroundColor(NoahColor.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                } icon: {
                                    Image(systemName: "eye.fill").foregroundColor(NoahColor.accent)
                                }
                            }
                        }
                    }
                    ElderText("U beslist hier zelf over. U kunt aanpassen wat uw familie ziet, en u kunt Noah zeggen dat een gesprek alleen voor u is of dat u wilt stoppen. Dit scherm vindt u altijd terug op uw beginscherm, bij \u{201C}Wie kijkt er mee\u{201D}.")
                } else {
                    LoadingStateView(large: true)
                }
                Button("Ik heb het gelezen") { Task { await session.transparencyIntroSeen() } }
                    .buttonStyle(.noah(.primary, size: .elder))
                    .accessibilityIdentifier("transparencyIntro.done")
                Button("Bekijken en aanpassen") {
                    Task {
                        await session.transparencyIntroSeen()
                        onMore()
                    }
                }
                .buttonStyle(.noah(.secondary, size: .elder))
            }
            .padding(.horizontal, NoahSpacing.screen)
            .padding(.vertical, NoahSpacing.xl)
            .noahReadableWidth()
        }
        .noahElderScreenScaling()
        .noahScreenBackground()
        .interactiveDismissDisabled()
        .task { snapshot = try? await session.transparencySnapshot() }
    }
}

// MARK: - What the family sees

struct ElderSharingView: View {
    @EnvironmentObject private var session: ElderSession
    @State private var choice: SharingLevel = .alles
    @State private var saved: SharingLevel?
    @State private var message: (text: String, isError: Bool)?

    var body: some View {
        ElderScrollScreen {
            ElderScreenTitle(title: "Wat ziet uw familie?")
            ElderText("U beslist zelf wat de mensen die meekijken van uw gesprekken zien. Bij nood of grote zorgen krijgen ze altijd een melding, wat u ook kiest.")
            VStack(spacing: NoahSpacing.s) {
                ForEach(SharingLevel.knownCases, id: \.self) { level in
                    NoahOptionCard(title: level.elderLabel, subtitle: level.elderExplanation, isSelected: choice == level, large: true) { choice = level }
                        .accessibilityIdentifier("sharing.\(level.rawValue)")
                }
            }
            ElderText("Uw familie krijgt een berichtje dat u dit heeft aangepast.", color: NoahColor.textSecondary)
            if let message { ElderMessage(text: message.text, isError: message.isError) }
            NoahAsyncButton(size: .elder, action: save) { Text("Bewaar") }
                .disabled(choice == saved)
                .accessibilityIdentifier("sharing.save")
        }
        .task {
            if saved == nil {
                await session.loadTransparency()
                saved = session.transparency?.sharing ?? .alles
                choice = saved ?? .alles
            }
        }
    }

    private func save() async {
        message = nil
        do {
            let updated = try await session.api.updateSharing(choice)
            session.didUpdate(transparency: updated)
            saved = updated.sharing ?? choice
            message = ("Bewaard. Uw familie ziet voortaan: \(choice.elderLabel.lowercased()).", false)
        } catch {
            message = (APIError.from(error).elderMessage(isSelfManaged: session.isSelfManaged), true)
        }
    }
}

// MARK: - Stopping (caregiver-managed)

/// The older person on a family-managed profile can ask for everything to be deleted. The family
/// is told and has 14 days to cancel the store subscription; the person can change their mind.
struct ElderStopView: View {
    @EnvironmentObject private var session: ElderSession
    @State private var request: DeletionRequest?
    @State private var loaded = false
    @State private var isSure = false
    @State private var message: (text: String, isError: Bool)?
    /// v2.4 `409 abonnement_actief`: the family still pays; they are told to stop it.
    @State private var familyStillPays = false

    var body: some View {
        ElderScrollScreen {
            ElderScreenTitle(title: "Stoppen met Noah")
            if let request, let executes = request.executesAt {
                ElderText("U heeft gevraagd om alles van u bij HelloNoah te verwijderen. Dat gebeurt op \(DutchFormat.shortDate(executes)). Uw familie weet het.")
                ElderText("Bent u van gedachten veranderd? Dat kan tot die dag.", color: NoahColor.textSecondary)
                if let message { ElderMessage(text: message.text, isError: message.isError) }
                NoahAsyncButton(size: .elder, action: withdraw) { Text("Toch niet stoppen") }
                    .accessibilityIdentifier("stop.withdraw")
            } else {
                ElderText("U mag altijd stoppen. Als u dat wilt, wordt na 14 dagen alles van u bij HelloNoah gewist: uw gesprekken, uw levensverhaal, opnames en herinneringen.")
                ElderText("Uw familie krijgt daar meteen bericht van, zodat zij ook het abonnement kunnen stoppen. In die 14 dagen kunt u nog van gedachten veranderen.", color: NoahColor.textSecondary)
                ElderText("Wilt u alleen niet meer gebeld worden? Zeg dat dan gewoon tegen Noah, of tegen uw familie.", color: NoahColor.textSecondary)
                if let message { ElderMessage(text: message.text, isError: message.isError) }
                if familyStillPays {
                    NoahNotice(kind: .info, text: "Uw familie betaalt nog een abonnement voor Noah. Zij krijgen bericht dat ze het moeten stoppen; dat hoeft u niet zelf te doen.", large: true)
                    NoahAsyncButton(kind: .destructive, size: .elder, action: { await requestDeletion(acknowledged: true) }) { Text("Ja, toch alles verwijderen over 14 dagen") }
                        .accessibilityIdentifier("stop.confirmAck")
                    Button("Nee, toch niet") { isSure = false; familyStillPays = false }
                        .buttonStyle(.noah(.secondary, size: .elder))
                } else if isSure {
                    NoahAsyncButton(kind: .destructive, size: .elder, action: { await requestDeletion(acknowledged: false) }) { Text("Ja, verwijder alles over 14 dagen") }
                        .accessibilityIdentifier("stop.confirm")
                    Button("Nee, toch niet") { isSure = false }
                        .buttonStyle(.noah(.secondary, size: .elder))
                } else {
                    Button(role: .destructive) { isSure = true } label: { Text("Ik wil stoppen") }
                        .buttonStyle(.noah(.destructive, size: .elder))
                        .accessibilityIdentifier("stop.start")
                }
            }
        }
        .task {
            guard !loaded else { return }
            loaded = true
            await session.loadTransparency()
            request = session.transparency?.deletionRequest
        }
    }

    private func requestDeletion(acknowledged: Bool) async {
        message = nil
        do {
            request = try await session.api.requestDeletion(subscriptionAcknowledged: acknowledged)
            familyStillPays = false
            await session.loadTransparency()
        } catch let apiError as APIError where apiError.isSubscriptionStillActive {
            familyStillPays = true
        } catch {
            message = (APIError.from(error).elderMessage(isSelfManaged: false), true)
        }
    }

    private func withdraw() async {
        message = nil
        do {
            try await session.api.withdrawDeletion()
            request = nil
            isSure = false
            message = ("Goed. Er wordt niets verwijderd.", false)
            await session.loadTransparency()
        } catch {
            message = (APIError.from(error).elderMessage(isSelfManaged: false), true)
        }
    }
}

// MARK: - Phones

/// The phones that can talk to Noah as this person; a new one can be approved or refused (v2.4).
struct ElderDevicesView: View {
    @EnvironmentObject private var session: ElderSession
    @State private var state: Loadable<[PairedDevice]> = .idle
    @State private var message: (text: String, isError: Bool)?
    @State private var confirmReject: PairedDevice?

    var body: some View {
        ElderScrollScreen {
            ElderScreenTitle(title: "Uw telefoons")
            ElderText("Op deze telefoons kan iemand als u met Noah praten. Herkent u een telefoon niet? Weiger hem dan.")
            if let message { ElderMessage(text: message.text, isError: message.isError) }
            LoadableView(state: state, large: true, retry: { Task { await load() } }) { devices in
                ForEach(devices) { device in
                    deviceCard(device)
                }
            }
        }
        .task { await load() }
        .confirmationDialog("Deze telefoon weigeren?", isPresented: Binding(get: { confirmReject != nil }, set: { if !$0 { confirmReject = nil } }), titleVisibility: .visible) {
            Button("Ja, weigeren", role: .destructive) {
                if let device = confirmReject { Task { await reject(device) } }
            }
            Button("Nee", role: .cancel) {}
        } message: {
            Text("Op die telefoon kan dan niet meer met Noah worden gepraat.")
        }
    }

    private func deviceCard(_ device: PairedDevice) -> some View {
        VStack(alignment: .leading, spacing: NoahSpacing.m) {
            AdaptiveStack(verticalAlignment: .center, spacing: NoahSpacing.m) {
                NoahIconBadge(systemName: device.platform == "android" ? "candybarphone" : "iphone", size: 52)
                VStack(alignment: .leading, spacing: NoahSpacing.xxs) {
                    Text(verbatim: (device.deviceName ?? "Telefoon") + (device.isThisDevice ? " (deze telefoon)" : ""))
                        .font(NoahFont.Elder.bodyStrong)
                        .foregroundColor(NoahColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let paired = device.pairedAt {
                        Text("Aangemeld op \(DutchFormat.shortDate(paired))")
                            .font(NoahFont.Elder.label)
                            .foregroundColor(NoahColor.textSoft)
                    }
                    if device.restricted {
                        Text("Wacht op goedkeuring")
                            .font(NoahFont.Elder.label)
                            .foregroundColor(NoahColor.accent)
                    }
                }
                Spacer(minLength: 0)
            }
            if device.restricted, !device.isThisDevice, !session.isRestricted {
                NoahAsyncButton(size: .elder, action: { await approve(device) }) { Text("Goedkeuren") }
                    .accessibilityIdentifier("devices.approve")
            }
            if !device.isThisDevice, !session.isRestricted {
                Button { confirmReject = device } label: {
                    NoahButtonLabel(title: device.restricted ? "Weigeren" : "Ontkoppelen", systemImage: "xmark.circle", iconTint: NoahColor.dangerText)
                }
                .buttonStyle(.noah(.secondary, size: .elder))
            }
        }
        .padding(NoahSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoahRadius.large, style: .continuous).fill(NoahColor.surface))
        .overlay(RoundedRectangle(cornerRadius: NoahRadius.large, style: .continuous).strokeBorder(device.restricted ? NoahColor.accent.opacity(0.8) : NoahColor.border, lineWidth: 1))
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await session.api.deviceDevices())
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled, state.value == nil { state = .failed(apiError) }
        }
    }

    private func approve(_ device: PairedDevice) async {
        message = nil
        do {
            try await session.api.approveDeviceFromDevice(deviceId: device.id)
            message = ("Goedgekeurd. Op die telefoon werkt Noah nu helemaal.", false)
            await load()
        } catch {
            message = (APIError.from(error).elderMessage(isSelfManaged: session.isSelfManaged), true)
        }
    }

    private func reject(_ device: PairedDevice) async {
        message = nil
        do {
            try await session.api.rejectDeviceFromDevice(deviceId: device.id)
            message = ("Die telefoon kan niet meer met Noah praten.", false)
            await load()
        } catch {
            message = (APIError.from(error).elderMessage(isSelfManaged: session.isSelfManaged), true)
        }
    }
}
