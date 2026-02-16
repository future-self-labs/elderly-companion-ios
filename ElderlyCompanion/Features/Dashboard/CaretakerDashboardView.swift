import SwiftUI

@Observable
final class CaretakerDashboardViewModel {
    var summary: APIClient.WellbeingSummary?
    var isLoading = false
    var errorMessage: String?
    var showError = false

    func load(elderlyUserId: String? = nil) async {
        let userId = elderlyUserId ?? UserDefaults.standard.string(forKey: "userId") ?? ""
        guard !userId.isEmpty else { return }
        isLoading = true

        do {
            summary = try await APIClient.shared.getWellbeingSummary(elderlyUserId: userId)
            await MainActor.run { isLoading = false }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

struct CaretakerDashboardView: View {
    @State private var viewModel = CaretakerDashboardViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: CompanionTheme.Spacing.lg) {
                // Header
                CalmCard {
                    VStack(spacing: CompanionTheme.Spacing.md) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.companionInfo)

                        Text("Wellbeing Dashboard")
                            .font(.companionHeadline)
                            .foregroundStyle(Color.companionTextPrimary)

                        Text("Overview of the past 7 days")
                            .font(.companionBodySecondary)
                            .foregroundStyle(Color.companionTextSecondary)
                    }
                }

                if viewModel.isLoading {
                    ProgressView().tint(Color.companionPrimary)
                } else if let summary = viewModel.summary {
                    // Mood
                    CalmCard {
                        VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                            CalmCardHeader("Mood", icon: "face.smiling.fill")

                            if let mood = summary.averageMoodScore {
                                HStack(spacing: CompanionTheme.Spacing.md) {
                                    Text(moodEmoji(mood))
                                        .font(.system(size: 44))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(String(format: "%.1f / 5.0", mood))
                                            .font(.system(size: 28, weight: .bold, design: .rounded))
                                            .foregroundStyle(moodColor(mood))

                                        Text("Average mood score")
                                            .font(.companionCaption)
                                            .foregroundStyle(Color.companionTextSecondary)
                                    }
                                }
                            } else {
                                Text("No mood data this week")
                                    .font(.companionBodySecondary)
                                    .foregroundStyle(Color.companionTextTertiary)
                            }
                        }
                    }

                    // Activity
                    CalmCard {
                        VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                            CalmCardHeader("Activity", icon: "bubble.left.and.bubble.right.fill")

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: CompanionTheme.Spacing.md) {
                                StatTile(label: "Conversations", value: "\(summary.totalConversations)", icon: "phone.fill", color: .companionPrimary)
                                StatTile(label: "Minutes", value: "\(summary.totalMinutes)", icon: "clock.fill", color: .companionSecondary)
                                StatTile(label: "Active Days", value: "\(summary.activeDays)/7", icon: "calendar", color: .companionInfo)
                            }
                        }
                    }

                    // Concerns
                    if !summary.concerns.isEmpty {
                        CalmCard {
                            VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                                CalmCardHeader("Concerns", icon: "exclamationmark.triangle.fill")

                                ForEach(summary.concerns, id: \.self) { concern in
                                    HStack(spacing: CompanionTheme.Spacing.sm) {
                                        Circle()
                                            .fill(Color.companionDanger)
                                            .frame(width: 8, height: 8)
                                        Text(concern)
                                            .font(.companionBody)
                                            .foregroundStyle(Color.companionTextPrimary)
                                    }
                                }
                            }
                        }
                    }

                    // Topics
                    if !summary.topTopics.isEmpty {
                        CalmCard {
                            VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                                CalmCardHeader("Topics Discussed", icon: "text.bubble.fill")

                                FlowLayout(spacing: CompanionTheme.Spacing.sm) {
                                    ForEach(summary.topTopics, id: \.self) { topic in
                                        TagBadge(text: topic, color: .companionPrimary)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    CalmCard {
                        Text("No wellbeing data available yet. Data is collected automatically from conversations with Noah.")
                            .font(.companionBodySecondary)
                            .foregroundStyle(Color.companionTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(CompanionTheme.Spacing.lg)
        }
        .background(Color.companionBackground)
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.large)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "Could not load dashboard.")
        }
        .task { await viewModel.load() }
    }

    private func moodEmoji(_ score: Double) -> String {
        switch score {
        case 4.5...5: return "😊"
        case 3.5..<4.5: return "🙂"
        case 2.5..<3.5: return "😐"
        case 1.5..<2.5: return "😔"
        default: return "😢"
        }
    }

    private func moodColor(_ score: Double) -> Color {
        switch score {
        case 4...5: return .companionSuccess
        case 3..<4: return .companionPrimary
        case 2..<3: return .companionWarning
        default: return .companionDanger
        }
    }
}

struct StatTile: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: CompanionTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.companionTextPrimary)

            Text(label)
                .font(.companionCaption)
                .foregroundStyle(Color.companionTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CompanionTheme.Spacing.md)
        .background(Color.companionSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CompanionTheme.Radius.md))
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var maxRowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += maxRowHeight + spacing
                maxRowHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            maxRowHeight = max(maxRowHeight, size.height)
            currentX += size.width + spacing
            totalHeight = currentY + maxRowHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
