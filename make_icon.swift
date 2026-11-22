// Copyright 2026 The TypingGuard Authors
// SPDX-License-Identifier: Apache-2.0

// 生成 AppIcon.icns：swift make_icon.swift
// 蓝色渐变圆角底 + 白色键盘 + 右下角“禁止点击”角标
// 所有图形都是自己画的路径，没有使用 SF Symbols（Apple 不允许把 SF Symbols 用在应用图标里）
import Cocoa

let size = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// 底板（按 macOS 图标规范：1024 画布里放 824 的圆角方块，带一点投影）
let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
let platePath = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.shadowBlurRadius = 24
shadow.set()
NSColor(srgbRed: 0.16, green: 0.38, blue: 0.90, alpha: 1).setFill()
platePath.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(
    starting: NSColor(srgbRed: 0.36, green: 0.66, blue: 1.00, alpha: 1),
    ending: NSColor(srgbRed: 0.12, green: 0.30, blue: 0.84, alpha: 1)
)!.draw(in: platePath, angle: -90)

// 键盘：白色圆角矩形，按键用镂空（even-odd）露出底色
let keyboard = NSBezierPath(roundedRect: NSRect(x: 212, y: 380, width: 600, height: 360), xRadius: 60, yRadius: 60)
keyboard.windingRule = .evenOdd
func key(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 50) {
    keyboard.append(NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: 50), xRadius: 10, yRadius: 10))
}
for row in [630, 535] as [CGFloat] {
    for i in 0..<6 { key(272 + CGFloat(i) * 86, row) }
}
key(272, 440); key(358, 440, 308); key(702, 440)   // 最下一排：中间是空格键
NSColor.white.setFill()
keyboard.fill()

// 角标：白色圆底 + 鼠标指针 + 红色禁止符号（表示“拦截点击”）
let badgeCenter = NSPoint(x: 700, y: 330)
let badgeRadius: CGFloat = 150
NSGraphicsContext.saveGraphicsState()
let badgeShadow = NSShadow()
badgeShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
badgeShadow.shadowOffset = NSSize(width: 0, height: -6)
badgeShadow.shadowBlurRadius = 16
badgeShadow.set()
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: badgeCenter.x - badgeRadius, y: badgeCenter.y - badgeRadius,
                            width: badgeRadius * 2, height: badgeRadius * 2)).fill()
NSGraphicsContext.restoreGraphicsState()

// 指针箭头（自己画的多边形，单位坐标 12×20，y 向下）
let arrowUnit: [(CGFloat, CGFloat)] = [(0, 0), (0, 17), (4, 13.2), (7, 20), (9.6, 18.9), (6.7, 12.2), (12, 12)]
let arrowScale: CGFloat = 7.5
let arrowTip = NSPoint(x: badgeCenter.x - 6 * arrowScale, y: badgeCenter.y + 10 * arrowScale)
let arrow = NSBezierPath()
for (i, p) in arrowUnit.enumerated() {
    let pt = NSPoint(x: arrowTip.x + p.0 * arrowScale, y: arrowTip.y - p.1 * arrowScale)
    if i == 0 { arrow.move(to: pt) } else { arrow.line(to: pt) }
}
arrow.close()
arrow.lineJoinStyle = .round
NSColor(srgbRed: 0.20, green: 0.22, blue: 0.27, alpha: 1).setFill()
arrow.fill()

// 禁止符号：红圈 + 斜杠
let red = NSColor(srgbRed: 0.92, green: 0.26, blue: 0.24, alpha: 1)
let ringRadius: CGFloat = 104
let ring = NSBezierPath(ovalIn: NSRect(x: badgeCenter.x - ringRadius, y: badgeCenter.y - ringRadius,
                                       width: ringRadius * 2, height: ringRadius * 2))
ring.lineWidth = 24
let d = ringRadius * 0.7071
let slash = NSBezierPath()
slash.move(to: NSPoint(x: badgeCenter.x - d, y: badgeCenter.y + d))
slash.line(to: NSPoint(x: badgeCenter.x + d, y: badgeCenter.y - d))
slash.lineWidth = 24
red.setStroke()
ring.stroke()
slash.stroke()

NSGraphicsContext.restoreGraphicsState()

// 导出各尺寸并打包成 icns
let fm = FileManager.default
let iconset = "AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
let master = "\(iconset)/icon_512x512@2x.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: master))

func run(_ tool: String, _ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    try! p.run()
    p.waitUntilExit()
    precondition(p.terminationStatus == 0, "\(tool) 失败")
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                   ("128x128", 128), ("128x128@2x", 256), ("256x256", 256),
                   ("256x256@2x", 512), ("512x512", 512)] {
    run("/usr/bin/sips", ["-z", "\(px)", "\(px)", master, "--out", "\(iconset)/icon_\(name).png"])
}
run("/usr/bin/iconutil", ["-c", "icns", iconset, "-o", "AppIcon.icns"])
try? fm.removeItem(atPath: "docs/icon.png")
try? fm.copyItem(atPath: master, toPath: "docs/icon.png")
try? fm.removeItem(atPath: iconset)
print("已生成 AppIcon.icns")
