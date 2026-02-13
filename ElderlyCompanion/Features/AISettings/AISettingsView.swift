import SwiftUI

struct AISettingsView: View {
    @State private var toneStyle: ToneStyle = .balanced
    @State private var proactiveLevel: ProactiveLevel = .balanced
    @State private var callFrequencyLimit = 3

    enum ToneStyle: String, CaseIterable {
        case formal
        case balanced
        case informal

        var label: String {
            switch self {
            case .formal: return "Formal"
            case .balanced: return "Balanced"
            case .informal: return "Informal"
            }
        }
    }

    enum ProactiveLevel: String, CaseIterable {
        case quiet
        case balanced
        case engaged

        var label: String {
            switch self {
            case .quiet: return "Quiet"
            case .balanced: return "Balanced"
            case .engaged: return "Engaged"
            }
        }

        var description: String {
            switch self {
            case .quiet: return "Noah mostly listens, rarely initiates"
            case .balanced: return "Noah checks in occasionally"
            case .engaged: return "Noah actively engages and suggests"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: CompanionTheme.Spacing.lg) {
                // Tone
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                        CalmCardHeader("Conversation Tone", icon: "text.bubble.fill")

                        Picker("Tone", selection: $toneStyle) {
                            ForEach(ToneStyle.allCases, id: \.self) { style in
                                Text(style.label).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                // Proactive level
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                        CalmCardHeader("Proactive Level", icon: "sparkles")

                        ForEach(ProactiveLevel.allCases, id: \.self) { level in
                            Button {
                                withAnimation { proactiveLevel = level }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(level.label)
                                            .font(.companionBody)
                                            .foregroundStyle(Color.companionTextPrimary)
                                        Text(level.description)
                                            .font(.companionCaption)
                                            .foregroundStyle(Color.companionTextSecondary)
                                    }

                                    Spacer()

                                    Image(systemName: proactiveLevel == level ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(proactiveLevel == level ? Color.companionPrimary : Color.companionTextTertiary)
                                }
                                .padding(.vertical, CompanionTheme.Spacing.xs)
                            }
                            .buttonStyle(.plain)

                            if level != ProactiveLevel.allCases.last {
                                Divider()
                            }
                        }
                    }
                }

                // Call frequency
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                        CalmCardHeader("Call Frequency Limit", icon: "phone.fill", subtitle: "Maximum calls per day")

                        Stepper("\(callFrequencyLimit) calls per day", value: $callFrequencyLimit, in: 1...10)
                            .font(.companionBody)
                    }
                }
            }
            .padding(CompanionTheme.Spacing.lg)
        }
        .background(Color.companionBackground)
        .navigationTitle("AI Personality")
        .navigationBarTitleDisplayMode(.large)
    }
}
