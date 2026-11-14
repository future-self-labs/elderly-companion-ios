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
        NoahTextField(label: "Mobiel of vast nummer van \(name.isEmpty ? "je naaste" : name)", text: $phone, prompt: phone.isEmpty ? "Nog geen telefoonnummer" : "06 12345678",
                      footnote: "Noah belt naar dit nummer voor herinneringen en het ochtendgesprek, zodra het nummer is bevestigd. Alleen Nederlandse en Belgische nummers.",
                      error: error, keyboard: .phonePad, contentType: .telephoneNumber, autocapitalization: .never)
            .accessibilityIdentifier("profile.phone")
    }
}

enum BirthYear {
    static var range: ClosedRange<Int> { 1900...DutchFormat.calendar.component(.year, from: Date()) }
}

struct ProfileAboutFields: View {
    @Binding var input: ElderlyProfileInput
    @State private var birthYearText = ""

    private var birthYearError: String? {
        let digits = birthYearText.filter(\.isNumber)
        guard input.birthYear == nil, digits.count == 4 else { return nil }
        return "Vul een geboortejaar in tussen 1900 en \(BirthYear.range.upperBound)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            NoahTextField(label: "Geboortejaar", text: Binding(
                get: { input.birthYear.map(String.init) ?? birthYearText },
                set: { value in
                    birthYearText = value
                    let digits = value.filter(\.isNumber)
                    // Audit L4: like the backend, 1900 up to this year.
                    if digits.count == 4, let year = Int(digits), BirthYear.range.contains(year) {
                        input.birthYear = year
                    } else {
                        input.birthYear = nil
                    }
                }
            ), prompt: "1941", error: birthYearError, keyboard: .numberPad)
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
    @EnvironmentObject private var router: CaregiverRouter
    @EnvironmentObject private var app: AppModel
    @State private var state: Loadable<ElderlyProfile> = .idle
    @State private var input = ElderlyProfileInput()
    @State private var original = ElderlyProfileInput()
    @State private var phone = ""
    @State private var phoneError: String?
    @State private var message: (text: String, isError: Bool)?
    @State private var share: ShareItem?
    @State private var showsDelete = false
    @State private var tagDrafts = PendingTagDrafts()

    var body: some View {
        NoahScrollScreen {
            if !session.permissions.canEditProfile { ReadOnlyNotice() }
            LoadableView(state: state, retry: { Task { await load() } }) { profile in
                if session.permissions.canEditProfile, profile.needsTellingElderly {
                    NoahNotice(kind: .info, text: "Heb je \(profile.preferredName) al verteld dat je de gesprekken kunt teruglezen?",
                               actionTitle: "Vertel het \(profile.preferredName)") { router.show(.tellElderly, in: .more) }
                        .accessibilityIdentifier("profile.tellReminder")
                }
                if let sharing = profile.sharing, sharing != .alles {
                    NoahNotice(kind: .info, text: sharing.caregiverExplanation(name: profile.preferredName))
                }
                VStack(alignment: .leading, spacing: NoahSpacing.xl) {
                    section("Naam en aanspreekvorm") { ProfileNameFields(input: $input) }
                    section("Telefoonnummer") {
                        ProfilePhoneField(phone: $phone, error: phoneError, name: input.preferredName)
                        if !profile.hasPhoneNumber {
                            Text("\(profile.preferredName) heeft nog geen telefoonnummer. Noah kan dan niet bellen; praten in de app kan wel.")
                                .font(NoahFont.footnote).foregroundColor(NoahColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // v2.2: Noah only calls a confirmed number (shown for the saved number only).
                        if session.permissions.canEditProfile, profile.hasPhoneNumber, phone == PhoneNumberFormat.display(profile.phoneNumber) {
                            if profile.needsPhoneConfirmation {
                                PhoneConfirmationCard(profile: profile) { updated in
                                    state = .loaded(updated)
                                    session.dataChanged()
                                }
                            } else if profile.phoneVerified == true {
                                Label("Nummer bevestigd", systemImage: "checkmark.seal.fill")
                                    .font(NoahFont.subheadline)
                                    .foregroundColor(NoahColor.positive)
                                    .accessibilityIdentifier("profile.phoneVerified")
                            }
                        }
                    }
                    section("Over \(input.preferredName)") { ProfileAboutFields(input: $input) }
                    section("Voorkeuren") { ProfilePreferenceFields(input: $input) }
                }
                .disabled(!session.permissions.canEditProfile)
                .environment(\.pendingTagDrafts, tagDrafts)

                if let message { NoahNotice(kind: message.isError ? .error : .success, text: message.text) }

                if session.permissions.canEditProfile {
                    NoahAsyncButton("Bewaar profiel") { _ = await save(profile) }
                        .disabled(!hasChanges(profile))
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
                        .foregroundColor(NoahColor.dangerText)
                    }
                }
            }
        }
        .navigationTitle("Profiel")
        .navigationBarTitleDisplayMode(.inline)
        .unsavedChangesGuard(hasChanges: session.permissions.canEditProfile && state.value.map(hasChanges) == true) {
            guard let profile = state.value else { return true }
            return await save(profile)
        }
        .task(id: session.reloadKey) { await load() }
        .sheet(item: $share, onDismiss: ExportFile.removeAll) { item in ActivityView(items: item.items) }
        .sheet(isPresented: $showsDelete) {
            if let profile = state.value {
                NavigationStack {
                    TypedConfirmationView(
                        title: "\(profile.preferredName) verwijderen",
                        explanation: "Alles van \(profile.preferredName) wordt definitief verwijderd: het profiel, alle gesprekken, het levensverhaal, herinneringen en gekoppelde telefoons. Dit kan niet ongedaan worden gemaakt.",
                        buttonTitle: "Definitief verwijderen",
                        subscriptionWarning: "Verwijderen stopt een abonnement in de App Store niet. Zeg het op via Abonnement beheren (of Instellingen › je naam › Abonnementen), anders loopt de betaling door."
                    ) { acknowledged in
                        try await session.api.deleteElderly(id: profile.id, subscriptionAcknowledged: acknowledged)
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

    private func hasChanges(_ profile: ElderlyProfile) -> Bool {
        input != original || phone != PhoneNumberFormat.display(profile.phoneNumber)
    }

    /// - Returns: true when saved.
    private func save(_ profile: ElderlyProfile) async -> Bool {
        phoneError = nil
        // Audit M1: text typed in a "Toevoegen" field is kept.
        tagDrafts.commitAll()
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        if trimmedPhone.isEmpty {
            // v2.4: a profile may have no number; never send an empty one.
            input.phoneNumber = ""
        } else {
            guard let e164 = PhoneNumberFormat.e164(phone) else {
                phoneError = PhoneNumberFormat.invalidMessage
                return false
            }
            input.phoneNumber = e164
        }
        guard !input.firstName.trimmingCharacters(in: .whitespaces).isEmpty, !input.preferredName.trimmingCharacters(in: .whitespaces).isEmpty else {
            message = ("Vul de voornaam en de roepnaam in.", true)
            return false
        }
        do {
            let updated = try await session.api.updateElderly(id: profile.id, input)
            input = ElderlyProfileInput(profile: updated)
            original = input
            phone = PhoneNumberFormat.display(updated.phoneNumber)
            state = .loaded(updated)
            message = ("Opgeslagen.", false)
            await session.reloadMe()
            return true
        } catch {
            let apiError = APIError.from(error)
            if apiError.code == "phone_number_taken" { phoneError = apiError.userMessage } else { message = (apiError.userMessage, true) }
            return false
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

/// "Bevestig het nummer" (v2.2): Noah only calls out to a confirmed number. Confirmed by one
/// inbound call to Noah, or by a code sent to the number (SMS, or read out for a landline).
struct PhoneConfirmationCard: View {
    let profile: ElderlyProfile
    let onConfirmed: (ElderlyProfile) -> Void

    @EnvironmentObject private var session: CaregiverSession
    @State private var sentVia: PhoneVerificationChannel?
    @State private var code = ""
    @State private var error: String?

    private var number: String { PhoneNumberFormat.display(profile.phoneNumber) }

    var body: some View {
        NoahCard(padding: NoahSpacing.l, border: NoahColor.accent.opacity(0.7)) {
            Label("Bevestig het nummer", systemImage: "checkmark.shield.fill")
                .font(NoahFont.headline)
                .foregroundColor(NoahColor.text)
            Text("Noah belt alleen naar een bevestigd nummer, zodat Noah nooit iemand anders belt. Bevestigen kan op twee manieren: \(profile.preferredName) belt één keer zelf naar het telefoonnummer van Noah, of je stuurt een code naar \(number).")
                .font(NoahFont.callout)
                .foregroundColor(NoahColor.textSoft)
                .fixedSize(horizontal: false, vertical: true)

            if let sentVia {
                Text(sentVia == .call
                     ? "Noah belt \(number) en leest een code van 6 cijfers voor. Vul die hieronder in."
                     : "Er is een sms met een code van 6 cijfers gestuurd naar \(number). Vraag \(profile.preferredName) om de code, of kijk samen op de telefoon.")
                    .font(NoahFont.callout)
                    .foregroundColor(NoahColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                NoahCodeField(code: $code) { Task { await verify() } }
                    .accessibilityIdentifier("profile.phoneCode")
                NoahAsyncButton("Bevestigen", action: verify)
                    .disabled(code.count != 6)
                    .accessibilityIdentifier("profile.phoneVerify")
                Button("Opnieuw versturen") {
                    self.sentVia = nil
                    code = ""
                    error = nil
                }
                .buttonStyle(.noah(.quiet))
            } else {
                NoahAsyncButton(kind: .secondary, action: { await send(.sms) }) {
                    NoahButtonLabel(title: "Stuur een code per sms", systemImage: "message.fill")
                }
                .accessibilityIdentifier("profile.phoneSendSms")
                NoahAsyncButton(kind: .quiet, action: { await send(.call) }) {
                    Text("Vaste lijn? Laat de code voorlezen")
                }
            }
            if let error { NoahNotice(kind: .error, text: error) }
        }
        .accessibilityIdentifier("profile.phoneConfirmation")
    }

    private func send(_ channel: PhoneVerificationChannel) async {
        error = nil
        do {
            let result = try await session.api.startPhoneVerification(elderlyId: profile.id, channel: channel)
            if result.isAlreadyConfirmed {
                onConfirmed(try await session.api.elderly(id: profile.id))
            } else {
                sentVia = channel
            }
        } catch {
            self.error = APIError.from(error).userMessage
        }
    }

    private func verify() async {
        guard code.count == 6 else { return }
        error = nil
        do {
            onConfirmed(try await session.api.verifyPhone(elderlyId: profile.id, code: code))
        } catch {
            let apiError = APIError.from(error)
            self.error = apiError.code == "ongeldige_code" ? "Deze code klopt niet of is verlopen. Probeer het opnieuw of stuur een nieuwe code." : apiError.userMessage
            code = ""
        }
    }
}

/// "Typ VERWIJDER om te bevestigen" for irreversible deletes.
struct TypedConfirmationView: View {
    let title: String
    let explanation: String
    let buttonTitle: LocalizedStringKey
    /// Audit M10: a deletion never stops the store subscription; shown as its own card.
    var subscriptionWarning: String?
    /// - Parameter acknowledged: v2.4 `subscriptionAcknowledged` (after `409 abonnement_actief`).
    let action: (_ acknowledged: Bool) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppModel
    @State private var typed = ""
    @State private var error: String?
    /// The server said a subscription still runs: confirm once more (v2.4).
    @State private var needsAck = false
    @State private var acknowledged = false

    private let word = "VERWIJDER"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoahSpacing.l) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(NoahColor.dangerText)
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .font(NoahFont.title).noahTitleScaling()
                    .foregroundColor(NoahColor.text)
                Text(verbatim: explanation)
                    .font(NoahFont.bodyText)
                    .foregroundColor(NoahColor.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if let subscriptionWarning {
                    SubscriptionWarningCard(text: subscriptionWarning)
                }
                NoahTextField(label: "Typ VERWIJDER om te bevestigen", text: $typed, prompt: "VERWIJDER", autocapitalization: .characters)
                    .accessibilityIdentifier("confirm.typed")
                if needsAck {
                    NoahNotice(kind: .warning, text: "Er loopt nog een abonnement in de App Store. Dat stopt niet als je verwijdert.")
                    Toggle(isOn: $acknowledged) {
                        Text("Ik weet dat ik het abonnement zelf moet opzeggen").font(NoahFont.bodyStrong).foregroundColor(NoahColor.text)
                    }
                    .noahInputBox()
                    .accessibilityIdentifier("confirm.subscriptionAck")
                }
                if let error { NoahNotice(kind: .error, text: error) }
                NoahAsyncButton(kind: .destructive, action: run) { Text(buttonTitle) }
                    .disabled(typed.trimmingCharacters(in: .whitespaces) != word || (needsAck && !acknowledged))
                    .accessibilityIdentifier("confirm.delete")
                Link(destination: app.environment.config.accountDeletionURL) {
                    Text("Meer over verwijderen: hellonoah.ai/account-verwijderen")
                }
                .font(NoahFont.footnote)
                .foregroundColor(NoahColor.accent)
                .frame(minHeight: NoahSize.minTap)
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
        error = nil
        do {
            try await action(needsAck && acknowledged)
            dismiss()
        } catch {
            let apiError = APIError.from(error)
            if apiError.isSubscriptionStillActive {
                needsAck = true
            } else {
                self.error = apiError.userMessage
            }
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
                        .foregroundColor(NoahColor.dangerText)
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
