import SwiftUI

/// Rounded square with an SF Symbol, used at the start of rows.
struct NoahIconBadge: View {
    let systemName: String
    var tint: Color = NoahColor.accent
    var size: CGFloat = 40

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.45 * min(scale, 1.6), weight: .semibold))
            .foregroundColor(tint)
            .frame(width: size * min(scale, 1.6), height: size * min(scale, 1.6))
            .background(
                RoundedRectangle(cornerRadius: NoahRadius.small, style: .continuous)
                    .fill(NoahColor.surfaceDeep)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NoahRadius.small, style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

/// Standard list row: optional icon, title, subtitle, trailing value and chevron.
struct NoahRow: View {
    var icon: String?
    var iconTint: Color = NoahColor.accent
    let title: String
    var subtitle: String?
    var value: String?
    var showsChevron: Bool = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        AdaptiveStack(verticalAlignment: .center, spacing: NoahSpacing.s) {
            if let icon {
                NoahIconBadge(systemName: icon, tint: iconTint)
            }
            VStack(alignment: .leading, spacing: NoahSpacing.xxs) {
                Text(verbatim: title)
                    .font(NoahFont.bodyStrong)
                    .foregroundColor(NoahColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(NoahFont.subheadline)
                        .foregroundColor(NoahColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let value, dynamicTypeSize.isAccessibilitySize {
                    Text(verbatim: value)
                        .font(NoahFont.subheadline)
                        .foregroundColor(NoahColor.textSoft)
                }
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: NoahSpacing.xs) }
            if let value, !dynamicTypeSize.isAccessibilitySize {
                Text(verbatim: value)
                    .font(NoahFont.subheadline)
                    .foregroundColor(NoahColor.textSoft)
                    .multilineTextAlignment(.trailing)
            }
            if showsChevron && !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "chevron.right")
                    .font(NoahFont.footnote)
                    .foregroundColor(NoahColor.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: NoahSize.minTap)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Initials in a circle (caregivers, people, older people in the switcher).
struct NoahAvatar: View {
    let name: String
    var size: CGFloat = 40
    var tint: Color = NoahColor.accent

    var body: some View {
        Text(verbatim: initials)
            .font(NoahFont.semibold(size * 0.38))
            .foregroundColor(NoahColor.onAccent)
            .frame(width: size, height: size)
            .background(Circle().fill(tint))
            .accessibilityHidden(true)
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}
