import Foundation

struct User: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let nickname: String?
    let birthYear: Int?
    let city: String?
    let phoneNumber: String
    let type: UserType
    let language: String?
    let proactiveCallsEnabled: Bool
    let createdAt: Date?

    enum UserType: String, Codable, Sendable {
        case elderly
        case familyMember = "family_member"
    }
}

struct NoahLanguage: Identifiable {
    let id: String   // ISO code
    let name: String
    let flag: String
    let nativeName: String

    static let available: [NoahLanguage] = [
        NoahLanguage(id: "nl", name: "Dutch", flag: "🇳🇱", nativeName: "Nederlands"),
        NoahLanguage(id: "en", name: "English", flag: "🇬🇧", nativeName: "English"),
        NoahLanguage(id: "de", name: "German", flag: "🇩🇪", nativeName: "Deutsch"),
        NoahLanguage(id: "fr", name: "French", flag: "🇫🇷", nativeName: "Français"),
        NoahLanguage(id: "es", name: "Spanish", flag: "🇪🇸", nativeName: "Español"),
        NoahLanguage(id: "tr", name: "Turkish", flag: "🇹🇷", nativeName: "Türkçe"),
    ]
}

struct UserProfile: Codable, Sendable {
    var name: String = ""
    var nickname: String = ""
    var birthYear: Int?
    var city: String = ""
    var phoneNumber: String = ""
    var language: String = "nl"
    var proactiveCallsEnabled: Bool = true
    var calendarAccess: CalendarAccessLevel = .none
    var notificationPreferences: NotificationPreferences = .init()
    var legacyPreferences: LegacyPreferences = .init()
}

enum CalendarAccessLevel: String, Codable, Sendable {
    case full
    case readOnly
    case none
}

struct NotificationPreferences: Codable, Sendable {
    var callEnabled: Bool = true
    var pushEnabled: Bool = true
    var smsEnabled: Bool = true
    var quietHoursStart: Int = 22 // 10 PM
    var quietHoursEnd: Int = 8   // 8 AM
}

struct LegacyPreferences: Codable, Sendable {
    var lifeStoryCaptureEnabled: Bool = true
    var audioStorageEnabled: Bool = true
    var familySharingEnabled: Bool = false
}
