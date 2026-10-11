import SwiftUI
import UIKit

/// The older person's phone: enter the 6-digit code from the caregiver. No login, no password.
struct PairingView: View {
    var initialCode: String?

    @EnvironmentObject private var app: AppModel
    @State private var code = ""
    @State private var isPairing = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoahSpacing.l) {
                ElderBackButton()
                Text("Telefoon koppelen")
                    .font(NoahFont.Elder.hero).noahElderTitleScaling()
                    .foregroundColor(NoahColor.text)
                    .accessibilityAddTraits(.isHeader)

                Text("Vul de code van 6 cijfers in die u van uw mantelzorger heeft gekregen.")
                    .font(NoahFont.Elder.body)
                    .foregroundColor(NoahColor.textSoft)
                    .fixedSize(horizontal: false, vertical: true)

                NoahCodeField(code: $code, large: true) {
                    Task { await pair() }
                }
                .accessibilityIdentifier("pairing.code")

                if let error {
                    Text(verbatim: error)
                        .font(NoahFont.Elder.body)
                        .foregroundColor(NoahColor.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isStaticText)
                }

                Button {
                    Task { await pair() }
                } label: {
                    if isPairing {
                        ProgressView().tint(NoahColor.onAccent)
                    } else {
                        Text("Koppelen")
                    }
                }
                .buttonStyle(.noah(.primary, size: .elder))
                .disabled(code.count != 6 || isPairing)
                .accessibilityIdentifier("pairing.submit")

                NoahCard {
                    Label {
                        Text("De mantelzorger vindt de code in de HelloNoah-app, bij Meer → Telefoon koppelen. De code is 15 minuten geldig.")
                            .font(NoahFont.Elder.label)
                            .foregroundColor(NoahColor.textSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(NoahColor.accent)
                    }
                }
            }
            .padding(.horizontal, NoahSpacing.screen)
            .padding(.vertical, NoahSpacing.l)
            .noahReadableWidth()
        }
        // Like the rest of the older person's interface: no navigation bar (the root has none
        // either, so nothing animates in during the push) and a big "Terug" button instead.
        .elderSubscreen()
        .onAppear {
            if let initialCode, code.isEmpty { code = initialCode }
        }
    }

    private func pair() async {
        guard code.count == 6, !isPairing else { return }
        isPairing = true
        error = nil
        defer { isPairing = false }
        do {
            let response = try await app.api.pairDevice(code: code, deviceName: UIDevice.current.name)
            app.didPair(response)
        } catch {
            let apiError = APIError.from(error)
            if case .server(_, let errorCode, _) = apiError, ["koppelcode_ongeldig", "invalid_code", "code_expired"].contains(errorCode) || apiError.status == 404 {
                self.error = "Deze code klopt niet of is verlopen. Vraag uw mantelzorger om een nieuwe code."
            } else {
                self.error = apiError.elderMessage
            }
            code = ""
        }
    }
}
