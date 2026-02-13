import Foundation

struct MemoryEntry: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let date: Date
    let duration: TimeInterval?
    let tags: [MemoryTag]
    let transcript: String?
    let audioURL: URL?
    let isHighlighted: Bool
    let isSharedWithFamily: Bool
}

enum MemoryTag: String, Codable, Sendable, CaseIterable {
    case childhood
    case career
    case love
    case family
    case travel
    case wisdom
    case daily
    case health

    var label: String {
        switch self {
        case .childhood: return "Childhood"
        case .career: return "Career"
        case .love: return "Love"
        case .family: return "Family"
        case .travel: return "Travel"
        case .wisdom: return "Wisdom"
        case .daily: return "Daily Life"
        case .health: return "Health"
        }
    }

    var iconName: String {
        switch self {
        case .childhood: return "figure.child"
        case .career: return "briefcase.fill"
        case .love: return "heart.fill"
        case .family: return "person.3.fill"
        case .travel: return "airplane"
        case .wisdom: return "lightbulb.fill"
        case .daily: return "sun.max.fill"
        case .health: return "cross.case.fill"
        }
    }
}
