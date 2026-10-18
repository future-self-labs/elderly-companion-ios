import Foundation

/// Dutch date/time formatting. All times are shown in Europe/Amsterdam, which is also the zone
/// of the contract's local `HH:mm` times. `now` is injectable for tests.
enum DutchFormat {
    static let timeZone = TimeZone(identifier: "Europe/Amsterdam")!
    static let locale = Locale(identifier: "nl_NL")

    static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        calendar.firstWeekday = 2
        return calendar
    }()

    private static func formatter(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayMonth = formatter("d MMMM")
    private static let dayMonthYear = formatter("d MMMM y")
    private static let weekdayDayMonth = formatter("EEEE d MMMM")
    private static let shortWeekdayDayMonth = formatter("EEE d MMM")
    private static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Number of calendar days from `date` to `now` (positive = in the past).
    static func dayDistance(from date: Date, to now: Date) -> Int {
        let start = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    /// "vandaag", "gisteren", "eergisteren", "3 dagen geleden", "een week geleden", "op 2 oktober".
    static func relativeDay(_ date: Date, now: Date = Date()) -> String {
        let days = dayDistance(from: date, to: now)
        switch days {
        case 0: return "vandaag"
        case 1: return "gisteren"
        case 2: return "eergisteren"
        case 3...6: return "\(days) dagen geleden"
        case 7...13: return "een week geleden"
        case 14...27: return "\(days / 7) weken geleden"
        case -1: return "morgen"
        case -2: return "overmorgen"
        case -6 ... -3: return "over \(-days) dagen"
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            return "op " + (sameYear ? dayMonth : dayMonthYear).string(from: date)
        }
    }

    /// "Laatste gesprek: gisteren" or "Nog geen gesprek".
    static func lastConversation(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Nog geen gesprek gehad" }
        return "Laatste gesprek: \(relativeDay(date, now: now))"
    }

    /// "vandaag om 14:05", "gisteren om 18:05", "za 4 okt. om 10:00".
    static func dayAndTime(_ date: Date, now: Date = Date()) -> String {
        let days = dayDistance(from: date, to: now)
        let time = timeFormatter.string(from: date)
        switch days {
        case 0: return "vandaag om \(time)"
        case 1: return "gisteren om \(time)"
        case -1: return "morgen om \(time)"
        default: return "\(shortWeekdayDayMonth.string(from: date)) om \(time)"
        }
    }

    /// Next occurrence of a reminder: "Vandaag om 13:30", "Morgen om 08:00", "Dinsdag 14 oktober om 15:30".
    static func upcoming(_ date: Date, now: Date = Date()) -> String {
        let days = dayDistance(from: date, to: now)
        let time = timeFormatter.string(from: date)
        switch days {
        case 0: return "Vandaag om \(time)"
        case -1: return "Morgen om \(time)"
        case -2: return "Overmorgen om \(time)"
        default: return weekdayDayMonth.string(from: date).capitalizedFirst + " om \(time)"
        }
    }

    /// "zaterdag 11 oktober" (for headers).
    static func longDay(_ date: Date) -> String {
        weekdayDayMonth.string(from: date)
    }

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// "12 sep" (chart axes).
    static func dayMonthShort(_ date: Date) -> String {
        let day = calendar.component(.day, from: date)
        let month = ["jan", "feb", "mrt", "apr", "mei", "jun", "jul", "aug", "sep", "okt", "nov", "dec"][calendar.component(.month, from: date) - 1]
        return "\(day) \(month)"
    }

    static func shortDate(_ date: Date) -> String {
        dayMonthYear.string(from: date)
    }

    /// Parses a contract day (`YYYY-MM-DD`) as midnight in Amsterdam.
    static func day(from string: String) -> Date? {
        isoDay.date(from: string)
    }

    static func dayString(_ date: Date) -> String {
        isoDay.string(from: date)
    }

    /// "ma", "di"… for chart axes.
    static func shortWeekday(_ date: Date) -> String {
        let index = calendar.component(.weekday, from: date) // 1 = Sunday
        return ["zo", "ma", "di", "wo", "do", "vr", "za"][index - 1]
    }

    /// Greeting for the time of day.
    static func greeting(now: Date = Date()) -> String {
        let hour = calendar.component(.hour, from: now)
        switch hour {
        case 5..<12: return "Goedemorgen"
        case 12..<18: return "Goedemiddag"
        case 18..<24: return "Goedenavond"
        default: return "Goedenacht"
        }
    }

    // MARK: Durations & numbers

    /// 734 → "12 min", 45 → "1 min", 3900 → "1 uur 5 min".
    static func duration(seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "–" }
        let minutes = max(1, Int((Double(seconds) / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) uur" : "\(hours) uur \(rest) min"
    }

    /// 3.8 → "3,8"
    /// 600 → "10 uur", 90 → "1,5 uur", 45 → "45 minuten".
    static func hours(minutes: Int) -> String {
        if minutes < 60 { return minutes == 1 ? "1 minuut" : "\(minutes) minuten" }
        let hours = Double(minutes) / 60
        return "\(decimal(hours, digits: hours.rounded() == hours ? 0 : 1)) uur"
    }

    static func decimal(_ value: Double, digits: Int = 1) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    // MARK: Local times (HH:mm)

    static func date(fromTime time: String, on day: Date = Date()) -> Date {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = parts.first ?? 0
        components.minute = parts.count > 1 ? parts[1] : 0
        return calendar.date(from: components) ?? day
    }

    static func timeString(from date: Date) -> String {
        timeFormatter.string(from: date)
    }
}

// MARK: - Weekdays & schedules

enum Weekdays {
    /// ISO weekday (1 = Monday) → Dutch name.
    static let names = [1: "maandag", 2: "dinsdag", 3: "woensdag", 4: "donderdag", 5: "vrijdag", 6: "zaterdag", 7: "zondag"]
    static let shortNames = [1: "ma", 2: "di", 3: "wo", 4: "do", 5: "vr", 6: "za", 7: "zo"]

    /// [2, 4] → "dinsdag en donderdag"; [1, 3, 5] → "maandag, woensdag en vrijdag".
    static func list(_ weekdays: [Int]) -> String {
        let names = Array(Set(weekdays)).sorted().compactMap { Self.names[$0] }
        return DutchList.join(names)
    }
}

enum DutchList {
    /// ["a"] → "a", ["a","b"] → "a en b", ["a","b","c"] → "a, b en c".
    static func join(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " en " + items.last!
        }
    }
}

enum ScheduleFormatter {
    /// "Eenmalig op dinsdag 14 oktober om 15:30", "Elke dag om 08:00",
    /// "Elke dinsdag en donderdag om 10:00", "Elke werkdag om 09:00", "Elk weekend om 11:00".
    static func describe(_ schedule: ReminderSchedule) -> String {
        switch schedule {
        case .once(let at):
            return "Eenmalig op \(DutchFormat.longDay(at)) om \(DutchFormat.time(at))"
        case .daily(let time):
            return "Elke dag om \(time)"
        case .weekly(let time, let weekdays):
            let set = Set(weekdays)
            if set.isEmpty { return "Wekelijks om \(time)" }
            if set == Set(1...7) { return "Elke dag om \(time)" }
            if set == Set(1...5) { return "Elke werkdag om \(time)" }
            if set == Set([6, 7]) { return "Elk weekend om \(time)" }
            return "Elke \(Weekdays.list(weekdays)) om \(time)"
        case .unknown:
            return "Op een vast moment"
        }
    }
}

// MARK: - Phone numbers

enum PhoneNumberFormat {
    /// Shown whenever a number is not accepted. HelloNoah only calls and texts Dutch (+31) and
    /// Belgian (+32) numbers.
    static let invalidMessage = "Vul een Nederlands of Belgisch telefoonnummer in, bijvoorbeeld 06 12345678. Een Belgisch nummer begint met +32."

    /// Normalises Dutch input to E.164: "06 1234 5678" → "+31612345678", "0031 6…" → "+316…",
    /// "+32 470 12 34 56" → "+32470123456". Returns nil unless it is a plausible Dutch (+31, 9
    /// digits after the country code) or Belgian (+32, 8 or 9 digits) number.
    static func e164(_ input: String) -> String? {
        var digits = input.filter { $0.isNumber || $0 == "+" }
        if digits.hasPrefix("00") { digits = "+" + digits.dropFirst(2) }
        if digits.hasPrefix("0") { digits = "+31" + digits.dropFirst() }
        if !digits.hasPrefix("+") { digits = "+31" + digits }
        let body = digits.dropFirst()
        guard body.allSatisfy(\.isNumber) else { return nil }
        if digits.hasPrefix("+31") {
            // "+31 06…" typed with the trunk zero.
            if digits.hasPrefix("+310") { digits = "+31" + digits.dropFirst(4) }
            return digits.count == 12 ? digits : nil
        }
        if digits.hasPrefix("+32") {
            if digits.hasPrefix("+320") { digits = "+32" + digits.dropFirst(4) }
            return (11...12).contains(digits.count) ? digits : nil
        }
        return nil
    }

    /// "+31612345678" → "06 12345678", "+32470123456" → "+32 470 12 34 56".
    static func display(_ e164: String?) -> String {
        guard let e164, !e164.isEmpty else { return "" }
        if e164.hasPrefix("+316"), e164.count == 12 {
            return "06 " + e164.dropFirst(4)
        }
        if e164.hasPrefix("+31"), e164.count == 12 {
            let national = "0" + e164.dropFirst(3)
            return String(national.prefix(3)) + " " + String(national.dropFirst(3))
        }
        if e164.hasPrefix("+324"), e164.count == 12 {
            let n = Array(e164.dropFirst(3))
            return "+32 \(String(n[0..<3])) \(String(n[3..<5])) \(String(n[5..<7])) \(String(n[7..<9]))"
        }
        return e164
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
