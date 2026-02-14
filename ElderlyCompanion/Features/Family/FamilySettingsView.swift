import SwiftUI

struct FamilyMember: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var phoneNumber: String
    var relationship: String

    static let relationships = ["Son", "Daughter", "Spouse", "Grandchild", "Sibling", "Friend", "Caregiver", "Other"]
}

@Observable
final class FamilyViewModel {
    var members: [FamilyMember] = []
    var showAddSheet = false

    init() { load() }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: "familyMembers"),
              let decoded = try? JSONDecoder().decode([FamilyMember].self, from: data) else { return }
        members = decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(members) {
            UserDefaults.standard.set(data, forKey: "familyMembers")
        }
    }

    func add(_ member: FamilyMember) {
        members.append(member)
        save()
    }

    func remove(at offsets: IndexSet) {
        members.remove(atOffsets: offsets)
        save()
    }

    func remove(id: String) {
        members.removeAll { $0.id == id }
        save()
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

                        Text("Add family members to share memories, receive activity updates, and stay connected.")
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
                        onSave(FamilyMember(name: name, phoneNumber: phoneNumber, relationship: relationship))
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
