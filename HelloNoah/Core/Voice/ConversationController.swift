import AVFoundation
import Combine
import Foundation
import UIKit

/// Runs one conversation with Noah for the older person: permission, `POST /device/conversation`,
/// the voice engine, max duration, interruptions (incoming phone call) and network loss.
@MainActor
final class ConversationController: ObservableObject {
    enum Phase: Equatable {
        case preparing
        case connecting
        case active
        case ended(EndKind)
        case failed(Failure)
    }

    enum EndKind: Equatable {
        case hungUp
        case noahEnded
        case maxDuration
        case interrupted
    }

    enum Failure: Equatable {
        case micDenied
        case inactive
        case offline
        case connectionLost
        case message(String)

        var text: String {
            switch self {
            case .micDenied: return "Noah kan u niet horen, omdat de microfoon uit staat. U kunt de microfoon aanzetten bij Instellingen."
            case .inactive: return "Noah is nog niet actief. Vraag uw mantelzorger om hulp."
            case .offline: return "Er is nu geen internet. Probeert u het straks nog eens."
            case .connectionLost: return "De verbinding met Noah is weggevallen. Probeert u het gerust nog een keer."
            case .message(let text): return text
            }
        }
    }

    @Published private(set) var phase: Phase = .preparing
    @Published private(set) var turn: VoiceTurn = .listening
    @Published private(set) var agentLevel: Double = 0
    @Published private(set) var userLevel: Double = 0
    @Published private(set) var levelHistory: [Double] = Array(repeating: 0, count: 24)
    @Published private(set) var subtitles: [SubtitleLine] = []
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var networkLost = false
    @Published private(set) var isNearMaxDuration = false
    /// The server records this conversation (Noah asks permission first): show "Wordt opgenomen".
    @Published private(set) var isRecording = false
    /// "Praat met Noah" (`gesprek`) or "Vertel een verhaal" (`levensverhaal`).
    let mode: ConversationMode
    @Published var showsSubtitles: Bool {
        didSet { UserDefaults.standard.set(showsSubtitles, forKey: Self.subtitlesKey) }
    }

    private static let subtitlesKey = "elder.showsSubtitles"
    /// How long before the maximum duration Noah is asked to round the conversation off.
    static let wrapUpLead: TimeInterval = 60
    /// Extra time after the maximum so Noah can finish the goodbye he is saying.
    static let goodbyeGrace: TimeInterval = 30
    static let wrapUpContext = "De afgesproken gesprekstijd is bijna om. Rond het gesprek in de komende minuut rustig en vriendelijk af: vat kort samen, neem warm afscheid en zeg dat je er de volgende keer graag weer bent. Begin geen nieuw onderwerp. Beëindig daarna zelf het gesprek."

    /// Configurable name of Noah, for the status line.
    let noahName: String
    private let api: NoahAPI
    private let makeEngine: () -> VoiceEngine
    private let reachability: Reachability
    private let requestMicrophone: () async -> MicrophonePermission.State
    private var engine: VoiceEngine?
    private var maxDuration: TimeInterval = 30 * 60
    private var wrapUpSent = false
    private var clock: Timer?
    private var startedAt: Date?
    private var cancellables = Set<AnyCancellable>()
    private var interruptionObserver: NSObjectProtocol?

    init(api: NoahAPI, reachability: Reachability, mode: ConversationMode = .gesprek, noahName: String = "Noah",
         requestMicrophone: @escaping () async -> MicrophonePermission.State = MicrophonePermission.ensure,
         makeEngine: @escaping () -> VoiceEngine) {
        self.api = api
        self.reachability = reachability
        self.mode = mode
        self.noahName = noahName.isEmpty ? "Noah" : noahName
        self.requestMicrophone = requestMicrophone
        self.makeEngine = makeEngine
        showsSubtitles = UserDefaults.standard.object(forKey: Self.subtitlesKey) as? Bool ?? true
    }

    var statusText: String {
        switch phase {
        case .preparing, .connecting: return "\(noahName) wordt gebeld…"
        case .active:
            if networkLost { return "De verbinding hapert even…" }
            switch turn {
            case .listening: return "\(noahName) luistert"
            case .thinking: return "\(noahName) denkt even na"
            case .speaking: return "\(noahName) praat"
            }
        case .ended: return "Gesprek beëindigd"
        case .failed: return "Dat lukte niet"
        }
    }

    var orbActivity: OrbActivity {
        switch phase {
        case .preparing, .connecting: return .connecting
        case .active:
            switch turn {
            case .listening: return .listening
            case .thinking: return .thinking
            case .speaking: return .speaking
            }
        default: return .idle
        }
    }

    // MARK: Lifecycle

    private var isStarting = false

    func start() async {
        guard !isStarting, phase == .preparing || isFinished else { return }
        isStarting = true
        defer { isStarting = false }
        reset()
        phase = .preparing

        // A story (or any recording) that is still playing must not play into the conversation.
        RecordingPlayer.pauseCurrent()

        guard reachability.isOnline else { return fail(.offline) }

        guard await requestMicrophone() == .granted else { return fail(.micDenied) }
        // Hung up while the permission alert was showing.
        guard !isFinished else { return }

        let session: ConversationSession
        do {
            session = try await api.startDeviceConversation(mode: mode)
        } catch {
            guard !isFinished else { return }
            let apiError = APIError.from(error)
            switch apiError {
            case .server(_, "inactive", _): return fail(.inactive)
            case .offline: return fail(.offline)
            case .cancelled: return
            default: return fail(.message(apiError.elderMessage))
            }
        }
        // Hung up while the session was being prepared: don't open the microphone at all.
        guard !isFinished, !Task.isCancelled else { return }
        if let seconds = session.maxDurationSeconds ?? session.overrides?.conversation?.maxDurationSeconds, seconds > 0 {
            maxDuration = TimeInterval(seconds)
        }
        isRecording = session.recording

        phase = .connecting
        let engine = makeEngine()
        self.engine = engine
        engine.onEvent = { [weak self] event in self?.handle(event) }
        observeInterruptions()
        observeNetwork()
        do {
            try await engine.start(session)
        } catch {
            if self.engine === engine { self.engine = nil }
            // Hung up while connecting: `end` already stopped the engine and closed the screen.
            guard !isFinished, !(error is VoiceStartCancelled) else { return }
            #if DEBUG
            NSLog("[Conversation] start failed: %@", String(describing: error))
            #endif
            return fail(reachability.isOnline ? .message("Het lukt nu even niet om \(noahName) te bereiken. Probeert u het over een paar minuten nog eens.") : .offline)
        }
        // The engine connected after a hang-up it did not notice: stop it now (mic, agent session).
        if isFinished || Task.isCancelled {
            await engine.stop()
            if !isFinished { finish(.ended(.hungUp)) }
        }
    }

    func hangUp() async {
        await end(.hungUp)
    }

    var isFinished: Bool {
        switch phase {
        case .ended, .failed: return true
        default: return false
        }
    }

    // MARK: Events

    private func handle(_ event: VoiceEvent) {
        switch event {
        case .connected:
            // Never come back to life after a hang-up (the microphone would stay open without UI).
            guard !isFinished, phase == .connecting else {
                if isFinished { Task { await engine?.stop() } }
                return
            }
            phase = .active
            startedAt = Date()
            UIApplication.shared.isIdleTimerDisabled = true
            clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        case .turn(let turn):
            self.turn = turn
        case .levels(let agent, let user):
            let shown = displayedLevels(agent: agent, user: user, now: Date())
            agentLevel = shown.agent
            userLevel = shown.user
            levelHistory.removeFirst()
            levelHistory.append(turn == .speaking ? shown.agent : shown.user)
        case .subtitles(let lines):
            subtitles = lines.filter { !$0.text.isEmpty }
        case .ended(let reason):
            guard !isFinished else { return }
            switch reason {
            case .local: finish(.ended(.hungUp))
            case .agent: finish(.ended(.noahEnded))
            case .connectionLost: finish(.failed(reachability.isOnline ? .connectionLost : .offline))
            }
        }
    }

    // MARK: Levels

    private var levelShaper = LevelShaper()
    var usesSyntheticLevels: Bool { levelShaper.isSynthetic }

    private func displayedLevels(agent: Double, user: Double, now: Date) -> (agent: Double, user: Double) {
        levelShaper.levels(agent: agent, user: user, turn: turn, now: now)
    }

    private func tick() {
        guard let startedAt, phase == .active else { return }
        elapsed = Date().timeIntervalSince(startedAt)
        isNearMaxDuration = maxDuration - elapsed <= Self.wrapUpLead
        // Never cut Noah off mid-sentence: a minute before the end Noah is asked to say goodbye
        // (and normally ends the call himself); only after a short grace period do we hang up.
        if isNearMaxDuration, !wrapUpSent {
            wrapUpSent = true
            let engine = self.engine
            Task { await engine?.sendContext(Self.wrapUpContext) }
        }
        if Self.shouldEndForMaxDuration(elapsed: elapsed, maxDuration: maxDuration, turn: turn) {
            Task { await end(.maxDuration) }
        }
    }

    /// At the maximum duration, wait while Noah is still talking (the goodbye), up to the grace period.
    nonisolated static func shouldEndForMaxDuration(elapsed: TimeInterval, maxDuration: TimeInterval, turn: VoiceTurn) -> Bool {
        guard elapsed >= maxDuration else { return false }
        if turn == .speaking, elapsed < maxDuration + goodbyeGrace { return false }
        return true
    }

    private func end(_ kind: EndKind) async {
        guard !isFinished else { return }
        let engine = self.engine
        finish(.ended(kind))
        await engine?.stop()
    }

    private func fail(_ failure: Failure) {
        guard !isFinished else { return }
        finish(.failed(failure))
    }

    private func finish(_ phase: Phase) {
        self.phase = phase
        clock?.invalidate()
        clock = nil
        UIApplication.shared.isIdleTimerDisabled = false
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        cancellables.removeAll()
        agentLevel = 0
        userLevel = 0
        levelHistory = Array(repeating: 0, count: levelHistory.count)
    }

    private func reset() {
        turn = .listening
        subtitles = []
        elapsed = 0
        networkLost = false
        isNearMaxDuration = false
        isRecording = false
        wrapUpSent = false
        startedAt = nil
        engine = nil
    }

    /// An incoming phone call takes the audio away: end calmly and say why.
    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor in await self?.end(.interrupted) }
        }
    }

    private func observeNetwork() {
        reachability.$isOnline
            .removeDuplicates()
            .sink { [weak self] online in
                guard let self, self.phase == .active || self.phase == .connecting else { return }
                self.networkLost = !online
            }
            .store(in: &cancellables)
    }
}

/// Real audio levels when they arrive; otherwise a calm synthetic wave keyed on who is speaking,
/// so the orb and waveform never look frozen (e.g. when a device exposes no audio buffers).
struct LevelShaper {
    /// Below this a level counts as "no signal".
    static let silenceThreshold = 0.04
    /// How long without a real level before the synthetic wave takes over.
    static let fallbackDelay: TimeInterval = 0.5

    private var lastRealAgentLevelAt = Date.distantPast
    private var lastRealUserLevelAt = Date.distantPast
    private(set) var isSynthetic = false

    mutating func levels(agent: Double, user: Double, turn: VoiceTurn, now: Date) -> (agent: Double, user: Double) {
        if agent > Self.silenceThreshold { lastRealAgentLevelAt = now }
        if user > Self.silenceThreshold { lastRealUserLevelAt = now }
        let t = now.timeIntervalSinceReferenceDate
        var shownAgent = agent
        var shownUser = user
        isSynthetic = false
        switch turn {
        case .speaking where now.timeIntervalSince(lastRealAgentLevelAt) > Self.fallbackDelay:
            // Speech-like: a slow swell with faster syllable ripples.
            shownAgent = 0.42 + 0.2 * sin(t * 5.3) + 0.14 * sin(t * 13.7 + 1.3) + 0.06 * sin(t * 29.1)
            isSynthetic = true
        case .listening where now.timeIntervalSince(lastRealUserLevelAt) > Self.fallbackDelay:
            // Quiet "breathing" so it is visible that Noah is listening.
            shownUser = 0.07 + 0.04 * sin(t * 2.1)
            isSynthetic = true
        case .thinking:
            shownAgent = max(agent, 0.05 + 0.03 * sin(t * 6))
        default:
            break
        }
        return (min(max(shownAgent, 0), 1), min(max(shownUser, 0), 1))
    }
}
