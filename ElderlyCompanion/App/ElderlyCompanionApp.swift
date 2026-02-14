import SwiftUI

@main
struct ElderlyCompanionApp: App {
    @State private var appState = AppState()
    @State private var themeManager = ThemeManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(themeManager)
        }
    }
}
