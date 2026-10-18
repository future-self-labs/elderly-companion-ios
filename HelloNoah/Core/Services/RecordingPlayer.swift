import AVFoundation
import Combine
import Foundation

/// Plays one recorded conversation (v2.1). The signed URL (valid ~15 min) is fetched when the
/// person taps play, and fetched again when it expired: on resume after a long pause, when
/// playback fails or stalls after `expiresAt`, or when the server answers `403 link_verlopen`
/// (seen in the item's error log). The shown state follows the player's real state (a phone
/// call pauses it). Only one recording plays at a time.
@MainActor
final class RecordingPlayer: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case playing
        case paused
        case finished
        case failed(APIError)
    }

    @Published private(set) var state: State = .idle
    /// Seconds into the recording.
    @Published private(set) var position: Double
    @Published private(set) var duration: Double?

    /// Where playback starts (a life-story fragment), 0 = the beginning.
    let startSeconds: Double
    private let fetch: () async throws -> ConversationAudio
    private var audio: ConversationAudio?
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var observers = Set<AnyCancellable>()
    private var pendingStart: Double = 0
    private var retriedWithFreshURL = false

    /// The player that is playing now; starting another one pauses it.
    private static weak var current: RecordingPlayer?
    private var interruptionObserver: NSObjectProtocol?
    private var resumeAfterInterruption = false
    private var lastLinkRefresh: Date?

    /// Pauses whatever recording is playing (a conversation with Noah is about to start).
    static func pauseCurrent() {
        current?.pause()
    }

    init(startSeconds: Double? = nil, durationHint: Double? = nil, fetch: @escaping () async throws -> ConversationAudio) {
        self.startSeconds = max(0, startSeconds ?? 0)
        self.position = max(0, startSeconds ?? 0)
        self.duration = durationHint
        self.fetch = fetch
    }

    var isPlaying: Bool { state == .playing }
    var isLoading: Bool { state == .loading }

    var error: APIError? {
        if case .failed(let error) = state { return error }
        return nil
    }

    /// A signed URL counts as expired a little before its `expiresAt`, so a resume never races it.
    nonisolated static func needsFreshURL(expiresAt: Date?, now: Date, margin: TimeInterval = 30) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) < margin
    }

    func toggle() {
        Task { await togglePlayback() }
    }

    func togglePlayback() async {
        switch state {
        case .loading:
            return
        case .playing:
            pause()
        case .paused:
            if player != nil, !Self.needsFreshURL(expiresAt: audio?.expiresAt, now: Date()) {
                resume()
            } else {
                await load(from: position)
            }
        case .idle, .finished:
            await load(from: startSeconds)
        case .failed:
            retriedWithFreshURL = false
            await load(from: position)
        }
    }

    func pause() {
        resumeAfterInterruption = false
        player?.pause()
        if state == .playing || state == .loading { state = .paused }
    }

    func seek(to seconds: Double) {
        let target = max(0, min(seconds, duration ?? seconds))
        position = target
        player?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    /// Stops and releases the player (screen closed).
    func stop() {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        teardown()
        if state == .playing || state == .loading { state = .paused }
        if Self.current === self {
            Self.current = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // MARK: Internals

    private func resume() {
        claimPlayback()
        player?.play()
        state = .playing
    }

    private func load(from seconds: Double) async {
        state = .loading
        do {
            let audio = try await fetch()
            self.audio = audio
            if let total = audio.durationSeconds, total > 0 { duration = total }
            start(url: audio.url, from: seconds)
        } catch {
            let apiError = APIError.from(error)
            state = apiError == .cancelled ? .idle : .failed(apiError)
        }
    }

    private func start(url: URL, from seconds: Double) {
        teardown()
        claimPlayback()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        observeInterruptions()

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        pendingStart = seconds

        item.publisher(for: \.status)
            .receive(on: RunLoop.main)
            .sink { [weak self, weak item] status in
                guard let self, let item else { return }
                switch status {
                case .readyToPlay:
                    let total = item.duration.seconds
                    if total.isFinite, total > 0 { self.duration = total }
                    guard self.state == .loading else { return }
                    let start = min(self.pendingStart, max(0, (self.duration ?? self.pendingStart) - 1))
                    player.seek(to: CMTime(seconds: start, preferredTimescale: 600)) { _ in
                        Task { @MainActor in
                            guard self.state == .loading, self.player === player else { return }
                            player.play()
                            self.position = start
                            self.state = .playing
                            self.retriedWithFreshURL = false
                        }
                    }
                case .failed:
                    self.playbackFailed()
                default:
                    break
                }
            }
            .store(in: &observers)

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.state = .finished
                self.position = self.startSeconds
            }
            .store(in: &observers)

        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.playbackFailed() }
            .store(in: &observers)

        // A stall after the link expired is an expired link (the next Range request answers 403).
        NotificationCenter.default.publisher(for: .AVPlayerItemPlaybackStalled, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, Self.needsFreshURL(expiresAt: self.audio?.expiresAt, now: Date(), margin: 0) else { return }
                self.refreshExpiredLink()
            }
            .store(in: &observers)

        // `403 link_verlopen` shows up in the access/error log before (or instead of) a failure.
        NotificationCenter.default.publisher(for: .AVPlayerItemNewErrorLogEntry, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self, weak item] _ in
                guard let self, let item, let event = item.errorLog()?.events.last,
                      Self.isExpiredLinkStatus(event.errorStatusCode) else { return }
                self.refreshExpiredLink()
            }
            .store(in: &observers)

        // Keep the shown state in line with what the player really does (route change, Siri,
        // another app taking the audio).
        player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self, weak player] status in
                guard let self, let player, self.player === player else { return }
                if status == .paused, self.state == .playing { self.state = .paused }
                if status == .playing, self.state == .paused { self.state = .playing }
            }
            .store(in: &observers)

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, self.state == .playing, time.seconds.isFinite else { return }
                self.position = time.seconds
            }
        }
    }

    nonisolated static func isExpiredLinkStatus(_ status: Int) -> Bool { status == 403 || status == 410 }

    /// The signed link ran out mid-stream: fetch a fresh one and continue where we were.
    private func refreshExpiredLink() {
        guard state == .playing || state == .loading else { return }
        // A fresh link that is refused at once is not an expiry: fall back to the one-shot retry.
        if let last = lastLinkRefresh, Date().timeIntervalSince(last) < 30 { return playbackFailed() }
        lastLinkRefresh = Date()
        retriedWithFreshURL = false
        playbackFailed()
    }

    /// A phone call (or another app) took the audio: show "paused", and continue afterwards
    /// when iOS says we may.
    private func observeInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            Task { @MainActor in
                guard let self, Self.current === self else { return }
                switch type {
                case .began:
                    let wasPlaying = self.state == .playing
                    self.player?.pause()
                    if wasPlaying { self.state = .paused }
                    self.resumeAfterInterruption = wasPlaying
                case .ended:
                    if self.resumeAfterInterruption, options.contains(.shouldResume) {
                        self.resumeAfterInterruption = false
                        await self.togglePlayback()
                    }
                @unknown default:
                    break
                }
            }
        }
    }

    /// Most likely the signed URL expired: fetch a fresh one once and continue where we were.
    private func playbackFailed() {
        let resumeAt = position
        teardown()
        guard !retriedWithFreshURL else {
            state = .failed(.unexpected("Afspelen lukt niet"))
            return
        }
        retriedWithFreshURL = true
        Task { await load(from: resumeAt) }
    }

    private func claimPlayback() {
        if let current = Self.current, current !== self { current.pause() }
        Self.current = self
    }

    private func teardown() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        observers.removeAll()
        player?.pause()
        player = nil
    }
}
