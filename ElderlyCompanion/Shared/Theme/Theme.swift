import SwiftUI

// MARK: - Theme Protocol

enum AppTheme: String, CaseIterable, Identifiable {
    case calm
    case apple

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .calm: return "Calm"
        case .apple: return "Apple"
        }
    }

    var description: String {
        switch self {
        case .calm: return "Warm, soft, natural"
        case .apple: return "Clean, glass, minimal"
        }
    }
}

// MARK: - Global Theme Manager

@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    var current: AppTheme {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: "selectedTheme")
        }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: "selectedTheme") ?? "calm"
        self.current = AppTheme(rawValue: stored) ?? .calm
    }
}

// MARK: - Design Tokens

enum CompanionTheme {

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
    }

    // MARK: - Corner Radius

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let full: CGFloat = 999
    }

    // MARK: - Minimum Touch Target

    static let minTouchTarget: CGFloat = 56
}

// MARK: - Dynamic Colors (resolve based on active theme)

extension Color {

    private static var theme: AppTheme { ThemeManager.shared.current }

    // Primary
    static var companionPrimary: Color {
        theme == .apple
            ? Color(red: 0.00, green: 0.48, blue: 1.00)  // iOS blue
            : Color(red: 0.42, green: 0.56, blue: 0.47)   // sage green
    }
    static var companionPrimaryLight: Color {
        theme == .apple
            ? Color(red: 0.90, green: 0.95, blue: 1.00)
            : Color(red: 0.85, green: 0.91, blue: 0.87)
    }
    static var companionPrimaryDark: Color {
        theme == .apple
            ? Color(red: 0.00, green: 0.35, blue: 0.80)
            : Color(red: 0.28, green: 0.40, blue: 0.32)
    }

    // Secondary
    static var companionSecondary: Color {
        theme == .apple
            ? Color(red: 0.55, green: 0.36, blue: 0.90)   // purple accent
            : Color(red: 0.82, green: 0.68, blue: 0.47)    // warm amber
    }
    static var companionSecondaryLight: Color {
        theme == .apple
            ? Color(red: 0.93, green: 0.90, blue: 1.00)
            : Color(red: 0.95, green: 0.91, blue: 0.83)
    }

    // Background
    static var companionBackground: Color {
        theme == .apple
            ? Color(uiColor: .systemGroupedBackground)
            : Color(red: 0.98, green: 0.97, blue: 0.95)
    }
    static var companionSurface: Color {
        theme == .apple
            ? Color(uiColor: .secondarySystemGroupedBackground)
            : Color.white
    }
    static var companionSurfaceSecondary: Color {
        theme == .apple
            ? Color(uiColor: .tertiarySystemGroupedBackground)
            : Color(red: 0.91, green: 0.89, blue: 0.86)
    }

    // Text
    static var companionTextPrimary: Color {
        theme == .apple
            ? Color(uiColor: .label)
            : Color(red: 0.16, green: 0.16, blue: 0.14)
    }
    static var companionTextSecondary: Color {
        theme == .apple
            ? Color(uiColor: .secondaryLabel)
            : Color(red: 0.45, green: 0.44, blue: 0.42)
    }
    static var companionTextTertiary: Color {
        theme == .apple
            ? Color(uiColor: .tertiaryLabel)
            : Color(red: 0.55, green: 0.53, blue: 0.50)
    }

    // Accent colors
    static var companionSuccess: Color {
        theme == .apple
            ? Color(red: 0.20, green: 0.78, blue: 0.35)   // iOS green
            : Color(red: 0.40, green: 0.65, blue: 0.45)
    }
    static var companionWarning: Color {
        theme == .apple
            ? Color(red: 1.00, green: 0.58, blue: 0.00)    // iOS orange
            : Color(red: 0.85, green: 0.65, blue: 0.30)
    }
    static var companionDanger: Color {
        theme == .apple
            ? Color(red: 1.00, green: 0.23, blue: 0.19)    // iOS red
            : Color(red: 0.80, green: 0.35, blue: 0.35)
    }
    static var companionInfo: Color {
        theme == .apple
            ? Color(red: 0.35, green: 0.68, blue: 0.95)    // iOS teal-blue
            : Color(red: 0.40, green: 0.55, blue: 0.75)
    }

    // Voice / Conversation
    static var companionVoiceActive: Color {
        theme == .apple
            ? Color(red: 0.00, green: 0.48, blue: 1.00)
            : Color(red: 0.42, green: 0.56, blue: 0.47)
    }
    static var companionVoiceIdle: Color {
        theme == .apple
            ? Color(uiColor: .systemGray4)
            : Color(red: 0.75, green: 0.73, blue: 0.70)
    }
}

// MARK: - Dynamic Typography

extension Font {
    private static var design: Font.Design {
        ThemeManager.shared.current == .apple ? .default : .rounded
    }

    static var companionDisplay: Font { .system(size: 34, weight: .bold, design: design) }
    static var companionTitle: Font { .system(size: 28, weight: .semibold, design: design) }
    static var companionHeadline: Font { .system(size: 22, weight: .semibold, design: design) }
    static var companionBody: Font { .system(size: 18, weight: .regular, design: design) }
    static var companionBodySecondary: Font { .system(size: 16, weight: .regular, design: design) }
    static var companionCaption: Font { .system(size: 14, weight: .regular, design: design) }
    static var companionLabel: Font { .system(size: 13, weight: .medium, design: design) }
}

// MARK: - Apple Theme Specific: Glass & Gradient Modifiers

extension View {
    /// Applies glass morphism effect (Apple theme) or plain card (Calm theme)
    @ViewBuilder
    func glassCard() -> some View {
        if ThemeManager.shared.current == .apple {
            self
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: CompanionTheme.Radius.lg))
        } else {
            self
                .background(Color.companionSurface)
                .clipShape(RoundedRectangle(cornerRadius: CompanionTheme.Radius.lg))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
    }
}

// MARK: - AI Gradient

extension LinearGradient {
    /// A subtle AI-inspired gradient for the Apple theme
    static var aiGradient: LinearGradient {
        if ThemeManager.shared.current == .apple {
            return LinearGradient(
                colors: [
                    Color(red: 0.00, green: 0.48, blue: 1.00),
                    Color(red: 0.55, green: 0.36, blue: 0.90),
                    Color(red: 0.90, green: 0.30, blue: 0.65),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 0.42, green: 0.56, blue: 0.47),
                    Color(red: 0.35, green: 0.50, blue: 0.42),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    /// Lighter version for backgrounds
    static var aiGradientSubtle: LinearGradient {
        if ThemeManager.shared.current == .apple {
            return LinearGradient(
                colors: [
                    Color(red: 0.90, green: 0.95, blue: 1.00),
                    Color(red: 0.95, green: 0.90, blue: 1.00),
                    Color(red: 1.00, green: 0.92, blue: 0.96),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 0.85, green: 0.91, blue: 0.87),
                    Color(red: 0.90, green: 0.93, blue: 0.88),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
