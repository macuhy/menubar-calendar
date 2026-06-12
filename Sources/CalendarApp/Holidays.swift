import Foundation

/// 中国法定节假日与调休安排（内置数据）。
/// 数据来源：国务院办公厅通知
///  - 2025 年：国办发明电〔2024〕12号
///  - 2026 年：国办发明电〔2025〕7号
/// 新一年安排通常在前一年 11 月发布，届时在下方补充即可。
enum ChineseHolidays {
    enum DayMark {
        case rest(String)   // 休：法定放假（含调休连休），关联节日名
        case work           // 班：调休补班的周末
    }

    /// 按公历年月日查询休/班标记；非节假日且非补班日返回 nil。
    static func mark(year: Int, month: Int, day: Int) -> DayMark? {
        let key = year * 10000 + month * 100 + day
        if let name = restDays[key] { return .rest(name) }
        if workDays.contains(key) { return .work }
        return nil
    }

    // key 为 yyyyMMdd 形式的整数；同月内的连续假期用区间表示
    private static let restDays: [Int: String] = {
        var d: [Int: String] = [:]
        func add(_ name: String, _ keys: [Int]) { for k in keys { d[k] = name } }
        func add(_ name: String, _ range: ClosedRange<Int>) { add(name, Array(range)) }

        // 2025
        add("元旦", [20250101])
        add("春节", [20250128, 20250129, 20250130, 20250131,
                     20250201, 20250202, 20250203, 20250204])
        add("清明节", 20250404...20250406)
        add("劳动节", 20250501...20250505)
        add("端午节", [20250531, 20250601, 20250602])
        add("国庆节、中秋节", 20251001...20251008)

        // 2026
        add("元旦", 20260101...20260103)
        add("春节", 20260215...20260223)
        add("清明节", 20260404...20260406)
        add("劳动节", 20260501...20260505)
        add("端午节", 20260619...20260621)
        add("中秋节", 20260925...20260927)
        add("国庆节", 20261001...20261007)
        return d
    }()

    private static let workDays: Set<Int> = [
        // 2025
        20250126, 20250208,           // 春节
        20250427,                     // 劳动节
        20250928, 20251011,           // 国庆节、中秋节
        // 2026
        20260104,                     // 元旦
        20260214, 20260228,           // 春节
        20260509,                     // 劳动节
        20260920, 20261010,           // 国庆节
    ]
}
