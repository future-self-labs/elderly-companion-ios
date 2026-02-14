import Foundation

@Observable
final class CallHistoryViewModel {
    var calls: [CallRecord] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var showError: Bool = false

    func loadCalls() async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        isLoading = true

        do {
            let transcripts = try await APIClient.shared.getTranscripts(userId: userId)

            let records: [CallRecord] = transcripts.compactMap { transcript in
                // Parse createdAt string to Date
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let startDate = formatter.date(from: transcript.createdAt) ?? Date()

                // Convert string tags to CallTag enum values
                let callTags: [CallTag] = transcript.tags.compactMap { CallTag(rawValue: $0) }

                return CallRecord(
                    id: transcript.id,
                    userId: transcript.userId,
                    direction: .inbound, // Default: conversations are user-initiated
                    duration: TimeInterval(transcript.duration),
                    startedAt: startDate,
                    endedAt: startDate.addingTimeInterval(TimeInterval(transcript.duration)),
                    tags: callTags.isEmpty ? [.companion] : callTags,
                    summary: transcript.summary
                )
            }

            await MainActor.run {
                calls = records.sorted { $0.startedAt > $1.startedAt }
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
}
