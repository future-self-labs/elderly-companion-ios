import SwiftUI

// HelloNoah design tokens — direction "B · Avond" (evening).
//
// This file is the single source of truth for colour, type, spacing, radii and sizes. It is
// compiled into both the app and the widget. Feature views must only use these tokens (directly
// or through the components in HelloNoah/DesignSystem); never hard-code colours or font names.
// A redesign should only need to touch this file (plus the components, for shape changes).

// MARK: - Colour

enum NoahColor {
    /// Main background ("ground").
    static let ground = Color(hex: 0x13203A)
    /// Cards, rows, inputs.
    static let surface = Color(hex: 0x1D2D4D)
    /// Recessed areas: conversation background, tab bar, sheets.
    static let surfaceDeep = Color(hex: 0x0E182D)
    /// Outlines of cards and inputs.
    static let border = Color(hex: 0x34466B)
    /// Hairlines between rows.
    static let divider = Color(hex: 0x2A3C60)

    /// Primary text (warm off-white).
    static let text = Color(hex: 0xF5EFE4)
    /// Body text that should feel slightly quieter than `text`.
    static let textSoft = Color(hex: 0xD6DCE7)
    /// Labels, metadata, captions.
    static let textSecondary = Color(hex: 0xB9C2D3)

    /// Amber accent: primary actions, the Noah orb, highlights.
    static let accent = Color(hex: 0xF2B84B)
    /// Lighter and deeper amber for the orb's gradient.
    static let accentHighlight = Color(hex: 0xF8D58C)
    static let accentDeep = Color(hex: 0xD99630)
    /// Text and icons placed on `accent`.
    static let onAccent = Color(hex: 0x13203A)
    /// Hang up, destructive actions, urgent alerts.
    static let danger = Color(hex: 0xE2725B)
    /// Text and icons placed on `danger`.
    static let onDanger = Color(hex: 0x13203A)
    /// Calm positive state (good mood, "afgehandeld").
    static let positive = Color(hex: 0x8FD3A8)
    /// Text and icons placed on `positive`.
    static let onPositive = Color(hex: 0x13203A)

    /// Soft amber wash used behind the orb and selected chips.
    static let accentGlow = Color(hex: 0xF2B84B, opacity: 0.22)
    static let dangerSoft = Color(hex: 0xE2725B, opacity: 0.18)
    static let positiveSoft = Color(hex: 0x8FD3A8, opacity: 0.18)

    /// Mood scale 1…5 (somber → heel goed). All pass WCAG AA on `ground` and `surface`.
    static func mood(_ score: Double?) -> Color {
        guard let score else { return textSecondary }
        switch score {
        case ..<1.5: return Color(hex: 0xE2725B)
        case ..<2.5: return Color(hex: 0xEC9A62)
        case ..<3.5: return Color(hex: 0xF2B84B)
        case ..<4.5: return Color(hex: 0xC3D98C)
        default: return Color(hex: 0x8FD3A8)
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Typography

/// Font families. DM Serif Display for titles, Lexend for all copy (both OFL, bundled).
enum NoahFontFamily {
    static let display = "DMSerifDisplay-Regular"
    static let body = "Lexend-Regular"
    static let bodySemibold = "Lexend-SemiBold"
}

/// Every text style scales with Dynamic Type through `relativeTo:`.
enum NoahFont {
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom(NoahFontFamily.display, size: size, relativeTo: style)
    }

    static func body(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(NoahFontFamily.body, size: size, relativeTo: style)
    }

    static func semibold(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(NoahFontFamily.bodySemibold, size: size, relativeTo: style)
    }

    // Caregiver interface (standard iOS scale, informal "je").
    static let largeTitle = display(34, relativeTo: .largeTitle)
    static let title = display(28, relativeTo: .title)
    static let title2 = display(24, relativeTo: .title2)
    static let title3 = display(21, relativeTo: .title3)
    static let headline = semibold(17, relativeTo: .headline)
    static let bodyText = body(17, relativeTo: .body)
    static let bodyStrong = semibold(17, relativeTo: .body)
    static let callout = body(16, relativeTo: .callout)
    static let subheadline = body(15, relativeTo: .subheadline)
    static let footnote = body(13, relativeTo: .footnote)
    static let caption = body(12, relativeTo: .caption)
    static let captionStrong = semibold(12, relativeTo: .caption)
    static let button = semibold(17, relativeTo: .headline)
    static let statNumber = display(34, relativeTo: .largeTitle)

    /// Older person's interface: bigger everything (body ≥ 20 pt at the default size).
    enum Elder {
        static let hero = display(40, relativeTo: .largeTitle)
        static let title = display(32, relativeTo: .title)
        static let title2 = display(28, relativeTo: .title2)
        static let body = NoahFont.body(22, relativeTo: .body)
        static let bodyStrong = NoahFont.semibold(22, relativeTo: .body)
        static let label = NoahFont.body(20, relativeTo: .callout)
        static let button = NoahFont.semibold(24, relativeTo: .title3)
        static let orb = display(30, relativeTo: .title)
        static let subtitle = NoahFont.body(26, relativeTo: .title3)
    }
}

// MARK: - Spacing, radii, sizes

enum NoahSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    /// Side margin of full-width screens.
    static let screen: CGFloat = 20
}

enum NoahRadius {
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let card: CGFloat = 22
    static let large: CGFloat = 24
}

enum NoahSize {
    /// Apple HIG minimum (caregiver interface).
    static let minTap: CGFloat = 44
    /// Standard button height in the caregiver interface.
    static let button: CGFloat = 54
    /// Minimum tap target in the older person's interface.
    static let elderMinTap: CGFloat = 64
    /// Button height in the older person's interface.
    static let elderButton: CGFloat = 76
    /// The big round "Praat met Noah" button.
    static let orb: CGFloat = 232
    /// Hang-up button.
    static let hangUp: CGFloat = 96
    /// Readable column width on iPad.
    static let readableWidth: CGFloat = 640
    static let borderWidth: CGFloat = 1
}

enum NoahMotion {
    static let quick = Animation.easeOut(duration: 0.18)
    static let standard = Animation.easeInOut(duration: 0.3)
}
