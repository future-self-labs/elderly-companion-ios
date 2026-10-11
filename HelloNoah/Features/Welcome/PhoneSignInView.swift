import SwiftUI

/// Phone number → SMS code (Twilio Verify on the backend).
struct PhoneSignInView: View {
    @EnvironmentObject private var app: AppModel
    @State private var phone = ""
    @State private var e164: String?
    @State private var code = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var resendAvailableAt = Date()
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoahSpacing.l) {
                if let e164 {
                    Text("Vul de code in")
                        .font(NoahFont.largeTitle).noahTitleScaling()
                        .foregroundColor(NoahColor.text)
                        .accessibilityAddTraits(.isHeader)
                    Text("We hebben een sms met een code van 6 cijfers gestuurd naar \(PhoneNumberFormat.display(e164)).")
                        .font(NoahFont.bodyText)
                        .foregroundColor(NoahColor.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    NoahCodeField(code: $code) { Task { await verify() } }
                        .accessibilityIdentifier("phone.code")
                    if let error { NoahNotice(kind: .error, text: error) }
                    NoahAsyncButton("Inloggen") { await verify() }
                        .disabled(code.count != 6)
                    HStack {
                        Button("Ander nummer") {
                            self.e164 = nil
                            code = ""
                            error = nil
                        }
                        Spacer()
                        if now < resendAvailableAt {
                            Text("Opnieuw sturen over \(Int(resendAvailableAt.timeIntervalSince(now)) + 1) s")
                                .foregroundColor(NoahColor.textSecondary)
                        } else {
                            Button("Code opnieuw sturen") { Task { await start() } }
                        }
                    }
                    .font(NoahFont.subheadline)
                    .foregroundColor(NoahColor.accent)
                    .frame(minHeight: NoahSize.minTap)
                } else {
                    Text("Je telefoonnummer")
                        .font(NoahFont.largeTitle).noahTitleScaling()
                        .foregroundColor(NoahColor.text)
                        .accessibilityAddTraits(.isHeader)
                    Text("We sturen je een sms met een code. Zo heb je geen wachtwoord nodig.")
                        .font(NoahFont.bodyText)
                        .foregroundColor(NoahColor.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    NoahTextField(label: "Mobiel nummer", text: $phone, prompt: "06 12345678", error: error,
                                  keyboard: .phonePad, contentType: .telephoneNumber, autocapitalization: .never)
                        .accessibilityIdentifier("phone.number")
                    NoahAsyncButton("Stuur code") { await start() }
                        .disabled(phone.filter(\.isNumber).count < 9)
                    LegalLinksText()
                }
            }
            .padding(.horizontal, NoahSpacing.screen)
            .padding(.vertical, NoahSpacing.l)
            .noahReadableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .noahScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(timer) { now = $0 }
    }

    private func start() async {
        error = nil
        guard let number = e164 ?? PhoneNumberFormat.e164(phone) else {
            error = "Dit lijkt geen geldig telefoonnummer. Gebruik bijvoorbeeld 06 12345678."
            return
        }
        do {
            try await app.api.startPhoneSignIn(phoneNumber: number)
            e164 = number
            resendAvailableAt = Date().addingTimeInterval(30)
        } catch {
            self.error = APIError.from(error).userMessage
        }
    }

    private func verify() async {
        guard let e164, code.count == 6, !isWorking else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            let auth = try await app.api.verifyPhoneSignIn(phoneNumber: e164, code: code)
            app.didSignIn(auth)
        } catch {
            self.error = APIError.from(error).userMessage
            code = ""
        }
    }
}
