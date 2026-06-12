// 生成应用图标：仿 macOS 日历风格（白色圆角卡片 + 红色头部 + 当日数字）
// 用法: swift scripts/make_icon.swift <输出目录>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let s = size
    // macOS 图标安全边距：内容占约 80%
    let inset = s * 0.10
    let card = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = s * 0.18

    // 阴影
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.shadowBlurRadius = s * 0.03
    shadow.set()

    // 白色卡片
    let cardPath = NSBezierPath(roundedRect: card, xRadius: radius, yRadius: radius)
    NSColor.white.setFill()
    cardPath.fill()

    NSShadow().set() // 清除阴影

    // 红色头部（顶部约 28%）
    let headerHeight = card.height * 0.28
    let header = NSRect(x: card.minX, y: card.maxY - headerHeight, width: card.width, height: headerHeight)
    let headerPath = NSBezierPath()
    headerPath.appendRoundedRect(header, topLeftRadius: radius, topRightRadius: radius)
    NSColor(calibratedRed: 0.95, green: 0.26, blue: 0.21, alpha: 1).setFill()
    headerPath.fill()

    // 头部文字「日历」
    let headerFont = NSFont.systemFont(ofSize: headerHeight * 0.52, weight: .semibold)
    let headerAttrs: [NSAttributedString.Key: Any] = [.font: headerFont, .foregroundColor: NSColor.white]
    let headerText = NSAttributedString(string: "日历", attributes: headerAttrs)
    let hSize = headerText.size()
    headerText.draw(at: NSPoint(x: header.midX - hSize.width / 2, y: header.midY - hSize.height / 2))

    // 日期数字
    let body = NSRect(x: card.minX, y: card.minY, width: card.width, height: card.height - headerHeight)
    let dayFont = NSFont.systemFont(ofSize: body.height * 0.66, weight: .light)
    let dayAttrs: [NSAttributedString.Key: Any] = [.font: dayFont, .foregroundColor: NSColor.black]
    let dayText = NSAttributedString(string: "12", attributes: dayAttrs)
    let dSize = dayText.size()
    dayText.draw(at: NSPoint(x: body.midX - dSize.width / 2, y: body.midY - dSize.height / 2 - body.height * 0.02))

    image.unlockFocus()
    return image
}

extension NSBezierPath {
    func appendRoundedRect(_ rect: NSRect, topLeftRadius r1: CGFloat, topRightRadius r2: CGFloat) {
        move(to: NSPoint(x: rect.minX, y: rect.minY))
        line(to: NSPoint(x: rect.maxX, y: rect.minY))
        line(to: NSPoint(x: rect.maxX, y: rect.maxY - r2))
        appendArc(withCenter: NSPoint(x: rect.maxX - r2, y: rect.maxY - r2), radius: r2, startAngle: 0, endAngle: 90)
        line(to: NSPoint(x: rect.minX + r1, y: rect.maxY))
        appendArc(withCenter: NSPoint(x: rect.minX + r1, y: rect.maxY - r1), radius: r1, startAngle: 90, endAngle: 180)
        close()
    }
}

func savePNG(_ image: NSImage, pixels: Int, name: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}

for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let px = points * scale
        let img = drawIcon(size: CGFloat(px))
        let suffix = scale == 1 ? "" : "@2x"
        savePNG(img, pixels: px, name: "icon_\(points)x\(points)\(suffix)")
    }
}
print("iconset 已生成: \(outDir)")
