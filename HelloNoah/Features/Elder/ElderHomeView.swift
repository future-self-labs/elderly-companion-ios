import SwiftUI

/// Home: one big "Praat met Noah" button, last conversation, "Bel mij", the next reminder and
/// the two big buttons to "Mijn verhaal" and "Herinneringen". Formal "u" throughout.
struct ElderHomeView: View {
    @Binding var path: [ElderRoute]

    @EnvironmentObject private var session: ElderSession
    @EnvironmentObject private var reachability: Reachability
    @Environment(\.scenePhase) private var scenePhase
    @State private var callMessage: String?
    @State private var callFailed = false
    @State private var isCalling = false
    @State private var showsHelp = false
    @ScaledMetric(relativeTo: .title) private var orbSize: CGFloat = NoahSize.orb

    var body: some View {
        ScrollView {
            VStack(spacing: NoahSpacing.l) {
                header

                if !reachability.isOnline {
                    NoahNotice(kind: .warning, text: "Er is nu geen internet. Praten met Noah lukt weer zodra de verbinding terug is.", large: true)
                }
                if session.justPaired {
                    NoahNotice(kind: .success, text: "Gelukt! Deze telefoon is gekoppeld. U kunt nu met \(session.noahName) praten.", large: true)
                }
                if session.me.value?.access == .inactive {
                    NoahNotice(kind: .warning, text: "Noah is nog niet actief. Vraag uw mantelzorger om hulp.", large: true)
                }
                if case .failed(let error) = session.me {
                    NoahNotice(kind: .warning, text: error.elderMessage, large: true, actionTitle: "Opnieuw proberen") {
                        Task { await session.load() }
                    }
                }

                talkButton

                Text(verbatim: DutchFormat.lastConversation(session.me.value?.lastConversationAt))
                    .font(NoahFont.Elder.label)
                    .foregroundColor(NoahColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("elder.lastConversation")

                callMeButton

                if let reminder = session.me.value?.nextReminder {
                    nextReminderCard(reminder)
                }

                navigationButtons
            }
            .padding(.horizontal, NoahSpacing.screen)
            .padding(.vertical, NoahSpacing.l)
            .noahReadableWidth()
        }
        .noahScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await session.load() }
        .task { await session.load() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await session.load() } }
        }
        .sheet(isPresented: $showsHelp) {
            ElderHelpSheet()
        }
    }

    // MARK: Parts

    private var header: some View {
        VStack(spacing: NoahSpacing.xs) {
            Text(verbatim: greeting)
                .font(NoahFont.Elder.title).noahElderTitleScaling()
                .foregroundColor(NoahColor.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: DutchFormat.longDay(Date()).capitalizedFirst)
                .font(NoahFont.Elder.label)
                .foregroundColor(NoahColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, NoahSpacing.s)
        .contentShape(Rectangle())
        // Hidden: caregivers can long-press the greeting for settings (unpairing).
        .onLongPressGesture(minimumDuration: 2) { showsHelp = true }
        .accessibilityAction(named: Text("Instellingen voor de mantelzorger")) { showsHelp = true }
    }

    private var greeting: String {
        let name = session.name
        return name.isEmpty ? DutchFormat.greeting() : "\(DutchFormat.greeting()), \(name)"
    }

    private var talkButton: some View {
        let diameter = min(orbSize, 300)
        return Button {
            session.justPaired = false
            session.requestConversation()
        } label: {
            ZStack {
                NoahOrb(activity: .idle, diameter: diameter)
                VStack(spacing: NoahSpacing.s) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: diameter * 0.16, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("Praat met \(session.noahName)")
                        .font(NoahFont.Elder.orb).noahElderTitleScaling()
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, diameter * 0.12)
                }
                .foregroundColor(NoahColor.onAccent)
                .frame(width: diameter, height: diameter)
            }
            .contentShape(Circle())
        }
        .buttonStyle(OrbPressStyle())
        .accessibilityLabel(Text("Praat met \(session.noahName)"))
        .accessibilityHint(Text("Begint meteen een gesprek"))
        .accessibilityIdentifier("elder.talk")
    }

    private var callMeButton: some View {
        VStack(spacing: NoahSpacing.s) {
            Button {
                Task { await callMe() }
            } label: {
                ZStack {
                    NoahButtonLabel(title: "Bel mij", systemImage: "phone.fill").opacity(isCalling ? 0 : 1)
                    if isCalling { ProgressView().tint(NoahColor.accent) }
                }
            }
            .buttonStyle(.noah(.secondary, size: .elder))
            .allowsHitTesting(!isCalling)
            .accessibilityHint(Text("Noah belt u op uw telefoon"))
            .accessibilityIdentifier("elder.callMe")

            if let callMessage {
                Text(verbatim: callMessage)
                    .font(NoahFont.Elder.label)
                    .foregroundColor(callFailed ? NoahColor.danger : NoahColor.positive)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func nextReminderCard(_ reminder: Reminder) -> some View {
        NoahCard(padding: NoahSpacing.l) {
            NoahEyebrow(text: "Volgende herinnering")
            AdaptiveStack(spacing: NoahSpacing.m) {
                NoahIconBadge(systemName: reminder.type.systemImage, size: 52)
                VStack(alignment: .leading, spacing: NoahSpacing.xxs) {
                    Text(verbatim: reminder.title)
                        .font(NoahFont.Elder.bodyStrong)
                        .foregroundColor(NoahColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let next = reminder.nextAt {
                        Text(verbatim: DutchFormat.upcoming(next))
                            .font(NoahFont.Elder.label)
                            .foregroundColor(NoahColor.textSoft)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .onTapGesture { path.append(.reminders) }
    }

    private var navigationButtons: some View {
        // Full-width rows: long single words like "Herinneringen" never break mid-word.
        VStack(spacing: NoahSpacing.m) {
            ElderTileButton(title: "Mijn verhaal", systemImage: "book.fill") { path.append(.myStory) }
                .accessibilityIdentifier("elder.myStory")
            ElderTileButton(title: "Herinneringen", systemImage: "bell.fill") { path.append(.reminders) }
                .accessibilityIdentifier("elder.reminders")
        }
    }

    // MARK: Actions

    private func callMe() async {
        isCalling = true
        callMessage = nil
        defer { isCalling = false }
        do {
            try await session.api.deviceCallMe()
            callFailed = false
            callMessage = "\(session.noahName) belt u zo op uw telefoon."
        } catch {
            callFailed = true
            callMessage = APIError.from(error).elderMessage
        }
    }
}

/// Large square-ish button with icon and label (≥ 64 pt).
struct ElderTileButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: NoahSpacing.m) {
                Image(systemName: systemImage)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(NoahColor.accent)
                    .frame(width: 40)
                    .accessibilityHidden(true)
                Text(title)
                    .font(NoahFont.Elder.bodyStrong)
                    .foregroundColor(NoahColor.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(NoahFont.Elder.label)
                    .foregroundColor(NoahColor.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, NoahSpacing.l)
            .padding(.vertical, NoahSpacing.m)
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(RoundedRectangle(cornerRadius: NoahRadius.large, style: .continuous).fill(NoahColor.surface))
            .overlay(RoundedRectangle(cornerRadius: NoahRadius.large, style: .continuous).strokeBorder(NoahColor.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: NoahRadius.large))
        }
        .buttonStyle(.plain)
    }
}

struct OrbPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(NoahMotion.quick, value: configuration.isPressed)
    }
}

/// Hidden settings for the caregiver on the older person's phone.
struct ElderHelpSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsUnpair = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoahSpacing.l) {
                    Text("Voor de mantelzorger")
                        .font(NoahFont.Elder.title).noahElderTitleScaling()
                        .foregroundColor(NoahColor.text)
                    Text("Deze telefoon is gekoppeld aan HelloNoah. Instellingen wijzigt u in de HelloNoah-app van de mantelzorger.")
                        .font(NoahFont.Elder.body)
                        .foregroundColor(NoahColor.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    if app.isMock {
                        NoahNotice(kind: .warning, text: "Demo-modus staat aan.", large: true)
                    }
                    Button(role: .destructive) {
                        confirmsUnpair = true
                    } label: {
                        Text("Deze telefoon ontkoppelen")
                    }
                    .buttonStyle(.noah(.destructive, size: .elder))
                    Button("Sluiten") { dismiss() }
                        .buttonStyle(.noah(.secondary, size: .elder))
                    Text("Versie \(AppConfig.appVersion)")
                        .font(NoahFont.footnote)
                        .foregroundColor(NoahColor.textSecondary)
                }
                .padding(NoahSpacing.screen)
            }
            .noahScreenBackground()
        }
        .confirmationDialog("Deze telefoon ontkoppelen?", isPresented: $confirmsUnpair, titleVisibility: .visible) {
            Button("Ontkoppelen", role: .destructive) {
                Task {
                    await app.unpairThisDevice()
                    dismiss()
                }
            }
            Button("Annuleren", role: .cancel) {}
        } message: {
            Text("Daarna kan op deze telefoon niet meer met Noah worden gepraat, tot hij opnieuw is gekoppeld met een nieuwe code.")
        }
    }
}
