import SwiftUI
import AppKit
import Combine
import Carbon.HIToolbox

@main
struct CalendarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var titleTimer: Timer?
    private var storeSubscription: AnyCancellable?
    private var appearanceSubscription: AnyCancellable?
    private var hotKey: GlobalHotKey?
    private var outsideClickMonitor: Any?
    private var escKeyMonitor: Any?
    let store = CalendarStore()
    let updater = UpdaterManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "日历")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(toggleFromClick)
            updateTitle()
        }

        // 点击打开，由我们监听应用外点击关闭，避免 transient 行为影响编辑 sheet。
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentSize = NSSize(
            width: PanelLayout.preferredWidth,
            height: PanelLayout.preferredHeight
        )
        popover.contentViewController = NSHostingController(
            rootView: MenuCalendarView()
                .environmentObject(store)
                .environmentObject(updater)
        )

        // 每秒检查一次，标题文本变化（跨分钟）时才真正刷新
        titleTimer = scheduleRepeatingTimer(interval: 1) { [weak self] _ in
            Task { @MainActor in self?.updateTitle() }
        }

        // 时区设置变化时，菜单栏日期立即跟着刷新
        storeSubscription = store.$timeZoneID.sink { [weak self] _ in
            Task { @MainActor in self?.updateTitle() }
        }
        appearanceSubscription = store.$appearanceMode.sink { [weak self] _ in
            Task { @MainActor in self?.applyPopoverAppearance() }
        }

        // 全局快捷键 ⌃⌥C：显示 / 隐藏面板
        hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(controlKey | optionKey)
        ) { [weak self] in
            self?.toggleFromHotKey()
        }

        // 面板打开时按 Esc 收起
        escKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown, event.keyCode == 53 else { return event }
            self.closePopover()
            return nil
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        store.refreshCalendarAuthorization()
    }

    private func updateTitle() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = DisplayTimeZone.current
        f.dateFormat = "M月d日 EEE HH:mm" // 显式 HH 模式强制 24 小时制
        let title = " " + f.string(from: Date())
        if statusItem.button?.title != title {
            statusItem.button?.title = title
        }
    }

    // MARK: - Popover

    private func scheduleRepeatingTimer(
        interval: TimeInterval,
        handler: @escaping @Sendable (Timer) -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true, block: handler)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    @objc private func toggleFromClick() {
        popover.isShown ? closePopover() : showPopover()
    }

    private func toggleFromHotKey() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
            // 激活应用，让面板能直接接收键盘事件（如 Esc）
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showPopover() {
        guard !popover.isShown, let button = statusItem.button else { return }
        store.refreshCalendarAuthorization()
        updatePopoverSize()
        applyPopoverAppearance()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        applyPopoverAppearance()
        positionPopoverNearStatusItem()
        clearStatusButtonHighlight(button)
        DispatchQueue.main.async { [weak self, weak button] in
            self?.positionPopoverNearStatusItem()
            if let button { self?.clearStatusButtonHighlight(button) }
        }
        startOutsideClickMonitor()
    }

    private func updatePopoverSize() {
        guard let screenFrame = statusButtonScreenRect().flatMap({ screen(containing: $0)?.visibleFrame })
            ?? NSScreen.main?.visibleFrame else {
            popover.contentSize = NSSize(
                width: PanelLayout.preferredWidth,
                height: PanelLayout.preferredHeight
            )
            return
        }
        let margin = PanelLayout.screenMargin
        let availableWidth = max(0, screenFrame.width - margin * 2)
        let availableHeight = max(0, screenFrame.height - margin * 2)

        popover.contentSize = NSSize(
            width: fittedLength(
                preferred: PanelLayout.preferredWidth,
                minimum: PanelLayout.minimumWidth,
                available: availableWidth
            ),
            height: fittedLength(
                preferred: PanelLayout.preferredHeight,
                minimum: PanelLayout.minimumHeight,
                available: availableHeight
            )
        )
    }

    private func fittedLength(preferred: CGFloat, minimum: CGFloat, available: CGFloat) -> CGFloat {
        guard available > 0 else { return preferred }
        let capped = min(preferred, available)
        return capped >= minimum ? capped : available
    }

    private func positionPopoverNearStatusItem() {
        guard let window = popover.contentViewController?.view.window,
              let buttonRect = statusButtonScreenRect() else { return }
        let screenFrame = screen(containing: buttonRect)?.visibleFrame
            ?? window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? window.frame
        let margin = PanelLayout.screenMargin
        let gap: CGFloat = 6

        var frame = window.frame
        frame.size.width = min(frame.width, max(0, screenFrame.width - margin * 2))
        frame.size.height = min(frame.height, max(0, screenFrame.height - margin * 2))

        frame.origin.x = buttonRect.midX - frame.width / 2
        frame.origin.x = clampedOrigin(
            frame.origin.x,
            lower: screenFrame.minX + margin,
            upper: screenFrame.maxX - frame.width - margin
        )

        let belowMenuBarY = buttonRect.minY - frame.height - gap
        let aboveButtonY = buttonRect.maxY + gap
        frame.origin.y = belowMenuBarY >= screenFrame.minY + margin
            ? belowMenuBarY
            : aboveButtonY
        frame.origin.y = clampedOrigin(
            frame.origin.y,
            lower: screenFrame.minY + margin,
            upper: screenFrame.maxY - frame.height - margin
        )

        window.setFrame(frame, display: true)
    }

    private func clampedOrigin(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard upper >= lower else { return lower }
        return min(max(value, lower), upper)
    }

    private func applyPopoverAppearance() {
        let appearance = store.appearanceMode.nsAppearanceName.flatMap { NSAppearance(named: $0) }

        if let view = popover.contentViewController?.view {
            view.appearance = appearance
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.clear.cgColor
        }
        if let window = popover.contentViewController?.view.window {
            window.appearance = appearance
            window.isOpaque = false
            window.backgroundColor = .clear
        }
    }

    private func clearStatusButtonHighlight(_ button: NSStatusBarButton) {
        button.highlight(false)
        button.state = .off
        DispatchQueue.main.async {
            button.highlight(false)
            button.state = .off
        }
    }

    private func closePopover() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        popover.performClose(nil)
    }

    private func startOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.closePopover() }
        }
    }

    private func statusButtonScreenRect() -> NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(buttonRectInWindow)
    }

    private func screen(containing rect: NSRect) -> NSScreen? {
        let point = NSPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(point) }
    }
}
