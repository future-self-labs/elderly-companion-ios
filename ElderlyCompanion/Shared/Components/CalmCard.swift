import SwiftUI

struct CalmCard<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(CompanionTheme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.companionSurface)
            .clipShape(RoundedRectangle(cornerRadius: CompanionTheme.Radius.lg))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}

struct CalmCardHeader: View {
    let title: String
    let icon: String?
    let subtitle: String?

    init(_ title: String, icon: String? = nil, subtitle: String? = nil) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(spacing: CompanionTheme.Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.companionPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.companionHeadline)
                    .foregroundStyle(Color.companionTextPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(.companionCaption)
                        .foregroundStyle(Color.companionTextSecondary)
                }
            }

            Spacer()
        }
    }
}

struct TagBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.companionLabel)
            .padding(.horizontal, CompanionTheme.Spacing.sm)
            .padding(.vertical, CompanionTheme.Spacing.xs)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

#Preview {
    VStack(spacing: 16) {
        CalmCard {
            VStack(alignment: .leading, spacing: 12) {
                CalmCardHeader("Next Event", icon: "calendar", subtitle: "Today")
                Text("Doctor's appointment at 2:00 PM")
                    .font(.companionBody)
                    .foregroundStyle(Color.companionTextSecondary)
            }
        }

        CalmCard {
            HStack {
                TagBadge(text: "Companion", color: .companionPrimary)
                TagBadge(text: "Memory", color: .companionInfo)
                TagBadge(text: "Concern", color: .companionDanger)
            }
        }
    }
    .padding()
    .background(Color.companionBackground)
}
