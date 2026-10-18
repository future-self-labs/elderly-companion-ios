import SwiftUI

/// After the first sign-in, without any profile: set up a profile or join through an invitation.
struct CaregiverStartView: View {
    @EnvironmentObject private var session: CaregiverSession
    @EnvironmentObject private var router: CaregiverRouter
    @EnvironmentObject private var app: AppModel
    @State private var confirmsSignOut = false
    @State private var name = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoahSpacing.l) {
                Text(session.firstName.isEmpty ? "Welkom!" : "Welkom, \(session.firstName)!")
                    .font(NoahFont.largeTitle).noahTitleScaling()
                    .foregroundColor(NoahColor.text)
                    .accessibilityAddTraits(.isHeader)
                Text("Voor wie stel je Noah in? We lopen stap voor stap door wat Noah moet weten. Dat duurt ongeveer tien minuten, en je kunt alles later nog aanpassen.")
                    .font(NoahFont.bodyText)
                    .foregroundColor(NoahColor.textSoft)
                    .fixedSize(horizontal: false, vertical: true)

                if (session.caregiver?.name).nilIfBlank == nil {
                    NoahTextField(label: "Hoe heet je?", text: $name, prompt: "Anna de Vries",
                                  footnote: "Zo weten familieleden en Noah wie je bent.", contentType: .name, autocapitalization: .words)
                }

                WelcomeChoiceCard(systemImage: "person.crop.circle.badge.plus",
                                  title: "Profiel aanmaken",
                                  subtitle: "Voor je vader, moeder of een andere naaste. Jij wordt beheerder.") {
                    saveNameIfNeeded()
                    router.present(.wizard)
                }
                .accessibilityIdentifier("start.wizard")

                WelcomeChoiceCard(systemImage: "envelope.open.fill",
                                  title: "Ik heb een uitnodiging",
                                  subtitle: "Iemand in je familie heeft Noah al ingesteld en je een code gestuurd.") {
                    saveNameIfNeeded()
                    router.present(.acceptInvitation(code: nil))
                }
                .accessibilityIdentifier("start.invitation")

                Button("Uitloggen") { confirmsSignOut = true }
                    .buttonStyle(.noah(.quiet))
            }
            .padding(.horizontal, NoahSpacing.screen)
            .padding(.vertical, NoahSpacing.l)
            .noahReadableWidth()
        }
        .noahScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Uitloggen?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
            Button("Uitloggen", role: .destructive) { Task { await app.signOut() } }
            Button("Annuleren", role: .cancel) {}
        }
        .onAppear {
            if let link = app.pendingLink, case .invitation(let code) = link {
                app.pendingLink = nil
                router.present(.acceptInvitation(code: code))
            }
        }
    }

    private func saveNameIfNeeded() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            _ = try? await session.api.updateMe(name: trimmed, phoneNumber: nil)
            await session.reloadMe()
        }
    }
}

/// Join an older person's circle with an invitation code (also opened from invitation links).
///
/// A code from a link is only filled in; joining always needs a tap on "Accepteren" (security
/// audit M10).
struct AcceptInvitationView: View {
    var initialCode: String?

    @EnvironmentObject private var session: CaregiverSession
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var error: String?
    @State private var accepted: AcceptInvitationResponse?
    @State private var isFromLink = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoahSpacing.l) {
                if let accepted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(NoahColor.positive)
                        .accessibilityHidden(true)
                    Text("Je kijkt nu mee bij \(accepted.elderly.preferredName)")
                        .font(NoahFont.title).noahTitleScaling()
                        .foregroundColor(NoahColor.text)
                    Text(verbatim: "Je rol: \(accepted.role.label). \(accepted.role.explanation)")
                        .font(NoahFont.bodyText)
                        .foregroundColor(NoahColor.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Naar het overzicht") { dismiss() }
                        .buttonStyle(.noah(.primary))
                } else {
                    Text("Uitnodiging accepteren")
                        .font(NoahFont.title).noahTitleScaling()
                        .foregroundColor(NoahColor.text)
                        .accessibilityAddTraits(.isHeader)
                    Text("Vul de code in die je hebt gekregen, bijvoorbeeld K7P-2QX. Je vindt hem in het bericht met de uitnodiging.")
                        .font(NoahFont.bodyText)
                        .foregroundColor(NoahColor.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    if isFromLink {
                        NoahNotice(kind: .info, text: "Deze uitnodiging kwam binnen via een link. Accepteer alleen als je weet van wie hij komt: je kijkt daarna mee bij die naaste en je naam is zichtbaar voor de andere mantelzorgers.")
                            .accessibilityIdentifier("invite.fromLink")
                    }
                    NoahTextField(label: "Uitnodigingscode", text: $code, prompt: "K7P-2QX", error: error, autocapitalization: .characters)
                        .accessibilityIdentifier("invite.code")
                    NoahAsyncButton("Accepteren") { await accept() }
                        .disabled(DeepLink.normalizedInvitationCode(code.replacingOccurrences(of: " ", with: "")) == nil)
                        .accessibilityIdentifier("invite.accept")
                }
            }
            .padding(.horizontal, NoahSpacing.screen)
            .padding(.vertical, NoahSpacing.l)
            .noahReadableWidth()
        }
        .noahScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if accepted == nil { Button("Annuleren") { dismiss() } }
            }
        }
        .onAppear {
            // Fill in only; the caregiver decides with a tap.
            if let initialCode, code.isEmpty {
                code = initialCode
                isFromLink = true
            }
        }
    }

    private func accept() async {
        error = nil
        guard let cleaned = DeepLink.normalizedInvitationCode(code.replacingOccurrences(of: " ", with: "")) else {
            error = "Een uitnodigingscode bestaat uit 6 letters en cijfers, bijvoorbeeld K7P-2QX."
            return
        }
        do {
            let response = try await session.api.acceptInvitation(code: cleaned)
            await session.didAddElderly(id: response.elderly.id)
            accepted = response
        } catch {
            self.error = APIError.from(error).userMessage
        }
    }
}
