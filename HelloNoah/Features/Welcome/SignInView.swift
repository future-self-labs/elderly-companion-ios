import AuthenticationServices
import SwiftUI

/// Caregiver sign-in: Sign in with Apple or phone number + SMS code.
struct SignInView: View {
    let onPhone: () -> Void

    @EnvironmentObject private var app: AppModel
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoahSpacing.l) {
                Text("Maak je account")
                    .font(NoahFont.largeTitle).noahTitleScaling()
                    .foregroundColor(NoahColor.text)
                    .accessibilityAddTraits(.isHeader)
                Text("Log in of maak in één stap een account. Daarna stel je Noah in voor je naaste.")
                    .font(NoahFont.bodyText)
                    .foregroundColor(NoahColor.textSoft)
                    .fixedSize(horizontal: false, vertical: true)

                if let error {
                    NoahNotice(kind: .error, text: error)
                }

                VStack(spacing: NoahSpacing.s) {
                    if app.isMock {
                        Button {
                            Task { await mockApple() }
                        } label: {
                            NoahButtonLabel(title: "Doorgaan met Apple", systemImage: "apple.logo")
                        }
                        .buttonStyle(.noah(.secondary))
                        .accessibilityIdentifier("signin.apple")
                    } else {
                        SignInWithAppleButton(.continue) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            Task { await handleApple(result) }
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: NoahSize.button)
                        .clipShape(RoundedRectangle(cornerRadius: NoahRadius.large, style: .continuous))
                        .accessibilityIdentifier("signin.apple")
                    }

                    Button(action: onPhone) {
                        NoahButtonLabel(title: "Doorgaan met telefoonnummer", systemImage: "phone.fill")
                    }
                    .buttonStyle(.noah(.secondary))
                    .accessibilityIdentifier("signin.phone")
                }
                .disabled(isWorking)
                .overlay {
                    if isWorking { ProgressView().tint(NoahColor.accent) }
                }

                #if DEBUG
                if app.isMock {
                    NoahNotice(kind: .info, text: "Demo: met Apple log je in als Anna (met Wim en Riet). Met een telefoonnummer maak je een nieuw account en loop je de hele inrichting door.")
                }
                #endif

                LegalLinksText()
            }
            .padding(.horizontal, NoahSpacing.screen)
            .padding(.vertical, NoahSpacing.l)
            .noahReadableWidth()
        }
        .noahScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let failure):
            if (failure as? ASAuthorizationError)?.code == .canceled { return }
            error = "Inloggen met Apple is niet gelukt. Probeer het opnieuw of gebruik je telefoonnummer."
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                error = "Inloggen met Apple is niet gelukt. Probeer het opnieuw."
                return
            }
            let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            let name = credential.fullName.map {
                AppleSignInRequest.FullName(givenName: $0.givenName, familyName: $0.familyName)
            }
            let hasName = name?.givenName != nil || name?.familyName != nil
            await signIn(AppleSignInRequest(identityToken: identityToken, authorizationCode: code, fullName: hasName ? name : nil))
        }
    }

    private func mockApple() async {
        await signIn(AppleSignInRequest(identityToken: "mock", authorizationCode: nil, fullName: .init(givenName: "Anna", familyName: "de Vries")))
    }

    private func signIn(_ request: AppleSignInRequest) async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            let auth = try await app.api.signInWithApple(request)
            app.didSignIn(auth)
        } catch {
            self.error = APIError.from(error).userMessage
        }
    }
}

/// "Door verder te gaan ga je akkoord met de voorwaarden en het privacybeleid."
struct LegalLinksText: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.xs) {
            Text("Door verder te gaan ga je akkoord met de voorwaarden en het privacybeleid van HelloNoah.")
                .font(NoahFont.footnote)
                .foregroundColor(NoahColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: NoahSpacing.m) {
                Link("Voorwaarden", destination: app.environment.config.termsURL)
                Link("Privacybeleid", destination: app.environment.config.privacyURL)
            }
            .font(NoahFont.semibold(13, relativeTo: .footnote))
            .foregroundColor(NoahColor.accent)
            .frame(minHeight: NoahSize.minTap)
        }
    }
}
