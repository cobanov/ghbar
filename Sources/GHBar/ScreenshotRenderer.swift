import AppKit
import SwiftUI
import Defaults

/// App Store ekran goruntuleri: `GHBar --render-screens <dizin>`.
///
/// Ekran yakalama (screencapture) TCC iznine takiliyor ve elle cekim her
/// surumde tekrarlanamiyor. Bunun yerine uygulamanin GERCEK SwiftUI
/// gorunumleri ekransiz render edilip markali 2880x1800 tuvale yerlestiriliyor
/// — piksel-kesin, izinsiz calisir ve `make screens` ile her surumde yeniden
/// uretilebilir.
@MainActor
enum ScreenshotRenderer {

    static let width: CGFloat = 1440    // mantiksal; cikti 2x = 2880x1800
    static let height: CGFloat = 900

    static func renderAll(to directory: String) {
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true
        )
        // Paket disinda applicationIconImage jenerik klasore duser; ikonu
        // diskten yukle — hem menu profili hem Welcome ayni kaynagi kullanir.
        if let icon = NSImage(contentsOfFile: "build/GHBar.icns") {
            NSApplication.shared.applicationIconImage = icon
        }
        seedSampleDefaults()

        let shots: [(String, String, String, NSImage)] = [
            ("1-menu",
             "Your repositories, at a glance",
             "Pull requests and issues from your repos — in the menu bar.",
             render(MenuReplicaView(), logicalWidth: 380)),
            ("2-repositories",
             "Silence the noisy repos",
             "Every repository GHBar has seen. Uncheck one to hide it.",
             // TabView ekransiz renderda ilk sekmeyi acar ve sekme cubugu
             // bozuk cizilir; paneli dogrudan kart icinde render ediyoruz.
             render(PaneCard { RepositoriesPane() }, logicalWidth: 470)),
            ("3-signin",
             "Sign in with GitHub",
             "Device flow sign-in — or your gh token, picked up automatically.",
             render(WelcomeView(onSignedIn: {}), logicalWidth: 340)),
        ]

        for (name, headline, sub, ui) in shots {
            let composed = compose(headline: headline, subheadline: sub, ui: ui)
            write(composed, to: "\(directory)/\(name).png")
            print("yazildi: \(directory)/\(name).png")
        }
    }

    /// Ayarlar panelleri Defaults'tan okur; bos gorunmesin diye ornek veri.
    private static func seedSampleDefaults() {
        Defaults[.signedInLogin] = "cobanov"
        Defaults[.knownRepos] = [
            "cobanov/herdrchat": 3,
            "cobanov/ghbar": 2,
            "cobanov/instagram": 1,
            "cobanov/paul-graham-turkce": 18,
            "cobanov/teslamate-mcp": 1,
        ]
        Defaults[.repoList] = ["cobanov/paul-graham-turkce"]
        Defaults[.accounts] = ["@me"]
    }

    // MARK: - Render altyapisi

    /// SwiftUI gorunumunu 2x yogunlukta bitmap'e cizer. Puf noktasi:
    /// pixelsWide'i iki kat verip rep.size'i mantiksal birakinca cacheDisplay
    /// Retina yogunlugunda cizer.
    private static func render(_ view: some View, logicalWidth: CGFloat) -> NSImage {
        let hosting = NSHostingView(rootView: view)
        let fitting = hosting.fittingSize
        let size = NSSize(width: max(logicalWidth, fitting.width),
                          height: max(200, fitting.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    /// Markali tuval: koyu zemin + yesil isik + baslik + golgeli UI karti.
    /// Site ve OG kartiyla ayni gorsel dil.
    private static func compose(headline: String, subheadline: String, ui: NSImage) -> NSImage {
        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = NSSize(width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        // Zemin
        NSColor(srgbRed: 0.051, green: 0.059, blue: 0.075, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGradient(
            starting: NSColor(srgbRed: 0.18, green: 0.75, blue: 0.38, alpha: 0.14),
            ending: .clear
        )?.draw(fromCenter: NSPoint(x: width * 0.85, y: height * 0.9), radius: 0,
                toCenter: NSPoint(x: width * 0.85, y: height * 0.9), radius: 700,
                options: [])

        // Basliklar
        func draw(_ text: String, size: CGFloat, weight: NSFont.Weight,
                  color: NSColor, y: CGFloat) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color,
                .kern: size * -0.02,
            ]
            NSAttributedString(string: text, attributes: attributes)
                .draw(at: NSPoint(x: 96, y: y))
        }
        draw(headline, size: 52, weight: .bold, color: .white, y: height - 140)
        draw(subheadline, size: 24, weight: .regular,
             color: NSColor(srgbRed: 0.62, green: 0.66, blue: 0.72, alpha: 1),
             y: height - 184)

        // UI karti — golgeyle ortala (baslik alani haric)
        let available = height - 240
        var uiSize = ui.size
        let maxHeight = available - 60
        if uiSize.height > maxHeight {
            let factor = maxHeight / uiSize.height
            uiSize = NSSize(width: uiSize.width * factor, height: uiSize.height * factor)
        }
        let uiOrigin = NSPoint(x: (width - uiSize.width) / 2,
                               y: (available - uiSize.height) / 2 + 40)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = 42
        shadow.shadowOffset = NSSize(width: 0, height: -14)
        NSGraphicsContext.current?.saveGraphicsState()
        shadow.set()
        ui.draw(in: NSRect(origin: uiOrigin, size: uiSize))
        NSGraphicsContext.current?.restoreGraphicsState()

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }

    private static func write(_ image: NSImage, to path: String) {
        guard let rep = image.representations.first as? NSBitmapImageRep,
              let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

/// Ayar panelini pencere benzeri karta saran render yardimcisi.
struct PaneCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(width: 470, height: 460)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: NSColor(srgbRed: 0.13, green: 0.14, blue: 0.16, alpha: 1)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .environment(\.colorScheme, .dark)
    }
}

// MARK: - Menu replikasi

/// Menunun SwiftUI replikasi. NSMenu ekransiz render EDILEMEZ (pencere ister);
/// bu gorunum ayni yazi tipleri, semboller, renkler ve gercekci veriyle ayni
/// gorseli uretir.
struct MenuReplicaView: View {

    private struct Row: Identifiable {
        let id = UUID()
        let symbol: String
        let label: String
        let detail: String
        let age: String
        var unseen = true
        var isGroup = false
        var count: Int? = nil
    }

    private let prs: [Row] = [
        .init(symbol: "arrow.trianglehead.pull", label: "herdrchat #55",
              detail: "Let the last row scroll clear…", age: "2h"),
        .init(symbol: "arrow.trianglehead.pull", label: "ghbar #12",
              detail: "Add keyboard navigation", age: "5h"),
        .init(symbol: "arrow.trianglehead.pull", label: "instagram #3",
              detail: "fix: cache-control headers", age: "1d", unseen: false),
    ]
    private let issues: [Row] = [
        .init(symbol: "smallcircle.filled.circle", label: "teslamate-mcp #8",
              detail: "Optional sponsored field", age: "3d"),
        .init(symbol: "folder", label: "paul-graham-turkce", detail: "", age: "",
              unseen: false, isGroup: true, count: 18),
    ]
    private let review: [Row] = [
        .init(symbol: "arrow.trianglehead.pull", label: "dataland/api #204",
              detail: "Refactor auth middleware", age: "4h"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text("Mert Cobanov").fontWeight(.medium)
                Text("@cobanov").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)

            divider

            section("Pull Requests", rows: prs)
            markAll
            divider
            section("Issues", rows: issues)
            markAll
            divider
            section("Review Requested", rows: review)
            markAll
            divider

            sectionHeader("API")
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.needle")
                    .foregroundStyle(.secondary).frame(width: 16)
                Text("Rate Limit").foregroundStyle(.secondary)
                Text("4,987 / 5,000").foregroundStyle(.tertiary)
                Spacer()
                Text("resets 42m").foregroundStyle(.tertiary).font(.system(size: 11))
            }
            .padding(.horizontal, 12).padding(.vertical, 4)

            divider
            plain("Open GitHub", symbol: "globe")
            plain("Refresh", symbol: "arrow.clockwise")
            plain("Settings…", symbol: "gearshape")
        }
        .font(.system(size: 13))
        .padding(.vertical, 8)
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: NSColor(srgbRed: 0.16, green: 0.17, blue: 0.19, alpha: 1)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1)
            .padding(.horizontal, 10).padding(.vertical, 4)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 2)
    }

    private func section(_ title: String, rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionHeader(title)
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Image(systemName: row.symbol)
                        .foregroundStyle(row.unseen ? Color(nsColor: .systemGreen) : Color.secondary)
                        .frame(width: 16)
                        .font(.system(size: 12))
                    Text(row.label)
                        .fontWeight(row.unseen ? .medium : .regular)
                        .foregroundStyle(row.unseen ? .primary : .secondary)
                    if row.isGroup, let count = row.count {
                        Spacer()
                        Text("\(count)").foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9)).foregroundStyle(.tertiary)
                    } else {
                        Text(row.detail).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text(row.age).foregroundStyle(.tertiary).font(.system(size: 11))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 3.5)
            }
        }
    }

    private var markAll: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary).frame(width: 16).font(.system(size: 12))
            Text("Mark All as Seen").foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 3.5)
    }

    private func plain(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary).frame(width: 16).font(.system(size: 12))
            Text(title)
        }
        .padding(.horizontal, 12).padding(.vertical, 3.5)
    }
}
