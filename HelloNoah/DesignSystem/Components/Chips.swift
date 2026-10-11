import SwiftUI

/// A small rounded tag ("moestuin", "Familie").
struct NoahChip: View {
    let text: String
    var systemImage: String?
    var tint: Color = NoahColor.textSoft
    var isSelected = false

    var body: some View {
        HStack(spacing: NoahSpacing.xxs) {
            if let systemImage {
                Image(systemName: systemImage).accessibilityHidden(true)
            }
            Text(verbatim: text)
        }
        .font(NoahFont.subheadline)
        .foregroundColor(isSelected ? NoahColor.onAccent : tint)
        .padding(.horizontal, NoahSpacing.s)
        .padding(.vertical, NoahSpacing.xs - 2)
        .background(Capsule().fill(isSelected ? NoahColor.accent : NoahColor.surfaceDeep))
        .overlay(Capsule().strokeBorder(isSelected ? .clear : NoahColor.border, lineWidth: 1))
    }
}

/// A selectable chip used for filters and weekday pickers (≥ 44 pt tap area).
struct NoahChoiceChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(NoahFont.semibold(15, relativeTo: .subheadline))
                .foregroundColor(isSelected ? NoahColor.onAccent : NoahColor.text)
                .padding(.horizontal, NoahSpacing.m)
                .frame(minHeight: NoahSize.minTap)
                .background(Capsule().fill(isSelected ? NoahColor.accent : NoahColor.surface))
                .overlay(Capsule().strokeBorder(isSelected ? .clear : NoahColor.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Wrapping horizontal layout for chips (iOS 16 `Layout`).
struct FlowLayout: Layout {
    var spacing: CGFloat = NoahSpacing.xs
    var lineSpacing: CGFloat = NoahSpacing.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, min(x - spacing, maxWidth))
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// A wrapping list of chips for a string array.
struct NoahChipList: View {
    let items: [String]
    var systemImage: String?

    var body: some View {
        FlowLayout {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                NoahChip(text: item, systemImage: systemImage)
            }
        }
    }
}

/// Mood dot + Dutch label ("Goed").
struct NoahMoodBadge: View {
    let score: Double?
    var showsLabel = true

    var body: some View {
        HStack(spacing: NoahSpacing.xs) {
            Circle()
                .fill(NoahColor.mood(score))
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            if showsLabel {
                Text(verbatim: MoodText.label(score))
                    .font(NoahFont.subheadline)
                    .foregroundColor(NoahColor.textSoft)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Stemming: \(MoodText.label(score))"))
    }
}
