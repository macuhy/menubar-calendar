import SwiftUI

/// The core month grid, mimicking Apple Calendar's month view:
/// a weekday header row on top and a 6x7 grid of day cells below.
struct MonthGridView: View {
    @EnvironmentObject var store: CalendarStore
    @Binding var editingEvent: CalendarEvent?

    var body: some View {
        VStack(spacing: 0) {
            weekdayHeader
            Divider()
            grid
        }
    }

    // MARK: Weekday header

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(store.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text("周\(symbol)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondaryText.opacity(isWeekend(symbol) ? 0.6 : 1.0))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 8)
            }
        }
        .padding(.vertical, 6)
    }

    private func isWeekend(_ symbol: String) -> Bool {
        symbol == "六" || symbol == "日"
    }

    // MARK: Grid

    private var grid: some View {
        GeometryReader { proxy in
            let days = store.gridDays()
            let cellWidth = proxy.size.width / 7
            let cellHeight = proxy.size.height / 6

            ZStack(alignment: .topLeading) {
                // Day cells
                VStack(spacing: 0) {
                    ForEach(0..<6, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { column in
                                DayCell(
                                    day: days[row * 7 + column],
                                    editingEvent: $editingEvent
                                )
                                .frame(width: cellWidth, height: cellHeight)
                            }
                        }
                    }
                }

                gridLines(size: proxy.size, cellWidth: cellWidth, cellHeight: cellHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Thin separator lines between cells, drawn once on top of all cells
    /// so each border is a single 0.5pt hairline (no doubled strokes).
    private func gridLines(size: CGSize, cellWidth: CGFloat, cellHeight: CGFloat) -> some View {
        Path { path in
            // Horizontal lines between rows
            for row in 1..<6 {
                let y = CGFloat(row) * cellHeight
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            // Vertical lines between columns
            for column in 1..<7 {
                let x = CGFloat(column) * cellWidth
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
        }
        .stroke(Theme.cellBorder, lineWidth: 0.5)
        .allowsHitTesting(false)
    }
}

// MARK: - Day cell

private struct DayCell: View {
    @EnvironmentObject var store: CalendarStore
    let day: Date
    @Binding var editingEvent: CalendarEvent?

    private static let maxVisibleEvents = 3

    private var isSelected: Bool {
        store.calendar.isDate(day, inSameDayAs: store.selectedDate)
    }

    var body: some View {
        let inMonth = store.isInDisplayedMonth(day)
        let dayEvents = store.events(on: day)

        VStack(alignment: .leading, spacing: 2) {
            dayNumber(inMonth: inMonth)

            ForEach(dayEvents.prefix(Self.maxVisibleEvents)) { event in
                EventChip(event: event, dimmed: !inMonth)
                    .onTapGesture { editingEvent = event }
            }

            if dayEvents.count > Self.maxVisibleEvents {
                Text("还有 \(dayEvents.count - Self.maxVisibleEvents) 项")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 3)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(isSelected ? Theme.accent.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        // Single click selects; double click also just selects the day.
        .gesture(
            TapGesture(count: 2).onEnded { store.selectedDate = day }
        )
        .simultaneousGesture(
            TapGesture(count: 1).onEnded { store.selectedDate = day }
        )
    }

    private func dayNumber(inMonth: Bool) -> some View {
        let dayValue = store.calendar.component(.day, from: day)
        let isToday = store.isToday(day)

        return HStack {
            Spacer(minLength: 0)
            Text("\(dayValue)")
                .font(.system(size: 12, weight: isToday ? .semibold : .regular))
                .foregroundStyle(numberColor(inMonth: inMonth, isToday: isToday))
                .frame(width: 20, height: 20)
                .background(numberBackground(isToday: isToday))
        }
        .padding(.trailing, 3)
    }

    private func numberColor(inMonth: Bool, isToday: Bool) -> Color {
        if isToday { return .white }
        if !inMonth { return Theme.secondaryText.opacity(0.5) }
        return .primary
    }

    @ViewBuilder
    private func numberBackground(isToday: Bool) -> some View {
        if isToday {
            Circle().fill(Theme.accent)
        } else if isSelected {
            Circle().strokeBorder(Theme.secondaryText.opacity(0.6), lineWidth: 1)
        }
    }
}

// MARK: - Event chip

private struct EventChip: View {
    let event: CalendarEvent
    var dimmed: Bool = false

    var body: some View {
        let color = event.displayColor

        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 3)

            Text(event.title)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 1.5)
        .padding(.horizontal, 3)
        .frame(height: 16)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(event.isAllDay ? 0.28 : 0.14))
        )
        .opacity(dimmed ? 0.45 : 1.0)
        .contentShape(Rectangle())
        .help(event.title)
    }
}
