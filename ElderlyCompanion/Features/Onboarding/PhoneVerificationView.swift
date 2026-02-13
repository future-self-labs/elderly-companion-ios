import SwiftUI

struct PhoneVerificationView: View {
    let phoneNumber: String
    @Bindable var authService: AuthService
    let onVerified: (String) -> Void

    @State private var otpCode: String = ""
    @State private var showError: Bool = false
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        VStack(spacing: CompanionTheme.Spacing.xl) {
            Spacer()

            // Header
            VStack(spacing: CompanionTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.companionPrimaryLight)
                        .frame(width: 80, height: 80)

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.companionPrimary)
                }

                Text("Verify your phone")
                    .font(.companionTitle)
                    .foregroundStyle(Color.companionTextPrimary)

                Text("We sent a code to \(phoneNumber)")
                    .font(.companionBody)
                    .foregroundStyle(Color.companionTextSecondary)
                    .multilineTextAlignment(.center)
            }

            // OTP Input
            if authService.verificationSent {
                VStack(spacing: CompanionTheme.Spacing.lg) {
                    OTPInputField(code: $otpCode)
                        .focused($isCodeFocused)
                        .onAppear { isCodeFocused = true }

                    if let error = authService.error {
                        Text(error)
                            .font(.companionCaption)
                            .foregroundStyle(Color.companionDanger)
                    }

                    LargeButton("Verify", icon: "checkmark.shield.fill") {
                        verifyCode()
                    }
                    .disabled(otpCode.count < 4 || authService.isVerifying)
                    .opacity(otpCode.count < 4 ? 0.5 : 1.0)
                    .padding(.horizontal, CompanionTheme.Spacing.lg)

                    Button("Resend code") {
                        sendCode()
                    }
                    .font(.companionBodySecondary)
                    .foregroundStyle(Color.companionPrimary)
                }
            } else {
                LargeButton(
                    authService.isVerifying ? "Sending..." : "Send verification code",
                    icon: "paperplane.fill"
                ) {
                    sendCode()
                }
                .disabled(authService.isVerifying)
                .padding(.horizontal, CompanionTheme.Spacing.lg)
            }

            Spacer()
            Spacer()
        }
        .padding(CompanionTheme.Spacing.lg)
        .background(Color.companionBackground)
        .onAppear {
            // Auto-send OTP when view appears
            sendCode()
        }
    }

    private func sendCode() {
        Task {
            try? await authService.sendOTP(to: phoneNumber)
        }
    }

    private func verifyCode() {
        Task {
            do {
                let userId = try await authService.validateOTP(phoneNumber: phoneNumber, code: otpCode)
                await MainActor.run {
                    onVerified(userId)
                }
            } catch {
                showError = true
            }
        }
    }
}

// MARK: - OTP Input Field

struct OTPInputField: View {
    @Binding var code: String
    private let codeLength = 6

    var body: some View {
        HStack(spacing: CompanionTheme.Spacing.md) {
            ForEach(0..<codeLength, id: \.self) { index in
                let character = index < code.count
                    ? String(code[code.index(code.startIndex, offsetBy: index)])
                    : ""

                Text(character)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.companionTextPrimary)
                    .frame(width: 44, height: 56)
                    .background(Color.companionSurface)
                    .clipShape(RoundedRectangle(cornerRadius: CompanionTheme.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: CompanionTheme.Radius.md)
                            .stroke(
                                index < code.count
                                    ? Color.companionPrimary
                                    : Color.companionTextTertiary.opacity(0.3),
                                lineWidth: index < code.count ? 2 : 1
                            )
                    )
            }
        }
        .overlay(
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .foregroundStyle(.clear)
                .tint(.clear)
                .onChange(of: code) { _, newValue in
                    code = String(newValue.prefix(codeLength))
                }
        )
    }
}
