import Foundation

// Codable models for HelloNoah API v2 (`elderly-companion-api/docs/api-v2.md`).
// Keys are camelCase exactly as in the contract, so no key strategy is used. Unknown fields are
// ignored, missing arrays decode as [], unknown enum values decode to `.unknown`.

// MARK: - Common

struct Page<Item: Decodable>: Decodable {
    let items: [Item]
    let nextCursor: String?
}

struct ItemsResponse<Item: Decodable>: Decodable {
    let items: [Item]
}

struct APIErrorBody: Decodable {
    struct Detail: Decodable {
        let code: String
        let message: String?
    }
    let error: Detail
}

enum Role: String, TolerantEnum {
    case beheerder
    case lezer
    case unknown
    static var unknownCase: Role { .unknown }
}

enum Access: String, TolerantEnum {
    case active
    case inactive
    case unknown
    static var unknownCase: Access { .unknown }
}

enum AddressForm: String, TolerantEnum {
    case u
    case jij
    case unknown
    static var unknownCase: AddressForm { .unknown }
}

enum Gender: String, TolerantEnum {
    case man
    case vrouw
    case anders
    case unknown
    static var unknownCase: Gender { .unknown }
}

enum LivingSituation: String, TolerantEnum {
    case alleen
    case metPartner = "met_partner"
    case metFamilie = "met_familie"
    case zorginstelling
    case unknown
    static var unknownCase: LivingSituation { .unknown }
}

enum CreatedBy: String, TolerantEnum {
    case caregiver
    case noah
    case unknown
    static var unknownCase: CreatedBy { .unknown }
}

// MARK: - Auth

struct Caregiver: Codable, Hashable, Identifiable {
    let id: String
    var name: String?
    var email: String?
    var phoneNumber: String?
    var createdAt: Date?
}

struct AuthResponse: Decodable {
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let caregiver: Caregiver?
    @DefaultFalse var isNewAccount: Bool = false
}

struct AppleSignInRequest: Encodable {
    struct FullName: Encodable {
        var givenName: String?
        var familyName: String?
    }
    let identityToken: String
    let authorizationCode: String?
    let fullName: FullName?
}

struct PairingCode: Codable, Hashable {
    let code: String
    let expiresAt: Date
}

struct PairDeviceResponse: Decodable {
    struct DeviceRef: Decodable { let id: String }
    struct ElderlyRef: Decodable {
        let id: String
        let preferredName: String
        let noahName: String?
    }
    let deviceToken: String
    let device: DeviceRef
    let elderly: ElderlyRef
}

// MARK: - Me

struct ElderlySummary: Codable, Hashable, Identifiable {
    let id: String
    var preferredName: String
    var role: Role
    var access: Access
    var lastConversationAt: Date?
    var openAlertCount: Int?
}

struct MeResponse: Decodable {
    let caregiver: Caregiver
    @DefaultEmpty var elderly: [ElderlySummary] = []
}

// MARK: - Elderly profile

struct ElderlyProfile: Codable, Hashable, Identifiable {
    let id: String
    var firstName: String
    var lastName: String?
    var preferredName: String
    var addressForm: AddressForm
    var gender: Gender?
    var birthYear: Int?
    var phoneNumber: String?
    var city: String?
    var livingSituation: LivingSituation?
    var about: String?
    @DefaultEmpty var likes: [String] = []
    @DefaultEmpty var dislikes: [String] = []
    @DefaultEmpty var topicsToRaise: [String] = []
    @DefaultEmpty var topicsToAvoid: [String] = []
    var routines: String?
    var caregiverNotes: String?
    var access: Access
    @DefaultFalse var isBeta: Bool = false
    var myRole: Role?
    var createdAt: Date?

    var fullName: String {
        [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Writable fields of an elderly profile (`POST /elderly`, `PATCH /elderly/:id`).
/// Optional fields are sent as explicit `null` so a PATCH can clear them.
struct ElderlyProfileInput: Encodable, Equatable {
    var firstName = ""
    var lastName: String?
    var preferredName = ""
    var addressForm: AddressForm = .u
    var gender: Gender?
    var birthYear: Int?
    var phoneNumber = ""
    var city: String?
    var livingSituation: LivingSituation?
    var about: String?
    var likes: [String] = []
    var dislikes: [String] = []
    var topicsToRaise: [String] = []
    var topicsToAvoid: [String] = []
    var routines: String?
    var caregiverNotes: String?

    init() {}

    init(profile: ElderlyProfile) {
        firstName = profile.firstName
        lastName = profile.lastName
        preferredName = profile.preferredName
        addressForm = profile.addressForm == .unknown ? .u : profile.addressForm
        gender = profile.gender == .unknown ? nil : profile.gender
        birthYear = profile.birthYear
        phoneNumber = profile.phoneNumber ?? ""
        city = profile.city
        livingSituation = profile.livingSituation == .unknown ? nil : profile.livingSituation
        about = profile.about
        likes = profile.likes
        dislikes = profile.dislikes
        topicsToRaise = profile.topicsToRaise
        topicsToAvoid = profile.topicsToAvoid
        routines = profile.routines
        caregiverNotes = profile.caregiverNotes
    }

    enum CodingKeys: String, CodingKey {
        case firstName, lastName, preferredName, addressForm, gender, birthYear, phoneNumber, city,
             livingSituation, about, likes, dislikes, topicsToRaise, topicsToAvoid, routines, caregiverNotes
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(firstName, forKey: .firstName)
        try c.encode(lastName.nilIfBlank, forKey: .lastName)
        try c.encode(preferredName, forKey: .preferredName)
        try c.encode(addressForm, forKey: .addressForm)
        try c.encode(gender, forKey: .gender)
        try c.encode(birthYear, forKey: .birthYear)
        try c.encode(phoneNumber, forKey: .phoneNumber)
        try c.encode(city.nilIfBlank, forKey: .city)
        try c.encode(livingSituation, forKey: .livingSituation)
        try c.encode(about.nilIfBlank, forKey: .about)
        try c.encode(likes, forKey: .likes)
        try c.encode(dislikes, forKey: .dislikes)
        try c.encode(topicsToRaise, forKey: .topicsToRaise)
        try c.encode(topicsToAvoid, forKey: .topicsToAvoid)
        try c.encode(routines.nilIfBlank, forKey: .routines)
        try c.encode(caregiverNotes.nilIfBlank, forKey: .caregiverNotes)
    }
}

extension Optional where Wrapped == String {
    /// `nil` for nil, empty or whitespace-only strings.
    var nilIfBlank: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

// MARK: - People

struct Person: Codable, Hashable, Identifiable {
    let id: String
    var name: String
    var relation: String?
    var notes: String?
    /// `YYYY-MM-DD`
    var birthday: String?
    @DefaultFalse var isDeceased: Bool = false
    var createdBy: CreatedBy?
}

struct PersonInput: Encodable, Equatable {
    var name = ""
    var relation: String?
    var notes: String?
    var birthday: String?
    var isDeceased = false

    enum CodingKeys: String, CodingKey { case name, relation, notes, birthday, isDeceased }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(relation.nilIfBlank, forKey: .relation)
        try c.encode(notes.nilIfBlank, forKey: .notes)
        try c.encode(birthday, forKey: .birthday)
        try c.encode(isDeceased, forKey: .isDeceased)
    }
}

// MARK: - Noah settings

enum NoahVoice: String, TolerantEnum {
    case vrouw
    case man
    case unknown
    static var unknownCase: NoahVoice { .unknown }
}

struct NoahSettings: Codable, Hashable {
    struct MorningCall: Codable, Hashable {
        var enabled: Bool
        /// `HH:mm`, Europe/Amsterdam.
        var time: String
        /// ISO weekdays, 1 = Monday.
        @DefaultEmpty var weekdays: [Int] = []
    }

    struct QuietHours: Codable, Hashable {
        var start: String
        var end: String
    }

    var noahName: String
    var voice: NoahVoice
    var speakingSpeed: Double
    var maxConversationMinutes: Int
    var noContactAlertDays: Int
    var morningCall: MorningCall
    var quietHours: QuietHours

    static let speedRange: ClosedRange<Double> = 0.8...1.2
    static let minutesRange: ClosedRange<Int> = 5...30
    static let noContactRange: ClosedRange<Int> = 1...7

    static let defaults = NoahSettings(
        noahName: "Noah",
        voice: .vrouw,
        speakingSpeed: 1.0,
        maxConversationMinutes: 30,
        noContactAlertDays: 2,
        morningCall: MorningCall(enabled: false, time: "09:30", weekdays: [1, 2, 3, 4, 5, 6, 7]),
        quietHours: QuietHours(start: "21:30", end: "08:00")
    )
}

// MARK: - Emergency contacts

struct EmergencyContact: Codable, Hashable, Identifiable {
    let id: String
    var name: String
    var phoneNumber: String
    var relation: String?
    var priority: Int
    var notifyBySms: Bool
    var notifyByCall: Bool
}

struct EmergencyContactInput: Encodable, Equatable {
    var name = ""
    var phoneNumber = ""
    var relation: String?
    var notifyBySms = true
    var notifyByCall = true
}

// MARK: - Caregivers & invitations

struct CaregiverMembership: Codable, Hashable, Identifiable {
    let caregiverId: String
    var name: String?
    var role: Role
    var joinedAt: Date?
    @DefaultFalse var isMe: Bool = false

    var id: String { caregiverId }
}

struct Invitation: Codable, Hashable {
    let code: String
    let url: String?
    let expiresAt: Date?
    let shareText: String?
}

struct AcceptInvitationResponse: Decodable {
    struct ElderlyRef: Decodable {
        let id: String
        let preferredName: String
    }
    let elderly: ElderlyRef
    let role: Role
}

// MARK: - Devices

struct PairedDevice: Codable, Hashable, Identifiable {
    let id: String
    var deviceName: String?
    var platform: String?
    var pairedAt: Date?
    var lastSeenAt: Date?
}

// MARK: - Conversations

enum ConversationChannel: String, TolerantEnum {
    case app
    case telefoonIn = "telefoon_in"
    case telefoonUit = "telefoon_uit"
    case unknown
    static var unknownCase: ConversationChannel { .unknown }
}

struct ConversationSummary: Codable, Hashable, Identifiable {
    let id: String
    var startedAt: Date
    var durationSeconds: Int?
    var channel: ConversationChannel
    var summary: String?
    var moodScore: Double?
    @DefaultEmpty var topics: [String] = []
    @DefaultFalse var hasConcern: Bool = false
}

enum TranscriptRole: String, TolerantEnum {
    case noah
    case oudere
    case unknown
    static var unknownCase: TranscriptRole { .unknown }
}

struct TranscriptLine: Codable, Hashable {
    var role: TranscriptRole
    var text: String
    var atSeconds: Double?
}

struct ConversationDetail: Codable, Hashable, Identifiable {
    let id: String
    var startedAt: Date
    var durationSeconds: Int?
    var channel: ConversationChannel
    var summary: String?
    var moodScore: Double?
    @DefaultEmpty var topics: [String] = []
    @DefaultFalse var hasConcern: Bool = false
    @DefaultEmpty var moodIndicators: [String] = []
    @DefaultEmpty var concerningSignals: [String] = []
    var cognitiveClarity: Double?
    @DefaultEmpty var mentionedPeople: [String] = []
    @DefaultEmpty var mentionedPlaces: [String] = []
    @DefaultEmpty var mentionedDates: [String] = []
    @DefaultEmpty var emotionalMoments: [String] = []
    @DefaultEmpty var lifeStoryEntryIds: [String] = []
    @DefaultEmpty var transcript: [TranscriptLine] = []
}

// MARK: - Mood

struct MoodPoint: Codable, Hashable {
    /// `YYYY-MM-DD`
    var date: String
    var mood: Double?
    var conversations: Int?
    var cognitiveClarity: Double?
}

enum MoodTrend: String, TolerantEnum {
    case stabiel
    case stijgend
    case dalend
    case unknown
    static var unknownCase: MoodTrend { .unknown }
}

struct MoodOverview: Codable, Hashable {
    @DefaultEmpty var days: [MoodPoint] = []
    var average: Double?
    var trend: MoodTrend?
}

// MARK: - Life story

enum LifeStoryCategory: String, TolerantEnum {
    case jeugd
    case familie
    case werk
    case hobbys
    case reizen
    case belangrijkeMomenten = "belangrijke_momenten"
    case dagelijksLeven = "dagelijks_leven"
    case unknown
    static var unknownCase: LifeStoryCategory { .unknown }
}

struct LifeStoryEntry: Codable, Hashable, Identifiable {
    let id: String
    var category: LifeStoryCategory
    var title: String
    var content: String
    var year: Int?
    @DefaultEmpty var people: [String] = []
    @DefaultEmpty var places: [String] = []
    var quote: String?
    var conversationId: String?
    var createdBy: CreatedBy?
    var createdAt: Date?
}

struct LifeStoryInput: Encodable, Equatable {
    var category: LifeStoryCategory = .familie
    var title = ""
    var content = ""
    var year: Int?
    var people: [String] = []
    var places: [String] = []
    var quote: String?

    enum CodingKeys: String, CodingKey { case category, title, content, year, people, places, quote }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(category, forKey: .category)
        try c.encode(title, forKey: .title)
        try c.encode(content, forKey: .content)
        try c.encode(year, forKey: .year)
        try c.encode(people, forKey: .people)
        try c.encode(places, forKey: .places)
        try c.encode(quote.nilIfBlank, forKey: .quote)
    }
}

// MARK: - Reminders

enum ReminderType: String, TolerantEnum {
    case medicatie
    case afspraak
    case verjaardag
    case routine
    case overig
    case unknown
    static var unknownCase: ReminderType { .unknown }
}

enum ReminderDelivery: String, TolerantEnum {
    /// Noah calls at that time.
    case bellen
    /// Noah mentions it in the next conversation.
    case inGesprek = "in_gesprek"
    case unknown
    static var unknownCase: ReminderDelivery { .unknown }
}

/// `{ "kind": "eenmalig", "at" }` | `{ "kind": "dagelijks", "time" }` | `{ "kind": "wekelijks", "time", "weekdays" }`
enum ReminderSchedule: Codable, Hashable {
    case once(at: Date)
    case daily(time: String)
    case weekly(time: String, weekdays: [Int])
    case unknown(kind: String)

    enum Kind: String, CaseIterable {
        case eenmalig, dagelijks, wekelijks
    }

    private enum CodingKeys: String, CodingKey { case kind, at, time, weekdays }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case Kind.eenmalig.rawValue:
            self = .once(at: try c.decode(Date.self, forKey: .at))
        case Kind.dagelijks.rawValue:
            self = .daily(time: try c.decode(String.self, forKey: .time))
        case Kind.wekelijks.rawValue:
            self = .weekly(time: try c.decode(String.self, forKey: .time),
                           weekdays: try c.decodeIfPresent([Int].self, forKey: .weekdays) ?? [])
        default:
            self = .unknown(kind: kind)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .once(let at):
            try c.encode(Kind.eenmalig.rawValue, forKey: .kind)
            try c.encode(at, forKey: .at)
        case .daily(let time):
            try c.encode(Kind.dagelijks.rawValue, forKey: .kind)
            try c.encode(time, forKey: .time)
        case .weekly(let time, let weekdays):
            try c.encode(Kind.wekelijks.rawValue, forKey: .kind)
            try c.encode(time, forKey: .time)
            try c.encode(weekdays.sorted(), forKey: .weekdays)
        case .unknown(let kind):
            try c.encode(kind, forKey: .kind)
        }
    }

    var kind: Kind? {
        switch self {
        case .once: return .eenmalig
        case .daily: return .dagelijks
        case .weekly: return .wekelijks
        case .unknown: return nil
        }
    }
}

struct Reminder: Codable, Hashable, Identifiable {
    let id: String
    var title: String
    var notes: String?
    var type: ReminderType
    var schedule: ReminderSchedule
    var delivery: ReminderDelivery
    var active: Bool
    var createdBy: CreatedBy?
    var nextAt: Date?
    var lastCompletedAt: Date?
}

struct ReminderInput: Encodable, Equatable {
    var title = ""
    var notes: String?
    var type: ReminderType = .medicatie
    var schedule: ReminderSchedule = .daily(time: "08:00")
    var delivery: ReminderDelivery = .inGesprek
    var active = true

    enum CodingKeys: String, CodingKey { case title, notes, type, schedule, delivery, active }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(notes.nilIfBlank, forKey: .notes)
        try c.encode(type, forKey: .type)
        try c.encode(schedule, forKey: .schedule)
        try c.encode(delivery, forKey: .delivery)
        try c.encode(active, forKey: .active)
    }
}

// MARK: - Alerts

enum AlertType: String, TolerantEnum {
    case lageStemming = "lage_stemming"
    case stemmingsdaling
    case zorgelijkSignaal = "zorgelijk_signaal"
    case geenContact = "geen_contact"
    case hulpvraag
    case oplichting
    case verwardheid
    case noodgeval
    case unknown
    static var unknownCase: AlertType { .unknown }
}

enum AlertSeverity: String, TolerantEnum {
    case info
    case waarschuwing
    case urgent
    case nood
    case unknown
    static var unknownCase: AlertSeverity { .unknown }
}

enum AlertStatus: String, TolerantEnum {
    case open
    case gezien
    case afgehandeld
    case unknown
    static var unknownCase: AlertStatus { .unknown }
}

struct NoahAlert: Codable, Hashable, Identifiable {
    let id: String
    var type: AlertType
    var severity: AlertSeverity
    var title: String
    var body: String?
    var conversationId: String?
    var status: AlertStatus
    var createdAt: Date
    var acknowledgedBy: String?
}

// MARK: - Dashboard

struct Dashboard: Decodable {
    struct ElderlyRef: Decodable, Hashable {
        let id: String
        let preferredName: String
        let access: Access
    }

    struct Week: Decodable, Hashable {
        var conversations: Int
        var minutes: Int
        var averageMood: Double?
    }

    struct LifeStoryStats: Decodable, Hashable {
        var entries: Int
        var latest: LifeStoryEntry?
    }

    let elderly: ElderlyRef
    var lastConversationAt: Date?
    var week: Week
    @DefaultEmpty var moodTrend: [MoodPoint] = []
    var latestConversation: ConversationSummary?
    @DefaultEmpty var openAlerts: [NoahAlert] = []
    @DefaultEmpty var upcomingReminders: [Reminder] = []
    var lifeStory: LifeStoryStats
}

// MARK: - Calls, phone line, subscription

struct CallNowResponse: Decodable {
    let status: String
}

struct PhoneLine: Decodable, Hashable {
    let phoneNumber: String
    let displayNumber: String?
    let instructions: String?
}

enum SubscriptionStatus: String, TolerantEnum {
    case actief
    case intro
    case beta
    case verlopen
    case geen
    case unknown
    static var unknownCase: SubscriptionStatus { .unknown }

    /// Whether Noah is available (paid, in intro or free beta).
    var grantsAccess: Bool { self == .actief || self == .intro || self == .beta }
}

struct Subscription: Codable, Hashable {
    var status: SubscriptionStatus
    var productId: String?
    var renewsAt: Date?
    var expiresAt: Date?
    var platform: String?
    var paidByMe: Bool?
    /// Additive (backend changelog): free trial conversations left before a subscription is needed.
    var freeConversationsLeft: Int?

    /// Paid, in the intro period, or beta: no paywall needed.
    var isPaidOrBeta: Bool { status == .actief || status == .intro || status == .beta }
}

// MARK: - Device (older person's phone)

struct DeviceMe: Decodable {
    struct ElderlyRef: Decodable, Hashable {
        let id: String
        var preferredName: String
        var addressForm: AddressForm?
        var noahName: String?
    }
    var elderly: ElderlyRef
    var access: Access
    var lastConversationAt: Date?
    var nextReminder: Reminder?
}

/// `POST /device/conversation`: everything needed to start an ElevenLabs session.
struct ConversationSession: Decodable {
    struct Overrides: Decodable {
        struct Agent: Decodable {
            struct Prompt: Decodable { let prompt: String? }
            let prompt: Prompt?
            let firstMessage: String?
            let language: String?
        }
        struct TTS: Decodable {
            let voiceId: String?
            let speed: Double?
        }
        let agent: Agent?
        let tts: TTS?
    }

    let agentId: String?
    let conversationToken: String
    var dynamicVariables: [String: JSONValue]?
    let overrides: Overrides?
    let maxDurationSeconds: Int?
}

struct PushTokenRequest: Encodable {
    let token: String
    let platform: String
    let environment: String
}
