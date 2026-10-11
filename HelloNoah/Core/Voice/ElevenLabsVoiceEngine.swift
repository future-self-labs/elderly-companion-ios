import AVFoundation
import Combine
import ElevenLabs
import Foundation
import LiveKit

/// Voice session on the ElevenLabs Agents platform (Swift SDK 3.x, WebRTC via LiveKit).
///
/// The backend's `POST /device/conversation` response is passed through unchanged:
/// `conversationToken` authenticates the private agent, `dynamicVariables` and `overrides` go into
/// the `ConversationConfig`.
@MainActor
final class ElevenLabsVoiceEngine: VoiceEngine {
    var onEvent: ((VoiceEvent) -> Void)?

    private var conversation: Conversation?
    private var cancellables = Set<AnyCancellable>()
    private let agentMeter = LevelMeter()
    private let micMeter = LevelMeter()
    private var levelTimer: Timer?
    private var endedLocally = false
    private var didReportEnd = false

    func start(_ session: ConversationSession) async throws {
        // We own the audio session (voice chat + speaker); LiveKit must not reconfigure it.
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
        try ConversationAudioSession.activate()

        var config = ConversationConfig()
        if let variables = session.dynamicVariables {
            config.typedDynamicVariables = variables.mapValues(Self.sdkValue)
        }
        if let agent = session.overrides?.agent {
            config.agentOverrides = AgentOverrides(
                prompt: agent.prompt?.prompt,
                firstMessage: agent.firstMessage,
                language: agent.language.flatMap(Language.init(rawValue:))
            )
        }
        if let tts = session.overrides?.tts {
            config.ttsOverrides = TTSOverrides(voiceId: tts.voiceId, speed: tts.speed)
        }
        config.onDisconnect = { [weak self] reason in
            Task { @MainActor in
                guard let self else { return }
                switch reason {
                case .user: self.reportEnd(.local)
                case .agent: self.reportEnd(.agent)
                case .error: self.reportEnd(.connectionLost)
                }
            }
        }

        let conversation = try await ElevenLabs.startConversation(conversationToken: session.conversationToken, config: config)
        self.conversation = conversation
        observe(conversation)

        AudioManager.shared.add(remoteAudioRenderer: agentMeter)
        AudioManager.shared.add(localAudioRenderer: micMeter)
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.onEvent?(.levels(agent: Double(self.agentMeter.level), user: Double(self.micMeter.level)))
            }
        }
        onEvent?(.connected)
    }

    func stop() async {
        endedLocally = true
        await conversation?.endConversation()
        cleanup()
        reportEnd(.local)
    }

    private func observe(_ conversation: Conversation) {
        conversation.$agentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .listening: self?.onEvent?(.turn(.listening))
                case .speaking: self?.onEvent?(.turn(.speaking))
                case .thinking: self?.onEvent?(.turn(.thinking))
                }
            }
            .store(in: &cancellables)

        conversation.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messages in
                let lines = messages.suffix(6).map {
                    SubtitleLine(id: $0.id, speaker: $0.role == .agent ? .noah : .user, text: $0.content)
                }
                self?.onEvent?(.subtitles(Array(lines)))
            }
            .store(in: &cancellables)

        conversation.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .ended(let reason):
                    switch reason {
                    case .userEnded: self.reportEnd(.local)
                    case .remoteDisconnected: self.reportEnd(self.endedLocally ? .local : .agent)
                    case .agentNotConnected: self.reportEnd(.connectionLost)
                    }
                    self.cleanup()
                case .error:
                    self.reportEnd(.connectionLost)
                    self.cleanup()
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func reportEnd(_ reason: VoiceEndReason) {
        guard !didReportEnd else { return }
        didReportEnd = true
        onEvent?(.ended(reason))
    }

    private func cleanup() {
        levelTimer?.invalidate()
        levelTimer = nil
        AudioManager.shared.remove(remoteAudioRenderer: agentMeter)
        AudioManager.shared.remove(localAudioRenderer: micMeter)
        cancellables.removeAll()
        conversation = nil
        ConversationAudioSession.deactivate()
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = true
    }

    private static func sdkValue(_ value: JSONValue) -> DynamicVariableValue {
        switch value {
        case .string(let string): return .string(string)
        case .int(let int): return .int(int)
        case .double(let double): return .number(double)
        case .bool(let bool): return .boolean(bool)
        case .array(let array): return .array(array.map(sdkValue))
        case .object(let object): return .object(object.mapValues(sdkValue))
        case .null: return .null
        }
    }
}

/// Turns PCM buffers into a smoothed 0…1 level (for the orb and waveform).
final class LevelMeter: NSObject, AudioRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Float = 0

    var level: Float {
        lock.lock(); defer { lock.unlock() }
        current *= 0.82 // decay between reads so silence falls back smoothly
        return current
    }

    func render(pcmBuffer: AVAudioPCMBuffer) {
        let frames = Int(pcmBuffer.frameLength)
        guard frames > 0 else { return }
        var sum: Float = 0
        if let samples = pcmBuffer.floatChannelData?[0] {
            for i in 0..<frames { sum += samples[i] * samples[i] }
        } else if let samples = pcmBuffer.int16ChannelData?[0] {
            for i in 0..<frames {
                let value = Float(samples[i]) / Float(Int16.max)
                sum += value * value
            }
        } else {
            return
        }
        let rms = sqrt(sum / Float(frames))
        let decibels = 20 * log10(max(rms, 0.000_01))
        let normalized = min(max((decibels + 50) / 45, 0), 1)
        lock.lock()
        current = max(normalized, current)
        lock.unlock()
    }
}
