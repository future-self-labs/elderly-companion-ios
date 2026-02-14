import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = HomeViewModel()
    @State private var selectedMood: Mood?
    @State private var showConversation = false
    @State private var calendarService = CalendarService()

    var body: some View {
        ScrollView {
            VStack(spacing: CompanionTheme.Spacing.lg) {
                // Date & Next Event header
                dateHeader

                // Main voice buttons
                voiceButtons

                // Mood check
                CalmCard {
                    MoodSelector(selectedMood: $selectedMood)
                }

                // Today's reminders
                remindersCard

                // Recent conversation summary
                recentConversationCard
            }
            .padding(CompanionTheme.Spacing.lg)
        }
        .background(Color.companionBackground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Noah")
                    .font(.companionHeadline)
                    .foregroundStyle(Color.companionTextPrimary)
            }
        }
        .fullScreenCover(isPresented: $showConversation) {
            ConversationView()
                .environment(appState)
        }
        .alert("Call Failed", isPresented: $showCallAlert) {
            Button("OK") {}
        } message: {
            Text(callError ?? "An unknown error occurred.")
        }
        .alert("Enter your phone number", isPresented: $showPhoneInput) {
            TextField("+31...", text: $phoneInputNumber)
                .keyboardType(.phonePad)
            Button("Call") {
                guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
                executeCall(phone: phoneInputNumber, userId: userId)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Noah will call this number. Include country code (e.g. +31).")
        }
        .onAppear {
            calendarService.fetchTodayEvents()
        }
    }

    // MARK: - Date Header

    private var dateHeader: some View {
        CalmCard {
            VStack(alignment: .leading, spacing: CompanionTheme.Spacing.sm) {
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.companionHeadline)
                    .foregroundStyle(Color.companionTextPrimary)

                if let nextEvent = calendarService.nextEvent {
                    HStack(spacing: CompanionTheme.Spacing.sm) {
                        Image(systemName: "calendar")
                            .foregroundStyle(Color.companionPrimary)
                        Text("Next: \(nextEvent.title ?? "Event") at \(nextEvent.startDate.formatted(.dateTime.hour().minute()))")
                            .font(.companionBodySecondary)
                            .foregroundStyle(Color.companionTextSecondary)
                    }
                } else {
                    HStack(spacing: CompanionTheme.Spacing.sm) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(Color.companionSuccess)
                        Text("No upcoming events today")
                            .font(.companionBodySecondary)
                            .foregroundStyle(Color.companionTextSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Voice Buttons

    private var voiceButtons: some View {
        VStack(spacing: CompanionTheme.Spacing.md) {
            // Primary: Talk Now (in-app voice)
            Button {
                showConversation = true
            } label: {
                HStack(spacing: CompanionTheme.Spacing.md) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 28, weight: .bold))

                    Text("Talk Now")
                        .font(.companionDisplay)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 100)
                .background(LinearGradient.aiGradient)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: CompanionTheme.Radius.xl))
                .shadow(color: Color.companionPrimary.opacity(0.3), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Talk to Noah now")

            // Secondary: Call AI (phone call)
            LargeButton("Call Noah", icon: "phone.fill", style: .secondary) {
                requestPhoneCall()
            }
        }
    }

    // MARK: - Reminders Card

    private var remindersCard: some View {
        CalmCard {
            VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                CalmCardHeader("Today's Reminders", icon: "bell.fill")

                if viewModel.todayReminders.isEmpty {
                    Text("No reminders for today")
                        .font(.companionBodySecondary)
                        .foregroundStyle(Color.companionTextTertiary)
                } else {
                    ForEach(viewModel.todayReminders, id: \.self) { reminder in
                        HStack(spacing: CompanionTheme.Spacing.sm) {
                            Image(systemName: "circle")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.companionPrimary)
                            Text(reminder)
                                .font(.companionBody)
                                .foregroundStyle(Color.companionTextSecondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recent Conversation

    private var recentConversationCard: some View {
        CalmCard {
            VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                CalmCardHeader("Recent Conversation", icon: "bubble.left.fill")

                Text(viewModel.recentConversationSummary ?? "No conversations yet. Tap \"Talk Now\" to start!")
                    .font(.companionBodySecondary)
                    .foregroundStyle(Color.companionTextSecondary)
                    .lineLimit(3)
            }
        }
    }

    // MARK: - Actions

    @State private var callError: String?
    @State private var showCallAlert = false
    @State private var showPhoneInput = false
    @State private var phoneInputNumber = ""

    private func requestPhoneCall() {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else {
            callError = "No user ID found. Please complete onboarding."
            showCallAlert = true
            return
        }

        let phoneNumber = appState.currentUser?.phoneNumber
            ?? UserDefaults.standard.string(forKey: "userPhoneNumber")

        if let phone = phoneNumber, !phone.isEmpty {
            executeCall(phone: phone, userId: userId)
        } else {
            // No phone stored -- ask for it
            showPhoneInput = true
        }
    }

    private func executeCall(phone: String, userId: String) {
        // Save for next time
        UserDefaults.standard.set(phone, forKey: "userPhoneNumber")

        Task {
            do {
                try await APIClient.shared.initiateCall(
                    phoneNumber: phone,
                    userId: userId
                )
            } catch {
                await MainActor.run {
                    callError = error.localizedDescription
                    showCallAlert = true
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .environment(AppState())
}
