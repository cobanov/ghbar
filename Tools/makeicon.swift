#!/usr/bin/env swift
//
// GHBar uygulama ikonunu uretir.
//
// Harici bir cizim araci yerine AppKit kullaniliyor: makinede zaten var,
// her boyut tam kontrolle ciziliyor ve sonuc dogrudan .iconset klasoru.
//
//   swift Tools/makeicon.swift  ->  build/GHBar.iconset
//   iconutil -c icns build/GHBar.iconset -o Resources/GHBar.icns
//
import AppKit

// MARK: - Palet

let accent      = NSColor(srgbRed: 0.18, green: 0.72, blue: 0.42, alpha: 1)  // yesil
let accentDeep  = NSColor(srgbRed: 0.09, green: 0.52, blue: 0.30, alpha: 1)
let plateTop    = NSColor(srgbRed: 0.13, green: 0.15, blue: 0.18, alpha: 1)  // grafit
let plateBottom = NSColor(srgbRed: 0.07, green: 0.08, blue: 0.10, alpha: 1)

// MARK: - Cizim

/// macOS ikonlari kenarlarda seffaf pay birakir; 1024'luk tuvalde
/// gorunur alan ~824 px olur. Bu oran korunmazsa ikon Dock'ta
/// komsularindan buyuk gorunur.
func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let context = NSGraphicsContext.current?.cgContext else { return image }
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    let inset = size * 0.098
    let plateRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = plateRect.width * 0.2237      // Apple'in squircle orani

    // Grafit zemin
    let plate = NSBezierPath(roundedRect: plateRect, xRadius: radius, yRadius: radius)
    plate.addClip()
    let plateGradient = NSGradient(starting: plateTop, ending: plateBottom)!
    plateGradient.draw(in: plateRect, angle: -90)

    // Ust kenarda ince isik cizgisi — duz zeminlere derinlik verir
    context.saveGState()
    let highlight = NSBezierPath(
        roundedRect: plateRect.insetBy(dx: size * 0.006, dy: size * 0.006),
        xRadius: radius, yRadius: radius
    )
    highlight.lineWidth = size * 0.006
    NSColor(white: 1, alpha: 0.10).setStroke()
    highlight.stroke()
    context.restoreGState()

    // MARK: Pull-request isareti
    //
    // Iki dikey dal ve aralarinda bir birlesme kavsi; ucta ve diplerde
    // daireler. Menudeki arrow.trianglehead.pull sembolunun sadelestirilmis
    // hali — uygulamayla ayni dili konusuyor.

    let stroke = size * 0.062
    let dotR   = size * 0.058
    let leftX  = plateRect.midX - size * 0.152
    let rightX = plateRect.midX + size * 0.152
    let topY   = plateRect.midY + size * 0.176
    let botY   = plateRect.midY - size * 0.176

    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineWidth(stroke)

    // Sol dal: yukaridan asagi duz
    accent.setStroke()
    let left = NSBezierPath()
    left.lineWidth = stroke
    left.lineCapStyle = .round
    left.move(to: CGPoint(x: leftX, y: topY - dotR * 0.2))
    left.line(to: CGPoint(x: leftX, y: botY + dotR * 0.2))
    left.stroke()

    // Sag dal: yukaridan iner, sola kivrilip sol dala baglanir
    accentDeep.setStroke()
    let right = NSBezierPath()
    right.lineWidth = stroke
    right.lineCapStyle = .round
    right.move(to: CGPoint(x: rightX, y: topY - dotR * 0.2))
    right.line(to: CGPoint(x: rightX, y: plateRect.midY + size * 0.02))
    right.curve(
        to: CGPoint(x: leftX + size * 0.052, y: botY + size * 0.052),
        controlPoint1: CGPoint(x: rightX, y: botY + size * 0.062),
        controlPoint2: CGPoint(x: leftX + size * 0.150, y: botY + size * 0.052)
    )
    right.stroke()

    // Daireler
    func dot(_ x: CGFloat, _ y: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)).fill()
        plateBottom.setFill()
        let inner = dotR * 0.42
        NSBezierPath(ovalIn: CGRect(x: x - inner, y: y - inner, width: inner * 2, height: inner * 2)).fill()
    }
    dot(leftX,  topY, accent)
    dot(rightX, topY, accentDeep)
    dot(leftX,  botY, accent)

    return image
}

// MARK: - Yazma

func png(_ image: NSImage, _ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: CGFloat(pixels)).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let outputDirectory = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "build/GHBar.iconset"

try? FileManager.default.createDirectory(
    atPath: outputDirectory, withIntermediateDirectories: true
)

// iconutil'in bekledigi tam dosya adlari
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16",      16), ("icon_16x16@2x",     32),
    ("icon_32x32",      32), ("icon_32x32@2x",     64),
    ("icon_128x128",   128), ("icon_128x128@2x",  256),
    ("icon_256x256",   256), ("icon_256x256@2x",  512),
    ("icon_512x512",   512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    let data = png(NSImage(), variant.pixels)
    let path = "\(outputDirectory)/\(variant.name).png"
    try! data.write(to: URL(fileURLWithPath: path))
    print("  \(variant.name).png  (\(variant.pixels)px, \(data.count / 1024) KB)")
}
print("iconset hazir: \(outputDirectory)")
