import SwiftUI

struct LargeButton: View {
    let title: String
    let icon: String?
    let style: ButtonStyle
    let action: () -> Void

    enum ButtonStyle {
        case primary
        case secondary
        case outline
        case danger

        var backgroundColor: Color {
            switch self {
            case .primary: return .companionPrimary
            case .secondary: return .companionSecondary
            case .outline: return .clear
            case .danger: return .companionDanger
            }
        }

        var foregroundColor: Color {
            switch self {
            case .primary: return .white
            case .secondary: return .white
            case .outline: return .companionPrimary
            case .danger: return .white
            }
        }

        var borderColor: Color {
            switch self {
            case .outline: return .companionPrimary
            default: return .clear
            }
        }
    }

    init(
        _ title: String,
        icon: String? = nil,
        style: ButtonStyle = .primary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: CompanionTheme.Spacing.md) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                }
                Text(title)
                    .font(.companionHeadline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(style.backgroundColor)
            .foregroundStyle(style.foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: CompanionTheme.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: CompanionTheme.Radius.lg)
                    .stroke(style.borderColor, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 16) {
        LargeButton("Talk Now", icon: "mic.fill") {}
        LargeButton("Call AI", icon: "phone.fill", style: .secondary) {}
        LargeButton("Settings", icon: "gear", style: .outline) {}
    }
    .padding()
}
