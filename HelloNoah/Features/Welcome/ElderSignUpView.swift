import SwiftUI

/// v2.3 self route, step 1 of 5: the older person's own phone number and the SMS code.
///
/// The code proves the number is theirs, so no password is ever needed. If the number already
/// belongs to a profile the family set up, this phone is simply paired to it.
struct ElderSignUpView: View {
    @EnvironmentObject private var app: AppModel
    @State private var phone = ""
    @State private var e164: String?
    @State private var channel: PhoneVerificationChannel = .sms
    @State private var code = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var resendAvailableAt = Date()
    /// The number belongs to a profile the family manages (shown before the home screen).
    @State private var linked: ElderSignUpResponse?
    /// v2.4: someone else put this number on a profile; ask first ("Kent u deze persoon?").
    @State private var claim: ElderClaimChoice?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoahSpacing.l) {
                if let linked {
                    linkedView(linked)
                } else if let claim {
                    claimView(claim)
                } else if let e164 {
                    codeView(e164)
                } else {
                    phoneView
                }
            }
            .padding(.horizontal, NoahSpacing.screen)
            .padding(.vertical, NoahSpacing.l)
            .noahReadableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .noahElderScreenScaling()
        .elderSubscreen()
        .onAppear(perform: applyDebugRoute)
    }

    // MARK: Phone number

    private var phoneView: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            ElderBackButton()
            ElderStepHeader(step: 1, total: 5, title: "Uw telefoonnummer")
            ElderText("Noah stuurt u een sms met een code. Zo weten we dat dit nummer van u is. U heeft geen wachtwoord nodig.")

            NoahTextField(label: "Uw mobiele nummer", text: $phone, prompt: "06 12345678",
                          footnote: "Een Nederlands of Belgisch nummer.", error: error,
                          keyboard: .phonePad, contentType: .telephoneNumber, autocapitalization: .never, large: true)
                .accessibilityIdentifier("signUp.phone")

            NoahAsyncButton(size: .elder, action: { await start(.sms) }) {
                Text("Stuur mij de code")
            }
            .disabled(phone.filter(\.isNumber).count < 9)
            .accessibilityIdentifier("signUp.sendCode")

            NoahAsyncButton(kind: .secondary, size: .elder, action: { await start(.call) }) {
                NoahButtonLabel(title: "Bel mij met de code", systemImage: "phone.fill", iconTint: NoahColor.accent)
            }
            .disabled(phone.filter(\.isNumber).count < 9)
            .accessibilityHint(Text("Voor een vaste telefoon: een stem leest de code voor"))

            ElderLegalLinks()
        }
    }

    // MARK: Code

    private func codeView(_ number: String) -> some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            ElderStepHeader(step: 1, total: 5, title: "Vul de code in")
            ElderText(channel == .call
                ? "U wordt zo gebeld op \(PhoneNumberFormat.display(number)). Een stem leest de code van 6 cijfers voor."
                : "Noah heeft een sms met een code van 6 cijfers gestuurd naar \(PhoneNumberFormat.display(number)).")

            NoahCodeField(code: $code, large: true) { Task { await verify() } }
                .accessibilityIdentifier("signUp.code")

            if let error { ElderMessage(text: error) }

            NoahAsyncButton(size: .elder, action: verify) { Text("Verder") }
                .disabled(code.count != 6)
                .accessibilityIdentifier("signUp.verify")

            ElderResendButton(availableAt: resendAvailableAt) { Task { await start(channel) } }

            if channel == .sms {
                // Audit L28: a landline can't receive the SMS; switch to a spoken code.
                NoahAsyncButton(kind: .secondary, size: .elder, action: { await start(.call) }) {
                    NoahButtonLabel(title: "Bel mij met de code", systemImage: "phone.fill", iconTint: NoahColor.accent)
                }
                .accessibilityHint(Text("Voor een vaste telefoon: een stem leest de code voor"))
            }

            Button {
                e164 = nil
                code = ""
                error = nil
            } label: {
                Text("Ander nummer invullen")
            }
            .buttonStyle(.noah(.quiet, size: .elder))
        }
    }

    // MARK: Someone else made a profile with this number (v2.4)

    private func claimView(_ choice: ElderClaimChoice) -> some View {
        let creator = choice.profile?.createdBy ?? "iemand"
        let firstName = choice.creatorFirstName ?? "diegene"
        return VStack(alignment: .leading, spacing: NoahSpacing.l) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 60))
                .foregroundColor(NoahColor.accent)
                .accessibilityHidden(true)
            ElderScreenTitle(title: "Kent u deze persoon?")
            ElderText("Er is al een profiel voor dit nummer aangemaakt door \(creator). Kent u \(firstName), en wilt u dat \(firstName) met u meekijkt?")
            ElderText("Meekijken betekent: \(firstName) kan lezen waarover u met Noah praat en ziet hoe het met u gaat. U kunt dat later zelf aanpassen.", color: NoahColor.textSecondary)
            if let error { ElderMessage(text: error) }
            NoahAsyncButton(size: .elder, action: { await answerClaim(choice, .koppelen) }) {
                Text("Ja, ik ken \(firstName)")
            }
            .accessibilityIdentifier("signUp.claimLink")
            NoahAsyncButton(kind: .secondary, size: .elder, action: { await answerClaim(choice, .eigenProfiel) }) {
                Text("Nee, ik begin voor mezelf")
            }
            .accessibilityIdentifier("signUp.claimOwn")
            ElderText("Kiest u voor uzelf, dan wordt uw nummer van dat andere profiel gehaald en krijgt \(firstName) daar bericht van.", color: NoahColor.textSecondary)
        }
        .accessibilityIdentifier("signUp.claim")
    }

    // MARK: Already set up by the family

    private func linkedView(_ response: ElderSignUpResponse) -> some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(NoahColor.positive)
                .accessibilityHidden(true)
            ElderScreenTitle(title: "Deze telefoon is gekoppeld aan het account van uw familie")
            ElderText("Uw familie heeft Noah al voor u ingesteld. U kunt meteen met Noah praten. Op het beginscherm ziet u bij \u{201C}Wie kijkt er mee\u{201D} wie er meekijkt en wat ze zien; daar beslist u zelf over.")
            Button("Naar het beginscherm") { app.didSignUpElder(response) }
                .buttonStyle(.noah(.primary, size: .elder))
                .accessibilityIdentifier("signUp.linkedContinue")
        }
        .accessibilityIdentifier("signUp.linked")
    }

    // MARK: Actions

    private func start(_ requested: PhoneVerificationChannel) async {
        error = nil
        guard let number = e164 ?? PhoneNumberFormat.e164(phone) else {
            error = PhoneNumberFormat.invalidMessage
            return
        }
        do {
            try await app.api.startElderSignUp(phoneNumber: number, channel: requested)
            channel = requested
            e164 = number
            resendAvailableAt = Date().addingTimeInterval(30)
        } catch {
            let apiError = APIError.from(error)
            self.error = apiError.code == "ongeldige_invoer" ? PhoneNumberFormat.invalidMessage : apiError.elderMessage(isSelfManaged: true)
        }
    }

    private func verify() async {
        guard let e164, code.count == 6, !isWorking else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            let outcome = try await app.api.verifyElderSignUp(ElderSignUpVerifyRequest(phoneNumber: e164, code: code, deviceName: UIDevice.current.name))
            switch outcome {
            case .signedIn(let response): signedIn(response)
            case .choiceNeeded(let choice): claim = choice
            }
        } catch {
            self.error = APIError.from(error).elderMessage(isSelfManaged: true)
            code = ""
        }
    }

    private func signedIn(_ response: ElderSignUpResponse) {
        if response.isLinkedToFamily, !response.restricted {
            // Keep the token right away, so closing the app on the next screen loses nothing (L29).
            app.rememberDeviceToken(response.deviceToken)
            linked = response
        } else {
            app.didSignUpElder(response)
        }
    }

    private func answerClaim(_ choice: ElderClaimChoice, _ decision: ElderClaimDecision) async {
        error = nil
        do {
            let response = try await app.api.claimElderSignUp(ElderClaimRequest(claimToken: choice.claimToken, choice: decision, deviceName: UIDevice.current.name))
            claim = nil
            signedIn(response)
        } catch {
            let apiError = APIError.from(error)
            if apiError.code == "claim_ongeldig" {
                claim = nil
                e164 = nil
                code = ""
            }
            self.error = apiError.elderMessage(isSelfManaged: true)
        }
    }

    private func applyDebugRoute() {
        #if DEBUG
        guard let route = DebugRoute.take(scope: "elderSignUp") else { return }
        switch route {
        case "elderSignUpCode":
            e164 = "+31645678901"
        case "claim":
            e164 = "+31611223344"
            claim = ElderClaimChoice(claimToken: "hnc_mock_\(MockIDs.bep)", expiresAt: nil, profile: .init(preferredName: "Bep", createdBy: "Mark de Vries"))
        case "familyLinked":
            linked = ElderSignUpResponse(deviceToken: "hnd_mock_\(MockIDs.wim)", device: .init(id: "d"),
                                         elderly: .init(id: MockIDs.wim, preferredName: "Wim", noahName: "Noah"),
                                         isNewProfile: false, managedBy: .mantelzorger)
        default: break
        }
        #endif
    }
}

/// "Opnieuw sturen over 12 s" → "Stuur de code opnieuw", in the older person's size.
struct ElderResendButton: View {
    let availableAt: Date
    let action: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if context.date < availableAt {
                Text("U kunt over \(Int(availableAt.timeIntervalSince(context.date)) + 1) seconden een nieuwe code vragen")
                    .font(NoahFont.Elder.label)
                    .foregroundColor(NoahColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: NoahSize.elderMinTap)
            } else {
                Button("Stuur de code opnieuw", action: action)
                    .buttonStyle(.noah(.secondary, size: .elder))
            }
        }
    }
}

/// Terms and privacy for the self sign-up, in "u".
struct ElderLegalLinks: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.xs) {
            Text("Als u verdergaat, gaat u akkoord met de voorwaarden en het privacybeleid van HelloNoah.")
                .font(NoahFont.Elder.label)
                .foregroundColor(NoahColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            AdaptiveStack(spacing: NoahSpacing.l) {
                Link("Voorwaarden", destination: app.environment.config.termsURL)
                Link("Privacybeleid", destination: app.environment.config.privacyURL)
            }
            .font(NoahFont.Elder.bodyStrong)
            .foregroundColor(NoahColor.accent)
            .frame(minHeight: NoahSize.elderMinTap)
        }
    }
}
