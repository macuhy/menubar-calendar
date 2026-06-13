import XCTest
@testable import CalendarApp

final class HolidaysTests: XCTestCase {

    // 已知的「休」日：2025-05-01 劳动节、2026-02-15 春节
    func testKnownRestDay() {
        guard case .rest(let name)? = ChineseHolidays.mark(year: 2025, month: 5, day: 1) else {
            return XCTFail("2025-05-01 应为休（劳动节）")
        }
        XCTAssertEqual(name, "劳动节")

        guard case .rest(let springName)? = ChineseHolidays.mark(year: 2026, month: 2, day: 15) else {
            return XCTFail("2026-02-15 应为休（春节）")
        }
        XCTAssertEqual(springName, "春节")
    }

    // 已知的「班」日（调休补班的周末）：2025-04-27 劳动节、2026-02-28 春节
    func testKnownWorkDay() {
        guard case .work? = ChineseHolidays.mark(year: 2025, month: 4, day: 27) else {
            return XCTFail("2025-04-27 应为班（劳动节调休补班）")
        }
        guard case .work? = ChineseHolidays.mark(year: 2026, month: 2, day: 28) else {
            return XCTFail("2026-02-28 应为班（春节调休补班）")
        }
    }

    // 普通工作日（非休非班）应返回 nil：2025-05-06、2026-03-16
    func testOrdinaryWeekdayReturnsNil() {
        XCTAssertNil(ChineseHolidays.mark(year: 2025, month: 5, day: 6))
        XCTAssertNil(ChineseHolidays.mark(year: 2026, month: 3, day: 16))
    }

    func testHasHolidayData() {
        XCTAssertTrue(ChineseHolidays.hasHolidayData(for: 2025))
        XCTAssertTrue(ChineseHolidays.hasHolidayData(for: 2026))
        XCTAssertFalse(ChineseHolidays.hasHolidayData(for: 2024))
        XCTAssertFalse(ChineseHolidays.hasHolidayData(for: 2027))
    }

    func testLatestDataYear() {
        XCTAssertEqual(ChineseHolidays.latestDataYear, 2026)
    }
}
