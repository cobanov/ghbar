#!/usr/bin/env swift
// 1200x630 Open Graph image, in the site's look: the green desktop, the menu bar, and the
// panel hanging from GHBar's status item. Run from the repository root: swift Tools/makeog.swift
import AppKit

let W: CGFloat = 1200, H: CGFloat = 630
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * 2), pixelsHigh: Int(H * 2),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let field = NSColor(srgbRed: 0x13 / 255.0, green: 0x61 / 255.0, blue: 0x2e / 255.0, alpha: 1)
field.setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, width: NSFont.Width = .standard,
          alpha: CGFloat = 1, kern: CGFloat = 0) -> NSAttributedString {
    let font = NSFont.systemFont(ofSize: size, weight: weight, width: width)
    return NSAttributedString(string: s, attributes: [
        .font: font, .foregroundColor: NSColor.white.withAlphaComponent(alpha), .kern: kern,
    ])
}

// Menu bar
let bar: CGFloat = 34
NSColor.black.withAlphaComponent(0.2).setFill()
NSRect(x: 0, y: H - bar, width: W, height: bar).fill()
text("GHBar", size: 15, weight: .bold).draw(at: NSPoint(x: 22, y: H - bar + 8))
text("Install", size: 15, weight: .regular).draw(at: NSPoint(x: 92, y: H - bar + 8))
let clock = text("Tue 21:04", size: 15, weight: .regular)
clock.draw(at: NSPoint(x: W - 22 - clock.size().width, y: H - bar + 8))
let count = text("10", size: 15, weight: .medium)
let itemRight = W - 22 - clock.size().width - 16
let itemWidth: CGFloat = 20 + 4 + count.size().width + 18
let item = NSRect(x: itemRight - itemWidth, y: H - bar + 5, width: itemWidth, height: 24)
NSColor.white.withAlphaComponent(0.22).setFill()
NSBezierPath(roundedRect: item, xRadius: 6, yRadius: 6).fill()
// GitHub's pull request glyph, drawn as strokes in a 16-point box.
do {
    let o = NSPoint(x: item.minX + 9, y: item.midY - 8)
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: o.x + x, y: o.y + 16 - y) }
    let path = NSBezierPath()
    path.lineWidth = 1.5
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    for c in [p(4, 3.5), p(4, 12.5), p(12, 12.5)] {
        path.appendOval(in: NSRect(x: c.x - 1.9, y: c.y - 1.9, width: 3.8, height: 3.8))
    }
    path.move(to: p(4, 5.4)); path.line(to: p(4, 10.6))
    path.move(to: p(12, 10.6)); path.line(to: p(12, 6))
    path.curve(to: p(10, 3.5), controlPoint1: p(12, 4.6), controlPoint2: p(11.2, 3.5))
    path.line(to: p(7.5, 3.5))
    path.move(to: p(9, 2)); path.line(to: p(7.5, 3.5)); path.line(to: p(9, 5))
    NSColor.white.setStroke()
    path.stroke()
}
count.draw(at: NSPoint(x: item.minX + 9 + 18, y: H - bar + 8))

// The panel, rendered by the app itself (GHBar --render-panel assets/panel.png), its arrow
// under the status item.
if let panel = NSImage(contentsOfFile: "assets/panel.png") {
    let size = NSSize(width: 380, height: 433)
    let x = min(item.midX - size.width * 0.79, W - 16 - size.width)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    panel.draw(in: NSRect(x: x, y: H - bar - 3 - size.height, width: size.width, height: size.height))
    NSGraphicsContext.restoreGraphicsState()
}

// Headline
var y: CGFloat = 360
for line in ["Pull requests", "people send you,", "in your menu bar."] {
    text(line, size: 60, weight: .heavy, width: .expanded, kern: -1.6).draw(at: NSPoint(x: 64, y: y))
    y -= 66
}
text("Free and open source for macOS.  ghbar.cobanov.dev", size: 22, weight: .regular, alpha: 0.78)
    .draw(at: NSPoint(x: 66, y: 168))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "site/assets/og.png"))
print("site/assets/og.png written (\(Int(W))x\(Int(H)) @2x)")
