import SwiftUI

@main
struct HelloNoahApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppModel()

    init() {
        NoahAppearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(app.reachability)
                .environmentObject(app.subscriptions)
                .environmentObject(app.push)
                .preferredColorScheme(.dark)
                .tint(NoahColor.accent)
                .onOpenURL { app.handle(url: $0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { app.handle(url: url) }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ZStack {
            NoahColor.ground.ignoresSafeArea()
            switch app.mode {
            case .launching:
                LoadingStateView()
            case .welcome:
                WelcomeFlowView()
                    .transition(.opacity)
            case .elder:
                if let elder = app.elder {
                    ElderRootView()
                        .environmentObject(elder)
                        .transition(.opacity)
                }
            case .caregiver:
                if let caregiver = app.caregiver {
                    CaregiverRootView()
                        .environmentObject(caregiver)
                        .environmentObject(caregiver.router)
                        .transition(.opacity)
                }
            }
        }
        .animation(NoahMotion.standard, value: app.mode)
    }
}

/// Runs navigation changes after the first layout pass; pushing several screens from `onAppear`
/// directly can leave a NavigationStack blank on iOS 16/17.
@MainActor
func afterFirstLayout(_ action: @escaping @MainActor () -> Void) {
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 350_000_000)
        action()
    }
}

/// Debug/screenshot helper: `-uiRoute <name>` (mock mode in Debug builds only) opens a screen right after launch.
enum DebugRoute {
    static var requested: String? {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: AppConfig.mockArgumentKey) || UserDefaults.standard.bool(forKey: AppConfig.mockToggleKey) else { return nil }
        return UserDefaults.standard.string(forKey: "uiRoute")
        #else
        return nil
        #endif
    }

    private static var consumed = Set<String>()

    /// Returns the route once per launch for a given scope.
    static func take(scope: String) -> String? {
        guard let route = requested, !consumed.contains(scope) else { return nil }
        consumed.insert(scope)
        return route
    }
}
