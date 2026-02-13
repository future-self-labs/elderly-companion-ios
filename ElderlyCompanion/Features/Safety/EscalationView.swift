import SwiftUI

struct EscalationView: View {
    @State private var gpNumber = ""
    @State private var emergencyNumber = ""
    @State private var askPermissionBeforeEscalating = true
    @State private var autoEscalateOnSevere = true

    var body: some View {
        ScrollView {
            VStack(spacing: CompanionTheme.Spacing.lg) {
                // Trusted contacts
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                        CalmCardHeader("Trusted Contacts", icon: "person.2.fill")

                        LargeButton("Add Trusted Contact", icon: "person.badge.plus", style: .outline) {
                            // TODO: Add contact picker
                        }
                    }
                }

                // Important numbers
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                        CalmCardHeader("Important Numbers", icon: "phone.fill")

                        CompanionTextField("GP / Doctor number", text: $gpNumber, icon: "cross.case.fill")
                        CompanionTextField("Emergency number", text: $emergencyNumber, icon: "staroflife.fill")
                    }
                }

                // Escalation behavior
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                        CalmCardHeader("Escalation Behavior", icon: "arrow.up.right.circle.fill")

                        Toggle(isOn: $askPermissionBeforeEscalating) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ask before escalating")
                                    .font(.companionBody)
                                Text("Noah will ask your permission before contacting family")
                                    .font(.companionCaption)
                                    .foregroundStyle(Color.companionTextSecondary)
                            }
                        }
                        .tint(Color.companionPrimary)

                        Divider()

                        Toggle(isOn: $autoEscalateOnSevere) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-escalate if severe")
                                    .font(.companionBody)
                                Text("Bypass permission in critical safety situations")
                                    .font(.companionCaption)
                                    .foregroundStyle(Color.companionTextSecondary)
                            }
                        }
                        .tint(Color.companionDanger)
                    }
                }
            }
            .padding(CompanionTheme.Spacing.lg)
        }
        .background(Color.companionBackground)
        .navigationTitle("Emergency Contacts")
        .navigationBarTitleDisplayMode(.large)
    }
}
