import AVFoundation
import Combine
import Foundation

/// Plays one recorded conversation (v2.1). The signed URL (valid ~15 min) is fetched when the
/// person taps play, and fetched again when it expired: on resume after a long pause, or when
/// playback fails (an expired URL answers 403). Only one recording plays at a time.
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
        player?.pause()
        if state == .playing { state = .paused }
    }

    func seek(to seconds: Double) {
        let target = max(0, min(seconds, duration ?? seconds))
        position = target
        player?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    /// Stops and releases the player (screen closed).
    func stop() {
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

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, self.state == .playing, time.seconds.isFinite else { return }
                self.position = time.seconds
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
