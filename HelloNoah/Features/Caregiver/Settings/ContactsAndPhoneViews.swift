import SwiftUI

// MARK: - Emergency contacts

struct EmergencyContactsView: View {
    @EnvironmentObject private var session: CaregiverSession
    @State private var contacts: [EmergencyContact] = []
    @State private var state: Loadable<Void> = .idle
    @State private var editing: ContactEditorTarget?
    @State private var editMode: EditMode = .inactive
    @State private var error: String?

    var body: some View {
        List {
            Section {
                Text("Bij een noodgeval waarschuwt Noah deze mensen in deze volgorde, per sms en/of telefoon. Ze hebben de app niet nodig. Mantelzorgers met de app krijgen altijd een melding.")
                    .font(NoahFont.callout)
                    .foregroundColor(NoahColor.textSoft)
                    .listRowBackground(Color.clear)
                if !session.permissions.canEditEmergencyContacts {
                    ReadOnlyNotice().listRowBackground(Color.clear)
                }
                if let error {
                    NoahNotice(kind: .error, text: error).listRowBackground(Color.clear)
                }
            }

            Section {
                switch state {
                case .idle, .loading:
                    LoadingStateView().listRowBackground(Color.clear)
                case .failed(let apiError):
                    ErrorStateView(message: apiError.userMessage, isOffline: apiError.isOffline) { Task { await load() } }
                        .listRowBackground(Color.clear)
                case .loaded:
                    if contacts.isEmpty {
                        EmptyStateView(systemImage: "staroflife", title: "Nog geen noodcontacten",
                                       message: "Voeg minstens één persoon toe die Noah kan waarschuwen.")
                            .listRowBackground(Color.clear)
                    }
                    ForEach(Array(contacts.enumerated()), id: \.element.id) { index, contact in
                        Button {
                            if session.permissions.canEditEmergencyContacts { editing = .edit(contact) }
                        } label: {
                            HStack(spacing: NoahSpacing.s) {
                                Text(verbatim: "\(index + 1)")
                                    .font(NoahFont.headline)
                                    .foregroundColor(NoahColor.onAccent)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(NoahColor.accent))
                                    .accessibilityLabel(Text("Prioriteit \(index + 1)"))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: contact.name).font(NoahFont.bodyStrong).foregroundColor(NoahColor.text)
                                    Text(verbatim: [contact.relation?.capitalizedFirst, PhoneNumberFormat.display(contact.phoneNumber)].compactMap { $0 }.joined(separator: " · "))
                                        .font(NoahFont.subheadline).foregroundColor(NoahColor.textSecondary)
                                    Text(verbatim: notifyText(contact))
                                        .font(NoahFont.footnote).foregroundColor(NoahColor.textSoft)
                                }
                            }
                            .frame(minHeight: NoahSize.minTap)
                        }
                        .buttonStyle(.plain)
                        .noahRowBackground()
                    }
                    .onMove(perform: session.permissions.canEditEmergencyContacts ? move : nil)
                    .onDelete(perform: session.permissions.canEditEmergencyContacts ? delete : nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .noahFormStyle()
        .environment(\.editMode, $editMode)
        .navigationTitle("Noodcontacten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.permissions.canEditEmergencyContacts {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if contacts.count > 1 {
                        Button(editMode == .active ? "Klaar" : "Volgorde") {
                            withAnimation { editMode = editMode == .active ? .inactive : .active }
                        }
                    }
                    Button { editing = .new } label: { Image(systemName: "plus") }
                        .accessibilityLabel(Text("Noodcontact toevoegen"))
                }
            }
        }
        .sheet(item: $editing) { target in
            NavigationStack {
                EmergencyContactEditorView(target: target) { Task { await load() } }
            }
            .environmentObject(session)
        }
        .task(id: session.reloadKey) { await load() }
        .refreshable { await load() }
    }

    private func notifyText(_ contact: EmergencyContact) -> String {
        switch (contact.notifyBySms, contact.notifyByCall) {
        case (true, true): return "Sms en telefoon"
        case (true, false): return "Alleen sms"
        case (false, true): return "Alleen telefoon"
        default: return "Wordt niet gewaarschuwd"
        }
    }

    private func load() async {
        guard let id = session.selected?.id else { return }
        if contacts.isEmpty { state = .loading }
        do {
            contacts = try await session.api.emergencyContacts(elderlyId: id)
            state = .loaded(())
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled { state = .failed(apiError) }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        let previous = contacts
        contacts.move(fromOffsets: source, toOffset: destination)
        Task {
            guard let id = session.selected?.id else { return }
            do {
                try await session.api.reorderEmergencyContacts(elderlyId: id, ids: contacts.map(\.id))
                error = nil
            } catch {
                contacts = previous
                self.error = APIError.from(error).userMessage
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let removed = offsets.map { contacts[$0] }
        contacts.remove(atOffsets: offsets)
        Task {
            guard let id = session.selected?.id else { return }
            for contact in removed {
                do {
                    try await session.api.deleteEmergencyContact(elderlyId: id, contactId: contact.id)
                } catch {
                    self.error = APIError.from(error).userMessage
                }
            }
            await load()
        }
    }
}

enum ContactEditorTarget: Identifiable {
    case new
    case edit(EmergencyContact)
    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let contact): return contact.id
        }
    }
}

struct EmergencyContactEditorView: View {
    let target: ContactEditorTarget
    var elderlyId: String?
    let onSaved: () -> Void

    @EnvironmentObject private var session: CaregiverSession
    @Environment(\.dismiss) private var dismiss
    @State private var input = EmergencyContactInput()
    @State private var phone = ""
    @State private var phoneError: String?
    @State private var error: String?
    @State private var didLoad = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoahSpacing.l) {
                NoahTextField(label: "Naam", text: $input.name, prompt: "Mark de Vries", autocapitalization: .words)
                NoahTextField(label: "Telefoonnummer", text: $phone, prompt: "06 12345678", error: phoneError,
                              keyboard: .phonePad, contentType: .telephoneNumber, autocapitalization: .never)
                NoahTextField(label: "Relatie", text: Binding(get: { input.relation ?? "" }, set: { input.relation = $0 }), prompt: "zoon")
                VStack(spacing: NoahSpacing.s) {
                    Toggle(isOn: $input.notifyBySms) { Text("Waarschuwen per sms").font(NoahFont.bodyText).foregroundColor(NoahColor.text) }
                    Toggle(isOn: $input.notifyByCall) { Text("Waarschuwen met een telefoontje").font(NoahFont.bodyText).foregroundColor(NoahColor.text) }
                }
                .noahInputBox()
                if let error { NoahNotice(kind: .error, text: error) }
            }
            .padding(NoahSpacing.screen)
        }
        .noahScreenBackground()
        .navigationTitle(isNew ? "Noodcontact toevoegen" : "Noodcontact")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuleren") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                AsyncToolbarButton(title: "Bewaar", isDisabled: input.name.trimmingCharacters(in: .whitespaces).isEmpty || phone.isEmpty) { await save() }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if case .edit(let contact) = target {
                input = EmergencyContactInput(name: contact.name, phoneNumber: contact.phoneNumber, relation: contact.relation,
                                              notifyBySms: contact.notifyBySms, notifyByCall: contact.notifyByCall)
                phone = PhoneNumberFormat.display(contact.phoneNumber)
            }
        }
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    private func save() async {
        phoneError = nil
        guard let e164 = PhoneNumberFormat.e164(phone) else {
            phoneError = "Dit lijkt geen geldig telefoonnummer."
            return
        }
        guard let id = elderlyId ?? session.selected?.id else { return }
        input.phoneNumber = e164
        input.relation = input.relation.nilIfBlank
        do {
            switch target {
            case .new: _ = try await session.api.createEmergencyContact(elderlyId: id, input)
            case .edit(let contact): _ = try await session.api.updateEmergencyContact(elderlyId: id, contactId: contact.id, input)
            }
            onSaved()
            dismiss()
        } catch {
            self.error = APIError.from(error).userMessage
        }
    }
}

// MARK: - Phone line

struct PhoneLineView: View {
    @EnvironmentObject private var session: CaregiverSession
    @State private var state: Loadable<PhoneLine> = .idle
    @State private var addsContact = false

    var body: some View {
        NoahScrollScreen {
            LoadableView(state: state, retry: { Task { await load() } }) { line in
                let name = session.selected?.preferredName ?? "je naaste"
                Text("Bellen met Noah, zonder app")
                    .font(NoahFont.title).noahTitleScaling()
                    .foregroundColor(NoahColor.text)
                    .accessibilityAddTraits(.isHeader)
                NoahCard(padding: NoahSpacing.l) {
                    NoahEyebrow(text: "Telefoonnummer van Noah")
                    Text(verbatim: line.displayNumber ?? PhoneNumberFormat.display(line.phoneNumber))
                        .font(NoahFont.display(38, relativeTo: .largeTitle)).noahTitleScaling()
                        .foregroundColor(NoahColor.accent)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("phoneLine.number")
                    if let instructions = line.instructions {
                        Text(verbatim: instructions)
                            .font(NoahFont.callout)
                            .foregroundColor(NoahColor.textSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                NoahCard {
                    stepRow(1, "Zet het nummer in de telefoon van \(name), bijvoorbeeld onder de naam \u{201C}Noah\u{201D}.")
                    stepRow(2, "\(name) belt het nummer, wanneer hij of zij maar wil. Ook \u{2019}s nachts.")
                    stepRow(3, "Noah herkent het nummer van \(name) en neemt meteen op. Bellen vanaf een ander nummer werkt niet.")
                }
                if session.selected?.access != .active {
                    NoahNotice(kind: .warning, text: "Het nummer werkt pas als het abonnement van \(name) actief is.")
                }
                if let url = URL(string: "tel://\(line.phoneNumber)") {
                    Link(destination: url) { NoahButtonLabel(title: "Bel Noah nu", systemImage: "phone.fill") }
                        .buttonStyle(.noah(.primary))
                }
                Button { addsContact = true } label: {
                    NoahButtonLabel(title: "Zet in contacten", systemImage: "person.crop.circle.badge.plus")
                }
                .buttonStyle(.noah(.secondary))
                ShareLink(item: "Je kunt Noah altijd bellen op \(line.displayNumber ?? line.phoneNumber). Noah herkent je nummer en neemt meteen op.") {
                    NoahButtonLabel(title: "Stuur het nummer naar \(name)", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.noah(.secondary))
            }
        }
        .navigationTitle("Telefoonnummer")
        .navigationBarTitleDisplayMode(.inline)
        .task { if state.value == nil { await load() } }
        .sheet(isPresented: $addsContact) {
            if let line = state.value {
                NewContactView(name: "Noah", phoneNumber: line.phoneNumber) { addsContact = false }
                    .ignoresSafeArea()
            }
        }
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
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

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await session.api.phoneLine())
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled { state = .failed(apiError) }
        }
    }
}
