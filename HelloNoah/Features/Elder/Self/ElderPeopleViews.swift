import SwiftUI

// MARK: - Noodcontacten

/// The people Noah warns, by SMS and a call, when the older person says things are not well.
struct ElderEmergencyContactsView: View {
    @EnvironmentObject private var session: ElderSession
    @State private var state: Loadable<[EmergencyContact]> = .idle
    @State private var editing: ContactEditorTarget?

    var body: some View {
        ElderScrollScreen {
            ElderScreenTitle(title: "Noodcontacten")
            ElderText("Vertelt u Noah dat het niet goed met u gaat? Dan waarschuwt Noah deze mensen, in deze volgorde, met een sms en een telefoontje. Ze hebben de app niet nodig.")
            NoahNotice(kind: .info, text: "Noah is geen alarmcentrale. Bij direct gevaar belt u altijd 112.", large: true)
            LoadableView(state: state, large: true, retry: { Task { await load() } }) { contacts in
                if contacts.isEmpty {
                    EmptyStateView(systemImage: "staroflife", title: "Nog niemand",
                                   message: "Voeg iemand toe die Noah mag waarschuwen, bijvoorbeeld een kind, buur of goede vriend.",
                                   large: true)
                }
                ForEach(Array(contacts.enumerated()), id: \.element.id) { index, contact in
                    VStack(alignment: .leading, spacing: NoahSpacing.s) {
                        Button { editing = .edit(contact) } label: {
                            contactCard(contact, number: index + 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(Text("Wijzigen of verwijderen"))
                        if index > 0 {
                            // Audit L28: the order matters ("in deze volgorde"), so it can be changed.
                            NoahAsyncButton(kind: .quiet, size: .elder, action: { await moveUp(index, in: contacts) }) {
                                NoahButtonLabel(title: "Eerder waarschuwen", systemImage: "arrow.up")
                            }
                            .accessibilityLabel(Text("\(contact.name) eerder waarschuwen"))
                        }
                    }
                }
                if contacts.count >= EmergencyContactLimit.max {
                    ElderText("U heeft het maximum van \(EmergencyContactLimit.max) noodcontacten. Wilt u iemand anders toevoegen? Verwijder dan eerst iemand.", color: NoahColor.textSecondary)
                }
            }
            if (state.value?.count ?? 0) < EmergencyContactLimit.max {
                Button { editing = .new } label: {
                    NoahButtonLabel(title: "Iemand toevoegen", systemImage: "person.badge.plus")
                }
                .buttonStyle(.noah(.primary, size: .elder))
                .accessibilityIdentifier("contacts.add")
            }
            ElderText("Laat het de mensen die u toevoegt even weten: ze krijgen een sms of telefoontje van Noah als het niet goed met u gaat.", color: NoahColor.textSecondary)
        }
        .task { await load() }
        .sheet(item: $editing) { target in
            NavigationStack {
                ElderContactEditorView(target: target) { Task { await load() } }
            }
            .environmentObject(session)
        }
    }

    private func contactCard(_ contact: EmergencyContact, number: Int) -> some View {
        HStack(alignment: .top, spacing: NoahSpacing.m) {
            Text(verbatim: "\(number)")
                .font(NoahFont.Elder.bodyStrong)
                .foregroundColor(NoahColor.onAccent)
                .frame(width: 44, height: 44)
                .background(Circle().fill(NoahColor.accent))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: NoahSpacing.xxs) {
                Text(verbatim: contact.name)
                    .font(NoahFont.Elder.bodyStrong)
                    .foregroundColor(NoahColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: [contact.relation?.capitalizedFirst, PhoneNumberFormat.display(contact.phoneNumber)].compactMap { $0 }.joined(separator: " · "))
                    .font(NoahFont.Elder.label)
                    .foregroundColor(NoahColor.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "pencil")
                .font(NoahFont.Elder.label)
                .foregroundColor(NoahColor.accent)
                .accessibilityHidden(true)
        }
        .padding(NoahSpacing.l)
        .frame(maxWidth: .infinity, minHeight: NoahSize.elderButton, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoahRadius.large, style: .continuous).fill(NoahColor.surface))
        .overlay(RoundedRectangle(cornerRadius: NoahRadius.large, style: .continuous).strokeBorder(NoahColor.border, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: NoahRadius.large))
    }

    private func moveUp(_ index: Int, in contacts: [EmergencyContact]) async {
        var ids = contacts.map(\.id)
        ids.swapAt(index, index - 1)
        try? await session.api.reorderDeviceEmergencyContacts(ids: ids)
        await load()
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await session.api.deviceEmergencyContacts())
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled { state = .failed(apiError) }
        }
    }
}

struct ElderContactEditorView: View {
    let target: ContactEditorTarget
    let onSaved: () -> Void

    @EnvironmentObject private var session: ElderSession
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var relation = ""
    @State private var notifyBySms = true
    @State private var notifyByCall = true
    @State private var phoneError: String?
    @State private var error: String?
    @State private var confirmsDelete = false
    @State private var didLoad = false

    private var existing: EmergencyContact? {
        if case .edit(let contact) = target { return contact }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoahSpacing.l) {
                ElderScreenTitle(title: existing == nil ? "Iemand toevoegen" : "Noodcontact")
                ElderContactFields(name: $name, phone: $phone, phoneError: phoneError)
                NoahTextField(label: "Wat is deze persoon van u?", text: $relation, prompt: "dochter, buurman…",
                              footnote: "Mag leeg blijven.", large: true)
                VStack(spacing: NoahSpacing.m) {
                    Toggle(isOn: $notifyBySms) { Text("Waarschuwen met een sms").font(NoahFont.Elder.body).foregroundColor(NoahColor.text) }
                    Toggle(isOn: $notifyByCall) { Text("Waarschuwen met een telefoontje").font(NoahFont.Elder.body).foregroundColor(NoahColor.text) }
                }
                .noahInputBox(large: true)
                if let error { ElderMessage(text: error) }
                if !notifyBySms && !notifyByCall {
                    ElderText("Kies minstens één manier, anders kan Noah deze persoon niet waarschuwen.", color: NoahColor.dangerText)
                }
                NoahAsyncButton(size: .elder, action: save) { Text("Bewaar") }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || phone.filter(\.isNumber).count < 9 || (!notifyBySms && !notifyByCall))
                    .accessibilityIdentifier("contactEditor.save")
                Button("Annuleren") { dismiss() }
                    .buttonStyle(.noah(.secondary, size: .elder))
                if existing != nil {
                    Button(role: .destructive) { confirmsDelete = true } label: {
                        NoahButtonLabel(title: "Verwijderen", systemImage: "trash")
                    }
                    .buttonStyle(.noah(.quiet, size: .elder))
                    .foregroundColor(NoahColor.dangerText)
                    .accessibilityIdentifier("contactEditor.delete")
                }
            }
            .padding(NoahSpacing.screen)
            .noahReadableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .noahElderScreenScaling()
        .noahScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let contact = existing {
                name = contact.name
                phone = PhoneNumberFormat.display(contact.phoneNumber)
                relation = contact.relation ?? ""
                notifyBySms = contact.notifyBySms
                notifyByCall = contact.notifyByCall
            }
        }
        .confirmationDialog("Wilt u \(existing?.name ?? "deze persoon") verwijderen?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Ja, verwijderen", role: .destructive) { Task { await delete() } }
            Button("Nee", role: .cancel) {}
        } message: {
            Text("Noah waarschuwt diegene dan niet meer als het niet goed met u gaat.")
        }
    }

    private func save() async {
        error = nil
        phoneError = nil
        guard let e164 = PhoneNumberFormat.e164(phone) else {
            phoneError = PhoneNumberFormat.invalidMessage
            return
        }
        let input = EmergencyContactInput(name: name.trimmingCharacters(in: .whitespaces), phoneNumber: e164,
                                          relation: relation.nilIfEmpty, notifyBySms: notifyBySms, notifyByCall: notifyByCall)
        do {
            if let contact = existing {
                _ = try await session.api.updateDeviceEmergencyContact(contactId: contact.id, input)
            } else {
                _ = try await session.api.createDeviceEmergencyContact(input)
            }
            onSaved()
            dismiss()
        } catch {
            let apiError = APIError.from(error)
            if apiError.code == "ongeldige_invoer" { phoneError = PhoneNumberFormat.invalidMessage } else { self.error = apiError.elderMessage(isSelfManaged: session.isSelfManaged) }
        }
    }

    private func delete() async {
        guard let contact = existing else { return }
        do {
            try await session.api.deleteDeviceEmergencyContact(contactId: contact.id)
            onSaved()
            dismiss()
        } catch {
            self.error = APIError.from(error).elderMessage(isSelfManaged: session.isSelfManaged)
        }
    }
}

// MARK: - Familie uitnodigen

/// Invite family: choose "meekijken" (lezer) or "helpen beheren" (beheerder), then the share sheet.
struct ElderInviteView: View {
    @EnvironmentObject private var session: ElderSession
    @State private var role: Role = .lezer
    @State private var invitation: Invitation?
    @State private var error: String?
    /// v2.4: "helpen beheren" is confirmed first (`confirmed: true`).
    @State private var confirmsBeheerder = false

    var body: some View {
        ElderScrollScreen {
            ElderScreenTitle(title: "Familie uitnodigen")
            if let invitation {
                ElderText("De uitnodiging is klaar. Stuur hem naar de persoon die u wilt uitnodigen, bijvoorbeeld met WhatsApp, een sms of e-mail.")
                NoahCard(padding: NoahSpacing.l) {
                    NoahEyebrow(text: "Code")
                    Text(verbatim: invitation.code)
                        .font(NoahFont.display(44, relativeTo: .largeTitle)).noahElderTitleScaling()
                        .foregroundColor(NoahColor.accent)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("invite.code")
                    ElderText("\(role.elderLabel)" + (invitation.expiresAt.map { ". Geldig tot \(DutchFormat.shortDate($0))." } ?? "."), color: NoahColor.textSecondary)
                }
                ShareLink(item: shareText(invitation)) {
                    NoahButtonLabel(title: "Stuur de uitnodiging", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.noah(.primary, size: .elder))
                .accessibilityIdentifier("invite.share")
                ElderText("Diegene installeert de HelloNoah-app, kiest \u{201C}Ik ben mantelzorger\u{201D} en tikt op de link of vult de code in. Heeft u zich vergist? Bij \u{201C}Wie kijkt er mee\u{201D} kunt u de uitnodiging intrekken.", color: NoahColor.textSecondary)
                Button("Nog iemand uitnodigen") { self.invitation = nil }
                    .buttonStyle(.noah(.secondary, size: .elder))
            } else {
                ElderText("Nodig iemand uit uw familie uit, of een goede vriend. Diegene kan dan zien hoe het met u gaat.")
                NoahField(label: "Wat mag diegene doen?", large: true) {
                    VStack(spacing: NoahSpacing.s) {
                        NoahOptionCard(title: Role.lezer.elderLabel, subtitle: Role.lezer.elderExplanation, isSelected: role == .lezer, large: true) { role = .lezer }
                            .accessibilityIdentifier("invite.lezer")
                        NoahOptionCard(title: Role.beheerder.elderLabel, subtitle: Role.beheerder.elderExplanation, isSelected: role == .beheerder, large: true) { role = .beheerder }
                            .accessibilityIdentifier("invite.beheerder")
                    }
                }
                if role == .beheerder {
                    NoahNotice(kind: .warning, text: "Deze persoon kan dan alles lezen, instellen en verwijderen. U kunt diegene later zelf weer verwijderen, bij \u{201C}Wie kijkt er mee\u{201D}. Als diegene de uitnodiging aanneemt, vraagt de app u eerst nog of het goed is.", large: true)
                }
                if let error { ElderMessage(text: error) }
                Button {
                    if role == .beheerder { confirmsBeheerder = true } else { Task { await create() } }
                } label: { Text("Maak de uitnodiging") }
                .buttonStyle(.noah(.primary, size: .elder))
                .accessibilityIdentifier("invite.create")
            }
        }
        .confirmationDialog("Mag deze persoon helpen beheren?", isPresented: $confirmsBeheerder, titleVisibility: .visible) {
            Button("Ja, maak de uitnodiging") { Task { await create() } }
            Button("Nee", role: .cancel) {}
        } message: {
            Text("Deze persoon kan dan alles lezen, instellen en verwijderen. U kunt diegene later zelf weer verwijderen.")
        }
    }

    private func shareText(_ invitation: Invitation) -> String {
        invitation.shareText ?? "Ik gebruik Noah en nodig je uit om mee te kijken. Installeer de HelloNoah-app en gebruik deze code: \(invitation.code) \(invitation.url ?? "")"
    }

    private func create() async {
        error = nil
        do {
            invitation = try await session.api.createDeviceInvitation(role: role, confirmed: role == .beheerder)
        } catch {
            self.error = APIError.from(error).elderMessage(isSelfManaged: session.isSelfManaged)
        }
    }
}
