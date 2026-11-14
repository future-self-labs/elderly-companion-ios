import SwiftUI

/// Step-by-step profile of the older person. The profile is created after the phone step
/// (the required fields are known then); later steps update it. Every optional step can be skipped.
@MainActor
final class ProfileWizardModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case name, phone, confirmPhone, about, people, preferences, noah, contacts, pair, tellElderly, subscription

        func title(name: String) -> String {
            let who = name.isEmpty ? "je naaste" : name
            switch self {
            case .name: return "Wie gaat er met Noah praten?"
            case .phone: return "Telefoonnummer"
            // Audit H1: confirming is part of setting up, not a hidden card on the profile.
            case .confirmPhone: return "Bevestig het nummer"
            case .about: return "Vertel iets meer"
            case .people: return "Belangrijke mensen"
            // Audit L5: it is about the older person, not about Noah.
            case .preferences: return "Waar praat \(who) graag over?"
            case .noah: return "Noah instellen"
            case .contacts: return "Noodcontacten"
            case .pair: return "Telefoon koppelen"
            // v2.4: tell the older person that family reads along.
            case .tellElderly: return "Vertel het \(who)"
            // Audit L6: the plan name already heads the paywall below.
            case .subscription: return "Abonnement"
            }
        }

        var isOptional: Bool { ![.name, .phone].contains(self) }
    }

    @Published var step: Step = .name
    @Published var input = ElderlyProfileInput()
    @Published var phone = ""
    @Published var phoneError: String?
    @Published var error: String?
    @Published private(set) var profile: ElderlyProfile?
    @Published var people: [Person] = []
    @Published var settings = NoahSettings.defaults
    /// What the server has after the last save in the wizard.
    private var savedSettings: NoahSettings?
    @Published var contacts: [EmergencyContact] = []
    @Published var isWorking = false
    @Published var subscription: Subscription?

    let api: NoahAPI

    init(api: NoahAPI) {
        self.api = api
    }

    var name: String { input.preferredName.isEmpty ? input.firstName : input.preferredName }
    var progress: Double { Double(step.rawValue + 1) / Double(Step.allCases.count) }

    var canContinue: Bool {
        switch step {
        case .name:
            // The preferred name falls back to the first name.
            return !input.firstName.trimmingCharacters(in: .whitespaces).isEmpty
        case .phone:
            return phone.filter(\.isNumber).count >= 9
        default:
            return true
        }
    }

    func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        error = nil
        step = previous
    }

    func skip() {
        error = nil
        advance()
    }

    /// Saves the current step, then moves on. Returns false when something must be fixed.
    func next() async {
        error = nil
        isWorking = true
        defer { isWorking = false }
        do {
            switch step {
            case .name:
                if input.preferredName.trimmingCharacters(in: .whitespaces).isEmpty { input.preferredName = input.firstName }
                if profile != nil { try await saveProfile() }
            case .phone:
                phoneError = nil
                guard let e164 = PhoneNumberFormat.e164(phone) else {
                    phoneError = PhoneNumberFormat.invalidMessage
                    return
                }
                input.phoneNumber = e164
                try await saveProfile()
            case .about, .preferences:
                try await saveProfile()
            case .noah:
                if let id = profile?.id {
                    // A new profile starts with the contract defaults: send only what was changed.
                    let patch = NoahSettingsPatch(from: savedSettings ?? .defaults, to: settings)
                    if !patch.isEmpty {
                        settings = try await api.updateSettings(elderlyId: id, patch)
                        savedSettings = settings
                    }
                }
            case .confirmPhone, .people, .contacts, .pair, .tellElderly, .subscription:
                break
            }
            advance()
        } catch {
            let apiError = APIError.from(error)
            if apiError.code == "phone_number_taken" {
                phoneError = apiError.userMessage
            } else {
                self.error = apiError.userMessage
            }
        }
    }

    private func advance() {
        guard let following = Step(rawValue: step.rawValue + 1) else { return }
        step = following
    }

    private func saveProfile() async throws {
        if let id = profile?.id {
            profile = try await api.updateElderly(id: id, input)
        } else {
            let created = try await api.createElderly(input)
            profile = created
            if let loaded = try? await api.settings(elderlyId: created.id) { settings = loaded }
        }
    }

    func reloadPeople() async {
        guard let id = profile?.id else { return }
        if let items = try? await api.people(elderlyId: id) { people = items }
    }

    func reloadContacts() async {
        guard let id = profile?.id else { return }
        if let items = try? await api.emergencyContacts(elderlyId: id) { contacts = items }
    }

    func refreshProfile() async {
        guard let id = profile?.id else { return }
        if let updated = try? await api.elderly(id: id) { profile = updated }
        subscription = try? await api.subscription(elderlyId: id)
    }

    /// The number was confirmed in the wizard (audit H1).
    func didConfirmPhone(_ updated: ElderlyProfile) {
        profile = updated
    }
}

struct ProfileWizardView: View {
    @EnvironmentObject private var session: CaregiverSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ProfileWizardModel
    @State private var confirmsClose = false
    @State private var addsPerson = false
    @State private var addsContact = false

    init(api: NoahAPI) {
        _model = StateObject(wrappedValue: ProfileWizardModel(api: api))
    }

    var body: some View {
        NavigationStack {
            WizardBody(model: model, onFinish: finish, addsPerson: $addsPerson, addsContact: $addsContact)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Sluiten") {
                            if model.profile == nil { dismiss() } else { confirmsClose = true }
                        }
                    }
                }
        }
        .confirmationDialog("Later verder gaan?", isPresented: $confirmsClose, titleVisibility: .visible) {
            Button("Ja, later verder") { finish() }
            Button("Doorgaan met instellen", role: .cancel) {}
        } message: {
            Text("Het profiel is al bewaard. Je kunt alles later aanvullen via Meer.")
        }
    }

    private func finish() {
        if let id = model.profile?.id {
            Task {
                await session.didAddElderly(id: id)
                dismiss()
            }
        } else {
            dismiss()
        }
    }
}

private struct WizardBody: View {
    @ObservedObject var model: ProfileWizardModel
    let onFinish: () -> Void
    @Binding var addsPerson: Bool
    @Binding var addsContact: Bool

    @EnvironmentObject private var session: CaregiverSession
    /// Audit M1: text typed in a "Toevoegen" field but not added yet is added when saving.
    @State private var tagDrafts = PendingTagDrafts()

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: NoahSpacing.l) {
                    Text(verbatim: model.step.title(name: model.name))
                        .font(NoahFont.largeTitle).noahTitleScaling()
                        .foregroundColor(NoahColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    stepContent
                    if let error = model.error { NoahNotice(kind: .error, text: error) }
                }
                .padding(.horizontal, NoahSpacing.screen)
                .padding(.vertical, NoahSpacing.l)
                .noahReadableWidth()
            }
            // Audit M2: every step starts at the top (a new scroll view per step).
            .id(model.step)
            .scrollDismissesKeyboard(.interactively)
            .environment(\.pendingTagDrafts, tagDrafts)
            if model.step != .subscription { footer }
        }
        .noahScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addsPerson) {
            NavigationStack {
                PersonEditorView(target: .new, elderlyId: model.profile?.id) { Task { await model.reloadPeople() } }
            }
            .environmentObject(session)
        }
        .sheet(isPresented: $addsContact) {
            NavigationStack {
                EmergencyContactEditorView(target: .new, elderlyId: model.profile?.id) { Task { await model.reloadContacts() } }
            }
            .environmentObject(session)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.xs) {
            ProgressView(value: model.progress)
                .tint(NoahColor.accent)
                .accessibilityLabel(Text("Voortgang"))
                .accessibilityValue(Text("Stap \(model.step.rawValue + 1) van \(ProfileWizardModel.Step.allCases.count)"))
            Text("Stap \(model.step.rawValue + 1) van \(ProfileWizardModel.Step.allCases.count)")
                .font(NoahFont.footnote)
                .foregroundColor(NoahColor.textSecondary)
        }
        .padding(.horizontal, NoahSpacing.screen)
        .padding(.top, NoahSpacing.s)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .name:
            Text("Voor wie stel je Noah in? Deze gegevens gebruikt Noah om je naaste persoonlijk aan te spreken.")
                .font(NoahFont.callout).foregroundColor(NoahColor.textSoft).fixedSize(horizontal: false, vertical: true)
            ProfileNameFields(input: $model.input)
        case .phone:
            ProfilePhoneField(phone: $model.phone, error: model.phoneError, name: model.name)
        case .confirmPhone:
            confirmPhoneStep
        case .about:
            ProfileAboutFields(input: $model.input)
        case .people:
            Text("Familie, vrienden of buren over wie \(model.name) graag praat. Noah vraagt naar ze en onthoudt verjaardagen.")
                .font(NoahFont.callout).foregroundColor(NoahColor.textSoft).fixedSize(horizontal: false, vertical: true)
            ForEach(model.people) { person in
                NoahCard {
                    NoahRow(icon: "person.fill", title: person.name, subtitle: person.relation, showsChevron: false)
                }
            }
            Button { addsPerson = true } label: { NoahButtonLabel(title: "Persoon toevoegen", systemImage: "plus") }
                .buttonStyle(.noah(.secondary))
        case .preferences:
            ProfilePreferenceFields(input: $model.input)
        case .noah:
            NoahSettingsForm(settings: $model.settings, elderlyName: model.name)
        case .contacts:
            Text("Wie moet Noah waarschuwen bij een noodgeval? Zet ze op volgorde: de eerste wordt als eerste gebeld.")
                .font(NoahFont.callout).foregroundColor(NoahColor.textSoft).fixedSize(horizontal: false, vertical: true)
            EmergencyNoticeText()
            ForEach(Array(model.contacts.enumerated()), id: \.element.id) { index, contact in
                NoahCard {
                    NoahRow(icon: "\(index + 1).circle.fill", title: contact.name,
                            subtitle: PhoneNumberFormat.display(contact.phoneNumber), showsChevron: false)
                }
            }
            Button { addsContact = true } label: { NoahButtonLabel(title: "Noodcontact toevoegen", systemImage: "plus") }
                .buttonStyle(.noah(.secondary))
        case .pair:
            NoahNotice(kind: .info, text: "Doe dit het liefst als je bij \(model.name) bent: de code is 15 minuten geldig en moet op de telefoon van \(model.name) worden ingevuld. Later kan ook, via Meer › Telefoon koppelen.")
            if let profile = model.profile {
                PairingCodePanel(elderlyId: profile.id, name: model.name, showsTitle: false)
            }
        case .tellElderly:
            if let profile = model.profile {
                TellElderlyPanel(elderlyId: profile.id, name: model.name, addressForm: model.input.addressForm) { model.skip() }
            }
        case .subscription:
            subscriptionStep
        }
    }

    @ViewBuilder
    private var confirmPhoneStep: some View {
        Text("Noah belt alleen naar een bevestigd nummer, zodat Noah nooit iemand anders belt. Tot het nummer van \(model.name) is bevestigd, werken het ochtendgesprek, herinneringen waarbij Noah belt en \u{201C}Laat Noah nu bellen\u{201D} niet. In de app met Noah praten kan wel meteen.")
            .font(NoahFont.callout).foregroundColor(NoahColor.textSoft).fixedSize(horizontal: false, vertical: true)
        if let profile = model.profile {
            if profile.phoneVerified == true {
                Label("Het nummer van \(model.name) is bevestigd. Noah kan bellen.", systemImage: "checkmark.seal.fill")
                    .font(NoahFont.bodyStrong)
                    .foregroundColor(NoahColor.positive)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("wizard.phoneConfirmed")
            } else if profile.phoneVerified == false {
                PhoneConfirmationCard(profile: profile) { model.didConfirmPhone($0) }
                Text("Ben je nu niet bij \(model.name)? Sla dit over; op het overzicht blijft het als volgende stap staan.")
                    .font(NoahFont.footnote).foregroundColor(NoahColor.textSecondary).fixedSize(horizontal: false, vertical: true)
            } else {
                // Older backend without confirmation: nothing to do.
                Text("Je kunt verder.").font(NoahFont.callout).foregroundColor(NoahColor.textSoft)
            }
        }
    }

    @ViewBuilder
    private var subscriptionStep: some View {
        if let profile = model.profile {
            if profile.isBeta || model.subscription?.isPaidOrBeta == true {
                VStack(alignment: .leading, spacing: NoahSpacing.l) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 52)).foregroundColor(NoahColor.positive)
                        .accessibilityHidden(true)
                    Text(profile.isBeta ? "\(model.name) doet mee aan de bètatest: Noah is gratis en meteen actief." : "Noah is actief voor \(model.name).")
                        .font(NoahFont.title3).foregroundColor(NoahColor.text).fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: PaywallView.activeText(name: model.name, phoneConfirmed: profile.phoneVerified))
                        .font(NoahFont.callout).foregroundColor(NoahColor.textSoft).fixedSize(horizontal: false, vertical: true)
                    Button("Klaar", action: onFinish).buttonStyle(.noah(.primary))
                }
            } else {
                PaywallView(elderlyId: profile.id, elderlyName: model.name, showsLater: true, embedded: true,
                            phoneConfirmed: profile.phoneVerified, onDone: onFinish)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: NoahSpacing.xs) {
            Button {
                guard !model.isWorking else { return }
                tagDrafts.commitAll()
                Task {
                    await model.next()
                    if model.step == .subscription { await model.refreshProfile() }
                }
            } label: {
                ZStack {
                    Text([.pair, .confirmPhone, .tellElderly].contains(model.step) ? "Volgende" : "Opslaan en verder").opacity(model.isWorking ? 0 : 1)
                    if model.isWorking { ProgressView().tint(NoahColor.onAccent) }
                }
            }
            .buttonStyle(.noah(.primary))
            .disabled(!model.canContinue)
            .accessibilityIdentifier("wizard.next")

            HStack {
                if model.step != .name {
                    Button {
                        model.back()
                    } label: {
                        Label("Terug", systemImage: "chevron.left").lineLimit(1)
                    }
                    .buttonStyle(.noah(.quiet, size: .compact, fullWidth: false))
                }
                Spacer(minLength: NoahSpacing.s)
                if model.step.isOptional && model.step != .pair {
                    Button(model.step == .confirmPhone || model.step == .tellElderly ? "Later" : "Overslaan") { model.skip() }
                        .lineLimit(1)
                        .buttonStyle(.noah(.quiet, size: .compact, fullWidth: false))
                }
            }
        }
        .padding(.horizontal, NoahSpacing.screen)
        .padding(.vertical, NoahSpacing.s)
        .background(NoahColor.surfaceDeep.ignoresSafeArea(edges: .bottom))
    }
}
