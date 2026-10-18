import SwiftUI

/// Players for recorded conversations (v2.1). The `RecordingPlayer` fetches the signed URL on tap.

/// "1:05" / "12:14"
enum PlaybackTime {
    static func text(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "–:––" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600, minutes = (total % 3600) / 60, rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }
}

/// Card for the caregiver interface: a big round play button, a title ("Luister naar Wim"),
/// the time and a scrubber.
struct RecordingPlayerCard: View {
    @ObservedObject var player: RecordingPlayer
    let title: String
    var subtitle: String?

    var body: some View {
        NoahCard(padding: NoahSpacing.m, background: NoahColor.surface, border: NoahColor.accent.opacity(0.6)) {
            HStack(alignment: .center, spacing: NoahSpacing.m) {
                RecordingPlayButton(player: player, diameter: 60)
                VStack(alignment: .leading, spacing: NoahSpacing.xxs) {
                    Text(verbatim: title)
                        .font(NoahFont.headline)
                        .foregroundColor(NoahColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: statusLine)
                        .font(NoahFont.footnote)
                        .foregroundColor(NoahColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if player.state != .idle, let duration = player.duration, duration > 0 {
                Slider(value: Binding(get: { min(player.position, duration) }, set: { player.seek(to: $0) }), in: 0...duration) {
                    Text("Positie in de opname")
                }
                .tint(NoahColor.accent)
                .accessibilityValue(Text(verbatim: "\(PlaybackTime.text(player.position)) van \(PlaybackTime.text(duration))"))
            }
            if let error = player.error {
                NoahNotice(kind: .warning, text: error.code == "geen_opname" ? "Er is geen opname (meer) van dit gesprek." : error.userMessage)
            }
        }
        .onDisappear { player.stop() }
    }

    private var statusLine: String {
        switch player.state {
        case .loading: return "Opname wordt geladen…"
        case .playing, .paused:
            return "\(PlaybackTime.text(player.position)) / \(PlaybackTime.text(player.duration))"
        default:
            return subtitle ?? (player.duration.map { "Opname van \(PlaybackTime.text($0))" } ?? "Opname")
        }
    }
}

/// Round amber play/pause button with a spinner while loading.
struct RecordingPlayButton: View {
    @ObservedObject var player: RecordingPlayer
    var diameter: CGFloat = 60

    var body: some View {
        Button { player.toggle() } label: {
            ZStack {
                Circle().fill(NoahColor.accent)
                if player.isLoading {
                    ProgressView().tint(NoahColor.onAccent)
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: diameter * 0.38, weight: .bold))
                        .foregroundColor(NoahColor.onAccent)
                        .offset(x: player.isPlaying ? 0 : diameter * 0.03)
                }
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(OrbPressStyle())
        .accessibilityLabel(Text(player.isPlaying ? "Pauzeer de opname" : "Speel de opname af"))
        .accessibilityIdentifier("recording.play")
    }
}

/// Small "Luister" capsule for list rows (≥ 44 pt).
struct RecordingInlineButton: View {
    @StateObject private var player: RecordingPlayer

    init(startSeconds: Double? = nil, fetch: @escaping () async throws -> ConversationAudio) {
        _player = StateObject(wrappedValue: RecordingPlayer(startSeconds: startSeconds, fetch: fetch))
    }

    var body: some View {
        Button { player.toggle() } label: {
            HStack(spacing: NoahSpacing.xs) {
                if player.isLoading {
                    ProgressView().tint(NoahColor.onAccent).controlSize(.small)
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .accessibilityHidden(true)
                }
                Text(verbatim: label)
                    .monospacedDigit()
            }
            .font(NoahFont.semibold(15, relativeTo: .subheadline))
            .foregroundColor(NoahColor.onAccent)
            .padding(.horizontal, NoahSpacing.m)
            .frame(minHeight: NoahSize.minTap)
            .background(Capsule().fill(NoahColor.accent))
            .contentShape(Capsule())
        }
        .buttonStyle(OrbPressStyle())
        .accessibilityLabel(Text(player.isPlaying ? "Pauzeer de opname" : "Luister naar de opname"))
        .onDisappear { player.stop() }
    }

    private var label: String {
        switch player.state {
        case .playing, .paused: return PlaybackTime.text(player.position)
        case .failed: return "Geen opname"
        default: return "Luister"
        }
    }
}

/// The older person's player: one huge button and a simple progress bar.
struct ElderRecordingPlayer: View {
    @ObservedObject var player: RecordingPlayer
    let title: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.s) {
            Button { player.toggle() } label: {
                ZStack {
                    NoahButtonLabel(title: player.isPlaying ? "Pauzeer" : title,
                                    systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                        .opacity(player.isLoading ? 0 : 1)
                    if player.isLoading { ProgressView().tint(NoahColor.onAccent) }
                }
            }
            .buttonStyle(.noah(.primary, size: .elder))
            .accessibilityIdentifier("elder.listen")

            if player.state != .idle, let duration = player.duration, duration > 0, player.error == nil {
                ProgressView(value: min(player.position, duration), total: duration)
                    .tint(NoahColor.accent)
                    .accessibilityHidden(true)
                Text(verbatim: "\(PlaybackTime.text(player.position)) van \(PlaybackTime.text(duration))")
                    .font(NoahFont.Elder.label)
                    .foregroundColor(NoahColor.textSecondary)
                    .monospacedDigit()
            }
            if let error = player.error {
                NoahNotice(kind: .warning, text: error.code == "geen_opname" ? "Van dit verhaal is geen opname." : error.elderMessage, large: true)
            }
        }
        .onDisappear { player.stop() }
    }
}

/// Calm "Wordt opgenomen als u ja zegt" pill with a red dot, shown during a conversation the server
/// records. Noah asks permission itself as its first message; the app cannot see the answer, so the
/// wording stays conditional (backend v2.1 note).
struct RecordingIndicator: View {
    /// One short line for accessibility text sizes.
    var compact = false

    var body: some View {
        if compact {
            HStack(spacing: NoahSpacing.xs) {
                Circle()
                    .fill(NoahColor.recording)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text("Opname als u ja zegt")
                    .foregroundColor(NoahColor.text)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Dit gesprek wordt opgenomen als u ja zegt"))
            .accessibilityIdentifier("conversation.recording")
        } else {
            full
        }
    }

    private var full: some View {
        HStack(spacing: NoahSpacing.xs) {
            Circle()
                .fill(NoahColor.recording)
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Wordt opgenomen")
                    .font(NoahFont.Elder.bodyStrong)
                    .foregroundColor(NoahColor.text)
                Text("als u ja zegt")
                    .font(NoahFont.Elder.label)
                    .foregroundColor(NoahColor.textSoft)
            }
            .fixedSize(horizontal: false, vertical: true)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .padding(.horizontal, NoahSpacing.m)
        .padding(.vertical, NoahSpacing.xs)
        .background(RoundedRectangle(cornerRadius: NoahRadius.large, style: .continuous).fill(NoahColor.surface))
        .overlay(RoundedRectangle(cornerRadius: NoahRadius.large, style: .continuous).strokeBorder(NoahColor.cardBorder, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Dit gesprek wordt opgenomen als u ja zegt"))
        .accessibilityIdentifier("conversation.recording")
    }
}
