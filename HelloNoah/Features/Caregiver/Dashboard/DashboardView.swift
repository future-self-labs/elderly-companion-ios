import SwiftUI

/// Dashboard home: latest summary, 7-day mood, open alerts, upcoming reminders, life story,
/// and "Laat Noah nu bellen".
struct DashboardView: View {
    @EnvironmentObject private var session: CaregiverSession
    @EnvironmentObject private var router: CaregiverRouter
    @EnvironmentObject private var push: PushManager
    @State private var state: Loadable<Dashboard> = .idle
    @State private var callResult: (text: String, isError: Bool)?
    @State private var callMode: ConversationMode = .gesprek
    @State private var subscription: Subscription?

    var body: some View {
        NoahScrollScreen {
            if let selected = session.selected {
                VStack(alignment: .leading, spacing: NoahSpacing.xxs) {
                    Text(session.firstName.isEmpty ? "Hoi!" : "Hoi \(session.firstName)")
                        .font(NoahFont.subheadline)
                        .foregroundColor(NoahColor.textSecondary)
                    Text("Zo gaat het met \(selected.preferredName)")
                        .font(NoahFont.largeTitle).noahTitleScaling()
                        .foregroundColor(NoahColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }

                if selected.access == .inactive {
                    InactiveNotice(elderly: selected)
                } else if let subscription, !subscription.isPaidOrBeta, session.permissions.canManageSubscription {
                    let free = subscription.freeConversationsLeft ?? 0
                    NoahNotice(kind: .info,
                               text: free == 1 ? "Proefperiode: \(selected.preferredName) kan nog 1 gratis gesprek voeren. Start het \(Plan.displayName) om daarna door te praten." : "Proefperiode: \(selected.preferredName) kan nog \(free) gratis gesprekken voeren. Start het \(Plan.displayName) om daarna door te praten.",
                               actionTitle: "Abonnement starten") {
                        router.present(.paywall(elderlyId: selected.id))
                    }
                }

                LoadableView(state: state, retry: { Task { await load() } }) { dashboard in
                    content(dashboard, selected: selected)
                }
            } else {
                NoElderlySelectedView()
            }
        }
        .navigationTitle("Overzicht")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { ElderlySwitcher() }
        }
        .refreshable { await load() }
        .task(id: session.reloadKey) { await load() }
    }

    @ViewBuilder
    private func content(_ dashboard: Dashboard, selected: ElderlySummary) -> some View {
        if !dashboard.openAlerts.isEmpty {
            VStack(alignment: .leading, spacing: NoahSpacing.s) {
                NoahSectionHeader(title: "Meldingen", actionTitle: "Alles") { router.show(.alerts, in: .overview) }
                ForEach(dashboard.openAlerts.sorted { $0.severity.rank > $1.severity.rank }) { alert in
                    NavigationLink(value: CaregiverRoute.alert(id: alert.id)) {
                        AlertCard(alert: alert)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        latestConversation(dashboard)

        NoahCard {
            NoahEyebrow(text: "Afgelopen 7 dagen")
            HStack(alignment: .top, spacing: NoahSpacing.m) {
                NoahStat(value: String(dashboard.week.conversations), label: "gesprekken")
                NoahStat(value: String(dashboard.week.minutes), label: "minuten")
                NoahStat(value: dashboard.week.averageMood.map { DutchFormat.decimal($0) } ?? "–", label: "gem. stemming")
            }
        }

        NavigationLink(value: CaregiverRoute.mood) {
            NoahCard {
                HStack {
                    NoahEyebrow(text: "Stemming deze week")
                    Spacer()
                    Text("Meer")
                        .font(NoahFont.subheadline)
                        .foregroundColor(NoahColor.accent)
                    Image(systemName: "chevron.right")
                        .font(NoahFont.caption)
                        .foregroundColor(NoahColor.accent)
                        .accessibilityHidden(true)
                }
                if dashboard.moodTrend.allSatisfy({ $0.mood == nil }) {
                    Text("Nog geen stemming gemeten deze week.")
                        .font(NoahFont.callout)
                        .foregroundColor(NoahColor.textSecondary)
                } else {
                    MoodChart(points: dashboard.moodTrend, height: 150)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opent het stemmingsoverzicht"))

        if push.authorization == .notDetermined, !session.pushPromptDismissed {
            PushPromptCard(name: selected.preferredName)
        }

        upcomingReminders(dashboard)

        Button {
            router.tab = .lifeStory
        } label: {
            NoahCard {
                NoahEyebrow(text: "Levensverhaal")
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: "\(dashboard.lifeStory.entries)")
                        .font(NoahFont.statNumber).noahTitleScaling()
                        .foregroundColor(NoahColor.text)
                    Text(dashboard.lifeStory.entries == 1 ? "herinnering bewaard" : "herinneringen bewaard")
                        .font(NoahFont.callout)
                        .foregroundColor(NoahColor.textSecondary)
                }
                if let latest = dashboard.lifeStory.latest {
                    Text("Nieuwste: \(latest.title)")
                        .font(NoahFont.callout)
                        .foregroundColor(NoahColor.textSoft)
                        .lineLimit(2)
                }
            }
        }
        .buttonStyle(.plain)

        if session.permissions.canCallNow {
            callNowCard(name: selected.preferredName)
        }
    }

    @ViewBuilder
    private func latestConversation(_ dashboard: Dashboard) -> some View {
        if let conversation = dashboard.latestConversation {
            NavigationLink(value: CaregiverRoute.conversation(id: conversation.id)) {
                NoahCard {
                    HStack {
                        NoahEyebrow(text: "Laatste gesprek")
                        Spacer()
                        NoahMoodBadge(score: conversation.moodScore)
                    }
                    Text(verbatim: "\(DutchFormat.dayAndTime(conversation.startedAt).capitalizedFirst) · \(DutchFormat.duration(seconds: conversation.durationSeconds)) · \(conversation.channel.label)")
                        .font(NoahFont.footnote)
                        .foregroundColor(NoahColor.textSecondary)
                    if let summary = conversation.summary {
                        Text(verbatim: summary)
                            .font(NoahFont.bodyText)
                            .foregroundColor(NoahColor.text)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !conversation.topics.isEmpty {
                        NoahChipList(items: conversation.topics)
                    }
                    if conversation.hasConcern {
                        Label("Noah merkte iets op", systemImage: "exclamationmark.triangle.fill")
                            .font(NoahFont.subheadline)
                            .foregroundColor(NoahColor.accent)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dashboard.latestConversation")
        } else {
            NoahCard {
                NoahEyebrow(text: "Laatste gesprek")
                Text("Nog geen gesprekken. Na het eerste gesprek met Noah zie je hier een korte samenvatting.")
                    .font(NoahFont.callout)
                    .foregroundColor(NoahColor.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func upcomingReminders(_ dashboard: Dashboard) -> some View {
        VStack(alignment: .leading, spacing: NoahSpacing.s) {
            NoahSectionHeader(title: "Binnenkort", actionTitle: "Alle herinneringen") { router.tab = .reminders }
            if dashboard.upcomingReminders.isEmpty {
                NoahCard {
                    Text("Geen herinneringen gepland.")
                        .font(NoahFont.callout)
                        .foregroundColor(NoahColor.textSecondary)
                }
            } else {
                NoahCard(padding: NoahSpacing.s) {
                    ForEach(Array(dashboard.upcomingReminders.enumerated()), id: \.element.id) { index, reminder in
                        if index > 0 { Divider().overlay(NoahColor.divider) }
                        NoahRow(icon: reminder.type.systemImage, title: reminder.title,
                                subtitle: reminder.nextAt.map { DutchFormat.upcoming($0) },
                                value: reminder.delivery.shortLabel, showsChevron: false)
                    }
                }
            }
        }
    }

    private func callNowCard(name: String) -> some View {
        NoahCard {
            NoahEyebrow(text: "Even contact")
            Text("Laat Noah \(name) nu bellen, bijvoorbeeld als je weet dat het een stille dag is.")
                .font(NoahFont.callout)
                .foregroundColor(NoahColor.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: NoahSpacing.s) {
                NoahOptionCard(title: ConversationMode.gesprek.label, subtitle: "Een praatje over de dag.",
                               isSelected: callMode == .gesprek) { callMode = .gesprek }
                NoahOptionCard(title: ConversationMode.levensverhaal.label, subtitle: "Noah vraagt naar herinneringen van vroeger, voor het levensverhaal.",
                               isSelected: callMode == .levensverhaal) { callMode = .levensverhaal }
                    .accessibilityIdentifier("dashboard.callStory")
            }
            NoahAsyncButton(kind: .primary, action: callNow) {
                NoahButtonLabel(title: "Laat Noah nu bellen", systemImage: "phone.arrow.up.right.fill")
            }
            .accessibilityIdentifier("dashboard.callNow")
            if let callResult {
                NoahNotice(kind: callResult.isError ? .warning : .success, text: callResult.text)
            }
        }
    }

    // MARK: Data

    private func load() async {
        guard let id = session.selected?.id else { return }
        if state.value == nil || state.value?.elderly.id != id { state = .loading }
        if session.permissions.canViewSubscription {
            subscription = try? await session.api.subscription(elderlyId: id)
        } else {
            subscription = nil
        }
        do {
            state = .loaded(try await session.api.dashboard(elderlyId: id))
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled, state.value == nil || state.value?.elderly.id != id { state = .failed(apiError) }
        }
    }

    private func callNow() async {
        guard let selected = session.selected else { return }
        do {
            let response = try await session.api.callNow(elderlyId: selected.id, mode: callMode)
            var text = callMode == .levensverhaal
                ? "Noah belt \(selected.preferredName) nu voor een verhaal-gesprek. Mooie herinneringen komen daarna in het levensverhaal."
                : "Noah belt \(selected.preferredName) nu. Na het gesprek zie je hier de samenvatting."
            if response.recording == true {
                text += " Noah vraagt eerst of het gesprek opgenomen mag worden."
            }
            callResult = (text, false)
        } catch {
            callResult = (APIError.from(error).userMessage, true)
        }
    }
}

/// Banner for an inactive profile: start the subscription (beheerder) or ask the beheerder.
struct InactiveNotice: View {
    let elderly: ElderlySummary
    @EnvironmentObject private var router: CaregiverRouter

    var body: some View {
        if elderly.role == .beheerder {
            NoahNotice(kind: .warning,
                       text: "Noah is nog niet actief voor \(elderly.preferredName). Start het abonnement, dan kan \(elderly.preferredName) meteen met Noah praten en werkt het telefoonnummer.",
                       actionTitle: "Abonnement starten") {
                router.present(.paywall(elderlyId: elderly.id))
            }
        } else {
            NoahNotice(kind: .warning, text: "Noah is nog niet actief voor \(elderly.preferredName). De beheerder kan het abonnement starten.")
        }
    }
}

/// Explains why notifications matter before iOS asks.
struct PushPromptCard: View {
    let name: String
    @EnvironmentObject private var session: CaregiverSession
    @EnvironmentObject private var push: PushManager

    var body: some View {
        NoahCard {
            Label("Meldingen aanzetten?", systemImage: "bell.badge.fill")
                .font(NoahFont.headline)
                .foregroundColor(NoahColor.text)
            Text("Krijg een seintje als Noah zich zorgen maakt over \(name), of als \(name) om hulp vraagt. Je krijgt geen reclame.")
                .font(NoahFont.callout)
                .foregroundColor(NoahColor.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: NoahSpacing.s) {
                NoahAsyncButton("Meldingen aanzetten", size: .compact) {
                    await push.requestAuthorization()
                    session.pushPromptDismissed = true
                }
                Button("Later") { session.pushPromptDismissed = true }
                    .buttonStyle(.noah(.quiet, size: .compact, fullWidth: false))
            }
        }
    }
}
