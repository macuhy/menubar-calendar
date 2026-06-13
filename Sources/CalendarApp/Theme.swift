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

    static func glassTint(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.10, green: 0.14, blue: 0.18).opacity(0.56)
            : Color(red: 0.98, green: 0.96, blue: 0.90).opacity(0.62)
    }

    static func glassHighlight(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.07)
            : Color.white.opacity(0.42)
    }

    static func glassBorder(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.08)
    }
}

struct PanelBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)

            Theme.glassTint(for: colorScheme)

            LinearGradient(
                colors: [
                    Theme.glassHighlight(for: colorScheme),
                    Color.clear,
                    Theme.accent.opacity(colorScheme == .dark ? 0.08 : 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .overlay(
            Rectangle()
                .strokeBorder(Theme.glassBorder(for: colorScheme), lineWidth: 0.8)
        )
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
    }
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
