import SwiftUI

struct OnboardingContainerView: View {
    @Environment(AppState.self) private var appState
    @State private var currentStep: OnboardingStep = .welcome
    @State private var profile = UserProfile()
    @State private var authService = AuthService()
    @State private var onboardingError: String?
    @State private var showError = false

    enum OnboardingStep: Int, CaseIterable {
        case welcome
        case language
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

                case .language:
                    LanguagePickerOnboardingView(
                        selectedLanguage: $profile.language,
                        onContinue: {
                            UserDefaults.standard.set(profile.language, forKey: "preferredLanguage")
                            advanceStep()
                        }
                    )

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
        .alert("Setup Error", isPresented: $showError) {
            Button("Continue Anyway") {
                appState.completeOnboarding()
            }
            Button("Retry") {
                completeOnboarding()
            }
        } message: {
            Text(onboardingError ?? "Could not create your profile. You can retry or continue and set up later.")
        }
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
        // Store phone number locally for call feature
        if !profile.phoneNumber.isEmpty {
            UserDefaults.standard.set(profile.phoneNumber, forKey: "userPhoneNumber")
        }

        // Create user on backend
        Task {
            do {
                let user = try await APIClient.shared.createUser(.init(
                    name: profile.name,
                    nickname: profile.nickname.isEmpty ? nil : profile.nickname,
                    birthYear: profile.birthYear,
                    city: profile.city.isEmpty ? nil : profile.city,
                    phoneNumber: profile.phoneNumber,
                    language: profile.language,
                    proactiveCallsEnabled: profile.proactiveCallsEnabled
                ))
                await MainActor.run {
                    appState.currentUser = user
                    appState.isAuthenticated = true
                    appState.completeOnboarding()
                }
            } catch {
                await MainActor.run {
                    onboardingError = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}
