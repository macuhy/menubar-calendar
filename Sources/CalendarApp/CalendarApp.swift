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
    private var autoHideTimer: Timer?
    private var hoverOpenTimer: Timer?
    private var titleTimer: Timer?
    private var storeSubscription: AnyCancellable?
    private var appearanceSubscription: AnyCancellable?
    private var sheetBehaviorObserver: NSObjectProtocol?
    private var hotKey: GlobalHotKey?
    /// 由快捷键打开且鼠标尚未移入面板时，悬停检测不收起面板
    private var openedViaHotKey = false
    private var hoveredSinceHotKeyOpen = false
    /// 刚关闭后若光标仍停在图标上，先不重开；待光标离开图标再恢复悬停打开
    private var suppressHoverReopen = false
    private var keepOpenWhileSheetIsPresented = false
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
            // 悬停即弹出：给菜单栏按钮挂 tracking area
            let tracking = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self, userInfo: nil
            )
            button.addTrackingArea(tracking)
            updateTitle()
        }

        // 关闭时机完全由我们控制（悬停离开后自动收起），避免 transient 行为
        // 在弹出编辑 sheet 时把面板一起关掉
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentSize = NSSize(width: 340, height: 600)
        popover.contentViewController = NSHostingController(
            rootView: MenuCalendarView()
                .environmentObject(store)
                .environmentObject(updater)
        )

        // 每秒检查一次，标题文本变化（跨分钟）时才真正刷新
        titleTimer = scheduleRepeatingTimer(interval: 1) { [weak self] _ in
            Task { @MainActor in self?.updateTitle() }
        }
        // 菜单栏按钮的 tracking event 偶尔会被系统状态栏吞掉，轮询鼠标位置更稳定。
        hoverOpenTimer = scheduleRepeatingTimer(interval: 0.12) { [weak self] _ in
            Task { @MainActor in self?.openOnMenuBarHoverIfNeeded() }
        }

        // 时区设置变化时，菜单栏日期立即跟着刷新
        storeSubscription = store.$timeZoneID.sink { [weak self] _ in
            Task { @MainActor in self?.updateTitle() }
        }
        appearanceSubscription = store.$appearanceMode.sink { [weak self] _ in
            Task { @MainActor in self?.applyPopoverAppearance() }
        }
        sheetBehaviorObserver = NotificationCenter.default.addObserver(
            forName: .calendarPopoverSheetBehaviorChanged, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                self?.keepOpenWhileSheetIsPresented = note.userInfo?["keepOpen"] as? Bool ?? false
            }
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

    // MARK: - Hover open / auto close

    private func scheduleRepeatingTimer(
        interval: TimeInterval,
        handler: @escaping @Sendable (Timer) -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true, block: handler)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    @objc func mouseEntered(with event: NSEvent) {
        requestHoverOpen()
    }

    @objc func mouseExited(with event: NSEvent) {
        // 离开图标即重新武装悬停打开（轮询也会兜底复位）
        suppressHoverReopen = false
        // 之后由 autoHideTimer 判断鼠标是否已移入面板，否则收起
    }

    @objc private func toggleFromClick() {
        popover.isShown ? closePopover() : showPopover()
    }

    private func toggleFromHotKey() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover(viaHotKey: true)
            // 激活应用，让面板能直接接收键盘事件（如 Esc）
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showPopover(viaHotKey: Bool = false) {
        guard !popover.isShown, let button = statusItem.button else { return }
        store.refreshCalendarAuthorization()
        openedViaHotKey = viaHotKey
        hoveredSinceHotKeyOpen = false
        applyPopoverAppearance()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        applyPopoverAppearance()
        positionPopoverNearStatusItem()
        clearStatusButtonHighlight(button)
        DispatchQueue.main.async { [weak self, weak button] in
            self?.positionPopoverNearStatusItem()
            if let button { self?.clearStatusButtonHighlight(button) }
        }
        startAutoHideMonitor()
        if viaHotKey {
            // 点击应用外任意位置时收起（全局监听不会收到本应用内的点击）
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                Task { @MainActor in self?.closePopover() }
            }
        }
    }

    private func positionPopoverNearStatusItem() {
        guard let window = popover.contentViewController?.view.window,
              let buttonRect = statusButtonScreenRect() else { return }
        let screenFrame = screen(containing: buttonRect)?.visibleFrame
            ?? window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? window.frame
        let margin: CGFloat = 8
        let gap: CGFloat = 6

        var frame = window.frame
        frame.origin.x = buttonRect.midX - frame.width / 2
        frame.origin.x = min(
            max(frame.origin.x, screenFrame.minX + margin),
            screenFrame.maxX - frame.width - margin
        )

        let belowMenuBarY = buttonRect.minY - frame.height - gap
        let aboveButtonY = buttonRect.maxY + gap
        frame.origin.y = belowMenuBarY >= screenFrame.minY + margin
            ? belowMenuBarY
            : aboveButtonY
        frame.origin.y = min(
            max(frame.origin.y, screenFrame.minY + margin),
            screenFrame.maxY - frame.height - margin
        )

        window.setFrame(frame, display: true)
    }

    private func openOnMenuBarHoverIfNeeded() {
        requestHoverOpen()
    }

    /// 悬停打开的唯一入口：tracking-area 与轮询都走这里，统一处理「关闭后不立即重开」。
    private func requestHoverOpen() {
        guard !popover.isShown else { return }
        if suppressHoverReopen {
            // 光标仍停在图标上则保持抑制；离开后复位，下次再移入才会打开
            if !mouseIsOverStatusButton() { suppressHoverReopen = false }
            return
        }
        guard mouseIsOverStatusButton() else { return }
        showPopover()
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
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        openedViaHotKey = false
        suppressHoverReopen = true // 防止光标停在图标上时被轮询立刻重开
        keepOpenWhileSheetIsPresented = false
        popover.performClose(nil)
    }

    /// 每 0.2s 检查一次：鼠标既不在菜单栏按钮上、也不在面板内（含编辑 sheet）时收起。
    private func startAutoHideMonitor() {
        autoHideTimer?.invalidate()
        var graceTicks = 3 // 刚弹出后约 0.6s 宽限，避免从按钮移向面板途中被收起
        autoHideTimer = scheduleRepeatingTimer(interval: 0.2) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.popover.isShown else {
                    self?.autoHideTimer?.invalidate()
                    return
                }
                if graceTicks > 0 { graceTicks -= 1; return }
                let mouseInside = self.mouseIsOverButtonOrPanel()
                // 快捷键打开的面板：鼠标移入过面板之后才恢复「移出即收起」
                if self.openedViaHotKey && !self.hoveredSinceHotKeyOpen {
                    if mouseInside { self.hoveredSinceHotKeyOpen = true }
                    return
                }
                if !mouseInside {
                    self.closePopover()
                }
            }
        }
    }

    private func mouseIsOverButtonOrPanel() -> Bool {
        let mouse = NSEvent.mouseLocation
        if mouseIsOverStatusButton() {
            return true
        }
        if let panel = popover.contentViewController?.view.window {
            if keepOpenWhileSheetIsPresented, panel.attachedSheet != nil { return true }
            if let sheet = panel.attachedSheet,
               sheet.frame.insetBy(dx: -20, dy: -20).contains(mouse) {
                return true
            }
            if panel.frame.insetBy(dx: -20, dy: -20).contains(mouse) { return true }
        }
        return false
    }

    private func mouseIsOverStatusButton() -> Bool {
        guard let buttonRectOnScreen = statusButtonScreenRect() else { return false }
        return buttonRectOnScreen.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation)
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

extension Notification.Name {
    static let calendarPopoverSheetBehaviorChanged = Notification.Name("calendarPopoverSheetBehaviorChanged")
}
