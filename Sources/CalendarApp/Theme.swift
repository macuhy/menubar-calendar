import SwiftUI

enum Theme {
    // Accent (red like Apple Calendar's "today" highlight)
    static let accent = Color(red: 0.95, green: 0.26, blue: 0.21)

    // Event colors users can pick
    static let eventColors: [Color] = [
        Color(red: 0.20, green: 0.48, blue: 0.97), // blue
        Color(red: 0.95, green: 0.26, blue: 0.21), // red
        Color(red: 0.99, green: 0.62, blue: 0.04), // orange
        Color(red: 0.20, green: 0.70, blue: 0.32), // green
        Color(red: 0.58, green: 0.35, blue: 0.92), // purple
        Color(red: 0.00, green: 0.65, blue: 0.71), // teal
    ]

    static let eventColorNames = ["蓝色", "红色", "橙色", "绿色", "紫色", "青色"]

    static func eventColor(_ index: Int) -> Color {
        eventColors[((index % eventColors.count) + eventColors.count) % eventColors.count]
    }

    static let background = Color(nsColor: .windowBackgroundColor)
    static let cellBorder = Color(nsColor: .separatorColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)

    static let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]

    // 节假日角标：休（绿）/ 班（橙）
    static let restBadge = Color(red: 0.20, green: 0.70, blue: 0.32)
    static let workBadge = Color(red: 0.99, green: 0.62, blue: 0.04)
}

extension Color {
    init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}
