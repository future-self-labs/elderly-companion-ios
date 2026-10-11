import SwiftUI

/// Mood over 7, 30 or 90 days, with cognitive clarity.
struct MoodOverviewView: View {
    @EnvironmentObject private var session: CaregiverSession
    @State private var days = 30
    @State private var state: Loadable<MoodOverview> = .idle

    var body: some View {
        NoahScrollScreen {
            Picker("Periode", selection: $days) {
                Text("7 dagen").tag(7)
                Text("30 dagen").tag(30)
                Text("90 dagen").tag(90)
            }
            .pickerStyle(.segmented)
            .frame(minHeight: NoahSize.minTap)
            .noahCompactControlScaling()
            .accessibilityIdentifier("mood.period")

            LoadableView(state: state, retry: { Task { await load() } }) { overview in
                content(overview)
            }
        }
        .navigationTitle("Stemming")
        .task(id: "\(session.reloadKey.elderlyId ?? "")-\(days)-\(session.reloadKey.version)") { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func content(_ overview: MoodOverview) -> some View {
        let conversations = overview.days.compactMap(\.conversations).reduce(0, +)
        HStack(spacing: NoahSpacing.m) {
            NoahCard {
                NoahStat(value: overview.average.map { DutchFormat.decimal($0) } ?? "–", label: "gemiddeld")
                Text(verbatim: MoodText.label(overview.average))
                    .font(NoahFont.subheadline)
                    .foregroundColor(NoahColor.mood(overview.average))
            }
            NoahCard {
                Image(systemName: (overview.trend ?? .unknown).systemImage)
                    .font(NoahFont.title2).noahTitleScaling()
                    .foregroundColor(trendColor(overview.trend))
                    .accessibilityHidden(true)
                Text(verbatim: (overview.trend ?? .unknown).label)
                    .font(NoahFont.headline)
                    .foregroundColor(NoahColor.text)
                Text("trend")
                    .font(NoahFont.footnote)
                    .foregroundColor(NoahColor.textSecondary)
            }
            .accessibilityElement(children: .combine)
        }

        NoahCard {
            NoahEyebrow(text: "Stemming en helderheid per dag")
            if overview.days.allSatisfy({ $0.mood == nil }) {
                Text("In deze periode is nog geen stemming gemeten.")
                    .font(NoahFont.callout)
                    .foregroundColor(NoahColor.textSecondary)
            } else {
                MoodChart(points: overview.days, showsClarity: true, height: 220)
            }
        }

        NoahCard {
            NoahRow(icon: "bubble.left.and.bubble.right.fill", title: conversations == 1 ? "1 gesprek" : "\(conversations) gesprekken",
                    subtitle: "in de afgelopen \(days) dagen", showsChevron: false)
            Divider().overlay(NoahColor.divider)
            let silentDays = overview.days.filter { ($0.conversations ?? 0) == 0 }.count
            NoahRow(icon: "calendar.badge.exclamationmark", title: silentDays == 1 ? "1 dag zonder gesprek" : "\(silentDays) dagen zonder gesprek",
                    subtitle: nil, showsChevron: false)
        }

        Text("Na elk gesprek schat Noah de stemming en de helderheid in, op een schaal van 1 tot 5. Het is een signaal om op te letten, geen diagnose. Twijfel je, bespreek het dan met de huisarts.")
            .font(NoahFont.footnote)
            .foregroundColor(NoahColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func trendColor(_ trend: MoodTrend?) -> Color {
        switch trend {
        case .stijgend: return NoahColor.positive
        case .dalend: return NoahColor.danger
        default: return NoahColor.accent
        }
    }

    private func load() async {
        guard let id = session.selected?.id else { return }
        state = .loading
        do {
            state = .loaded(try await session.api.mood(elderlyId: id, days: days))
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled { state = .failed(apiError) }
        }
    }
}
