import SwiftUI

struct LegacyPreferencesView: View {
    @Binding var preferences: LegacyPreferences
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: CompanionTheme.Spacing.xl) {
            Spacer()

            // Header
            VStack(spacing: CompanionTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.companionPrimaryLight)
                        .frame(width: 80, height: 80)

                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.companionPrimary)
                }

                Text("Life Story Capture")
                    .font(.companionTitle)
                    .foregroundStyle(Color.companionTextPrimary)

                Text("Noah can help preserve life stories and precious memories through natural conversation.")
                    .font(.companionBody)
                    .foregroundStyle(Color.companionTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, CompanionTheme.Spacing.lg)
            }

            // Toggles
            VStack(spacing: CompanionTheme.Spacing.md) {
                CalmCard {
                    Toggle(isOn: $preferences.lifeStoryCaptureEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Life story capture")
                                .font(.companionBody)
                                .foregroundStyle(Color.companionTextPrimary)
                            Text("Gently record stories during conversations")
                                .font(.companionCaption)
                                .foregroundStyle(Color.companionTextSecondary)
                        }
                    }
                    .tint(Color.companionPrimary)
                }

                CalmCard {
                    Toggle(isOn: $preferences.audioStorageEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Store audio recordings")
                                .font(.companionBody)
                                .foregroundStyle(Color.companionTextPrimary)
                            Text("Keep voice recordings of special memories")
                                .font(.companionCaption)
                                .foregroundStyle(Color.companionTextSecondary)
                        }
                    }
                    .tint(Color.companionPrimary)
                }

                CalmCard {
                    Toggle(isOn: $preferences.familySharingEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Share with family")
                                .font(.companionBody)
                                .foregroundStyle(Color.companionTextPrimary)
                            Text("Allow family members to view memories")
                                .font(.companionCaption)
                                .foregroundStyle(Color.companionTextSecondary)
                        }
                    }
                    .tint(Color.companionPrimary)
                }
            }
            .padding(.horizontal, CompanionTheme.Spacing.lg)

            Spacer()

            LargeButton("Get Started", icon: "sparkles") {
                onContinue()
            }
            .padding(.horizontal, CompanionTheme.Spacing.lg)
            .padding(.bottom, CompanionTheme.Spacing.xxl)
        }
        .background(Color.companionBackground)
    }
}
