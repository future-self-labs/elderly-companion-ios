import SwiftUI

// MARK: - View Model

@Observable
final class LegacyArchiveViewModel {
    var transcripts: [APIClient.TranscriptRecord] = []
    var isLoading = false
    var errorMessage: String?
    var showError = false

    func load() async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        isLoading = true

        do {
            transcripts = try await APIClient.shared.getTranscripts(userId: userId)
            await MainActor.run { isLoading = false }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    /// Transcripts that contain at least one message
    var withMessages: [APIClient.TranscriptRecord] {
        transcripts.filter { !$0.messages.isEmpty }
    }

    /// Transcripts tagged as important or memory_capture
    var starred: [APIClient.TranscriptRecord] {
        transcripts.filter { record in
            record.tags.contains("important") || record.tags.contains("memory_capture")
        }
    }
}

// MARK: - Main View

struct LegacyArchiveView: View {
    @State private var viewModel = LegacyArchiveViewModel()
    @State private var selectedTab: ArchiveTab = .transcripts

    enum ArchiveTab: String, CaseIterable {
        case transcripts
        case timeline
        case highlighted

        var label: String {
            switch self {
            case .transcripts: return "Transcripts"
            case .timeline: return "Timeline"
            case .highlighted: return "Starred"
            }
        }

        var icon: String {
            switch self {
            case .transcripts: return "doc.text.fill"
            case .timeline: return "clock.fill"
            case .highlighted: return "star.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CompanionTheme.Spacing.sm) {
                    ForEach(ArchiveTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation { selectedTab = tab }
                        } label: {
                            Label(tab.label, systemImage: tab.icon)
                                .font(.companionLabel)
                                .padding(.horizontal, CompanionTheme.Spacing.md)
                                .padding(.vertical, CompanionTheme.Spacing.sm)
                                .background(selectedTab == tab ? Color.companionPrimary : Color.companionSurface)
                                .foregroundStyle(selectedTab == tab ? .white : Color.companionTextSecondary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, CompanionTheme.Spacing.lg)
                .padding(.vertical, CompanionTheme.Spacing.md)
            }

            // Content
            Group {
                if viewModel.isLoading {
                    loadingView
                } else {
                    switch selectedTab {
                    case .transcripts:
                        transcriptsTab
                    case .timeline:
                        timelineTab
                    case .highlighted:
                        starredTab
                    }
                }
            }
        }
        .background(Color.companionBackground)
        .navigationTitle("Memories")
        .navigationBarTitleDisplayMode(.large)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "Could not load memories.")
        }
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .tint(Color.companionPrimary)
            Text("Loading memories...")
                .font(.companionCaption)
                .foregroundStyle(Color.companionTextSecondary)
                .padding(.top, CompanionTheme.Spacing.sm)
            Spacer()
        }
    }

    // MARK: - Transcripts Tab

    private var transcriptsTab: some View {
        Group {
            if viewModel.withMessages.isEmpty {
                emptyState(
                    icon: "doc.text.fill",
                    title: "No transcripts yet",
                    message: "Conversations with Noah will be saved here with full transcripts."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: CompanionTheme.Spacing.md) {
                        ForEach(viewModel.withMessages) { transcript in
                            TranscriptCard(transcript: transcript)
                        }
                    }
                    .padding(CompanionTheme.Spacing.lg)
                }
            }
        }
    }

    // MARK: - Timeline Tab

    private var timelineTab: some View {
        Group {
            if viewModel.transcripts.isEmpty {
                emptyState(
                    icon: "clock.fill",
                    title: "No conversations yet",
                    message: "Your conversation timeline with Noah will appear here."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.transcripts.enumerated()), id: \.element.id) { index, transcript in
                            TimelineRow(transcript: transcript, isLast: index == viewModel.transcripts.count - 1)
                        }
                    }
                    .padding(CompanionTheme.Spacing.lg)
                }
            }
        }
    }

    // MARK: - Starred Tab

    private var starredTab: some View {
        Group {
            if viewModel.starred.isEmpty {
                emptyState(
                    icon: "star.fill",
                    title: "No starred memories",
                    message: "Mark conversations as important during a call and they'll appear here."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: CompanionTheme.Spacing.md) {
                        ForEach(viewModel.starred) { transcript in
                            TranscriptCard(transcript: transcript)
                        }
                    }
                    .padding(CompanionTheme.Spacing.lg)
                }
            }
        }
    }

    // MARK: - Empty State

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: CompanionTheme.Spacing.lg) {
            Spacer(minLength: CompanionTheme.Spacing.xxxl)

            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(Color.companionTextTertiary)

            VStack(spacing: CompanionTheme.Spacing.sm) {
                Text(title)
                    .font(.companionHeadline)
                    .foregroundStyle(Color.companionTextPrimary)

                Text(message)
                    .font(.companionBody)
                    .foregroundStyle(Color.companionTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, CompanionTheme.Spacing.xl)
            }

            Spacer()
        }
    }
}

// MARK: - Transcript Card

struct TranscriptCard: View {
    let transcript: APIClient.TranscriptRecord

    @State private var isExpanded = false
    @State private var isPlayingAudio = false

    private var date: Date {
        LegacyDateParser.parse(transcript.createdAt)
    }

    private var durationText: String {
        let minutes = transcript.duration / 60
        let seconds = transcript.duration % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    var body: some View {
        CalmCard {
            VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(date.formatted(.dateTime.weekday(.wide).month().day()))
                            .font(.companionBody)
                            .foregroundStyle(Color.companionTextPrimary)

                        HStack(spacing: CompanionTheme.Spacing.sm) {
                            Label(durationText, systemImage: "clock")
                            Label("\(transcript.messages.count) messages", systemImage: "text.bubble")
                        }
                        .font(.companionCaption)
                        .foregroundStyle(Color.companionTextSecondary)
                    }

                    Spacer()

                    // Tags
                    HStack(spacing: 4) {
                        ForEach(transcript.tags.prefix(2), id: \.self) { tag in
                            TagBadge(
                                text: tag.capitalized,
                                color: tagColor(tag)
                            )
                        }
                    }
                }

                // Summary
                if let summary = transcript.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.companionBodySecondary)
                        .foregroundStyle(Color.companionTextSecondary)
                        .lineLimit(isExpanded ? nil : 2)
                }

                // Expandable messages
                if isExpanded {
                    Divider()
                        .padding(.vertical, CompanionTheme.Spacing.xs)

                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.sm) {
                        ForEach(Array(transcript.messages.enumerated()), id: \.offset) { _, message in
                            MessageBubble(message: message)
                        }
                    }
                }

                // Audio playback button
                if let audioUrl = transcript.audioUrl, !audioUrl.isEmpty {
                    Button {
                        isPlayingAudio.toggle()
                    } label: {
                        HStack(spacing: CompanionTheme.Spacing.sm) {
                            Image(systemName: isPlayingAudio ? "stop.circle.fill" : "play.circle.fill")
                                .font(.system(size: 28))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isPlayingAudio ? "Playing..." : "Play recording")
                                    .font(.companionLabel)
                                Text(durationText)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.companionTextTertiary)
                            }
                            Spacer()
                        }
                        .foregroundStyle(Color.companionPrimary)
                        .padding(CompanionTheme.Spacing.sm)
                        .background(Color.companionPrimaryLight)
                        .clipShape(RoundedRectangle(cornerRadius: CompanionTheme.Radius.md))
                    }
                    .buttonStyle(.plain)
                }

                // Action buttons
                if !transcript.messages.isEmpty {
                    HStack(spacing: CompanionTheme.Spacing.md) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(isExpanded ? "Hide" : "Show")
                                    .font(.companionLabel)
                            }
                            .foregroundStyle(Color.companionPrimary)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        ShareLink(
                            item: formatTranscriptForExport(),
                            subject: Text("Noah Conversation"),
                            message: Text("Transcript from \(date.formatted(.dateTime.weekday(.wide).month().day()))")
                        ) {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Export")
                                    .font(.companionLabel)
                            }
                            .foregroundStyle(Color.companionPrimary)
                        }
                    }
                }
            }
        }
    }

    private func formatTranscriptForExport() -> String {
        var text = "Noah — Conversation Transcript\n"
        text += "Date: \(date.formatted(.dateTime.weekday(.wide).month(.wide).day().year().hour().minute()))\n"
        text += "Duration: \(durationText)\n"
        if let summary = transcript.summary, !summary.isEmpty {
            text += "Summary: \(summary)\n"
        }
        text += "\n" + String(repeating: "—", count: 40) + "\n\n"

        for message in transcript.messages {
            let role = message.role == "user" ? "You" : "Noah"
            text += "\(role): \(message.content)\n\n"
        }

        text += String(repeating: "—", count: 40) + "\n"
        text += "Exported from Noah AI Companion"
        return text
    }

    private func tagColor(_ tag: String) -> Color {
        switch tag {
        case "important": return .companionWarning
        case "memory_capture": return .companionInfo
        case "companion": return .companionPrimary
        case "reminder": return .companionSecondary
        case "concern_detected", "escalation": return .companionDanger
        default: return .companionTextSecondary
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: APIClient.TranscriptMessage

    var body: some View {
        HStack(alignment: .top, spacing: CompanionTheme.Spacing.sm) {
            Image(systemName: message.role == "user" ? "person.fill" : "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(message.role == "user" ? Color.companionPrimary : Color.companionSecondary)
                .frame(width: 20)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(message.role == "user" ? "You" : "Noah")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(message.role == "user" ? Color.companionPrimary : Color.companionSecondary)

                Text(message.content)
                    .font(.companionBodySecondary)
                    .foregroundStyle(Color.companionTextPrimary)
            }

            Spacer()
        }
        .padding(.vertical, CompanionTheme.Spacing.xs)
    }
}

// MARK: - Timeline Row

struct TimelineRow: View {
    let transcript: APIClient.TranscriptRecord
    let isLast: Bool

    private var date: Date {
        LegacyDateParser.parse(transcript.createdAt)
    }

    var body: some View {
        HStack(alignment: .top, spacing: CompanionTheme.Spacing.md) {
            // Timeline line + dot
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.companionPrimary)
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)

                if !isLast {
                    Rectangle()
                        .fill(Color.companionPrimary.opacity(0.3))
                        .frame(width: 2)
                }
            }
            .frame(width: 10)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute()))
                    .font(.companionCaption)
                    .foregroundStyle(Color.companionTextTertiary)

                if let summary = transcript.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.companionBodySecondary)
                        .foregroundStyle(Color.companionTextPrimary)
                        .lineLimit(2)
                } else if let firstAssistant = transcript.messages.first(where: { $0.role == "assistant" }) {
                    Text(firstAssistant.content)
                        .font(.companionBodySecondary)
                        .foregroundStyle(Color.companionTextPrimary)
                        .lineLimit(2)
                } else {
                    Text("Conversation (\(transcript.duration / 60)m)")
                        .font(.companionBodySecondary)
                        .foregroundStyle(Color.companionTextPrimary)
                }

                HStack(spacing: CompanionTheme.Spacing.sm) {
                    Label("\(transcript.messages.count) msgs", systemImage: "text.bubble")
                    Label("\(transcript.duration / 60)m", systemImage: "clock")
                }
                .font(.system(size: 11))
                .foregroundStyle(Color.companionTextTertiary)
            }
            .padding(.bottom, CompanionTheme.Spacing.lg)

            Spacer()
        }
    }
}

// MARK: - Date Parser

private enum LegacyDateParser {
    static func parse(_ string: String) -> Date {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f1.date(from: string) { return date }

        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        if let date = f2.date(from: string) { return date }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        if let date = df.date(from: string) { return date }

        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        df.timeZone = TimeZone(identifier: "UTC")
        if let date = df.date(from: string) { return date }

        return Date()
    }
}

#Preview {
    NavigationStack {
        LegacyArchiveView()
    }
}
