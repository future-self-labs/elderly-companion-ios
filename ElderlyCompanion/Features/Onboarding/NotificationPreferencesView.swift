import SwiftUI

struct NotificationPreferencesView: View {
    @Binding var preferences: NotificationPreferences
    let onContinue: () -> Void

    @State private var notificationService = NotificationService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CompanionTheme.Spacing.xl) {
                // Header
                VStack(alignment: .leading, spacing: CompanionTheme.Spacing.sm) {
                    Text("Notifications")
                        .font(.companionTitle)
                        .foregroundStyle(Color.companionTextPrimary)

                    Text("Choose how Noah can reach you with reminders and check-ins.")
                        .font(.companionBody)
                        .foregroundStyle(Color.companionTextSecondary)
                }

                // Notification methods
                VStack(spacing: CompanionTheme.Spacing.md) {
                    CalmCard {
                        Toggle(isOn: $preferences.callEnabled) {
                            HStack(spacing: CompanionTheme.Spacing.sm) {
                                Image(systemName: "phone.fill")
                                    .foregroundStyle(Color.companionPrimary)
                                Text("Phone calls")
                                    .font(.companionBody)
                                    .foregroundStyle(Color.companionTextPrimary)
                            }
                        }
                        .tint(Color.companionPrimary)
                    }

                    CalmCard {
                        Toggle(isOn: $preferences.pushEnabled) {
                            HStack(spacing: CompanionTheme.Spacing.sm) {
                                Image(systemName: "bell.fill")
                                    .foregroundStyle(Color.companionPrimary)
                                Text("Push notifications")
                                    .font(.companionBody)
                                    .foregroundStyle(Color.companionTextPrimary)
                            }
                        }
                        .tint(Color.companionPrimary)
                    }

                    CalmCard {
                        Toggle(isOn: $preferences.smsEnabled) {
                            HStack(spacing: CompanionTheme.Spacing.sm) {
                                Image(systemName: "message.fill")
                                    .foregroundStyle(Color.companionPrimary)
                                Text("SMS messages")
                                    .font(.companionBody)
                                    .foregroundStyle(Color.companionTextPrimary)
                            }
                        }
                        .tint(Color.companionPrimary)
                    }
                }

                // Quiet hours
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                        CalmCardHeader("Quiet Hours", icon: "moon.fill", subtitle: "Do not disturb window")

                        HStack {
                            VStack(alignment: .leading) {
                                Text("From")
                                    .font(.companionCaption)
                                    .foregroundStyle(Color.companionTextSecondary)
                                Text("\(preferences.quietHoursStart):00")
                                    .font(.companionHeadline)
                                    .foregroundStyle(Color.companionTextPrimary)
                            }

                            Spacer()

                            Image(systemName: "arrow.right")
                                .foregroundStyle(Color.companionTextTertiary)

                            Spacer()

                            VStack(alignment: .trailing) {
                                Text("Until")
                                    .font(.companionCaption)
                                    .foregroundStyle(Color.companionTextSecondary)
                                Text("\(preferences.quietHoursEnd):00")
                                    .font(.companionHeadline)
                                    .foregroundStyle(Color.companionTextPrimary)
                            }
                        }
                    }
                }

                // Continue
                LargeButton("Continue", icon: "arrow.right") {
                    if preferences.pushEnabled {
                        Task {
                            _ = await notificationService.requestAuthorization()
                            await MainActor.run { onContinue() }
                        }
                    } else {
                        onContinue()
                    }
                }
            }
            .padding(CompanionTheme.Spacing.lg)
        }
        .background(Color.companionBackground)
    }
}
