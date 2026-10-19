import SwiftUI

// MARK: - Uw gegevens downloaden

struct ElderExportView: View {
    @EnvironmentObject private var session: ElderSession
    @State private var share: ShareItem?
    @State private var error: String?

    var body: some View {
        ElderScrollScreen {
            ElderScreenTitle(title: "Uw gegevens downloaden")
            ElderText("U heeft altijd recht op uw gegevens. U krijgt één bestand met alles wat HelloNoah van u bewaart: uw gesprekken, uw levensverhaal, herinneringen, noodcontacten en instellingen.")
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
            self.error = APIError.from(error).elderMessage
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
            NoahAsyncButton(kind: .destructive, size: .elder, action: delete) {
                Text("Definitief verwijderen")
            }
            .disabled(!isArmed)
            .accessibilityIdentifier("delete.confirm")
        }
    }

    private func delete() async {
        error = nil
        do {
            try await session.api.deleteDeviceAccount()
            app.elderAccountDeleted()
        } catch {
            self.error = APIError.from(error).elderMessage
        }
    }
}
