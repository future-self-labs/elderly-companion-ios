import SwiftUI

enum ElderRoute: Hashable {
    case myStory
    case storyEntry(LifeStoryEntry)
    case reminders
    // v2.3: "Instellingen" of a self-managed profile.
    case settings
    case settingsNoah
    case settingsRecording
    case settingsContacts
    case settingsSubscription
    case settingsPaywall
    case settingsInvite
    case settingsCaregivers
    case settingsExport
    case settingsDelete
}

/// The older person's interface: home, conversation (full screen), my story, reminders.
struct ElderRootView: View {
    @EnvironmentObject private var session: ElderSession
    @EnvironmentObject private var app: AppModel
    @State private var path: [ElderRoute] = []

    var body: some View {
        if session.isOnboarding {
            // v2.3: a new self-managed profile first finishes steps 2–5 of the sign-up.
            SelfOnboardingView()
                .transition(.opacity)
        } else {
            home
        }
    }

    private var home: some View {
        NavigationStack(path: $path) {
            ElderHomeView(path: $path)
                .hidesWhileCovered(ownDepth: 0, stackDepth: path.count)
                .navigationDestination(for: ElderRoute.self) { route in
                    Group {
                        switch route {
                        case .myStory: MyStoryView(path: $path)
                        case .storyEntry(let entry): ElderStoryDetailView(entry: entry)
                        case .reminders: ElderRemindersView()
                        case .settings: ElderSettingsView(path: $path)
                        case .settingsNoah: ElderNoahSettingsView()
                        case .settingsRecording: ElderRecordingView()
                        case .settingsContacts: ElderEmergencyContactsView()
                        case .settingsSubscription: ElderSubscriptionView(path: $path)
                        case .settingsPaywall:
                            ElderScrollScreen {
                                ElderPaywallView { if !path.isEmpty { path.removeLast() } }
                            }
                        case .settingsInvite: ElderInviteView()
                        case .settingsCaregivers: ElderCaregiversView(path: $path)
                        case .settingsExport: ElderExportView()
                        case .settingsDelete: ElderDeleteAccountView()
                        }
                    }
                    .noahPushedScreen()
                    .hidesWhileCovered(ownDepth: (path.firstIndex(of: route) ?? 0) + 1, stackDepth: path.count)
                }
        }
        .fullScreenCover(isPresented: $session.isConversationPresented) {
            ConversationScreen(controller: session.makeConversationController(), noahName: session.noahName,
                               needsConfirmation: session.conversationNeedsConfirmation) {
                session.isConversationPresented = false
                Task { await session.load() }
            }
        }
        .onAppear { afterFirstLayout(applyDebugRoute) }
    }

    private func applyDebugRoute() {
        #if DEBUG
        guard let route = DebugRoute.take(scope: "elder") else { return }
        switch route {
        case "conversation": session.requestConversation()
        case "storyConversation": session.requestConversation(mode: .levensverhaal)
        case "myStory": path = [.myStory]
        case "storyEntry":
            path = [.myStory, .storyEntry(MockData.wimLifeStory(now: Date())[2])]
        case "reminders": path = [.reminders]
        case "onboarding", "onboardingVoice", "onboardingContact", "onboardingPaywall": session.startOnboarding()
        case "settings": path = [.settings]
        case "settingsNoah": path = [.settings, .settingsNoah]
        case "settingsRecording": path = [.settings, .settingsRecording]
        case "settingsContacts": path = [.settings, .settingsContacts]
        case "settingsSubscription": path = [.settings, .settingsSubscription]
        case "settingsPaywall": path = [.settings, .settingsSubscription, .settingsPaywall]
        case "settingsInvite": path = [.settings, .settingsInvite]
        case "settingsCaregivers": path = [.settings, .settingsCaregivers]
        case "settingsExport": path = [.settings, .settingsExport]
        case "settingsDelete": path = [.settings, .settingsDelete]
        default: break
        }
        #endif
    }
}

/// Big "Terug" button for the older person's sub-screens (the system back button is too small).
struct ElderBackButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: NoahSpacing.s) {
                Image(systemName: "chevron.left")
                    .accessibilityHidden(true)
                Text("Terug")
            }
            .font(NoahFont.Elder.bodyStrong)
            .foregroundColor(NoahColor.text)
            .padding(.horizontal, NoahSpacing.l)
            .frame(minHeight: NoahSize.elderMinTap)
            .background(Capsule().fill(NoahColor.surface))
            .overlay(Capsule().strokeBorder(NoahColor.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Terug"))
        .accessibilityIdentifier("elder.back")
    }
}

extension View {
    /// Standard chrome for the older person's sub-screens.
    func elderSubscreen() -> some View {
        self
            .noahScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
    }
}
