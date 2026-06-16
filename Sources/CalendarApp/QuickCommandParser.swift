import Foundation

struct QuickCommand {
    enum Action {
        case jump(Date)
        case create(CalendarEvent)
    }

    let action: Action
    let searchText: String
}

enum QuickCommandParser {
    static func parse(
        _ text: String,
        calendar: Calendar,
        selectedDate: Date,
        now: Date = Date()
    ) -> QuickCommand? {
        var working = cleanup(text)
        guard !working.isEmpty else { return nil }

        let today = calendar.startOfDay(for: now)
        let selectedDay = calendar.startOfDay(for: selectedDate)
        let parsedDate = extractDate(from: &working, calendar: calendar, today: today)
        let parsedTime = extractTime(from: &working)
        let durationMinutes = extractDurationMinutes(from: &working) ?? 60
        let title = cleanup(working)

        if let date = parsedDate, title.isEmpty {
            return QuickCommand(action: .jump(date), searchText: "")
        }

        guard !title.isEmpty, parsedDate != nil || parsedTime != nil else {
            return nil
        }

        let day = parsedDate ?? selectedDay
        if let parsedTime {
            guard let start = date(on: day, hour: parsedTime.hour, minute: parsedTime.minute, calendar: calendar),
                  let end = calendar.date(byAdding: .minute, value: durationMinutes, to: start) else {
                return nil
            }
            let event = CalendarEvent(
                title: title,
                date: calendar.startOfDay(for: start),
                startTime: start,
                endTime: end,
                colorIndex: 0
            )
            return QuickCommand(action: .create(event), searchText: title)
        }

        guard let end = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
        let event = CalendarEvent(
            title: title,
            date: day,
            startTime: day,
            endTime: end,
            colorIndex: 0,
            isAllDay: true
        )
        return QuickCommand(action: .create(event), searchText: title)
    }

    private static func extractDate(from text: inout String, calendar: Calendar, today: Date) -> Date? {
        for (word, offset) in [("大后天", 3), ("后天", 2), ("明天", 1), ("今天", 0), ("今日", 0), ("昨天", -1)] {
            if let range = text.range(of: word) {
                text.removeSubrange(range)
                return calendar.date(byAdding: .day, value: offset, to: today)
            }
        }

        if let match = firstMatch(#"下周([一二三四五六日天])"#, in: text),
           let value = match.group(1),
           let targetWeekday = weekdayNumber(for: value) {
            text.removeSubrange(match.range)
            let currentWeekday = calendar.component(.weekday, from: today)
            let delta = (targetWeekday - currentWeekday + 7) % 7
            return calendar.date(byAdding: .day, value: delta == 0 ? 7 : delta, to: today)
        }

        if let match = firstMatch(#"(?<!\d)(\d{4})年(\d{1,2})月(\d{1,2})(?:日|号)?"#, in: text),
           let year = match.int(1),
           let month = match.int(2),
           let day = match.int(3),
           let date = makeDate(year: year, month: month, day: day, calendar: calendar, today: today) {
            text.removeSubrange(match.range)
            return date
        }

        if let match = firstMatch(#"(?<!\d)(\d{4})[./-](\d{1,2})[./-](\d{1,2})(?!\d)"#, in: text),
           let year = match.int(1),
           let month = match.int(2),
           let day = match.int(3),
           let date = makeDate(year: year, month: month, day: day, calendar: calendar, today: today) {
            text.removeSubrange(match.range)
            return date
        }

        if let match = firstMatch(#"(?<!\d)(\d{1,2})月(\d{1,2})(?:日|号)?"#, in: text),
           let month = match.int(1),
           let day = match.int(2),
           let date = makeDate(year: nil, month: month, day: day, calendar: calendar, today: today) {
            text.removeSubrange(match.range)
            return date
        }

        if let match = firstMatch(#"(?<!\d)(\d{1,2})[./-](\d{1,2})(?!\d)"#, in: text),
           let month = match.int(1),
           let day = match.int(2),
           let date = makeDate(year: nil, month: month, day: day, calendar: calendar, today: today) {
            text.removeSubrange(match.range)
            return date
        }

        return nil
    }

    private static func extractTime(from text: inout String) -> (hour: Int, minute: Int)? {
        guard let match = firstMatch(
            #"(?:(上午|早上|下午|晚上|中午)\s*)?(\d{1,2})\s*(?:[:：点时時]\s*(\d{1,2})?\s*(?:分|分钟|分鐘)?)"#,
            in: text,
            options: [.caseInsensitive]
        ), var hour = match.int(2) else {
            return nil
        }

        let minute = match.int(3) ?? 0
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }

        if let period = match.group(1) {
            if (period == "下午" || period == "晚上"), hour < 12 {
                hour += 12
            } else if (period == "上午" || period == "早上"), hour == 12 {
                hour = 0
            } else if period == "中午", hour < 11 {
                hour += 12
            }
        }

        text.removeSubrange(match.range)
        return (hour, minute)
    }

    private static func extractDurationMinutes(from text: inout String) -> Int? {
        if let match = firstMatch(#"半\s*(?:小时|小時|h|hour)"#, in: text, options: [.caseInsensitive]) {
            text.removeSubrange(match.range)
            return 30
        }

        if let match = firstMatch(#"(\d+(?:\.\d+)?)\s*(?:小时|小時|h|hr|hrs|hour|hours)"#, in: text, options: [.caseInsensitive]),
           let value = match.double(1) {
            text.removeSubrange(match.range)
            return max(1, Int((value * 60).rounded()))
        }

        if let match = firstMatch(#"(\d+)\s*(?:分钟|分鐘|分|min|m)"#, in: text, options: [.caseInsensitive]),
           let value = match.int(1) {
            text.removeSubrange(match.range)
            return max(1, value)
        }

        return nil
    }

    private static func date(on day: Date, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    private static func makeDate(
        year: Int?,
        month: Int,
        day: Int,
        calendar: Calendar,
        today: Date
    ) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }

        var components = calendar.dateComponents([.year], from: today)
        if let year { components.year = year }
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        components.second = 0

        guard let date = calendar.date(from: components) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == components.year, check.month == month, check.day == day else { return nil }
        return calendar.startOfDay(for: date)
    }

    private static func weekdayNumber(for text: String) -> Int? {
        switch text {
        case "日", "天": return 1
        case "一": return 2
        case "二": return 3
        case "三": return 4
        case "四": return 5
        case "五": return 6
        case "六": return 7
        default: return nil
        }
    }

    private static func cleanup(_ text: String) -> String {
        text
            .replacingOccurrences(of: "，", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "；", with: " ")
            .replacingOccurrences(of: ";", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatch(
        _ pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> RegexMatch? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let swiftRange = Range(match.range, in: text) else {
            return nil
        }
        return RegexMatch(text: text, match: match, range: swiftRange)
    }
}

private struct RegexMatch {
    let text: String
    let match: NSTextCheckingResult
    let range: Range<String.Index>

    func group(_ index: Int) -> String? {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: text) else {
            return nil
        }
        return String(text[range])
    }

    func int(_ index: Int) -> Int? {
        group(index).flatMap(Int.init)
    }

    func double(_ index: Int) -> Double? {
        group(index).flatMap(Double.init)
    }
}
