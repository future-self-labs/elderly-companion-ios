import Foundation
import LiveKit

@Observable
final class ConversationViewModel {
    private var liveKitService = LiveKitService()
    private var timer: Timer?
    private var sessionStartTime: Date?

    // State
    var isListening: Bool = false
    var isMicEnabled: Bool = true
    var audioLevel: Float = 0.0
    var sessionDuration: TimeInterval = 0
    var lastTranscription: String?
    var isMarkedImportant: Bool = false
    var statusMessage: String = "Connecting..."
    var errorDetail: String?
    var transcriptSaveError: String?
    var showTranscriptSaveError: Bool = false

    // Transcript collection
    private(set) var transcriptMessages: [APIClient.TranscriptMessage] = []

    var isConnected: Bool {
        liveKitService.voiceState == .connected
    }

    var formattedDuration: String {
        let minutes = Int(sessionDuration) / 60
        let seconds = Int(sessionDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func startSession(userId: String) {
        guard !userId.isEmpty else {
            statusMessage = "No user ID"
            errorDetail = "Please complete onboarding first."
            return
        }

        statusMessage = "Connecting..."
        errorDetail = nil
        transcriptMessages = []

        Task { @MainActor in
            do {
                try await liveKitService.connect(userId: userId)

                // Listen for transcription data from the agent
                liveKitService.onTranscription = { [weak self] text, role in
                    Task { @MainActor in
                        self?.handleTranscription(text: text, role: role)
                    }
                }

                isListening = true
                statusMessage = "Connected"
                sessionStartTime = Date()
                startTimer()
            } catch {
                statusMessage = "Connection failed"
                errorDetail = error.localizedDescription
                print("[ConversationVM] Connection error: \(error)")
            }
        }
    }

    private var hasEndedSession = false

    func endSession() {
        // Prevent double-save when both button press and onDisappear trigger this
        guard !hasEndedSession else { return }
        hasEndedSession = true

        stopTimer()
        let duration = Int(sessionDuration)
        let messages = transcriptMessages
        let userId = UserDefaults.standard.string(forKey: "userId") ?? ""

        Task { @MainActor in
            await liveKitService.disconnect()
            isListening = false
            statusMessage = "Disconnected"

            // Save transcript if we have messages
            if !messages.isEmpty && !userId.isEmpty {
                await saveTranscript(userId: userId, duration: duration, messages: messages)
            }
        }
    }

    func toggleMicrophone() {
        Task { @MainActor in
            try? await liveKitService.toggleMicrophone()
            isMicEnabled = liveKitService.isMicrophoneEnabled
            isListening = isMicEnabled
        }
    }

    func markAsImportant() {
        isMarkedImportant.toggle()
    }

    func markAsMemory() {
        // Will be handled when saving transcript
    }

    func retry() {
        let userId = UserDefaults.standard.string(forKey: "userId") ?? ""
        liveKitService = LiveKitService()
        startSession(userId: userId)
    }

    // MARK: - Transcription handling

    private func handleTranscription(text: String, role: String) {
        lastTranscription = text

        let message = APIClient.TranscriptMessage(
            role: role,
            content: text,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        transcriptMessages.append(message)
    }

    // MARK: - Save transcript to backend

    private func saveTranscript(userId: String, duration: Int, messages: [APIClient.TranscriptMessage]) async {
        do {
            _ = try await APIClient.shared.saveTranscript(.init(
                userId: userId,
                duration: duration,
                messages: messages,
                tags: isMarkedImportant ? ["companion", "important"] : ["companion"],
                summary: nil
            ))
            print("[ConversationVM] Transcript saved (\(messages.count) messages)")
        } catch {
            print("[ConversationVM] Failed to save transcript: \(error)")
            await MainActor.run {
                transcriptSaveError = "Your conversation was not saved: \(error.localizedDescription)"
                showTranscriptSaveError = true
            }
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let start = sessionStartTime else { return }
            Task { @MainActor in
                self.sessionDuration = Date().timeIntervalSince(start)
                self.audioLevel = self.liveKitService.audioLevel
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
