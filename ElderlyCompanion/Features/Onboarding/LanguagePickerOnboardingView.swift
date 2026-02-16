import SwiftUI

struct LanguagePickerOnboardingView: View {
    @Binding var selectedLanguage: String
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: CompanionTheme.Spacing.xl) {
            Spacer()

            VStack(spacing: CompanionTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.companionPrimaryLight)
                        .frame(width: 80, height: 80)

                    Image(systemName: "globe")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.companionPrimary)
                }

                Text("Choose your language")
                    .font(.companionTitle)
                    .foregroundStyle(Color.companionTextPrimary)

                Text("Noah will speak with you in your preferred language.")
                    .font(.companionBody)
                    .foregroundStyle(Color.companionTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, CompanionTheme.Spacing.lg)
            }

            VStack(spacing: CompanionTheme.Spacing.sm) {
                ForEach(NoahLanguage.available) { lang in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedLanguage = lang.id
                        }
                    } label: {
                        HStack(spacing: CompanionTheme.Spacing.md) {
                            Text(lang.flag)
                                .font(.system(size: 28))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(lang.nativeName)
                                    .font(.companionBody)
                                    .foregroundStyle(
                                        selectedLanguage == lang.id ? .white : Color.companionTextPrimary
                                    )
                                Text(lang.name)
                                    .font(.companionCaption)
                                    .foregroundStyle(
                                        selectedLanguage == lang.id ? .white.opacity(0.8) : Color.companionTextSecondary
                                    )
                            }

                            Spacer()

                            if selectedLanguage == lang.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(CompanionTheme.Spacing.md)
                        .background(
                            selectedLanguage == lang.id
                                ? Color.companionPrimary
                                : Color.companionSurface
                        )
                        .clipShape(RoundedRectangle(cornerRadius: CompanionTheme.Radius.lg))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, CompanionTheme.Spacing.lg)

            Spacer()

            LargeButton("Continue", icon: "arrow.right") {
                onContinue()
            }
            .padding(.horizontal, CompanionTheme.Spacing.lg)
            .padding(.bottom, CompanionTheme.Spacing.xxl)
        }
        .background(Color.companionBackground)
    }
}
