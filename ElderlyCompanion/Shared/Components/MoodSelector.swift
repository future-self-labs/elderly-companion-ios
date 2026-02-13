import SwiftUI

enum Mood: String, CaseIterable, Sendable {
    case great
    case good
    case okay
    case notGreat = "not_great"
    case bad

    var emoji: String {
        switch self {
        case .great: return "😊"
        case .good: return "🙂"
        case .okay: return "😐"
        case .notGreat: return "😔"
        case .bad: return "😢"
        }
    }

    var label: String {
        switch self {
        case .great: return "Great"
        case .good: return "Good"
        case .okay: return "Okay"
        case .notGreat: return "Not great"
        case .bad: return "Bad"
        }
    }
}

struct MoodSelector: View {
    @Binding var selectedMood: Mood?

    var body: some View {
        VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
            Text("How are you feeling today?")
                .font(.companionBodySecondary)
                .foregroundStyle(Color.companionTextSecondary)

            HStack(spacing: CompanionTheme.Spacing.md) {
                ForEach(Mood.allCases, id: \.self) { mood in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            selectedMood = mood
                        }
                    } label: {
                        VStack(spacing: CompanionTheme.Spacing.xs) {
                            Text(mood.emoji)
                                .font(.system(size: 32))
                                .scaleEffect(selectedMood == mood ? 1.2 : 1.0)

                            Text(mood.label)
                                .font(.companionCaption)
                                .foregroundStyle(
                                    selectedMood == mood
                                        ? Color.companionPrimary
                                        : Color.companionTextTertiary
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, CompanionTheme.Spacing.sm)
                        .background(
                            selectedMood == mood
                                ? Color.companionPrimaryLight
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: CompanionTheme.Radius.md))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Feeling \(mood.label)")
                }
            }
        }
    }
}

#Preview {
    MoodSelector(selectedMood: .constant(.good))
        .padding()
}
