# 日历（menubar-calendar）

macOS 菜单栏日历，SwiftUI + SwiftPM 构建，无需 Xcode 工程。

![platform](https://img.shields.io/badge/macOS-14%2B-blue)

## 功能

- 菜单栏显示日期时间，悬停 / 点击 / 全局快捷键 **⌃⌥C** 呼出面板
- 紧凑月历 + 当日与即将到来的日程列表
- 中国法定节假日「休 / 班」角标（内置 2025–2026 官方数据，来源：国务院办公厅通知）
- 系统日历（EventKit）双向同步；未授权时本地 JSON 存储
- 双击日期格子快速新建日程；日程行拖拽到任意日期改期
- 自定义事件颜色、时区切换、每周起始日（周日 / 周一）设置
- Sparkle 自动更新

## 安装

从 [Releases](../../releases) 下载 `Calendar.zip`，解压后把 `日历.app` 拖进「应用程序」，直接双击打开即可。

> 应用已用 Apple Developer ID 签名并经过公证（notarized），下载后无需任何额外操作。

## 本地构建

```bash
./build_app.sh        # 产物在 build/日历.app
```

## 日历授权排障

### 授权修复要点

这个 App 是无 Dock 图标的菜单栏应用（`LSUIElement` / accessory 模式），如果启动时或非前台状态下直接请求 EventKit 权限，macOS 可能不会显示授权弹窗，表现为“点了授权但没有反应”。当前修复做了几件事：

- 打包签名时给主 App 带上 `com.apple.security.personal-information.calendars` entitlement，并在 `Info.plist` 写入日历用途说明。
- 启动时只在已授权的情况下静默连接系统日历；未授权的新用户必须在设置里主动点“去授权”，避免后台请求浪费系统弹窗机会。
- 点“去授权”时临时把应用切到前台 regular 模式，并显示一个“日历权限”锚点窗口，再调用 `requestFullAccessToEvents()`，确保系统授权弹窗能正常出现。
- 授权完成后重新创建 `EKEventStore` 并重新订阅 `.EKEventStoreChanged`，避免旧 store 状态缓存导致授权后仍读不到日历。
- 如果权限是“仅添加事件”、已拒绝或受限制，会打开系统设置的日历隐私页，并在设置界面显示当前状态。
- 授权成功后会把本地 JSON 模式下创建的日程导入系统日历，避免切换到 EventKit 后本地日程从界面消失。

如果曾运行过未带 Calendar entitlement 的旧版包，macOS 可能缓存了拒绝结果。更新到新版后仍不弹权限框时，可定向重置本应用的日历授权记录：

```bash
tccutil reset Calendar com.xiaobo.calendarapp
```

## 发布流程

参考 [macuhy/macos-app-release-kit](https://github.com/macuhy/macos-app-release-kit)：

```bash
git tag v1.1.0 && git push origin v1.1.0
```

GitHub Actions 会自动：测试 → 编译 → 打包 → Sparkle EdDSA 签名 → 创建 Release → 更新 `appcast.xml`。
已安装的 App 之后会通过 Sparkle 弹窗提示更新。

- 版本号取自 tag（`v1.1.0` → `CFBundleShortVersionString=1.1.0`）
- build 号用 `git rev-list --count HEAD` 自动生成，保证递增
- Sparkle 命令行工具版本从 `Package.resolved` 的 Sparkle pin 读取，避免与依赖版本漂移
- Sparkle 签名需要仓库 Secret：`SPARKLE_PRIVATE_KEY`
- Developer ID 签名和公证需要 workflow 顶部列出的 Apple/证书相关 Secrets
