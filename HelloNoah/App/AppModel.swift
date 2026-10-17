import Foundation
import SwiftUI

/// The live or mock wiring of the app.
@MainActor
final class AppEnvironment {
    let config: AppConfig
    let storage: TokenStorage
    let api: NoahAPI
    let client: APIClient?

    var isMock: Bool { config.useMock }

    init(config: AppConfig) {
        self.config = config
        if config.useMock {
            storage = KeychainTokenStorage(namespace: "mock")
            api = MockNoahAPI()
            client = nil
            Self.applyMockPersona(storage: storage)
        } else {
            storage = KeychainTokenStorage(namespace: "live")
            let client = APIClient(baseURL: config.baseURL, storage: storage)
            self.client = client
            api = LiveNoahAPI(client: client)
        }
    }

    func makeVoiceEngine() -> VoiceEngine {
        isMock ? MockVoiceEngine() : ElevenLabsVoiceEngine()
    }

    /// `-mockPersona caregiver|new|elder|none` puts mock mode straight into a state (testing and
    /// screenshots). Only applies to the mock namespace.
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
        case "none":
            storage.deviceToken = nil
            storage.caregiverTokens = nil
        default:
            break
        }
    }
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
        environment.client?.onSessionExpired = { [weak self] in self?.sessionExpired() }
        environment.client?.onDeviceUnpaired = { [weak self] in self?.deviceUnpairedRemotely() }
        subscriptions.allowsDemoPurchase = environment.isMock
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
        mode = environment.storage.deviceToken != nil ? .elder : .welcome
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
        elder = nil
        welcomeNotice = "Deze telefoon is niet meer gekoppeld aan HelloNoah. Vraag uw mantelzorger om een nieuwe code."
        mode = environment.storage.caregiverTokens != nil ? .caregiver : .welcome
        if mode == .caregiver { enterCaregiver() }
    }

    private func enterElder(justPaired: Bool = false) {
        caregiver = nil
        let session = ElderSession(api: api, reachability: reachability, makeEngine: { [weak self] in
            self?.environment.makeVoiceEngine() ?? MockVoiceEngine()
        })
        session.justPaired = justPaired
        elder = session
        mode = .elder
        if pendingLink == .talk || pendingLink == .story {
            session.requestConversation(mode: pendingLink == .story ? .levensverhaal : .gesprek)
            pendingLink = nil
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
        guard let link = DeepLink(url: url) else { return }
        handle(link)
    }

    func handle(_ link: DeepLink) {
        switch (link, mode) {
        case (.talk, .elder):
            elder?.requestConversation()
        case (.story, .elder):
            elder?.requestConversation(mode: .levensverhaal)
        case (.invitation(let code), .caregiver):
            caregiver?.router.present(.acceptInvitation(code: code))
        case (.alert(let id, let elderlyId), .caregiver):
            caregiver?.openAlert(id: id, elderlyId: elderlyId)
        case (.pair, .welcome), (.invitation, .welcome), (.talk, .welcome), (.talk, .launching), (.story, .welcome), (.story, .launching):
            pendingLink = link
        default:
            pendingLink = link
        }
    }

    // MARK: Mock mode (hidden debug toggle)

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
}
