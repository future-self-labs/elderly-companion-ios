import SwiftUI

/// Caregiver interface: tab bar with dashboard, conversations, life story, reminders and more.
struct CaregiverRootView: View {
    @EnvironmentObject private var session: CaregiverSession
    @EnvironmentObject private var router: CaregiverRouter
    @EnvironmentObject private var reachability: Reachability
    @EnvironmentObject private var app: AppModel

    var body: some View {
        Group {
            if session.me == nil {
                if let error = session.meError {
                    ErrorStateView(message: error.userMessage, isOffline: error.isOffline) {
                        Task { await session.reloadMe() }
                    }
                    .frame(maxHeight: .infinity)
                    .noahScreenBackground()
                } else {
                    LoadingStateView(message: "Je gegevens worden geladen…")
                        .frame(maxHeight: .infinity)
                        .noahScreenBackground()
                }
            } else if session.needsOnboarding {
                NavigationStack { CaregiverStartView() }
            } else {
                tabs
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !reachability.isOnline { OfflineBanner() }
        }
        .task { if session.me == nil, !session.isLoadingMe { await session.reloadMe() } }
        .onChange(of: reachability.isOnline) { online in
            if online { Task { await session.reloadMe() } }
        }
        .fullScreenCover(item: wizardBinding) { _ in
            ProfileWizardView(api: session.api)
                .environmentObject(session)
                .environmentObject(router)
        }
        .sheet(item: sheetBinding) { sheet in
            switch sheet {
            case .paywall(let elderlyId):
                NavigationStack {
                    PaywallView(elderlyId: elderlyId, onDone: { router.sheet = nil })
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Sluiten") { router.sheet = nil } }
                        }
                }
                .environmentObject(session)
            case .acceptInvitation(let code):
                NavigationStack { AcceptInvitationView(initialCode: code) }
                    .environmentObject(session)
            case .wizard:
                EmptyView()
            }
        }
        .onAppear { afterFirstLayout(applyDebugRoute) }
        .onChange(of: session.me?.elderly.count) { _ in afterFirstLayout(applyDebugRoute) }
    }

    private var wizardBinding: Binding<CaregiverSheet?> {
        Binding(
            get: { router.sheet == .wizard ? .wizard : nil },
            set: { if $0 == nil, router.sheet == .wizard { router.sheet = nil } }
        )
    }

    private var sheetBinding: Binding<CaregiverSheet?> {
        Binding(
            get: { router.sheet == .wizard ? nil : router.sheet },
            set: { newValue in if router.sheet != .wizard { router.sheet = newValue } }
        )
    }

    private var tabs: some View {
        TabView(selection: $router.tab) {
            NavigationStack(path: $router.overviewPath) {
                DashboardView()
                    .hidesWhileCovered(ownDepth: 0, stackDepth: router.overviewPath.count)
                    .caregiverDestinations()
            }
            .tabItem { Label("Overzicht", systemImage: "house.fill") }
            .tag(CaregiverTab.overview)

            NavigationStack(path: $router.conversationsPath) {
                ConversationListView()
                    .hidesWhileCovered(ownDepth: 0, stackDepth: router.conversationsPath.count)
                    .caregiverDestinations()
            }
            .tabItem { Label("Gesprekken", systemImage: "bubble.left.and.bubble.right.fill") }
            .tag(CaregiverTab.conversations)

            NavigationStack(path: $router.lifeStoryPath) {
                LifeStoryListView()
                    .hidesWhileCovered(ownDepth: 0, stackDepth: router.lifeStoryPath.count)
                    .caregiverDestinations()
            }
            .tabItem { Label("Verhaal", systemImage: "book.fill") }
            .tag(CaregiverTab.lifeStory)

            NavigationStack(path: $router.remindersPath) {
                RemindersListView()
                    .hidesWhileCovered(ownDepth: 0, stackDepth: router.remindersPath.count)
                    .caregiverDestinations()
            }
            .tabItem { Label("Herinneringen", systemImage: "bell.fill") }
            .tag(CaregiverTab.reminders)

            NavigationStack(path: $router.morePath) {
                MoreView()
                    .hidesWhileCovered(ownDepth: 0, stackDepth: router.morePath.count)
                    .caregiverDestinations()
            }
            .tabItem { Label("Meer", systemImage: "ellipsis.circle.fill") }
            .tag(CaregiverTab.more)
        }
    }

    /// `-uiRoute <name>` in mock mode, for screenshots and quick testing.
    private func applyDebugRoute() {
        guard session.me != nil, let route = DebugRoute.take(scope: "caregiver") else { return }
        if let wim = session.elderly.first(where: { $0.id == MockIDs.wim }) { session.select(wim.id) }
        switch route {
        case "dashboard": router.tab = .overview
        case "conversations": router.tab = .conversations
        case "conversationDetail": router.show(.conversation(id: "C0A1B2C3-0000-4000-8000-000000000001"), in: .conversations)
        case "storyConversationDetail": router.show(.conversation(id: "C0A1B2C3-0000-4000-8000-000000000006"), in: .conversations)
        case "lifeStory": router.tab = .lifeStory
        case "lifeStoryEntry": router.show(.lifeStoryEntry(MockData.wimLifeStory(now: Date())[2]), in: .lifeStory)
        case "reminders": router.tab = .reminders
        case "mood": router.show(.mood, in: .overview)
        case "alerts": router.show(.alerts, in: .overview)
        case "alertDetail": router.show(.alert(id: "A01"), in: .overview)
        case "more": router.tab = .more
        case "noahSettings": router.show(.noahSettings, in: .more)
        case "profile": router.show(.profile, in: .more)
        case "people": router.show(.people, in: .more)
        case "emergencyContacts": router.show(.emergencyContacts, in: .more)
        case "phoneLine": router.show(.phoneLine, in: .more)
        case "caregivers": router.show(.caregivers, in: .more)
        case "devices": router.show(.devices, in: .more)
        case "pairDevice": router.show(.pairDevice, in: .more)
        case "subscription": router.show(.subscription, in: .more)
        case "account": router.show(.account, in: .more)
        case "elderlyList": router.show(.elderlyList, in: .more)
        case "paywall": router.present(.paywall(elderlyId: MockIDs.wim))
        case "wizard": router.present(.wizard)
        case "acceptInvite": router.present(.acceptInvitation(code: nil))
        case "riet":
            if let riet = session.elderly.first(where: { $0.id == MockIDs.riet }) { session.select(riet.id) }
        default: break
        }
    }
}

// MARK: - Destinations

extension View {
    func caregiverDestinations() -> some View {
        navigationDestination(for: CaregiverRoute.self) { route in
            CaregiverDestinationView(route: route)
                .noahPushedScreen()
        }
    }
}

struct CaregiverDestinationView: View {
    let route: CaregiverRoute

    var body: some View {
        switch route {
        case .conversation(let id): ConversationDetailView(conversationId: id)
        case .alerts: AlertsListView()
        case .alert(let id): AlertDetailView(alertId: id)
        case .mood: MoodOverviewView()
        case .lifeStoryEntry(let entry): LifeStoryEntryView(entry: entry)
        case .noahSettings: NoahSettingsView()
        case .profile: ElderlyProfileView()
        case .people: PeopleView()
        case .emergencyContacts: EmergencyContactsView()
        case .phoneLine: PhoneLineView()
        case .caregivers: CaregiversView()
        case .devices: DevicesView()
        case .pairDevice: PairDeviceView()
        case .subscription: SubscriptionView()
        case .account: AccountView()
        case .elderlyList: ElderlyListView()
        }
    }
}

// MARK: - Shared caregiver pieces

/// Reload trigger for screens that depend on the selected person and on edits elsewhere.
struct ReloadKey: Equatable {
    let elderlyId: String?
    let version: Int
}

extension CaregiverSession {
    var reloadKey: ReloadKey { ReloadKey(elderlyId: selected?.id, version: dataVersion) }
}

/// Toolbar menu to switch between older people.
struct ElderlySwitcher: View {
    @EnvironmentObject private var session: CaregiverSession
    @EnvironmentObject private var router: CaregiverRouter

    var body: some View {
        Menu {
            ForEach(session.elderly) { person in
                Button {
                    session.select(person.id)
                } label: {
                    if person.id == session.selected?.id {
                        Label(person.preferredName, systemImage: "checkmark")
                    } else {
                        Text(verbatim: person.preferredName)
                    }
                }
            }
            Divider()
            Button {
                router.present(.wizard)
            } label: {
                Label("Nieuw profiel toevoegen", systemImage: "plus")
            }
            Button {
                router.present(.acceptInvitation(code: nil))
            } label: {
                Label("Uitnodigingscode invullen", systemImage: "envelope.open")
            }
        } label: {
            HStack(spacing: NoahSpacing.xxs) {
                Text(verbatim: session.selected?.preferredName ?? "")
                    .font(NoahFont.bodyStrong)
                Image(systemName: "chevron.down")
                    .font(NoahFont.caption)
            }
            .foregroundColor(NoahColor.accent)
            .frame(minHeight: NoahSize.minTap)
        }
        .accessibilityLabel(Text("Kies naaste, nu \(session.selected?.preferredName ?? "")"))
        .accessibilityIdentifier("caregiver.switcher")
    }
}

/// Shown on edit screens for a "lezer".
struct ReadOnlyNotice: View {
    var body: some View {
        NoahNotice(kind: .info, text: "Je kijkt mee als lezer. Alleen een beheerder kan dit aanpassen.")
    }
}

/// Placeholder when no older person is selected (should be rare).
struct NoElderlySelectedView: View {
    @EnvironmentObject private var router: CaregiverRouter

    var body: some View {
        EmptyStateView(systemImage: "person.crop.circle.badge.plus", title: "Nog niemand toegevoegd",
                       message: "Voeg eerst je naaste toe, dan zie je hier hoe het gaat.",
                       actionTitle: "Profiel toevoegen") { router.present(.wizard) }
    }
}
