import SwiftUI

// MARK: - Caregivers & invitations

struct CaregiversView: View {
    @EnvironmentObject private var session: CaregiverSession
    @State private var state: Loadable<[CaregiverMembership]> = .idle
    @State private var invites = false
    @State private var error: String?
    @State private var confirmRemove: CaregiverMembership?
    /// Audit M4: "Maak beheerder" is confirmed first.
    @State private var confirmPromote: CaregiverMembership?
    @State private var invitationsReload = 0

    var body: some View {
        NoahScrollScreen(spacing: NoahSpacing.m) {
            Text("Zorg je samen? Nodig familie uit om mee te kijken. Een beheerder kan alles instellen, een lezer kan alleen meelezen. Iedereen die meekijkt, leest de samenvattingen en de uitgeschreven gesprekken.")
                .font(NoahFont.callout)
                .foregroundColor(NoahColor.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            if let error { NoahNotice(kind: .error, text: error) }
            LoadableView(state: state, retry: { Task { await load() } }) { members in
                NoahCard(padding: NoahSpacing.s) {
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                        if index > 0 { Divider().overlay(NoahColor.divider) }
                        memberRow(member, members: members)
                    }
                }
            }
            if let id = session.selected?.id, session.permissions.canInvite {
                PendingInvitationsSection(elderlyId: id, reloadToken: invitationsReload)
            }
            if session.permissions.canInvite {
                Button { invites = true } label: {
                    NoahButtonLabel(title: "Iemand uitnodigen", systemImage: "person.badge.plus")
                }
                .buttonStyle(.noah(.primary))
                .accessibilityIdentifier("caregivers.invite")
            }
        }
        .navigationTitle("Mantelzorgers")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.reloadKey) { await load() }
        .sheet(isPresented: $invites, onDismiss: { invitationsReload += 1 }) {
            NavigationStack { InviteCaregiverView() }
                .environmentObject(session)
        }
        .confirmationDialog(promoteTitle, isPresented: Binding(get: { confirmPromote != nil }, set: { if !$0 { confirmPromote = nil } }), titleVisibility: .visible) {
            Button("Ja, maak beheerder") {
                if let member = confirmPromote { Task { await setRole(member, .beheerder) } }
            }
            Button("Annuleren", role: .cancel) {}
        } message: {
            Text("Een beheerder kan alles: instellingen en noodcontacten wijzigen, het abonnement regelen, anderen toevoegen of verwijderen en het profiel verwijderen.")
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }), titleVisibility: .visible) {
            Button(confirmRemove?.isMe == true ? "Stoppen met meekijken" : "Verwijderen", role: .destructive) {
                if let member = confirmRemove { Task { await remove(member) } }
            }
            Button("Annuleren", role: .cancel) {}
        }
    }

    private var promoteTitle: String {
        "\(confirmPromote?.name ?? "Deze mantelzorger") beheerder maken?"
    }

    private var confirmTitle: String {
        guard let member = confirmRemove else { return "" }
        return member.isMe ? "Wil je stoppen met meekijken?" : "\(member.name ?? "Deze mantelzorger") verwijderen?"
    }

    private func memberRow(_ member: CaregiverMembership, members: [CaregiverMembership]) -> some View {
        HStack(spacing: NoahSpacing.s) {
            NoahAvatar(name: member.name ?? "?", size: 40, tint: member.role == .beheerder ? NoahColor.accent : NoahColor.textSoft)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: (member.name ?? "Mantelzorger") + (member.isMe ? " (jij)" : ""))
                    .font(NoahFont.bodyStrong).foregroundColor(NoahColor.text)
                Text(verbatim: member.role.label + (member.joinedAt.map { " · sinds \(DutchFormat.shortDate($0))" } ?? ""))
                    .font(NoahFont.subheadline).foregroundColor(NoahColor.textSecondary)
            }
            Spacer()
            if session.permissions.canManageCaregivers || member.isMe {
                Menu {
                    if session.permissions.canManageCaregivers && !member.isMe {
                        Button(member.role == .beheerder ? "Maak lezer" : "Maak beheerder") {
                            if member.role == .beheerder {
                                Task { await setRole(member, .lezer) }
                            } else {
                                confirmPromote = member
                            }
                        }
                    }
                    Button(member.isMe ? "Stoppen met meekijken" : "Verwijderen", role: .destructive) { confirmRemove = member }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(NoahFont.title3)
                        .foregroundColor(NoahColor.accent)
                        .frame(width: NoahSize.minTap, height: NoahSize.minTap)
                }
                .accessibilityLabel(Text("Opties voor \(member.name ?? "mantelzorger")"))
            }
        }
        .frame(minHeight: NoahSize.minTap)
    }

    private func load() async {
        guard let id = session.selected?.id else { return }
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await session.api.caregivers(elderlyId: id))
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled { state = .failed(apiError) }
        }
    }

    private func setRole(_ member: CaregiverMembership, _ role: Role) async {
        guard let id = session.selected?.id else { return }
        do {
            try await session.api.updateCaregiverRole(elderlyId: id, caregiverId: member.caregiverId, role: role)
            error = nil
            await load()
        } catch {
            self.error = APIError.from(error).userMessage
        }
    }

    private func remove(_ member: CaregiverMembership) async {
        guard let id = session.selected?.id else { return }
        do {
            try await session.api.removeCaregiver(elderlyId: id, caregiverId: member.caregiverId)
            error = nil
            if member.isMe {
                await session.reloadMe()
                session.dataChanged()
            } else {
                await load()
            }
        } catch {
            self.error = APIError.from(error).userMessage
        }
    }
}

struct InviteCaregiverView: View {
    @EnvironmentObject private var session: CaregiverSession
    @Environment(\.dismiss) private var dismiss
    @State private var role: Role = .lezer
    @State private var invitation: Invitation?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoahSpacing.l) {
                if let invitation {
                    Text("Uitnodiging klaar")
                        .font(NoahFont.title).noahTitleScaling()
                        .foregroundColor(NoahColor.text)
                    NoahCard(padding: NoahSpacing.l) {
                        NoahEyebrow(text: "Code")
                        Text(verbatim: invitation.code)
                            .font(NoahFont.display(44, relativeTo: .largeTitle)).noahTitleScaling()
                            .foregroundColor(NoahColor.accent)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("invite.generatedCode")
                        if let expires = invitation.expiresAt {
                            Text("Geldig tot \(DutchFormat.shortDate(expires)). Rol: \(role.label.lowercased()).")
                                .font(NoahFont.footnote)
                                .foregroundColor(NoahColor.textSecondary)
                        }
                    }
                    ShareLink(item: invitation.shareText ?? "Ik nodig je uit om mee te kijken bij Noah. Code: \(invitation.code) \(invitation.url ?? "")") {
                        NoahButtonLabel(title: "Deel de uitnodiging", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.noah(.primary))
                    Text("De ander installeert HelloNoah, logt in en vult deze code in (of tikt op de link).")
                        .font(NoahFont.callout)
                        .foregroundColor(NoahColor.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // Audit L13: the screen asks for a role, so it says so.
                    Text("Welke rol krijgt diegene?")
                        .font(NoahFont.title).noahTitleScaling()
                        .foregroundColor(NoahColor.text)
                    NoahField(label: "Rol") {
                        VStack(spacing: NoahSpacing.s) {
                            NoahOptionCard(title: Role.lezer.label, subtitle: Role.lezer.explanation, isSelected: role == .lezer) { role = .lezer }
                            NoahOptionCard(title: Role.beheerder.label, subtitle: Role.beheerder.explanation, isSelected: role == .beheerder) { role = .beheerder }
                        }
                    }
                    Text("De uitnodiging is 7 dagen geldig. Tot hij is gebruikt, kun je hem intrekken bij Mantelzorgers.")
                        .font(NoahFont.footnote).foregroundColor(NoahColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error { NoahNotice(kind: .error, text: error) }
                    NoahAsyncButton("Maak uitnodiging") { await create() }
                }
            }
            .padding(NoahSpacing.screen)
        }
        .noahScreenBackground()
        .navigationTitle("Uitnodigen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(invitation == nil ? "Annuleren" : "Klaar") { dismiss() } }
        }
    }

    private func create() async {
        guard let id = session.selected?.id else { return }
        do {
            invitation = try await session.api.createInvitation(elderlyId: id, role: role)
        } catch {
            self.error = APIError.from(error).userMessage
        }
    }
}

// MARK: - Devices

struct DevicesView: View {
    @EnvironmentObject private var session: CaregiverSession
    @State private var state: Loadable<[PairedDevice]> = .idle
    @State private var confirmUnpair: PairedDevice?
    @State private var error: String?

    var body: some View {
        NoahScrollScreen(spacing: NoahSpacing.m) {
            if let error { NoahNotice(kind: .error, text: error) }
            LoadableView(state: state, retry: { Task { await load() } }) { devices in
                if devices.isEmpty {
                    EmptyStateView(systemImage: "iphone.slash", title: "Nog geen telefoon gekoppeld",
                                   message: "Koppel de telefoon van \(session.selected?.preferredName ?? "je naaste"), dan kan hij of zij met één tik met Noah praten.")
                } else {
                    ForEach(devices) { device in
                        NoahCard {
                            HStack(spacing: NoahSpacing.s) {
                                NoahIconBadge(systemName: device.platform == "android" ? "candybarphone" : "iphone")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: device.deviceName ?? "Telefoon").font(NoahFont.bodyStrong).foregroundColor(NoahColor.text)
                                    if let paired = device.pairedAt {
                                        Text("Gekoppeld op \(DutchFormat.shortDate(paired))").font(NoahFont.subheadline).foregroundColor(NoahColor.textSecondary)
                                    }
                                    if let seen = device.lastSeenAt {
                                        Text("Laatst gebruikt \(DutchFormat.relativeDay(seen))").font(NoahFont.footnote).foregroundColor(NoahColor.textSoft)
                                    }
                                    if device.restricted {
                                        Text("Nieuw aangemeld, wacht op goedkeuring").font(NoahFont.footnote).foregroundColor(NoahColor.accent)
                                    }
                                }
                                Spacer()
                                if session.permissions.canManageDevices {
                                    Button(device.restricted ? "Weiger" : "Ontkoppel") { confirmUnpair = device }
                                        .font(NoahFont.subheadline)
                                        .foregroundColor(NoahColor.dangerText)
                                        .frame(minHeight: NoahSize.minTap)
                                }
                            }
                            if device.restricted, session.permissions.canManageDevices {
                                Text("Iemand heeft zich met het nummer van \(session.selected?.preferredName ?? "je naaste") aangemeld op een nieuwe telefoon. Tot je die goedkeurt (of na 72 uur) kan daar alleen kort met Noah worden gepraat. Herken je dit niet? Weiger hem.")
                                    .font(NoahFont.footnote).foregroundColor(NoahColor.textSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                                NoahAsyncButton("Goedkeuren", kind: .secondary, size: .compact) { await approve(device) }
                                    .accessibilityIdentifier("devices.approve")
                            }
                        }
                    }
                }
            }
            if session.permissions.canPair {
                NavigationLink(value: CaregiverRoute.pairDevice) {
                    NoahButtonLabel(title: "Telefoon koppelen", systemImage: "plus")
                }
                .buttonStyle(.noah(.primary))
            }
        }
        .navigationTitle("Gekoppelde telefoons")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.reloadKey) { await load() }
        .confirmationDialog("Telefoon ontkoppelen?", isPresented: Binding(get: { confirmUnpair != nil }, set: { if !$0 { confirmUnpair = nil } }), titleVisibility: .visible) {
            Button("Ontkoppelen", role: .destructive) {
                if let device = confirmUnpair { Task { await unpair(device) } }
            }
            Button("Annuleren", role: .cancel) {}
        } message: {
            Text("Op deze telefoon kan dan meteen niet meer met Noah worden gepraat. Je kunt hem later opnieuw koppelen.")
        }
    }

    private func load() async {
        guard let id = session.selected?.id else { return }
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await session.api.devices(elderlyId: id))
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled { state = .failed(apiError) }
        }
    }

    private func approve(_ device: PairedDevice) async {
        guard let id = session.selected?.id else { return }
        do {
            try await session.api.approveDevice(elderlyId: id, deviceId: device.id)
            error = nil
            await load()
        } catch {
            self.error = APIError.from(error).userMessage
        }
    }

    private func unpair(_ device: PairedDevice) async {
        guard let id = session.selected?.id else { return }
        do {
            try await session.api.unpairDevice(elderlyId: id, deviceId: device.id)
            error = nil
            await load()
        } catch {
            self.error = APIError.from(error).userMessage
        }
    }
}

struct PairDeviceView: View {
    @EnvironmentObject private var session: CaregiverSession

    var body: some View {
        NoahScrollScreen {
            if let selected = session.selected {
                PairingCodePanel(elderlyId: selected.id, name: selected.preferredName)
            }
        }
        .navigationTitle("Telefoon koppelen")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The welcome screen's pairing choice, named exactly the same in every instruction (audit H3).
enum PairingCopy {
    static let welcomeButton = "Deze telefoon koppelen met een code"
}

/// Shows a fresh pairing code big, with step-by-step instructions (also used in the wizard).
struct PairingCodePanel: View {
    let elderlyId: String
    let name: String
    var showsTitle = true

    @EnvironmentObject private var session: CaregiverSession
    @State private var code: PairingCode?
    @State private var error: APIError?
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            if showsTitle {
                Text("Koppel de telefoon van \(name)")
                    .font(NoahFont.title).noahTitleScaling()
                    .foregroundColor(NoahColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            NoahCard(padding: NoahSpacing.l) {
                if let code {
                    let remaining = code.expiresAt.timeIntervalSince(now)
                    NoahEyebrow(text: "Koppelcode")
                    Text(verbatim: spaced(code.code))
                        .font(NoahFont.display(52, relativeTo: .largeTitle)).noahTitleScaling()
                        .foregroundColor(remaining > 0 ? NoahColor.accent : NoahColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .textSelection(.enabled)
                        .accessibilityLabel(Text("Code: \(code.code.map(String.init).joined(separator: " "))"))
                        .accessibilityIdentifier("pair.code")
                    Group {
                        if remaining > 0 {
                            Text("Nog \(Int(remaining) / 60):\(String(format: "%02d", Int(remaining) % 60)) geldig, één keer te gebruiken.")
                                .foregroundColor(NoahColor.textSecondary)
                        } else {
                            Text("Deze code is verlopen. Maak een nieuwe code.")
                                .foregroundColor(NoahColor.dangerText)
                        }
                    }
                    .font(NoahFont.footnote)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                } else if let error {
                    ErrorStateView(message: error.userMessage, isOffline: error.isOffline) { Task { await generate() } }
                } else {
                    LoadingStateView(message: "Code maken…")
                }
            }
            NoahCard {
                step(1, "Installeer HelloNoah op de iPhone of Android-telefoon van \(name), via de App Store of Google Play.")
                // Audit H3: the exact name of the button on the welcome screen.
                step(2, "Open de app en kies \u{201C}\(PairingCopy.welcomeButton)\u{201D}. Niet \u{201C}Ik wil zelf met Noah praten\u{201D}: dat maakt een tweede profiel.")
                step(3, "Vul de koppelcode in. Klaar: \(name) hoeft nooit in te loggen. Daarna ziet \(name) eenmalig wie er meekijkt.")
            }
            if let code {
                ShareLink(item: "Koppelcode voor HelloNoah: \(code.code). Open de app, kies \u{201C}\(PairingCopy.welcomeButton)\u{201D} en vul de code in. De code is 15 minuten geldig.") {
                    NoahButtonLabel(title: "Stuur de code", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.noah(.secondary))
            }
            NoahAsyncButton(kind: .quiet, action: generate) {
                NoahButtonLabel(title: "Nieuwe code", systemImage: "arrow.clockwise")
            }
        }
        .onReceive(timer) { now = $0 }
        .task { if code == nil { await generate() } }
    }

    private func spaced(_ code: String) -> String {
        code.count == 6 ? "\(code.prefix(3)) \(code.suffix(3))" : code
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: NoahSpacing.s) {
            Text(verbatim: "\(number)")
                .font(NoahFont.headline)
                .foregroundColor(NoahColor.onAccent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(NoahColor.accent))
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(NoahFont.callout)
                .foregroundColor(NoahColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func generate() async {
        error = nil
        do {
            code = try await session.api.createPairingCode(elderlyId: elderlyId)
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled { self.error = apiError }
        }
    }
}
