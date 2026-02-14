import Foundation
import LiveKit

@Observable
final class LiveKitService {
    private(set) var room: Room?
    private(set) var voiceState: VoiceConnectionState = .disconnected
    private(set) var isConnecting: Bool = false
    private(set) var isMicrophoneEnabled: Bool = true
    private(set) var audioLevel: Float = 0.0

    /// Callback for transcriptions: (text, role)
    var onTranscription: ((String, String) -> Void)?

    enum VoiceConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case failed(String)
    }

    private let api = APIClient.shared
    private var roomDelegate: RoomDelegateHandler?

    func connect(userId: String) async throws {
        guard voiceState == .disconnected else { return }

        isConnecting = true
        voiceState = .connecting

        do {
            let tokenResponse = try await api.getLiveKitToken(userId: userId)
            let livekitURL = Bundle.main.infoDictionary?["LIVEKIT_WS_URL"] as? String
                ?? "wss://test-7hm3rr9r.livekit.cloud"

            let newRoom = Room()
            self.room = newRoom

            let delegate = RoomDelegateHandler(service: self)
            self.roomDelegate = delegate
            newRoom.add(delegate: delegate)

            try await newRoom.connect(url: livekitURL, token: tokenResponse.token)

            do {
                try await newRoom.localParticipant.setMicrophone(enabled: true)
                isMicrophoneEnabled = true
            } catch {
                print("[LiveKit] Microphone enable failed: \(error)")
                isMicrophoneEnabled = false
            }

            voiceState = .connected
        } catch {
            voiceState = .failed(error.localizedDescription)
            isConnecting = false
            throw error
        }

        isConnecting = false
    }

    func disconnect() async {
        await room?.disconnect()
        room = nil
        voiceState = .disconnected
        audioLevel = 0.0
        onTranscription = nil
    }

    func toggleMicrophone() async throws {
        guard let room else { return }
        let newState = !isMicrophoneEnabled
        try await room.localParticipant.setMicrophone(enabled: newState)
        isMicrophoneEnabled = newState
    }

    func requestCall(to phoneNumber: String, userId: String, message: String? = nil) async throws {
        _ = try await api.initiateCall(phoneNumber: phoneNumber, userId: userId, message: message)
    }

    fileprivate func updateVoiceState(_ state: VoiceConnectionState) {
        self.voiceState = state
    }

    fileprivate func updateAudioLevel(_ level: Float) {
        self.audioLevel = level
    }

    fileprivate func handleTranscription(_ text: String, role: String) {
        onTranscription?(text, role)
    }
}

// MARK: - Room Delegate Handler

private class RoomDelegateHandler: RoomDelegate {
    weak var service: LiveKitService?

    init(service: LiveKitService) {
        self.service = service
    }

    nonisolated func room(_ room: Room, didUpdateConnectionState connectionState: LiveKit.ConnectionState, from oldConnectionState: LiveKit.ConnectionState) {
        Task { @MainActor in
            switch connectionState {
            case .connected:
                service?.updateVoiceState(.connected)
            case .reconnecting:
                service?.updateVoiceState(.reconnecting)
            case .disconnected:
                service?.updateVoiceState(.disconnected)
            default:
                break
            }
        }
    }

    nonisolated func room(_ room: Room, participant: Participant, didReceiveData data: Data, forTopic topic: String) {
        // LiveKit agents send transcription data on the "lk-transcription" topic
        if topic == "lk-transcription" || topic == "transcription" {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String {
                let role = json["participant_identity"] as? String ?? "assistant"
                let isUser = role.contains("test_") || role == (room.localParticipant.identity?.stringValue ?? "")
                Task { @MainActor in
                    service?.handleTranscription(text, role: isUser ? "user" : "assistant")
                }
            }
        }

        // Also try parsing as plain text
        if topic == "agent-text" || topic == "lk-agent-text" {
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                Task { @MainActor in
                    service?.handleTranscription(text, role: "assistant")
                }
            }
        }
    }
}
