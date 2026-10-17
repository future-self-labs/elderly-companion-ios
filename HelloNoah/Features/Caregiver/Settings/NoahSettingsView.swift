import SwiftUI

/// Noah's name, voice, speed, max length, no-contact alert, morning call, quiet hours and
/// recording (v2.1). The whole screen is beheerder-only.
struct NoahSettingsView: View {
    @EnvironmentObject private var session: CaregiverSession
    @State private var state: Loadable<NoahSettings> = .idle
    @State private var draft = NoahSettings.defaults
    @State private var saved: NoahSettings?
    @State private var message: (text: String, isError: Bool)?

    var body: some View {
        NoahScrollScreen {
            if !session.permissions.canEditSettings { ReadOnlyNotice() }
            LoadableView(state: state, retry: { Task { await load() } }) { _ in
                NoahSettingsForm(settings: $draft, elderlyName: session.selected?.preferredName ?? "")
                    .disabled(!session.permissions.canEditSettings)
                if let message { NoahNotice(kind: message.isError ? .error : .success, text: message.text) }
                if session.permissions.canEditSettings {
                    NoahAsyncButton("Bewaar instellingen") { await save() }
                        .disabled(draft == saved)
                        .accessibilityIdentifier("settings.save")
                }
            }
        }
        .navigationTitle("Noah-instellingen")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.reloadKey) { await load() }
    }

    private func load() async {
        guard let id = session.selected?.id else { return }
        if saved == nil { state = .loading }
        do {
            let settings = try await session.api.settings(elderlyId: id)
            saved = settings
            draft = settings
            state = .loaded(settings)
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled { state = .failed(apiError) }
        }
    }

    private func save() async {
        guard let id = session.selected?.id else { return }
        do {
            let settings = try await session.api.updateSettings(elderlyId: id, draft)
            saved = settings
            draft = settings
            message = ("Opgeslagen. Noah gebruikt de nieuwe instellingen vanaf het volgende gesprek.", false)
        } catch {
            message = (APIError.from(error).userMessage, true)
        }
    }
}

/// Shared between the settings screen and the profile wizard.
struct NoahSettingsForm: View {
    @Binding var settings: NoahSettings
    let elderlyName: String

    var body: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.l) {
            NoahTextField(label: "Naam van Noah", text: $settings.noahName, prompt: "Noah",
                          footnote: "Zo stelt Noah zich voor. Je kunt een andere naam kiezen als dat prettiger voelt.")

            NoahField(label: "Stem") {
                VStack(spacing: NoahSpacing.s) {
                    NoahOptionCard(title: NoahVoice.vrouw.label, isSelected: settings.voice == .vrouw) { settings.voice = .vrouw }
                    NoahOptionCard(title: NoahVoice.man.label, isSelected: settings.voice == .man) { settings.voice = .man }
                }
            }

            NoahField(label: "Spreektempo", footnote: "Iets rustiger praten helpt vaak bij slechthorendheid.") {
                VStack(spacing: NoahSpacing.xs) {
                    Slider(value: $settings.speakingSpeed, in: NoahSettings.speedRange, step: 0.05) {
                        Text("Spreektempo")
                    }
                    .accessibilityValue(Text(speedLabel))
                    HStack {
                        Text("Rustig").font(NoahFont.footnote).foregroundColor(NoahColor.textSecondary)
                        Spacer()
                        Text(verbatim: speedLabel).font(NoahFont.semibold(13, relativeTo: .footnote)).foregroundColor(NoahColor.accent)
                        Spacer()
                        Text("Vlot").font(NoahFont.footnote).foregroundColor(NoahColor.textSecondary)
                    }
                }
                .noahInputBox()
            }

            NoahField(label: "Maximale gesprekslengte") {
                Stepper(value: $settings.maxConversationMinutes, in: NoahSettings.minutesRange, step: 5) {
                    Text("\(settings.maxConversationMinutes) minuten").font(NoahFont.bodyText).foregroundColor(NoahColor.text)
                }
                .noahInputBox()
            }

            NoahField(label: "Waarschuw me bij geen contact",
                      footnote: "Je krijgt een melding als \(elderlyName.isEmpty ? "je naaste" : elderlyName) zo lang niet met Noah heeft gepraat.") {
                Stepper(value: $settings.noContactAlertDays, in: NoahSettings.noContactRange) {
                    Text(settings.noContactAlertDays == 1 ? "Na 1 dag" : "Na \(settings.noContactAlertDays) dagen")
                        .font(NoahFont.bodyText).foregroundColor(NoahColor.text)
                }
                .noahInputBox()
            }

            NoahField(label: "Ochtendgesprek", footnote: "Noah belt dan elke gekozen dag om een goedemorgen te wensen en de dag door te nemen.") {
                VStack(alignment: .leading, spacing: NoahSpacing.s) {
                    Toggle(isOn: $settings.morningCall.enabled) {
                        Text("Noah belt elke ochtend").font(NoahFont.bodyText).foregroundColor(NoahColor.text)
                    }
                    if settings.morningCall.enabled {
                        TimeField(title: "Tijd", time: $settings.morningCall.time)
                        FlowLayout {
                            ForEach(1...7, id: \.self) { day in
                                NoahChoiceChip(title: Weekdays.shortNames[day]!, isSelected: settings.morningCall.weekdays.contains(day)) {
                                    if let index = settings.morningCall.weekdays.firstIndex(of: day) {
                                        settings.morningCall.weekdays.remove(at: index)
                                    } else {
                                        settings.morningCall.weekdays.append(day)
                                        settings.morningCall.weekdays.sort()
                                    }
                                }
                                .accessibilityLabel(Text(verbatim: Weekdays.names[day]!))
                            }
                        }
                    }
                }
                .noahInputBox()
            }

            NoahField(label: "Rusttijden", footnote: "In deze tijd belt Noah nooit, behalve bij een noodgeval.") {
                VStack(spacing: NoahSpacing.s) {
                    TimeField(title: "Vanaf", time: $settings.quietHours.start)
                    TimeField(title: "Tot", time: $settings.quietHours.end)
                }
                .noahInputBox()
            }

            recording
        }
    }

    private var name: String { elderlyName.isEmpty ? "je naaste" : elderlyName }

    /// Recording is a choice (contract v2.1 point 2). Noah always asks permission first.
    private var recording: some View {
        NoahField(label: "Gesprekken opnemen") {
            VStack(alignment: .leading, spacing: NoahSpacing.s) {
                ForEach(RecordingSetting.knownCases, id: \.self) { option in
                    NoahOptionCard(title: option.label, subtitle: option.explanation(name: name),
                                   isSelected: settings.recording == option) { settings.recording = option }
                        .accessibilityIdentifier("settings.recording.\(option.rawValue)")
                }
                VStack(alignment: .leading, spacing: NoahSpacing.xs) {
                    Label("Noah vraagt altijd eerst toestemming", systemImage: "hand.raised.fill")
                        .font(NoahFont.bodyStrong)
                        .foregroundColor(NoahColor.text)
                    Text("Aan het begin van elk gesprek dat wordt opgenomen, vraagt Noah \(name) of dat goed is. Zegt \(name) nee, dan wordt er niets bewaard.")
                        .font(NoahFont.callout)
                        .foregroundColor(NoahColor.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Een opname kan later heel dierbaar zijn: de eigen stem van \(name), die een verhaal vertelt. Om zelf terug te luisteren, of samen met de kleinkinderen.")
                        .font(NoahFont.callout)
                        .foregroundColor(NoahColor.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Opnames worden versleuteld opgeslagen in de EU. Alleen \(name) zelf en de mantelzorgers van \(name) kunnen ze beluisteren. Verwijder je het profiel, dan verdwijnen ook de opnames.")
                        .font(NoahFont.footnote)
                        .foregroundColor(NoahColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(NoahSpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: NoahRadius.medium, style: .continuous).fill(NoahColor.surfaceDeep))
            }
        }
        .accessibilityIdentifier("settings.recording")
    }

    private var speedLabel: String {
        switch settings.speakingSpeed {
        case ..<0.9: return "Rustig"
        case ..<0.98: return "Iets rustiger"
        case ...1.02: return "Normaal"
        case ..<1.1: return "Iets vlotter"
        default: return "Vlot"
        }
    }
}

/// Edits a contract `HH:mm` time (Europe/Amsterdam) with a wheel-free compact picker.
struct TimeField: View {
    let title: LocalizedStringKey
    @Binding var time: String

    var body: some View {
        DatePicker(selection: Binding(
            get: { DutchFormat.date(fromTime: time) },
            set: { time = DutchFormat.timeString(from: $0) }
        ), displayedComponents: .hourAndMinute) {
            Text(title).font(NoahFont.bodyText).foregroundColor(NoahColor.text)
        }
        .environment(\.timeZone, DutchFormat.timeZone)
        .environment(\.locale, DutchFormat.locale)
    }
}
