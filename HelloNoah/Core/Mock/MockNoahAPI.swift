import Foundation

// Mock mode exists only in Debug builds: Release (TestFlight, App Store) cannot reach it.
#if DEBUG

/// In-memory implementation of API v2 for testing every screen without a backend.
///
/// Behaviour worth knowing when testing:
/// - Sign in with Apple → existing caregiver Anna (Wim as beheerder, Riet as lezer).
/// - Phone sign-in with any number and any 6-digit code → a brand-new caregiver without profiles
///   (to walk through the profile wizard). Code `000000` is rejected.
/// - Pairing code: any 6 digits pair this phone with Wim; `000000` is rejected.
/// - Role rules are enforced: writes on Riet's profile fail with 403 like the real backend.
/// - Launch arguments: `-mockLatency <seconds>`, `-mockOffline YES` (every call fails offline),
///   `-mockInactive YES` (Wim's profile inactive, to see the 409 flows), `-mockOverAllowance YES`
///   (Wim used up this month's fair use: shorter conversations, notice on the subscription screen).
/// - v2.1: Wim's recording setting is "alleen bij levensverhalen"; his story conversations and two
///   life-story entries have a (generated, demo) recording.
/// - v2.3 self route: Toos manages her own profile (`-mockPersona self`). Self sign-up with any
///   number and any 6-digit code (`000000` is rejected) creates a new self profile; Wim's number
///   (06 23456789) pairs to Wim instead ("gekoppeld aan het account van uw familie"), Toos's number
///   (06 45678901) signs Toos in again. Device endpoints answer `403 beheerd_door_mantelzorger` for
///   Wim and Riet. The phone's profile follows the (mock) device token.
/// - v2.4: one of Wim's conversations is private ("wilde dit gesprek voor zichzelf houden"), alerts
///   say what really went out (`delivery`). Bep's number (06 11223344) was set up by Mark and never
///   used: self sign-up asks "Kent u deze persoon?". Signing up again on a profile that is in use
///   gives a restricted phone (`-mockRestricted YES` makes this phone restricted). Wim's pending
///   requests, invitations and devices are seeded for the transparency screen;
///   `-mockTransparencyUnseen YES` makes Wim's phone show "Wie kijkt er mee" once.
///   `-mockV23Backend YES` answers 404 on every v2.4 endpoint (graceful degradation).
/// Data lives in memory and resets at each launch, except self sign-ups (kept in UserDefaults so
/// a relaunch still knows the new profile).
final class MockNoahAPI: NoahAPI {
    private let lock = NSLock()
    private let latency: TimeInterval
    private let offline: Bool
    private let overAllowance: Bool
    private let defaults: UserDefaults
    /// The device token of this phone (mock tokens are `hnd_mock_<elderlyId>`).
    private let deviceToken: () -> String?

    // MARK: State

    private var caregiverRecords: [String: Caregiver] = [:]
    private var currentCaregiverId: String {
        get { defaults.string(forKey: "mock.currentCaregiver") ?? MockIDs.anna }
        set { defaults.set(newValue, forKey: "mock.currentCaregiver") }
    }
    private var profiles: [String: ElderlyProfile] = [:]
    /// elderlyId → caregiverId → role
    private var memberships: [String: [String: Role]] = [:]
    private var joinedAt: [String: Date] = [:]
    private var peopleByElderly: [String: [Person]] = [:]
    private var settingsByElderly: [String: NoahSettings] = [:]
    private var contacts: [String: [EmergencyContact]] = [:]
    private var conversationsByElderly: [String: [ConversationDetail]] = [:]
    private var lifeStories: [String: [LifeStoryEntry]] = [:]
    private var remindersByElderly: [String: [Reminder]] = [:]
    private var alertsByElderly: [String: [NoahAlert]] = [:]
    private var devicesByElderly: [String: [PairedDevice]] = [:]
    private var subscriptions: [String: Subscription] = [:]
    private var invitations: [String: MockInvitation] = [:]
    private var pairingCodes: [String: String] = [:]
    // v2.4
    private struct MockInvitation {
        let id: String
        let code: String
        let elderlyId: String
        let role: Role
        let createdAt: Date
        let expiresAt: Date
        /// "zelf" or the caregiver's name.
        let createdBy: String
        var fromDevice: Bool { createdBy == "zelf" }
    }
    private struct MockRequest {
        let request: CaregiverRequest
        let caregiverId: String
        let elderlyId: String
    }
    private var caregiverRequests: [MockRequest] = []
    private var transparency: [String: Transparency] = [:]
    private var sharingByElderly: [String: SharingLevel] = [:]
    private var outboundPaused: Set<String> = []
    private var deletionRequests: [String: DeletionRequest] = [:]
    private var selfRegistered: Set<String> = []
    /// Device id per mock device token holder (this phone).
    private var thisDeviceId: [String: String] = [:]
    /// Answers 404 on every v2.4 endpoint, like a backend that is not updated yet.
    private let v23Backend: Bool
    private let restrictedPhone: Bool

    init(defaults: UserDefaults = .standard, now: Date = Date(), deviceToken: @escaping () -> String? = { nil }) {
        self.defaults = defaults
        self.deviceToken = deviceToken
        latency = defaults.object(forKey: "mockLatency") == nil ? 0.35 : defaults.double(forKey: "mockLatency")
        offline = defaults.bool(forKey: "mockOffline")
        overAllowance = defaults.bool(forKey: "mockOverAllowance")
        v23Backend = defaults.bool(forKey: "mockV23Backend")
        restrictedPhone = defaults.bool(forKey: "mockRestricted")
        seed(now: now, inactive: defaults.bool(forKey: "mockInactive"))
        seedSelfProfiles(now: now)
        restoreSelfSignUps()
    }

    // MARK: Seed

    private func seed(now: Date, inactive: Bool) {
        let calendar = DutchFormat.calendar
        caregiverRecords[MockIDs.anna] = Caregiver(id: MockIDs.anna, name: "Anna de Vries", email: "anna@example.com", phoneNumber: "+31612340000", createdAt: now.addingTimeInterval(-86_400 * 40))
        caregiverRecords[MockIDs.mark] = Caregiver(id: MockIDs.mark, name: "Mark de Vries", email: "mark@example.com", phoneNumber: "+31687654321", createdAt: now.addingTimeInterval(-86_400 * 38))
        caregiverRecords[MockIDs.newCaregiver] = Caregiver(id: MockIDs.newCaregiver, name: nil, email: nil, phoneNumber: "+31611112222", createdAt: now)

        profiles[MockIDs.wim] = ElderlyProfile(
            id: MockIDs.wim, firstName: "Willem", lastName: "de Vries", preferredName: "Wim",
            addressForm: .u, gender: .man, birthYear: 1941, phoneNumber: "+31623456789", city: "Haarlem",
            livingSituation: .alleen,
            about: "Oud-onderwijzer van de Ritmeesterschool. Houdt van tuinieren, Ajax en Toon Hermans. Weduwnaar sinds 2019.",
            likes: ["tuinieren", "Ajax", "Toon Hermans", "wandelen langs het Spaarne"],
            dislikes: ["politiek"],
            topicsToRaise: ["de kleinkinderen", "zijn moestuin"],
            topicsToAvoid: ["het overlijden van zijn broer Kees"],
            routines: "Staat om 7:30 op, koffie om 10:00, wandelt na de lunch.",
            caregiverNotes: "Heeft dinsdag een afspraak bij de huisarts.",
            access: inactive ? .inactive : .active, isBeta: false, myRole: .beheerder,
            createdAt: now.addingTimeInterval(-86_400 * 40),
            // `-mockPhoneUnverified YES`: Wim's number still needs confirming (v2.2).
            phoneVerified: !defaults.bool(forKey: "mockPhoneUnverified"),
            phoneVerifiedAt: defaults.bool(forKey: "mockPhoneUnverified") ? nil : now.addingTimeInterval(-86_400 * 39),
            phoneVerifiedVia: defaults.bool(forKey: "mockPhoneUnverified") ? nil : "inbound",
            managedBy: .mantelzorger
        )
        profiles[MockIDs.riet] = ElderlyProfile(
            id: MockIDs.riet, firstName: "Hendrika", lastName: "Jansen", preferredName: "Riet",
            addressForm: .u, gender: .vrouw, birthYear: 1938, phoneNumber: "+31634567890", city: "Amersfoort",
            livingSituation: .alleen, about: "Tante van Anna. Vroeger naaister bij V&D. Houdt van bingo en puzzels.",
            likes: ["bingo", "puzzels", "Zeeland"], dislikes: [], topicsToRaise: ["haar zus in Zeeland"], topicsToAvoid: [],
            routines: nil, caregiverNotes: nil, access: .active, isBeta: true, myRole: .lezer,
            createdAt: now.addingTimeInterval(-86_400 * 20),
            phoneVerified: true, phoneVerifiedAt: now.addingTimeInterval(-86_400 * 19), phoneVerifiedVia: "code",
            managedBy: .mantelzorger
        )
        memberships[MockIDs.wim] = [MockIDs.anna: .beheerder, MockIDs.mark: .lezer]
        memberships[MockIDs.riet] = [MockIDs.anna: .lezer, MockIDs.mark: .beheerder]
        joinedAt[MockIDs.anna + MockIDs.wim] = now.addingTimeInterval(-86_400 * 40)
        joinedAt[MockIDs.mark + MockIDs.wim] = now.addingTimeInterval(-86_400 * 38)
        joinedAt[MockIDs.anna + MockIDs.riet] = now.addingTimeInterval(-86_400 * 20)
        joinedAt[MockIDs.mark + MockIDs.riet] = now.addingTimeInterval(-86_400 * 21)

        peopleByElderly[MockIDs.wim] = [
            Person(id: "P01", name: "Margriet", relation: "echtgenote", notes: "Overleden in 2019. Wim praat graag over hun mooie jaren.", birthday: "1943-03-02", isDeceased: true, createdBy: .caregiver),
            Person(id: "P02", name: "Anna", relation: "dochter", notes: "Woont in Utrecht, belt elke zondag.", birthday: "1972-05-14", isDeceased: false, createdBy: .caregiver),
            Person(id: "P03", name: "Mark", relation: "zoon", notes: "Woont in Haarlem-Noord.", birthday: "1975-09-30", isDeceased: false, createdBy: .caregiver),
            Person(id: "P04", name: "Sara", relation: "kleindochter", notes: "Dochter van Anna, komt op zaterdag.", birthday: DutchFormat.dayString(calendar.date(byAdding: .day, value: 6, to: now) ?? now).replacingOccurrences(of: String(calendar.component(.year, from: now)), with: "2010"), isDeceased: false, createdBy: .noah),
            Person(id: "P05", name: "Kees", relation: "broer", notes: "Liever niet over beginnen.", birthday: nil, isDeceased: true, createdBy: .caregiver),
        ]
        peopleByElderly[MockIDs.riet] = [Person(id: "P11", name: "Mark", relation: "neef", notes: nil, birthday: nil, isDeceased: false, createdBy: .caregiver)]

        var wimSettings = NoahSettings.defaults
        wimSettings.morningCall = .init(enabled: true, time: "09:30", weekdays: [1, 2, 3, 4, 5])
        wimSettings.recording = .levensverhaal
        settingsByElderly[MockIDs.wim] = wimSettings
        settingsByElderly[MockIDs.riet] = NoahSettings.defaults

        contacts[MockIDs.wim] = [
            EmergencyContact(id: "E01", name: "Anna de Vries", phoneNumber: "+31612340000", relation: "dochter", priority: 1, notifyBySms: true, notifyByCall: true),
            EmergencyContact(id: "E02", name: "Mark de Vries", phoneNumber: "+31687654321", relation: "zoon", priority: 2, notifyBySms: true, notifyByCall: true),
            EmergencyContact(id: "E03", name: "Ria Bakker", phoneNumber: "+31655501234", relation: "buurvrouw", priority: 3, notifyBySms: true, notifyByCall: false),
        ]
        contacts[MockIDs.riet] = [EmergencyContact(id: "E11", name: "Mark de Vries", phoneNumber: "+31687654321", relation: "neef", priority: 1, notifyBySms: true, notifyByCall: true)]

        let wimConversations = MockData.wimConversations(now: now)
        conversationsByElderly[MockIDs.wim] = wimConversations
        conversationsByElderly[MockIDs.riet] = MockData.rietConversations(now: now)
        lifeStories[MockIDs.wim] = MockData.wimLifeStory(now: now)
        lifeStories[MockIDs.riet] = MockData.rietLifeStory(now: now)
        remindersByElderly[MockIDs.wim] = MockData.wimReminders(now: now)
        remindersByElderly[MockIDs.riet] = [
            Reminder(id: "R11", title: "Bingo in het buurthuis", notes: nil, type: .afspraak, schedule: .weekly(time: "19:30", weekdays: [3]), delivery: .inGesprek, active: true, createdBy: .caregiver, nextAt: ReminderSchedule.weekly(time: "19:30", weekdays: [3]).nextOccurrence(after: now), lastCompletedAt: nil),
        ]

        let sadConversation = wimConversations.first { $0.moodScore == 2 }
        let scamConversation = wimConversations.first { $0.topics.contains("bank") }
        alertsByElderly[MockIDs.wim] = [
            NoahAlert(id: "A01", type: .lageStemming, severity: .waarschuwing, title: "Wim klonk wat somber",
                      body: "Wim sliep slecht en miste Margriet. Noah heeft voorgesteld om jou te bellen. Misschien fijn om vanavond even contact te hebben.",
                      conversationId: sadConversation?.id, status: .open, createdAt: sadConversation?.startedAt ?? now.addingTimeInterval(-7200), acknowledgedBy: nil),
            NoahAlert(id: "A02", type: .oplichting, severity: .urgent, title: "Mogelijk oplichtingstelefoontje",
                      body: "Wim werd gebeld door iemand die zei van de bank te zijn en naar zijn pincode vroeg. Hij heeft niets doorgegeven.",
                      conversationId: scamConversation?.id, status: .gezien, createdAt: scamConversation?.startedAt ?? now.addingTimeInterval(-86_400 * 3), acknowledgedBy: "Anna"),
            NoahAlert(id: "A03", type: .geenContact, severity: .info, title: "Twee dagen geen gesprek",
                      body: "Wim heeft twee dagen niet met Noah gepraat.", conversationId: nil, status: .afgehandeld,
                      createdAt: now.addingTimeInterval(-86_400 * 12), acknowledgedBy: "Mark"),
        ]
        if overAllowance {
            alertsByElderly[MockIDs.wim, default: []].append(
                NoahAlert(id: "A04", type: .verbruik, severity: .info, title: "Het redelijk gebruik van deze maand is bereikt",
                          body: "Wim heeft deze maand al veel met Noah gepraat. Noah blijft gewoon bereikbaar, met gesprekken van maximaal 10 minuten tot het einde van de maand.",
                          conversationId: nil, status: .open, createdAt: now.addingTimeInterval(-3600), acknowledgedBy: nil))
        }
        alertsByElderly[MockIDs.riet] = []

        devicesByElderly[MockIDs.wim] = [PairedDevice(id: MockIDs.wimDevice, deviceName: "iPhone van Wim", platform: "ios", pairedAt: now.addingTimeInterval(-86_400 * 39), lastSeenAt: now.addingTimeInterval(-3600 * 3))]
        devicesByElderly[MockIDs.riet] = []
        thisDeviceId[MockIDs.wim] = MockIDs.wimDevice

        // v2.4: who was told what, and a private conversation.
        transparency[MockIDs.wim] = Transparency(noahToldAt: now.addingTimeInterval(-86_400 * 38),
                                                 appShownAt: defaults.bool(forKey: "mockTransparencyUnseen") ? nil : now.addingTimeInterval(-86_400 * 38),
                                                 caregiverToldAt: defaults.bool(forKey: "mockNotTold") ? nil : now.addingTimeInterval(-86_400 * 39))
        transparency[MockIDs.riet] = Transparency(noahToldAt: now.addingTimeInterval(-86_400 * 19), appShownAt: nil, caregiverToldAt: now.addingTimeInterval(-86_400 * 20))
        sharingByElderly[MockIDs.wim] = .alles
        sharingByElderly[MockIDs.riet] = .samenvattingen
        // `-mockOutboundPaused YES`: Wim told Noah he wants to stop (scheduled calls paused).
        if defaults.bool(forKey: "mockOutboundPaused") { outboundPaused.insert(MockIDs.wim) }
        if let index = conversationsByElderly[MockIDs.wim]?.indices.dropFirst(2).first {
            var hidden = conversationsByElderly[MockIDs.wim]![index]
            hidden.hidden = true
            hidden.summary = nil
            hidden.topics = []
            hidden.moodScore = nil
            hidden.cognitiveClarity = nil
            hidden.transcript = []
            hidden.emotionalMoments = []
            hidden.moodIndicators = []
            hidden.hasConcern = false
            hidden.hasAudio = false
            hidden.lifeStoryEntryIds = []
            conversationsByElderly[MockIDs.wim]![index] = hidden
        }
        if alertsByElderly[MockIDs.wim]?.isEmpty == false {
            alertsByElderly[MockIDs.wim]![0].delivery = AlertDelivery(pushedDevices: 0, sms: 0, calls: 0)
            alertsByElderly[MockIDs.wim]![1].delivery = AlertDelivery(pushedDevices: 2, sms: 1, calls: 0)
        }
        // A beheerder invitation Anna made and a lezer invitation Wim made himself.
        invitations["Q4R-7TW"] = MockInvitation(id: "I01", code: "Q4R-7TW", elderlyId: MockIDs.wim, role: .lezer, createdAt: now.addingTimeInterval(-86_400 * 2),
                                                expiresAt: now.addingTimeInterval(86_400 * 5), createdBy: "Anna de Vries")

        // v2.4: Bep's number was put on a profile by Mark; Bep never used Noah (claim flow).
        profiles[MockIDs.bep] = ElderlyProfile(
            id: MockIDs.bep, firstName: "Elisabeth", lastName: "de Vries", preferredName: "Bep",
            addressForm: .u, gender: .vrouw, birthYear: 1946, phoneNumber: "+31611223344", city: "Haarlem",
            livingSituation: .alleen, about: nil, routines: nil, caregiverNotes: nil, access: .active, isBeta: false,
            myRole: nil, createdAt: now.addingTimeInterval(-86_400 * 3), phoneVerified: false, managedBy: .mantelzorger
        )
        memberships[MockIDs.bep] = [MockIDs.mark: .beheerder]
        settingsByElderly[MockIDs.bep] = NoahSettings.defaults
        devicesByElderly[MockIDs.bep] = []
        subscriptions[MockIDs.bep] = Subscription(status: .geen, productId: nil, renewsAt: nil, expiresAt: nil, platform: nil, paidByMe: nil, freeConversationsLeft: 1)

        subscriptions[MockIDs.wim] = inactive
            ? Subscription(status: .geen, productId: nil, renewsAt: nil, expiresAt: nil, platform: nil, paidByMe: nil, freeConversationsLeft: 0)
            : Subscription(status: .intro, productId: SubscriptionStore.productID, renewsAt: calendar.date(byAdding: .day, value: 18, to: now), expiresAt: nil, platform: "app_store", paidByMe: true, freeConversationsLeft: 0)
        subscriptions[MockIDs.riet] = Subscription(status: .beta, productId: nil, renewsAt: nil, expiresAt: nil, platform: nil, paidByMe: false)
    }

    /// v2.3: Toos signed up herself; her daughter Ellen looks along as lezer.
    private func seedSelfProfiles(now: Date) {
        let id = MockIDs.toos
        caregiverRecords[MockIDs.ellen] = Caregiver(id: MockIDs.ellen, name: "Ellen Bakker", email: "ellen@example.com", phoneNumber: "+31656781234", createdAt: now.addingTimeInterval(-86_400 * 10))
        profiles[id] = ElderlyProfile(
            id: id, firstName: "Catharina", lastName: "Bakker", preferredName: "Toos",
            addressForm: .u, gender: .vrouw, birthYear: 1944, phoneNumber: "+31645678901", city: "Leiden",
            livingSituation: .alleen, about: nil, routines: nil, caregiverNotes: nil,
            access: defaults.bool(forKey: "mockInactive") ? .inactive : .active, isBeta: false, myRole: nil,
            createdAt: now.addingTimeInterval(-86_400 * 14),
            phoneVerified: true, phoneVerifiedAt: now.addingTimeInterval(-86_400 * 14), phoneVerifiedVia: "code",
            managedBy: .zelf
        )
        memberships[id] = [MockIDs.ellen: .lezer]
        joinedAt[MockIDs.ellen + id] = now.addingTimeInterval(-86_400 * 10)
        selfRegistered.insert(id)
        thisDeviceId[id] = MockIDs.toosDevice
        transparency[id] = Transparency(noahToldAt: now.addingTimeInterval(-86_400 * 9), appShownAt: now.addingTimeInterval(-86_400 * 14), caregiverToldAt: nil)
        sharingByElderly[id] = .alles
        var settings = NoahSettings.defaults
        settings.speakingSpeed = 0.9
        settingsByElderly[id] = settings
        contacts[id] = [
            EmergencyContact(id: "E21", name: "Ellen Bakker", phoneNumber: "+31656781234", relation: "dochter", priority: 1, notifyBySms: true, notifyByCall: true),
        ]
        conversationsByElderly[id] = []
        lifeStories[id] = []
        remindersByElderly[id] = [
            Reminder(id: "R21", title: "Koffie bij de buurvrouw", notes: nil, type: .afspraak, schedule: .weekly(time: "10:30", weekdays: [4]), delivery: .inGesprek, active: true, createdBy: .noah, nextAt: ReminderSchedule.weekly(time: "10:30", weekdays: [4]).nextOccurrence(after: now), lastCompletedAt: nil),
        ]
        alertsByElderly[id] = []
        devicesByElderly[id] = [PairedDevice(id: MockIDs.toosDevice, deviceName: "iPhone van Toos", platform: "ios", pairedAt: now.addingTimeInterval(-86_400 * 14), lastSeenAt: now.addingTimeInterval(-600))]
        subscriptions[id] = defaults.bool(forKey: "mockInactive")
            ? Subscription(status: .geen, productId: nil, renewsAt: nil, expiresAt: nil, platform: nil, paidByMe: nil, freeConversationsLeft: 0)
            : Subscription(status: .intro, productId: Plan.productIDs[1], renewsAt: DutchFormat.calendar.date(byAdding: .day, value: 12, to: now), expiresAt: nil, platform: "app_store", paidByMe: true, freeConversationsLeft: 0)
    }

    // MARK: Self sign-ups (kept across launches)

    private static let selfSignUpsKey = "mock.selfSignUps"

    private struct StoredSelfProfile: Codable {
        var id: String
        var phoneNumber: String
        var preferredName: String
        var addressForm: String
    }

    private func restoreSelfSignUps() {
        guard let data = defaults.data(forKey: Self.selfSignUpsKey),
              let stored = try? JSONDecoder().decode([StoredSelfProfile].self, from: data) else { return }
        for item in stored where profiles[item.id] == nil {
            createSelfProfile(id: item.id, phoneNumber: item.phoneNumber, preferredName: item.preferredName,
                              addressForm: AddressForm(rawValue: item.addressForm) ?? .u, persist: false)
        }
    }

    private func persistSelfSignUps() {
        let stored = profiles.values.filter { $0.managedBy == .zelf && $0.id != MockIDs.toos }.map {
            StoredSelfProfile(id: $0.id, phoneNumber: $0.phoneNumber ?? "", preferredName: $0.preferredName, addressForm: $0.addressForm.rawValue)
        }
        defaults.set(try? JSONEncoder().encode(stored), forKey: Self.selfSignUpsKey)
    }

    @discardableResult
    private func createSelfProfile(id: String, phoneNumber: String, preferredName: String, addressForm: AddressForm, persist: Bool = true) -> ElderlyProfile {
        let profile = ElderlyProfile(
            id: id, firstName: preferredName, lastName: nil, preferredName: preferredName, addressForm: addressForm,
            gender: nil, birthYear: nil, phoneNumber: phoneNumber, city: nil, livingSituation: nil, about: nil,
            routines: nil, caregiverNotes: nil, access: .active, isBeta: false, myRole: nil, createdAt: Date(),
            // The SMS code proves the number (v2.3).
            phoneVerified: true, phoneVerifiedAt: Date(), phoneVerifiedVia: "code", managedBy: .zelf
        )
        profiles[id] = profile
        memberships[id] = [:]
        selfRegistered.insert(id)
        transparency[id] = Transparency(noahToldAt: nil, appShownAt: nil, caregiverToldAt: nil)
        sharingByElderly[id] = .alles
        settingsByElderly[id] = NoahSettings.defaults
        contacts[id] = []
        conversationsByElderly[id] = []
        lifeStories[id] = []
        remindersByElderly[id] = []
        alertsByElderly[id] = []
        // Free trial: the first conversation is free.
        subscriptions[id] = Subscription(status: .geen, productId: nil, renewsAt: nil, expiresAt: nil, platform: nil, paidByMe: nil, freeConversationsLeft: 1)
        if persist { persistSelfSignUps() }
        return profile
    }

    // MARK: Helpers

    private func simulate() async throws {
        if latency > 0 { try await Task.sleep(nanoseconds: UInt64(latency * 1_000_000_000)) }
        if offline { throw APIError.offline }
    }

    private func sync<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }

    private func fail(_ status: Int, _ code: String, _ message: String) -> APIError {
        .server(status: status, code: code, message: message)
    }

    /// v2.4 endpoints answer 404 with `-mockV23Backend YES`, like a backend not yet updated.
    private func requireV24() throws {
        if v23Backend { throw fail(404, "niet_gevonden", "Deze route bestaat niet.") }
    }

    /// v2.4: the profile as caregivers see it, with transparency and sharing filled in.
    private func decorated(_ profile: ElderlyProfile) -> ElderlyProfile {
        guard !v23Backend else { return profile }
        var copy = profile
        copy.transparency = transparency[profile.id] ?? Transparency()
        copy.sharing = sharingByElderly[profile.id] ?? .alles
        copy.outboundPaused = outboundPaused.contains(profile.id)
        return copy
    }

    /// v2.4: what caregivers may see of a conversation, given the older person's choice.
    private func shared(_ c: ConversationDetail, elderlyId: String) -> ConversationDetail {
        var copy = c
        switch sharingByElderly[elderlyId] ?? .alles {
        case .samenvattingen:
            copy.transcript = []
            copy.emotionalMoments = []
            copy.cognitiveClarity = nil
        case .alleenMeldingen:
            copy = ConversationDetail(id: c.id, startedAt: c.startedAt, durationSeconds: c.durationSeconds, channel: c.channel,
                                      summary: nil, moodScore: nil, mode: c.mode, hasAudio: false, hidden: true)
        case .alles, .unknown:
            break
        }
        return copy
    }

    /// This phone is restricted (v2.4): a new phone on a profile in use, waiting for approval.
    private func requireUnrestricted() throws {
        if restrictedPhone, !v23Backend {
            throw fail(403, "apparaat_wacht_op_bevestiging", "Deze telefoon is net aangemeld. Uw andere telefoon of uw familie kan hem goedkeuren.")
        }
    }

    private func makeInvitationCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let raw = String((0..<6).map { _ in alphabet.randomElement()! })
        return String(raw.prefix(3)) + "-" + String(raw.suffix(3))
    }

    private func role(for elderlyId: String) throws -> Role {
        guard profiles[elderlyId] != nil else { throw fail(404, "niet_gevonden", "Dit profiel bestaat niet (meer).") }
        guard let role = memberships[elderlyId]?[currentCaregiverId] else {
            throw fail(404, "niet_gevonden", "Dit profiel bestaat niet (meer).")
        }
        return role
    }

    private func requireBeheerder(_ elderlyId: String) throws {
        if try role(for: elderlyId) != .beheerder {
            throw fail(403, "alleen_lezen", "Je kijkt mee als lezer. Alleen een beheerder kan dit doen.")
        }
    }

    private func elderlyId(ofConversation id: String) -> String? {
        conversationsByElderly.first { $0.value.contains { $0.id == id } }?.key
    }

    private func elderlyId(ofEntry id: String) -> String? {
        lifeStories.first { $0.value.contains { $0.id == id } }?.key
    }

    private func elderlyId(ofReminder id: String) -> String? {
        remindersByElderly.first { $0.value.contains { $0.id == id } }?.key
    }

    private func elderlyId(ofAlert id: String) -> String? {
        alertsByElderly.first { $0.value.contains { $0.id == id } }?.key
    }

    private func paginate<T>(_ items: [T], cursor: String?, limit: Int) -> Page<T> {
        let start = cursor.flatMap(Int.init) ?? 0
        let end = min(items.count, start + max(1, limit))
        let slice = start < items.count ? Array(items[start..<end]) : []
        return Page(items: slice, nextCursor: end < items.count ? String(end) : nil)
    }

    private func tokens(for caregiverId: String, isNew: Bool) -> AuthResponse {
        currentCaregiverId = caregiverId
        return AuthResponse(
            accessToken: "mock-access-\(UUID().uuidString)",
            accessTokenExpiresAt: Date().addingTimeInterval(3600),
            refreshToken: "hnr_mock_\(UUID().uuidString)",
            caregiver: caregiverRecords[caregiverId],
            isNewAccount: isNew
        )
    }

    private func summary(_ c: ConversationDetail) -> ConversationSummary {
        ConversationSummary(id: c.id, startedAt: c.startedAt, durationSeconds: c.durationSeconds, channel: c.channel,
                            summary: c.summary, moodScore: c.moodScore, topics: c.topics, hasConcern: c.hasConcern,
                            mode: c.mode, hasAudio: c.hasAudio, hidden: v23Backend ? false : c.hidden)
    }

    /// Fair use this month (v2.1): minutes of this calendar month (Europe/Amsterdam).
    private func usage(_ elderlyId: String, now: Date = Date()) -> Subscription.Usage {
        let calendar = DutchFormat.calendar
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let resetsAt = calendar.date(byAdding: .month, value: 1, to: monthStart)
        let seconds = (conversationsByElderly[elderlyId] ?? []).filter { $0.startedAt >= monthStart }.compactMap(\.durationSeconds).reduce(0, +)
        let allowance = Double(Plan.fairUseMonthlyMinutes)
        // Kept under the allowance unless `-mockOverAllowance YES`, so screenshots stay stable.
        let minutes = elderlyId == MockIDs.wim && overAllowance ? allowance + 12 : min((Double(seconds) / 60).rounded(), allowance * 0.9)
        return Subscription.Usage(minutesThisMonth: minutes, allowanceMinutes: allowance, resetsAt: resetsAt, overAllowance: minutes >= allowance)
    }

    private func audio(for conversation: ConversationDetail?) throws -> ConversationAudio {
        guard let conversation, conversation.hasAudio else {
            throw fail(404, "geen_opname", "Er is geen opname van dit gesprek.")
        }
        return ConversationAudio(url: try MockRecording.fileURL(), durationSeconds: MockRecording.durationSeconds,
                                 expiresAt: Date().addingTimeInterval(15 * 60))
    }

    private func refreshedReminders(_ elderlyId: String) -> [Reminder] {
        let now = Date()
        return (remindersByElderly[elderlyId] ?? []).map { reminder in
            var copy = reminder
            copy.nextAt = reminder.active ? reminder.schedule.nextOccurrence(after: now) : nil
            return copy
        }
    }

    private func moodDays(_ elderlyId: String, days: Int, now: Date = Date()) -> [MoodPoint] {
        let calendar = DutchFormat.calendar
        let conversations = conversationsByElderly[elderlyId] ?? []
        return (0..<days).reversed().compactMap { offset -> MoodPoint? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let onDay = conversations.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
            if offset < 30 || !onDay.isEmpty {
                let moods = onDay.compactMap(\.moodScore)
                let clarity = onDay.compactMap(\.cognitiveClarity)
                return MoodPoint(date: DutchFormat.dayString(day),
                                 mood: moods.isEmpty ? nil : moods.reduce(0, +) / Double(moods.count),
                                 conversations: onDay.count,
                                 cognitiveClarity: clarity.isEmpty ? nil : clarity.reduce(0, +) / Double(clarity.count))
            }
            // Older history: synthetic but stable.
            let r = MockData.noise(offset * 31)
            if r < 0.2 { return MoodPoint(date: DutchFormat.dayString(day), mood: nil, conversations: 0, cognitiveClarity: nil) }
            let mood = min(5, max(1, 3.4 + sin(Double(offset) / 6) * 0.8 + (r - 0.5)))
            return MoodPoint(date: DutchFormat.dayString(day), mood: (mood * 10).rounded() / 10, conversations: r > 0.8 ? 2 : 1, cognitiveClarity: 4.5)
        }
    }

    // MARK: Auth

    func signInWithApple(_ request: AppleSignInRequest) async throws -> AuthResponse {
        try await simulate()
        return sync { tokens(for: MockIDs.anna, isNew: false) }
    }

    func startPhoneSignIn(phoneNumber: String) async throws {
        try await simulate()
        guard PhoneNumberFormat.e164(phoneNumber) != nil else {
            throw fail(400, "invalid_phone_number", "Dit telefoonnummer klopt niet.")
        }
    }

    func verifyPhoneSignIn(phoneNumber: String, code: String) async throws -> AuthResponse {
        try await simulate()
        if code == "000000" || code.count != 6 { throw fail(401, "ongeldige_code", "Deze code klopt niet. Controleer de sms en probeer het opnieuw.") }
        return sync {
            caregiverRecords[MockIDs.newCaregiver]?.phoneNumber = phoneNumber
            return tokens(for: MockIDs.newCaregiver, isNew: true)
        }
    }

    func logout(refreshToken: String) async throws {
        try await simulate()
    }

    func createPairingCode(elderlyId: String) async throws -> PairingCode {
        try await simulate()
        return try sync {
            try requireBeheerder(elderlyId)
            let code = String(format: "%06d", Int.random(in: 100_000...999_999))
            pairingCodes[code] = elderlyId
            return PairingCode(code: code, expiresAt: Date().addingTimeInterval(15 * 60))
        }
    }

    func pairDevice(code: String, deviceName: String) async throws -> PairDeviceResponse {
        try await simulate()
        return try sync {
            guard code.count == 6, code != "000000" else {
                throw fail(400, "koppelcode_ongeldig", "Deze code klopt niet of is verlopen. Vraag uw mantelzorger om een nieuwe code.")
            }
            let elderlyId = pairingCodes[code] ?? MockIDs.wim
            pairingCodes[code] = nil
            let device = PairedDevice(id: UUID().uuidString, deviceName: deviceName, platform: "ios", pairedAt: Date(), lastSeenAt: Date())
            devicesByElderly[elderlyId, default: []].append(device)
            thisDeviceId[elderlyId] = device.id
            // v2.4: the older person sees "Wie kijkt er mee" once on the new phone.
            transparency[elderlyId, default: Transparency()].appShownAt = nil
            let profile = profiles[elderlyId]
            return PairDeviceResponse(
                deviceToken: "hnd_mock_\(elderlyId)",
                device: .init(id: device.id),
                elderly: .init(id: elderlyId, preferredName: profile?.preferredName ?? "Wim", noahName: settingsByElderly[elderlyId]?.noahName ?? "Noah")
            )
        }
    }

    // MARK: Me

    func me() async throws -> MeResponse {
        try await simulate()
        return sync {
            let me = currentCaregiverId
            let elderly = memberships.compactMap { elderlyId, members -> ElderlySummary? in
                guard let role = members[me], let profile = profiles[elderlyId] else { return nil }
                return ElderlySummary(
                    id: elderlyId, preferredName: profile.preferredName, role: role, access: profile.access,
                    lastConversationAt: conversationsByElderly[elderlyId]?.first?.startedAt,
                    openAlertCount: alertsByElderly[elderlyId]?.filter { $0.status == .open }.count ?? 0,
                    managedBy: profile.managedBy
                )
            }.sorted { $0.preferredName < $1.preferredName }
            return MeResponse(caregiver: caregiverRecords[me] ?? Caregiver(id: me), elderly: elderly)
        }
    }

    func updateMe(name: String?, phoneNumber: String?) async throws -> Caregiver {
        try await simulate()
        return sync {
            var caregiver = caregiverRecords[currentCaregiverId] ?? Caregiver(id: currentCaregiverId)
            if let name { caregiver.name = name }
            if let phoneNumber { caregiver.phoneNumber = phoneNumber }
            caregiverRecords[currentCaregiverId] = caregiver
            return caregiver
        }
    }

    func registerPushToken(_ token: String, environment: String) async throws {
        try await simulate()
    }

    func deletePushToken(_ token: String) async throws {
        try await simulate()
    }

    func exportMe() async throws -> Data {
        try await simulate()
        return try sync {
            let me = currentCaregiverId
            let owned = memberships.filter { $0.value[me] == .beheerder }.keys
            let export: [String: AnyEncodable] = [
                "caregiver": AnyEncodable(caregiverRecords[me] ?? Caregiver(id: me)),
                "elderly": AnyEncodable(owned.compactMap { profiles[$0] }),
                "conversations": AnyEncodable(owned.flatMap { conversationsByElderly[$0] ?? [] }),
                "lifeStory": AnyEncodable(owned.flatMap { lifeStories[$0] ?? [] }),
                "reminders": AnyEncodable(owned.flatMap { remindersByElderly[$0] ?? [] }),
                "recordings": AnyEncodable(owned.flatMap { (conversationsByElderly[$0] ?? []).filter(\.hasAudio).map { "opnames/\($0.id).m4a" } }),
                "exportedAt": AnyEncodable(NoahJSON.formatDate(Date())),
            ]
            return try NoahJSON.makeEncoder(pretty: true).encode(export)
        }
    }

    func deleteMe(subscriptionAcknowledged: Bool) async throws {
        try await simulate()
        try sync {
            let me = currentCaregiverId
            if !subscriptionAcknowledged, !v23Backend {
                let wouldDelete = memberships.filter { $0.value[me] == .beheerder && $0.value.filter({ $0.value == .beheerder }).count == 1 && !selfRegistered.contains($0.key) }.keys
                if wouldDelete.contains(where: { subscriptions[$0]?.status == .actief || subscriptions[$0]?.status == .intro }) {
                    throw fail(409, "abonnement_actief", "Er loopt nog een abonnement. Zeg het eerst op in de App Store.")
                }
            }
            for (elderlyId, members) in memberships where members[me] != nil {
                memberships[elderlyId]?[me] = nil
                if members.filter({ $0.value == .beheerder && $0.key != me }).isEmpty, members[me] == .beheerder, !selfRegistered.contains(elderlyId) {
                    profiles[elderlyId] = nil
                    memberships[elderlyId] = nil
                }
            }
        }
    }

    // MARK: Elderly

    func createElderly(_ input: ElderlyProfileInput) async throws -> ElderlyProfile {
        try await simulate()
        return try sync {
            if profiles.values.contains(where: { $0.phoneNumber == input.phoneNumber }) {
                throw fail(409, "phone_number_taken", "Dit telefoonnummer hoort al bij een ander profiel.")
            }
            let id = UUID().uuidString
            let profile = ElderlyProfile(
                id: id, firstName: input.firstName, lastName: input.lastName, preferredName: input.preferredName,
                addressForm: input.addressForm, gender: input.gender, birthYear: input.birthYear, phoneNumber: input.phoneNumber,
                city: input.city, livingSituation: input.livingSituation, about: input.about, likes: input.likes,
                dislikes: input.dislikes, topicsToRaise: input.topicsToRaise, topicsToAvoid: input.topicsToAvoid,
                routines: input.routines, caregiverNotes: input.caregiverNotes, access: .active, isBeta: false,
                myRole: .beheerder, createdAt: Date(), phoneVerified: false, managedBy: .mantelzorger
            )
            profiles[id] = profile
            transparency[id] = Transparency()
            sharingByElderly[id] = .alles
            memberships[id] = [currentCaregiverId: .beheerder]
            joinedAt[currentCaregiverId + id] = Date()
            settingsByElderly[id] = NoahSettings.defaults
            // Free trial (backend changelog): active while free conversations are left.
            subscriptions[id] = Subscription(status: .geen, productId: nil, renewsAt: nil, expiresAt: nil, platform: nil, paidByMe: nil, freeConversationsLeft: 1)
            return decorated(profile)
        }
    }

    func startPhoneVerification(elderlyId: String, channel: PhoneVerificationChannel) async throws -> PhoneVerificationStart {
        try await simulate()
        return try sync {
            try requireBeheerder(elderlyId)
            if profiles[elderlyId]?.phoneVerified == true { return PhoneVerificationStart(status: "al_bevestigd", channel: channel.rawValue) }
            return PhoneVerificationStart(status: "verstuurd", channel: channel.rawValue)
        }
    }

    /// Any 6 digits confirm the number, except `000000`.
    func verifyPhone(elderlyId: String, code: String) async throws -> ElderlyProfile {
        try await simulate()
        return try sync {
            try requireBeheerder(elderlyId)
            guard code.count == 6, code != "000000" else {
                throw fail(400, "ongeldige_code", "Deze code klopt niet of is verlopen.")
            }
            var profile = profiles[elderlyId]!
            profile.phoneVerified = true
            profile.phoneVerifiedAt = Date()
            profile.phoneVerifiedVia = "code"
            profiles[elderlyId] = profile
            profile.myRole = .beheerder
            return decorated(profile)
        }
    }

    func elderly(id: String) async throws -> ElderlyProfile {
        try await simulate()
        return try sync {
            let role = try role(for: id)
            var profile = decorated(profiles[id]!)
            profile.myRole = role
            return profile
        }
    }

    func updateElderly(id: String, _ input: ElderlyProfileInput) async throws -> ElderlyProfile {
        try await simulate()
        return try sync {
            try requireBeheerder(id)
            if !input.phoneNumber.isEmpty, profiles.values.contains(where: { $0.id != id && $0.phoneNumber == input.phoneNumber }) {
                throw fail(409, "phone_number_taken", "Dit telefoonnummer hoort al bij een ander profiel.")
            }
            var profile = profiles[id]!
            profile.firstName = input.firstName
            profile.lastName = input.lastName.nilIfBlank
            profile.preferredName = input.preferredName
            profile.addressForm = input.addressForm
            profile.gender = input.gender
            profile.birthYear = input.birthYear
            // Like the backend: a new number must be confirmed again (no number sent: unchanged).
            if !input.phoneNumber.isEmpty, profile.phoneNumber != input.phoneNumber {
                profile.phoneVerified = false
                profile.phoneVerifiedAt = nil
                profile.phoneVerifiedVia = nil
            }
            if !input.phoneNumber.isEmpty { profile.phoneNumber = input.phoneNumber }
            profile.city = input.city.nilIfBlank
            profile.livingSituation = input.livingSituation
            profile.about = input.about.nilIfBlank
            profile.likes = input.likes
            profile.dislikes = input.dislikes
            profile.topicsToRaise = input.topicsToRaise
            profile.topicsToAvoid = input.topicsToAvoid
            profile.routines = input.routines.nilIfBlank
            profile.caregiverNotes = input.caregiverNotes.nilIfBlank
            profiles[id] = profile
            return decorated(profile)
        }
    }

    func deleteElderly(id: String, subscriptionAcknowledged: Bool) async throws {
        try await simulate()
        try sync {
            try requireBeheerder(id)
            if !v23Backend {
                if selfRegistered.contains(id) {
                    throw fail(403, "profiel_van_oudere", "Dit profiel is van de oudere zelf.")
                }
                if !subscriptionAcknowledged, subscriptions[id]?.status == .actief || subscriptions[id]?.status == .intro {
                    throw fail(409, "abonnement_actief", "Er loopt nog een abonnement. Zeg het eerst op in de App Store.")
                }
            }
            profiles[id] = nil
            memberships[id] = nil
        }
    }

    func markToldElderly(elderlyId: String) async throws {
        try await simulate()
        try sync {
            try requireV24()
            try requireBeheerder(elderlyId)
            transparency[elderlyId, default: Transparency()].caregiverToldAt = Date()
        }
    }

    func setOutboundPaused(elderlyId: String, paused: Bool) async throws -> ElderlyProfile {
        try await simulate()
        return try sync {
            try requireV24()
            try requireBeheerder(elderlyId)
            if paused { outboundPaused.insert(elderlyId) } else { outboundPaused.remove(elderlyId) }
            var profile = decorated(profiles[elderlyId]!)
            profile.myRole = .beheerder
            return profile
        }
    }

    func exportElderly(id: String) async throws -> Data {
        try await simulate()
        return try sync {
            try requireBeheerder(id)
            let export: [String: AnyEncodable] = [
                "elderly": AnyEncodable(profiles[id]),
                "people": AnyEncodable(peopleByElderly[id] ?? []),
                "settings": AnyEncodable(settingsByElderly[id]),
                "emergencyContacts": AnyEncodable(contacts[id] ?? []),
                "conversations": AnyEncodable(conversationsByElderly[id] ?? []),
                "lifeStory": AnyEncodable(lifeStories[id] ?? []),
                "reminders": AnyEncodable(remindersByElderly[id] ?? []),
                "recordings": AnyEncodable((conversationsByElderly[id] ?? []).filter(\.hasAudio).map { "opnames/\($0.id).m4a" }),
            ]
            return try NoahJSON.makeEncoder(pretty: true).encode(export)
        }
    }

    // MARK: People

    func people(elderlyId: String) async throws -> [Person] {
        try await simulate()
        return try sync {
            try requireBeheerder(elderlyId)
            return peopleByElderly[elderlyId] ?? []
        }
    }

    func createPerson(elderlyId: String, _ input: PersonInput) async throws -> Person {
        try await simulate()
        return try sync {
            try requireBeheerder(elderlyId)
            let person = Person(id: UUID().uuidString, name: input.name, relation: input.relation.nilIfBlank, notes: input.notes.nilIfBlank,
                                birthday: input.birthday, isDeceased: input.isDeceased, createdBy: .caregiver)
            peopleByElderly[elderlyId, default: []].append(person)
            return person
        }
    }

    func updatePerson(elderlyId: String, personId: String, _ input: PersonInput) async throws -> Person {
        try await simulate()
        return try sync {
            try requireBeheerder(elderlyId)
            guard let index = peopleByElderly[elderlyId]?.firstIndex(where: { $0.id == personId }) else { throw fail(404, "niet_gevonden", "Deze persoon bestaat niet (meer).") }
            var person = peopleByElderly[elderlyId]![index]
            person.name = input.name
            person.relation = input.relation.nilIfBlank
            person.notes = input.notes.nilIfBlank
            person.birthday = input.birthday
            person.isDeceased = input.isDeceased
            peopleByElderly[elderlyId]![index] = person
            return person
        }
    }

    func deletePerson(elderlyId: String, personId: String) async throws {
        try await simulate()
        try sync {
            try requireBeheerder(elderlyId)
            peopleByElderly[elderlyId]?.removeAll { $0.id == personId }
        }
    }

    // MARK: Settings

    func settings(elderlyId: String) async throws -> NoahSettings {
        try await simulate()
        return try sync {
            try requireBeheerder(elderlyId)
            return settingsByElderly[elderlyId] ?? .defaults
        }
    }

    func updateSettings(elderlyId: String, _ patch: NoahSettingsPatch) async throws -> NoahSettings {
        try await simulate()
        return try sync {
            try requireBeheerder(elderlyId)
            // Like the backend: recording ≠ uit needs EU storage (`-mockRecordingUnavailable YES`).
            if let recording = patch.recording, recording != .uit, defaults.bool(forKey: "mockRecordingUnavailable") {
                throw fail(503, "niet_geconfigureerd", "Opnemen is op dit moment niet beschikbaar.")
            }
            if let speed = patch.speakingSpeed, !NoahSettings.speedRange.contains(speed) {
                throw fail(400, "ongeldige_invoer", "Spreektempo moet tussen 0.8 en 1.2 liggen.")
            }
            var clamped = patch.applied(to: settingsByElderly[elderlyId] ?? .defaults)
            clamped.speakingSpeed = min(max(clamped.speakingSpeed, NoahSettings.speedRange.lowerBound), NoahSettings.speedRange.upperBound)
            clamped.maxConversationMinutes = min(max(clamped.maxConversationMinutes, 5), 30)
            clamped.noContactAlertDays = min(max(clamped.noContactAlertDays, 1), 7)
            settingsByElderly[elderlyId] = clamped
            return clamped
        }
    }

    // MARK: Emergency contacts

    func emergencyContacts(elderlyId: String) async throws -> [EmergencyContact] {
        try await simulate()
        return try sync {
            try requireBeheerder(elderlyId)
            return (contacts[elderlyId] ?? []).sorted { $0.priority < $1.priority }
        }
    }

    func createEmergencyContact(elderlyId: String, _ input: EmergencyContactInput) async throws -> EmergencyContact {
        try await simulate()
        return try sync {
            try requireBeheerder(elderlyId)
            if !v23Backend, (contacts[elderlyId]?.count ?? 0) >= EmergencyContactLimit.max {
                throw fail(409, "te_veel_noodcontacten", "Er kunnen maximaal 5 noodcontacten zijn.")
            }
            let contact = EmergencyContact(id: UUID().uuidString, name: input.name, phoneNumber: input.phoneNumber, relation: input.relation,
                                           priority: (contacts[elderlyId]?.count ?? 0) + 1, notifyBySms: input.notifyBySms, notifyByCall: input.notifyByCall)
            contacts[elderlyId, default: []].append(contact)
            return contact
        }
    }

    func updateEmergencyContact(elderlyId: String, contactId: String, _ input: EmergencyContactInput) async throws -> EmergencyContact {
        try await simulate()
        return try sync {
            try requireBeheerder(elderlyId)
            guard let index = contacts[elderlyId]?.firstIndex(where: { $0.id == contactId }) else { throw fail(404, "niet_gevonden", "Dit contact bestaat niet (meer).") }
            var contact = contacts[elderlyId]![index]
            contact.name = input.name
            contact.phoneNumber = input.phoneNumber
            contact.relation = input.relation
            contact.notifyBySms = input.notifyBySms
            contact.notifyByCall = input.notifyByCall
            contacts[elderlyId]![index] = contact
            return contact
        }
    }

    func deleteEmergencyContact(elderlyId: String, contactId: String) async throws {
        try await simulate()
        try sync {
            try requireBeheerder(elderlyId)
            contacts[elderlyId]?.removeAll { $0.id == contactId }
            contacts[elderlyId] = contacts[elderlyId]?.enumerated().map { index, contact in
                var copy = contact
                copy.priority = index + 1
                return copy
            }
        }
    }

    func reorderEmergencyContacts(elderlyId: String, ids: [String]) async throws {
        try await simulate()
        try sync {
            try requireBeheerder(elderlyId)
            let current = contacts[elderlyId] ?? []
            contacts[elderlyId] = ids.enumerated().compactMap { index, id in
                guard var contact = current.first(where: { $0.id == id }) else { return nil }
                contact.priority = index + 1
                return contact
            }
        }
    }

    // MARK: Caregivers & invitations

    func caregivers(elderlyId: String) async throws -> [CaregiverMembership] {
        try await simulate()
        return try sync {
            try requireBeheerder(elderlyId)
            return (memberships[elderlyId] ?? [:]).map { caregiverId, role in
                CaregiverMembership(caregiverId: caregiverId, name: caregiverRecords[caregiverId]?.name ?? "Nieuwe mantelzorger", role: role,
                                    joinedAt: joinedAt[caregiverId + elderlyId], isMe: caregiverId == currentCaregiverId)
            }.sorted { ($0.isMe ? 0 : 1, $0.name ?? "") < ($1.isMe ? 0 : 1, $1.name ?? "") }
        }
    }

    func createInvitation(elderlyId: String, role: Role) async throws -> Invitation {
        try await simulate()
        return try sync {
            try requireBeheerder(elderlyId)
            let code = makeInvitationCode()
            invitations[code] = MockInvitation(id: UUID().uuidString, code: code, elderlyId: elderlyId, role: role, createdAt: Date(),
                                               expiresAt: Date().addingTimeInterval(7 * 86_400), createdBy: caregiverRecords[currentCaregiverId]?.name ?? "Mantelzorger")
            let name = profiles[elderlyId]?.preferredName ?? ""
            let url = "https://hellonoah.ai/uitnodiging/\(code)"
            return Invitation(code: code, url: url, expiresAt: Date().addingTimeInterval(7 * 86_400),
                              shareText: "Ik nodig je uit om mee te kijken bij Noah voor \(name): \(url) (code \(code))")
        }
    }

    func acceptInvitation(code: String) async throws -> AcceptInvitationResponse {
        try await simulate()
        return try sync {
            let normalized = code.uppercased().replacingOccurrences(of: " ", with: "")
            if let invitation = invitations[normalized] {
                invitations[normalized] = nil
                let name = profiles[invitation.elderlyId]?.preferredName ?? ""
                // v2.4: a beheerder invitation the older person made waits for their approval.
                if invitation.fromDevice, invitation.role == .beheerder, !v23Backend {
                    caregiverRequests.append(MockRequest(
                        request: CaregiverRequest(id: UUID().uuidString, name: caregiverRecords[currentCaregiverId]?.name ?? "Familielid", role: .beheerder, requestedAt: Date()),
                        caregiverId: currentCaregiverId, elderlyId: invitation.elderlyId))
                    return AcceptInvitationResponse(elderly: .init(id: invitation.elderlyId, preferredName: name), role: invitation.role, status: "wacht_op_bevestiging")
                }
                addMember(currentCaregiverId, to: invitation.elderlyId, role: invitation.role)
                return AcceptInvitationResponse(elderly: .init(id: invitation.elderlyId, preferredName: name), role: invitation.role, status: v23Backend ? nil : "actief")
            }
            // Demo: the code K7P-2QX from the contract joins Riet as lezer.
            if normalized == "K7P-2QX" {
                memberships[MockIDs.riet, default: [:]][currentCaregiverId] = .lezer
                joinedAt[currentCaregiverId + MockIDs.riet] = Date()
                return AcceptInvitationResponse(elderly: .init(id: MockIDs.riet, preferredName: "Riet"), role: .lezer)
            }
            throw fail(404, "uitnodiging_ongeldig", "Deze uitnodiging bestaat niet of is verlopen. Vraag om een nieuwe uitnodiging.")
        }
    }

    private func addMember(_ caregiverId: String, to elderlyId: String, role: Role) {
        memberships[elderlyId, default: [:]][caregiverId] = role
        joinedAt[caregiverId + elderlyId] = Date()
        // v2.3: a beheerder takes over a self-managed profile.
        if role == .beheerder, profiles[elderlyId]?.managedBy == .zelf {
            profiles[elderlyId]?.managedBy = .mantelzorger
            persistSelfSignUps()
        }
    }

    func pendingInvitations(elderlyId: String) async throws -> [PendingInvitation] {
        try await simulate()
        return try sync {
            try requireV24()
            try requireBeheerder(elderlyId)
            return invitations.values.filter { $0.elderlyId == elderlyId && $0.expiresAt > Date() }
                .sorted { $0.createdAt > $1.createdAt }
                .map { PendingInvitation(id: $0.id, code: $0.code, role: $0.role, createdAt: $0.createdAt, expiresAt: $0.expiresAt, createdBy: $0.createdBy) }
        }
    }

    func revokeInvitation(elderlyId: String, invitationId: String) async throws {
        try await simulate()
        try sync {
            try requireV24()
            try requireBeheerder(elderlyId)
            invitations = invitations.filter { !($0.value.elderlyId == elderlyId && $0.value.id == invitationId) }
        }
    }

    func updateCaregiverRole(elderlyId: String, caregiverId: String, role newRole: Role) async throws {
        try await simulate()
        try sync {
            try requireBeheerder(elderlyId)
            let members = memberships[elderlyId] ?? [:]
            if newRole != .beheerder, members[caregiverId] == .beheerder, members.values.filter({ $0 == .beheerder }).count == 1 {
                throw fail(409, "last_beheerder", "Er moet altijd minstens één beheerder zijn.")
            }
            memberships[elderlyId]?[caregiverId] = newRole
        }
    }

    func removeCaregiver(elderlyId: String, caregiverId: String) async throws {
        try await simulate()
        try sync {
            if caregiverId != currentCaregiverId { try requireBeheerder(elderlyId) }
            let members = memberships[elderlyId] ?? [:]
            if members[caregiverId] == .beheerder, members.values.filter({ $0 == .beheerder }).count == 1 {
                throw fail(409, "last_beheerder", "Er moet altijd minstens één beheerder zijn.")
            }
            memberships[elderlyId]?[caregiverId] = nil
        }
    }

    // MARK: Devices

    func devices(elderlyId: String) async throws -> [PairedDevice] {
        try await simulate()
        return try sync {
            try requireBeheerder(elderlyId)
            return devicesByElderly[elderlyId] ?? []
        }
    }

    func unpairDevice(elderlyId: String, deviceId: String) async throws {
        try await simulate()
        try sync {
            try requireBeheerder(elderlyId)
            devicesByElderly[elderlyId]?.removeAll { $0.id == deviceId }
        }
    }

    func approveDevice(elderlyId: String, deviceId: String) async throws {
        try await simulate()
        try sync {
            try requireV24()
            try requireBeheerder(elderlyId)
            guard let index = devicesByElderly[elderlyId]?.firstIndex(where: { $0.id == deviceId }) else {
                throw fail(404, "niet_gevonden", "Deze telefoon bestaat niet (meer).")
            }
            devicesByElderly[elderlyId]![index].restricted = false
        }
    }

    // MARK: Dashboard, conversations, mood

    func dashboard(elderlyId: String) async throws -> Dashboard {
        try await simulate()
        return try sync {
            _ = try role(for: elderlyId)
            let profile = profiles[elderlyId]!
            let now = Date()
            let conversations = conversationsByElderly[elderlyId] ?? []
            let weekAgo = now.addingTimeInterval(-7 * 86_400)
            let week = conversations.filter { $0.startedAt > weekAgo }
            let moods = week.compactMap(\.moodScore)
            let stories = lifeStories[elderlyId] ?? []
            return Dashboard(
                elderly: .init(id: elderlyId, preferredName: profile.preferredName, access: profile.access),
                lastConversationAt: conversations.first?.startedAt,
                week: .init(conversations: week.count, minutes: week.compactMap(\.durationSeconds).reduce(0, +) / 60,
                            averageMood: moods.isEmpty ? nil : (moods.reduce(0, +) / Double(moods.count) * 10).rounded() / 10),
                moodTrend: moodDays(elderlyId, days: 7),
                latestConversation: conversations.first.map { summary(shared($0, elderlyId: elderlyId)) },
                openAlerts: (alertsByElderly[elderlyId] ?? []).filter { $0.status == .open },
                upcomingReminders: Array(refreshedReminders(elderlyId).filter { $0.active && $0.nextAt != nil }.sorted { $0.nextAt! < $1.nextAt! }.prefix(5)),
                lifeStory: .init(entries: stories.count, latest: stories.max { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) })
            )
        }
    }

    func conversations(elderlyId: String, cursor: String?, limit: Int) async throws -> Page<ConversationSummary> {
        try await simulate()
        return try sync {
            _ = try role(for: elderlyId)
            return paginate((conversationsByElderly[elderlyId] ?? []).map { summary(shared($0, elderlyId: elderlyId)) }, cursor: cursor, limit: limit)
        }
    }

    func conversation(id: String) async throws -> ConversationDetail {
        try await simulate()
        return try sync {
            guard let elderlyId = elderlyId(ofConversation: id) else { throw fail(404, "niet_gevonden", "Dit gesprek bestaat niet (meer).") }
            _ = try role(for: elderlyId)
            return shared(conversationsByElderly[elderlyId]!.first { $0.id == id }!, elderlyId: elderlyId)
        }
    }

    func conversationAudio(conversationId: String) async throws -> ConversationAudio {
        try await simulate()
        return try sync {
            guard let elderlyId = elderlyId(ofConversation: conversationId) else { throw fail(404, "niet_gevonden", "Dit gesprek bestaat niet (meer).") }
            _ = try role(for: elderlyId)
            return try audio(for: conversationsByElderly[elderlyId]?.first { $0.id == conversationId })
        }
    }

    func mood(elderlyId: String, days: Int) async throws -> MoodOverview {
        try await simulate()
        return try sync {
            _ = try role(for: elderlyId)
            let points = moodDays(elderlyId, days: [7, 30, 90].contains(days) ? days : 30)
            let moods = points.compactMap(\.mood)
            let average = moods.isEmpty ? nil : (moods.reduce(0, +) / Double(moods.count) * 10).rounded() / 10
            let half = moods.count / 2
            let first = moods.prefix(half), last = moods.suffix(moods.count - half)
            let delta = (last.reduce(0, +) / Double(max(1, last.count))) - (first.reduce(0, +) / Double(max(1, first.count)))
            let trend: MoodTrend = delta > 0.25 ? .stijgend : (delta < -0.25 ? .dalend : .stabiel)
            return MoodOverview(days: points, average: average, trend: trend)
        }
    }

    // MARK: Life story

    func lifeStory(elderlyId: String, category: LifeStoryCategory?, cursor: String?, limit: Int) async throws -> Page<LifeStoryEntry> {
        try await simulate()
        return try sync {
            _ = try role(for: elderlyId)
            return paginate(sortedStory(elderlyId, category: category), cursor: cursor, limit: limit)
        }
    }

    private func sortedStory(_ elderlyId: String, category: LifeStoryCategory?) -> [LifeStoryEntry] {
        (lifeStories[elderlyId] ?? [])
            .filter { category == nil || $0.category == category }
            .sorted { lhs, rhs in
                switch (lhs.year, rhs.year) {
                case let (l?, r?) where l != r: return l < r
                case (nil, _?): return false
                case (_?, nil): return true
                default: return (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
                }
            }
    }

    func createLifeStoryEntry(elderlyId: String, _ input: LifeStoryInput) async throws -> LifeStoryEntry {
        try await simulate()
        return try sync {
            try requireBeheerder(elderlyId)
            let entry = LifeStoryEntry(id: UUID().uuidString, category: input.category, title: input.title, content: input.content,
                                       year: input.year, people: input.people, places: input.places, quote: input.quote.nilIfBlank,
                                       conversationId: nil, createdBy: .caregiver, createdAt: Date())
            lifeStories[elderlyId, default: []].append(entry)
            return entry
        }
    }

    func updateLifeStoryEntry(entryId: String, _ input: LifeStoryInput) async throws -> LifeStoryEntry {
        try await simulate()
        return try sync {
            guard let elderlyId = elderlyId(ofEntry: entryId) else { throw fail(404, "niet_gevonden", "Dit verhaal bestaat niet (meer).") }
            try requireBeheerder(elderlyId)
            let index = lifeStories[elderlyId]!.firstIndex { $0.id == entryId }!
            var entry = lifeStories[elderlyId]![index]
            entry.category = input.category
            entry.title = input.title
            entry.content = input.content
            entry.year = input.year
            entry.people = input.people
            entry.places = input.places
            entry.quote = input.quote.nilIfBlank
            lifeStories[elderlyId]![index] = entry
            return entry
        }
    }

    func deleteLifeStoryEntry(entryId: String) async throws {
        try await simulate()
        try sync {
            guard let elderlyId = elderlyId(ofEntry: entryId) else { return }
            try requireBeheerder(elderlyId)
            lifeStories[elderlyId]?.removeAll { $0.id == entryId }
        }
    }

    // MARK: Reminders

    func reminders(elderlyId: String) async throws -> [Reminder] {
        try await simulate()
        return try sync {
            _ = try role(for: elderlyId)
            return refreshedReminders(elderlyId)
        }
    }

    func createReminder(elderlyId: String, _ input: ReminderInput) async throws -> Reminder {
        try await simulate()
        return try sync {
            try requireBeheerder(elderlyId)
            let reminder = Reminder(id: UUID().uuidString, title: input.title, notes: input.notes.nilIfBlank, type: input.type,
                                    schedule: input.schedule, delivery: input.delivery, active: input.active, createdBy: .caregiver,
                                    nextAt: input.active ? input.schedule.nextOccurrence(after: Date()) : nil, lastCompletedAt: nil)
            remindersByElderly[elderlyId, default: []].append(reminder)
            return reminder
        }
    }

    func updateReminder(reminderId: String, _ input: ReminderInput) async throws -> Reminder {
        try await simulate()
        return try sync {
            guard let elderlyId = elderlyId(ofReminder: reminderId) else { throw fail(404, "niet_gevonden", "Deze herinnering bestaat niet (meer).") }
            try requireBeheerder(elderlyId)
            let index = remindersByElderly[elderlyId]!.firstIndex { $0.id == reminderId }!
            var reminder = remindersByElderly[elderlyId]![index]
            reminder.title = input.title
            reminder.notes = input.notes.nilIfBlank
            reminder.type = input.type
            reminder.schedule = input.schedule
            reminder.delivery = input.delivery
            reminder.active = input.active
            reminder.nextAt = input.active ? input.schedule.nextOccurrence(after: Date()) : nil
            remindersByElderly[elderlyId]![index] = reminder
            return reminder
        }
    }

    func deleteReminder(reminderId: String) async throws {
        try await simulate()
        try sync {
            guard let elderlyId = elderlyId(ofReminder: reminderId) else { return }
            try requireBeheerder(elderlyId)
            remindersByElderly[elderlyId]?.removeAll { $0.id == reminderId }
        }
    }

    // MARK: Alerts

    func alerts(elderlyId: String, status: AlertListFilter, cursor: String?, limit: Int) async throws -> Page<NoahAlert> {
        try await simulate()
        return try sync {
            _ = try role(for: elderlyId)
            let all = (alertsByElderly[elderlyId] ?? []).sorted { $0.createdAt > $1.createdAt }
            return paginate(status == .open ? all.filter { $0.status == .open } : all, cursor: cursor, limit: limit)
        }
    }

    func acknowledgeAlert(alertId: String) async throws -> NoahAlert {
        try await simulate()
        return try sync {
            guard let elderlyId = elderlyId(ofAlert: alertId) else { throw fail(404, "niet_gevonden", "Deze melding bestaat niet (meer).") }
            _ = try role(for: elderlyId)
            let index = alertsByElderly[elderlyId]!.firstIndex { $0.id == alertId }!
            var alert = alertsByElderly[elderlyId]![index]
            if alert.status == .open {
                alert.status = .gezien
                alert.acknowledgedBy = caregiverRecords[currentCaregiverId]?.name?.components(separatedBy: " ").first ?? "Jij"
            }
            alertsByElderly[elderlyId]![index] = alert
            return alert
        }
    }

    func resolveAlert(alertId: String, falseAlarm: Bool, note: String?) async throws -> NoahAlert {
        try await simulate()
        return try sync {
            guard let elderlyId = elderlyId(ofAlert: alertId) else { throw fail(404, "niet_gevonden", "Deze melding bestaat niet (meer).") }
            try requireBeheerder(elderlyId)
            let index = alertsByElderly[elderlyId]!.firstIndex { $0.id == alertId }!
            var alert = alertsByElderly[elderlyId]![index]
            alert.status = .afgehandeld
            if alert.acknowledgedBy == nil {
                alert.acknowledgedBy = caregiverRecords[currentCaregiverId]?.name?.components(separatedBy: " ").first ?? "Jij"
            }
            alertsByElderly[elderlyId]![index] = alert
            return alert
        }
    }

    // MARK: Calls & phone line

    func callNow(elderlyId: String, mode: ConversationMode) async throws -> CallNowResponse {
        try await simulate()
        return try sync {
            try requireBeheerder(elderlyId)
            guard profiles[elderlyId]?.access == .active else {
                throw fail(409, "inactive", "Noah is nog niet actief voor dit profiel. Start eerst het abonnement.")
            }
            // v2.2: Noah only calls confirmed numbers.
            if profiles[elderlyId]?.phoneVerified == false {
                throw fail(409, "telefoonnummer_niet_bevestigd", "Het telefoonnummer is nog niet bevestigd.")
            }
            let quiet = settingsByElderly[elderlyId]?.quietHours ?? NoahSettings.defaults.quietHours
            let now = DutchFormat.timeString(from: Date())
            let inQuiet = quiet.start > quiet.end ? (now >= quiet.start || now < quiet.end) : (now >= quiet.start && now < quiet.end)
            if inQuiet {
                throw fail(409, "quiet_hours", "Het is nu rusttijd (\(quiet.start)–\(quiet.end)). Noah belt dan niet, behalve in een noodgeval.")
            }
            let recording = settingsByElderly[elderlyId]?.recording ?? .uit
            return CallNowResponse(status: "gestart", mode: mode,
                                   recording: recording == .alleGesprekken || (recording == .levensverhaal && mode == .levensverhaal))
        }
    }

    func phoneLine() async throws -> PhoneLine {
        try await simulate()
        return PhoneLine(
            phoneNumber: "+3197010203456",
            displayNumber: "097 0102 3456",
            instructions: "Bel dit nummer vanaf de telefoon die in het profiel staat. Aan de telefoon kent Noah alleen de voornaam; het volledige gesprek met levensverhaal en herinneringen is er in de app. Bellen kost hetzelfde als een gewoon gesprek naar een vast nummer."
        )
    }

    // MARK: Subscription

    func subscription(elderlyId: String) async throws -> Subscription {
        try await simulate()
        return try sync {
            try requireBeheerder(elderlyId)
            var subscription = subscriptions[elderlyId] ?? Subscription(status: .geen, productId: nil, renewsAt: nil, expiresAt: nil, platform: nil, paidByMe: nil)
            if subscription.status.grantsAccess { subscription.usage = usage(elderlyId) }
            return subscription
        }
    }

    func submitAppStoreTransaction(elderlyId: String, signedTransaction: String) async throws -> Subscription {
        try await simulate()
        return try sync {
            try requireBeheerder(elderlyId)
            let subscription = Subscription(status: .intro, productId: Self.productID(fromMockJWS: signedTransaction),
                                            renewsAt: DutchFormat.calendar.date(byAdding: .month, value: 1, to: Date()),
                                            expiresAt: nil, platform: "app_store", paidByMe: true, freeConversationsLeft: 0)
            subscriptions[elderlyId] = subscription
            profiles[elderlyId]?.access = .active
            return subscription
        }
    }

    /// Simulated purchases send `mock-signed-transaction:<productId>` (never a real JWS).
    static func productID(fromMockJWS jws: String) -> String {
        let parts = jws.split(separator: ":", maxSplits: 1)
        if parts.count == 2, Plan.isPlanProduct(String(parts[1])) { return String(parts[1]) }
        return Plan.productID
    }

    // MARK: Device

    /// The profile of this phone, from the mock device token (`hnd_mock_<elderlyId>`); Wim when
    /// there is none (tests).
    private var deviceElderlyId: String {
        if let token = deviceToken(), token.hasPrefix("hnd_mock_") {
            let id = String(token.dropFirst("hnd_mock_".count))
            if profiles[id] != nil { return id }
        }
        return MockIDs.wim
    }

    /// v2.3: device endpoints for self-managed profiles only.
    private func requireSelfManaged() throws -> String {
        let id = deviceElderlyId
        guard profiles[id]?.managedBy == .zelf else {
            throw fail(403, "beheerd_door_mantelzorger", "Dit regelt uw familie voor u.")
        }
        return id
    }

    func deviceMe() async throws -> DeviceMe {
        try await simulate()
        return sync {
            let id = deviceElderlyId
            let profile = profiles[id]!
            let next = refreshedReminders(id).filter { $0.active && $0.nextAt != nil }.min { $0.nextAt! < $1.nextAt! }
            return DeviceMe(
                elderly: .init(id: id, preferredName: profile.preferredName, addressForm: profile.addressForm, noahName: settingsByElderly[id]?.noahName ?? "Noah"),
                access: profile.access,
                lastConversationAt: conversationsByElderly[id]?.first?.startedAt,
                nextReminder: next,
                managedBy: profile.managedBy,
                restricted: v23Backend ? nil : restrictedPhone,
                restrictedUntil: restrictedPhone && !v23Backend ? Date().addingTimeInterval(60 * 3600) : nil
            )
        }
    }

    func startDeviceConversation(mode: ConversationMode) async throws -> ConversationSession {
        try await simulate()
        return try sync {
            let id = deviceElderlyId
            guard profiles[id]?.access == .active else {
                throw fail(409, "inactive", "Noah is nog niet actief. Vraag uw mantelzorger om hulp.")
            }
            // Free trial (v2.2): used up when the session starts; a second one is inactive.
            if var subscription = subscriptions[id], !subscription.isPaidOrBeta, let free = subscription.freeConversationsLeft, free > 0 {
                subscription.freeConversationsLeft = free - 1
                subscriptions[id] = subscription
                if free - 1 == 0 { profiles[id]?.access = .inactive }
            }
            let settings = settingsByElderly[id] ?? .defaults
            let mode: ConversationMode = mode == .levensverhaal ? .levensverhaal : .gesprek
            let recording: Bool
            switch settings.recording {
            case .alleGesprekken: recording = true
            case .levensverhaal: recording = mode == .levensverhaal
            case .uit, .unknown: recording = false
            }
            // Fair use used up: Noah keeps working, with shorter conversations.
            let minutes = usage(id).overAllowance
                ? min(settings.maxConversationMinutes, Plan.cappedConversationMinutes)
                : settings.maxConversationMinutes
            return ConversationSession(
                agentId: "agent_mock",
                conversationToken: "mock-conversation-token",
                dynamicVariables: ["user_name": .string(profiles[id]?.preferredName ?? "Wim"), "session_claim": .string("mock")],
                overrides: nil,
                // `-mockMaxDurationSeconds 75` shortens sessions to try the calm goodbye at the end.
                maxDurationSeconds: defaults.integer(forKey: "mockMaxDurationSeconds") > 0 ? defaults.integer(forKey: "mockMaxDurationSeconds") : minutes * 60,
                mode: mode,
                recording: recording
            )
        }
    }

    func deviceCallMe() async throws {
        try await simulate()
        try sync {
            guard profiles[deviceElderlyId]?.access == .active else {
                throw fail(409, "inactive", "Noah is nog niet actief. Vraag uw mantelzorger om hulp.")
            }
            if profiles[deviceElderlyId]?.phoneVerified == false {
                throw fail(409, "telefoonnummer_niet_bevestigd", "Uw telefoonnummer is nog niet bevestigd.")
            }
        }
    }

    func deviceLifeStory(cursor: String?, limit: Int) async throws -> Page<LifeStoryEntry> {
        try await simulate()
        try requireUnrestricted()
        return sync { paginate(sortedStory(deviceElderlyId, category: nil), cursor: cursor, limit: limit) }
    }

    func deviceConversationAudio(conversationId: String) async throws -> ConversationAudio {
        try await simulate()
        return try sync {
            try audio(for: conversationsByElderly[deviceElderlyId]?.first { $0.id == conversationId })
        }
    }

    func deviceReminders() async throws -> [Reminder] {
        try await simulate()
        return sync {
            refreshedReminders(deviceElderlyId).filter { $0.active && $0.nextAt != nil }.sorted { $0.nextAt! < $1.nextAt! }
        }
    }

    func registerDevicePushToken(_ token: String, environment: String) async throws {
        try await simulate()
    }

    func unpairThisDevice() async throws {
        try await simulate()
    }

    // MARK: Self sign-up (v2.3)

    func startElderSignUp(phoneNumber: String, channel: PhoneVerificationChannel) async throws {
        try await simulate()
        guard PhoneNumberFormat.e164(phoneNumber) != nil else {
            throw fail(400, "ongeldige_invoer", "Dit telefoonnummer klopt niet.")
        }
    }

    func verifyElderSignUp(_ request: ElderSignUpVerifyRequest) async throws -> ElderVerifyOutcome {
        try await simulate()
        return try sync {
            guard request.code.count == 6, request.code != "000000" else {
                throw fail(400, "ongeldige_code", "Deze code klopt niet of is verlopen.")
            }
            // v2.4: a number someone else put on a profile the older person never used: ask first.
            if !v23Backend, let existing = profiles.values.first(where: { $0.phoneNumber == request.phoneNumber }),
               existing.managedBy != .zelf, existing.phoneVerified != true, (devicesByElderly[existing.id] ?? []).isEmpty {
                let creator = memberships[existing.id]?.first { $0.value == .beheerder }.flatMap { caregiverRecords[$0.key]?.name }
                return .choiceNeeded(ElderClaimChoice(claimToken: "hnc_mock_\(existing.id)", expiresAt: Date().addingTimeInterval(900),
                                                      profile: .init(preferredName: existing.preferredName, createdBy: creator)))
            }
            return .signedIn(try signIn(phoneNumber: request.phoneNumber, preferredName: request.preferredName, addressForm: request.addressForm))
        }
    }

    func claimElderSignUp(_ request: ElderClaimRequest) async throws -> ElderSignUpResponse {
        try await simulate()
        return try sync {
            try requireV24()
            guard request.claimToken.hasPrefix("hnc_mock_") else { throw fail(400, "claim_ongeldig", "Begin opnieuw.") }
            let id = String(request.claimToken.dropFirst("hnc_mock_".count))
            guard let existing = profiles[id], let phone = existing.phoneNumber else { throw fail(400, "claim_ongeldig", "Begin opnieuw.") }
            switch request.choice {
            case .koppelen:
                profiles[id]?.phoneVerified = true
                profiles[id]?.phoneVerifiedVia = "code"
                let deviceId = UUID().uuidString
                devicesByElderly[id, default: []].append(PairedDevice(id: deviceId, deviceName: request.deviceName ?? "iPhone", platform: "ios", pairedAt: Date(), lastSeenAt: Date()))
                thisDeviceId[id] = deviceId
                transparency[id, default: Transparency()].appShownAt = nil
                return ElderSignUpResponse(deviceToken: "hnd_mock_\(id)", device: .init(id: deviceId),
                                           elderly: .init(id: id, preferredName: existing.preferredName, noahName: settingsByElderly[id]?.noahName ?? "Noah"),
                                           isNewProfile: false, managedBy: .mantelzorger)
            case .eigenProfiel:
                profiles[id]?.phoneNumber = nil
                profiles[id]?.phoneVerified = false
                alertsByElderly[id, default: []].insert(
                    NoahAlert(id: UUID().uuidString, type: .nummerLosgekoppeld, severity: .waarschuwing, title: "Het nummer is losgekoppeld van het profiel van \(existing.preferredName)",
                              body: "Iemand met dit nummer heeft gekozen voor een eigen profiel. Het profiel van \(existing.preferredName) heeft nu geen telefoonnummer.",
                              conversationId: nil, status: .open, createdAt: Date(), acknowledgedBy: nil), at: 0)
                return try signIn(phoneNumber: phone, preferredName: request.preferredName, addressForm: request.addressForm)
            }
        }
    }

    /// v2.3/v2.4 sign-in with a verified number (inside `sync`).
    private func signIn(phoneNumber: String, preferredName: String?, addressForm: AddressForm?) throws -> ElderSignUpResponse {
        do {
            let request = (phoneNumber: phoneNumber, preferredName: preferredName, addressForm: addressForm)
            let deviceId = UUID().uuidString
            if let existing = profiles.values.first(where: { $0.phoneNumber == request.phoneNumber }) {
                // Caregiver-managed: this phone is paired to that profile, the family gets a notice.
                let managedBy: ManagedBy = existing.managedBy == .zelf ? .zelf : .mantelzorger
                if managedBy == .mantelzorger {
                    alertsByElderly[existing.id, default: []].insert(
                        NoahAlert(id: UUID().uuidString, type: .apparaatGekoppeld, severity: .info, title: "De telefoon van \(existing.preferredName) is gekoppeld",
                                  body: "\(existing.preferredName) heeft zich aangemeld met het eigen telefoonnummer. Die telefoon is nu gekoppeld aan dit profiel.",
                                  conversationId: nil, status: .open, createdAt: Date(), acknowledgedBy: nil), at: 0)
                }
                // v2.4: a profile in use (a phone seen lately, or beheerders) gets a restricted phone.
                let inUse = !(devicesByElderly[existing.id] ?? []).isEmpty || memberships[existing.id]?.values.contains(.beheerder) == true
                let restricted = inUse && !v23Backend
                devicesByElderly[existing.id, default: []].append(PairedDevice(id: deviceId, deviceName: "iPhone", platform: "ios", pairedAt: Date(), lastSeenAt: Date(), restricted: restricted))
                return ElderSignUpResponse(deviceToken: "hnd_mock_\(existing.id)", device: .init(id: deviceId),
                                           elderly: .init(id: existing.id, preferredName: existing.preferredName, noahName: settingsByElderly[existing.id]?.noahName ?? "Noah"),
                                           isNewProfile: false, managedBy: managedBy, restricted: restricted,
                                           restrictedUntil: restricted ? Date().addingTimeInterval(72 * 3600) : nil)
            }
            let id = UUID().uuidString
            let profile = createSelfProfile(id: id, phoneNumber: request.phoneNumber, preferredName: request.preferredName ?? "",
                                            addressForm: request.addressForm ?? .u)
            _ = profile
            devicesByElderly[id] = [PairedDevice(id: deviceId, deviceName: "iPhone", platform: "ios", pairedAt: Date(), lastSeenAt: Date())]
            thisDeviceId[id] = deviceId
            return ElderSignUpResponse(deviceToken: "hnd_mock_\(id)", device: .init(id: deviceId),
                                       elderly: .init(id: id, preferredName: profile.preferredName, noahName: "Noah"),
                                       isNewProfile: true, managedBy: .zelf)
        }
    }

    // MARK: Device endpoints for self-managed profiles (v2.3)

    func deviceProfile() async throws -> DeviceProfile {
        try await simulate()
        return sync {
            let id = deviceElderlyId
            let profile = profiles[id]!
            var result = DeviceProfile(id: id, preferredName: profile.preferredName, addressForm: profile.addressForm, phoneNumber: profile.phoneNumber,
                                       managedBy: profile.managedBy ?? .mantelzorger, access: profile.access)
            if !v23Backend { result.outboundPaused = outboundPaused.contains(id) }
            return result
        }
    }

    func updateDeviceProfile(_ patch: DeviceProfilePatch) async throws -> DeviceProfile {
        try await simulate()
        try sync {
            let id = try requireSelfManaged()
            if let name = patch.preferredName?.trimmingCharacters(in: .whitespacesAndNewlines) {
                guard !name.isEmpty else { throw fail(400, "ongeldige_invoer", "Vul een naam in.") }
                profiles[id]?.preferredName = name
                if profiles[id]?.firstName.isEmpty == true { profiles[id]?.firstName = name }
            }
            if let form = patch.addressForm, form != .unknown { profiles[id]?.addressForm = form }
            persistSelfSignUps()
        }
        return try await deviceProfile()
    }

    func deviceSettings() async throws -> NoahSettings {
        try await simulate()
        return try sync {
            let id = try requireSelfManaged()
            var settings = settingsByElderly[id] ?? .defaults
            if !v23Backend { settings.outboundPaused = outboundPaused.contains(id) }
            return settings
        }
    }

    func updateDeviceSettings(_ patch: NoahSettingsPatch) async throws -> NoahSettings {
        try await simulate()
        return try sync {
            let id = try requireSelfManaged()
            if let recording = patch.recording, recording != .uit, defaults.bool(forKey: "mockRecordingUnavailable") {
                throw fail(503, "niet_geconfigureerd", "Opnemen is op dit moment niet beschikbaar.")
            }
            if let speed = patch.speakingSpeed, !NoahSettings.speedRange.contains(speed) {
                throw fail(400, "ongeldige_invoer", "Spreektempo moet tussen 0.8 en 1.2 liggen.")
            }
            try requireUnrestricted()
            if let paused = patch.outboundPaused {
                if paused { outboundPaused.insert(id) } else { outboundPaused.remove(id) }
            }
            var updated = patch.applied(to: settingsByElderly[id] ?? .defaults)
            updated.outboundPaused = nil
            settingsByElderly[id] = updated
            if !v23Backend { updated.outboundPaused = outboundPaused.contains(id) }
            return updated
        }
    }

    func deviceEmergencyContacts() async throws -> [EmergencyContact] {
        try await simulate()
        return try sync { (contacts[try requireSelfManaged()] ?? []).sorted { $0.priority < $1.priority } }
    }

    func createDeviceEmergencyContact(_ input: EmergencyContactInput) async throws -> EmergencyContact {
        try await simulate()
        return try sync {
            let id = try requireSelfManaged()
            try requireUnrestricted()
            guard PhoneNumberFormat.e164(input.phoneNumber) != nil else { throw fail(400, "ongeldige_invoer", "Dit telefoonnummer klopt niet.") }
            if !v23Backend, (contacts[id]?.count ?? 0) >= EmergencyContactLimit.max {
                throw fail(409, "te_veel_noodcontacten", "U kunt maximaal 5 noodcontacten hebben.")
            }
            let contact = EmergencyContact(id: UUID().uuidString, name: input.name, phoneNumber: input.phoneNumber, relation: input.relation,
                                           priority: (contacts[id]?.count ?? 0) + 1, notifyBySms: input.notifyBySms, notifyByCall: input.notifyByCall)
            contacts[id, default: []].append(contact)
            return contact
        }
    }

    func updateDeviceEmergencyContact(contactId: String, _ input: EmergencyContactInput) async throws -> EmergencyContact {
        try await simulate()
        return try sync {
            let id = try requireSelfManaged()
            guard let index = contacts[id]?.firstIndex(where: { $0.id == contactId }) else { throw fail(404, "niet_gevonden", "Dit contact bestaat niet (meer).") }
            var contact = contacts[id]![index]
            contact.name = input.name
            contact.phoneNumber = input.phoneNumber
            contact.relation = input.relation
            contact.notifyBySms = input.notifyBySms
            contact.notifyByCall = input.notifyByCall
            contacts[id]![index] = contact
            return contact
        }
    }

    func deleteDeviceEmergencyContact(contactId: String) async throws {
        try await simulate()
        try sync {
            let id = try requireSelfManaged()
            contacts[id]?.removeAll { $0.id == contactId }
            contacts[id] = contacts[id]?.enumerated().map { index, contact in
                var copy = contact
                copy.priority = index + 1
                return copy
            }
        }
    }

    func deviceSubscription() async throws -> Subscription {
        try await simulate()
        return sync {
            let id = deviceElderlyId
            var subscription = subscriptions[id] ?? Subscription(status: .geen, productId: nil, renewsAt: nil, expiresAt: nil, platform: nil, paidByMe: nil)
            // `paidByMe` = paid via this device: a caregiver pays for Wim and Riet.
            if profiles[id]?.managedBy != .zelf { subscription.paidByMe = false }
            if subscription.status.grantsAccess { subscription.usage = usage(id) }
            return subscription
        }
    }

    func submitDeviceAppStoreTransaction(signedTransaction: String) async throws -> Subscription {
        try await simulate()
        return try sync {
            let id = try requireSelfManaged()
            let subscription = Subscription(status: .intro, productId: Self.productID(fromMockJWS: signedTransaction),
                                            renewsAt: DutchFormat.calendar.date(byAdding: .month, value: 1, to: Date()),
                                            expiresAt: nil, platform: "app_store", paidByMe: true, freeConversationsLeft: 0)
            subscriptions[id] = subscription
            profiles[id]?.access = .active
            return subscription
        }
    }

    func createDeviceInvitation(role: Role, confirmed: Bool) async throws -> Invitation {
        try await simulate()
        return try sync {
            let id = try requireSelfManaged()
            try requireUnrestricted()
            if role == .beheerder, !confirmed, !v23Backend {
                throw fail(400, "bevestiging_nodig", "Bevestig eerst dat deze persoon mag helpen beheren.")
            }
            let code = makeInvitationCode()
            // v2.4: invitations made on the phone are valid for 24 hours.
            let validity: TimeInterval = v23Backend ? 7 * 86_400 : 86_400
            invitations[code] = MockInvitation(id: UUID().uuidString, code: code, elderlyId: id, role: role, createdAt: Date(),
                                               expiresAt: Date().addingTimeInterval(validity), createdBy: "zelf")
            let url = "https://hellonoah.ai/uitnodiging/\(code)"
            let what = role == .beheerder ? "om mee te kijken en mee te helpen" : "om mee te kijken"
            return Invitation(code: code, url: url, expiresAt: Date().addingTimeInterval(validity),
                              shareText: "Ik gebruik Noah en nodig je uit \(what). Installeer de HelloNoah-app en open deze link: \(url) (code \(code))")
        }
    }

    func deviceCaregivers() async throws -> [CaregiverMembership] {
        try await simulate()
        return sync {
            let id = deviceElderlyId
            return (memberships[id] ?? [:]).map { caregiverId, role in
                CaregiverMembership(caregiverId: caregiverId, name: caregiverRecords[caregiverId]?.name ?? "Familielid", role: role,
                                    joinedAt: joinedAt[caregiverId + id], isMe: false)
            }.sorted { ($0.name ?? "") < ($1.name ?? "") }
        }
    }

    /// v2.3: self-managed profiles; v2.4: also self-registered profiles while a family member helps.
    private func requireOwnProfile() throws -> String {
        let id = deviceElderlyId
        if profiles[id]?.managedBy == .zelf || (!v23Backend && selfRegistered.contains(id)) { return id }
        throw fail(403, "beheerd_door_mantelzorger", "Dit regelt uw familie voor u.")
    }

    func removeDeviceCaregiver(caregiverId: String) async throws {
        try await simulate()
        try sync {
            let id = try requireOwnProfile()
            try requireUnrestricted()
            memberships[id]?[caregiverId] = nil
            if profiles[id]?.managedBy == .mantelzorger, memberships[id]?.values.contains(.beheerder) != true {
                profiles[id]?.managedBy = .zelf
                persistSelfSignUps()
            }
        }
    }

    func exportDevice() async throws -> Data {
        try await simulate()
        try requireUnrestricted()
        return try sync {
            // v2.4: the older person may always download their own data.
            let id = v23Backend ? try requireSelfManaged() : deviceElderlyId
            let export: [String: AnyEncodable] = [
                "profiel": AnyEncodable(profiles[id]),
                "instellingen": AnyEncodable(settingsByElderly[id]),
                "noodcontacten": AnyEncodable(contacts[id] ?? []),
                "gesprekken": AnyEncodable(conversationsByElderly[id] ?? []),
                "levensverhaal": AnyEncodable(lifeStories[id] ?? []),
                "herinneringen": AnyEncodable(remindersByElderly[id] ?? []),
                "exportedAt": AnyEncodable(NoahJSON.formatDate(Date())),
            ]
            return try NoahJSON.makeEncoder(pretty: true).encode(export)
        }
    }

    func deleteDeviceAccount(subscriptionAcknowledged: Bool) async throws {
        try await simulate()
        try sync {
            let id = try requireOwnProfile()
            try requireUnrestricted()
            if !subscriptionAcknowledged, !v23Backend, subscriptions[id]?.status == .actief || subscriptions[id]?.status == .intro {
                throw fail(409, "abonnement_actief", "Uw abonnement loopt nog. Zegt u het eerst op in de App Store.")
            }
            profiles[id] = nil
            memberships[id] = nil
            settingsByElderly[id] = nil
            contacts[id] = nil
            conversationsByElderly[id] = nil
            lifeStories[id] = nil
            remindersByElderly[id] = nil
            alertsByElderly[id] = nil
            devicesByElderly[id] = nil
            subscriptions[id] = nil
            persistSelfSignUps()
        }
    }

    // MARK: Device, transparency and control (v2.4)

    private func transparencyObject(_ id: String) -> DeviceTransparency {
        let profile = profiles[id]
        let members = (memberships[id] ?? [:]).map { caregiverId, role in
            DeviceTransparency.Member(id: caregiverId, name: caregiverRecords[caregiverId]?.name ?? "Familielid", role: role, joinedAt: joinedAt[caregiverId + id])
        }.sorted { ($0.name ?? "") < ($1.name ?? "") }
        let sharing = sharingByElderly[id] ?? .alles
        let recording = settingsByElderly[id]?.recording ?? .uit
        return DeviceTransparency(
            managedBy: profile?.managedBy,
            caregivers: members,
            pendingInvitations: invitations.values.filter { $0.elderlyId == id && $0.expiresAt > Date() }.sorted { $0.createdAt > $1.createdAt }
                .map { PendingInvitation(id: $0.id, code: nil, role: $0.role, createdAt: $0.createdAt, expiresAt: $0.expiresAt, createdBy: $0.createdBy) },
            caregiverRequests: caregiverRequests.filter { $0.elderlyId == id }.map(\.request),
            familySees: members.isEmpty ? [] : FamilySees.sentences(sharing: sharing, recording: recording),
            sharing: sharing,
            recording: recording,
            appShownAt: transparency[id]?.appShownAt,
            deletionRequest: deletionRequests[id],
            selfRegistered: selfRegistered.contains(id)
        )
    }

    func deviceTransparency() async throws -> DeviceTransparency {
        try await simulate()
        return try sync {
            try requireV24()
            return transparencyObject(deviceElderlyId)
        }
    }

    func markTransparencySeen() async throws {
        try await simulate()
        try sync {
            try requireV24()
            transparency[deviceElderlyId, default: Transparency()].appShownAt = Date()
        }
    }

    func updateSharing(_ level: SharingLevel) async throws -> DeviceTransparency {
        try await simulate()
        return try sync {
            try requireV24()
            try requireUnrestricted()
            let id = deviceElderlyId
            if sharingByElderly[id] != level, !(memberships[id] ?? [:]).isEmpty {
                alertsByElderly[id, default: []].insert(
                    NoahAlert(id: UUID().uuidString, type: .privacyGewijzigd, severity: .waarschuwing,
                              title: "\(profiles[id]?.preferredName ?? "Uw naaste") heeft aangepast wat de familie ziet",
                              body: nil, conversationId: nil, status: .open, createdAt: Date(), acknowledgedBy: nil), at: 0)
            }
            sharingByElderly[id] = level
            return transparencyObject(id)
        }
    }

    func requestDeletion(subscriptionAcknowledged: Bool) async throws -> DeletionRequest {
        try await simulate()
        return try sync {
            try requireV24()
            try requireUnrestricted()
            let id = deviceElderlyId
            if !subscriptionAcknowledged, subscriptions[id]?.status == .actief || subscriptions[id]?.status == .intro {
                throw fail(409, "abonnement_actief", "Er loopt nog een abonnement.")
            }
            let request = DeletionRequest(requestedAt: Date(), executesAt: Date().addingTimeInterval(14 * 86_400))
            deletionRequests[deviceElderlyId] = request
            return request
        }
    }

    func withdrawDeletion() async throws {
        try await simulate()
        try sync {
            try requireV24()
            deletionRequests[deviceElderlyId] = nil
        }
    }

    func deviceDevices() async throws -> [PairedDevice] {
        try await simulate()
        return try sync {
            try requireV24()
            let id = deviceElderlyId
            return (devicesByElderly[id] ?? []).map { device in
                var copy = device
                copy.isThisDevice = device.id == thisDeviceId[id]
                return copy
            }
        }
    }

    func approveDeviceFromDevice(deviceId: String) async throws {
        try await simulate()
        try sync {
            try requireV24()
            try requireUnrestricted()
            let id = deviceElderlyId
            guard let index = devicesByElderly[id]?.firstIndex(where: { $0.id == deviceId }) else { throw fail(404, "niet_gevonden", "Deze telefoon bestaat niet (meer).") }
            devicesByElderly[id]![index].restricted = false
        }
    }

    func rejectDeviceFromDevice(deviceId: String) async throws {
        try await simulate()
        try sync {
            try requireV24()
            try requireUnrestricted()
            devicesByElderly[deviceElderlyId]?.removeAll { $0.id == deviceId }
        }
    }

    func approveCaregiverRequest(id requestId: String) async throws {
        try await simulate()
        try sync {
            try requireV24()
            try requireUnrestricted()
            guard let index = caregiverRequests.firstIndex(where: { $0.request.id == requestId }) else { throw fail(404, "niet_gevonden", "Dit verzoek bestaat niet (meer).") }
            let request = caregiverRequests.remove(at: index)
            addMember(request.caregiverId, to: request.elderlyId, role: request.request.role)
        }
    }

    func rejectCaregiverRequest(id requestId: String) async throws {
        try await simulate()
        try sync {
            try requireV24()
            caregiverRequests.removeAll { $0.request.id == requestId }
        }
    }

    func revokeDeviceInvitation(id invitationId: String) async throws {
        try await simulate()
        try sync {
            try requireV24()
            _ = try requireOwnProfile()
            invitations = invitations.filter { $0.value.id != invitationId }
        }
    }

    func reorderDeviceEmergencyContacts(ids: [String]) async throws {
        try await simulate()
        try sync {
            let id = try requireSelfManaged()
            try requireUnrestricted()
            let current = contacts[id] ?? []
            contacts[id] = ids.enumerated().compactMap { index, contactId in
                guard var contact = current.first(where: { $0.id == contactId }) else { return nil }
                contact.priority = index + 1
                return contact
            }
        }
    }

    /// Debug helper for screenshots: a pending "helpen beheren" request and a new phone on Wim.
    func seedPendingRequestsForWim() {
        sync {
            guard caregiverRequests.isEmpty else { return }
            caregiverRequests.append(MockRequest(request: CaregiverRequest(id: "CR1", name: "Mark de Vries", role: .beheerder, requestedAt: Date().addingTimeInterval(-1800)),
                                                 caregiverId: MockIDs.mark, elderlyId: MockIDs.wim))
            devicesByElderly[MockIDs.wim, default: []].append(PairedDevice(id: MockIDs.wimNewDevice, deviceName: "iPhone", platform: "ios",
                                                                           pairedAt: Date().addingTimeInterval(-3600), lastSeenAt: Date().addingTimeInterval(-600), restricted: true))
        }
    }
}

#endif
