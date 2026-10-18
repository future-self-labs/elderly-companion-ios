import SwiftUI

/// The standard container: surface colour, hairline border, large radius.
struct NoahCard<Content: View>: View {
    var padding: CGFloat = NoahSpacing.m
    var background: Color = NoahColor.surface
    var border: Color = NoahColor.cardBorder
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.s) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: NoahRadius.card, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NoahRadius.card, style: .continuous)
                .strokeBorder(border, lineWidth: NoahSize.borderWidth)
        )
    }
}

/// Section title above a group of cards, with an optional trailing action.
struct NoahSectionHeader: View {
    let title: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(NoahFont.title3)
                .foregroundColor(NoahColor.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: NoahSpacing.s)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(NoahFont.subheadline)
                    .foregroundColor(NoahColor.accent)
                    .frame(minHeight: NoahSize.minTap)
            }
        }
    }
}

/// Small uppercase-ish label used inside cards ("LAATSTE GESPREK").
struct NoahEyebrow: View {
    let text: LocalizedStringKey
    var color: Color = NoahColor.textSecondary

    var body: some View {
        Text(text)
            .font(NoahFont.captionStrong)
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundColor(color)
    }
}

/// Inline message box for info, warnings and errors.
struct NoahNotice: View {
    enum Kind { case info, warning, error, success }

    let kind: Kind
    let text: String
    /// Bigger text for the older person's interface.
    var large = false
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: NoahSpacing.s) {
            Image(systemName: icon)
                .font(large ? NoahFont.Elder.bodyStrong : NoahFont.headline)
                .foregroundColor(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: NoahSpacing.xs) {
                Text(verbatim: text)
                    .font(large ? NoahFont.Elder.label : NoahFont.callout)
                    .foregroundColor(NoahColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(large ? NoahFont.Elder.bodyStrong : NoahFont.bodyStrong)
                        .foregroundColor(tint)
                        .frame(minHeight: large ? NoahSize.elderMinTap : NoahSize.minTap)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(NoahSpacing.m)
        .background(RoundedRectangle(cornerRadius: NoahRadius.medium, style: .continuous).fill(soft))
        .overlay(RoundedRectangle(cornerRadius: NoahRadius.medium, style: .continuous).strokeBorder(tint.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch kind {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        case .success: return "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch kind {
        case .info: return NoahColor.textSoft
        case .warning: return NoahColor.accent
        case .error: return NoahColor.dangerText
        case .success: return NoahColor.positive
        }
    }

    private var soft: Color {
        switch kind {
        case .info: return NoahColor.surface
        case .warning: return NoahColor.accentGlow
        case .error: return NoahColor.dangerSoft
        case .success: return NoahColor.positiveSoft
        }
    }
}

/// Big number with a caption, for dashboard stats.
struct NoahStat: View {
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.xxs) {
            Text(verbatim: value)
                .font(NoahFont.statNumber).noahTitleScaling()
                .foregroundColor(NoahColor.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(NoahFont.footnote)
                .foregroundColor(NoahColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
