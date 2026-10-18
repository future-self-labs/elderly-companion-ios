import SwiftUI

/// Name, phone, sign out, GDPR export (share sheet) and account deletion ("VERWIJDER").
struct AccountView: View {
    @EnvironmentObject private var session: CaregiverSession
    @EnvironmentObject private var app: AppModel
    @State private var name = ""
    @State private var phone = ""
    @State private var phoneError: String?
    @State private var message: (text: String, isError: Bool)?
    @State private var share: ShareItem?
    @State private var confirmsSignOut = false
    @State private var showsDelete = false
    @State private var showsDebug = false

    var body: some View {
        NoahScrollScreen {
            VStack(alignment: .leading, spacing: NoahSpacing.l) {
                NoahTextField(label: "Je naam", text: $name, prompt: "Anna de Vries", contentType: .name, autocapitalization: .words)
                NoahTextField(label: "Je mobiele nummer", text: $phone, prompt: "06 12345678",
                              footnote: "Voor sms bij noodgevallen en om in te loggen met een code.",
                              error: phoneError, keyboard: .phonePad, contentType: .telephoneNumber, autocapitalization: .never)
                if let email = session.caregiver?.email {
                    NoahField(label: "E-mail") {
                        Text(verbatim: email).font(NoahFont.bodyText).foregroundColor(NoahColor.textSoft)
                    }
                }
                if let message { NoahNotice(kind: message.isError ? .error : .success, text: message.text) }
                NoahAsyncButton("Bewaar") { await save() }
                    .disabled(name == (session.caregiver?.name ?? "") && phone == PhoneNumberFormat.display(session.caregiver?.phoneNumber))
            }

            VStack(alignment: .leading, spacing: NoahSpacing.s) {
                NoahEyebrow(text: "Privacy")
                Text(verbatim: ProductCopy.privacy)
                    .font(NoahFont.callout)
                    .foregroundColor(NoahColor.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("account.privacy")
                Text("Je hebt altijd recht op je gegevens (AVG). De export bevat je account en alle gegevens van de profielen waarvan je beheerder bent.")
                    .font(NoahFont.callout)
                    .foregroundColor(NoahColor.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
                NoahAsyncButton(kind: .secondary, action: export) {
                    NoahButtonLabel(title: "Mijn gegevens exporteren", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("account.export")
                HStack(spacing: NoahSpacing.m) {
                    Link("Privacybeleid", destination: app.environment.config.privacyURL)
                    Link("Voorwaarden", destination: app.environment.config.termsURL)
                }
                .font(NoahFont.semibold(15, relativeTo: .subheadline))
                .foregroundColor(NoahColor.accent)
                .frame(minHeight: NoahSize.minTap)
            }

            VStack(alignment: .leading, spacing: NoahSpacing.s) {
                NoahEyebrow(text: "Account")
                Button { confirmsSignOut = true } label: {
                    NoahButtonLabel(title: "Uitloggen", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.noah(.secondary))
                Button(role: .destructive) { showsDelete = true } label: {
                    NoahButtonLabel(title: "Account verwijderen", systemImage: "trash")
                }
                .buttonStyle(.noah(.quiet))
                .foregroundColor(NoahColor.danger)
                .accessibilityIdentifier("account.delete")
            }

            VStack(spacing: NoahSpacing.xxs) {
                Text("HelloNoah \(AppConfig.appVersion) · Een product van Aldery")
                Text(verbatim: "Next Empire BV · Nieuwpoortkade 2A, 1055 RX Amsterdam · KvK 63190982")
            }
                .font(NoahFont.footnote)
                .foregroundColor(NoahColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                #if DEBUG
                .onLongPressGesture(minimumDuration: 1.5) { showsDebug = true }
                #endif
        }
        .navigationTitle("Account en privacy")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            name = session.caregiver?.name ?? ""
            phone = PhoneNumberFormat.display(session.caregiver?.phoneNumber)
        }
        .sheet(item: $share) { item in ActivityView(items: item.items) }
        .sheet(isPresented: $showsDelete) {
            NavigationStack {
                TypedConfirmationView(
                    title: "Account verwijderen",
                    explanation: "Je account wordt verwijderd. Profielen waarvan jij de enige beheerder bent, worden helemaal verwijderd: gesprekken, levensverhaal, herinneringen en gekoppelde telefoons. Bij andere profielen verdwijn alleen jij als mantelzorger. Een abonnement stop je apart via je Apple ID.",
                    buttonTitle: "Account definitief verwijderen"
                ) {
                    try await session.api.deleteMe()
                    app.accountDeleted()
                }
            }
        }
        .confirmationDialog("Uitloggen?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
            Button("Uitloggen", role: .destructive) { Task { await app.signOut() } }
            Button("Annuleren", role: .cancel) {}
        } message: {
            Text("Je gegevens blijven bewaard. Je kunt later weer inloggen.")
        }
        #if DEBUG
        .confirmationDialog("Ontwikkelaarsopties", isPresented: $showsDebug, titleVisibility: .visible) {
            Button(app.isMock ? "Demo-modus uitzetten" : "Demo-modus aanzetten") { app.setMockMode(!app.isMock) }
            Button("Annuleren", role: .cancel) {}
        } message: {
            Text(verbatim: app.isMock ? "De app gebruikt nu voorbeeldgegevens." : "Server: \(app.environment.config.baseURL.absoluteString)")
        }
        #endif
    }

    private func save() async {
        phoneError = nil
        var e164: String?
        if !phone.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let normalized = PhoneNumberFormat.e164(phone) else {
                phoneError = "Dit lijkt geen geldig telefoonnummer."
                return
            }
            e164 = normalized
        }
        do {
            _ = try await session.api.updateMe(name: name.trimmingCharacters(in: .whitespaces), phoneNumber: e164)
            await session.reloadMe()
            message = ("Opgeslagen.", false)
        } catch {
            message = (APIError.from(error).userMessage, true)
        }
    }

    private func export() async {
        do {
            let data = try await session.api.exportMe()
            share = ShareItem(items: [try ExportFile.write(data, name: "HelloNoah-mijn-gegevens")])
        } catch {
            message = (APIError.from(error).userMessage, true)
        }
    }
}
