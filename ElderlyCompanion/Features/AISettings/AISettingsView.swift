import SwiftUI

struct AISettingsView: View {
    @State private var toneStyle: ToneStyle = {
        ToneStyle(rawValue: UserDefaults.standard.string(forKey: "aiToneStyle") ?? "balanced") ?? .balanced
    }()
    @State private var proactiveLevel: ProactiveLevel = {
        ProactiveLevel(rawValue: UserDefaults.standard.string(forKey: "aiProactiveLevel") ?? "balanced") ?? .balanced
    }()
    @State private var callFrequencyLimit: Int = {
        let stored = UserDefaults.standard.integer(forKey: "aiCallFrequencyLimit")
        return stored > 0 ? stored : 3
    }()

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

        var description: String {
            switch self {
            case .formal: return "Polite and respectful"
            case .balanced: return "Warm and natural"
            case .informal: return "Casual and friendly"
            }
        }

        var icon: String {
            switch self {
            case .formal: return "person.text.rectangle"
            case .balanced: return "face.smiling"
            case .informal: return "hand.wave.fill"
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
                // Tone - high contrast custom selector
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                        CalmCardHeader("Conversation Tone", icon: "text.bubble.fill")

                        VStack(spacing: CompanionTheme.Spacing.sm) {
                            ForEach(ToneStyle.allCases, id: \.self) { style in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { toneStyle = style }
                                    UserDefaults.standard.set(style.rawValue, forKey: "aiToneStyle")
                                } label: {
                                    HStack(spacing: CompanionTheme.Spacing.md) {
                                        Image(systemName: style.icon)
                                            .font(.system(size: 18))
                                            .frame(width: 28)
                                            .foregroundStyle(
                                                toneStyle == style ? .white : Color.companionPrimary
                                            )

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(style.label)
                                                .font(.companionBody)
                                                .foregroundStyle(
                                                    toneStyle == style ? .white : Color.companionTextPrimary
                                                )
                                            Text(style.description)
                                                .font(.companionCaption)
                                                .foregroundStyle(
                                                    toneStyle == style ? .white.opacity(0.8) : Color.companionTextSecondary
                                                )
                                        }

                                        Spacer()

                                        if toneStyle == style {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .padding(CompanionTheme.Spacing.md)
                                    .background(
                                        toneStyle == style
                                            ? Color.companionPrimary
                                            : Color.companionSurfaceSecondary
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: CompanionTheme.Radius.md))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Proactive level
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                        CalmCardHeader("Proactive Level", icon: "sparkles")

                        ForEach(ProactiveLevel.allCases, id: \.self) { level in
                            Button {
                                withAnimation {
                                    proactiveLevel = level
                                    UserDefaults.standard.set(level.rawValue, forKey: "aiProactiveLevel")
                                }
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
                                        .font(.system(size: 22))
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
                        CalmCardHeader("Call Frequency Limit", icon: "phone.fill", subtitle: "Maximum proactive calls per day")

                        VStack(spacing: CompanionTheme.Spacing.sm) {
                            Text("\(callFrequencyLimit)")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.companionPrimary)

                            Text(callFrequencyLimit == 1 ? "call per day" : "calls per day")
                                .font(.companionBodySecondary)
                                .foregroundStyle(Color.companionTextSecondary)

                            HStack(spacing: CompanionTheme.Spacing.lg) {
                                Button {
                                    if callFrequencyLimit > 1 {
                                        callFrequencyLimit -= 1
                                        UserDefaults.standard.set(callFrequencyLimit, forKey: "aiCallFrequencyLimit")
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 36))
                                        .foregroundStyle(callFrequencyLimit > 1 ? Color.companionPrimary : Color.companionTextTertiary)
                                }
                                .disabled(callFrequencyLimit <= 1)

                                Button {
                                    if callFrequencyLimit < 10 {
                                        callFrequencyLimit += 1
                                        UserDefaults.standard.set(callFrequencyLimit, forKey: "aiCallFrequencyLimit")
                                    }
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 36))
                                        .foregroundStyle(callFrequencyLimit < 10 ? Color.companionPrimary : Color.companionTextTertiary)
                                }
                                .disabled(callFrequencyLimit >= 10)
                            }
                            .padding(.top, CompanionTheme.Spacing.sm)
                        }
                        .frame(maxWidth: .infinity)
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
