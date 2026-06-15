import SwiftUI
import Combine
import EventKit
import AppKit

// MARK: - Event model

struct CalendarEvent: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var date: Date          // start of the day the event belongs to
    var startTime: Date     // full date+time of start
    var endTime: Date
    var colorIndex: Int     // index into Theme.eventColors
    var location: String = ""
    var notes: String = ""
    var isAllDay: Bool = false
    var ekID: String? = nil      // 系统日历事件标识（EventKit eventIdentifier）
    var colorHex: String? = nil  // 系统日历的日历颜色
}

extension CalendarEvent {
    /// 系统日历事件用其所属日历的颜色，本地事件用自选颜色
    var displayColor: Color {
        if let hex = colorHex, let c = Color(hexString: hex) { return c }
        return Theme.eventColor(colorIndex)
    }
}

// MARK: - Display time zone (global so the Date.formatted extension can read it)

enum DisplayTimeZone {
    static var current: TimeZone = .current
}

enum CalendarAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var nsAppearanceName: NSAppearance.Name? {
        switch self {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
}

// MARK: - Store

@MainActor
final class CalendarStore: ObservableObject {
    @Published var events: [CalendarEvent] = [] {
        didSet { save() }
    }
    @Published var displayedMonth: Date   // any date inside the displayed month
    @Published var selectedDate: Date     // currently selected day

    /// 用于显示「今天」的时区（IANA 标识符），持久化到 UserDefaults
    @Published var timeZoneID: String {
        didSet {
            UserDefaults.standard.set(timeZoneID, forKey: "displayTimeZone")
            DisplayTimeZone.current = TimeZone(identifier: timeZoneID) ?? .current
            if usingSystemCalendar { reloadFromEventKit() } // 重新按新时区给事件分桶
        }
    }

    /// 每周起始日（1=周日，2=周一），持久化到 UserDefaults
    @Published var firstWeekday: Int {
        didSet { UserDefaults.standard.set(firstWeekday, forKey: "firstWeekday") }
    }

    /// 外观模式（跟随系统 / 浅色 / 深色），持久化到 UserDefaults
    @Published var appearanceMode: CalendarAppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
            applyAppearance()
        }
    }

    /// 开机时启动：以 SMAppService 的注册状态为唯一可信来源，不另行持久化。
    /// 翻转时调用注册 / 取消，并触发视图刷新以反映真实状态。
    var launchAtLogin: Bool {
        get { LaunchAtLogin.isEnabled }
        set {
            objectWillChange.send()
            newValue ? LaunchAtLogin.register() : LaunchAtLogin.unregister()
        }
    }

    /// 是否已连接系统日历（EventKit 授权通过后为 true，事件双向读写系统日历）
    @Published var usingSystemCalendar = false
    @Published private(set) var isRequestingCalendarAccess = false
    @Published var calendarAccessMessage: String?
    private let ekStore = EKEventStore()
    private var ekObserver: NSObjectProtocol?

    /// 系统日历事件的自选颜色（EventKit 不支持逐事件颜色，本地记住用户的选择）ekID -> colorIndex
    private var colorOverrides: [String: Int] =
        UserDefaults.standard.dictionary(forKey: "eventColorOverrides") as? [String: Int] ?? [:]

    private func setColorOverride(_ index: Int?, for ekID: String) {
        colorOverrides[ekID] = index
        UserDefaults.standard.set(colorOverrides, forKey: "eventColorOverrides")
    }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = firstWeekday
        cal.timeZone = timeZone
        return cal
    }

    /// 按每周起始日排列的星期表头符号
    var weekdaySymbols: [String] {
        let base = Theme.weekdaySymbols // 下标 0 = 周日
        return (0..<7).map { base[($0 + firstWeekday - 1) % 7] }
    }

    private var storageURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CalendarApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("events.json")
    }

    init() {
        let savedZone = UserDefaults.standard.string(forKey: "displayTimeZone") ?? TimeZone.current.identifier
        self.timeZoneID = savedZone
        DisplayTimeZone.current = TimeZone(identifier: savedZone) ?? .current

        let savedWeekday = UserDefaults.standard.integer(forKey: "firstWeekday")
        let effectiveWeekday = (savedWeekday == 1 || savedWeekday == 2) ? savedWeekday : 2
        self.firstWeekday = effectiveWeekday

        let savedAppearance = UserDefaults.standard.string(forKey: "appearanceMode")
        self.appearanceMode = CalendarAppearanceMode(rawValue: savedAppearance ?? "") ?? .system

        var cal = Calendar.current
        cal.firstWeekday = effectiveWeekday
        cal.timeZone = TimeZone(identifier: savedZone) ?? .current
        let today = cal.startOfDay(for: Date())
        self.displayedMonth = today
        self.selectedDate = today
        applyAppearance()
        load()
        if events.isEmpty { seedSampleEvents() }

        // 启动只做「已授权则静默重连」，不在后台触发弹窗（详见 connectCalendarIfAuthorized 注释）
        Task { await connectCalendarIfAuthorized() }
    }

    /// 恢复为跟随系统时区
    func useSystemTimeZone() {
        timeZoneID = TimeZone.current.identifier
    }

    private func applyAppearance() {
        NSApp.appearance = appearanceMode.nsAppearanceName.flatMap { NSAppearance(named: $0) }
    }

    // MARK: Queries

    func events(on day: Date) -> [CalendarEvent] {
        events
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.startTime < $1.startTime }
    }

    /// All day cells (including leading/trailing days of adjacent months) for the displayed month — always 42 cells (6 weeks).
    func gridDays() -> [Date] {
        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))!
        let weekdayOfFirst = calendar.component(.weekday, from: firstOfMonth)
        let leading = (weekdayOfFirst - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leading, to: firstOfMonth)!
        return (0..<42).map { calendar.date(byAdding: .day, value: $0, to: gridStart)! }
    }

    func isInDisplayedMonth(_ day: Date) -> Bool {
        calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
    }

    func isToday(_ day: Date) -> Bool {
        calendar.isDateInToday(day)
    }

    /// 今天之后的事件，按时间排序（跨天事件只显示一次）。
    /// 如果传入 excludedDay，则该日期的事件不会出现在「即将到来」里。
    func upcomingEvents(limit: Int = 12, excluding excludedDay: Date? = nil) -> [CalendarEvent] {
        let today = calendar.startOfDay(for: Date())
        let excludedKeys: Set<String>
        if let excludedDay {
            excludedKeys = Set(
                events
                    .filter { calendar.isDate($0.date, inSameDayAs: excludedDay) }
                    .map { $0.ekID ?? $0.id.uuidString }
            )
        } else {
            excludedKeys = []
        }
        var seen = Set<String>()
        return events
            .filter { $0.date > today }
            .filter { event in
                let key = event.ekID ?? event.id.uuidString
                return !excludedKeys.contains(key)
            }
            .sorted { $0.startTime < $1.startTime }
            .filter { ev in
                let key = ev.ekID ?? ev.id.uuidString
                return seen.insert(key).inserted
            }
            .prefix(limit)
            .map { $0 }
    }

    func todayEvents() -> [CalendarEvent] {
        events(on: calendar.startOfDay(for: Date()))
    }

    // MARK: Navigation

    func goToPreviousMonth() {
        displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth)!
    }

    func goToNextMonth() {
        displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth)!
    }

    func goToToday() {
        let today = calendar.startOfDay(for: Date())
        displayedMonth = today
        selectedDate = today
    }

    // MARK: Mutations（系统日历模式下直接写回 EventKit）

    func add(_ event: CalendarEvent) {
        if usingSystemCalendar {
            let ek = EKEvent(eventStore: ekStore)
            ek.calendar = ekStore.defaultCalendarForNewEvents
            apply(event, to: ek)
            try? ekStore.save(ek, span: .thisEvent, commit: true)
            if let id = ek.eventIdentifier { setColorOverride(event.colorIndex, for: id) }
            reloadFromEventKit()
        } else {
            events.append(event)
        }
    }

    func update(_ event: CalendarEvent) {
        if usingSystemCalendar, let ekID = event.ekID {
            guard let ek = ekStore.event(withIdentifier: ekID) else { return }
            apply(event, to: ek)
            try? ekStore.save(ek, span: .thisEvent, commit: true)
            setColorOverride(event.colorIndex, for: ekID)
            reloadFromEventKit()
        } else if let i = events.firstIndex(where: { $0.id == event.id }) {
            events[i] = event
        }
    }

    func delete(_ event: CalendarEvent) {
        if usingSystemCalendar, let ekID = event.ekID {
            guard let ek = ekStore.event(withIdentifier: ekID) else { return }
            try? ekStore.remove(ek, span: .thisEvent, commit: true)
            setColorOverride(nil, for: ekID)
            reloadFromEventKit()
        } else {
            events.removeAll { $0.id == event.id }
        }
    }

    /// 拖拽改期：把事件整体平移到目标日期（保持起止时刻不变）。
    /// key 为 ekID（系统日历事件）或本地事件的 UUID 字符串。
    func reschedule(key: String, to day: Date) {
        guard var event = events.first(where: { ($0.ekID ?? $0.id.uuidString) == key }) else { return }
        let targetDay = calendar.startOfDay(for: day)
        let delta = calendar.dateComponents([.day], from: event.date, to: targetDay).day ?? 0
        guard delta != 0,
              let newStart = calendar.date(byAdding: .day, value: delta, to: event.startTime),
              let newEnd = calendar.date(byAdding: .day, value: delta, to: event.endTime) else { return }
        event.date = targetDay
        event.startTime = newStart
        event.endTime = newEnd
        update(event)
    }

    /// 某天的法定节假日休/班标记（按显示时区的公历日期查询）
    func holidayMark(on day: Date) -> ChineseHolidays.DayMark? {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        guard let y = c.year, let m = c.month, let d = c.day else { return nil }
        return ChineseHolidays.mark(year: y, month: m, day: d)
    }

    private func apply(_ event: CalendarEvent, to ek: EKEvent) {
        ek.title = event.title
        ek.startDate = event.startTime
        ek.endDate = event.endTime
        ek.isAllDay = event.isAllDay
        ek.location = event.location.isEmpty ? nil : event.location
        ek.notes = event.notes.isEmpty ? nil : event.notes
    }

    // MARK: EventKit 双向同步

    /// 用户点「去授权」时调用：未决定 → 弹系统授权框；已拒绝/受限 → 跳系统设置让用户手动开。
    /// （仅在 Developer ID 签名/公证版上才会真正登记进隐私列表；ad-hoc build 会被 TCC 直接拒绝。）
    func requestCalendarAccess() {
        guard !isRequestingCalendarAccess else { return }
        Task { await runCalendarAccessFlow() }
    }

    private func runCalendarAccessFlow() async {
        isRequestingCalendarAccess = true
        calendarAccessMessage = nil
        defer { isRequestingCalendarAccess = false }

        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .notDetermined:
            // 关键：本应用是无 Dock 图标的 accessory 应用。若在「非前台活跃」状态下请求，
            // 系统会静默抑制 EventKit 授权弹窗——回调 granted=false 且状态仍停留在 .notDetermined，
            // 用户看不到任何弹框，表现就是「怎么点都授权不了」。这里临时切到 regular，
            // 等前台激活真正完成后再请求，随后恢复为菜单栏应用。
            await prepareForSystemAuthorizationUI()
            await setupEventKit()
            restoreAccessoryActivationPolicy()

            if !usingSystemCalendar {
                handleCalendarAccessFailure()
            }
        case .denied, .restricted:
            await prepareForSystemAuthorizationUI()
            openCalendarPrivacySettings()
            calendarAccessMessage = "已打开系统设置，请在「日历」权限里允许访问。"
            try? await Task.sleep(nanoseconds: 300_000_000)
            restoreAccessoryActivationPolicy()
        default:
            // .fullAccess / .writeOnly：已授权，直接重连
            await setupEventKit()
            if !usingSystemCalendar {
                handleCalendarAccessFailure()
            }
        }
    }

    private func prepareForSystemAuthorizationUI() async {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(nanoseconds: 250_000_000)
    }

    private func restoreAccessoryActivationPolicy() {
        NSApp.setActivationPolicy(.accessory)
    }

    private func openCalendarPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func handleCalendarAccessFailure() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .denied, .restricted:
            calendarAccessMessage = "日历权限未开启，请在系统设置中允许访问。"
            openCalendarPrivacySettings()
        case .notDetermined:
            calendarAccessMessage = "授权窗口未弹出，请再点一次或到系统设置手动开启日历权限。"
        default:
            calendarAccessMessage = "未能连接系统日历，请稍后重试。"
        }
    }

    /// 启动时调用：仅在「已经授权」时静默重连系统日历。
    /// 绝不在启动阶段对「未决定」发起请求——此时应用尚未成为前台活跃应用，弹窗会被系统抑制，
    /// 白白浪费掉那次自然弹框的机会（看起来甚至像被拒绝）。未授权的新用户改由其在面板里
    /// 主动点「去授权」触发（见 requestCalendarAccess，那条路径会先激活前台）。
    private func connectCalendarIfAuthorized() async {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly:
            await setupEventKit()
        default:
            break
        }
    }

    private func setupEventKit() async {
        let granted = (try? await ekStore.requestFullAccessToEvents()) ?? false
        usingSystemCalendar = granted
        guard granted else { return }
        calendarAccessMessage = nil
        reloadFromEventKit()
        ekObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: ekStore, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reloadFromEventKit() }
        }
    }

    /// 把系统日历前1年～后2年的事件读入；跨天事件按天展开（同一 ekID）
    private func reloadFromEventKit() {
        let cal = calendar
        let now = Date()
        guard let rangeStart = cal.date(byAdding: .year, value: -1, to: now),
              let rangeEnd = cal.date(byAdding: .year, value: 2, to: now) else { return }
        let predicate = ekStore.predicateForEvents(withStart: rangeStart, end: rangeEnd, calendars: nil)
        let ekEvents = ekStore.events(matching: predicate)

        var mapped: [CalendarEvent] = []
        for ek in ekEvents {
            guard let start = ek.startDate, let end = ek.endDate else { continue }
            // 用户自选过颜色的事件优先用自选色，否则用所属日历的颜色
            let override = ek.eventIdentifier.flatMap { colorOverrides[$0] }
            let hex = override == nil ? ek.calendar.flatMap { Self.hexString($0.color) } : nil
            // 末日界：全天/整点结束的事件不把结束当天多算一天
            let effectiveEnd = max(start, end.addingTimeInterval(-1))
            var day = cal.startOfDay(for: start)
            let lastDay = cal.startOfDay(for: effectiveEnd)
            var spanCount = 0
            while day <= lastDay && spanCount < 31 {
                mapped.append(CalendarEvent(
                    title: ek.title ?? "（无标题）",
                    date: day,
                    startTime: start,
                    endTime: end,
                    colorIndex: override ?? 0,
                    location: ek.location ?? "",
                    notes: ek.notes ?? "",
                    isAllDay: ek.isAllDay,
                    ekID: ek.eventIdentifier,
                    colorHex: hex
                ))
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                spanCount += 1
            }
        }
        events = mapped.sorted { $0.startTime < $1.startTime }
    }

    private static func hexString(_ color: NSColor?) -> String? {
        guard let c = color?.usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X",
                      Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([CalendarEvent].self, from: data) else { return }
        events = decoded
    }

    private func save() {
        guard !usingSystemCalendar else { return } // 系统日历模式不写本地文件
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func seedSampleEvents() {
        let today = calendar.startOfDay(for: Date())
        func at(dayOffset: Int, hour: Int, minute: Int = 0, durationMin: Int, title: String, color: Int, location: String = "") -> CalendarEvent {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: today)!
            let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
            let end = calendar.date(byAdding: .minute, value: durationMin, to: start)!
            return CalendarEvent(title: title, date: day, startTime: start, endTime: end, colorIndex: color, location: location)
        }
        events = [
            at(dayOffset: 0, hour: 9,  durationMin: 60,  title: "团队站会",  color: 0, location: "会议室 A"),
            at(dayOffset: 0, hour: 14, durationMin: 90,  title: "产品评审",  color: 1, location: "线上"),
            at(dayOffset: 1, hour: 10, durationMin: 60,  title: "客户电话",  color: 2),
            at(dayOffset: 2, hour: 12, durationMin: 60,  title: "午餐约会",  color: 3, location: "公司餐厅"),
            at(dayOffset: 4, hour: 19, durationMin: 120, title: "健身",      color: 4),
            at(dayOffset: -1, hour: 16, durationMin: 45, title: "一对一沟通", color: 1),
        ]
    }
}

// MARK: - Date helpers

extension Date {
    func formatted(_ format: String, locale: Locale = Locale(identifier: "zh_CN")) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = DisplayTimeZone.current
        f.dateFormat = format
        return f.string(from: self)
    }
}
