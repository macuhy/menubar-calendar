import SwiftUI

/// 时区设置弹窗：搜索并选择「今天」按哪个时区显示
struct SettingsView: View {
    @EnvironmentObject var store: CalendarStore
    @Environment(\.dismiss) private var dismiss
    var onDone: (() -> Void)?
    @State private var query = ""

    private var filteredZones: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers.sorted()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("完成") {
                    if let onDone {
                        onDone()
                    } else {
                        dismiss()
                    }
                }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)

            Divider()

            HStack(spacing: 6) {
                Circle()
                    .fill(store.usingSystemCalendar ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(store.usingSystemCalendar
                     ? "已连接系统日历（双向同步）"
                     : "未连接系统日历，当前为本地模式")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
                Spacer()
                if !store.usingSystemCalendar {
                    Button(store.isRequestingCalendarAccess ? "授权中…" : "去授权") {
                        store.requestCalendarAccess()
                    }
                        .font(.system(size: 11))
                        .disabled(store.isRequestingCalendarAccess)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            if let message = store.calendarAccessMessage, !store.usingSystemCalendar {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }

            HStack {
                Text("每周开始于")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Picker("", selection: $store.firstWeekday) {
                    Text("周日").tag(1)
                    Text("周一").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 120)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            HStack {
                Text("外观")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Picker("", selection: $store.appearanceMode) {
                    Text("系统").tag(CalendarAppearanceMode.system)
                    Text("浅色").tag(CalendarAppearanceMode.light)
                    Text("深色").tag(CalendarAppearanceMode.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            HStack {
                Text("开机时启动")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Toggle("", isOn: $store.launchAtLogin)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            HStack {
                Text("全局快捷键")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("⌃⌥C 显示 / 隐藏面板")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("「今天」使用的时区")
                    .font(.system(size: 12, weight: .medium))
                Text("当前：\(store.timeZoneID)（\(offsetLabel(store.timeZone))）")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)

                Button("使用系统时区（\(TimeZone.current.identifier)）") {
                    store.useSystemTimeZone()
                }
                .font(.system(size: 12))

                TextField("搜索时区，如 Shanghai、Tokyo、America…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredZones, id: \.self) { id in
                        zoneRow(id)
                    }
                }
            }
        }
        .frame(width: 340, height: 600)
        .background(PanelBackground().ignoresSafeArea())
        .preferredColorScheme(store.appearanceMode.colorScheme)
    }

    private func zoneRow(_ id: String) -> some View {
        let selected = id == store.timeZoneID
        return Button {
            store.timeZoneID = id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(id.replacingOccurrences(of: "_", with: " "))
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                    if let tz = TimeZone(identifier: id) {
                        Text(offsetLabel(tz))
                            .font(.system(size: 10))
                            .foregroundColor(Theme.secondaryText)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(selected ? Theme.accent.opacity(0.08) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func offsetLabel(_ tz: TimeZone) -> String {
        let seconds = tz.secondsFromGMT()
        let hours = seconds / 3600
        let minutes = abs(seconds % 3600) / 60
        let sign = hours >= 0 ? "+" : "-"
        return String(format: "GMT%@%d:%02d", sign, abs(hours), minutes)
    }
}
