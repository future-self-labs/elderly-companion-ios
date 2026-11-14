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
    /// v2.4 `GET /device/transparency`: who reads along and what. nil until loaded, and on an
    /// older backend (then `transparencyFallback` is used).
    @Published private(set) var transparency: DeviceTransparency?
    /// v2.4: the backend has no transparency endpoint yet; the screen is built from
    /// `GET /device/caregivers` instead.
    @Published private(set) var transparencyUnsupported = false
    /// "Wie kijkt er mee" opens once after pairing/sign-in (v2.4: while `appShownAt` is null).
    @Published var isTransparencyIntroPresented = false
    /// Set to open "Wie kijkt er mee" on the home stack (from a device push).
    @Published var opensTransparency = false

    func openTransparency() { opensTransparency = true }

    static let onboardingKey = "elder.selfOnboardingPending"
    /// Offline, the home screen still greets by name and knows the last conversation (audit L18).
    static let cachedNameKey = "elder.cachedName"
    static let cachedLastConversationKey = "elder.cachedLastConversation"
    /// Older backend: the transparency intro was shown on this phone.
    static let transparencyShownLocallyKey = "elder.transparencyShownLocally"
    private var loadTask: Task<Void, Never>?

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

    var name: String {
        profile?.preferredName.nilIfEmpty ?? me.value?.elderly.preferredName.nilIfEmpty ?? defaults.string(forKey: Self.cachedNameKey) ?? ""
    }
    /// The last conversation, also when offline (cached).
    var lastConversationAt: Date? {
        me.value?.lastConversationAt ?? (defaults.object(forKey: Self.cachedLastConversationKey) as? Date)
    }
    /// v2.4: this phone was just signed in on a profile in use and waits for approval.
    var isRestricted: Bool { me.value?.restricted == true }
    var restrictedUntil: Date? { me.value?.restrictedUntil }
    /// v2.4: on `GET /device/me` and `GET /device/profile` (backend v2.4 §6).
    var outboundPaused: Bool? { me.value?.outboundPaused ?? profile?.outboundPaused }
    var noahName: String { me.value?.elderly.noahName ?? "Noah" }
    var elderlyId: String? { me.value?.elderly.id ?? profile?.id }
    /// The older person manages everything themselves: show "Instellingen" (v2.3).
    var isSelfManaged: Bool {
        if let profile { return profile.isSelfManaged }
        return me.value?.resolvedManagedBy == .zelf
    }

    /// Loads the home data. Calls that overlap (the screen appearing and the app becoming active
    /// at the same moment) share one round of requests (audit L20).
    func load() async {
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { await performLoad() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func performLoad() async {
        if me.value == nil { me = .loading }
        async let profileResult = try? api.deviceProfile()
        async let transparencyResult = loadTransparency()
        do {
            let loaded = try await api.deviceMe()
            me = .loaded(loaded)
            if !loaded.elderly.preferredName.isEmpty { defaults.set(loaded.elderly.preferredName, forKey: Self.cachedNameKey) }
            if let last = loaded.lastConversationAt { defaults.set(last, forKey: Self.cachedLastConversationKey) }
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled, me.value == nil { me = .failed(apiError) }
        }
        if let loaded = await profileResult { profile = loaded }
        await transparencyResult
        configureSubscriptions()
        // A purchase that was paid but not yet accepted gets another try now the profile is known (M12).
        if isSelfManaged { subscriptions.retryUnfinished() }
        presentTransparencyIntroIfNeeded()
    }

    /// v2.4: who reads along. 404 = older backend: fall back, never show an error.
    func loadTransparency() async {
        do {
            transparency = try await api.deviceTransparency()
            transparencyUnsupported = false
        } catch {
            let apiError = APIError.from(error)
            if apiError.isFeatureUnavailable { transparencyUnsupported = true }
        }
    }

    func didUpdate(transparency: DeviceTransparency) {
        self.transparency = transparency
    }

    /// Shown once after pairing or signing in, for both kinds of profile (v2.4).
    private func presentTransparencyIntroIfNeeded() {
        guard !isOnboarding, !isTransparencyIntroPresented, !isConversationPresented else { return }
        if let transparency {
            if transparency.appShownAt == nil { isTransparencyIntroPresented = true }
        } else if transparencyUnsupported, justPaired, !defaults.bool(forKey: Self.transparencyShownLocallyKey) {
            // Older backend: show it once on this phone after pairing.
            isTransparencyIntroPresented = true
        }
    }

    /// "Ik heb het gelezen" on the intro.
    func transparencyIntroSeen() async {
        isTransparencyIntroPresented = false
        defaults.set(true, forKey: Self.transparencyShownLocallyKey)
        do {
            try await api.markTransparencySeen()
            transparency?.appShownAt = Date()
        } catch {
            // Older backend or offline: the local flag keeps it from coming back on this phone.
        }
    }

    /// v2.4 device pushes ("iemand wil meekijken"): register this phone's token once the person
    /// allowed notifications themselves (from the transparency screen). Never asked at launch.
    func registerForDeviceNotices(push: PushManager) {
        push.tokenHandler = { [weak self] token in
            try? await self?.api.registerDevicePushToken(token, environment: AppConfig.pushEnvironment)
        }
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
        // The self route explains "Wie kijkt er mee" itself (nobody yet); don't show it again now.
        defaults.set(true, forKey: Self.transparencyShownLocallyKey)
        isOnboarding = false
        arrivalMessage = "Alles staat klaar. Tik op de grote knop om met \(noahName) te praten."
        Task { await load() }
    }

    static func clearOnboarding(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: onboardingKey)
    }

    /// The phone left HelloNoah: forget everything cached about the person.
    static func clearCache(defaults: UserDefaults = .standard) {
        clearOnboarding(defaults: defaults)
        for key in [cachedNameKey, cachedLastConversationKey, transparencyShownLocallyKey] { defaults.removeObject(forKey: key) }
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
    /// v2.4: "Vertel het Wim" (read-aloud text, then "Ik heb het verteld").
    case tellElderly
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
    /// A one-off message on the dashboard (e.g. a link that is meant for another phone).
    @Published var notice: String?
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
            Self.cache(response)
            if selected?.id != selectedElderlyId { selectedElderlyId = selected?.id }
            subscriptions.knownElderlyIds = response.elderly.map(\.id)
            subscriptions.knownElderlyNames = Dictionary(response.elderly.map { ($0.id.lowercased(), $0.preferredName) }, uniquingKeysWith: { first, _ in first })
            // A paid but not yet accepted purchase gets another try now the profiles are known (M12).
            subscriptions.retryUnfinished()
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled { meError = apiError }
            // Offline at launch: keep the tab bar with the last known people (audit L21); every
            // screen then shows its own offline state and the banner says why.
            if me == nil, apiError.isOffline, let cached = Self.cachedMe() { me = cached }
        }
    }

    private static let cachedMeKey = "caregiver.cachedMe"

    private struct CachedMe: Codable {
        let caregiver: Caregiver
        let elderly: [ElderlySummary]
    }

    private static func cache(_ response: MeResponse) {
        UserDefaults.standard.set(try? JSONEncoder().encode(CachedMe(caregiver: response.caregiver, elderly: response.elderly)), forKey: cachedMeKey)
    }

    private static func cachedMe() -> MeResponse? {
        guard let data = UserDefaults.standard.data(forKey: cachedMeKey),
              let cached = try? JSONDecoder().decode(CachedMe.self, from: data) else { return nil }
        return MeResponse(caregiver: cached.caregiver, elderly: cached.elderly)
    }

    static func clearCache() {
        UserDefaults.standard.removeObject(forKey: cachedMeKey)
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
