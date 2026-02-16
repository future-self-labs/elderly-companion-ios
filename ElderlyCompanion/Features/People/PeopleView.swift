import SwiftUI

@Observable
final class PeopleViewModel {
    var people: [APIClient.PersonRecord] = []
    var isLoading = false
    var showAddSheet = false
    var errorMessage: String?
    var showError = false

    func load() async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        isLoading = true
        do {
            people = try await APIClient.shared.getPeople(elderlyUserId: userId)
            await MainActor.run { isLoading = false }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    func add(_ person: APIClient.PersonRequest) {
        Task {
            do {
                let created = try await APIClient.shared.createPerson(person)
                await MainActor.run { people.append(created) }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    func remove(id: String) {
        Task {
            do {
                try await APIClient.shared.deletePerson(id: id)
                await MainActor.run { people.removeAll { $0.id == id } }
            } catch {
                print("[People] Delete error: \(error)")
            }
        }
    }
}

struct PeopleView: View {
    @State private var viewModel = PeopleViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: CompanionTheme.Spacing.lg) {
                CalmCard {
                    VStack(spacing: CompanionTheme.Spacing.md) {
                        Image(systemName: "person.text.rectangle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.companionPrimary)

                        Text("Memory Vault — People")
                            .font(.companionHeadline)
                            .foregroundStyle(Color.companionTextPrimary)

                        Text("People in your life that Noah remembers. Add family, friends, and caretakers so Noah can mention them naturally.")
                            .font(.companionBodySecondary)
                            .foregroundStyle(Color.companionTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                }

                if viewModel.isLoading {
                    ProgressView().tint(Color.companionPrimary)
                } else if !viewModel.people.isEmpty {
                    ForEach(viewModel.people) { person in
                        PersonRow(person: person) {
                            viewModel.remove(id: person.id)
                        }
                    }
                }

                LargeButton("Add Person", icon: "person.badge.plus", style: .outline) {
                    viewModel.showAddSheet = true
                }
            }
            .padding(CompanionTheme.Spacing.lg)
        }
        .background(Color.companionBackground)
        .navigationTitle("People")
        .navigationBarTitleDisplayMode(.large)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "Something went wrong.")
        }
        .task { await viewModel.load() }
        .sheet(isPresented: $viewModel.showAddSheet) {
            AddPersonView { request in
                viewModel.add(request)
            }
        }
    }
}

struct PersonRow: View {
    let person: APIClient.PersonRecord
    let onDelete: () -> Void

    var body: some View {
        CalmCard {
            HStack(spacing: CompanionTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.companionPrimaryLight)
                        .frame(width: 48, height: 48)
                    Text(String(person.name.prefix(1)).uppercased())
                        .font(.companionHeadline)
                        .foregroundStyle(Color.companionPrimary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name)
                        .font(.companionBody)
                        .foregroundStyle(Color.companionTextPrimary)
                    Text(person.relationship)
                        .font(.companionCaption)
                        .foregroundStyle(Color.companionTextSecondary)
                    if let bday = person.birthDate {
                        HStack(spacing: 4) {
                            Image(systemName: "gift.fill")
                                .font(.system(size: 10))
                            Text(bday)
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(Color.companionInfo)
                    }
                    if let notes = person.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.companionCaption)
                            .foregroundStyle(Color.companionTextTertiary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Button { onDelete() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.companionTextTertiary)
                }
            }
        }
    }
}

struct AddPersonView: View {
    let onSave: (APIClient.PersonRequest) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var nickname = ""
    @State private var relationship = "Son"
    @State private var phoneNumber = ""
    @State private var birthDate = Date()
    @State private var hasBirthDate = false
    @State private var notes = ""

    static let relationships = ["Son", "Daughter", "Spouse", "Grandchild", "Sibling", "Friend", "Caregiver", "Neighbor", "Doctor", "Other"]

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Full name", text: $name)
                    TextField("Nickname (optional)", text: $nickname)
                    TextField("Phone number (optional)", text: $phoneNumber)
                        .keyboardType(.phonePad)
                }

                Section("Birthday") {
                    Toggle("Has birthday", isOn: $hasBirthDate)
                    if hasBirthDate {
                        DatePicker("Date", selection: $birthDate, displayedComponents: .date)
                    }
                }

                Section("Relationship") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(Self.relationships, id: \.self) { rel in
                            Button {
                                relationship = rel
                            } label: {
                                Text(rel)
                                    .font(.subheadline.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(relationship == rel ? Color.accentColor : Color(.systemGray5))
                                    .foregroundStyle(relationship == rel ? .white : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Notes") {
                    TextField("Interests, details...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let userId = UserDefaults.standard.string(forKey: "userId") ?? ""
                        onSave(APIClient.PersonRequest(
                            elderlyUserId: userId,
                            addedByUserId: userId,
                            name: name,
                            nickname: nickname.isEmpty ? nil : nickname,
                            relationship: relationship,
                            phoneNumber: phoneNumber.isEmpty ? nil : phoneNumber,
                            email: nil,
                            birthDate: hasBirthDate ? Self.dateFormatter.string(from: birthDate) : nil,
                            notes: notes.isEmpty ? nil : notes
                        ))
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(Color.accentColor)
    }
}
