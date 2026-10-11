import SwiftUI

enum ElderRoute: Hashable {
    case myStory
    case storyEntry(LifeStoryEntry)
    case reminders
}

/// The older person's interface: home, conversation (full screen), my story, reminders.
struct ElderRootView: View {
    @EnvironmentObject private var session: ElderSession
    @EnvironmentObject private var app: AppModel
    @State private var path: [ElderRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ElderHomeView(path: $path)
                .navigationDestination(for: ElderRoute.self) { route in
                    switch route {
                    case .myStory: MyStoryView(path: $path)
                    case .storyEntry(let entry): ElderStoryDetailView(entry: entry)
                    case .reminders: ElderRemindersView()
                    }
                }
        }
        .fullScreenCover(isPresented: $session.isConversationPresented) {
            ConversationScreen(controller: session.makeConversationController(), noahName: session.noahName) {
                session.isConversationPresented = false
                Task { await session.load() }
            }
        }
        .onAppear { afterFirstLayout(applyDebugRoute) }
    }

    private func applyDebugRoute() {
        guard let route = DebugRoute.take(scope: "elder") else { return }
        switch route {
        case "conversation": session.requestConversation()
        case "myStory": path = [.myStory]
        case "storyEntry":
            path = [.myStory, .storyEntry(MockData.wimLifeStory(now: Date())[2])]
        case "reminders": path = [.reminders]
        default: break
        }
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
