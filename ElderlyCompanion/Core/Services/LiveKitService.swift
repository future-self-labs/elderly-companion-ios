import AVFoundation
import Foundation
import LiveKit

@Observable
final class LiveKitService {
    private(set) var room: Room?
    private(set) var voiceState: VoiceConnectionState = .disconnected
    private(set) var isConnecting: Bool = false
    private(set) var isMicrophoneEnabled: Bool = true
    private(set) var audioLevel: Float = 0.0

    init() {
        // Use .voiceChat mode with speaker output for optimal echo cancellation.
        // The default .videoChat mode has weaker AEC, causing the agent to hear its own audio.
        AudioManager.shared.sessionConfiguration = AudioSessionConfiguration(
            category: .playAndRecord,
            categoryOptions: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .allowAirPlay],
            mode: .voiceChat
        )
    }

    /// Callback for transcriptions: (text, role)
    var onTranscription: ((String, String) -> Void)?

    /// Track seen transcription stream IDs to deduplicate interim results
    private var seenTranscriptionIds: Set<String> = []

    enum VoiceConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case failed(String)
    }

    private let api = APIClient.shared
    private var roomDelegate: RoomDelegateHandler?

    func connect(userId: String, usePipeline: Bool = false, voiceId: String? = nil) async throws {
        guard voiceState == .disconnected else { return }

        isConnecting = true
        voiceState = .connecting

        do {
            let tokenResponse = usePipeline
                ? try await api.getLiveKitPipelineToken(userId: userId, voiceId: voiceId)
                : try await api.getLiveKitToken(userId: userId)
            let livekitURL = Bundle.main.infoDictionary?["LIVEKIT_WS_URL"] as? String
                ?? "wss://test-7hm3rr9r.livekit.cloud"

            let newRoom = Room()
            self.room = newRoom

            let delegate = RoomDelegateHandler(service: self)
            self.roomDelegate = delegate
            newRoom.add(delegate: delegate)

            try await newRoom.connect(url: livekitURL, token: tokenResponse.token)

            // Register text stream handler for pipeline transcriptions
            if usePipeline {
                do {
                    try await newRoom.registerTextStreamHandler(for: "lk.transcription") { [weak self] reader, participantIdentity in
                        do {
                            let streamId = reader.info.id
                            let localIdentity = newRoom.localParticipant.identity?.stringValue ?? ""
                            let isUser = participantIdentity.stringValue == localIdentity

                            // Read all chunks until stream closes
                            var accumulated = ""
                            for try await chunk in reader {
                                accumulated += chunk
                            }

                            let trimmed = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }

                            await MainActor.run {
                                guard let self else { return }
                                // Deduplicate: only process each stream ID once (skip interim updates)
                                guard !self.seenTranscriptionIds.contains(streamId) else { return }
                                self.seenTranscriptionIds.insert(streamId)
                                self.handleTranscription(trimmed, role: isUser ? "user" : "assistant")
                            }
                        } catch {
                            print("[LiveKit] Transcription stream error: \(error)")
                        }
                    }
                } catch {
                    print("[LiveKit] Failed to register transcription handler: \(error)")
                }
            }

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
        seenTranscriptionIds.removeAll()
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

    // MARK: - Pipeline transcriptions (TranscriptionSegments — new LiveKit streaming API)

    nonisolated func room(_ room: Room, participant: RemoteParticipant, trackPublication: RemoteTrackPublication, didReceiveTranscriptionSegments segments: [TranscriptionSegment]) {
        let localIdentity = room.localParticipant.identity?.stringValue ?? ""

        for segment in segments {
            guard segment.isFinal else { continue }
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            // Determine role: if the segment's track belongs to the local participant, it's "user"
            let participantId = participant.identity?.stringValue ?? ""
            let isUser = participantId == localIdentity

            Task { @MainActor in
                service?.handleTranscription(text, role: isUser ? "user" : "assistant")
            }
        }
    }

    // MARK: - Realtime transcriptions (data channels — old format for OpenAI Realtime API)

    nonisolated func room(_ room: Room, participant: Participant, didReceiveData data: Data, forTopic topic: String) {
        let localIdentity = room.localParticipant.identity?.stringValue ?? ""

        // LiveKit Realtime agents send transcription data on the "lk-transcription" topic
        if topic == "lk-transcription" || topic == "transcription" {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Format 1: Direct text field
                if let text = json["text"] as? String, !text.isEmpty {
                    let isFinal = json["is_final"] as? Bool ?? json["final"] as? Bool ?? true
                    guard isFinal else { return }

                    let role = json["participant_identity"] as? String ?? participant.identity?.stringValue ?? "assistant"
                    let isUser = role == localIdentity || role.contains("sip_")
                    Task { @MainActor in
                        service?.handleTranscription(text, role: isUser ? "user" : "assistant")
                    }
                    return
                }

                // Format 2: Segments array (OpenAI Realtime format)
                if let segments = json["segments"] as? [[String: Any]] {
                    for segment in segments {
                        if let text = segment["text"] as? String, !text.isEmpty {
                            let isFinal = segment["final"] as? Bool ?? segment["is_final"] as? Bool ?? true
                            guard isFinal else { continue }

                            let segmentId = segment["id"] as? String ?? ""
                            let isUser = segmentId.contains("user") || (segment["language"] as? String) != nil
                            Task { @MainActor in
                                service?.handleTranscription(text, role: isUser ? "user" : "assistant")
                            }
                        }
                    }
                    return
                }
            }
        }

        // Also try parsing as plain text for custom agent topics
        if topic == "agent-text" || topic == "lk-agent-text" {
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                Task { @MainActor in
                    service?.handleTranscription(text, role: "assistant")
                }
            }
        }
    }
}
