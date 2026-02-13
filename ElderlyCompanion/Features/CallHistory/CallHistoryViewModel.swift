import Foundation

@Observable
final class CallHistoryViewModel {
    var calls: [CallRecord] = []
    var isLoading: Bool = false

    func loadCalls() async {
        isLoading = true

        // TODO: Fetch call history from backend
        // For now, using empty state
        // In production, this would call: APIClient.shared.getCallHistory(userId:)

        await MainActor.run {
            isLoading = false
        }
    }
}
