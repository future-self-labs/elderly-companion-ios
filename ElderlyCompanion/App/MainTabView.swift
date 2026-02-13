import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Tab = .home

    enum Tab: String, CaseIterable {
        case home
        case calendar
        case legacy
        case settings

        var title: String {
            switch self {
            case .home: return "Home"
            case .calendar: return "Calendar"
            case .legacy: return "Memories"
            case .settings: return "Settings"
            }
        }

        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .calendar: return "calendar"
            case .legacy: return "book.fill"
            case .settings: return "gear"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(Tab.allCases, id: \.self) { tab in
                tabContent(for: tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.icon)
                    }
                    .tag(tab)
            }
        }
        .tint(Color.companionPrimary)
    }

    @ViewBuilder
    private func tabContent(for tab: Tab) -> some View {
        switch tab {
        case .home:
            NavigationStack {
                HomeView()
            }
        case .calendar:
            NavigationStack {
                CompanionCalendarView()
            }
        case .legacy:
            NavigationStack {
                LegacyArchiveView()
            }
        case .settings:
            NavigationStack {
                SettingsHubView()
            }
        }
    }
}

#Preview {
    MainTabView()
        .environment(AppState())
}
