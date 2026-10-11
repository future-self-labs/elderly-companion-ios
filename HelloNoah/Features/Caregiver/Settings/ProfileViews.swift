import SwiftUI

// MARK: - Shared form sections (wizard + profile screen)

struct ProfileNameFields: View {
    @Binding var input: ElderlyProfileInput

    var body: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            NoahTextField(label: "Voornaam", text: $input.firstName, prompt: "Willem", autocapitalization: .words)
                .accessibilityIdentifier("profile.firstName")
            NoahTextField(label: "Achternaam (optioneel)", text: Binding(get: { input.lastName ?? "" }, set: { input.lastName = $0 }),
                          prompt: "de Vries", autocapitalization: .words)
            NoahTextField(label: "Hoe wil hij of zij genoemd worden?", text: $input.preferredName, prompt: "Wim",
                          footnote: "Noah gebruikt deze naam in de gesprekken.", autocapitalization: .words)
                .accessibilityIdentifier("profile.preferredName")
            NoahField(label: "Aanspreekvorm", footnote: "Noah zegt standaard \u{201C}u\u{201D}. Kies \u{201C}jij\u{201D} als dat vertrouwder voelt.") {
                VStack(spacing: NoahSpacing.s) {
                    NoahOptionCard(title: "Met \u{201C}u\u{201D}", subtitle: "\u{201C}Hoe gaat het met u?\u{201D}", isSelected: input.addressForm == .u) { input.addressForm = .u }
                    NoahOptionCard(title: "Met \u{201C}jij\u{201D}", subtitle: "\u{201C}Hoe gaat het met je?\u{201D}", isSelected: input.addressForm == .jij) { input.addressForm = .jij }
                }
            }
            NoahField(label: "Geslacht (optioneel)", footnote: "Alleen voor de juiste Nederlandse zinnen, zoals \u{201C}meneer\u{201D} of \u{201C}mevrouw\u{201D}.") {
                FlowLayout {
                    ForEach([Gender.man, .vrouw, .anders], id: \.self) { gender in
                        NoahChoiceChip(title: gender.label, isSelected: input.gender == gender) {
                            input.gender = input.gender == gender ? nil : gender
                        }
                    }
                }
            }
        }
    }
}

struct ProfilePhoneField: View {
    @Binding var phone: String
    var error: String?
    let name: String

    var body: some View {
        NoahTextField(label: "Mobiel of vast nummer van \(name.isEmpty ? "je naaste" : name)", text: $phone, prompt: "06 12345678",
                      footnote: "Noah herkent dit nummer als er gebeld wordt, en belt naar dit nummer voor herinneringen en het ochtendgesprek.",
                      error: error, keyboard: .phonePad, contentType: .telephoneNumber, autocapitalization: .never)
            .accessibilityIdentifier("profile.phone")
    }
}

struct ProfileAboutFields: View {
    @Binding var input: ElderlyProfileInput
    @State private var birthYearText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            NoahTextField(label: "Geboortejaar", text: Binding(
                get: { input.birthYear.map(String.init) ?? birthYearText },
                set: { value in
                    birthYearText = value
                    let digits = value.filter(\.isNumber)
                    input.birthYear = digits.count == 4 ? Int(digits) : nil
                }
            ), prompt: "1941", keyboard: .numberPad)
            NoahTextField(label: "Woonplaats", text: Binding(get: { input.city ?? "" }, set: { input.city = $0 }), prompt: "Haarlem", autocapitalization: .words)
            NoahField(label: "Woonsituatie") {
                FlowLayout {
                    ForEach(LivingSituation.knownCases, id: \.self) { situation in
                        NoahChoiceChip(title: situation.label, isSelected: input.livingSituation == situation) {
                            input.livingSituation = input.livingSituation == situation ? nil : situation
                        }
                    }
                }
            }
            NoahTextField(label: "Over \(input.preferredName.isEmpty ? "je naaste" : input.preferredName)",
                          text: Binding(get: { input.about ?? "" }, set: { input.about = $0 }),
                          prompt: "Bijvoorbeeld: oud-onderwijzer, houdt van tuinieren, weduwnaar sinds 2019",
                          footnote: "Een paar zinnen helpen Noah om echt een gesprek te voeren.", multiline: true)
        }
    }
}

struct ProfilePreferenceFields: View {
    @Binding var input: ElderlyProfileInput

    var body: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            NoahTagEditor(label: "Houdt van", tags: $input.likes, prompt: "Tuinieren")
            NoahTagEditor(label: "Houdt niet van", tags: $input.dislikes, prompt: "Politiek")
            NoahTagEditor(label: "Onderwerpen om over te beginnen", tags: $input.topicsToRaise, prompt: "De kleinkinderen")
            NoahTagEditor(label: "Liever vermijden", tags: $input.topicsToAvoid, prompt: "Een gevoelig onderwerp",
                          footnote: "Noah begint hier zelf niet over.")
            NoahTextField(label: "Vaste gewoontes", text: Binding(get: { input.routines ?? "" }, set: { input.routines = $0 }),
                          prompt: "Staat om 7:30 op, wandelt na de lunch", multiline: true)
            NoahTextField(label: "Notitie voor Noah", text: Binding(get: { input.caregiverNotes ?? "" }, set: { input.caregiverNotes = $0 }),
                          prompt: "Bijvoorbeeld: dinsdag een afspraak bij de huisarts",
                          footnote: "Noah neemt dit mee in de volgende gesprekken.", multiline: true)
        }
    }
}

// MARK: - Profile screen

struct ElderlyProfileView: View {
    @EnvironmentObject private var session: CaregiverSession
    @EnvironmentObject private var app: AppModel
    @State private var state: Loadable<ElderlyProfile> = .idle
    @State private var input = ElderlyProfileInput()
    @State private var original = ElderlyProfileInput()
    @State private var phone = ""
    @State private var phoneError: String?
    @State private var message: (text: String, isError: Bool)?
    @State private var share: ShareItem?
    @State private var showsDelete = false

    var body: some View {
        NoahScrollScreen {
            if !session.permissions.canEditProfile { ReadOnlyNotice() }
            LoadableView(state: state, retry: { Task { await load() } }) { profile in
                VStack(alignment: .leading, spacing: NoahSpacing.xl) {
                    section("Naam en aanspreekvorm") { ProfileNameFields(input: $input) }
                    section("Telefoonnummer") { ProfilePhoneField(phone: $phone, error: phoneError, name: input.preferredName) }
                    section("Over \(input.preferredName)") { ProfileAboutFields(input: $input) }
                    section("Voorkeuren") { ProfilePreferenceFields(input: $input) }
                }
                .disabled(!session.permissions.canEditProfile)

                if let message { NoahNotice(kind: message.isError ? .error : .success, text: message.text) }

                if session.permissions.canEditProfile {
                    NoahAsyncButton("Bewaar profiel") { await save(profile) }
                        .disabled(input == original && phone == PhoneNumberFormat.display(profile.phoneNumber))
                }

                if session.permissions.canExportProfile {
                    VStack(alignment: .leading, spacing: NoahSpacing.s) {
                        NoahEyebrow(text: "Gegevens")
                        NoahAsyncButton(kind: .secondary, action: { await export(profile) }) {
                            NoahButtonLabel(title: "Gegevens van \(profile.preferredName) exporteren", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) { showsDelete = true } label: {
                            NoahButtonLabel(title: "Profiel verwijderen", systemImage: "trash")
                        }
                        .buttonStyle(.noah(.quiet))
                        .foregroundColor(NoahColor.danger)
                    }
                }
            }
        }
        .navigationTitle("Profiel")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.reloadKey) { await load() }
        .sheet(item: $share) { item in ActivityView(items: item.items) }
        .sheet(isPresented: $showsDelete) {
            if let profile = state.value {
                NavigationStack {
                    TypedConfirmationView(
                        title: "\(profile.preferredName) verwijderen",
                        explanation: "Alles van \(profile.preferredName) wordt definitief verwijderd: het profiel, alle gesprekken, het levensverhaal, herinneringen en gekoppelde telefoons. Het abonnement stop je apart via je Apple ID. Dit kan niet ongedaan worden gemaakt.",
                        buttonTitle: "Definitief verwijderen"
                    ) {
                        try await session.api.deleteElderly(id: profile.id)
                        await session.reloadMe()
                        session.dataChanged()
                    }
                }
                .environmentObject(session)
            }
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        let body = content()
        return VStack(alignment: .leading, spacing: NoahSpacing.m) {
            Text(title).font(NoahFont.title3).foregroundColor(NoahColor.text).accessibilityAddTraits(.isHeader)
            body
        }
    }

    private func load() async {
        guard let id = session.selected?.id else { return }
        if state.value?.id != id { state = .loading }
        do {
            let profile = try await session.api.elderly(id: id)
            input = ElderlyProfileInput(profile: profile)
            original = input
            phone = PhoneNumberFormat.display(profile.phoneNumber)
            state = .loaded(profile)
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled { state = .failed(apiError) }
        }
    }

    private func save(_ profile: ElderlyProfile) async {
        phoneError = nil
        guard let e164 = PhoneNumberFormat.e164(phone) else {
            phoneError = "Dit lijkt geen geldig telefoonnummer. Gebruik bijvoorbeeld 06 12345678."
            return
        }
        guard !input.firstName.trimmingCharacters(in: .whitespaces).isEmpty, !input.preferredName.trimmingCharacters(in: .whitespaces).isEmpty else {
            message = ("Vul de voornaam en de roepnaam in.", true)
            return
        }
        input.phoneNumber = e164
        do {
            let updated = try await session.api.updateElderly(id: profile.id, input)
            input = ElderlyProfileInput(profile: updated)
            original = input
            state = .loaded(updated)
            message = ("Opgeslagen.", false)
            await session.reloadMe()
        } catch {
            let apiError = APIError.from(error)
            if apiError.code == "phone_number_taken" { phoneError = apiError.userMessage } else { message = (apiError.userMessage, true) }
        }
    }

    private func export(_ profile: ElderlyProfile) async {
        do {
            let data = try await session.api.exportElderly(id: profile.id)
            share = ShareItem(items: [try ExportFile.write(data, name: "HelloNoah-\(profile.preferredName)")])
        } catch {
            message = (APIError.from(error).userMessage, true)
        }
    }
}

/// "Typ VERWIJDER om te bevestigen" for irreversible deletes.
struct TypedConfirmationView: View {
    let title: String
    let explanation: String
    let buttonTitle: LocalizedStringKey
    let action: () async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var error: String?

    private let word = "VERWIJDER"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoahSpacing.l) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(NoahColor.danger)
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .font(NoahFont.title).noahTitleScaling()
                    .foregroundColor(NoahColor.text)
                Text(verbatim: explanation)
                    .font(NoahFont.bodyText)
                    .foregroundColor(NoahColor.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
                NoahTextField(label: "Typ VERWIJDER om te bevestigen", text: $typed, prompt: "VERWIJDER", autocapitalization: .characters)
                    .accessibilityIdentifier("confirm.typed")
                if let error { NoahNotice(kind: .error, text: error) }
                NoahAsyncButton(kind: .destructive, action: run) { Text(buttonTitle) }
                    .disabled(typed.trimmingCharacters(in: .whitespaces) != word)
                    .accessibilityIdentifier("confirm.delete")
            }
            .padding(NoahSpacing.screen)
            .noahReadableWidth()
        }
        .noahScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuleren") { dismiss() } }
        }
    }

    private func run() async {
        do {
            try await action()
            dismiss()
        } catch {
            self.error = APIError.from(error).userMessage
        }
    }
}

// MARK: - Important people

struct PeopleView: View {
    @EnvironmentObject private var session: CaregiverSession
    @State private var state: Loadable<[Person]> = .idle
    @State private var editing: PersonEditorTarget?

    var body: some View {
        NoahScrollScreen(spacing: NoahSpacing.m) {
            Text("Wie zijn belangrijk voor \(session.selected?.preferredName ?? "je naaste")? Noah gebruikt dit om naar ze te vragen en verjaardagen te onthouden.")
                .font(NoahFont.callout)
                .foregroundColor(NoahColor.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            if !session.permissions.canEditPeople { ReadOnlyNotice() }
            LoadableView(state: state, retry: { Task { await load() } }) { people in
                if people.isEmpty {
                    EmptyStateView(systemImage: "person.2", title: "Nog niemand toegevoegd",
                                   actionTitle: session.permissions.canEditPeople ? "Persoon toevoegen" : nil) { editing = .new }
                } else {
                    ForEach(people) { person in
                        Button {
                            if session.permissions.canEditPeople { editing = .edit(person) }
                        } label: {
                            NoahCard {
                                NoahRow(icon: person.isDeceased ? "heart.slash" : "person.fill", title: person.name,
                                        subtitle: personSubtitle(person), showsChevron: session.permissions.canEditPeople)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Belangrijke mensen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if session.permissions.canEditPeople {
                    Button { editing = .new } label: { Image(systemName: "plus") }
                        .accessibilityLabel(Text("Persoon toevoegen"))
                }
            }
        }
        .sheet(item: $editing) { target in
            NavigationStack {
                PersonEditorView(target: target) { Task { await load() } }
            }
            .environmentObject(session)
        }
        .task(id: session.reloadKey) { await load() }
    }

    private func personSubtitle(_ person: Person) -> String {
        var parts: [String] = []
        if let relation = person.relation { parts.append(relation.capitalizedFirst) }
        if person.isDeceased { parts.append("overleden") }
        if let birthday = person.birthday, let date = DutchFormat.day(from: birthday) {
            parts.append("jarig op \(DutchFormat.shortDate(date).components(separatedBy: " ").prefix(2).joined(separator: " "))")
        }
        if person.createdBy == .noah { parts.append("toegevoegd door Noah") }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        guard let id = session.selected?.id else { return }
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await session.api.people(elderlyId: id))
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled { state = .failed(apiError) }
        }
    }
}

enum PersonEditorTarget: Identifiable {
    case new
    case edit(Person)
    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let person): return person.id
        }
    }
}

struct PersonEditorView: View {
    let target: PersonEditorTarget
    var elderlyId: String?
    let onSaved: () -> Void

    @EnvironmentObject private var session: CaregiverSession
    @Environment(\.dismiss) private var dismiss
    @State private var input = PersonInput()
    @State private var hasBirthday = false
    @State private var birthday = DutchFormat.calendar.date(from: DateComponents(year: 1970, month: 1, day: 1)) ?? Date()
    @State private var error: String?
    @State private var confirmsDelete = false
    @State private var didLoad = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoahSpacing.l) {
                NoahTextField(label: "Naam", text: $input.name, prompt: "Sara", autocapitalization: .words)
                NoahTextField(label: "Relatie", text: Binding(get: { input.relation ?? "" }, set: { input.relation = $0 }), prompt: "kleindochter")
                VStack(alignment: .leading, spacing: NoahSpacing.s) {
                    Toggle(isOn: $hasBirthday) { Text("Verjaardag bekend").font(NoahFont.bodyText).foregroundColor(NoahColor.text) }
                    if hasBirthday {
                        DatePicker("Verjaardag", selection: $birthday, displayedComponents: .date)
                            .environment(\.timeZone, DutchFormat.timeZone)
                            .environment(\.locale, DutchFormat.locale)
                    }
                }
                .noahInputBox()
                Toggle(isOn: $input.isDeceased) { Text("Overleden").font(NoahFont.bodyText).foregroundColor(NoahColor.text) }
                    .noahInputBox()
                NoahTextField(label: "Notitie", text: Binding(get: { input.notes ?? "" }, set: { input.notes = $0 }),
                              prompt: "Bijvoorbeeld: komt op zaterdag langs", multiline: true)
                if let error { NoahNotice(kind: .error, text: error) }
                if case .edit = target {
                    Button(role: .destructive) { confirmsDelete = true } label: { NoahButtonLabel(title: "Verwijderen", systemImage: "trash") }
                        .buttonStyle(.noah(.quiet))
                        .foregroundColor(NoahColor.danger)
                }
            }
            .padding(NoahSpacing.screen)
        }
        .noahScreenBackground()
        .navigationTitle(isNew ? "Persoon toevoegen" : "Persoon bewerken")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuleren") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                AsyncToolbarButton(title: "Bewaar", isDisabled: input.name.trimmingCharacters(in: .whitespaces).isEmpty) { await save() }
            }
        }
        .confirmationDialog("Deze persoon verwijderen?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Verwijderen", role: .destructive) { Task { await delete() } }
            Button("Annuleren", role: .cancel) {}
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if case .edit(let person) = target {
                input = PersonInput(name: person.name, relation: person.relation, notes: person.notes, birthday: person.birthday, isDeceased: person.isDeceased)
                if let value = person.birthday, let date = DutchFormat.day(from: value) {
                    hasBirthday = true
                    birthday = date
                }
            }
        }
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    private var targetElderlyId: String? { elderlyId ?? session.selected?.id }

    private func save() async {
        guard let id = targetElderlyId else { return }
        input.birthday = hasBirthday ? DutchFormat.dayString(birthday) : nil
        do {
            switch target {
            case .new: _ = try await session.api.createPerson(elderlyId: id, input)
            case .edit(let person): _ = try await session.api.updatePerson(elderlyId: id, personId: person.id, input)
            }
            onSaved()
            dismiss()
        } catch {
            self.error = APIError.from(error).userMessage
        }
    }

    private func delete() async {
        guard let id = targetElderlyId, case .edit(let person) = target else { return }
        do {
            try await session.api.deletePerson(elderlyId: id, personId: person.id)
            onSaved()
            dismiss()
        } catch {
            self.error = APIError.from(error).userMessage
        }
    }
}
