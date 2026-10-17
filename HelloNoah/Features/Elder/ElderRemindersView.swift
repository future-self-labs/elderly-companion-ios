import SwiftUI

/// "Herinneringen": upcoming reminders, read-only.
struct ElderRemindersView: View {
    @EnvironmentObject private var session: ElderSession
    @State private var state: Loadable<[Reminder]> = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoahSpacing.l) {
                ElderBackButton()
                Text("Herinneringen")
                    .font(NoahFont.Elder.hero).noahElderTitleScaling()
                    .foregroundColor(NoahColor.text)
                    .accessibilityAddTraits(.isHeader)

                // A memory aid next to what the person already uses, never a replacement.
                Text(verbatim: ProductCopy.elderReminderNote)
                    .font(NoahFont.Elder.label)
                    .foregroundColor(NoahColor.textSoft)
                    .fixedSize(horizontal: false, vertical: true)

                LoadableView(state: state, large: true, retry: { Task { await load() } }) { reminders in
                    if reminders.isEmpty {
                        EmptyStateView(
                            systemImage: "bell.slash.fill",
                            title: "Geen herinneringen",
                            message: "Er staan nu geen herinneringen klaar. U kunt Noah vragen om u ergens aan te herinneren.",
                            large: true
                        )
                    } else {
                        ForEach(reminders) { reminder in
                            ElderReminderCard(reminder: reminder)
                        }
                    }
                }
            }
            .padding(.horizontal, NoahSpacing.screen)
            .padding(.vertical, NoahSpacing.m)
            .noahReadableWidth()
        }
        .elderSubscreen()
        .task { if state.value == nil { await load() } }
        .refreshable { await load() }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            let reminders = try await session.api.deviceReminders()
            state = .loaded(reminders.filter(\.active).sorted { ($0.nextAt ?? .distantFuture) < ($1.nextAt ?? .distantFuture) })
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled { state = .failed(apiError) }
        }
    }
}

struct ElderReminderCard: View {
    let reminder: Reminder

    var body: some View {
        AdaptiveStack(spacing: NoahSpacing.m) {
            NoahIconBadge(systemName: reminder.type.systemImage, size: 56)
            VStack(alignment: .leading, spacing: NoahSpacing.xs) {
                Text(verbatim: reminder.title)
                    .font(NoahFont.Elder.bodyStrong)
                    .foregroundColor(NoahColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let next = reminder.nextAt {
                    Text(verbatim: DutchFormat.upcoming(next))
                        .font(NoahFont.Elder.body)
                        .foregroundColor(NoahColor.accent)
                }
                Text(verbatim: ScheduleFormatter.describe(reminder.schedule))
                    .font(NoahFont.Elder.label)
                    .foregroundColor(NoahColor.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if let notes = reminder.notes, !notes.isEmpty {
                    Text(verbatim: notes)
                        .font(NoahFont.Elder.label)
                        .foregroundColor(NoahColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(NoahSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoahRadius.large, style: .continuous).fill(NoahColor.surface))
        .overlay(RoundedRectangle(cornerRadius: NoahRadius.large, style: .continuous).strokeBorder(NoahColor.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
