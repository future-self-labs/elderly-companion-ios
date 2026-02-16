import SwiftUI

@Observable
final class LegacyStoriesViewModel {
    var stories: [APIClient.LegacyStoryRecord] = []
    var isLoading = false
    var errorMessage: String?
    var showError = false

    func load(elderlyUserId: String? = nil) async {
        let userId = elderlyUserId ?? UserDefaults.standard.string(forKey: "userId") ?? ""
        guard !userId.isEmpty else { return }
        isLoading = true

        do {
            stories = try await APIClient.shared.getLegacyStories(elderlyUserId: userId)
            await MainActor.run { isLoading = false }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    var starred: [APIClient.LegacyStoryRecord] {
        stories.filter { $0.isStarred }
    }
}

struct LegacyStoriesView: View {
    @State private var viewModel = LegacyStoriesViewModel()
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("All Stories").tag(0)
                Text("Starred").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, CompanionTheme.Spacing.lg)
            .padding(.vertical, CompanionTheme.Spacing.md)

            Group {
                if viewModel.isLoading {
                    VStack { Spacer(); ProgressView().tint(Color.companionPrimary); Spacer() }
                } else {
                    let displayStories = selectedTab == 0 ? viewModel.stories : viewModel.starred

                    if displayStories.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: CompanionTheme.Spacing.md) {
                                ForEach(displayStories) { story in
                                    StoryCard(story: story)
                                }
                            }
                            .padding(CompanionTheme.Spacing.lg)
                        }
                    }
                }
            }
        }
        .background(Color.companionBackground)
        .navigationTitle("Legacy Stories")
        .navigationBarTitleDisplayMode(.large)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "Could not load stories.")
        }
        .task { await viewModel.load() }
    }

    private var emptyState: some View {
        VStack(spacing: CompanionTheme.Spacing.lg) {
            Spacer()
            Image(systemName: "book.closed.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.companionTextTertiary)
            VStack(spacing: CompanionTheme.Spacing.sm) {
                Text("No stories yet")
                    .font(.companionHeadline)
                    .foregroundStyle(Color.companionTextPrimary)
                Text("Life stories shared during conversations with Noah will appear here.")
                    .font(.companionBody)
                    .foregroundStyle(Color.companionTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, CompanionTheme.Spacing.xl)
            }
            Spacer()
        }
    }
}

struct StoryCard: View {
    let story: APIClient.LegacyStoryRecord

    var body: some View {
        CalmCard {
            VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(story.title)
                            .font(.companionBody)
                            .foregroundStyle(Color.companionTextPrimary)

                        Text(story.createdAt.prefix(10))
                            .font(.companionCaption)
                            .foregroundStyle(Color.companionTextTertiary)
                    }

                    Spacer()

                    if story.isStarred {
                        Image(systemName: "star.fill")
                            .foregroundStyle(Color.companionWarning)
                    }

                    if story.audioUrl != nil {
                        Image(systemName: "waveform")
                            .foregroundStyle(Color.companionPrimary)
                    }
                }

                if let summary = story.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.companionBodySecondary)
                        .foregroundStyle(Color.companionTextSecondary)
                        .lineLimit(3)
                }

                if !story.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(story.tags.prefix(4), id: \.self) { tag in
                            TagBadge(text: tag, color: .companionSecondary)
                        }
                    }
                }

                if let duration = story.audioDuration, duration > 0 {
                    HStack(spacing: CompanionTheme.Spacing.sm) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                        Text("\(duration / 60)m \(duration % 60)s")
                            .font(.companionCaption)
                    }
                    .foregroundStyle(Color.companionTextTertiary)
                }
            }
        }
    }
}
