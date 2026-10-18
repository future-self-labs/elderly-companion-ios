import SwiftUI
import UIKit

/// The active conversation: Noah's orb, a waveform, optional big subtitles and one big
/// "Ophangen" button. Nothing else.
///
/// Opened by a link from outside the app (`needsConfirmation`), it first shows one big start
/// button: the microphone never opens without a visible tap (security audit M11). At
/// accessibility text sizes the header becomes one compact line, subtitles show the latest line
/// and keep scaling, and the controls are pinned above the home indicator (audit H6).
struct ConversationScreen: View {
    @StateObject private var controller: ConversationController
    let noahName: String
    let onClose: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var autoCloseTask: Task<Void, Never>?
    @State private var awaitsConfirmation: Bool

    init(controller: ConversationController, noahName: String, needsConfirmation: Bool = false, onClose: @escaping () -> Void) {
        _controller = StateObject(wrappedValue: controller)
        _awaitsConfirmation = State(initialValue: needsConfirmation)
        self.noahName = noahName
        self.onClose = onClose
    }

    private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        ZStack {
            NoahColor.surfaceDeep.ignoresSafeArea()
            if awaitsConfirmation {
                confirmation
            } else {
                content
            }
        }
        .task {
            guard !awaitsConfirmation else { return }
            await controller.start()
        }
        .onChange(of: controller.phase) { phase in
            switch phase {
            case .ended(.hungUp):
                onClose()
            case .ended(.noahEnded):
                announce("Het gesprek is afgelopen.")
                scheduleAutoClose()
            case .active:
                announce("U bent verbonden met \(noahName).")
            default:
                break
            }
        }
        .onDisappear { autoCloseTask?.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch controller.phase {
            case .failed(let failure):
                outcome(
                    systemImage: failure == .micDenied ? "mic.slash.fill" : (failure == .offline ? "wifi.slash" : "exclamationmark.bubble.fill"),
                    message: failure.text,
                    canRetry: failure != .inactive,
                    showsSettings: failure == .micDenied
                )
            case .ended(let kind) where kind != .hungUp:
                outcome(systemImage: "checkmark.circle.fill", message: endMessage(kind), canRetry: true, showsSettings: false)
            default:
                live
            }
        }
    }

    // MARK: Confirmation (opened from outside the app)

    private var confirmation: some View {
        ScrollView {
            VStack(spacing: NoahSpacing.l) {
                Text(verbatim: controller.mode == .levensverhaal ? "Een verhaal vertellen?" : "Met \(noahName) praten?")
                    .font(NoahFont.Elder.title).noahElderTitleScaling()
                    .foregroundColor(NoahColor.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, NoahSpacing.xl)
                Text("Tik op de knop om het gesprek te beginnen. Pas dan gaat de microfoon aan.")
                    .font(NoahFont.Elder.body)
                    .foregroundColor(NoahColor.textSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    awaitsConfirmation = false
                    Task { await controller.start() }
                } label: {
                    ZStack {
                        NoahOrb(activity: .idle, diameter: 200)
                        VStack(spacing: NoahSpacing.s) {
                            Image(systemName: controller.mode == .levensverhaal ? "quote.bubble.fill" : "mic.fill")
                                .font(.system(size: 34, weight: .semibold))
                                .accessibilityHidden(true)
                            Text(verbatim: controller.mode == .levensverhaal ? "Vertel een verhaal" : "Praat met \(noahName)")
                                .font(NoahFont.Elder.orb).noahElderTitleScaling()
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.7)
                                .padding(.horizontal, NoahSpacing.l)
                        }
                        .foregroundColor(NoahColor.onAccent)
                        .frame(width: 200, height: 200)
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(OrbPressStyle())
                .accessibilityLabel(Text(verbatim: controller.mode == .levensverhaal ? "Vertel een verhaal" : "Praat met \(noahName)"))
                .accessibilityHint(Text("Begint het gesprek en zet de microfoon aan"))
                .accessibilityIdentifier("conversation.confirmStart")
                Button("Terug", action: onClose)
                    .buttonStyle(.noah(.secondary, size: .elder))
                    .accessibilityIdentifier("conversation.back")
            }
            .padding(.horizontal, NoahSpacing.screen)
            .padding(.bottom, NoahSpacing.l)
            .noahReadableWidth()
        }
    }

    // MARK: Live conversation

    private var live: some View {
        VStack(spacing: isAccessibilitySize ? NoahSpacing.s : NoahSpacing.m) {
            if isAccessibilitySize {
                compactHeader
            } else {
                header
            }

            if controller.networkLost {
                NoahNotice(kind: .warning,
                           text: isAccessibilitySize ? "De verbinding hapert even." : "De verbinding hapert even. Blijft u gerust aan de lijn.",
                           large: true)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }

            if !controller.showsSubtitles { Spacer(minLength: 0) }

            NoahOrb(activity: controller.orbActivity,
                    level: controller.turn == .speaking ? controller.agentLevel : controller.userLevel * 0.6,
                    diameter: orbDiameter)

            WaveformView(levels: controller.levelHistory,
                         color: controller.turn == .speaking ? NoahColor.accent : NoahColor.textSoft,
                         maxHeight: controller.showsSubtitles ? (isAccessibilitySize ? 24 : 40) : 64)
                .padding(.horizontal, NoahSpacing.l)

            if controller.showsSubtitles {
                subtitles
                    .layoutPriority(1)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, NoahSpacing.screen)
        .noahReadableWidth()
        // The controls always stay on screen, above the home indicator.
        .safeAreaInset(edge: .bottom, spacing: NoahSpacing.s) {
            controls
                .padding(.horizontal, NoahSpacing.screen)
                .padding(.top, NoahSpacing.xs)
                .padding(.bottom, NoahSpacing.s)
                .noahReadableWidth()
                .background(NoahColor.surfaceDeep)
        }
    }

    /// Accessibility sizes: one line with the status (it already names Noah), then small
    /// indicators. Capped at accessibility 1 so the subtitles keep the room.
    private var compactHeader: some View {
        VStack(spacing: NoahSpacing.xxs) {
            HStack(spacing: NoahSpacing.xs) {
                Image(systemName: statusIcon)
                    .foregroundColor(NoahColor.accent)
                    .accessibilityHidden(true)
                Text(verbatim: controller.statusText)
                    .foregroundColor(NoahColor.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityIdentifier("conversation.status")
            }
            .font(NoahFont.Elder.bodyStrong)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            // Stacked, so the honest recording line is never cut off.
            VStack(spacing: NoahSpacing.xxs) {
                if controller.mode == .levensverhaal {
                    Label("Verhaal", systemImage: "quote.bubble.fill")
                        .foregroundColor(NoahColor.accent)
                        .accessibilityLabel(Text("U vertelt een verhaal"))
                }
                if controller.isRecording, controller.phase == .active {
                    RecordingIndicator(compact: true)
                }
                if controller.isNearMaxDuration {
                    Label("Nog 1 minuut", systemImage: "clock.fill")
                        .foregroundColor(NoahColor.accent)
                        .accessibilityLabel(Text("Nog ongeveer een minuut"))
                }
            }
            .font(NoahFont.Elder.label)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.top, NoahSpacing.xs)
    }

    private var statusIcon: String {
        switch controller.orbActivity {
        case .speaking: return "waveform"
        case .thinking: return "ellipsis.bubble.fill"
        case .connecting: return "phone.arrow.up.right.fill"
        default: return "ear.fill"
        }
    }

    private var header: some View {
        VStack(spacing: NoahSpacing.xxs) {
            Text(verbatim: noahName)
                .font(NoahFont.Elder.title).noahElderTitleScaling()
                .foregroundColor(NoahColor.text)
                .accessibilityAddTraits(.isHeader)
            if controller.mode == .levensverhaal {
                Text("U vertelt een verhaal")
                    .font(NoahFont.Elder.label)
                    .foregroundColor(NoahColor.accent)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }
            Text(verbatim: controller.statusText)
                .font(NoahFont.Elder.label)
                .foregroundColor(NoahColor.textSoft)
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .accessibilityIdentifier("conversation.status")
            if controller.isNearMaxDuration {
                Text("Nog ongeveer een minuut")
                    .font(NoahFont.Elder.label)
                    .foregroundColor(NoahColor.accent)
            }
            if controller.isRecording, controller.phase == .active {
                RecordingIndicator()
                    .padding(.top, NoahSpacing.xs)
            }
        }
        .padding(.top, NoahSpacing.m)
    }

    private var orbDiameter: CGFloat {
        if isAccessibilitySize { return controller.showsSubtitles ? 64 : 140 }
        return controller.showsSubtitles ? 120 : 200
    }

    private var subtitles: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: NoahSpacing.s) {
                    if controller.subtitles.isEmpty {
                        Text("Hier ziet u wat er gezegd wordt.")
                            .font(NoahFont.Elder.label)
                            .foregroundColor(NoahColor.textSecondary)
                    }
                    // At accessibility sizes only the latest line fits; it keeps scaling.
                    ForEach(controller.subtitles.suffix(isAccessibilitySize ? 1 : 4)) { line in
                        Text(verbatim: line.text)
                            .font(NoahFont.Elder.subtitle)
                            .foregroundColor(line.speaker == .noah ? NoahColor.text : NoahColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .id(line.id)
                            .accessibilityLabel(Text(line.speaker == .noah ? "\(noahName): \(line.text)" : "U: \(line.text)"))
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(NoahSpacing.m)
            }
            .frame(minHeight: isAccessibilitySize ? 120 : 140, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: NoahRadius.card, style: .continuous).fill(NoahColor.surface))
            .onChange(of: controller.subtitles) { _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
        .accessibilityIdentifier("conversation.subtitles")
    }

    /// Phone-call layout: the big hang-up button in the centre, the subtitle switch beside it.
    private var controls: some View {
        HStack(alignment: .top) {
            Button {
                controller.showsSubtitles.toggle()
            } label: {
                VStack(spacing: NoahSpacing.xs) {
                    Image(systemName: controller.showsSubtitles ? "captions.bubble.fill" : "captions.bubble")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(controller.showsSubtitles ? NoahColor.onAccent : NoahColor.text)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(controller.showsSubtitles ? NoahColor.accent : NoahColor.surface))
                        .overlay(Circle().strokeBorder(NoahColor.border, lineWidth: controller.showsSubtitles ? 0 : 1))
                    Text("Tekst")
                        .font(NoahFont.Elder.label)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundColor(NoahColor.textSoft)
                }
                .frame(minWidth: 88)
                .contentShape(Rectangle())
            }
            .buttonStyle(OrbPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(controller.showsSubtitles ? "Ondertitels uitzetten" : "Ondertitels aanzetten"))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("conversation.subtitlesToggle")

            Spacer(minLength: NoahSpacing.s)

            Button {
                Task { await controller.hangUp() }
            } label: {
                VStack(spacing: NoahSpacing.xs) {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(NoahColor.onDanger)
                        .frame(width: NoahSize.hangUp, height: NoahSize.hangUp)
                        .background(Circle().fill(NoahColor.danger))
                        .shadow(color: NoahColor.danger.opacity(0.4), radius: 16)
                    Text("Ophangen")
                        .font(NoahFont.Elder.bodyStrong)
                        .foregroundColor(NoahColor.text)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .lineLimit(1)
                        .fixedSize()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(OrbPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Ophangen"))
            .accessibilityHint(Text("Beëindigt het gesprek met \(noahName)"))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("conversation.hangUp")

            Spacer(minLength: NoahSpacing.s)

            // Keeps the hang-up button centred.
            Color.clear.frame(width: 88, height: 1).accessibilityHidden(true)
        }
    }

    // MARK: Outcomes

    private func outcome(systemImage: String, message: String, canRetry: Bool, showsSettings: Bool) -> some View {
        ScrollView {
            VStack(spacing: NoahSpacing.l) {
                Image(systemName: systemImage)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundColor(NoahColor.accent)
                    .padding(.top, NoahSpacing.xxl)
                    .accessibilityHidden(true)
                Text(verbatim: message)
                    .font(NoahFont.Elder.title2).noahElderTitleScaling()
                    .foregroundColor(NoahColor.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("conversation.outcome")
                if showsSettings {
                    Button("Naar Instellingen") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(.noah(.primary, size: .elder))
                }
                if canRetry {
                    Button {
                        autoCloseTask?.cancel()
                        Task { await controller.start() }
                    } label: {
                        NoahButtonLabel(title: "Opnieuw praten", systemImage: "mic.fill")
                    }
                    .buttonStyle(.noah(showsSettings ? .secondary : .primary, size: .elder))
                }
                Button("Terug", action: onClose)
                    .buttonStyle(.noah(.secondary, size: .elder))
                    .accessibilityIdentifier("conversation.back")
            }
            .padding(.horizontal, NoahSpacing.screen)
            .noahReadableWidth()
        }
    }

    private func endMessage(_ kind: ConversationController.EndKind) -> String {
        switch kind {
        case .noahEnded: return "\(noahName) heeft het gesprek afgesloten. Tot de volgende keer!"
        case .maxDuration: return "U heeft al een hele tijd gepraat. Neem gerust even pauze. U kunt straks weer met \(noahName) praten."
        case .interrupted: return "Het gesprek is gestopt, omdat u werd gebeld. U kunt zo weer met \(noahName) praten."
        case .hungUp: return ""
        }
    }

    private func scheduleAutoClose() {
        autoCloseTask?.cancel()
        autoCloseTask = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if !Task.isCancelled { onClose() }
        }
    }

    private func announce(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}
