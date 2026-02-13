import Foundation

@Observable
final class HomeViewModel {
    var todayReminders: [String] = []
    var recentConversationSummary: String?
    var isLoading: Bool = false

    func loadData() async {
        isLoading = true

        // Load today's reminders from stored routines
        loadReminders()

        // Load recent conversation summary from memory
        await loadRecentConversation()

        isLoading = false
    }

    private func loadReminders() {
        // Load from UserDefaults or local storage
        // For now, return placeholder data
        todayReminders = []
    }

    private func loadRecentConversation() async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }

        do {
            let context = try await APIClient.shared.getUserMemory(userId: userId)
            await MainActor.run {
                recentConversationSummary = context
            }
        } catch {
            // Silently fail - we'll show the empty state
        }
    }
}
