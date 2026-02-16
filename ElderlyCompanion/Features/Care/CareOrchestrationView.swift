import SwiftUI

@Observable
final class CareOrchestrationViewModel {
    var settings: APIClient.CareSettingsRecord?
    var contacts: [APIClient.TrustedContactRecord] = []
    var isLoading = false
    var showAddContact = false
    var errorMessage: String?
    var showError = false

    func load() async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        isLoading = true
        do {
            async let s = APIClient.shared.getCareSettings(elderlyUserId: userId)
            async let c = APIClient.shared.getTrustedCircle(elderlyUserId: userId)
            let (loadedSettings, loadedContacts) = try await (s, c)
            await MainActor.run {
                settings = loadedSettings
                contacts = loadedContacts.sorted { $0.priorityOrder < $1.priorityOrder }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    func toggleCare(_ enabled: Bool) {
        guard var s = settings, let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        s.careEnabled = enabled
        settings = s
        Task {
            do { try await APIClient.shared.updateCareSettings(elderlyUserId: userId, settings: s) }
            catch { print("[Care] Toggle error: \(error)") }
        }
    }

    func toggleAIFirstContact(_ enabled: Bool) {
        guard var s = settings, let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        s.aiFirstContact = enabled
        settings = s
        Task {
            do { try await APIClient.shared.updateCareSettings(elderlyUserId: userId, settings: s) }
            catch { print("[Care] Toggle error: \(error)") }
        }
    }

    func addContact(_ request: APIClient.CreateTrustedContactRequest) {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        Task {
            do {
                let contact = try await APIClient.shared.addTrustedContact(elderlyUserId: userId, request: request)
                await MainActor.run { contacts.append(contact) }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; showError = true }
            }
        }
    }

    func removeContact(id: String) {
        Task {
            do {
                try await APIClient.shared.deleteTrustedContact(id: id)
                await MainActor.run { contacts.removeAll { $0.id == id } }
            } catch { print("[Care] Delete error: \(error)") }
        }
    }
}

struct CareOrchestrationView: View {
    @State private var vm = CareOrchestrationViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: CompanionTheme.Spacing.lg) {
                // Master toggle
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                        CalmCardHeader("Care Features", icon: "shield.checkered")
                        Toggle(isOn: Binding(
                            get: { vm.settings?.careEnabled ?? false },
                            set: { vm.toggleCare($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable Care Monitoring")
                                    .font(.companionBody)
                                    .foregroundStyle(Color.companionTextPrimary)
                                Text("Noah will monitor for concerns and alert your trusted circle when needed")
                                    .font(.companionCaption)
                                    .foregroundStyle(Color.companionTextSecondary)
                            }
                        }
                        .tint(Color.companionPrimary)
                    }
                }

                // AI First Contact Guard
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                        CalmCardHeader("AI First-Contact Guard", icon: "person.badge.shield.checkmark.fill")
                        Toggle(isOn: Binding(
                            get: { vm.settings?.aiFirstContact ?? true },
                            set: { vm.toggleAIFirstContact($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Contact me first")
                                    .font(.companionBody)
                                    .foregroundStyle(Color.companionTextPrimary)
                                Text("Noah will always try to reach you before contacting anyone else")
                                    .font(.companionCaption)
                                    .foregroundStyle(Color.companionTextSecondary)
                            }
                        }
                        .tint(Color.companionPrimary)

                        Text("Bypassed only for: active scam, severe safety risk, or extended silence")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.companionTextTertiary)
                    }
                }

                // Trusted Circle
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                        CalmCardHeader("Trusted Circle", icon: "person.3.fill")

                        if vm.contacts.isEmpty {
                            Text("No trusted contacts yet. Add people Noah can reach when needed.")
                                .font(.companionBodySecondary)
                                .foregroundStyle(Color.companionTextTertiary)
                        } else {
                            ForEach(vm.contacts) { contact in
                                HStack(spacing: CompanionTheme.Spacing.md) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 4) {
                                            Text("#\(contact.priorityOrder)")
                                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                                .foregroundStyle(Color.companionPrimary)
                                            Text(contact.name)
                                                .font(.companionBody)
                                                .foregroundStyle(Color.companionTextPrimary)
                                        }
                                        Text("\(contact.role.capitalized) — \(contact.phoneNumber)")
                                            .font(.companionCaption)
                                            .foregroundStyle(Color.companionTextSecondary)
                                    }
                                    Spacer()
                                    Button { vm.removeContact(id: contact.id) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(Color.companionTextTertiary)
                                    }
                                }
                                .padding(.vertical, CompanionTheme.Spacing.xs)
                                if contact.id != vm.contacts.last?.id { Divider() }
                            }
                        }

                        LargeButton("Add Trusted Contact", icon: "person.badge.plus", style: .outline) {
                            vm.showAddContact = true
                        }
                    }
                }
            }
            .padding(CompanionTheme.Spacing.lg)
        }
        .background(Color.companionBackground)
        .navigationTitle("Care Orchestration")
        .navigationBarTitleDisplayMode(.large)
        .alert("Error", isPresented: $vm.showError) { Button("OK") {} } message: { Text(vm.errorMessage ?? "") }
        .task { await vm.load() }
        .sheet(isPresented: $vm.showAddContact) {
            AddTrustedContactView { request in vm.addContact(request) }
        }
    }
}

struct AddTrustedContactView: View {
    let onSave: (APIClient.CreateTrustedContactRequest) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var role = "family"
    @State private var priority = 1

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact") {
                    TextField("Name", text: $name)
                    TextField("Phone number", text: $phone).keyboardType(.phonePad)
                    Picker("Role", selection: $role) {
                        Text("Family").tag("family")
                        Text("Caretaker").tag("caretaker")
                        Text("Neighbor").tag("neighbor")
                        Text("Friend").tag("friend")
                    }
                    Stepper("Priority: #\(priority)", value: $priority, in: 1...10)
                }
            }
            .navigationTitle("Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(APIClient.CreateTrustedContactRequest(
                            name: name, phoneNumber: phone, role: role, priorityOrder: priority,
                            mayReceiveScamAlerts: true, mayReceiveEmotionalAlerts: true,
                            mayReceiveSilenceAlerts: true, mayReceiveCognitiveAlerts: true,
                            mayReceiveRoutineAlerts: true
                        ))
                        dismiss()
                    }.disabled(name.isEmpty || phone.isEmpty)
                }
            }
        }
    }
}
