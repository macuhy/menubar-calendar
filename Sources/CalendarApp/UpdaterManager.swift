//  通用 Sparkle 自动更新管理器（来自 macos-app-release-kit 模板，按本项目调整）
//  配套: Info.plist 中需配置 SUFeedURL / SUPublicEDKey（由 build_app.sh 写入）

import SwiftUI
import Sparkle

/// 包装 Sparkle 的标准更新控制器。
/// - 打包后的 App（Info.plist 含 SUFeedURL）启动即按 SUScheduledCheckInterval 自动检查并弹窗。
/// - `swift run` 直接跑可执行文件时没有 SUFeedURL，不启动 updater，避免报错弹窗。
final class UpdaterManager: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    /// 手动「检查更新」按钮是否可点（Sparkle 正在检查时自动置灰）。
    @Published var canCheckForUpdates = false

    init() {
        let hasFeed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        updaterController = SPUStandardUpdaterController(
            startingUpdater: hasFeed,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// 手动触发一次更新检查（弹出 Sparkle 标准 UI）。
    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }
}
