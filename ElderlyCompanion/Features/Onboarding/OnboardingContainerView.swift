import SwiftUI

struct OnboardingContainerView: View {
    @Environment(AppState.self) private var appState
    @State private var currentStep: OnboardingStep = .welcome
    @State private var profile = UserProfile()
    @State private var authService = AuthService()

    enum OnboardingStep: Int, CaseIterable {
        case welcome
        case profile
        case phoneVerification
        case calendarPermission
        case notificationPreferences
        case legacyPreferences
        case complete
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            if currentStep != .welcome && currentStep != .complete {
                ProgressView(value: progressValue)
                    .tint(Color.companionPrimary)
                    .padding(.horizontal, CompanionTheme.Spacing.lg)
                    .padding(.top, CompanionTheme.Spacing.md)
            }

            // Content
            Group {
                switch currentStep {
                case .welcome:
                    WelcomeView(onContinue: { advanceStep() })

                case .profile:
                    ProfileCreationView(profile: $profile, onContinue: { advanceStep() })

                case .phoneVerification:
                    PhoneVerificationView(
                        phoneNumber: profile.phoneNumber,
                        authService: authService,
                        onVerified: { userId in
                            UserDefaults.standard.set(userId, forKey: "userId")
                            advanceStep()
                        }
                    )

                case .calendarPermission:
                    CalendarPermissionView(
                        selectedAccess: $profile.calendarAccess,
                        onContinue: { advanceStep() }
                    )

                case .notificationPreferences:
                    NotificationPreferencesView(
                        preferences: $profile.notificationPreferences,
                        onContinue: { advanceStep() }
                    )

                case .legacyPreferences:
                    LegacyPreferencesView(
                        preferences: $profile.legacyPreferences,
                        onContinue: { advanceStep() }
                    )

                case .complete:
                    EmptyView()
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
        .background(Color.companionBackground)
        .animation(.easeInOut(duration: 0.3), value: currentStep)
    }

    private var progressValue: Double {
        let totalSteps = OnboardingStep.allCases.count - 2 // exclude welcome and complete
        let currentIndex = max(0, currentStep.rawValue - 1)
        return Double(currentIndex) / Double(totalSteps)
    }

    private func advanceStep() {
        if let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) {
            if nextStep == .complete {
                completeOnboarding()
            } else {
                currentStep = nextStep
            }
        }
    }

    private func completeOnboarding() {
        // Create user on backend
        Task {
            do {
                let user = try await APIClient.shared.createUser(.init(
                    name: profile.name,
                    nickname: profile.nickname.isEmpty ? nil : profile.nickname,
                    birthYear: profile.birthYear,
                    city: profile.city.isEmpty ? nil : profile.city,
                    phoneNumber: profile.phoneNumber,
                    proactiveCallsEnabled: profile.proactiveCallsEnabled
                ))
                await MainActor.run {
                    appState.currentUser = user
                    appState.isAuthenticated = true
                    appState.completeOnboarding()
                }
            } catch {
                // If user creation fails, still complete onboarding for now
                // The user can be created later
                await MainActor.run {
                    appState.completeOnboarding()
                }
            }
        }
    }
}
