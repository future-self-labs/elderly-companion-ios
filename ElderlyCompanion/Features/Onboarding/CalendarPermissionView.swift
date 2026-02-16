import SwiftUI

struct CalendarPermissionView: View {
    @Binding var selectedAccess: CalendarAccessLevel
    let onContinue: () -> Void

    @State private var calendarService = CalendarService()

    var body: some View {
        VStack(spacing: CompanionTheme.Spacing.xl) {
            Spacer()

            // Header
            VStack(spacing: CompanionTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.companionSecondaryLight)
                        .frame(width: 80, height: 80)

                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.companionSecondary)
                }

                Text("Calendar Access")
                    .font(.companionTitle)
                    .foregroundStyle(Color.companionTextPrimary)

                Text("Noah can view and manage your appointments to send timely reminders and help plan your day.")
                    .font(.companionBody)
                    .foregroundStyle(Color.companionTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, CompanionTheme.Spacing.lg)
            }

            // Options
            VStack(spacing: CompanionTheme.Spacing.md) {
                PermissionOption(
                    title: "Full access",
                    description: "View, add, and edit events",
                    icon: "calendar.badge.plus",
                    isSelected: selectedAccess == .full
                ) {
                    selectedAccess = .full
                }

                PermissionOption(
                    title: "Read only",
                    description: "View events only",
                    icon: "calendar",
                    isSelected: selectedAccess == .readOnly
                ) {
                    selectedAccess = .readOnly
                }

                PermissionOption(
                    title: "Skip for now",
                    description: "You can enable this later",
                    icon: "calendar.badge.minus",
                    isSelected: selectedAccess == .none
                ) {
                    selectedAccess = .none
                }
            }
            .padding(.horizontal, CompanionTheme.Spacing.lg)

            Spacer()

            LargeButton("Continue", icon: "arrow.right") {
                if selectedAccess == .full || selectedAccess == .readOnly {
                    // iOS EventKit requires full access for reading events too
                    // The "Read only" distinction is enforced in-app, not at OS level
                    Task {
                        _ = await calendarService.requestFullAccess()
                        UserDefaults.standard.set(selectedAccess.rawValue, forKey: "calendarAccessLevel")
                        await MainActor.run { onContinue() }
                    }
                } else {
                    UserDefaults.standard.set("none", forKey: "calendarAccessLevel")
                    onContinue()
                }
            }
            .padding(.horizontal, CompanionTheme.Spacing.lg)
            .padding(.bottom, CompanionTheme.Spacing.xxl)
        }
        .background(Color.companionBackground)
    }
}

struct PermissionOption: View {
    let title: String
    let description: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: CompanionTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.companionPrimary : Color.companionTextTertiary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.companionBody)
                        .foregroundStyle(Color.companionTextPrimary)

                    Text(description)
                        .font(.companionCaption)
                        .foregroundStyle(Color.companionTextSecondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? Color.companionPrimary : Color.companionTextTertiary.opacity(0.4))
            }
            .padding(CompanionTheme.Spacing.md)
            .background(isSelected ? Color.companionPrimaryLight : Color.companionSurface)
            .clipShape(RoundedRectangle(cornerRadius: CompanionTheme.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: CompanionTheme.Radius.lg)
                    .stroke(isSelected ? Color.companionPrimary.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
