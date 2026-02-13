import SwiftUI

// MARK: - Design System for Elderly Companion
// Calm. Dignified. Always There.
//
// Design principles:
// - Large touch targets (minimum 56pt)
// - Generous spacing
// - Soft, warm color palette
// - High contrast for readability
// - Dynamic Type support throughout

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

// MARK: - Color Palette

extension Color {
    // Primary - warm sage green (calm, natural)
    static let companionPrimary = Color(red: 0.42, green: 0.56, blue: 0.47)
    static let companionPrimaryLight = Color(red: 0.85, green: 0.91, blue: 0.87)
    static let companionPrimaryDark = Color(red: 0.28, green: 0.40, blue: 0.32)

    // Secondary - warm amber (inviting, gentle)
    static let companionSecondary = Color(red: 0.82, green: 0.68, blue: 0.47)
    static let companionSecondaryLight = Color(red: 0.95, green: 0.91, blue: 0.83)

    // Background - soft warm whites
    static let companionBackground = Color(red: 0.98, green: 0.97, blue: 0.95)
    static let companionSurface = Color.white
    static let companionSurfaceSecondary = Color(red: 0.96, green: 0.95, blue: 0.93)

    // Text
    static let companionTextPrimary = Color(red: 0.16, green: 0.16, blue: 0.14)
    static let companionTextSecondary = Color(red: 0.45, green: 0.44, blue: 0.42)
    static let companionTextTertiary = Color(red: 0.65, green: 0.63, blue: 0.60)

    // Accent colors
    static let companionSuccess = Color(red: 0.40, green: 0.65, blue: 0.45)
    static let companionWarning = Color(red: 0.85, green: 0.65, blue: 0.30)
    static let companionDanger = Color(red: 0.80, green: 0.35, blue: 0.35)
    static let companionInfo = Color(red: 0.40, green: 0.55, blue: 0.75)

    // Voice / Conversation
    static let companionVoiceActive = Color(red: 0.42, green: 0.56, blue: 0.47)
    static let companionVoiceIdle = Color(red: 0.75, green: 0.73, blue: 0.70)
}

// MARK: - Typography

extension Font {
    /// Extra large display text for the main "Talk Now" button
    static let companionDisplay = Font.system(size: 34, weight: .bold, design: .rounded)
    /// Large title for screen headers
    static let companionTitle = Font.system(size: 28, weight: .semibold, design: .rounded)
    /// Subtitle / section headers
    static let companionHeadline = Font.system(size: 22, weight: .semibold, design: .rounded)
    /// Body text - slightly larger than default for readability
    static let companionBody = Font.system(size: 18, weight: .regular, design: .rounded)
    /// Secondary body text
    static let companionBodySecondary = Font.system(size: 16, weight: .regular, design: .rounded)
    /// Caption text
    static let companionCaption = Font.system(size: 14, weight: .regular, design: .rounded)
    /// Small label text
    static let companionLabel = Font.system(size: 13, weight: .medium, design: .rounded)
}
