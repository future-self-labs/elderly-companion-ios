import SwiftUI

struct PrivacyView: View {
    @Environment(AppState.self) private var appState
    @State private var showDeleteAccountAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: CompanionTheme.Spacing.lg) {
                // Data storage info
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                        CalmCardHeader("Data Storage", icon: "server.rack")

                        InfoRow(label: "Conversations", value: "Encrypted, stored securely")
                        InfoRow(label: "Audio recordings", value: "Stored if enabled")
                        InfoRow(label: "Calendar data", value: "Read from your device")
                        InfoRow(label: "Personal info", value: "Name, phone, preferences")
                    }
                }

                // Consent management
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                        CalmCardHeader("Consent & Permissions", icon: "hand.raised.fill")

                        NavigationLink(destination: Text("Calendar permissions detail")) {
                            ConsentRow(title: "Calendar access", status: "Granted")
                        }
                        Divider()
                        NavigationLink(destination: Text("Microphone permissions detail")) {
                            ConsentRow(title: "Microphone access", status: "Granted")
                        }
                        Divider()
                        NavigationLink(destination: Text("Notification permissions detail")) {
                            ConsentRow(title: "Notifications", status: "Granted")
                        }
                    }
                }

                // GDPR
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                        CalmCardHeader("Your Rights", icon: "doc.text.fill")

                        VStack(spacing: CompanionTheme.Spacing.sm) {
                            LargeButton("Export My Data", icon: "arrow.down.doc.fill", style: .outline) {
                                // TODO: GDPR data export
                            }

                            LargeButton("Delete My Account", icon: "trash.fill", style: .danger) {
                                showDeleteAccountAlert = true
                            }
                        }
                    }
                }

                // Listening scope
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                        CalmCardHeader("Listening Scope", icon: "ear.fill")

                        Text("Noah only listens during active conversations that you initiate through the app or phone calls. Noah never listens passively or records ambient audio.")
                            .font(.companionBodySecondary)
                            .foregroundStyle(Color.companionTextSecondary)
                    }
                }
            }
            .padding(CompanionTheme.Spacing.lg)
        }
        .background(Color.companionBackground)
        .navigationTitle("Privacy & Data")
        .navigationBarTitleDisplayMode(.large)
        .alert("Delete Account?", isPresented: $showDeleteAccountAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                appState.signOut()
            }
        } message: {
            Text("This will permanently delete your account and all associated data including conversations, memories, and preferences. This cannot be undone.")
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.companionBody)
                .foregroundStyle(Color.companionTextPrimary)
            Spacer()
            Text(value)
                .font(.companionCaption)
                .foregroundStyle(Color.companionTextSecondary)
        }
    }
}

struct ConsentRow: View {
    let title: String
    let status: String

    var body: some View {
        HStack {
            Text(title)
                .font(.companionBody)
                .foregroundStyle(Color.companionTextPrimary)
            Spacer()
            Text(status)
                .font(.companionCaption)
                .foregroundStyle(Color.companionSuccess)
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Color.companionTextTertiary)
        }
    }
}
