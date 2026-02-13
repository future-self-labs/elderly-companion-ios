import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: CompanionTheme.Spacing.xxl) {
            Spacer()

            // Logo area
            VStack(spacing: CompanionTheme.Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(Color.companionPrimaryLight)
                        .frame(width: 120, height: 120)

                    Image(systemName: "heart.text.clipboard.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(Color.companionPrimary)
                }

                VStack(spacing: CompanionTheme.Spacing.sm) {
                    Text("Noah")
                        .font(.companionDisplay)
                        .foregroundStyle(Color.companionTextPrimary)

                    Text("Calm. Dignified. Always There.")
                        .font(.companionBody)
                        .foregroundStyle(Color.companionTextSecondary)
                }
            }

            Spacer()

            // Action buttons
            VStack(spacing: CompanionTheme.Spacing.md) {
                LargeButton("Set up for myself", icon: "person.fill") {
                    onContinue()
                }

                LargeButton("Set up for my parent", icon: "person.2.fill", style: .outline) {
                    onContinue()
                }
            }
            .padding(.horizontal, CompanionTheme.Spacing.lg)
            .padding(.bottom, CompanionTheme.Spacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.companionBackground)
    }
}

#Preview {
    WelcomeView(onContinue: {})
}
