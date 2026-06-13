import SwiftUI

// MARK: - Editor mode

enum EditorMode {
    case create(initialDate: Date)
    case edit(CalendarEvent)
}

// MARK: - Event editor sheet (Apple Calendar "new event" style)

struct EventEditorView: View {
    @EnvironmentObject var store: CalendarStore
    @Environment(\.dismiss) private var dismiss
    let mode: EditorMode

    @State private var title: String
    @State private var location: String
    @State private var isAllDay: Bool
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var colorIndex: Int
    @State private var notes: String

    init(mode: EditorMode) {
        self.mode = mode
        switch mode {
        case .create(let initialDate):
            let cal = Calendar.current
            let day = cal.startOfDay(for: initialDate)
            let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
            let end = cal.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day
            _title = State(initialValue: "")
            _location = State(initialValue: "")
            _isAllDay = State(initialValue: false)
            _startTime = State(initialValue: start)
            _endTime = State(initialValue: end)
            _colorIndex = State(initialValue: 0)
            _notes = State(initialValue: "")
        case .edit(let event):
            _title = State(initialValue: event.title)
            _location = State(initialValue: event.location)
            _isAllDay = State(initialValue: event.isAllDay)
            _startTime = State(initialValue: event.startTime)
            _endTime = State(initialValue: event.endTime)
            _colorIndex = State(initialValue: event.colorIndex)
            _notes = State(initialValue: event.notes)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var pickerComponents: DatePickerComponents {
        isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Title
            TextField("事件标题", text: $title)
                .textFieldStyle(.plain)
                .font(.title2.bold())

            TextField("地点", text: $location)
                .textFieldStyle(.plain)
                .font(.body)

            Divider()

            // Time
            Toggle("全天", isOn: $isAllDay)
                .toggleStyle(.switch)
                .controlSize(.small)

            HStack {
                Text("开始")
                    .foregroundColor(Theme.secondaryText)
                    .frame(width: 36, alignment: .leading)
                DatePicker("", selection: $startTime, displayedComponents: pickerComponents)
                    .labelsHidden()
            }

            HStack {
                Text("结束")
                    .foregroundColor(Theme.secondaryText)
                    .frame(width: 36, alignment: .leading)
                DatePicker("", selection: $endTime, displayedComponents: pickerComponents)
                    .labelsHidden()
            }

            Divider()

            // Color
            HStack(spacing: 10) {
                Text("颜色")
                    .foregroundColor(Theme.secondaryText)
                    .frame(width: 36, alignment: .leading)
                ForEach(Theme.eventColors.indices, id: \.self) { i in
                    Circle()
                        .fill(Theme.eventColors[i])
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(colorIndex == i ? 0.7 : 0), lineWidth: 2)
                                .padding(-3)
                        )
                        .contentShape(Circle())
                        .onTapGesture { colorIndex = i }
                        .help(Theme.eventColorNames[i])
                }
                Spacer()
            }

            // Notes
            VStack(alignment: .leading, spacing: 6) {
                Text("备注")
                    .foregroundColor(Theme.secondaryText)
                TextEditor(text: $notes)
                    .font(.body)
                    .frame(height: 80)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: .separatorColor))
                    )
            }

            Spacer(minLength: 0)

            // Bottom buttons
            HStack {
                if case .edit(let event) = mode {
                    Button("删除", role: .destructive) {
                        store.delete(event)
                        dismiss()
                    }
                    .foregroundColor(.red)
                }

                Spacer()

                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(isEditing ? "保存" : "添加") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 420, height: 520)
        .background(PanelBackground().ignoresSafeArea())
        .onChange(of: startTime) { _, newStart in
            if endTime < newStart {
                endTime = store.calendar.date(byAdding: .hour, value: 1, to: newStart) ?? newStart
            }
        }
    }

    private func save() {
        let day = store.calendar.startOfDay(for: startTime)
        switch mode {
        case .create:
            let event = CalendarEvent(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                date: day,
                startTime: startTime,
                endTime: endTime,
                colorIndex: colorIndex,
                location: location,
                notes: notes,
                isAllDay: isAllDay
            )
            store.add(event)
        case .edit(let original):
            var event = original
            event.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            event.date = day
            event.startTime = startTime
            event.endTime = endTime
            event.colorIndex = colorIndex
            event.location = location
            event.notes = notes
            event.isAllDay = isAllDay
            store.update(event)
        }
        dismiss()
    }
}
