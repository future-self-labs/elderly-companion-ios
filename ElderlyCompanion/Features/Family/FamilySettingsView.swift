import SwiftUI

struct FamilySettingsView: View {
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

                // Add family member button
                LargeButton("Add Family Member", icon: "person.badge.plus", style: .outline) {
                    // TODO: Implement add family member flow
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
    }
}
