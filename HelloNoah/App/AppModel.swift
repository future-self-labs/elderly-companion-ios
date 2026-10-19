import Foundation
import SwiftUI
import WidgetKit

/// The live or mock wiring of the app.
@MainActor
final class AppEnvironment {
    let config: AppConfig
    let storage: TokenStorage
    let api: NoahAPI
    let client: APIClient?

    /// Always false in Release builds (the mock and every demo branch are compiled out).
    var isMock: Bool {
        #if DEBUG
        return config.useMock
        #else
        return false
        #endif
    }

    init(config: AppConfig) {
        self.config = config
        #if DEBUG
        if config.useMock {
            let mockStorage = KeychainTokenStorage(namespace: "mock")
            storage = mockStorage
            // The mock knows which profile this phone belongs to from the (mock) device token.
            api = MockNoahAPI(deviceToken: { mockStorage.deviceToken })
            client = nil
            Self.applyMockPersona(storage: storage)
            return
        }
        #endif
        storage = KeychainTokenStorage(namespace: "live")
        let client = APIClient(baseURL: config.baseURL, storage: storage)
        self.client = client
        api = LiveNoahAPI(client: client)
    }

    func makeVoiceEngine() -> VoiceEngine {
        #if DEBUG
        if isMock { return MockVoiceEngine() }
        #endif
        return ElevenLabsVoiceEngine()
    }

    #if DEBUG
    /// `-mockPersona caregiver|new|elder|self|none` puts mock mode straight into a state (testing and
    /// screenshots). `self` is Toos, who signed up herself (v2.3). Only applies to the mock namespace.
    private static func applyMockPersona(storage: TokenStorage) {
        guard let persona = UserDefaults.standard.string(forKey: "mockPersona") else { return }
        let tokens = CaregiverTokens(accessToken: "mock-access", accessTokenExpiresAt: Date().addingTimeInterval(3600 * 24 * 365), refreshToken: "hnr_mock")
        switch persona {
        case "caregiver":
            storage.deviceToken = nil
            storage.caregiverTokens = tokens
            UserDefaults.standard.set(MockIDs.anna, forKey: "mock.currentCaregiver")
        case "new":
            storage.deviceToken = nil
            storage.caregiverTokens = tokens
            UserDefaults.standard.set(MockIDs.newCaregiver, forKey: "mock.currentCaregiver")
        case "elder":
            storage.deviceToken = "hnd_mock_\(MockIDs.wim)"
            storage.caregiverTokens = nil
            ElderSession.clearOnboarding()
        case "self":
            storage.deviceToken = "hnd_mock_\(MockIDs.toos)"
            storage.caregiverTokens = nil
            ElderSession.clearOnboarding()
        case "none":
            storage.deviceToken = nil
            storage.caregiverTokens = nil
            ElderSession.clearOnboarding()
        default:
            break
        }
    }
    #endif
}

/// Root state: which interface is shown, and the sessions behind them.
@MainActor
final class AppModel: ObservableObject {
    enum Mode: Equatable {
        case launching
        case welcome
        case elder
        case caregiver
    }

    @Published private(set) var mode: Mode = .launching
    @Published private(set) var environment: AppEnvironment
    @Published private(set) var caregiver: CaregiverSession?
    @Published private(set) var elder: ElderSession?
    /// One-off message shown on the welcome screen (e.g. after the phone was unpaired remotely).
    @Published var welcomeNotice: String?
    /// A link that arrived before the right interface was ready.
    @Published var pendingLink: DeepLink?

    let reachability = Reachability()
    let subscriptions = SubscriptionStore()
    let push = PushManager.shared

    init() {
        environment = AppEnvironment(config: .current())
        start()
    }

    var api: NoahAPI { environment.api }
    var isMock: Bool { environment.isMock }

    func start() {
        // GDPR exports never stay on disk.
        ExportFile.removeAll()
        environment.client?.onSessionExpired = { [weak self] in self?.sessionExpired() }
        environment.client?.onDeviceUnpaired = { [weak self] in self?.deviceUnpairedRemotely() }
        subscriptions.usesMockBackend = environment.isMock
        subscriptions.start()

        if environment.storage.deviceToken != nil {
            enterElder()
        } else if environment.storage.caregiverTokens != nil {
            enterCaregiver()
        } else {
            caregiver = nil
            elder = nil
            mode = .welcome
        }
    }

    // MARK: Transitions

    func didPair(_ response: PairDeviceResponse) {
        environment.storage.deviceToken = response.deviceToken
        enterElder(justPaired: true)
    }

    /// v2.3 self route: the older person verified their own number.
    func didSignUpElder(_ response: ElderSignUpResponse) {
        environment.storage.deviceToken = response.deviceToken
        if response.needsOnboarding {
            ElderSession.clearOnboarding()
            enterElder(justPaired: true)
            elder?.startOnboarding()
        } else {
            enterElder(justPaired: true)
            if response.managedBy == .zelf {
                let name = response.elderly.preferredName
                elder?.arrivalMessage = name.isEmpty ? "Welkom terug! U kunt meteen weer met Noah praten." : "Welkom terug, \(name)! U kunt meteen weer met Noah praten."
            } else {
                elder?.arrivalMessage = "Deze telefoon is gekoppeld aan het account van uw familie. U kunt nu met Noah praten."
            }
        }
    }

    /// v2.3: the older person deleted their own account.
    func elderAccountDeleted() {
        environment.storage.deviceToken = nil
        ElderSession.clearOnboarding()
        elder = nil
        welcomeNotice = "Uw account en al uw gegevens zijn verwijderd."
        if environment.storage.caregiverTokens != nil { enterCaregiver() } else { mode = .welcome }
    }

    func didSignIn(_ auth: AuthResponse) {
        environment.storage.caregiverTokens = CaregiverTokens(
            accessToken: auth.accessToken,
            accessTokenExpiresAt: auth.accessTokenExpiresAt,
            refreshToken: auth.refreshToken
        )
        enterCaregiver()
    }

    func signOut() async {
        if let token = push.deviceToken { try? await api.deletePushToken(token) }
        if let refresh = environment.storage.caregiverTokens?.refreshToken {
            try? await api.logout(refreshToken: refresh)
        }
        environment.storage.caregiverTokens = nil
        push.tokenHandler = nil
        caregiver = nil
        if environment.storage.deviceToken != nil { enterElder() } else { mode = .welcome }
    }

    /// Account deleted: tokens are already invalid on the server.
    func accountDeleted() {
        environment.storage.caregiverTokens = nil
        push.tokenHandler = nil
        caregiver = nil
        welcomeNotice = "Je account is verwijderd."
        mode = .welcome
    }

    func unpairThisDevice() async {
        try? await api.unpairThisDevice()
        environment.storage.deviceToken = nil
        ElderSession.clearOnboarding()
        elder = nil
        welcomeNotice = "Deze telefoon is ontkoppeld."
        if environment.storage.caregiverTokens != nil { enterCaregiver() } else { mode = .welcome }
    }

    private func sessionExpired() {
        guard caregiver != nil else { return }
        caregiver = nil
        push.tokenHandler = nil
        welcomeNotice = "Je bent uitgelogd. Log opnieuw in om verder te gaan."
        mode = .welcome
    }

    private func deviceUnpairedRemotely() {
        ElderSession.clearOnboarding()
        elder = nil
        welcomeNotice = "Deze telefoon is niet meer gekoppeld aan HelloNoah. U kunt zich opnieuw aanmelden met uw telefoonnummer, of uw familie om een nieuwe code vragen."
        mode = environment.storage.caregiverTokens != nil ? .caregiver : .welcome
        if mode == .caregiver { enterCaregiver() }
    }

    private func enterElder(justPaired: Bool = false) {
        caregiver = nil
        let session = ElderSession(api: api, reachability: reachability, subscriptions: subscriptions, makeEngine: { [weak self] in
            self?.environment.makeVoiceEngine() ?? ElevenLabsVoiceEngine()
        })
        session.justPaired = justPaired
        elder = session
        mode = .elder
        // The widget token lets the app's own widget start a conversation with one tap.
        if WidgetLaunch.ensureToken() { WidgetCenter.shared.reloadAllTimelines() }
        if let link = pendingLink {
            pendingLink = nil
            // Right after pairing nothing starts by itself.
            if !justPaired { handle(link) }
        }
    }

    private func enterCaregiver() {
        elder = nil
        let session = CaregiverSession(api: api, subscriptions: subscriptions, push: push, isMock: isMock)
        caregiver = session
        mode = .caregiver
        push.onOpenAlert = { [weak self] alertId, elderlyId in
            self?.caregiver?.openAlert(id: alertId, elderlyId: elderlyId)
        }
        if let pending = push.consumePendingAlert() {
            session.openAlert(id: pending.alertId, elderlyId: pending.elderlyId)
        }
        if let link = pendingLink {
            pendingLink = nil
            handle(link)
        }
    }

    // MARK: Links

    func handle(url: URL) {
        guard let link = DeepLink(url: url, widgetToken: WidgetLaunch.storedToken()) else { return }
        handle(link)
    }

    func handle(_ link: DeepLink) {
        switch (link, mode) {
        case (.talk(let verified), .elder):
            // Only the app's own widget may open the microphone without a visible tap (M11).
            elder?.requestConversation(needsConfirmation: !verified)
        case (.story, .elder):
            elder?.requestConversation(mode: .levensverhaal, needsConfirmation: true)
        case (.invitation(let code), .caregiver):
            caregiver?.router.present(.acceptInvitation(code: code))
        case (.alert(let id, let elderlyId), .caregiver):
            caregiver?.openAlert(id: id, elderlyId: elderlyId)
        case (_, .welcome), (_, .launching):
            // Kept until the right interface is ready (pairing, sign-in).
            pendingLink = link
        default:
            // Not for this interface (e.g. a pairing link on a paired phone, the widget on a
            // caregiver's phone): ignore it instead of keeping it around.
            pendingLink = nil
        }
    }

    // MARK: Mock mode (hidden debug toggle, Debug builds only)

    #if DEBUG
    func setMockMode(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: AppConfig.mockToggleKey)
        environment = AppEnvironment(config: .current())
        caregiver = nil
        elder = nil
        if !enabled, AppConfig.isMockForcedByLaunchArgument {
            welcomeNotice = "Demo-modus is aangezet met het startargument -useMockAPI en blijft aan tot je dat uitzet in Xcode."
        } else {
            welcomeNotice = enabled ? "Demo-modus staat aan: de app gebruikt voorbeeldgegevens." : "Demo-modus staat uit."
        }
        start()
    }
    #endif
}
