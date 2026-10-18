import Foundation
import SwiftUI

// MARK: - Older person

@MainActor
final class ElderSession: ObservableObject {
    let api: NoahAPI
    let reachability: Reachability
    private let makeEngine: () -> VoiceEngine

    @Published private(set) var me: Loadable<DeviceMe> = .idle
    /// Set when a conversation should open (big button, widget, `hellonoah://praat`).
    @Published var isConversationPresented = false
    /// What the next conversation is: "Praat met Noah" or "Vertel een verhaal" (v2.1).
    @Published private(set) var conversationMode: ConversationMode = .gesprek
    @Published var justPaired = false

    init(api: NoahAPI, reachability: Reachability, makeEngine: @escaping () -> VoiceEngine) {
        self.api = api
        self.reachability = reachability
        self.makeEngine = makeEngine
    }

    var name: String { me.value?.elderly.preferredName ?? "" }
    var noahName: String { me.value?.elderly.noahName ?? "Noah" }

    func load() async {
        if me.value == nil { me = .loading }
        do {
            me = .loaded(try await api.deviceMe())
        } catch {
            let apiError = APIError.from(error)
            if apiError == .cancelled { return }
            if me.value == nil { me = .failed(apiError) }
        }
    }

    func requestConversation(mode: ConversationMode = .gesprek) {
        guard !isConversationPresented else { return }
        conversationMode = mode
        isConversationPresented = true
    }

    func makeConversationController() -> ConversationController {
        ConversationController(api: api, reachability: reachability, mode: conversationMode, noahName: noahName, makeEngine: makeEngine)
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
