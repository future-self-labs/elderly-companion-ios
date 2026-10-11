import SwiftUI

enum NoahButtonKind {
    /// Amber, for the one main action on a screen.
    case primary
    /// Surface with outline, for secondary actions.
    case secondary
    /// Coral, for hang-up and destructive actions.
    case destructive
    /// Text-only amber, for tertiary actions.
    case quiet
}

enum NoahButtonSize {
    /// Caregiver interface.
    case regular
    /// Older person's interface: taller, bigger text.
    case elder
    /// Inline/compact (still ≥ 44 pt tall).
    case compact
}

struct NoahButtonStyle: ButtonStyle {
    var kind: NoahButtonKind = .primary
    var size: NoahButtonSize = .regular
    var fullWidth: Bool = true

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .multilineTextAlignment(.center)
            .foregroundColor(foreground)
            .padding(.horizontal, size == .compact ? NoahSpacing.m : NoahSpacing.l)
            .padding(.vertical, size == .elder ? NoahSpacing.m : NoahSpacing.xs)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: minHeight)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(kind == .secondary ? NoahColor.border : .clear, lineWidth: NoahSize.borderWidth)
            )
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(NoahMotion.quick, value: configuration.isPressed)
    }

    private var font: Font {
        switch size {
        case .elder: return NoahFont.Elder.button
        case .regular: return NoahFont.button
        case .compact: return NoahFont.semibold(15, relativeTo: .subheadline)
        }
    }

    private var minHeight: CGFloat {
        switch size {
        case .elder: return NoahSize.elderButton
        case .regular: return NoahSize.button
        case .compact: return NoahSize.minTap
        }
    }

    private var radius: CGFloat { size == .compact ? NoahRadius.medium : NoahRadius.large }

    private var foreground: Color {
        switch kind {
        case .primary: return NoahColor.onAccent
        case .secondary: return NoahColor.text
        case .destructive: return NoahColor.onDanger
        case .quiet: return NoahColor.accent
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return NoahColor.accent
        case .secondary: return NoahColor.surface
        case .destructive: return NoahColor.danger
        case .quiet: return .clear
        }
    }
}

extension ButtonStyle where Self == NoahButtonStyle {
    static func noah(_ kind: NoahButtonKind = .primary, size: NoahButtonSize = .regular, fullWidth: Bool = true) -> NoahButtonStyle {
        NoahButtonStyle(kind: kind, size: size, fullWidth: fullWidth)
    }
}

/// A button that runs an async action and shows a spinner while it runs (and blocks double taps).
struct NoahAsyncButton<Label: View>: View {
    var kind: NoahButtonKind = .primary
    var size: NoahButtonSize = .regular
    var fullWidth: Bool = true
    let action: () async -> Void
    @ViewBuilder var label: () -> Label

    @State private var isRunning = false

    var body: some View {
        Button {
            guard !isRunning else { return }
            isRunning = true
            Task {
                await action()
                isRunning = false
            }
        } label: {
            ZStack {
                label().opacity(isRunning ? 0 : 1)
                if isRunning {
                    ProgressView()
                        .tint(kind == .primary || kind == .destructive ? NoahColor.onAccent : NoahColor.accent)
                        .accessibilityLabel(Text("Bezig…"))
                }
            }
        }
        .buttonStyle(.noah(kind, size: size, fullWidth: fullWidth))
        // Not `.disabled`: the button keeps full contrast while the spinner shows.
        .allowsHitTesting(!isRunning)
        .accessibilityAddTraits(isRunning ? .updatesFrequently : [])
    }
}

extension NoahAsyncButton where Label == Text {
    init(_ title: LocalizedStringKey, kind: NoahButtonKind = .primary, size: NoahButtonSize = .regular, fullWidth: Bool = true, action: @escaping () async -> Void) {
        self.kind = kind
        self.size = size
        self.fullWidth = fullWidth
        self.action = action
        self.label = { Text(title) }
    }
}

/// Icon + text label laid out for buttons; stacks vertically at accessibility sizes.
struct NoahButtonLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        HStack(spacing: NoahSpacing.s) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
        }
    }
}
