#!/bin/zsh
# Build the SPM executable and package it as 日历.app
# 可用环境变量覆盖版本号（CI 用）：VERSION=1.2.0 BUILD_NUMBER=42 ./build_app.sh
set -e
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APPCAST_URL="${APPCAST_URL:-https://raw.githubusercontent.com/macuhy/menubar-calendar/main/appcast.xml}"
SPARKLE_PUBLIC_KEY="QxXWME0pGom6NLGkoNq6AdkK8h+i+ZttNeED2No5HT8="

swift build -c release

APP="build/日历.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp .build/release/CalendarApp "$APP/Contents/MacOS/CalendarApp"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# 嵌入 Sparkle.framework（SPM 二进制 artifact）
SPARKLE_FRAMEWORK="$(find .build -type d -name 'Sparkle.framework' -path '*macos*' | head -1)"
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
    echo "找不到 Sparkle.framework，请先 swift build -c release" >&2
    exit 1
fi
cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>CalendarApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.xiaobo.calendarapp</string>
    <key>CFBundleName</key>
    <string>日历</string>
    <key>CFBundleDisplayName</key>
    <string>日历</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
    <key>NSCalendarsUsageDescription</key>
    <string>需要访问系统日历，以显示并双向同步你的日程。</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>需要访问系统日历，以显示并双向同步你的日程。</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>SUFeedURL</key>
    <string>${APPCAST_URL}</string>
    <key>SUPublicEDKey</key>
    <string>${SPARKLE_PUBLIC_KEY}</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
    <key>SUAutomaticallyUpdate</key>
    <false/>
    <key>SUVerifyUpdateBeforeExtraction</key>
    <true/>
</dict>
</plist>
PLIST

# 签名：本地默认 ad-hoc（够本机跑）；CI 传 SIGN_IDENTITY 时用 Developer ID + Hardened Runtime（公证前置条件）
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - "$APP"
else
    FW="$APP/Contents/Frameworks/Sparkle.framework"
    V="$FW/Versions/B"
    RT=(--options runtime --timestamp)
    # 由内到外逐个签名；Sparkle 两个 XPC 服务保留各自（含沙盒）entitlements
    codesign --force "${RT[@]}" --preserve-metadata=entitlements --sign "$SIGN_IDENTITY" "$V/XPCServices/Downloader.xpc"
    codesign --force "${RT[@]}" --preserve-metadata=entitlements --sign "$SIGN_IDENTITY" "$V/XPCServices/Installer.xpc"
    codesign --force "${RT[@]}" --sign "$SIGN_IDENTITY" "$V/Updater.app"
    codesign --force "${RT[@]}" --sign "$SIGN_IDENTITY" "$V/Autoupdate"
    codesign --force "${RT[@]}" --sign "$SIGN_IDENTITY" "$FW"
    codesign --force "${RT[@]}" --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP"
fi
echo "打包完成: $PWD/$APP (v${VERSION} build ${BUILD_NUMBER}, 签名: $SIGN_IDENTITY)"
