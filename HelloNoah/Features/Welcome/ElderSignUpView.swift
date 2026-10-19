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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoahSpacing.l) {
                if let linked {
                    linkedView(linked)
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

    // MARK: Already set up by the family

    private func linkedView(_ response: ElderSignUpResponse) -> some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(NoahColor.positive)
                .accessibilityHidden(true)
            ElderScreenTitle(title: "Deze telefoon is gekoppeld aan het account van uw familie")
            ElderText("Uw familie heeft Noah al voor u ingesteld. U kunt meteen met Noah praten. De instellingen regelt uw familie voor u.")
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
            self.error = apiError.code == "ongeldige_invoer" ? PhoneNumberFormat.invalidMessage : apiError.elderMessage
        }
    }

    private func verify() async {
        guard let e164, code.count == 6, !isWorking else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            let response = try await app.api.verifyElderSignUp(ElderSignUpVerifyRequest(phoneNumber: e164, code: code, deviceName: UIDevice.current.name))
            if response.isLinkedToFamily {
                linked = response
            } else {
                app.didSignUpElder(response)
            }
        } catch {
            self.error = APIError.from(error).elderMessage
            code = ""
        }
    }

    private func applyDebugRoute() {
        #if DEBUG
        guard let route = DebugRoute.take(scope: "elderSignUp") else { return }
        switch route {
        case "elderSignUpCode":
            e164 = "+31645678901"
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
