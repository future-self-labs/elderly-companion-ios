import SwiftUI

@Observable
final class AppState {
    var isOnboardingComplete: Bool = UserDefaults.standard.bool(forKey: "onboardingComplete")
    var currentUser: User?
    var isAuthenticated: Bool = false

    func completeOnboarding() {
        isOnboardingComplete = true
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
    }

    func signOut() {
        currentUser = nil
        isAuthenticated = false
        isOnboardingComplete = false
        UserDefaults.standard.set(false, forKey: "onboardingComplete")
        UserDefaults.standard.removeObject(forKey: "userId")
        UserDefaults.standard.removeObject(forKey: "authToken")
    }
}
