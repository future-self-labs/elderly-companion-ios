import SwiftUI

struct CallHistoryView: View {
    @State private var viewModel = CallHistoryViewModel()

    var body: some View {
        Group {
            if viewModel.calls.isEmpty && !viewModel.isLoading {
                emptyState
            } else {
                callList
            }
        }
        .background(Color.companionBackground)
        .navigationTitle("Call History")
        .navigationBarTitleDisplayMode(.large)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "Could not load call history.")
        }
        .task {
            await viewModel.loadCalls()
        }
    }

    // MARK: - Call List

    private var callList: some View {
        ScrollView {
            LazyVStack(spacing: CompanionTheme.Spacing.md) {
                ForEach(viewModel.calls) { call in
                    CallRow(call: call)
                }
            }
            .padding(CompanionTheme.Spacing.lg)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: CompanionTheme.Spacing.lg) {
            Spacer()

            Image(systemName: "phone.badge.checkmark")
                .font(.system(size: 48))
                .foregroundStyle(Color.companionTextTertiary)

            VStack(spacing: CompanionTheme.Spacing.sm) {
                Text("No calls yet")
                    .font(.companionHeadline)
                    .foregroundStyle(Color.companionTextPrimary)

                Text("Your call history with Noah will appear here.")
                    .font(.companionBody)
                    .foregroundStyle(Color.companionTextSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(CompanionTheme.Spacing.lg)
    }
}

// MARK: - Call Row

struct CallRow: View {
    let call: CallRecord

    var body: some View {
        CalmCard {
            VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                // Header
                HStack {
                    Image(systemName: call.direction == .inbound ? "phone.arrow.down.left.fill" : "phone.arrow.up.right.fill")
                        .foregroundStyle(call.direction == .inbound ? Color.companionPrimary : Color.companionSecondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(call.direction == .inbound ? "Incoming call" : "Outgoing call")
                            .font(.companionBody)
                            .foregroundStyle(Color.companionTextPrimary)

                        Text(call.startedAt.formatted(.dateTime.month().day().hour().minute()))
                            .font(.companionCaption)
                            .foregroundStyle(Color.companionTextSecondary)
                    }

                    Spacer()

                    Text(formatDuration(call.duration))
                        .font(.companionLabel)
                        .foregroundStyle(Color.companionTextSecondary)
                }

                // Tags
                if !call.tags.isEmpty {
                    HStack(spacing: CompanionTheme.Spacing.sm) {
                        ForEach(call.tags, id: \.self) { tag in
                            TagBadge(text: tag.label, color: tagColor(for: tag))
                        }
                    }
                }

                // Summary
                if let summary = call.summary {
                    Text(summary)
                        .font(.companionCaption)
                        .foregroundStyle(Color.companionTextSecondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    private func tagColor(for tag: CallTag) -> Color {
        switch tag {
        case .companion: return .companionPrimary
        case .reminder: return .companionSecondary
        case .memoryCapture: return .companionInfo
        case .concernDetected: return .companionDanger
        case .escalation: return .companionDanger
        }
    }
}
