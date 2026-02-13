import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isOnboardingComplete {
                MainTabView()
            } else {
                OnboardingContainerView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.isOnboardingComplete)
    }
}
