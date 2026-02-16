import SwiftUI

@Observable
final class OutreachLogViewModel {
    var events: [APIClient.CareEventRecord] = []
    var isLoading = false

    func load() async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        isLoading = true
        do {
            events = try await APIClient.shared.getCareEvents(elderlyUserId: userId)
            await MainActor.run { isLoading = false }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }

    func resolve(id: String, outcome: String) {
        Task {
            do {
                try await APIClient.shared.resolveCareEvent(id: id, outcome: outcome)
                await MainActor.run {
                    if let idx = events.firstIndex(where: { $0.id == id }) {
                        // Refresh
                        Task { await load() }
                    }
                }
            } catch { print("[OutreachLog] Resolve error: \(error)") }
        }
    }
}

struct OutreachLogView: View {
    @State private var vm = OutreachLogViewModel()

    var body: some View {
        Group {
            if vm.isLoading {
                VStack { Spacer(); ProgressView().tint(Color.companionPrimary); Spacer() }
            } else if vm.events.isEmpty {
                VStack(spacing: CompanionTheme.Spacing.lg) {
                    Spacer()
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.companionSuccess)
                    VStack(spacing: CompanionTheme.Spacing.sm) {
                        Text("All clear")
                            .font(.companionHeadline)
                            .foregroundStyle(Color.companionTextPrimary)
                        Text("No care events have been logged yet. When Noah detects a concern, it will appear here.")
                            .font(.companionBody)
                            .foregroundStyle(Color.companionTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, CompanionTheme.Spacing.xl)
                    }
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: CompanionTheme.Spacing.md) {
                        ForEach(vm.events) { event in
                            CareEventRow(event: event, onResolve: { outcome in
                                vm.resolve(id: event.id, outcome: outcome)
                            })
                        }
                    }
                    .padding(CompanionTheme.Spacing.lg)
                }
            }
        }
        .background(Color.companionBackground)
        .navigationTitle("Outreach Log")
        .navigationBarTitleDisplayMode(.large)
        .task { await vm.load() }
    }
}

struct CareEventRow: View {
    let event: APIClient.CareEventRecord
    let onResolve: (String) -> Void

    var body: some View {
        CalmCard {
            VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                HStack {
                    Image(systemName: categoryIcon)
                        .foregroundStyle(categoryColor)
                    Text(categoryLabel)
                        .font(.companionBody)
                        .foregroundStyle(Color.companionTextPrimary)
                    Spacer()
                    TagBadge(text: "L\(event.escalationLayer)", color: layerColor)
                    TagBadge(text: event.outcome.capitalized, color: outcomeColor)
                }

                if let desc = event.description {
                    Text(desc)
                        .font(.companionBodySecondary)
                        .foregroundStyle(Color.companionTextSecondary)
                }

                if let action = event.aiAction {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                        Text(action)
                            .font(.companionCaption)
                    }
                    .foregroundStyle(Color.companionTextTertiary)
                }

                HStack {
                    Text(event.createdAt.prefix(16).replacingOccurrences(of: "T", with: " "))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.companionTextTertiary)

                    Spacer()

                    if event.outcome == "pending" {
                        Button("Resolved") { onResolve("resolved") }
                            .font(.companionLabel)
                            .foregroundStyle(Color.companionSuccess)
                        Text("·").foregroundStyle(Color.companionTextTertiary)
                        Button("False alarm") { onResolve("false_alarm") }
                            .font(.companionLabel)
                            .foregroundStyle(Color.companionWarning)
                    }
                }
            }
        }
    }

    private var categoryIcon: String {
        switch event.triggerCategory {
        case "cognitive_drift": return "brain.head.profile"
        case "emotional": return "heart.fill"
        case "scam": return "exclamationmark.shield.fill"
        case "silence": return "zzz"
        case "medication": return "pills.fill"
        case "help_request": return "sos"
        case "environmental": return "location.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private var categoryLabel: String {
        switch event.triggerCategory {
        case "cognitive_drift": return "Cognitive Concern"
        case "emotional": return "Emotional Concern"
        case "scam": return "Scam Alert"
        case "silence": return "Silence Alert"
        case "medication": return "Medication"
        case "help_request": return "Help Request"
        case "environmental": return "Environment"
        default: return event.triggerCategory
        }
    }

    private var categoryColor: Color {
        switch event.triggerCategory {
        case "scam", "help_request": return .companionDanger
        case "emotional": return .companionWarning
        case "silence": return .companionInfo
        default: return .companionSecondary
        }
    }

    private var layerColor: Color {
        switch event.escalationLayer {
        case 0: return .companionTextTertiary
        case 1: return .companionInfo
        case 2: return .companionWarning
        case 3, 4: return .companionDanger
        default: return .companionTextTertiary
        }
    }

    private var outcomeColor: Color {
        switch event.outcome {
        case "resolved": return .companionSuccess
        case "false_alarm": return .companionTextTertiary
        case "escalated": return .companionDanger
        default: return .companionWarning
        }
    }
}
