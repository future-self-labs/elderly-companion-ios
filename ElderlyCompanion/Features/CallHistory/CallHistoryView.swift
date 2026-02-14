import SwiftUI

struct CallHistoryView: View {
    @State private var viewModel = CallHistoryViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                        .tint(Color.companionPrimary)
                    Text("Loading calls...")
                        .font(.companionCaption)
                        .foregroundStyle(Color.companionTextSecondary)
                        .padding(.top, CompanionTheme.Spacing.sm)
                    Spacer()
                }
            } else if viewModel.calls.isEmpty {
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
            HStack(spacing: CompanionTheme.Spacing.md) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.companionPrimaryLight)
                        .frame(width: 44, height: 44)

                    Image(systemName: "waveform")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.companionPrimary)
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text("Conversation with Noah")
                        .font(.companionBody)
                        .foregroundStyle(Color.companionTextPrimary)

                    Text(call.startedAt.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
                        .font(.companionCaption)
                        .foregroundStyle(Color.companionTextSecondary)

                    if let summary = call.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.companionCaption)
                            .foregroundStyle(Color.companionTextTertiary)
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                }

                Spacer()

                // Duration
                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatDuration(call.duration))
                        .font(.companionLabel)
                        .foregroundStyle(Color.companionTextSecondary)

                    if !call.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(call.tags.prefix(2), id: \.self) { tag in
                                Text(tag.label)
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(tagColor(for: tag).opacity(0.15))
                                    .foregroundStyle(tagColor(for: tag))
                                    .clipShape(Capsule())
                            }
                        }
                    }
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
