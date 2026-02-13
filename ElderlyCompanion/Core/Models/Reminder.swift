import Foundation

struct Medication: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var time: Date
    var frequency: MedicationFrequency
    var notificationMethod: NotificationMethod
    var escalateIfIgnored: Bool

    enum MedicationFrequency: String, Codable, Sendable, CaseIterable {
        case daily
        case twiceDaily = "twice_daily"
        case weekly
        case asNeeded = "as_needed"

        var label: String {
            switch self {
            case .daily: return "Daily"
            case .twiceDaily: return "Twice daily"
            case .weekly: return "Weekly"
            case .asNeeded: return "As needed"
            }
        }
    }

    enum NotificationMethod: String, Codable, Sendable, CaseIterable {
        case call
        case push
        case sms

        var label: String {
            switch self {
            case .call: return "Phone call"
            case .push: return "Push notification"
            case .sms: return "SMS"
            }
        }

        var iconName: String {
            switch self {
            case .call: return "phone.fill"
            case .push: return "bell.fill"
            case .sms: return "message.fill"
            }
        }
    }
}

struct DailyCheckIn: Codable, Sendable {
    var enabled: Bool = true
    var time: Date = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    var format: CheckInFormat = .short
    var callIfNoActivity: Bool = true

    enum CheckInFormat: String, Codable, Sendable, CaseIterable {
        case short
        case long

        var label: String {
            switch self {
            case .short: return "Short check-in"
            case .long: return "Extended conversation"
            }
        }
    }
}

struct WeeklyRitual: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var dayOfWeek: Int // 1 = Sunday, 7 = Saturday
    var time: Date
    var enabled: Bool
}
