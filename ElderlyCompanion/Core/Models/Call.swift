import Foundation

struct CallRecord: Codable, Identifiable, Sendable {
    let id: String
    let userId: String
    let direction: CallDirection
    let duration: TimeInterval
    let startedAt: Date
    let endedAt: Date?
    let tags: [CallTag]
    let summary: String?

    enum CallDirection: String, Codable, Sendable {
        case inbound
        case outbound
    }
}

enum CallTag: String, Codable, Sendable, CaseIterable {
    case companion
    case reminder
    case memoryCapture = "memory_capture"
    case concernDetected = "concern_detected"
    case escalation

    var label: String {
        switch self {
        case .companion: return "Companion"
        case .reminder: return "Reminder"
        case .memoryCapture: return "Memory"
        case .concernDetected: return "Concern"
        case .escalation: return "Escalation"
        }
    }

    var iconName: String {
        switch self {
        case .companion: return "heart.fill"
        case .reminder: return "bell.fill"
        case .memoryCapture: return "book.fill"
        case .concernDetected: return "exclamationmark.triangle.fill"
        case .escalation: return "phone.arrow.up.right.fill"
        }
    }
}
