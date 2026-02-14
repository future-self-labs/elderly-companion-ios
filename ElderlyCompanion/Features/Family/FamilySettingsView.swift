import SwiftUI

struct FamilyMember: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var phoneNumber: String
    var relationship: String
    var whatsappUpdatesEnabled: Bool = true

    static let relationships = ["Son", "Daughter", "Spouse", "Grandchild", "Sibling", "Friend", "Caregiver", "Other"]
}

@Observable
final class FamilyViewModel {
    var members: [FamilyMember] = []
    var showAddSheet = false
    var isLoading = false
    var errorMessage: String?
    var showError = false

    func loadFromServer() async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        isLoading = true

        do {
            let contacts = try await APIClient.shared.getFamilyContacts(userId: userId)
            await MainActor.run {
                members = contacts.map { contact in
                    FamilyMember(
                        id: contact.id,
                        name: contact.name,
                        phoneNumber: contact.phoneNumber,
                        relationship: contact.relationship,
                        whatsappUpdatesEnabled: contact.whatsappUpdatesEnabled
                    )
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
                // Fallback to local storage
                if let data = UserDefaults.standard.data(forKey: "familyMembers"),
                   let decoded = try? JSONDecoder().decode([FamilyMember].self, from: data) {
                    members = decoded
                }
            }
        }
    }

    func add(_ member: FamilyMember) {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }

        Task {
            do {
                let contact = try await APIClient.shared.createFamilyContact(.init(
                    userId: userId,
                    name: member.name,
                    phoneNumber: member.phoneNumber,
                    relationship: member.relationship,
                    whatsappUpdatesEnabled: member.whatsappUpdatesEnabled
                ))
                await MainActor.run {
                    members.append(FamilyMember(
                        id: contact.id,
                        name: contact.name,
                        phoneNumber: contact.phoneNumber,
                        relationship: contact.relationship,
                        whatsappUpdatesEnabled: contact.whatsappUpdatesEnabled
                    ))
                    saveLocally()
                }
            } catch {
                await MainActor.run {
                    // Save locally as fallback
                    members.append(member)
                    saveLocally()
                    errorMessage = "Saved locally. Will sync when online."
                    showError = true
                }
            }
        }
    }

    func remove(id: String) {
        Task {
            do {
                try await APIClient.shared.deleteFamilyContact(id: id)
            } catch {
                print("[Family] Server delete failed, removing locally: \(error)")
            }
            await MainActor.run {
                members.removeAll { $0.id == id }
                saveLocally()
            }
        }
    }

    private func saveLocally() {
        if let data = try? JSONEncoder().encode(members) {
            UserDefaults.standard.set(data, forKey: "familyMembers")
        }
    }
}

struct FamilySettingsView: View {
    @State private var viewModel = FamilyViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: CompanionTheme.Spacing.lg) {
                // Info card
                CalmCard {
                    VStack(spacing: CompanionTheme.Spacing.md) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.companionPrimary)

                        Text("Family Circle")
                            .font(.companionHeadline)
                            .foregroundStyle(Color.companionTextPrimary)

                        Text("Add family members to receive daily WhatsApp updates about how your loved one is doing.")
                            .font(.companionBodySecondary)
                            .foregroundStyle(Color.companionTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                }

                // Family member list
                if !viewModel.members.isEmpty {
                    VStack(spacing: CompanionTheme.Spacing.md) {
                        ForEach(viewModel.members) { member in
                            CalmCard {
                                HStack(spacing: CompanionTheme.Spacing.md) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.companionPrimaryLight)
                                            .frame(width: 48, height: 48)

                                        Text(String(member.name.prefix(1)).uppercased())
                                            .font(.companionHeadline)
                                            .foregroundStyle(Color.companionPrimary)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(member.name)
                                            .font(.companionBody)
                                            .foregroundStyle(Color.companionTextPrimary)

                                        Text(member.relationship)
                                            .font(.companionCaption)
                                            .foregroundStyle(Color.companionTextSecondary)

                                        if !member.phoneNumber.isEmpty {
                                            Text(member.phoneNumber)
                                                .font(.companionCaption)
                                                .foregroundStyle(Color.companionTextTertiary)
                                        }

                                        if member.whatsappUpdatesEnabled {
                                            HStack(spacing: 4) {
                                                Image(systemName: "message.fill")
                                                    .font(.system(size: 10))
                                                Text("WhatsApp daily update")
                                                    .font(.system(size: 11, weight: .medium))
                                            }
                                            .foregroundStyle(Color.companionSuccess)
                                            .padding(.top, 2)
                                        }
                                    }

                                    Spacer()

                                    Button {
                                        viewModel.remove(id: member.id)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundStyle(Color.companionTextTertiary)
                                    }
                                }
                            }
                        }
                    }
                }

                // Add family member button
                LargeButton("Add Family Member", icon: "person.badge.plus", style: .outline) {
                    viewModel.showAddSheet = true
                }

                // Privacy note
                CalmCard {
                    HStack(spacing: CompanionTheme.Spacing.md) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.companionPrimary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Privacy First")
                                .font(.companionBody)
                                .foregroundStyle(Color.companionTextPrimary)

                            Text("You can revoke any family member's access at any time.")
                                .font(.companionCaption)
                                .foregroundStyle(Color.companionTextSecondary)
                        }
                    }
                }
            }
            .padding(CompanionTheme.Spacing.lg)
        }
        .background(Color.companionBackground)
        .navigationTitle("Family")
        .navigationBarTitleDisplayMode(.large)
        .alert("Notice", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "Something went wrong.")
        }
        .task {
            await viewModel.loadFromServer()
        }
        .sheet(isPresented: $viewModel.showAddSheet) {
            AddFamilyMemberView { member in
                viewModel.add(member)
            }
        }
    }
}

// MARK: - Add Family Member Sheet

struct AddFamilyMemberView: View {
    let onSave: (FamilyMember) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var phoneNumber = ""
    @State private var relationship = "Son"
    @State private var whatsappEnabled = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CompanionTheme.Spacing.lg) {
                    CompanionTextField("Full name", text: $name, icon: "person.fill")
                    CompanionTextField("Phone number", text: $phoneNumber, icon: "phone.fill")

                    CalmCard {
                        VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                            Text("Relationship")
                                .font(.companionBody)
                                .foregroundStyle(Color.companionTextPrimary)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: CompanionTheme.Spacing.sm) {
                                ForEach(FamilyMember.relationships, id: \.self) { rel in
                                    Button {
                                        relationship = rel
                                    } label: {
                                        Text(rel)
                                            .font(.companionLabel)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, CompanionTheme.Spacing.sm)
                                            .background(
                                                relationship == rel
                                                    ? Color.companionPrimary
                                                    : Color.companionSurfaceSecondary
                                            )
                                            .foregroundStyle(
                                                relationship == rel ? .white : Color.companionTextSecondary
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: CompanionTheme.Radius.sm))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    // WhatsApp toggle
                    CalmCard {
                        Toggle(isOn: $whatsappEnabled) {
                            HStack(spacing: CompanionTheme.Spacing.md) {
                                Image(systemName: "message.fill")
                                    .foregroundStyle(Color.companionSuccess)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("WhatsApp Daily Update")
                                        .font(.companionBody)
                                        .foregroundStyle(Color.companionTextPrimary)
                                    Text("Receive a daily summary at 20:00")
                                        .font(.companionCaption)
                                        .foregroundStyle(Color.companionTextSecondary)
                                }
                            }
                        }
                        .tint(Color.companionPrimary)
                    }
                }
                .padding(CompanionTheme.Spacing.lg)
            }
            .background(Color.companionBackground)
            .navigationTitle("Add Family Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(FamilyMember(name: name, phoneNumber: phoneNumber, relationship: relationship, whatsappUpdatesEnabled: whatsappEnabled))
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(Color.companionPrimary)
    }
}
