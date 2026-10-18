import ContactsUI
import SwiftUI
import UIKit

/// Settings hub ("Meer").
struct MoreView: View {
    @EnvironmentObject private var session: CaregiverSession
    @EnvironmentObject private var router: CaregiverRouter
    @EnvironmentObject private var app: AppModel
    @State private var confirmsLeave = false
    @State private var leaveError: String?

    var body: some View {
        NoahScrollScreen(spacing: NoahSpacing.l) {
            if let leaveError { NoahNotice(kind: .error, text: leaveError) }
            if let selected = session.selected {
                NavigationLink(value: CaregiverRoute.elderlyList) {
                    NoahCard {
                        AdaptiveStack(verticalAlignment: .center, spacing: NoahSpacing.m) {
                            NoahAvatar(name: selected.preferredName, size: 52)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: selected.preferredName)
                                    .font(NoahFont.title3)
                                    .foregroundColor(NoahColor.text)
                                Text(verbatim: "\(selected.role.label) · \(selected.access == .active ? "Noah is actief" : "Noah is nog niet actief")")
                                    .font(NoahFont.subheadline)
                                    .foregroundColor(NoahColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if session.elderly.count > 1 {
                                    Text("Tik om te wisselen").font(NoahFont.subheadline).foregroundColor(NoahColor.accent)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .buttonStyle(.plain)

                let permissions = session.permissions
                group("Noah") {
                    if permissions.canViewSettings {
                        link(.noahSettings, icon: "slider.horizontal.3", title: "Noah-instellingen", subtitle: "Naam, stem, ochtendgesprek, opnemen")
                    }
                    link(.profile, icon: "person.text.rectangle", title: "Profiel van \(selected.preferredName)", subtitle: "Over \(selected.preferredName), voorkeuren en onderwerpen")
                    if permissions.canViewPeople {
                        link(.people, icon: "person.2.fill", title: "Belangrijke mensen", subtitle: "Familie, vrienden, buren")
                    }
                    if permissions.canViewEmergencyContacts {
                        link(.emergencyContacts, icon: "staroflife.fill", title: "Noodcontacten", subtitle: "Wie Noah waarschuwt, in welke volgorde")
                    }
                    link(.phoneLine, icon: "phone.fill", title: "Telefoonnummer van Noah", subtitle: "Bellen zonder app")
                }

                if permissions.isBeheerder {
                    group("Samen zorgen") {
                        link(.caregivers, icon: "person.3.fill", title: "Mantelzorgers", subtitle: "Familie uitnodigen om mee te kijken")
                        link(.pairDevice, icon: "qrcode", title: "Telefoon koppelen", subtitle: "Code voor de telefoon van \(selected.preferredName)")
                        link(.devices, icon: "iphone", title: "Gekoppelde telefoons", subtitle: nil)
                    }

                    group("Abonnement") {
                        link(.subscription, icon: "creditcard.fill", title: Plan.displayName, subtitle: selected.access == .active ? "Noah is actief" : "Nog niet gestart")
                    }
                } else {
                    VStack(alignment: .leading, spacing: NoahSpacing.s) {
                        ReadOnlyNotice()
                        Button(role: .destructive) { confirmsLeave = true } label: {
                            NoahButtonLabel(title: "Stoppen met meekijken bij \(selected.preferredName)", systemImage: "person.badge.minus")
                        }
                        .buttonStyle(.noah(.quiet))
                        .foregroundColor(NoahColor.dangerText)
                    }
                }
            } else {
                NoElderlySelectedView()
            }

            group("Account") {
                link(.account, icon: "person.crop.circle", title: "Account en privacy", subtitle: session.caregiver?.name ?? session.caregiver?.email)
                Button {
                    router.present(.acceptInvitation(code: nil))
                } label: {
                    NoahRow(icon: "envelope.open.fill", title: "Uitnodigingscode invullen")
                }
                .buttonStyle(.plain)
                Link(destination: app.environment.config.supportURL) {
                    NoahRow(icon: "questionmark.circle.fill", title: "Hulp en contact", subtitle: "Vragen? Ons supportteam helpt je graag.")
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: NoahSpacing.xxs) {
                Text("HelloNoah \(AppConfig.appVersion)")
                Text("Een product van Aldery")
                #if DEBUG
                if app.isMock { Text("Demo-modus: voorbeeldgegevens") }
                #endif
            }
            .font(NoahFont.footnote)
            .foregroundColor(NoahColor.textSecondary)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Meer")
        .confirmationDialog("Stoppen met meekijken?", isPresented: $confirmsLeave, titleVisibility: .visible) {
            Button("Stoppen met meekijken", role: .destructive) { Task { await leave() } }
            Button("Annuleren", role: .cancel) {}
        } message: {
            Text("Je ziet dan niets meer van dit profiel. De beheerder kan je opnieuw uitnodigen.")
        }
    }

    private func leave() async {
        guard let selected = session.selected, let me = session.caregiver?.id else { return }
        do {
            try await session.api.removeCaregiver(elderlyId: selected.id, caregiverId: me)
            leaveError = nil
            await session.reloadMe()
            session.dataChanged()
        } catch {
            leaveError = APIError.from(error).userMessage
        }
    }

    private func group<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        let body = content()
        return VStack(alignment: .leading, spacing: NoahSpacing.s) {
            NoahEyebrow(text: title)
            NoahCard(padding: NoahSpacing.s) {
                body
            }
        }
    }

    private func link(_ route: CaregiverRoute, icon: String, title: String, subtitle: String?) -> some View {
        NavigationLink(value: route) {
            NoahRow(icon: icon, title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }
}

/// All older people this caregiver is connected to; switch, add, or join.
struct ElderlyListView: View {
    @EnvironmentObject private var session: CaregiverSession
    @EnvironmentObject private var router: CaregiverRouter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NoahScrollScreen(spacing: NoahSpacing.m) {
            ForEach(session.elderly) { person in
                Button {
                    session.select(person.id)
                    dismiss()
                } label: {
                    NoahCard {
                        AdaptiveStack(verticalAlignment: .center, spacing: NoahSpacing.m) {
                            NoahAvatar(name: person.preferredName, size: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: person.preferredName).font(NoahFont.headline).foregroundColor(NoahColor.text)
                                Text(verbatim: person.role.label + " · " + DutchFormat.lastConversation(person.lastConversationAt))
                                    .font(NoahFont.subheadline).foregroundColor(NoahColor.textSecondary)
                                if let count = person.openAlertCount, count > 0 {
                                    Text(count == 1 ? "1 open melding" : "\(count) open meldingen")
                                        .font(NoahFont.footnote).foregroundColor(NoahColor.accent)
                                }
                            }
                            Spacer()
                            if person.id == session.selected?.id {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(NoahColor.accent)
                                    .accessibilityLabel(Text("Geselecteerd"))
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Button { router.present(.wizard) } label: {
                NoahButtonLabel(title: "Nieuw profiel toevoegen", systemImage: "plus")
            }
            .buttonStyle(.noah(.primary))
            Button { router.present(.acceptInvitation(code: nil)) } label: {
                NoahButtonLabel(title: "Uitnodigingscode invullen", systemImage: "envelope.open")
            }
            .buttonStyle(.noah(.secondary))
        }
        .navigationTitle("Naasten")
    }
}

// MARK: - UIKit bridges

/// Share sheet for files and text (GDPR export, invitations).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// "Nieuw contact" with the number prefilled; needs no Contacts permission.
struct NewContactView: UIViewControllerRepresentable {
    let name: String
    let phoneNumber: String
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let contact = CNMutableContact()
        contact.givenName = name
        contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: phoneNumber))]
        contact.note = "Bel dit nummer om met Noah te praten."
        let controller = CNContactViewController(forNewContact: contact)
        controller.delegate = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            onDone()
        }
    }
}

/// Writes export data to a temporary, nicely named JSON file for the share sheet.
enum ExportFile {
    static func write(_ data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(DutchFormat.dayString(Date())).json")
        try data.write(to: url, options: .atomic)
        return url
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let items: [Any]
}
