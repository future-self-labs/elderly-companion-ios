import SwiftUI

struct SettingsHubView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(spacing: CompanionTheme.Spacing.md) {
                // User info card
                if let user = appState.currentUser {
                    CalmCard {
                        HStack(spacing: CompanionTheme.Spacing.md) {
                            ZStack {
                                Circle()
                                    .fill(Color.companionPrimaryLight)
                                    .frame(width: 56, height: 56)

                                Text(String(user.name.prefix(1)).uppercased())
                                    .font(.companionHeadline)
                                    .foregroundStyle(Color.companionPrimary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.name)
                                    .font(.companionHeadline)
                                    .foregroundStyle(Color.companionTextPrimary)

                                Text(user.phoneNumber)
                                    .font(.companionCaption)
                                    .foregroundStyle(Color.companionTextSecondary)
                            }

                            Spacer()
                        }
                    }
                }

                // Appearance
                SettingsSection(title: "Appearance") {
                    SettingsRow(title: "Theme", icon: "paintbrush.fill", color: .companionSecondary) {
                        ThemePickerView()
                    }
                }

                // Main features
                SettingsSection(title: "Features") {
                    SettingsRow(title: "Scheduled Calls", icon: "phone.arrow.up.right.fill", color: .companionSuccess) {
                        ScheduledCallsView()
                    }
                    SettingsRow(title: "Call History", icon: "phone.fill", color: .companionPrimary) {
                        CallHistoryView()
                    }
                    SettingsRow(title: "Routines & Reminders", icon: "bell.fill", color: .companionSecondary) {
                        RoutinesView()
                    }
                    SettingsRow(title: "Activity Overview", icon: "chart.bar.fill", color: .companionInfo) {
                        ActivityOverviewView()
                    }
                }

                // People & Memory
                SettingsSection(title: "People & Memory") {
                    SettingsRow(title: "Memory Vault — People", icon: "person.text.rectangle.fill", color: .companionPrimary) {
                        PeopleView()
                    }
                    SettingsRow(title: "Family Circle", icon: "person.3.fill", color: .companionSecondary) {
                        FamilySettingsView()
                    }
                    SettingsRow(title: "Legacy Stories", icon: "book.fill", color: .companionInfo) {
                        LegacyStoriesView()
                    }
                    SettingsRow(title: "Wellbeing Dashboard", icon: "chart.line.uptrend.xyaxis", color: .companionSuccess) {
                        CaretakerDashboardView()
                    }
                    SettingsRow(title: "Emergency Contacts", icon: "staroflife.fill", color: .companionDanger) {
                        EscalationView()
                    }
                }

                // Health
                SettingsSection(title: "Health") {
                    SettingsRow(title: "Health & Peripherals", icon: "heart.text.clipboard.fill", color: .companionDanger) {
                        HealthSettingsView()
                    }
                }

                // AI Configuration
                SettingsSection(title: "Noah") {
                    SettingsRow(title: "Personality", icon: "sparkles", color: .companionSecondary) {
                        AISettingsView()
                    }
                    SettingsRow(title: "Memory & Context", icon: "brain.fill", color: .companionInfo) {
                        AIMemoryView()
                    }
                }

                // Safety & Privacy
                SettingsSection(title: "Safety & Privacy") {
                    SettingsRow(title: "Safety & Protection", icon: "shield.fill", color: .companionSuccess) {
                        SafetyView()
                    }
                    SettingsRow(title: "Privacy & Data", icon: "lock.fill", color: .companionTextSecondary) {
                        PrivacyView()
                            .environment(appState)
                    }
                }

                // Sign out
                Button {
                    appState.signOut()
                } label: {
                    Text("Sign Out")
                        .font(.companionBody)
                        .foregroundStyle(Color.companionDanger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, CompanionTheme.Spacing.md)
                }
                .padding(.top, CompanionTheme.Spacing.lg)
            }
            .padding(CompanionTheme.Spacing.lg)
        }
        .background(Color.companionBackground)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Settings Section

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: CompanionTheme.Spacing.sm) {
            Text(title.uppercased())
                .font(.companionLabel)
                .foregroundStyle(Color.companionTextTertiary)
                .padding(.leading, CompanionTheme.Spacing.sm)

            CalmCard {
                VStack(spacing: 0) {
                    content()
                }
            }
        }
    }
}

// MARK: - Settings Row

struct SettingsRow<Destination: View>: View {
    let title: String
    let icon: String
    let color: Color
    let destination: () -> Destination

    init(title: String, icon: String, color: Color, @ViewBuilder destination: @escaping () -> Destination) {
        self.title = title
        self.icon = icon
        self.color = color
        self.destination = destination
    }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: CompanionTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: CompanionTheme.Radius.sm))

                Text(title)
                    .font(.companionBody)
                    .foregroundStyle(Color.companionTextPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.companionTextTertiary)
            }
            .padding(.vertical, CompanionTheme.Spacing.sm)
        }
        .buttonStyle(.plain)
    }
}
