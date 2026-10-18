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
///
/// Audio levels (SDK 3.4 has no level publisher):
/// - Noah: a renderer on the agent's `RemoteAudioTrack` (a WebRTC track sink, so it receives
///   decoded audio even when Apple's voice processing bypasses WebRTC's audio-processing module,
///   which is why `AudioManager.add(remoteAudioRenderer:)` alone stays silent on devices).
/// - The older person: the server's VAD score (`onVadScore`, 0…1) plus the local mic renderer.
/// `ConversationController` adds a gentle synthetic animation if no real level arrives.
@MainActor
final class ElevenLabsVoiceEngine: VoiceEngine {
    var onEvent: ((VoiceEvent) -> Void)?

    private var conversation: Conversation?
    private var cancellables = Set<AnyCancellable>()
    private let agentMeter = LevelMeter()
    private let agentProcessingMeter = LevelMeter()
    private let micMeter = LevelMeter()
    private var vadScore = VADScore()
    private weak var attachedAgentTrack: RemoteAudioTrack?
    private var levelTimer: Timer?
    private var endedLocally = false
    private var didReportEnd = false
    /// `stop()` was called; a session that is still connecting must be ended as soon as it exists.
    private var stopRequested = false

    func start(_ session: ConversationSession) async throws {
        guard !stopRequested else { throw VoiceStartCancelled() }
        // We own the audio session (voice chat + speaker); LiveKit must not reconfigure it.
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
        do {
            try ConversationAudioSession.activate()
        } catch {
            cleanup()
            throw error
        }

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
        let vad = vadScore
        config.onVadScore = { score in vad.update(score) }

        let conversation: Conversation
        do {
            // `onDisconnect` must be passed here: this entry point overwrites `config.onDisconnect`.
            conversation = try await ElevenLabs.startConversation(
                conversationToken: session.conversationToken,
                config: config,
                onDisconnect: { [weak self] reason in
                    Task { @MainActor in
                        guard let self else { return }
                        switch reason {
                        case .user: self.reportEnd(.local)
                        case .agent: self.reportEnd(self.endedLocally ? .local : .agent)
                        case .error: self.reportEnd(.connectionLost)
                        }
                    }
                }
            )
        } catch {
            // Connecting failed: give the audio session back (other apps, the recording player).
            cleanup()
            if stopRequested { throw VoiceStartCancelled() }
            throw error
        }

        // Hung up while connecting: end the session that just came up, never report it connected.
        if stopRequested || Task.isCancelled {
            await conversation.endConversation()
            cleanup()
            throw VoiceStartCancelled()
        }

        self.conversation = conversation
        observe(conversation)

        AudioManager.shared.add(remoteAudioRenderer: agentProcessingMeter)
        AudioManager.shared.add(localAudioRenderer: micMeter)
        attachAgentTrackIfNeeded()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // The agent's track appears once the agent publishes it; attach as soon as it exists.
                self.attachAgentTrackIfNeeded()
                let agent = max(self.agentMeter.level, self.agentProcessingMeter.level)
                let user = max(self.micMeter.level, Float(self.vadScore.value) * 0.8)
                #if DEBUG
                self.logFirstLevels(agent: agent, user: user)
                #endif
                self.onEvent?(.levels(agent: Double(agent), user: Double(user)))
            }
        }
        onEvent?(.connected)
    }

    func stop() async {
        endedLocally = true
        stopRequested = true
        let conversation = self.conversation
        await conversation?.endConversation()
        cleanup()
        reportEnd(.local)
    }

    func sendContext(_ text: String) async {
        try? await conversation?.updateContext(text)
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

    #if DEBUG
    private var loggedAgentLevel = false
    private var loggedUserLevel = false

    private func logFirstLevels(agent: Float, user: Float) {
        if !loggedAgentLevel, agent > 0.04 {
            loggedAgentLevel = true
            NSLog("[HelloNoah Voice] real agent level %.2f (track sink %.2f, APM %.2f)", agent, agentMeter.level, agentProcessingMeter.level)
        }
        if !loggedUserLevel, user > 0.04 {
            loggedUserLevel = true
            NSLog("[HelloNoah Voice] real user level %.2f (vad %.2f)", user, vadScore.value)
        }
    }
    #endif

    private func attachAgentTrackIfNeeded() {
        guard let track = conversation?.agentAudioTrack, track !== attachedAgentTrack else { return }
        attachedAgentTrack?.remove(audioRenderer: agentMeter)
        track.add(audioRenderer: agentMeter)
        attachedAgentTrack = track
        #if DEBUG
        NSLog("[HelloNoah Voice] level renderer attached to agent track")
        #endif
    }

    private func reportEnd(_ reason: VoiceEndReason) {
        guard !didReportEnd else { return }
        didReportEnd = true
        onEvent?(.ended(reason))
    }

    private func cleanup() {
        levelTimer?.invalidate()
        levelTimer = nil
        attachedAgentTrack?.remove(audioRenderer: agentMeter)
        attachedAgentTrack = nil
        AudioManager.shared.remove(remoteAudioRenderer: agentProcessingMeter)
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

/// Latest server VAD score, decaying when no new scores arrive.
final class VADScore: @unchecked Sendable {
    private let lock = NSLock()
    private var score: Double = 0
    private var at = Date.distantPast

    func update(_ value: Double) {
        lock.lock(); score = min(max(value, 0), 1); at = Date(); lock.unlock()
    }

    var value: Double {
        lock.lock(); defer { lock.unlock() }
        let age = Date().timeIntervalSince(at)
        return age > 0.6 ? 0 : score * (1 - age / 0.6)
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
