import SwiftUI

@Observable
final class AppState {
    var isOnboardingComplete: Bool = UserDefaults.standard.bool(forKey: "onboardingComplete")
    var currentUser: User?
    var isAuthenticated: Bool = KeychainService.authToken != nil

    func completeOnboarding() {
        isOnboardingComplete = true
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
    }

    func signOut() {
        currentUser = nil
        isAuthenticated = false
        isOnboardingComplete = false
        KeychainService.authToken = nil
        UserDefaults.standard.set(false, forKey: "onboardingComplete")
        UserDefaults.standard.removeObject(forKey: "userId")
        UserDefaults.standard.removeObject(forKey: "userPhoneNumber")
    }
}
