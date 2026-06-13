import Foundation
import ServiceManagement

/// 开机时启动的辅助封装（基于 macOS 13+ 的 SMAppService.mainApp）。
/// 系统本身记录注册状态，因此以 `SMAppService.mainApp.status` 为唯一可信来源，
/// 不在本地额外持久化任何标记。
enum LaunchAtLogin {
    /// 当前是否已注册为开机启动项
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 注册开机启动；失败时记录错误，不让应用崩溃
    static func register() {
        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("开机启动注册失败：\(error.localizedDescription)")
        }
    }

    /// 取消开机启动；失败时记录错误，不让应用崩溃
    static func unregister() {
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            NSLog("开机启动取消失败：\(error.localizedDescription)")
        }
    }
}
