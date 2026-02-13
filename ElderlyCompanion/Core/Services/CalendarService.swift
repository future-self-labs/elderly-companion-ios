import EventKit
import Foundation

@Observable
final class CalendarService {
    private let store = EKEventStore()
    private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    private(set) var events: [EKEvent] = []

    init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    /// Request full calendar access
    func requestFullAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            await MainActor.run {
                authorizationStatus = granted ? .fullAccess : .denied
            }
            return granted
        } catch {
            await MainActor.run {
                authorizationStatus = .denied
            }
            return false
        }
    }

    /// Fetch events for a date range
    func fetchEvents(from startDate: Date, to endDate: Date) {
        guard authorizationStatus == .fullAccess else { return }

        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let fetched = store.events(matching: predicate)
        events = fetched.sorted { $0.startDate < $1.startDate }
    }

    /// Fetch events for today
    func fetchTodayEvents() {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        fetchEvents(from: start, to: end)
    }

    /// Fetch events for current month
    func fetchCurrentMonthEvents() {
        let calendar = Calendar.current
        let now = Date()
        guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let end = calendar.date(byAdding: .month, value: 1, to: start) else { return }
        fetchEvents(from: start, to: end)
    }

    /// Add a new event
    func addEvent(title: String, startDate: Date, endDate: Date, notes: String? = nil) throws {
        guard authorizationStatus == .fullAccess else {
            throw CalendarError.notAuthorized
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = notes
        event.calendar = store.defaultCalendarForNewEvents

        try store.save(event, span: .thisEvent)
        fetchTodayEvents()
    }

    /// Get the next upcoming event
    var nextEvent: EKEvent? {
        let now = Date()
        return events.first { $0.startDate > now }
    }

    enum CalendarError: LocalizedError {
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Calendar access is not authorized"
            }
        }
    }
}
