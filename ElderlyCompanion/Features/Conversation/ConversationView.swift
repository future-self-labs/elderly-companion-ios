import SwiftUI

struct ConversationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var viewModel = ConversationViewModel()

    /// Set to true to use the pipeline agent (Deepgram + GPT-4o-mini + ElevenLabs)
    var usePipeline: Bool = false

    var body: some View {
        ZStack {
            // Background
            Color.companionBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                topBar

                Spacer()

                // Voice visualization
                voiceVisualization

                // Status text
                statusText

                Spacer()

                // Transcription area
                transcriptionArea

                // Controls
                controlBar
            }
        }
        .onAppear {
            viewModel.usePipeline = usePipeline
            if usePipeline {
                viewModel.voiceId = UserDefaults.standard.string(forKey: "pipelineVoiceId")
            }
            viewModel.startSession(userId: UserDefaults.standard.string(forKey: "userId") ?? "")
        }
        .onDisappear {
            viewModel.endSession()
        }
        .alert("Save Failed", isPresented: $viewModel.showTranscriptSaveError) {
            Button("OK") {}
        } message: {
            Text(viewModel.transcriptSaveError ?? "Your conversation could not be saved.")
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                viewModel.endSession()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.companionTextSecondary)
                    .frame(width: 44, height: 44)
                    .background(Color.companionSurface)
                    .clipShape(Circle())
            }

            Spacer()

            // Session timer
            if viewModel.isConnected {
                Text(viewModel.formattedDuration)
                    .font(.companionLabel)
                    .foregroundStyle(Color.companionTextSecondary)
                    .padding(.horizontal, CompanionTheme.Spacing.md)
                    .padding(.vertical, CompanionTheme.Spacing.sm)
                    .background(Color.companionSurface)
                    .clipShape(Capsule())
            }

            Spacer()

            // Save memory button
            Button {
                viewModel.markAsMemory()
            } label: {
                Image(systemName: "bookmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.companionTextSecondary)
                    .frame(width: 44, height: 44)
                    .background(Color.companionSurface)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, CompanionTheme.Spacing.lg)
        .padding(.top, CompanionTheme.Spacing.md)
    }

    // MARK: - Voice Visualization

    private var voiceVisualization: some View {
        ZStack {
            // Outer pulse ring
            Circle()
                .stroke(Color.companionVoiceActive.opacity(0.15), lineWidth: 2)
                .frame(width: 240, height: 240)
                .scaleEffect(viewModel.isListening ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: viewModel.isListening)

            // Middle ring
            Circle()
                .stroke(Color.companionVoiceActive.opacity(0.25), lineWidth: 3)
                .frame(width: 190, height: 190)
                .scaleEffect(viewModel.isListening ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: viewModel.isListening)

            // Audio level ring
            Circle()
                .fill(
                    viewModel.isListening
                        ? Color.companionVoiceActive.opacity(0.1)
                        : Color.companionVoiceIdle.opacity(0.05)
                )
                .frame(width: 160, height: 160)
                .scaleEffect(1.0 + CGFloat(viewModel.audioLevel) * 0.3)
                .animation(.easeOut(duration: 0.1), value: viewModel.audioLevel)

            // Center orb
            Circle()
                .fill(
                    viewModel.isConnected
                        ? AnyShapeStyle(LinearGradient.aiGradient)
                        : AnyShapeStyle(Color.companionVoiceIdle)
                )
                .frame(width: 120, height: 120)
                .shadow(
                    color: (viewModel.isConnected ? Color.companionVoiceActive : Color.companionVoiceIdle).opacity(0.4),
                    radius: 20
                )

            // Mic icon
            Image(systemName: viewModel.isMicEnabled ? "waveform" : "mic.slash.fill")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Status Text

    private var statusText: some View {
        VStack(spacing: CompanionTheme.Spacing.sm) {
            Text(viewModel.statusMessage)
                .font(.companionHeadline)
                .foregroundStyle(Color.companionTextPrimary)

            if viewModel.isListening {
                Text("Noah is listening...")
                    .font(.companionBodySecondary)
                    .foregroundStyle(Color.companionPrimary)
            }

            if let error = viewModel.errorDetail {
                Text(error)
                    .font(.companionCaption)
                    .foregroundStyle(Color.companionDanger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, CompanionTheme.Spacing.xl)

                Button("Retry") {
                    viewModel.retry()
                }
                .font(.companionBody)
                .foregroundStyle(Color.companionPrimary)
                .padding(.top, CompanionTheme.Spacing.sm)
            }
        }
        .padding(.top, CompanionTheme.Spacing.xl)
    }

    // MARK: - Transcription

    private var transcriptionArea: some View {
        Group {
            if !viewModel.transcriptMessages.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.sm) {
                        ForEach(Array(viewModel.transcriptMessages.suffix(5).enumerated()), id: \.offset) { _, msg in
                            HStack {
                                if msg.role == "user" { Spacer() }
                                Text(msg.content)
                                    .font(.companionCaption)
                                    .foregroundStyle(msg.role == "user" ? Color.companionPrimary : Color.companionTextSecondary)
                                    .padding(.horizontal, CompanionTheme.Spacing.md)
                                    .padding(.vertical, CompanionTheme.Spacing.xs)
                                    .background(
                                        msg.role == "user"
                                            ? Color.companionPrimaryLight
                                            : Color.companionSurfaceSecondary
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: CompanionTheme.Radius.md))
                                if msg.role != "user" { Spacer() }
                            }
                        }
                    }
                    .padding(.horizontal, CompanionTheme.Spacing.lg)
                }
                .frame(maxHeight: 140)
                .padding(.bottom, CompanionTheme.Spacing.sm)
            } else if let last = viewModel.lastTranscription {
                Text(last)
                    .font(.companionCaption)
                    .foregroundStyle(Color.companionTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, CompanionTheme.Spacing.xl)
                    .padding(.bottom, CompanionTheme.Spacing.md)
            }
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: CompanionTheme.Spacing.xxl) {
            // Mute button
            Button {
                viewModel.toggleMicrophone()
            } label: {
                VStack(spacing: CompanionTheme.Spacing.xs) {
                    Image(systemName: viewModel.isMicEnabled ? "mic.fill" : "mic.slash.fill")
                        .font(.system(size: 22))
                        .frame(width: 56, height: 56)
                        .background(viewModel.isMicEnabled ? Color.companionSurface : Color.companionDanger.opacity(0.15))
                        .foregroundStyle(viewModel.isMicEnabled ? Color.companionTextPrimary : Color.companionDanger)
                        .clipShape(Circle())

                    Text(viewModel.isMicEnabled ? "Mute" : "Unmute")
                        .font(.companionCaption)
                        .foregroundStyle(Color.companionTextSecondary)
                }
            }
            .buttonStyle(.plain)

            // End button
            Button {
                viewModel.endSession()
                dismiss()
            } label: {
                VStack(spacing: CompanionTheme.Spacing.xs) {
                    Image(systemName: "xmark")
                        .font(.system(size: 22, weight: .bold))
                        .frame(width: 64, height: 64)
                        .background(Color.companionDanger)
                        .foregroundStyle(.white)
                        .clipShape(Circle())

                    Text("End")
                        .font(.companionCaption)
                        .foregroundStyle(Color.companionTextSecondary)
                }
            }
            .buttonStyle(.plain)

            // Mark important button
            Button {
                viewModel.markAsImportant()
            } label: {
                VStack(spacing: CompanionTheme.Spacing.xs) {
                    Image(systemName: viewModel.isMarkedImportant ? "star.fill" : "star")
                        .font(.system(size: 22))
                        .frame(width: 56, height: 56)
                        .background(Color.companionSurface)
                        .foregroundStyle(viewModel.isMarkedImportant ? Color.companionWarning : Color.companionTextPrimary)
                        .clipShape(Circle())

                    Text("Important")
                        .font(.companionCaption)
                        .foregroundStyle(Color.companionTextSecondary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, CompanionTheme.Spacing.xxl)
    }
}
