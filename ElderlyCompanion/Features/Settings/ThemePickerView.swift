import SwiftUI

struct ThemePickerView: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        ScrollView {
            VStack(spacing: CompanionTheme.Spacing.lg) {
                ForEach(AppTheme.allCases) { theme in
                    ThemePreviewCard(
                        theme: theme,
                        isSelected: themeManager.current == theme
                    ) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            themeManager.current = theme
                        }
                    }
                }
            }
            .padding(CompanionTheme.Spacing.lg)
        }
        .background(Color.companionBackground)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct ThemePreviewCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                // Preview area
                themePreview
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: CompanionTheme.Radius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: CompanionTheme.Radius.lg, style: .continuous)
                            .stroke(isSelected ? Color.companionPrimary : Color.clear, lineWidth: 3)
                    )

                // Label
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(theme.displayName)
                            .font(.companionHeadline)
                            .foregroundStyle(Color.companionTextPrimary)

                        Text(theme.description)
                            .font(.companionCaption)
                            .foregroundStyle(Color.companionTextSecondary)
                    }

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundStyle(isSelected ? Color.companionPrimary : Color.companionTextTertiary)
                }
                .padding(.top, CompanionTheme.Spacing.md)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var themePreview: some View {
        switch theme {
        case .calm:
            calmPreview
        case .apple:
            applePreview
        }
    }

    private var calmPreview: some View {
        ZStack {
            Color(red: 0.98, green: 0.97, blue: 0.95)

            VStack(spacing: 12) {
                // Mock talk button
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.42, green: 0.56, blue: 0.47))
                    .frame(width: 200, height: 50)
                    .overlay(
                        HStack(spacing: 8) {
                            Image(systemName: "mic.fill")
                            Text("Talk Now")
                                .fontWeight(.bold)
                        }
                        .foregroundStyle(.white)
                        .font(.system(size: 16, design: .rounded))
                    )

                // Mock cards
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white)
                        .frame(height: 40)
                        .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white)
                        .frame(height: 40)
                        .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
                }
                .padding(.horizontal, 20)

                RoundedRectangle(cornerRadius: 10)
                    .fill(.white)
                    .frame(height: 30)
                    .padding(.horizontal, 20)
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
            }
        }
    }

    private var applePreview: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.97, blue: 1.00),
                    Color(red: 0.97, green: 0.95, blue: 1.00),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 12) {
                // Mock talk button with AI gradient
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.00, green: 0.48, blue: 1.00),
                                Color(red: 0.55, green: 0.36, blue: 0.90),
                                Color(red: 0.90, green: 0.30, blue: 0.65),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 200, height: 50)
                    .overlay(
                        HStack(spacing: 8) {
                            Image(systemName: "mic.fill")
                            Text("Talk Now")
                                .fontWeight(.bold)
                        }
                        .foregroundStyle(.white)
                        .font(.system(size: 16))
                    )

                // Mock glass cards
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .frame(height: 40)
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .frame(height: 40)
                }
                .padding(.horizontal, 20)

                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .frame(height: 30)
                    .padding(.horizontal, 20)
            }
        }
    }
}
