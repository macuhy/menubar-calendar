import SwiftUI

// MARK: - Day detail sidebar (Apple Calendar style)

struct DayDetailView: View {
    @EnvironmentObject var store: CalendarStore
    @Binding var editingEvent: CalendarEvent?
    @Binding var showingNewEvent: Bool

    var body: some View {
        let dayEvents = store.events(on: store.selectedDate)

        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

            Divider()

            if dayEvents.isEmpty {
                emptyPlaceholder
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(dayEvents) { event in
                            EventRow(event: event) {
                                editingEvent = event
                            } onDelete: {
                                store.delete(event)
                            }
                        }
                    }
                    .padding(10)
                }
            }

            Divider()

            Button {
                showingNewEvent = true
            } label: {
                Label("新建事件", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(store.selectedDate.formatted("M月d日 EEEE"))
                .font(.title3.bold())

            if store.isToday(store.selectedDate) {
                Text("今天")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.accent))
            }

            Spacer()
        }
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "calendar.badge.minus")
                .font(.system(size: 34))
                .foregroundColor(Theme.secondaryText.opacity(0.6))
            Text("没有日程")
                .font(.body)
                .foregroundColor(Theme.secondaryText)
            Button("新建事件") {
                showingNewEvent = true
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Event row

private struct EventRow: View {
    let event: CalendarEvent
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private var timeText: String {
        if event.isAllDay {
            return "全天"
        }
        return "\(event.startTime.formatted("HH:mm")) – \(event.endTime.formatted("HH:mm"))"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.displayColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.body.bold())
                    .lineLimit(2)

                Text(timeText)
                    .font(.caption)
                    .foregroundColor(Theme.secondaryText)

                if !event.location.isEmpty {
                    Label(event.location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundColor(Theme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? event.displayColor.opacity(0.12) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
        .onTapGesture { onTap() }
        .contextMenu {
            Button("删除", role: .destructive) { onDelete() }
        }
    }
}
