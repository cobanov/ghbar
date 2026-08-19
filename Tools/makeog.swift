#!/usr/bin/env swift
// 1200x630 Open Graph gorseli — sitenin karanlik paletiyle.
import AppKit

let W: CGFloat = 1200, H: CGFloat = 630
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W*2), pixelsHigh: Int(H*2),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Zemin: sitedeki --bg + yesil radial isik
NSColor(srgbRed: 0.051, green: 0.059, blue: 0.075, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()
let glow = NSGradient(starting: NSColor(srgbRed: 0.18, green: 0.75, blue: 0.38, alpha: 0.16),
                      ending: .clear)!
glow.draw(fromCenter: NSPoint(x: W*0.82, y: H*0.85), radius: 0,
          toCenter: NSPoint(x: W*0.82, y: H*0.85), radius: 620, options: [])

// Ikon (buyuk boy iconset'ten)
if let icon = NSImage(contentsOfFile: "build/GHBar.iconset/icon_512x512.png") {
    icon.draw(in: NSRect(x: 96, y: H-96-176, width: 176, height: 176))
}

// Baslik + alt baslik
func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .kern: size * -0.02,
    ]
    NSAttributedString(string: text, attributes: attrs)
        .draw(at: NSPoint(x: 96, y: y))
}
draw("GHBar", size: 96, weight: .bold, color: .white, y: 236)
draw("Pull requests and issues", size: 46, weight: .medium,
     color: NSColor(srgbRed: 0.93, green: 0.95, blue: 0.96, alpha: 1), y: 152)
draw("in your macOS menu bar.", size: 46, weight: .medium,
     color: NSColor(srgbRed: 0.93, green: 0.95, blue: 0.96, alpha: 1), y: 96)
draw("Free · Open source · ghbar.cobanov.dev", size: 26, weight: .regular,
     color: NSColor(srgbRed: 0.42, green: 0.75, blue: 0.53, alpha: 1), y: 34)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "site/assets/og.png"))
print("site/assets/og.png yazildi (\(Int(W))x\(Int(H)) @2x)")
