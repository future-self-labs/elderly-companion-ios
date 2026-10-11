import Foundation

extension ReminderSchedule {
    /// The next moment this schedule fires after `now` (Europe/Amsterdam local times).
    func nextOccurrence(after now: Date = Date(), calendar: Calendar = DutchFormat.calendar) -> Date? {
        switch self {
        case .once(let at):
            return at
        case .daily(let time):
            for offset in 0...1 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
                let candidate = DutchFormat.date(fromTime: time, on: day)
                if candidate > now { return candidate }
            }
            return nil
        case .weekly(let time, let weekdays):
            guard !weekdays.isEmpty else { return nil }
            for offset in 0...7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
                guard weekdays.contains(Self.isoWeekday(of: day, calendar: calendar)) else { continue }
                let candidate = DutchFormat.date(fromTime: time, on: day)
                if candidate > now { return candidate }
            }
            return nil
        case .unknown:
            return nil
        }
    }

    /// ISO weekday (1 = Monday … 7 = Sunday).
    static func isoWeekday(of date: Date, calendar: Calendar = DutchFormat.calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date) // 1 = Sunday
        return weekday == 1 ? 7 : weekday - 1
    }
}
