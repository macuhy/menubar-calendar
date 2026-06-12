import SwiftUI

/// Top toolbar of the month view, mimicking the Apple Calendar header:
/// big month title on the left, segmented prev/today/next controls and
/// a "+" new-event button on the right.
struct HeaderView: View {
    @EnvironmentObject var store: CalendarStore
    @Binding var showingNewEvent: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                titleView
                Spacer()
                HStack(spacing: 12) {
                    navigationSegment
                    newEventButton
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)

            Divider()
        }
        .background(Theme.background)
    }

    // MARK: Title — "6月" accented red, "2026年" regular, like Apple Calendar.

    private var titleView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(store.displayedMonth.formatted("M月"))
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(Theme.accent)
            Text(store.displayedMonth.formatted("yyyy年"))
                .font(.system(size: 26, weight: .regular))
                .foregroundColor(.primary)
        }
        .animation(.none, value: store.displayedMonth)
    }

    // MARK: Segmented ◀ / 今天 / ▶ control

    private var navigationSegment: some View {
        HStack(spacing: 0) {
            SegmentButton(action: { store.goToPreviousMonth() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            segmentSeparator
            SegmentButton(action: { store.goToToday() }) {
                Text("今天")
                    .font(.system(size: 13))
            }
            segmentSeparator
            SegmentButton(action: { store.goToNextMonth() }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Theme.cellBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var segmentSeparator: some View {
        Rectangle()
            .fill(Theme.cellBorder)
            .frame(width: 1, height: 16)
    }

    // MARK: "+" new event button

    private var newEventButton: some View {
        Button {
            showingNewEvent = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.accent)
                )
        }
        .buttonStyle(.plain)
        .help("新建事件")
    }
}

// MARK: - Segment button with hover highlight

private struct SegmentButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            label()
                .foregroundColor(.primary)
                .frame(minWidth: 36)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(isHovering ? Color.primary.opacity(0.08) : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
