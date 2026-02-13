import Foundation
import LiveKit

@Observable
final class LiveKitService {
    private(set) var room: Room?
    private(set) var voiceState: VoiceConnectionState = .disconnected
    private(set) var isConnecting: Bool = false
    private(set) var isMicrophoneEnabled: Bool = true
    private(set) var audioLevel: Float = 0.0

    /// Our own connection state (avoids conflict with LiveKit's ConnectionState)
    enum VoiceConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case failed(String)
    }

    private let api = APIClient.shared
    private var roomDelegate: RoomDelegateHandler?

    /// Connect to a LiveKit voice room for in-app conversation
    func connect(userId: String) async throws {
        guard voiceState == .disconnected else { return }

        isConnecting = true
        voiceState = .connecting

        do {
            // Get token from backend
            let tokenResponse = try await api.getLiveKitToken(userId: userId)
            let livekitURL = Bundle.main.infoDictionary?["LIVEKIT_WS_URL"] as? String
                ?? "wss://elderly-companion-iru5iqec.livekit.cloud"

            // Create and connect room
            let newRoom = Room()
            self.room = newRoom

            // Set up delegate
            let delegate = RoomDelegateHandler(service: self)
            self.roomDelegate = delegate
            newRoom.add(delegate: delegate)

            try await newRoom.connect(url: livekitURL, token: tokenResponse.token)

            // Enable microphone
            try await newRoom.localParticipant.setMicrophone(enabled: true)

            voiceState = .connected
            isMicrophoneEnabled = true
        } catch {
            voiceState = .failed(error.localizedDescription)
            throw error
        }

        isConnecting = false
    }

    /// Disconnect from the voice room
    func disconnect() async {
        await room?.disconnect()
        room = nil
        voiceState = .disconnected
        audioLevel = 0.0
    }

    /// Toggle microphone on/off
    func toggleMicrophone() async throws {
        guard let room else { return }
        let newState = !isMicrophoneEnabled
        try await room.localParticipant.setMicrophone(enabled: newState)
        isMicrophoneEnabled = newState
    }

    /// Request an outbound AI call to a phone number
    func requestCall(to phoneNumber: String, userId: String, message: String? = nil) async throws {
        _ = try await api.initiateCall(phoneNumber: phoneNumber, userId: userId, message: message)
    }

    // MARK: - Internal state updates

    fileprivate func updateVoiceState(_ state: VoiceConnectionState) {
        self.voiceState = state
    }

    fileprivate func updateAudioLevel(_ level: Float) {
        self.audioLevel = level
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
}
