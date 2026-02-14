import Foundation

@Observable
final class CallHistoryViewModel {
    var calls: [CallRecord] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var showError: Bool = false

    private static func parseDate(_ string: String) -> Date {
        // Try multiple formats since Postgres timestamps can vary
        let formatters: [ISO8601DateFormatter] = {
            let f1 = ISO8601DateFormatter()
            f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            return [f1, f2]
        }()

        for formatter in formatters {
            if let date = formatter.date(from: string) { return date }
        }

        // Fallback: try DateFormatter for Postgres format "2026-02-14 15:36:54.427"
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        if let date = df.date(from: string) { return date }

        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        df.timeZone = TimeZone(identifier: "UTC")
        if let date = df.date(from: string) { return date }

        return Date()
    }

    func loadCalls() async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        isLoading = true

        do {
            let transcripts = try await APIClient.shared.getTranscripts(userId: userId)

            let records: [CallRecord] = transcripts.map { transcript in
                let startDate = Self.parseDate(transcript.createdAt)
                let callTags: [CallTag] = transcript.tags.compactMap { CallTag(rawValue: $0) }

                return CallRecord(
                    id: transcript.id,
                    userId: transcript.userId,
                    direction: .inbound,
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
