import SwiftUI

struct SafetyView: View {
    @State private var scamProtectionEnabled = true
    @State private var notifyOnDistress = true
    @State private var notifyOnConfusion = true
    @State private var notifyOnScam = true

    var body: some View {
        ScrollView {
            VStack(spacing: CompanionTheme.Spacing.lg) {
                // Scam protection
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                        CalmCardHeader("Scam Protection", icon: "shield.fill")

                        Toggle(isOn: $scamProtectionEnabled) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Enable scam detection")
                                    .font(.companionBody)
                                Text("Noah will gently intervene if a suspicious call pattern is detected")
                                    .font(.companionCaption)
                                    .foregroundStyle(Color.companionTextSecondary)
                            }
                        }
                        .tint(Color.companionPrimary)
                    }
                }

                // Escalation rules
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                        CalmCardHeader("Escalation Rules", icon: "exclamationmark.triangle.fill", subtitle: "When to notify family")

                        Toggle(isOn: $notifyOnScam) {
                            Text("High scam probability")
                                .font(.companionBody)
                        }
                        .tint(Color.companionPrimary)

                        Divider()

                        Toggle(isOn: $notifyOnDistress) {
                            Text("Emotional distress pattern")
                                .font(.companionBody)
                        }
                        .tint(Color.companionPrimary)

                        Divider()

                        Toggle(isOn: $notifyOnConfusion) {
                            Text("Repeated confusion")
                                .font(.companionBody)
                        }
                        .tint(Color.companionPrimary)
                    }
                }

                // Calm alerts log
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                        CalmCardHeader("Calm Alerts Log", icon: "list.bullet.clipboard")

                        Text("No alerts recorded yet. Past safety interventions will appear here.")
                            .font(.companionBodySecondary)
                            .foregroundStyle(Color.companionTextTertiary)
                    }
                }
            }
            .padding(CompanionTheme.Spacing.lg)
        }
        .background(Color.companionBackground)
        .navigationTitle("Safety")
        .navigationBarTitleDisplayMode(.large)
    }
}
