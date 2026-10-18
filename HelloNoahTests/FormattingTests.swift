import XCTest
@testable import HelloNoah

final class FormattingTests: XCTestCase {
    /// Sunday 11 October 2026, 14:00 in Amsterdam (CEST, UTC+2).
    private let now = NoahJSON.parseDate("2026-10-11T12:00:00Z")!

    private func amsterdam(_ iso: String) -> Date { NoahJSON.parseDate(iso)! }

    // MARK: Relative dates

    func testRelativeDays() {
        XCTAssertEqual(DutchFormat.relativeDay(amsterdam("2026-10-11T07:00:00Z"), now: now), "vandaag")
        XCTAssertEqual(DutchFormat.relativeDay(amsterdam("2026-10-10T16:05:00Z"), now: now), "gisteren")
        XCTAssertEqual(DutchFormat.relativeDay(amsterdam("2026-10-09T10:00:00Z"), now: now), "eergisteren")
        XCTAssertEqual(DutchFormat.relativeDay(amsterdam("2026-10-07T10:00:00Z"), now: now), "4 dagen geleden")
        XCTAssertEqual(DutchFormat.relativeDay(amsterdam("2026-10-02T10:00:00Z"), now: now), "een week geleden")
        XCTAssertEqual(DutchFormat.relativeDay(amsterdam("2026-09-21T10:00:00Z"), now: now), "2 weken geleden")
        XCTAssertEqual(DutchFormat.relativeDay(amsterdam("2026-08-12T10:00:00Z"), now: now), "op 12 augustus")
        XCTAssertEqual(DutchFormat.relativeDay(amsterdam("2025-10-11T10:00:00Z"), now: now), "op 11 oktober 2025")
        XCTAssertEqual(DutchFormat.relativeDay(amsterdam("2026-10-12T10:00:00Z"), now: now), "morgen")
        XCTAssertEqual(DutchFormat.relativeDay(amsterdam("2026-10-13T10:00:00Z"), now: now), "overmorgen")
    }

    /// 00:30 in Amsterdam is still "today" even though it is the previous day in UTC.
    func testRelativeDayUsesAmsterdamTime() {
        XCTAssertEqual(DutchFormat.relativeDay(amsterdam("2026-10-10T22:30:00Z"), now: now), "vandaag")
        XCTAssertEqual(DutchFormat.relativeDay(amsterdam("2026-10-10T21:30:00Z"), now: now), "gisteren")
    }

    func testLastConversationLine() {
        XCTAssertEqual(DutchFormat.lastConversation(amsterdam("2026-10-10T16:05:00Z"), now: now), "Laatste gesprek: gisteren")
        XCTAssertEqual(DutchFormat.lastConversation(nil, now: now), "Nog geen gesprek gehad")
    }

    func testDayAndTimeAndUpcoming() {
        XCTAssertEqual(DutchFormat.dayAndTime(amsterdam("2026-10-10T16:05:00Z"), now: now), "gisteren om 18:05")
        XCTAssertEqual(DutchFormat.dayAndTime(amsterdam("2026-10-11T07:30:00Z"), now: now), "vandaag om 09:30")
        XCTAssertEqual(DutchFormat.upcoming(amsterdam("2026-10-11T13:30:00Z"), now: now), "Vandaag om 15:30")
        XCTAssertEqual(DutchFormat.upcoming(amsterdam("2026-10-12T06:00:00Z"), now: now), "Morgen om 08:00")
        XCTAssertEqual(DutchFormat.upcoming(amsterdam("2026-10-14T13:30:00Z"), now: now), "Woensdag 14 oktober om 15:30")
    }

    func testGreeting() {
        XCTAssertEqual(DutchFormat.greeting(now: amsterdam("2026-10-11T06:00:00Z")), "Goedemorgen")
        XCTAssertEqual(DutchFormat.greeting(now: now), "Goedemiddag")
        XCTAssertEqual(DutchFormat.greeting(now: amsterdam("2026-10-11T18:00:00Z")), "Goedenavond")
    }

    // MARK: Reminder schedules

    func testScheduleDescriptions() {
        XCTAssertEqual(ScheduleFormatter.describe(.once(at: amsterdam("2026-10-14T13:30:00Z"))), "Eenmalig op woensdag 14 oktober om 15:30")
        XCTAssertEqual(ScheduleFormatter.describe(.daily(time: "08:00")), "Elke dag om 08:00")
        XCTAssertEqual(ScheduleFormatter.describe(.weekly(time: "10:00", weekdays: [2, 4])), "Elke dinsdag en donderdag om 10:00")
        XCTAssertEqual(ScheduleFormatter.describe(.weekly(time: "10:00", weekdays: [5, 1, 3])), "Elke maandag, woensdag en vrijdag om 10:00")
        XCTAssertEqual(ScheduleFormatter.describe(.weekly(time: "09:00", weekdays: [1, 2, 3, 4, 5])), "Elke werkdag om 09:00")
        XCTAssertEqual(ScheduleFormatter.describe(.weekly(time: "11:00", weekdays: [6, 7])), "Elk weekend om 11:00")
        XCTAssertEqual(ScheduleFormatter.describe(.weekly(time: "07:45", weekdays: [1, 2, 3, 4, 5, 6, 7])), "Elke dag om 07:45")
        XCTAssertEqual(ScheduleFormatter.describe(.weekly(time: "19:30", weekdays: [3])), "Elke woensdag om 19:30")
        XCTAssertEqual(ScheduleFormatter.describe(.unknown(kind: "maandelijks")), "Op een vast moment")
    }

    func testNextOccurrence() {
        // Sunday 14:00 → daily 08:00 is tomorrow (Monday) 08:00 Amsterdam = 06:00Z.
        XCTAssertEqual(ReminderSchedule.daily(time: "08:00").nextOccurrence(after: now), amsterdam("2026-10-12T06:00:00Z"))
        XCTAssertEqual(ReminderSchedule.daily(time: "20:00").nextOccurrence(after: now), amsterdam("2026-10-11T18:00:00Z"))
        // Weekly on Tuesday and Thursday at 10:00 → Tuesday 13 October.
        XCTAssertEqual(ReminderSchedule.weekly(time: "10:00", weekdays: [2, 4]).nextOccurrence(after: now), amsterdam("2026-10-13T08:00:00Z"))
        // Weekly on Sunday at 10:00 (already passed today) → next Sunday.
        XCTAssertEqual(ReminderSchedule.weekly(time: "10:00", weekdays: [7]).nextOccurrence(after: now), amsterdam("2026-10-18T08:00:00Z"))
        XCTAssertNil(ReminderSchedule.weekly(time: "10:00", weekdays: []).nextOccurrence(after: now))
        XCTAssertEqual(ReminderSchedule.isoWeekday(of: now), 7)
    }

    // MARK: Numbers and phone numbers

    func testDurations() {
        XCTAssertEqual(DutchFormat.duration(seconds: 734), "12 min")
        XCTAssertEqual(DutchFormat.duration(seconds: 45), "1 min")
        XCTAssertEqual(DutchFormat.duration(seconds: 3600), "1 uur")
        XCTAssertEqual(DutchFormat.duration(seconds: 3900), "1 uur 5 min")
        XCTAssertEqual(DutchFormat.duration(seconds: nil), "–")
        XCTAssertEqual(DutchFormat.decimal(3.8), "3,8")
    }

    func testPhoneNumbers() {
        XCTAssertEqual(PhoneNumberFormat.e164("06 1234 5678"), "+31612345678")
        XCTAssertEqual(PhoneNumberFormat.e164("06-12345678"), "+31612345678")
        XCTAssertEqual(PhoneNumberFormat.e164("0031612345678"), "+31612345678")
        XCTAssertEqual(PhoneNumberFormat.e164("+31 6 12345678"), "+31612345678")
        XCTAssertEqual(PhoneNumberFormat.e164("023 123 4567"), "+31231234567")
        XCTAssertEqual(PhoneNumberFormat.e164("+32 470 12 34 56"), "+32470123456")
        XCTAssertNil(PhoneNumberFormat.e164("12345"))
        XCTAssertNil(PhoneNumberFormat.e164("06 1234"))
        // Only Dutch and Belgian numbers (security audit C2, backend v2.2).
        XCTAssertNil(PhoneNumberFormat.e164("+49 151 12345678"))
        XCTAssertNil(PhoneNumberFormat.e164("+1 415 555 0100"))
        XCTAssertEqual(PhoneNumberFormat.e164("+32 2 123 45 67"), "+3221234567")
        XCTAssertEqual(PhoneNumberFormat.e164("+31 06 12345678"), "+31612345678")
        XCTAssertNil(PhoneNumberFormat.e164("+31 6 1234567"))
        XCTAssertEqual(PhoneNumberFormat.display("+32470123456"), "+32 470 12 34 56")
        XCTAssertEqual(PhoneNumberFormat.display("+31612345678"), "06 12345678")
        XCTAssertEqual(PhoneNumberFormat.display("+31231234567"), "023 1234567")
    }

    func testLabels() {
        XCTAssertEqual(MoodText.label(4), "Goed")
        XCTAssertEqual(MoodText.label(1.2), "Somber")
        XCTAssertEqual(MoodText.label(nil), "Onbekend")
        XCTAssertEqual(DutchList.join(["Anna", "Mark", "Sara"]), "Anna, Mark en Sara")
        XCTAssertEqual(Weekdays.list([4, 2, 2]), "dinsdag en donderdag")
        XCTAssertEqual(LifeStoryCategory.belangrijkeMomenten.label, "Belangrijke momenten")
    }

    func testDecadeGrouping() {
        func entry(_ id: String, _ year: Int?) -> LifeStoryEntry {
            LifeStoryEntry(id: id, category: .familie, title: id, content: "", year: year, people: [], places: [], quote: nil, conversationId: nil, createdBy: .noah, createdAt: nil)
        }
        let groups = LifeStoryGrouping.byDecade([entry("a", 1962), entry("b", 1949), entry("c", nil), entry("d", 2003), entry("e", 2019), entry("f", 1968)])
        XCTAssertEqual(groups.map(\.title), ["De jaren 40", "De jaren 60", "Na 2000", "Zonder jaartal"])
        XCTAssertEqual(groups[1].entries.map(\.id), ["a", "f"])
        XCTAssertEqual(groups[2].entries.map(\.id), ["d", "e"])
    }
}
