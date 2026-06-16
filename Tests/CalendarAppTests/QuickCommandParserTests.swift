import XCTest
@testable import CalendarApp

final class QuickCommandParserTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "zh_CN")
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        cal.firstWeekday = 2
        return cal
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 9))!
    }

    func testParsesRelativeTimedCreateCommand() {
        let command = QuickCommandParser.parse(
            "明天 10 点 产品会 1h",
            calendar: calendar,
            selectedDate: now,
            now: now
        )

        guard case .create(let event)? = command?.action else {
            return XCTFail("应解析为创建事件")
        }

        XCTAssertEqual(event.title, "产品会")
        XCTAssertFalse(event.isAllDay)
        XCTAssertEqual(components([.year, .month, .day, .hour, .minute], from: event.startTime), [2026, 6, 16, 10, 0])
        XCTAssertEqual(components([.year, .month, .day, .hour, .minute], from: event.endTime), [2026, 6, 16, 11, 0])
    }

    func testParsesSlashDateTimedCreateCommand() {
        let command = QuickCommandParser.parse(
            "6/20 14:00 电话",
            calendar: calendar,
            selectedDate: now,
            now: now
        )

        guard case .create(let event)? = command?.action else {
            return XCTFail("应解析为创建事件")
        }

        XCTAssertEqual(event.title, "电话")
        XCTAssertEqual(components([.year, .month, .day, .hour, .minute], from: event.startTime), [2026, 6, 20, 14, 0])
        XCTAssertEqual(components([.year, .month, .day, .hour, .minute], from: event.endTime), [2026, 6, 20, 15, 0])
    }

    func testParsesChineseMinuteTimeCommand() {
        let command = QuickCommandParser.parse(
            "明天 10点30分 产品会 30分钟",
            calendar: calendar,
            selectedDate: now,
            now: now
        )

        guard case .create(let event)? = command?.action else {
            return XCTFail("应解析为创建事件")
        }

        XCTAssertEqual(event.title, "产品会")
        XCTAssertEqual(components([.year, .month, .day, .hour, .minute], from: event.startTime), [2026, 6, 16, 10, 30])
        XCTAssertEqual(components([.year, .month, .day, .hour, .minute], from: event.endTime), [2026, 6, 16, 11, 0])
    }

    func testParsesDateOnlyAsJumpCommand() {
        let command = QuickCommandParser.parse(
            "后天",
            calendar: calendar,
            selectedDate: now,
            now: now
        )

        guard case .jump(let date)? = command?.action else {
            return XCTFail("应解析为跳转日期")
        }

        XCTAssertEqual(components([.year, .month, .day], from: date), [2026, 6, 17])
    }

    func testPlainSearchTextDoesNotCreateCommand() {
        let command = QuickCommandParser.parse(
            "产品会",
            calendar: calendar,
            selectedDate: now,
            now: now
        )

        XCTAssertNil(command)
    }

    private func components(_ fields: Set<Calendar.Component>, from date: Date) -> [Int] {
        let values = calendar.dateComponents(fields, from: date)
        let orderedFields: [Calendar.Component] = [.year, .month, .day, .hour, .minute]
        return orderedFields.compactMap { field in
            guard fields.contains(field) else { return nil }
            return values.value(for: field)
        }
    }
}
