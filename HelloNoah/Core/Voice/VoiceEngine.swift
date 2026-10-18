import AVFoundation
import Foundation

/// Who is talking right now.
enum VoiceTurn: Equatable {
    case listening
    case thinking
    case speaking
}

struct SubtitleLine: Identifiable, Equatable {
    enum Speaker { case noah, user }
    let id: String
    let speaker: Speaker
    var text: String
}

enum VoiceEndReason: Equatable {
    /// We ended it (hang up).
    case local
    /// The agent ended the call (e.g. said goodbye, silence timeout).
    case agent
    /// Connection dropped.
    case connectionLost
}

enum VoiceEvent {
    case connected
    case turn(VoiceTurn)
    /// 0…1 levels, sampled ~20× per second.
    case levels(agent: Double, user: Double)
    /// Full subtitle list (latest last).
    case subtitles([SubtitleLine])
    case ended(VoiceEndReason)
}

/// A live voice session. `ElevenLabsVoiceEngine` in production, `MockVoiceEngine` in mock mode.
///
/// `stop()` may be called at any time, also while `start` is still connecting: the engine must
/// then end the session as soon as it exists and must not report `.connected`.
@MainActor
protocol VoiceEngine: AnyObject {
    var onEvent: ((VoiceEvent) -> Void)? { get set }
    func start(_ session: ConversationSession) async throws
    func stop() async
    /// Background information for the agent that it does not answer out loud (an ElevenLabs
    /// contextual update), e.g. "round the conversation off".
    func sendContext(_ text: String) async
}

extension VoiceEngine {
    func sendContext(_ text: String) async {}
}

/// The engine was stopped (hung up) before the session finished connecting.
struct VoiceStartCancelled: Error {}

/// The audio session for a Noah conversation: play-and-record, voice-chat mode (Apple's echo
/// cancellation), loudspeaker by default (older people rarely hold the phone to their ear),
/// Bluetooth headsets/hearing aids allowed.
enum ConversationAudioSession {
    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        #if compiler(>=6.2)
        let bluetooth: AVAudioSession.CategoryOptions = .allowBluetoothHFP
        #else
        let bluetooth: AVAudioSession.CategoryOptions = .allowBluetooth
        #endif
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, bluetooth, .allowBluetoothA2DP])
        try session.setActive(true)
        if session.currentRoute.outputs.contains(where: { $0.portType == .builtInReceiver }) {
            try? session.overrideOutputAudioPort(.speaker)
        }
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Microphone permission (iOS 16 + 17 APIs).
enum MicrophonePermission {
    enum State { case granted, denied, undetermined }

    static var state: State {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            default: return .undetermined
            }
        }
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .undetermined
        }
    }

    /// The current permission, asking once when it was never asked.
    static func ensure() async -> State {
        switch state {
        case .undetermined: return await request() ? .granted : .denied
        case let known: return known
        }
    }

    static func request() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
    }
}
