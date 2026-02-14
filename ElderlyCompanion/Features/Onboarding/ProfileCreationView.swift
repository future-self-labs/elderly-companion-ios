import SwiftUI

struct ProfileCreationView: View {
    @Binding var profile: UserProfile
    let onContinue: () -> Void

    @FocusState private var focusedField: Field?

    enum Field {
        case name, nickname, birthYear, city, phoneNumber
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CompanionTheme.Spacing.xl) {
                // Header
                VStack(alignment: .leading, spacing: CompanionTheme.Spacing.sm) {
                    Text("Tell us about yourself")
                        .font(.companionTitle)
                        .foregroundStyle(Color.companionTextPrimary)

                    Text("This helps Noah get to know you better.")
                        .font(.companionBody)
                        .foregroundStyle(Color.companionTextSecondary)
                }

                // Form fields
                VStack(spacing: CompanionTheme.Spacing.lg) {
                    CompanionTextField(
                        "Full name",
                        text: $profile.name,
                        icon: "person.fill"
                    )
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .nickname }

                    CompanionTextField(
                        "Preferred nickname (optional)",
                        text: $profile.nickname,
                        icon: "face.smiling"
                    )
                    .focused($focusedField, equals: .nickname)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .city }

                    CompanionTextField(
                        "City",
                        text: $profile.city,
                        icon: "mappin.and.ellipse"
                    )
                    .focused($focusedField, equals: .city)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .phoneNumber }

                    CompanionTextField(
                        "Phone number",
                        text: $profile.phoneNumber,
                        icon: "phone.fill"
                    )
                    .focused($focusedField, equals: .phoneNumber)
                    .keyboardType(.phonePad)

                    // Proactive calls toggle
                    CalmCard {
                        Toggle(isOn: $profile.proactiveCallsEnabled) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Proactive check-in calls")
                                    .font(.companionBody)
                                    .foregroundStyle(Color.companionTextPrimary)

                                Text("Noah may call to check in on you")
                                    .font(.companionCaption)
                                    .foregroundStyle(Color.companionTextSecondary)
                            }
                        }
                        .tint(Color.companionPrimary)
                    }
                }

                // Continue button
                LargeButton("Continue", icon: "arrow.right") {
                    onContinue()
                }
                .disabled(profile.name.isEmpty || profile.phoneNumber.isEmpty)
                .opacity(profile.name.isEmpty || profile.phoneNumber.isEmpty ? 0.5 : 1.0)
            }
            .padding(CompanionTheme.Spacing.lg)
        }
        .background(Color.companionBackground)
    }
}

// MARK: - Custom Text Field

struct CompanionTextField: View {
    let label: String
    @Binding var text: String
    let icon: String

    init(_ label: String, text: Binding<String>, icon: String) {
        self.label = label
        self._text = text
        self.icon = icon
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CompanionTheme.Spacing.xs) {
            // Always-visible label above the field
            Text(label)
                .font(.companionLabel)
                .foregroundStyle(Color.companionTextSecondary)

            HStack(spacing: CompanionTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.companionPrimary.opacity(0.6))
                    .frame(width: 24)

                TextField("", text: $text, prompt: Text(label).foregroundStyle(Color.companionTextTertiary))
                    .font(.companionBody)
                    .foregroundStyle(Color.companionTextPrimary)
            }
            .padding(CompanionTheme.Spacing.md)
            .background(Color.companionSurface)
            .clipShape(RoundedRectangle(cornerRadius: CompanionTheme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: CompanionTheme.Radius.md)
                    .stroke(
                        text.isEmpty
                            ? Color.companionTextTertiary.opacity(0.3)
                            : Color.companionPrimary.opacity(0.5),
                        lineWidth: 1
                    )
            )
        }
    }
}
