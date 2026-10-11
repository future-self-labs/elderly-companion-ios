import SwiftUI

/// All conversations, newest first, with cursor pagination.
struct ConversationListView: View {
    @EnvironmentObject private var session: CaregiverSession
    @State private var items: [ConversationSummary] = []
    @State private var nextCursor: String?
    @State private var state: Loadable<Void> = .idle
    @State private var isLoadingMore = false
    @State private var loadMoreError: APIError?
    @State private var loadedFor: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: NoahSpacing.m) {
                if session.selected == nil {
                    NoElderlySelectedView()
                } else if items.isEmpty {
                    LoadableView(state: state, retry: { Task { await reload() } }) { _ in
                        EmptyStateView(systemImage: "bubble.left.and.bubble.right",
                                       title: "Nog geen gesprekken",
                                       message: "Na elk gesprek met Noah verschijnt hier een korte samenvatting, met de stemming en de onderwerpen.")
                    }
                } else {
                    ForEach(items) { conversation in
                        NavigationLink(value: CaregiverRoute.conversation(id: conversation.id)) {
                            ConversationRow(conversation: conversation)
                        }
                        .buttonStyle(.plain)
                    }
                    if nextCursor != nil {
                        Group {
                            if let loadMoreError {
                                ErrorStateView(message: loadMoreError.userMessage, isOffline: loadMoreError.isOffline) {
                                    Task { await loadMore() }
                                }
                            } else {
                                ProgressView()
                                    .tint(NoahColor.accent)
                                    .frame(maxWidth: .infinity, minHeight: 60)
                                    .task { await loadMore() }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, NoahSpacing.screen)
            .padding(.vertical, NoahSpacing.m)
            .noahReadableWidth()
        }
        .noahScreenBackground()
        .navigationTitle("Gesprekken")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { ElderlySwitcher() }
        }
        .refreshable { await reload() }
        .task(id: session.reloadKey) { await reload() }
    }

    private func reload() async {
        guard let id = session.selected?.id else { return }
        if loadedFor != id { items = []; state = .loading }
        do {
            let page = try await session.api.conversations(elderlyId: id, cursor: nil, limit: 20)
            items = page.items
            nextCursor = page.nextCursor
            loadedFor = id
            state = .loaded(())
            loadMoreError = nil
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled, items.isEmpty { state = .failed(apiError) }
        }
    }

    private func loadMore() async {
        guard let id = session.selected?.id, let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await session.api.conversations(elderlyId: id, cursor: cursor, limit: 20)
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            nextCursor = page.nextCursor
            loadMoreError = nil
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled { loadMoreError = apiError }
        }
    }
}

struct ConversationRow: View {
    let conversation: ConversationSummary

    var body: some View {
        NoahCard {
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text(verbatim: DutchFormat.dayAndTime(conversation.startedAt).capitalizedFirst)
                } icon: {
                    Image(systemName: conversation.channel.systemImage)
                }
                .font(NoahFont.bodyStrong)
                .foregroundColor(NoahColor.text)
                Spacer(minLength: NoahSpacing.xs)
                NoahMoodBadge(score: conversation.moodScore, showsLabel: false)
            }
            Text(verbatim: "\(conversation.channel.label) · \(DutchFormat.duration(seconds: conversation.durationSeconds))")
                .font(NoahFont.footnote)
                .foregroundColor(NoahColor.textSecondary)
            if let summary = conversation.summary {
                Text(verbatim: summary)
                    .font(NoahFont.callout)
                    .foregroundColor(NoahColor.textSoft)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            if conversation.hasConcern {
                Label("Noah merkte iets op", systemImage: "exclamationmark.triangle.fill")
                    .font(NoahFont.footnote)
                    .foregroundColor(NoahColor.accent)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text("Stemming: \(MoodText.label(conversation.moodScore))"))
    }
}
