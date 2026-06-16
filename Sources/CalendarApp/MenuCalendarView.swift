import SwiftUI
import UniformTypeIdentifiers

/// sheet(item:) 用的新建事件目标日期包装
private struct CreationTarget: Identifiable {
    let id = UUID()
    let date: Date
}

/// 菜单栏下拉面板：紧凑月历 + 当日日程列表
struct MenuCalendarView: View {
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var updater: UpdaterManager
    @State private var editingEvent: CalendarEvent? = nil
    @State private var creating: CreationTarget? = nil
    @State private var showingSettings = false
    @State private var commandText = ""
    @State private var commandMessage: String? = nil
    @FocusState private var commandFocused: Bool

    var body: some View {
        Group {
            if showingSettings {
                SettingsView {
                    showingSettings = false
                }
            } else {
                calendarPanel
            }
        }
        .frame(width: 340, height: 600)
        .background(PanelBackground().ignoresSafeArea())
        .preferredColorScheme(store.appearanceMode.colorScheme)
        .sheet(item: $creating) { target in
            EventEditorView(mode: .create(initialDate: target.date))
                .preferredColorScheme(store.appearanceMode.colorScheme)
        }
        .sheet(item: $editingEvent) { event in
            EventEditorView(mode: .edit(event))
                .preferredColorScheme(store.appearanceMode.colorScheme)
        }
        .onAppear {
            publishSheetBehavior()
            focusCommandField()
        }
        .onDisappear {
            publishSheetBehavior(keepOpen: false)
        }
        .onChange(of: creating != nil) { _, _ in publishSheetBehavior() }
        .onChange(of: editingEvent != nil) { _, _ in publishSheetBehavior() }
        .onChange(of: showingSettings) { _, isShowing in
            if !isShowing { focusCommandField() }
        }
        .onChange(of: commandText) { _, newValue in
            if !newValue.isEmpty { commandMessage = nil }
        }
    }

    private var calendarPanel: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            commandBar
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            weekdayRow
                .padding(.horizontal, 12)

            miniGrid
                .padding(.horizontal, 8)
                .padding(.bottom, 6)

            Divider()

            if isCommandActive {
                commandResults
            } else {
                agendaList
            }

            Divider()

            footer
        }
    }

    private func publishSheetBehavior(keepOpen: Bool? = nil) {
        let shouldKeepOpen = keepOpen ?? (creating != nil || editingEvent != nil)
        NotificationCenter.default.post(
            name: .calendarPopoverSheetBehaviorChanged,
            object: nil,
            userInfo: ["keepOpen": shouldKeepOpen]
        )
    }

    private func focusCommandField() {
        DispatchQueue.main.async {
            commandFocused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            (Text(store.displayedMonth.formatted("M月")).foregroundColor(Theme.accent)
             + Text(" " + store.displayedMonth.formatted("yyyy年")))
                .font(.system(size: 15, weight: .bold))

            Spacer()

            navButton("plus") { creating = CreationTarget(date: store.selectedDate) }
                .help("新建日程（也可双击日期格子）")
            navButton("chevron.left") { store.goToPreviousMonth() }
            Button("今天") { store.goToToday() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(Theme.accent)
            navButton("chevron.right") { store.goToNextMonth() }
        }
    }

    private func navButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Command bar

    private var commandBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.secondaryText)

                TextField("搜索、跳转或创建：明天 10点 产品会 1h", text: $commandText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($commandFocused)
                    .onSubmit(runCommand)

                if !commandText.isEmpty {
                    Button {
                        commandText = ""
                        commandMessage = nil
                        focusCommandField()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.secondaryText.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("清空")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(commandFocused ? 0.18 : 0.08), lineWidth: 1)
            )

            if let commandMessage, commandText.isEmpty {
                Text(commandMessage)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
                    .padding(.horizontal, 2)
            }
        }
    }

    private var isCommandActive: Bool {
        !commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Grid

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(store.weekdaySymbols, id: \.self) { s in
                Text(s)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 2)
    }

    private var miniGrid: some View {
        let days = store.gridDays()
        return VStack(spacing: 2) {
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        MiniDayCell(day: days[row * 7 + col]) { date in
                            creating = CreationTarget(date: date)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Agenda（今天 / 即将到来，始终展开不折叠）

    private var agendaList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 选中了今天以外的日期时，先显示该日的日程
                if !store.isToday(store.selectedDate) {
                    sectionHeader(store.selectedDate.formatted("M月d日 EEE"))
                    let selected = store.events(on: store.selectedDate)
                    if selected.isEmpty {
                        emptyHint("当天没有日程")
                    } else {
                        ForEach(selected) { agendaRow($0, showDate: false) }
                    }
                }

                sectionHeader("今天")
                    .padding(.top, store.isToday(store.selectedDate) ? 0 : 8)
                let today = store.todayEvents()
                if today.isEmpty {
                    emptyHint("今天没有日程")
                } else {
                    ForEach(today) { agendaRow($0, showDate: false) }
                }

                sectionHeader("即将到来")
                    .padding(.top, 8)
                // 选中未来某天时，上方已显示当天日程；这里剔除它，避免重复。
                let upcoming = store.upcomingEvents(excluding: store.selectedDate)
                if upcoming.isEmpty {
                    emptyHint("暂无即将到来的日程")
                } else {
                    ForEach(upcoming) { agendaRow($0, showDate: true) }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Theme.secondaryText)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(Theme.secondaryText.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }

    private func agendaRow(_ event: CalendarEvent, showDate: Bool) -> some View {
        AgendaRow(event: event, showDate: showDate) {
            editingEvent = event
        } onDelete: {
            store.delete(event)
        }
    }

    // MARK: - Command results

    private var commandResults: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let command = parsedCommand {
                    commandPreview(command)
                        .padding(.bottom, 6)
                }

                let results = searchResults
                if !results.isEmpty {
                    sectionHeader("搜索结果")
                    ForEach(results) { agendaRow($0, showDate: true) }
                } else if case nil = parsedCommand {
                    emptyHint("没有找到匹配事件")
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity)
    }

    private var parsedCommand: QuickCommand? {
        QuickCommandParser.parse(
            commandText,
            calendar: store.calendar,
            selectedDate: store.selectedDate
        )
    }

    private var searchResults: [CalendarEvent] {
        let query = searchQuery
        guard !query.isEmpty else { return [] }
        return filteredEvents(for: query)
    }

    private var searchQuery: String {
        let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedSearch = parsedCommand?.searchText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return parsedSearch.isEmpty ? trimmed : parsedSearch
    }

    private func commandPreview(_ command: QuickCommand) -> some View {
        Button {
            runCommand()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: commandIcon(command))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(commandTitle(command))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text("按回车执行")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.secondaryText)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.accent.opacity(0.08))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func commandIcon(_ command: QuickCommand) -> String {
        switch command.action {
        case .jump:
            return "arrow.turn.down.right"
        case .create:
            return "plus.circle.fill"
        }
    }

    private func commandTitle(_ command: QuickCommand) -> String {
        switch command.action {
        case .jump(let date):
            return "跳转到 \(date.formatted("M月d日 EEE"))"
        case .create(let event):
            return "创建 \(event.title) · \(eventDateTimeLabel(event))"
        }
    }

    private func eventDateTimeLabel(_ event: CalendarEvent) -> String {
        if event.isAllDay {
            return "\(event.date.formatted("M月d日 EEE")) 全天"
        }
        return "\(event.date.formatted("M月d日 EEE")) \(event.startTime.formatted("HH:mm"))-\(event.endTime.formatted("HH:mm"))"
    }

    private func runCommand() {
        let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let command = parsedCommand {
            execute(command)
            return
        }

        if let first = filteredEvents(for: trimmed).first {
            store.goTo(first.date)
            editingEvent = first
            commandText = ""
            commandMessage = "已打开：\(first.title)"
            return
        }

        commandMessage = "没有找到匹配事件"
    }

    private func execute(_ command: QuickCommand) {
        switch command.action {
        case .jump(let date):
            store.goTo(date)
            commandText = ""
            commandMessage = "已跳转到 \(date.formatted("M月d日 EEE"))"
        case .create(let event):
            store.add(event)
            store.goTo(event.date)
            commandText = ""
            commandMessage = "已创建：\(event.title)"
        }
        focusCommandField()
    }

    private func filteredEvents(for query: String) -> [CalendarEvent] {
        let tokens = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else { return [] }

        let today = store.calendar.startOfDay(for: Date())
        return store.events
            .filter { event in
                let haystack = [
                    event.title,
                    event.location,
                    event.notes,
                    event.date.formatted("yyyy-M-d EEE"),
                    event.date.formatted("M月d日 EEE")
                ]
                    .joined(separator: " ")
                    .lowercased()
                return tokens.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
            }
            .sorted { lhs, rhs in
                let lhsFuture = lhs.startTime >= today
                let rhsFuture = rhs.startTime >= today
                if lhsFuture != rhsFuture { return lhsFuture }
                return lhsFuture ? lhs.startTime < rhs.startTime : lhs.startTime > rhs.startTime
            }
            .prefix(20)
            .map { $0 }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            TimelineView(.everyMinute) { context in
                Text(context.date.formatted("yyyy年M月d日 EEEE HH:mm"))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
            }
            Spacer()
            Button {
                updater.checkForUpdates()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!updater.canCheckForUpdates)
            .help("检查更新")

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("设置")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("退出")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// 月历中的单个日期格子：单击选中、双击新建、支持拖放改期，带节假日休/班角标
private struct MiniDayCell: View {
    @EnvironmentObject var store: CalendarStore
    let day: Date
    let onCreate: (Date) -> Void
    @State private var dropTargeted = false

    var body: some View {
        let inMonth = store.isInDisplayedMonth(day)
        let isToday = store.isToday(day)
        let isSelected = store.calendar.isDate(day, inSameDayAs: store.selectedDate)
        let events = store.events(on: day)
        let mark = store.holidayMark(on: day)

        VStack(spacing: 1) {
            Text("\(store.calendar.component(.day, from: day))")
                .font(.system(size: 12, weight: isToday ? .bold : .regular))
                .foregroundColor(
                    isToday ? .white :
                    inMonth ? .primary : Theme.secondaryText.opacity(0.5)
                )
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(
                        isToday ? Theme.accent :
                        (isSelected || dropTargeted) ? Color.primary.opacity(0.12) : .clear
                    )
                )
                .overlay(alignment: .topTrailing) {
                    if let mark { badge(mark).opacity(inMonth ? 1 : 0.45) }
                }
            HStack(spacing: 2) {
                ForEach(events.prefix(3)) { e in
                    Circle()
                        .fill(e.displayColor.opacity(inMonth ? 1 : 0.4))
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .help(holidayName(mark) ?? "")
        .gesture(TapGesture(count: 2).onEnded {
            let date = store.calendar.startOfDay(for: day)
            store.selectedDate = date
            onCreate(date)
        })
        .simultaneousGesture(TapGesture().onEnded {
            store.selectedDate = store.calendar.startOfDay(for: day)
        })
        .onDrop(of: [.plainText], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            let targetDay = day
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let key = object as? String else { return }
                Task { @MainActor in store.reschedule(key: key, to: targetDay) }
            }
            return true
        }
    }

    private func badge(_ mark: ChineseHolidays.DayMark) -> some View {
        let isRest = holidayName(mark) != nil
        return Text(isRest ? "休" : "班")
            .font(.system(size: 7, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 10, height: 10)
            .background(Circle().fill(isRest ? Theme.restBadge : Theme.workBadge))
            .offset(x: 4, y: -2)
    }

    private func holidayName(_ mark: ChineseHolidays.DayMark?) -> String? {
        if case .rest(let name) = mark { return name }
        return nil
    }
}

/// 单行日程：竖色条 + 标题 + 时间（即将到来的行附带日期标签）
private struct AgendaRow: View {
    @EnvironmentObject var store: CalendarStore
    let event: CalendarEvent
    let showDate: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(event.displayColor)
                .frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if showDate {
                        Text(dateLabel)
                            .foregroundColor(event.displayColor)
                    }
                    Text(timeLabel)
                        .foregroundColor(Theme.secondaryText)
                    if !event.location.isEmpty {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.secondaryText)
                        Text(event.location)
                            .foregroundColor(Theme.secondaryText)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 11))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(hovered ? Color.primary.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(perform: onTap)
        .onDrag {
            NSItemProvider(object: (event.ekID ?? event.id.uuidString) as NSString)
        }
        .contextMenu {
            Button("删除", role: .destructive, action: onDelete)
        }
    }

    private var timeLabel: String {
        event.isAllDay ? "全天"
            : "\(event.startTime.formatted("HH:mm")) – \(event.endTime.formatted("HH:mm"))"
    }

    private var dateLabel: String {
        let today = store.calendar.startOfDay(for: Date())
        let days = store.calendar.dateComponents([.day], from: today, to: event.date).day ?? 0
        switch days {
        case 1: return "明天"
        case 2: return "后天"
        default: return event.date.formatted("M月d日 EEE")
        }
    }
}
