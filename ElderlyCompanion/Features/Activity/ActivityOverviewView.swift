import SwiftUI

struct ActivityOverviewView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: CompanionTheme.Spacing.lg) {
                // Stats cards
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: CompanionTheme.Spacing.md) {
                    StatCard(title: "Conversations", value: "0", icon: "bubble.left.fill", color: .companionPrimary)
                    StatCard(title: "Memories", value: "0", icon: "book.fill", color: .companionInfo)
                    StatCard(title: "Events", value: "0", icon: "calendar", color: .companionSecondary)
                    StatCard(title: "Mood", value: "--", icon: "face.smiling", color: .companionSuccess)
                }

                // Weekly summary placeholder
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                        CalmCardHeader("This Week", icon: "chart.bar.fill")

                        Text("Activity summaries will appear here once you start using Noah regularly.")
                            .font(.companionBodySecondary)
                            .foregroundStyle(Color.companionTextTertiary)
                    }
                }
            }
            .padding(CompanionTheme.Spacing.lg)
        }
        .background(Color.companionBackground)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        CalmCard {
            VStack(spacing: CompanionTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(color)

                Text(value)
                    .font(.companionDisplay)
                    .foregroundStyle(Color.companionTextPrimary)

                Text(title)
                    .font(.companionCaption)
                    .foregroundStyle(Color.companionTextSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
