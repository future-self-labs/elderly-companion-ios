import Foundation
import SwiftUI

// MARK: - Older person

@MainActor
final class ElderSession: ObservableObject {
    let api: NoahAPI
    let reachability: Reachability
    let subscriptions: SubscriptionStore
    private let makeEngine: () -> VoiceEngine
    private let defaults: UserDefaults

    @Published private(set) var me: Loadable<DeviceMe> = .idle
    /// v2.3 `GET /device/profile`: tells whether the older person manages the profile themselves.
    /// nil until loaded (or on an older backend): then nobody sees the self-managed settings.
    @Published private(set) var profile: DeviceProfile?
    /// Set when a conversation should open (big button, widget, `hellonoah://praat`).
    @Published var isConversationPresented = false
    /// What the next conversation is: "Praat met Noah" or "Vertel een verhaal" (v2.1).
    @Published private(set) var conversationMode: ConversationMode = .gesprek
    /// Opened by a link from outside the app: wait for a tap before the microphone starts (M11).
    @Published private(set) var conversationNeedsConfirmation = false
    @Published var justPaired = false
    /// A calm one-off line on the home screen ("Welkom terug", "Alles staat klaar").
    @Published var arrivalMessage: String?
    /// v2.3: a new self-managed profile still walks through name, voice, emergency contact and
    /// subscription. Kept across launches, so a closed app resumes where it was.
    @Published private(set) var isOnboarding: Bool

    static let onboardingKey = "elder.selfOnboardingPending"

    init(api: NoahAPI, reachability: Reachability, subscriptions: SubscriptionStore, defaults: UserDefaults = .standard,
         makeEngine: @escaping () -> VoiceEngine) {
        self.api = api
        self.reachability = reachability
        self.subscriptions = subscriptions
        self.defaults = defaults
        self.makeEngine = makeEngine
        isOnboarding = defaults.bool(forKey: Self.onboardingKey)
        configureSubscriptions()
    }

    var name: String { profile?.preferredName.nilIfEmpty ?? me.value?.elderly.preferredName ?? "" }
    var noahName: String { me.value?.elderly.noahName ?? "Noah" }
    var elderlyId: String? { me.value?.elderly.id ?? profile?.id }
    /// The older person manages everything themselves: show "Instellingen" (v2.3).
    var isSelfManaged: Bool {
        if let profile { return profile.isSelfManaged }
        return me.value?.resolvedManagedBy == .zelf
    }

    func load() async {
        if me.value == nil { me = .loading }
        async let profileResult = try? api.deviceProfile()
        do {
            me = .loaded(try await api.deviceMe())
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled, me.value == nil { me = .failed(apiError) }
        }
        if let loaded = await profileResult { profile = loaded }
        configureSubscriptions()
    }

    /// Settings changed the name or "u"/"jij".
    func didUpdate(profile: DeviceProfile) {
        var merged = profile
        if merged.id == nil { merged.id = self.profile?.id }
        self.profile = merged
    }

    func startOnboarding() {
        defaults.set(true, forKey: Self.onboardingKey)
        isOnboarding = true
    }

    func finishOnboarding() {
        defaults.removeObject(forKey: Self.onboardingKey)
        isOnboarding = false
        arrivalMessage = "Alles staat klaar. Tik op de grote knop om met \(noahName) te praten."
        Task { await load() }
    }

    static func clearOnboarding(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: onboardingKey)
    }

    /// Purchases on this phone go to the device endpoint, and only for this person's own profile:
    /// the same Apple ID may pay for other people elsewhere, those transactions are left alone.
    private func configureSubscriptions() {
        subscriptions.audience = .elder
        subscriptions.redeemsOnlyKnownProfiles = true
        let selfId = isSelfManaged ? elderlyId : nil
        subscriptions.knownElderlyIds = selfId.map { [$0] } ?? []
        subscriptions.knownElderlyNames = selfId.map { [$0.lowercased(): name] } ?? [:]
        guard selfId != nil else {
            // Caregiver-managed: the family pays; nothing is redeemed from this phone.
            subscriptions.submit = nil
            subscriptions.hasActiveAppStoreSubscription = nil
            return
        }
        subscriptions.submit = { [weak self] _, jws in
            guard let self else { throw APIError.cancelled }
            let subscription = try await self.api.submitDeviceAppStoreTransaction(signedTransaction: jws)
            await self.load()
            return subscription
        }
        subscriptions.hasActiveAppStoreSubscription = { [weak self] in
            guard let self, let subscription = try? await self.api.deviceSubscription() else { return false }
            return subscription.isPaidOrBeta && subscription.platform == "app_store" && subscription.paidByMe != false
        }
    }

    /// - Parameter needsConfirmation: true for links from outside the app (not the big button,
    ///   not the app's own widget): the screen opens, the conversation starts after a tap.
    func requestConversation(mode: ConversationMode = .gesprek, needsConfirmation: Bool = false) {
        guard !isConversationPresented else { return }
        conversationMode = mode
        conversationNeedsConfirmation = needsConfirmation
        isConversationPresented = true
    }

    func makeConversationController() -> ConversationController {
        ConversationController(api: api, reachability: reachability, mode: conversationMode, noahName: noahName,
                               isSelfManaged: isSelfManaged, makeEngine: makeEngine)
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : self
    }
}

// MARK: - Caregiver

enum CaregiverTab: Hashable {
    case overview, conversations, lifeStory, reminders, more
}

enum CaregiverRoute: Hashable {
    case conversation(id: String)
    case alerts
    case alert(id: String)
    case mood
    case lifeStoryEntry(LifeStoryEntry)
    case noahSettings
    case profile
    case people
    case emergencyContacts
    case phoneLine
    case caregivers
    case devices
    case pairDevice
    case subscription
    case account
    case elderlyList
}

enum CaregiverSheet: Identifiable, Equatable {
    case wizard
    case paywall(elderlyId: String)
    case acceptInvitation(code: String?)

    var id: String {
        switch self {
        case .wizard: return "wizard"
        case .paywall(let id): return "paywall-\(id)"
        case .acceptInvitation(let code): return "invite-\(code ?? "")"
        }
    }
}

@MainActor
final class CaregiverRouter: ObservableObject {
    @Published var tab: CaregiverTab = .overview
    @Published var overviewPath = NavigationPath()
    @Published var conversationsPath = NavigationPath()
    @Published var lifeStoryPath = NavigationPath()
    @Published var remindersPath = NavigationPath()
    @Published var morePath = NavigationPath()
    @Published var sheet: CaregiverSheet?

    func present(_ sheet: CaregiverSheet) {
        self.sheet = sheet
    }

    func show(_ route: CaregiverRoute, in tab: CaregiverTab) {
        self.tab = tab
        switch tab {
        case .overview: overviewPath.append(route)
        case .conversations: conversationsPath.append(route)
        case .lifeStory: lifeStoryPath.append(route)
        case .reminders: remindersPath.append(route)
        case .more: morePath.append(route)
        }
    }

    func resetPaths() {
        overviewPath = NavigationPath()
        conversationsPath = NavigationPath()
        lifeStoryPath = NavigationPath()
        remindersPath = NavigationPath()
        morePath = NavigationPath()
    }
}

@MainActor
final class CaregiverSession: ObservableObject {
    let api: NoahAPI
    let subscriptions: SubscriptionStore
    let push: PushManager
    let isMock: Bool
    let router = CaregiverRouter()

    @Published private(set) var me: MeResponse?
    @Published private(set) var meError: APIError?
    @Published private(set) var isLoadingMe = false
    @Published private(set) var selectedElderlyId: String?
    /// Bumped whenever data changed somewhere, so other screens reload.
    @Published private(set) var dataVersion = 0
    /// Whether to show the push pre-prompt card on the dashboard.
    @Published var pushPromptDismissed = UserDefaults.standard.bool(forKey: "caregiver.pushPromptDismissed") {
        didSet { UserDefaults.standard.set(pushPromptDismissed, forKey: "caregiver.pushPromptDismissed") }
    }

    private static let selectedKey = "caregiver.selectedElderlyId"

    init(api: NoahAPI, subscriptions: SubscriptionStore, push: PushManager, isMock: Bool) {
        self.api = api
        self.subscriptions = subscriptions
        self.push = push
        self.isMock = isMock
        selectedElderlyId = UserDefaults.standard.string(forKey: Self.selectedKey)
        subscriptions.audience = .caregiver
        subscriptions.redeemsOnlyKnownProfiles = false
        subscriptions.submit = { [weak self] elderlyId, jws in
            guard let self else { throw APIError.cancelled }
            let subscription = try await self.api.submitAppStoreTransaction(elderlyId: elderlyId, signedTransaction: jws)
            await self.reloadMe()
            return subscription
        }
        subscriptions.hasActiveAppStoreSubscription = { [weak self] in
            guard let self else { return false }
            if self.me == nil { await self.reloadMe() }
            for profile in self.elderly where profile.role == .beheerder {
                if let subscription = try? await self.api.subscription(elderlyId: profile.id),
                   subscription.status == .actief || subscription.status == .intro,
                   subscription.platform == "app_store", subscription.paidByMe != false {
                    return true
                }
            }
            return false
        }
        push.tokenHandler = { [weak self] token in
            try? await self?.api.registerPushToken(token, environment: AppConfig.pushEnvironment)
        }
        // Load right away, independent of any view's lifecycle (a cancelled `.task` must never
        // leave the caregiver on an endless spinner).
        Task { [weak self] in await self?.reloadMe() }
    }

    var caregiver: Caregiver? { me?.caregiver }
    var elderly: [ElderlySummary] { me?.elderly ?? [] }
    var selected: ElderlySummary? {
        elderly.first { $0.id == selectedElderlyId }
            ?? elderly.first { $0.role == .beheerder }
            ?? elderly.first
    }
    var permissions: Permissions { Permissions(role: selected?.role ?? .unknown) }
    var firstName: String {
        caregiver?.name?.split(separator: " ").first.map(String.init) ?? ""
    }
    var needsOnboarding: Bool { me != nil && elderly.isEmpty }

    func reloadMe() async {
        isLoadingMe = true
        defer { isLoadingMe = false }
        do {
            let response = try await api.me()
            me = response
            meError = nil
            if selected?.id != selectedElderlyId { selectedElderlyId = selected?.id }
            subscriptions.knownElderlyIds = response.elderly.map(\.id)
            subscriptions.knownElderlyNames = Dictionary(response.elderly.map { ($0.id.lowercased(), $0.preferredName) }, uniquingKeysWith: { first, _ in first })
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled { meError = apiError }
        }
    }

    func select(_ id: String) {
        guard id != selectedElderlyId else { return }
        selectedElderlyId = id
        UserDefaults.standard.set(id, forKey: Self.selectedKey)
        router.resetPaths()
        dataVersion += 1
    }

    func dataChanged() {
        dataVersion += 1
    }

    /// After creating a profile or accepting an invitation.
    func didAddElderly(id: String) async {
        await reloadMe()
        select(id)
        dataVersion += 1
    }

    func openAlert(id: String, elderlyId: String?) {
        if let elderlyId, elderly.contains(where: { $0.id == elderlyId }) || me == nil {
            selectedElderlyId = elderlyId
            UserDefaults.standard.set(elderlyId, forKey: Self.selectedKey)
        }
        router.sheet = nil
        router.resetPaths()
        router.show(.alert(id: id), in: .overview)
    }
}
