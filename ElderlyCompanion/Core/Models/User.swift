import Foundation

struct User: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let nickname: String?
    let birthYear: Int?
    let city: String?
    let phoneNumber: String
    let type: UserType
    let proactiveCallsEnabled: Bool
    let createdAt: Date?

    enum UserType: String, Codable, Sendable {
        case elderly
        case familyMember = "family_member"
    }
}

struct UserProfile: Codable, Sendable {
    var name: String = ""
    var nickname: String = ""
    var birthYear: Int?
    var city: String = ""
    var phoneNumber: String = ""
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
