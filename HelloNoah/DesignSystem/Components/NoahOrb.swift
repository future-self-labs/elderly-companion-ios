import SwiftUI

/// What the orb is showing. Drives its animation.
enum OrbActivity: Equatable {
    case idle
    case connecting
    case listening
    case thinking
    case speaking
}

/// Noah's visual presence: a warm amber orb with a halo that breathes when idle and swells with
/// the audio level while Noah speaks. Respects Reduce Motion (static halo, no pulsing).
///
/// The breathing and spinning are computed from the clock (`TimelineView`) rather than with
/// `repeatForever` animations, which in SwiftUI can leak into the layout of surrounding views.
struct NoahOrb: View {
    var activity: OrbActivity = .idle
    /// 0…1, current audio level (Noah while speaking, the user while listening).
    var level: Double = 0
    var diameter: CGFloat = NoahSize.orb

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let breath = reduceMotion ? 0 : (sin(time * 2 * .pi / 5.2) + 1) / 2 // 0…1, 5.2 s cycle
            let spin = reduceMotion ? 0 : (time * 220).truncatingRemainder(dividingBy: 360)
            orb(breath: breath, spin: spin)
        }
        .frame(width: diameter * 1.25, height: diameter * 1.25)
        .accessibilityHidden(true)
    }

    private func orb(breath: Double, spin: Double) -> some View {
        let pulse = reduceMotion ? 0 : min(max(level, 0), 1)
        return ZStack {
            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [NoahColor.accent.opacity(0.32), NoahColor.accent.opacity(0.0)],
                        center: .center,
                        startRadius: diameter * 0.35,
                        endRadius: diameter * 0.85
                    )
                )
                .frame(width: diameter * 1.7, height: diameter * 1.7)
                .scaleEffect(1 + pulse * 0.18 + breath * 0.05)

            // Halo ring
            Circle()
                .strokeBorder(NoahColor.accent.opacity(activity == .listening ? 0.55 : 0.28), lineWidth: 2)
                .frame(width: diameter * 1.22, height: diameter * 1.22)
                .scaleEffect(1 + pulse * 0.12 + breath * 0.02)

            if activity == .thinking || activity == .connecting {
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(NoahColor.accentHighlight, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: diameter * 1.22, height: diameter * 1.22)
                    .rotationEffect(.degrees(spin))
            }

            // Core
            Circle()
                .fill(
                    LinearGradient(
                        colors: [NoahColor.accentHighlight, NoahColor.accent, NoahColor.accentDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: diameter, height: diameter)
                .shadow(color: NoahColor.accent.opacity(0.45), radius: diameter * 0.14)
                .scaleEffect(1 + pulse * 0.05 + breath * 0.015)
        }
        .frame(width: diameter * 1.25, height: diameter * 1.25)
    }
}

/// Vertical bars showing recent audio levels (newest on the right).
struct WaveformView: View {
    /// 0…1 values, oldest first.
    let levels: [Double]
    var color: Color = NoahColor.accent
    var maxHeight: CGFloat = 64

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, value in
                let clamped = min(max(value, 0), 1)
                Capsule()
                    .fill(color.opacity(0.35 + 0.65 * clamped))
                    .frame(width: 6, height: max(6, maxHeight * (reduceMotion ? 0.25 + 0.5 * clamped : clamped)))
            }
        }
        .frame(height: maxHeight)
        .accessibilityHidden(true)
    }
}
