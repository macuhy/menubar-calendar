import XCTest
@testable import CalendarApp

final class EventEditorDefaultsTests: XCTestCase {
    func testDefaultCreateRangeUsesProvidedCalendarTimeZone() {
        var displayCalendar = Calendar(identifier: .gregorian)
        displayCalendar.locale = Locale(identifier: "zh_CN")
        displayCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        displayCalendar.firstWeekday = 2

        var systemLikeCalendar = Calendar(identifier: .gregorian)
        systemLikeCalendar.locale = Locale(identifier: "zh_CN")
        systemLikeCalendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        systemLikeCalendar.firstWeekday = 2

        let selectedDate = displayCalendar.date(from: DateComponents(year: 2026, month: 6, day: 30))!

        let corrected = EventEditorDefaults.defaultRange(for: selectedDate, calendar: displayCalendar)
        XCTAssertEqual(
            components([.year, .month, .day, .hour, .minute], from: corrected.start, calendar: displayCalendar),
            [2026, 6, 30, 9, 0]
        )
        XCTAssertEqual(
            components([.year, .month, .day, .hour, .minute], from: corrected.end, calendar: displayCalendar),
            [2026, 6, 30, 10, 0]
        )

        let previousBehavior = EventEditorDefaults.defaultRange(for: selectedDate, calendar: systemLikeCalendar)
        XCTAssertEqual(
            components([.year, .month, .day, .hour, .minute], from: previousBehavior.start, calendar: displayCalendar),
            [2026, 6, 29, 15, 0]
        )
    }

    private func components(_ fields: Set<Calendar.Component>, from date: Date, calendar: Calendar) -> [Int] {
        let values = calendar.dateComponents(fields, from: date)
        let orderedFields: [Calendar.Component] = [.year, .month, .day, .hour, .minute]
        return orderedFields.compactMap { field in
            guard fields.contains(field) else { return nil }
            return values.value(for: field)
        }
    }
}
