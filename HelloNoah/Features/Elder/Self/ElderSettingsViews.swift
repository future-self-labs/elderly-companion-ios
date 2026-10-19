import SwiftUI

/// "Instellingen" for an older person who manages Noah themselves (v2.3). One calm list of big
/// rows; every row opens one small screen. Caregiver-managed phones never show this.
struct ElderSettingsView: View {
    @Binding var path: [ElderRoute]
    @EnvironmentObject private var session: ElderSession
    @State private var contactCount: Int?

    var body: some View {
        ElderScrollScreen {
            ElderScreenTitle(title: "Instellingen")
            if contactCount == 0 {
                NoahNotice(kind: .warning, text: "Er staat nog niemand bij uw noodcontacten. Voeg iemand toe die Noah mag waarschuwen als het niet goed met u gaat.",
                           large: true, actionTitle: "Iemand toevoegen") { path.append(.settingsContacts) }
                    .accessibilityIdentifier("settings.noContacts")
            }
            VStack(spacing: NoahSpacing.m) {
                ElderTileButton(title: "Naam, stem en tempo", systemImage: "person.wave.2.fill") { path.append(.settingsNoah) }
                    .accessibilityIdentifier("settings.noah")
                ElderTileButton(title: "Opnemen", systemImage: "record.circle") { path.append(.settingsRecording) }
                    .accessibilityIdentifier("settings.recording")
                ElderTileButton(title: "Noodcontacten", systemImage: "staroflife.fill") { path.append(.settingsContacts) }
                    .accessibilityIdentifier("settings.contacts")
                ElderTileButton(title: "Abonnement", systemImage: "creditcard.fill") { path.append(.settingsSubscription) }
                    .accessibilityIdentifier("settings.subscription")
                ElderTileButton(title: "Familie uitnodigen", systemImage: "person.badge.plus") { path.append(.settingsInvite) }
                    .accessibilityIdentifier("settings.invite")
                ElderTileButton(title: "Wie kijkt er mee", systemImage: "person.2.fill") { path.append(.settingsCaregivers) }
                    .accessibilityIdentifier("settings.caregivers")
                ElderTileButton(title: "Uw gegevens downloaden", systemImage: "square.and.arrow.down") { path.append(.settingsExport) }
                    .accessibilityIdentifier("settings.export")
                ElderTileButton(title: "Account verwijderen", systemImage: "trash.fill", iconTint: NoahColor.dangerText) { path.append(.settingsDelete) }
                    .accessibilityIdentifier("settings.delete")
            }
            Text("HelloNoah \(AppConfig.appVersion) · Een product van Aldery")
                .font(NoahFont.footnote)
                .foregroundColor(NoahColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, NoahSpacing.s)
        }
        .task { contactCount = (try? await session.api.deviceEmergencyContacts())?.count }
    }
}

// MARK: - Naam, stem en tempo

struct ElderNoahSettingsView: View {
    @EnvironmentObject private var session: ElderSession
    @State private var state: Loadable<NoahSettings> = .idle
    @State private var saved: NoahSettings?
    @State private var draft = NoahSettings.defaults
    @State private var name = ""
    @State private var addressForm: AddressForm = .u
    @State private var message: (text: String, isError: Bool)?

    var body: some View {
        ElderScrollScreen {
            ElderScreenTitle(title: "Naam, stem en tempo")
            LoadableView(state: state, large: true, retry: { Task { await load() } }) { _ in
                NoahTextField(label: "Hoe mag Noah u noemen?", text: $name, prompt: "Toos", contentType: .givenName,
                              autocapitalization: .words, large: true)
                    .accessibilityIdentifier("noahSettings.name")
                NoahField(label: "Hoe mag Noah tegen u praten?", large: true) {
                    VStack(spacing: NoahSpacing.s) {
                        NoahOptionCard(title: "Met \u{201C}u\u{201D}", subtitle: AddressForm.u.elderExample, isSelected: addressForm == .u, large: true) { addressForm = .u }
                        NoahOptionCard(title: "Met \u{201C}jij\u{201D}", subtitle: AddressForm.jij.elderExample, isSelected: addressForm == .jij, large: true) { addressForm = .jij }
                    }
                }
                NoahTextField(label: "Naam van Noah", text: $draft.noahName, prompt: "Noah",
                              footnote: "Zo stelt Noah zich aan u voor. Een andere naam mag ook.", autocapitalization: .words, large: true)
                NoahField(label: "Stem", large: true) {
                    VStack(spacing: NoahSpacing.s) {
                        NoahOptionCard(title: NoahVoice.vrouw.label, isSelected: draft.voice == .vrouw, large: true) { draft.voice = .vrouw }
                        NoahOptionCard(title: NoahVoice.man.label, isSelected: draft.voice == .man, large: true) { draft.voice = .man }
                    }
                }
                NoahField(label: "Hoe snel praat Noah?", large: true) {
                    VStack(spacing: NoahSpacing.s) {
                        ForEach(ElderSpeed.allCases, id: \.self) { speed in
                            NoahOptionCard(title: speed.label, subtitle: speed.explanation,
                                           isSelected: ElderSpeed.nearest(to: draft.speakingSpeed) == speed, large: true) {
                                draft.speakingSpeed = speed.value
                            }
                        }
                    }
                }
                if let message { ElderMessage(text: message.text, isError: message.isError) }
                NoahAsyncButton(size: .elder, action: save) { Text("Bewaar") }
                    .disabled(!hasChanges || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("noahSettings.save")
            }
        }
        .task { if saved == nil { await load() } }
    }

    private var hasChanges: Bool {
        draft != saved || name != (session.profile?.preferredName ?? "") || addressForm != (session.profile?.addressForm ?? .u)
    }

    private func load() async {
        state = .loading
        do {
            let settings = try await session.api.deviceSettings()
            if let profile = try? await session.api.deviceProfile() { session.didUpdate(profile: profile) }
            saved = settings
            draft = settings
            name = session.profile?.preferredName ?? session.name
            addressForm = session.profile?.addressForm == .jij ? .jij : .u
            state = .loaded(settings)
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled { state = .failed(apiError) }
        }
    }

    private func save() async {
        message = nil
        do {
            var profilePatch = DeviceProfilePatch()
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != session.profile?.preferredName { profilePatch.preferredName = trimmed }
            if addressForm != session.profile?.addressForm { profilePatch.addressForm = addressForm }
            if !profilePatch.isEmpty {
                session.didUpdate(profile: try await session.api.updateDeviceProfile(profilePatch))
            }
            let patch = NoahSettingsPatch(from: saved, to: draft)
            if !patch.isEmpty {
                let settings = try await session.api.updateDeviceSettings(patch)
                saved = settings
                draft = settings
            }
            message = ("Bewaard. Noah gebruikt dit vanaf het volgende gesprek.", false)
            Task { await session.load() }
        } catch {
            message = (APIError.from(error).elderMessage, true)
        }
    }
}

// MARK: - Opnemen

/// The older person decides about recording themselves (v2.3), with the consent explained in "u".
struct ElderRecordingView: View {
    @EnvironmentObject private var session: ElderSession
    @State private var state: Loadable<NoahSettings> = .idle
    @State private var saved: RecordingSetting?
    @State private var choice: RecordingSetting = .uit
    @State private var message: (text: String, isError: Bool)?

    var body: some View {
        ElderScrollScreen {
            ElderScreenTitle(title: "Opnemen")
            ElderText("Een opname van uw eigen stem kan later heel dierbaar zijn: om zelf terug te luisteren, of voor uw kinderen en kleinkinderen.")
            LoadableView(state: state, large: true, retry: { Task { await load() } }) { _ in
                VStack(spacing: NoahSpacing.s) {
                    ForEach(RecordingSetting.knownCases, id: \.self) { option in
                        NoahOptionCard(title: option.elderLabel, subtitle: option.elderExplanation,
                                       isSelected: choice == option, large: true) { choice = option }
                            .accessibilityIdentifier("recording.\(option.rawValue)")
                    }
                }
                NoahCard(padding: NoahSpacing.l, background: NoahColor.surfaceDeep) {
                    Label {
                        Text("Noah vraagt altijd eerst of het mag").font(NoahFont.Elder.bodyStrong).foregroundColor(NoahColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "hand.raised.fill").foregroundColor(NoahColor.accent)
                    }
                    ElderText("Aan het begin van elk gesprek dat wordt opgenomen, vraagt Noah of u dat goed vindt. Zegt u nee, dan wordt er niets bewaard. U kunt dit altijd weer uitzetten.")
                    ElderText("Opnames worden versleuteld bewaard in de EU. Alleen u en de mensen die u uitnodigt om mee te kijken, kunnen ze beluisteren. Verwijdert u uw account, dan verdwijnen ook de opnames.", color: NoahColor.textSecondary)
                }
                .accessibilityIdentifier("recording.consent")
                if let message { ElderMessage(text: message.text, isError: message.isError) }
                NoahAsyncButton(size: .elder, action: save) { Text("Bewaar") }
                    .disabled(choice == saved)
                    .accessibilityIdentifier("recording.save")
            }
        }
        .task { if saved == nil { await load() } }
    }

    private func load() async {
        state = .loading
        do {
            let settings = try await session.api.deviceSettings()
            saved = settings.recording
            choice = settings.recording == .unknown ? .uit : settings.recording
            state = .loaded(settings)
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled { state = .failed(apiError) }
        }
    }

    private func save() async {
        message = nil
        var patch = NoahSettingsPatch()
        patch.recording = choice
        do {
            let settings = try await session.api.updateDeviceSettings(patch)
            saved = settings.recording
            choice = settings.recording
            message = (choice == .uit ? "Bewaard. Er wordt niets opgenomen." : "Bewaard. Noah vraagt u voortaan eerst of opnemen mag.", false)
        } catch {
            let apiError = APIError.from(error)
            // Recording needs storage on the server; nothing was changed.
            if apiError.status == 503 {
                choice = saved ?? .uit
                message = ("Opnemen is op dit moment niet beschikbaar. Probeert u het later nog eens.", true)
            } else {
                message = (apiError.elderMessage, true)
            }
        }
    }
}

extension RecordingSetting {
    /// The older person's words (v2.3: they decide themselves).
    var elderLabel: String {
        switch self {
        case .uit: return "Niet opnemen"
        case .levensverhaal: return "Alleen als ik een verhaal vertel"
        case .alleGesprekken: return "Alle gesprekken"
        case .unknown: return "Onbekend"
        }
    }

    var elderExplanation: String {
        switch self {
        case .uit: return "Er wordt niets opgenomen."
        case .levensverhaal: return "Alleen de gesprekken waarin u een verhaal vertelt. Zo blijft uw eigen stem bij uw levensverhaal bewaard."
        case .alleGesprekken: return "Elk gesprek met Noah, als u daar ja op zegt."
        case .unknown: return ""
        }
    }
}
