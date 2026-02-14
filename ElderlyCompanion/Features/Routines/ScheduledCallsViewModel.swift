import Foundation

@Observable
final class ScheduledCallsViewModel {
    var scheduledCalls: [APIClient.ScheduledCallRecord] = []
    var showAddCall = false
    var newCallType: ScheduledCallType = .checkin
    var isLoading = false
    var errorMessage: String?
    var showError = false

    func loadCalls() async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        isLoading = true

        do {
            let calls = try await APIClient.shared.getScheduledCalls(userId: userId)
            await MainActor.run {
                scheduledCalls = calls
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    func addCall(_ request: APIClient.ScheduledCallRequest) {
        Task {
            do {
                let call = try await APIClient.shared.createScheduledCall(request)
                await MainActor.run {
                    scheduledCalls.append(call)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to create scheduled call: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }

    func toggleCall(_ call: APIClient.ScheduledCallRecord, enabled: Bool) {
        Task {
            do {
                try await APIClient.shared.updateScheduledCall(
                    id: call.id,
                    update: .init(enabled: enabled, time: nil, days: nil)
                )
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to update: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
}
