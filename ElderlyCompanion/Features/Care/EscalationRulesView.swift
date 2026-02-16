import SwiftUI

struct EscalationRulesView: View {
    @State private var settings: APIClient.CareSettingsRecord?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: CompanionTheme.Spacing.lg) {
                if isLoading {
                    ProgressView().tint(Color.companionPrimary)
                } else if var s = settings {
                    // Sensitivity
                    CalmCard {
                        VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                            CalmCardHeader("Sensitivity Level", icon: "slider.horizontal.3")
                            Picker("", selection: Binding(
                                get: { s.sensitivity },
                                set: { s.sensitivity = $0; settings = s; save(s) }
                            )) {
                                Text("Conservative").tag("conservative")
                                Text("Balanced").tag("balanced")
                                Text("Protective").tag("protective")
                            }
                            .pickerStyle(.segmented)

                            Text(sensitivityDescription(s.sensitivity))
                                .font(.companionCaption)
                                .foregroundStyle(Color.companionTextSecondary)
                        }
                    }

                    // Silence window
                    CalmCard {
                        VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                            CalmCardHeader("Silence Window", icon: "clock.badge.questionmark", subtitle: "Hours of no contact before alerting")
                            Picker("", selection: Binding(
                                get: { s.silenceWindowHours },
                                set: { s.silenceWindowHours = $0; settings = s; save(s) }
                            )) {
                                Text("24h").tag(24)
                                Text("48h").tag(48)
                                Text("72h").tag(72)
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    // Scam threshold
                    CalmCard {
                        VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                            CalmCardHeader("Scam Detection", icon: "exclamationmark.shield.fill")
                            Picker("", selection: Binding(
                                get: { s.scamThreshold },
                                set: { s.scamThreshold = $0; settings = s; save(s) }
                            )) {
                                Text("Low").tag("low")
                                Text("Medium").tag("medium")
                                Text("High").tag("high")
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    // Max outreach per week
                    CalmCard {
                        VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                            CalmCardHeader("Max Outreach / Week", icon: "phone.badge.waveform.fill", subtitle: "Maximum times Noah contacts your trusted circle per week")
                            Stepper("\(s.maxOutreachPerWeek) per week", value: Binding(
                                get: { s.maxOutreachPerWeek },
                                set: { s.maxOutreachPerWeek = $0; settings = s; save(s) }
                            ), in: 1...10)
                            .font(.companionBody)
                        }
                    }

                    // Cooldown
                    CalmCard {
                        VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                            CalmCardHeader("Escalation Cooldown", icon: "timer", subtitle: "Minimum hours between escalation events")
                            Picker("", selection: Binding(
                                get: { s.escalationCooldownHours },
                                set: { s.escalationCooldownHours = $0; settings = s; save(s) }
                            )) {
                                Text("12h").tag(12)
                                Text("24h").tag(24)
                                Text("48h").tag(48)
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }
            }
            .padding(CompanionTheme.Spacing.lg)
        }
        .background(Color.companionBackground)
        .navigationTitle("Escalation Rules")
        .navigationBarTitleDisplayMode(.large)
        .task { await loadSettings() }
    }

    private func loadSettings() async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        do {
            settings = try await APIClient.shared.getCareSettings(elderlyUserId: userId)
            isLoading = false
        } catch {
            isLoading = false
        }
    }

    private func save(_ s: APIClient.CareSettingsRecord) {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        Task {
            do { try await APIClient.shared.updateCareSettings(elderlyUserId: userId, settings: s) }
            catch { print("[EscalationRules] Save error: \(error)") }
        }
    }

    private func sensitivityDescription(_ level: String) -> String {
        switch level {
        case "conservative": return "Higher thresholds — Noah only alerts for clear, persistent concerns"
        case "protective": return "Lower thresholds — Noah alerts earlier, even for mild concerns"
        default: return "Balanced approach — Noah uses moderate thresholds"
        }
    }
}
