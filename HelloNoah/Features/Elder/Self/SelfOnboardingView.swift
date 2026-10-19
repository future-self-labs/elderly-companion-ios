import SwiftUI

/// v2.3 self route, steps 2–5 (step 1, the phone number and code, comes before the device token):
/// "Hoe mag Noah u noemen?" + u/jij → Noah's voice → someone to warn (strongly suggested, may be
/// skipped) → subscription (or try the free first conversation first) → home.
struct SelfOnboardingView: View {
    enum Step: Int, CaseIterable {
        case name = 2, voice, contact, subscription
    }

    static let totalSteps = 5

    @EnvironmentObject private var session: ElderSession
    @State private var step: Step = .name
    @State private var name = ""
    @State private var addressForm: AddressForm = .u
    @State private var voice: NoahVoice = .vrouw
    @State private var savedSettings: NoahSettings?
    @State private var contactName = ""
    @State private var contactPhone = ""
    @State private var phoneError: String?
    @State private var error: String?
    @State private var didPrefill = false
    @State private var isPaid = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: NoahSpacing.l) {
                    Color.clear.frame(height: 0).id("top")
                    if step != .name, !isPaid {
                        backButton
                    }
                    switch step {
                    case .name: nameStep
                    case .voice: voiceStep
                    case .contact: contactStep
                    case .subscription:
                        ElderPaywallView(showsTryFirst: true, step: (step.rawValue, Self.totalSteps),
                                         onActivated: { isPaid = true }) {
                            session.finishOnboarding()
                        }
                    }
                }
                .padding(.horizontal, NoahSpacing.screen)
                .padding(.vertical, NoahSpacing.l)
                .noahReadableWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: step) { _ in proxy.scrollTo("top", anchor: .top) }
        }
        .noahElderScreenScaling()
        .noahScreenBackground()
        .task { await prefill() }
        .onAppear(perform: applyDebugRoute)
    }

    private var backButton: some View {
        Button {
            error = nil
            if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
        } label: {
            HStack(spacing: NoahSpacing.s) {
                Image(systemName: "chevron.left").accessibilityHidden(true)
                Text("Terug")
            }
            .font(NoahFont.Elder.bodyStrong)
            .foregroundColor(NoahColor.text)
            .padding(.horizontal, NoahSpacing.l)
            .frame(minHeight: NoahSize.elderMinTap)
            .background(Capsule().fill(NoahColor.surface))
            .overlay(Capsule().strokeBorder(NoahColor.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.back")
    }

    // MARK: Step 2: name and "u"/"jij"

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            ElderStepHeader(step: Step.name.rawValue, total: Self.totalSteps, title: "Hoe mag Noah u noemen?")
            ElderText("Bijvoorbeeld uw voornaam, of de naam die uw vrienden gebruiken.")
            NoahTextField(label: "Uw naam", text: $name, prompt: "Toos", contentType: .givenName,
                          autocapitalization: .words, large: true)
                .accessibilityIdentifier("onboarding.name")
            NoahField(label: "Hoe mag Noah tegen u praten?", large: true) {
                VStack(spacing: NoahSpacing.s) {
                    NoahOptionCard(title: "Met \u{201C}u\u{201D}", subtitle: AddressForm.u.elderExample,
                                   isSelected: addressForm == .u, large: true) { addressForm = .u }
                        .accessibilityIdentifier("onboarding.u")
                    NoahOptionCard(title: "Met \u{201C}jij\u{201D}", subtitle: AddressForm.jij.elderExample,
                                   isSelected: addressForm == .jij, large: true) { addressForm = .jij }
                        .accessibilityIdentifier("onboarding.jij")
                }
            }
            if let error { ElderMessage(text: error) }
            NoahAsyncButton(size: .elder, action: saveName) { Text("Verder") }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("onboarding.next")
        }
    }

    // MARK: Step 3: voice

    private var voiceStep: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            ElderStepHeader(step: Step.voice.rawValue, total: Self.totalSteps, title: "Welke stem past bij u?")
            ElderText("Met deze stem praat Noah met u. U kunt dit later altijd veranderen bij Instellingen.")
            VStack(spacing: NoahSpacing.s) {
                NoahOptionCard(title: NoahVoice.vrouw.label, subtitle: "Een warme, rustige vrouwenstem.",
                               isSelected: voice == .vrouw, large: true) { voice = .vrouw }
                    .accessibilityIdentifier("onboarding.voice.vrouw")
                NoahOptionCard(title: NoahVoice.man.label, subtitle: "Een warme, rustige mannenstem.",
                               isSelected: voice == .man, large: true) { voice = .man }
                    .accessibilityIdentifier("onboarding.voice.man")
            }
            if let error { ElderMessage(text: error) }
            NoahAsyncButton(size: .elder, action: saveVoice) { Text("Verder") }
                .accessibilityIdentifier("onboarding.next")
        }
    }

    // MARK: Step 4: someone to warn

    private var contactStep: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            ElderStepHeader(step: Step.contact.rawValue, total: Self.totalSteps, title: "Wie mogen we waarschuwen als het niet goed gaat?")
            ElderText("Vertelt u Noah dat het niet goed met u gaat, bijvoorbeeld na een val? Dan stuurt Noah deze persoon een sms en belt diegene op. Diegene heeft de app niet nodig.")
            NoahNotice(kind: .info, text: "We raden het u echt aan: zo is er altijd iemand die weet dat u hulp nodig heeft. Noah is geen alarmcentrale. Bij direct gevaar belt u altijd 112.", large: true)
            ElderContactFields(name: $contactName, phone: $contactPhone, phoneError: phoneError)
            if let error { ElderMessage(text: error) }
            NoahAsyncButton(size: .elder, action: saveContact) { Text("Bewaar en ga verder") }
                .disabled(contactName.trimmingCharacters(in: .whitespaces).isEmpty || contactPhone.filter(\.isNumber).count < 9)
                .accessibilityIdentifier("onboarding.saveContact")
            Button {
                error = nil
                step = .subscription
            } label: {
                Text("Nu overslaan, ik doe dit later")
            }
            .buttonStyle(.noah(.secondary, size: .elder))
            .accessibilityIdentifier("onboarding.skipContact")
        }
    }

    // MARK: Actions

    private func prefill() async {
        guard !didPrefill else { return }
        didPrefill = true
        await session.load()
        if name.isEmpty, let profile = session.profile {
            name = profile.preferredName
            addressForm = profile.addressForm == .jij ? .jij : .u
        }
        if let settings = try? await session.api.deviceSettings() {
            savedSettings = settings
            voice = settings.voice == .man ? .man : .vrouw
        }
    }

    private func saveName() async {
        error = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let profile = try await session.api.updateDeviceProfile(DeviceProfilePatch(preferredName: trimmed, addressForm: addressForm))
            session.didUpdate(profile: profile)
            step = .voice
        } catch {
            self.error = APIError.from(error).elderMessage
        }
    }

    private func saveVoice() async {
        error = nil
        let current = savedSettings ?? .defaults
        var wanted = current
        wanted.voice = voice
        let patch = NoahSettingsPatch(from: current, to: wanted)
        do {
            // Only when it changed (the server default is already a woman's voice).
            if !patch.isEmpty || savedSettings == nil {
                savedSettings = try await session.api.updateDeviceSettings(patch.isEmpty ? NoahSettingsPatch(voiceOnly: voice) : patch)
            }
            step = .contact
        } catch {
            self.error = APIError.from(error).elderMessage
        }
    }

    private func saveContact() async {
        error = nil
        phoneError = nil
        guard let e164 = PhoneNumberFormat.e164(contactPhone) else {
            phoneError = PhoneNumberFormat.invalidMessage
            return
        }
        do {
            _ = try await session.api.createDeviceEmergencyContact(
                EmergencyContactInput(name: contactName.trimmingCharacters(in: .whitespaces), phoneNumber: e164, relation: nil))
            step = .subscription
        } catch {
            let apiError = APIError.from(error)
            if apiError.code == "ongeldige_invoer" { phoneError = PhoneNumberFormat.invalidMessage } else { self.error = apiError.elderMessage }
        }
    }

    private func applyDebugRoute() {
        #if DEBUG
        guard let route = DebugRoute.take(scope: "onboarding") else { return }
        switch route {
        case "onboardingVoice": step = .voice
        case "onboardingContact": step = .contact
        case "onboardingPaywall": step = .subscription
        default: break
        }
        #endif
    }
}

extension NoahSettingsPatch {
    /// Just the voice (onboarding, when the current settings could not be loaded).
    init(voiceOnly voice: NoahVoice) {
        self.init()
        self.voice = voice
    }
}
