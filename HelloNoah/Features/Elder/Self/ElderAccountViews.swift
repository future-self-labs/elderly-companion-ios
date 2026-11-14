import StoreKit
import SwiftUI

// MARK: - Uw gegevens downloaden

struct ElderExportView: View {
    @EnvironmentObject private var session: ElderSession
    @State private var share: ShareItem?
    @State private var error: String?

    var body: some View {
        ElderScrollScreen {
            ElderScreenTitle(title: "Uw gegevens downloaden")
            ElderText("U heeft altijd recht op uw gegevens, ook als uw familie Noah voor u regelt. U krijgt één bestand met alles wat HelloNoah van u bewaart: uw gesprekken, uw levensverhaal, herinneringen, noodcontacten en instellingen.")
            ElderText("U kunt het bestand bewaren in Bestanden, of naar iemand sturen die u vertrouwt.", color: NoahColor.textSecondary)
            if let error { ElderMessage(text: error) }
            NoahAsyncButton(size: .elder, action: export) {
                NoahButtonLabel(title: "Download mijn gegevens", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("export.download")
        }
        .sheet(item: $share, onDismiss: ExportFile.removeAll) { item in ActivityView(items: item.items) }
    }

    private func export() async {
        error = nil
        do {
            let data = try await session.api.exportDevice()
            share = ShareItem(items: [try ExportFile.write(data, name: "HelloNoah-mijn-gegevens")])
        } catch {
            self.error = APIError.from(error).elderMessage(isSelfManaged: session.isSelfManaged)
        }
    }
}

// MARK: - Account verwijderen

/// Deleting is deliberate but never a typing test: two clear screens with a big red button.
/// The second screen puts "Nee, toch niet" first and arms the red button only after a moment, so a
/// double tap can never go through both steps.
struct ElderDeleteAccountView: View {
    @EnvironmentObject private var session: ElderSession
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var isSure = false
    @State private var isArmed = false
    @State private var error: String?
    /// v2.4 `409 abonnement_actief`: the store subscription still runs; ask once more.
    @State private var needsSubscriptionAck = false

    var body: some View {
        ElderScrollScreen(showsBack: !isSure) {
            if isSure {
                confirmStep
            } else {
                explainStep
            }
        }
    }

    private var explainStep: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            ElderScreenTitle(title: "Account verwijderen")
            ElderText("Als u uw account verwijdert, wordt alles gewist: uw gesprekken, uw levensverhaal, opnames, herinneringen en noodcontacten. Ook de mensen die meekijken, zien daarna niets meer.")
            NoahNotice(kind: .warning, text: "Uw abonnement stopt hiermee niet vanzelf. Zeg het apart op via Instellingen › uw naam › Abonnementen op uw iPhone, anders loopt de betaling door.", large: true)
                .accessibilityIdentifier("delete.subscriptionWarning")
            Button(role: .destructive) {
                isArmed = false
                isSure = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    isArmed = true
                }
            } label: {
                Text("Ja, ik wil mijn account verwijderen")
            }
            .buttonStyle(.noah(.destructive, size: .elder))
            .accessibilityIdentifier("delete.step1")
            Button("Nee, terug") { dismiss() }
                .buttonStyle(.noah(.secondary, size: .elder))
        }
    }

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundColor(NoahColor.dangerText)
                .accessibilityHidden(true)
            ElderScreenTitle(title: "Weet u het zeker?")
            ElderText("Dit kan niet ongedaan worden gemaakt. Alles van u bij HelloNoah is daarna echt weg.")
            Button("Nee, toch niet") {
                isSure = false
            }
            .buttonStyle(.noah(.primary, size: .elder))
            .accessibilityIdentifier("delete.cancel")
            if let error { ElderMessage(text: error) }
            if needsSubscriptionAck {
                NoahNotice(kind: .warning, text: "Uw abonnement loopt nog en stopt niet vanzelf. Zeg het op via Instellingen › uw naam › Abonnementen op uw iPhone. Wilt u toch nu alles verwijderen?", large: true)
                Button { Task { await manageSubscriptions() } } label: {
                    NoahButtonLabel(title: "Abonnement opzeggen", systemImage: "creditcard")
                }
                .buttonStyle(.noah(.secondary, size: .elder))
                NoahAsyncButton(kind: .destructive, size: .elder, action: { await delete(acknowledged: true) }) {
                    Text("Ik weet het, verwijder alles")
                }
                .accessibilityIdentifier("delete.confirmAck")
            } else {
                NoahAsyncButton(kind: .destructive, size: .elder, action: { await delete(acknowledged: false) }) {
                    Text("Definitief verwijderen")
                }
                .disabled(!isArmed)
                .accessibilityIdentifier("delete.confirm")
            }
        }
    }

    private func manageSubscriptions() async {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
    }

    private func delete(acknowledged: Bool) async {
        error = nil
        do {
            try await session.api.deleteDeviceAccount(subscriptionAcknowledged: acknowledged)
            app.elderAccountDeleted()
        } catch let apiError as APIError where apiError.isSubscriptionStillActive {
            needsSubscriptionAck = true
        } catch {
            self.error = APIError.from(error).elderMessage(isSelfManaged: session.isSelfManaged)
        }
    }
}
