import Foundation

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

    var isConnected: Bool {
        liveKitService.voiceState == .connected
    }

    var formattedDuration: String {
        let minutes = Int(sessionDuration) / 60
        let seconds = Int(sessionDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func startSession(userId: String) {
        Task {
            do {
                try await liveKitService.connect(userId: userId)
                await MainActor.run {
                    isListening = true
                    statusMessage = "Connected"
                    sessionStartTime = Date()
                    startTimer()
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Connection failed"
                }
            }
        }
    }

    func endSession() {
        stopTimer()
        Task {
            await liveKitService.disconnect()
            await MainActor.run {
                isListening = false
                statusMessage = "Disconnected"
            }
        }
    }

    func toggleMicrophone() {
        Task {
            try? await liveKitService.toggleMicrophone()
            await MainActor.run {
                isMicEnabled = liveKitService.isMicrophoneEnabled
                isListening = isMicEnabled
            }
        }
    }

    func markAsImportant() {
        isMarkedImportant.toggle()
    }

    func markAsMemory() {
        // Save current conversation as a memory
        // This will be sent to the backend when the session ends
    }

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
