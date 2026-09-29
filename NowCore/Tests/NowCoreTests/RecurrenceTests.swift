import Foundation
import Testing
@testable import NowCore

struct RecurrenceTests {
    func next(_ rule: Recurrence, due: Date, now: Date, calendar: Calendar = utc) -> Date {
        rule.nextDue(after: due, now: now, calendar: calendar)
    }

    @Test func labels() {
        #expect(Recurrence.allCases.map(\.label) == ["Every Day", "Every Weekday", "Every Week", "Every 2 Weeks", "Every Month", "Every Year"])
    }

    @Test func daily() {
        let due = date(2026, 9, 24, 8)
        #expect(next(.daily, due: due, now: date(2026, 9, 24, 7)) == date(2026, 9, 25, 8)) // early
        #expect(next(.daily, due: due, now: date(2026, 9, 24, 8)) == date(2026, 9, 25, 8)) // exactly on time
        #expect(next(.daily, due: due, now: date(2026, 9, 24, 23)) == date(2026, 9, 25, 8))
    }

    @Test func dailyOverdueSkipsMissedDays() {
        let due = date(2026, 9, 20, 8)
        #expect(next(.daily, due: due, now: date(2026, 9, 24, 7)) == date(2026, 9, 24, 8))
        #expect(next(.daily, due: due, now: date(2026, 9, 24, 10)) == date(2026, 9, 25, 8))
        #expect(next(.daily, due: date(2020, 1, 1, 8), now: now) == date(2026, 9, 25, 8))
    }

    @Test func weekly() {
        #expect(next(.weekly, due: date(2026, 9, 24, 8), now: date(2026, 9, 24, 9)) == date(2026, 10, 1, 8))
        #expect(next(.weekly, due: date(2026, 9, 3, 8), now: now) == date(2026, 10, 1, 8))
        #expect(next(.weekly, due: date(2026, 9, 3, 8), now: date(2026, 9, 24, 7)) == date(2026, 9, 24, 8))
    }

    @Test func biweekly() {
        #expect(next(.biweekly, due: date(2026, 9, 24, 8), now: date(2026, 9, 24, 9)) == date(2026, 10, 8, 8))
        #expect(next(.biweekly, due: date(2026, 9, 10, 8), now: now) == date(2026, 10, 8, 8))
        #expect(next(.biweekly, due: date(2026, 9, 17, 8), now: now) == date(2026, 10, 1, 8))
    }

    @Test func weekdays() {
        // Thu -> Fri.
        #expect(next(.weekdays, due: date(2026, 9, 24, 8), now: date(2026, 9, 24, 9)) == date(2026, 9, 25, 8))
        // Fri -> Mon.
        #expect(next(.weekdays, due: date(2026, 9, 25, 8), now: date(2026, 9, 25, 9)) == date(2026, 9, 28, 8))
        // Sat -> Mon, even when completed before it was due.
        #expect(next(.weekdays, due: date(2026, 9, 26, 8), now: date(2026, 9, 26, 7)) == date(2026, 9, 28, 8))
        // Sun -> Mon.
        #expect(next(.weekdays, due: date(2026, 9, 27, 8), now: date(2026, 9, 27, 9)) == date(2026, 9, 28, 8))
    }

    @Test func weekdaysOverdue() {
        let due = date(2026, 9, 14, 8) // Monday
        #expect(next(.weekdays, due: due, now: date(2026, 9, 24, 7)) == date(2026, 9, 24, 8))
        #expect(next(.weekdays, due: due, now: date(2026, 9, 25, 9)) == date(2026, 9, 28, 8))
        #expect(next(.weekdays, due: due, now: date(2026, 9, 26, 12)) == date(2026, 9, 28, 8))
    }

    @Test func monthlyAnchorsToMonthEnd() {
        let due = date(2026, 1, 31, 8)
        #expect(next(.monthly, due: due, now: date(2026, 1, 31, 9)) == date(2026, 2, 28, 8))
        #expect(next(.monthly, due: due, now: date(2026, 2, 28, 9)) == date(2026, 3, 31, 8))
        #expect(next(.monthly, due: due, now: date(2026, 4, 1)) == date(2026, 4, 30, 8))
        #expect(next(.monthly, due: due, now: now) == date(2026, 9, 30, 8))
        #expect(next(.monthly, due: date(2028, 1, 31, 8), now: date(2028, 1, 31, 9)) == date(2028, 2, 29, 8))
    }

    @Test func monthlyMidMonth() {
        #expect(next(.monthly, due: date(2026, 9, 15, 8), now: date(2026, 9, 15, 9)) == date(2026, 10, 15, 8))
        #expect(next(.monthly, due: date(2026, 1, 15, 8), now: now) == date(2026, 10, 15, 8))
    }

    @Test func yearlyLeapDay() {
        let due = date(2024, 2, 29, 8)
        #expect(next(.yearly, due: due, now: date(2024, 2, 29, 9)) == date(2025, 2, 28, 8))
        #expect(next(.yearly, due: due, now: date(2025, 3, 1)) == date(2026, 2, 28, 8))
        #expect(next(.yearly, due: due, now: date(2027, 3, 1)) == date(2028, 2, 29, 8))
    }

    @Test func yearly() {
        #expect(next(.yearly, due: date(2026, 9, 24, 8), now: date(2026, 9, 24, 9)) == date(2027, 9, 24, 8))
        #expect(next(.yearly, due: date(2020, 12, 25, 8), now: now) == date(2026, 12, 25, 8))
    }

    @Test(arguments: Recurrence.allCases)
    func alwaysAfterDueAndNowKeepingTimeOfDay(_ rule: Recurrence) {
        let due = date(2026, 1, 31, 8, 45)
        for offsetDays in [-3, 0, 1, 13, 30, 400, 3000] {
            let completed = due.addingTimeInterval(Double(offsetDays) * 86_400 + 3600)
            let result = next(rule, due: due, now: completed)
            #expect(result > due)
            #expect(result > completed)
            #expect(utc.dateComponents([.hour, .minute], from: result) == DateComponents(hour: 8, minute: 45))
        }
    }

    @Test func keepsLocalTimeAcrossDaylightSaving() {
        // Spring forward 2026-03-08.
        #expect(next(.daily, due: torontoDate(2026, 3, 7, 8), now: torontoDate(2026, 3, 7, 9), calendar: toronto) == torontoDate(2026, 3, 8, 8))
        #expect(next(.daily, due: torontoDate(2026, 3, 1, 8), now: torontoDate(2026, 3, 9, 9), calendar: toronto) == torontoDate(2026, 3, 10, 8))
        #expect(next(.weekdays, due: torontoDate(2026, 3, 6, 8), now: torontoDate(2026, 3, 6, 9), calendar: toronto) == torontoDate(2026, 3, 9, 8))
        // Fall back 2026-11-01.
        #expect(next(.daily, due: torontoDate(2026, 10, 31, 8), now: torontoDate(2026, 10, 31, 9), calendar: toronto) == torontoDate(2026, 11, 1, 8))
        #expect(next(.weekly, due: torontoDate(2026, 10, 29, 8), now: torontoDate(2026, 10, 29, 9), calendar: toronto) == torontoDate(2026, 11, 5, 8))
        #expect(next(.monthly, due: torontoDate(2026, 10, 15, 8), now: torontoDate(2026, 10, 15, 9), calendar: toronto) == torontoDate(2026, 11, 15, 8))
    }
}

/// A series completed occurrence by occurrence, the way the app spawns them.
struct RecurrenceSeriesTests {
    @Test func monthlyChainKeepsTheAnchorDay() {
        let anchor = date(2026, 1, 31, 9)
        let feb = Recurrence.monthly.nextOccurrence(currentDue: anchor, anchor: anchor, now: date(2026, 1, 31, 10), calendar: utc)
        #expect(feb == date(2026, 2, 28, 9))
        let mar = Recurrence.monthly.nextOccurrence(currentDue: feb, anchor: anchor, now: date(2026, 2, 28, 10), calendar: utc)
        #expect(mar == date(2026, 3, 31, 9))
        let apr = Recurrence.monthly.nextOccurrence(currentDue: mar, anchor: anchor, now: date(2026, 3, 31, 10), calendar: utc)
        #expect(apr == date(2026, 4, 30, 9))
    }

    @Test func yearlyLeapDayChain() {
        let anchor = date(2028, 2, 29, 9)
        let next = Recurrence.yearly.nextOccurrence(currentDue: anchor, anchor: anchor, now: date(2028, 2, 29, 10), calendar: utc)
        #expect(next == date(2029, 2, 28, 9))
        let later = Recurrence.yearly.nextOccurrence(currentDue: date(2031, 2, 28, 9), anchor: anchor, now: date(2031, 2, 28, 10), calendar: utc)
        #expect(later == date(2032, 2, 29, 9))
    }

    @Test func completingEarlyNeverRepeatsTheCurrentOccurrence() {
        let anchor = date(2026, 1, 31, 9)
        // Completing the Feb 28 occurrence on Feb 20 goes to March, not back to Feb 28.
        let next = Recurrence.monthly.nextOccurrence(currentDue: date(2026, 2, 28, 9), anchor: anchor, now: date(2026, 2, 20, 9), calendar: utc)
        #expect(next == date(2026, 3, 31, 9))
        let daily = Recurrence.daily.nextOccurrence(currentDue: date(2026, 9, 26, 8), anchor: nil, now: date(2026, 9, 24, 8), calendar: utc)
        #expect(daily == date(2026, 9, 27, 8))
    }

    @Test func keepsTheCurrentOccurrencesTimeOfDay() {
        // The anchor was at 09:00 but this occurrence was moved to 14:30; the next one follows the edit.
        let next = Recurrence.monthly.nextOccurrence(currentDue: date(2026, 2, 28, 14, 30), anchor: date(2026, 1, 31, 9), now: date(2026, 2, 28, 15), calendar: utc)
        #expect(next == date(2026, 3, 31, 14, 30))
    }

    @Test func withoutAnAnchorFallsBackToTheCurrentDue() {
        let next = Recurrence.monthly.nextOccurrence(currentDue: date(2026, 1, 15, 9), anchor: nil, now: date(2026, 1, 15, 10), calendar: utc)
        #expect(next == date(2026, 2, 15, 9))
    }
}

extension RecurrenceSeriesTests {
    @Test func occurrenceMovedEarlierThanTheAnchorTimeStillMovesOn() {
        // The anchor is 09:00, but this occurrence was moved to 08:00 and is completed at 08:00.
        let next = Recurrence.monthly.nextOccurrence(currentDue: date(2026, 2, 28, 8), anchor: date(2026, 1, 31, 9), now: date(2026, 2, 28, 8), calendar: utc)
        #expect(next == date(2026, 3, 31, 8))
    }
}

/// Custom cadences: every N days, weeks, months, or years, and weeks on chosen weekdays.
struct CustomRecurrenceTests {
    func next(_ rule: Recurrence, due: Date, now: Date) -> Date {
        rule.nextDue(after: due, now: now, calendar: utc)
    }

    @Test func everyThreeDays() {
        let rule = Recurrence(unit: .day, interval: 3)
        #expect(next(rule, due: date(2026, 9, 24, 8), now: date(2026, 9, 24, 9)) == date(2026, 9, 27, 8))
        // Overdue: skips missed occurrences but stays on the 3-day rhythm from the due date.
        #expect(next(rule, due: date(2026, 9, 1, 8), now: date(2026, 9, 24, 9)) == date(2026, 9, 25, 8))
    }

    @Test func everyTwoWeeksOnMondayAndWednesday() {
        // Weekdays: 2 = Monday, 4 = Wednesday. Due Monday 2026-09-21.
        let rule = Recurrence(unit: .week, interval: 2, weekdays: [2, 4])
        let due = date(2026, 9, 21, 8)
        #expect(next(rule, due: due, now: date(2026, 9, 21, 9)) == date(2026, 9, 23, 8)) // same week, Wednesday
        #expect(next(rule, due: date(2026, 9, 23, 8), now: date(2026, 9, 23, 9)) == date(2026, 10, 5, 8)) // skips a week
    }

    @Test func weeklyOnSeveralDays() {
        let rule = Recurrence(unit: .week, interval: 1, weekdays: [2, 4, 6]) // Mon, Wed, Fri
        #expect(next(rule, due: date(2026, 9, 25, 8), now: date(2026, 9, 25, 9)) == date(2026, 9, 28, 8)) // Fri -> Mon
    }

    @Test func everyThreeMonthsKeepsTheDay() {
        let rule = Recurrence(unit: .month, interval: 3)
        #expect(next(rule, due: date(2026, 1, 31, 8), now: date(2026, 1, 31, 9)) == date(2026, 4, 30, 8))
        #expect(next(rule, due: date(2026, 1, 31, 8), now: date(2026, 5, 1)) == date(2026, 7, 31, 8))
    }

    @Test func everyTwoYears() {
        let rule = Recurrence(unit: .year, interval: 2)
        #expect(next(rule, due: date(2026, 9, 24, 8), now: date(2026, 9, 24, 9)) == date(2028, 9, 24, 8))
    }

    @Test func presetsKeepTheirStoredNames() {
        #expect(Recurrence.daily.rawValue == "daily")
        #expect(Recurrence.weekdays.rawValue == "weekdays")
        #expect(Recurrence.biweekly.rawValue == "biweekly")
        #expect(Recurrence(rawValue: "monthly") == .monthly)
        #expect(Recurrence(unit: .week, interval: 2) == .biweekly)
    }

    @Test func customRulesRoundTrip() {
        for rule in [Recurrence(unit: .day, interval: 3), Recurrence(unit: .week, interval: 2, weekdays: [2, 4]), Recurrence(unit: .year, interval: 5)] {
            #expect(Recurrence(rawValue: rule.rawValue) == rule)
        }
        #expect(Recurrence(rawValue: "nonsense") == nil)
        #expect(Recurrence(rawValue: "every:0:day") == nil)
    }

    @Test func labels() {
        #expect(Recurrence(unit: .day, interval: 3).label == "Every 3 Days")
        #expect(Recurrence(unit: .week, interval: 2, weekdays: [2, 4]).label == "Every 2 Weeks on Mon, Wed")
        #expect(Recurrence(unit: .week, interval: 1, weekdays: [2, 4, 6]).label == "Every Week on Mon, Wed, Fri")
        #expect(Recurrence(unit: .month, interval: 6).label == "Every 6 Months")
        #expect(Recurrence.weekdays.label == "Every Weekday")
    }
}
