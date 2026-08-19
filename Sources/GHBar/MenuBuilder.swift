import AppKit

@MainActor
final class MenuBuilder {

    /// Menu ogelerinin hedefi; tiklama eylemleri AppDelegate'te.
    private weak var target: AnyObject?

    init(target: AnyObject) {
        self.target = target
    }

    struct Input {
        var viewer: Viewer?
        var sections: [MenuSection]
        var rateLimit: RateLimit?
        var errors: [AppError]
        var lastRefresh: Date?
        var isSignedOut: Bool
        var isRefreshing: Bool = false
        var showOwner: Bool
        var knownOrganizations: [String] = []
        var selectedOrganizations: [String] = []
        /// Repo beyaz/kara listesi sonucu daraltiyor mu; bos menunun nedenini
        /// dogru soyleyebilmek icin gerekiyor.
        var repositoryFilterActive: Bool = false
        var visibleSections: Set<SectionKind>
        /// Acikken bos bolum basligi ve "None" satiri korunur.
        var showEmptySections: Bool = false
        var maxRowsPerSection: Int
        var isSeen: (String) -> Bool
        var now: Date
    }

    func build(_ input: Input) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if input.isSignedOut {
            let signIn = action("Sign in to GitHub…", #selector(AppDelegate.openWelcome))
            signIn.image = Icons.symbol("person.crop.circle.badge.plus", color: .systemGreen)
            menu.addItem(signIn)
            menu.addItem(.separator())
        } else if let viewer = input.viewer {
            menu.addItem(profileItem(viewer))
            if !input.knownOrganizations.isEmpty {
                menu.addItem(organizationsItem(input))
            }
            // Org secimi ag turunu bekliyor. Bu satir olmadan menu, tiklama
            // hic islenmemis gibi eski sonuclari gosteriyor.
            if input.isRefreshing {
                let row = disabled("Refreshing…")
                row.image = Icons.symbol("arrow.clockwise", color: .secondaryLabelColor)
                menu.addItem(row)
            }
            menu.addItem(.separator())
        }

        if !input.errors.isEmpty {
            for error in input.errors { menu.addItem(errorItem(error)) }
            // Eski veri gosterilirken ne kadar eski oldugu soylenmeli; yoksa
            // kullanici bayat listeyi guncel sanir.
            if let last = input.lastRefresh {
                menu.addItem(disabled("Last updated \(Self.clock.string(from: last))"))
            }
            menu.addItem(.separator())
        }

        if input.errors.isEmpty && !input.isSignedOut {
            // Bos bolum varsayilan olarak hic cizilmez: bes bolum bir arada
            // bosken menu bes baslik ve bes gri satirdan ibaret kaliyor ve
            // bozuk gorunuyordu. Ayar acikken kullanicinin sectigi her bolum
            // "None" satiriyla gorunur kalir.
            let kinds = SectionKind.allCases.filter { kind in
                input.showEmptySections
                    ? input.visibleSections.contains(kind)
                    : input.sections.contains { $0.kind == kind }
            }
            for kind in kinds { addSection(kind, to: menu, input: input) }
            if kinds.isEmpty {
                for item in emptyStateItems(input) { menu.addItem(item) }
                menu.addItem(.separator())
            }
        } else {
            // Hata sirasinda eksik bolume "None" demek yaniltici olur:
            // GitHub'a bakamadik, gercekten bos oldugunu bilmiyoruz.
            for section in input.sections {
                addSection(section.kind, to: menu, input: input)
            }
        }

        if let rateLimit = input.rateLimit {
            menu.addItem(.sectionHeader(title: "API"))
            menu.addItem(rateLimitItem(rateLimit, now: input.now))
            menu.addItem(.separator())
        }

        // Kisayollar geri geldi: alt menu oku sutunu ("7 more…" ve repo
        // gruplari) sagda zaten yer ayirttigi icin kisayol sutunu ekstra
        // genislik katmiyor — ayni boslugu islevle dolduruyor.
        menu.addItem(action("Open GitHub", #selector(AppDelegate.openProfile), key: "o"))
        menu.addItem(action("Refresh", #selector(AppDelegate.refreshNow), key: "r"))
        menu.addItem(action("Settings…", #selector(AppDelegate.openSettings), key: ","))

        if LaunchAtLogin.isAvailable {
            // Tik, NSMenuItem.state yerine gorsel sutununda: state kullanmak
            // menuye AYRI bir durum sutunu ekletiyor ve butun satirlari saga
            // kaydiriyor. Gorsel sutunu zaten var, bedava.
            let launch = action("Launch at Login", #selector(AppDelegate.toggleLaunchAtLogin))
            launch.image = LaunchAtLogin.isEnabled
                ? Icons.symbol("checkmark", color: .labelColor)
                : Icons.blank
            menu.addItem(launch)
        }

        menu.addItem(.separator())
        menu.addItem(disabled("GHBar \(AppVersion.current)"))
        menu.addItem(action("Quit GHBar", #selector(AppDelegate.quit), key: "q"))
        return menu
    }

    // MARK: - Bolum satirlari

    private func addSection(_ kind: SectionKind, to menu: NSMenu, input: Input) {
        menu.addItem(.sectionHeader(title: kind.title))
        guard let section = input.sections.first(where: { $0.kind == kind }) else {
            menu.addItem(disabled("None"))
            menu.addItem(.separator())
            return
        }
        addRows(of: section, to: menu, input: input)
        if section.truncated {
            menu.addItem(disabled("Showing first 100 — narrow your filters"))
        }
        menu.addItem(markAllSeenItem(for: section))
        menu.addItem(.separator())
    }

    /// Bos menu neden bos oldugunu soylemeli. Bir filtre sorumluysa filtrenin
    /// adi ve geri alma yolu ayni yerde durur; kullanici ayarlari arayarak
    /// bulmak zorunda kalmaz.
    private func emptyStateItems(_ input: Input) -> [NSMenuItem] {
        if !input.selectedOrganizations.isEmpty {
            let scope = input.selectedOrganizations.count == 1
                ? input.selectedOrganizations[0]
                : "\(input.selectedOrganizations.count) organizations"
            let undo = action("Show All Organizations",
                              #selector(AppDelegate.clearOrganizations))
            undo.image = Icons.blank
            return [caughtUpItem("No open work in \(scope)"), undo]
        }

        if input.repositoryFilterActive {
            let settings = action("Open Settings…", #selector(AppDelegate.openSettings))
            settings.image = Icons.blank
            return [caughtUpItem("No open work in the watched repositories"), settings]
        }

        return [caughtUpItem("You're all caught up")]
    }

    private func caughtUpItem(_ title: String) -> NSMenuItem {
        let item = disabled(title)
        item.image = Icons.symbol("checkmark.circle", color: .secondaryLabelColor)
        return item
    }

    private func addRows(of section: MenuSection, to menu: NSMenu, input: Input) {
        let visible = section.rows.prefix(input.maxRowsPerSection)
        for row in visible {
            menu.addItem(item(for: row, input: input))
        }

        let overflow = section.rows.count - visible.count
        guard overflow > 0 else { return }

        let more = NSMenuItem(title: "\(overflow) more…", action: nil, keyEquivalent: "")
        more.image = Icons.blank   // ikonlu satirlarla ayni hizada baslasin
        let submenu = NSMenu()
        for row in section.rows.dropFirst(visible.count) {
            submenu.addItem(item(for: row, input: input))
        }
        more.submenu = submenu
        menu.addItem(more)
    }

    private func item(for row: Row, input: Input) -> NSMenuItem {
        switch row {
        case .item(let entry):
            return itemRow(entry, input: input)

        case .group(let repository, let items):
            let unseen = items.contains { !input.isSeen($0.url) }
            let name = input.showOwner
                ? repository
                : (repository.split(separator: "/").last.map(String.init) ?? repository)

            let text = NSMutableAttributedString(
                string: TextFit.truncate(name, font: MenuFont.label,
                                         maxWidth: MenuFont.rowWidth * 0.7),
                attributes: [
                    .font: MenuFont.label,
                    .foregroundColor: unseen ? NSColor.labelColor : NSColor.secondaryLabelColor,
                ]
            )
            text.append(NSAttributedString(
                string: "\t\(items.count)",
                attributes: [.font: MenuFont.detail, .foregroundColor: NSColor.secondaryLabelColor]
            ))
            text.addAttribute(.paragraphStyle, value: MenuFont.rowStyle,
                              range: NSRange(location: 0, length: text.length))

            let menuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            menuItem.attributedTitle = text
            menuItem.image = Icons.folder(unseen: unseen)
            let submenu = NSMenu()
            for entry in items { submenu.addItem(itemRow(entry, input: input)) }
            menuItem.submenu = submenu
            return menuItem
        }
    }

    /// Bir PR/issue satiri. Genisligin tamami punto ile olculuyor:
    ///
    ///   [etiket][  ][baslik — kalan boslugu doldurur][sekme][yas]
    ///
    /// Yas, rowWidth'teki saga yasli sekme duraginda bitiyor; baslik ise
    /// "rowWidth - etiket - yas - nefes payi" kadar yer kaplayacak sekilde
    /// olculup kirpiliyor. Onceki surum basligi KARAKTER sayisiyla kirpiyordu
    /// ve karakter ile punto ayni sey olmadigi icin kimi satir duraktan cok
    /// once bitip ortada delik birakiyor, kimi duragi asip yasin ustune
    /// yapisiyordu. Olcum gercek yazi tipiyle yapilinca satirlar iki kenara
    /// birden yasli oluyor.
    private func itemRow(_ entry: Item, input: Input) -> NSMenuItem {
        let seen = input.isSeen(entry.url)
        let age = Formatting.age(of: entry.createdAt, now: input.now)

        // Repo adi en fazla satirin yarisi; numara asla kirpilmaz.
        let suffix = " #\(entry.number)"
        let nameRoom = MenuFont.rowWidth * 0.5 - TextFit.width(of: suffix, font: MenuFont.label)
        let name = input.showOwner ? entry.repository : entry.repositoryName
        let label = TextFit.truncate(name, font: MenuFont.label, maxWidth: nameRoom) + suffix

        let lead = "  "
        let breathing: CGFloat = 14   // baslik ile yas arasindaki asgari bosluk
        let titleRoom = MenuFont.rowWidth
            - TextFit.width(of: label, font: MenuFont.label)
            - TextFit.width(of: lead, font: MenuFont.detail)
            - TextFit.width(of: age, font: MenuFont.detail)
            - breathing
        let title = TextFit.truncate(entry.title, font: MenuFont.detail,
                                     maxWidth: max(40, titleRoom))

        let text = NSMutableAttributedString(
            string: label,
            attributes: [
                .font: MenuFont.label,
                .foregroundColor: seen ? NSColor.secondaryLabelColor : NSColor.labelColor,
            ]
        )
        text.append(NSAttributedString(
            string: "\(lead)\(title)\t\(age)",
            attributes: [
                .font: MenuFont.detail,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        ))
        text.addAttribute(.paragraphStyle, value: MenuFont.rowStyle,
                          range: NSRange(location: 0, length: text.length))

        let menuItem = NSMenuItem(
            title: "",
            action: #selector(AppDelegate.openItem(_:)),
            keyEquivalent: ""
        )
        menuItem.attributedTitle = text
        menuItem.target = target
        menuItem.representedObject = entry
        menuItem.image = Icons.forItem(entry, seen: seen)
        // Kirpilan basligin tam hali fare uzerine gelince gorunur.
        menuItem.toolTip = "\(entry.title)\n@\(entry.authorLogin)"
        return menuItem
    }

    // MARK: - Diger satirlar

    private func organizationsItem(_ input: Input) -> NSMenuItem {
        let selected = Set(input.selectedOrganizations)
        let parent = NSMenuItem(title: "Organizations", action: nil, keyEquivalent: "")
        parent.image = Icons.symbol("building.2", color: .secondaryLabelColor)
        let submenu = NSMenu()
        for org in input.knownOrganizations.sorted() {
            let row = NSMenuItem(
                title: org,
                action: #selector(AppDelegate.toggleOrganization(_:)),
                keyEquivalent: ""
            )
            row.target = target
            row.representedObject = org
            // state sutunu butun satirlari kaydirir; tik gorsel sutununda.
            row.image = selected.contains(org)
                ? Icons.symbol("checkmark", color: .labelColor)
                : Icons.blank
            submenu.addItem(row)
        }
        parent.submenu = submenu
        return parent
    }

    private func profileItem(_ viewer: Viewer) -> NSMenuItem {
        let text = NSMutableAttributedString(
            string: viewer.displayName,
            attributes: [.font: MenuFont.label, .foregroundColor: NSColor.labelColor]
        )
        text.append(NSAttributedString(
            string: "  @\(viewer.login)",
            attributes: [.font: MenuFont.detail, .foregroundColor: NSColor.secondaryLabelColor]
        ))

        let item = NSMenuItem(title: "", action: #selector(AppDelegate.openProfile), keyEquivalent: "")
        item.attributedTitle = text
        item.target = target
        item.image = Avatar.cached(size: Icons.size) ?? Icons.blank
        return item
    }

    private func rateLimitItem(_ limit: RateLimit, now: Date) -> NSMenuItem {
        // Sifirlanma ani gecmisse "0m" anlamsiz; bir sonraki yenilemede yeni
        // pencere gelmis olacak.
        let resets = limit.resetAt <= now
            ? "resets <1m"
            : "resets \(Formatting.age(of: now, now: limit.resetAt))"

        let text = NSMutableAttributedString(
            string: "Rate Limit",
            attributes: [.font: MenuFont.label, .foregroundColor: NSColor.labelColor]
        )
        text.append(NSAttributedString(
            string: "  \(Formatting.grouped(limit.remaining)) / \(Formatting.grouped(limit.limit))\t\(resets)",
            attributes: [.font: MenuFont.detail, .foregroundColor: NSColor.secondaryLabelColor]
        ))
        text.addAttribute(.paragraphStyle, value: MenuFont.rowStyle,
                          range: NSRange(location: 0, length: text.length))

        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.attributedTitle = text
        item.isEnabled = false
        item.image = Icons.gauge(fraction: limit.fraction)
        return item
    }

    private func markAllSeenItem(for section: MenuSection) -> NSMenuItem {
        let item = NSMenuItem(
            title: "Mark All as Seen",
            action: #selector(AppDelegate.markSectionSeen(_:)),
            keyEquivalent: ""
        )
        item.target = target
        item.representedObject = section.kind.rawValue
        item.image = Icons.symbol("checkmark.circle", color: .secondaryLabelColor)
        return item
    }

    private func errorItem(_ error: AppError) -> NSMenuItem {
        let item = NSMenuItem(title: error.menuText, action: nil, keyEquivalent: "")
        item.image = Icons.symbol("exclamationmark.triangle", color: .systemOrange)
        item.isEnabled = false
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = target
        return item
    }
}

/// Menu yazi tipleri ve satir olculeri.
///
/// attributedTitle kullanildiginda AppKit menunun kendi yazi tipini
/// uygulamiyor, varsayilana dusuyor. menuFont(ofSize: 0) "sistemin standart
/// menu boyutu" demek. Depolanan degil hesaplanan ozellikler: NSFont bir
/// sinif ve Sendable degil, Swift 6 statik tutulmasina izin vermiyor.
enum MenuFont {
    /// Satirlarin bittigi nokta, punto cinsinden. Yas bu konumda saga yasli
    /// sekme duragiyla hizalaniyor; baslik da ayni genislige gore olculup
    /// kirpildigi icin satirlar iki kenara birden yasli.
    ///
    /// Menu genisligini ayarlamak icin degistirilecek TEK sayi budur.
    static let rowWidth: CGFloat = 280

    /// Satirin sag kenarini sabitleyen paragraf stili.
    static var rowStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: rowWidth, options: [:])]
        style.lineBreakMode = .byTruncatingTail   // olcum sasarsa son emniyet
        return style
    }

    static var label: NSFont { .menuFont(ofSize: 0) }

    /// Ikincil metin bir punto kucuk: hiyerarsiyi guclendiriyor.
    static var detail: NSFont { .menuFont(ofSize: NSFont.systemFontSize - 1) }
}

/// Ayri bir "okunmadi" noktasi cizilmiyor — ikonun rengi bu isi goruyor.
enum Icons {

    /// Tek boyut. NSMenu gorsel sutununu EN BUYUK gorsele gore olculendiriyor;
    /// tek bir buyuk gorsel butun satirlari saga kaydiriyor.
    static let size: CGFloat = 15

    /// Gorseli olan ve olmayan satirlarin hizasi kaymasin diye seffaf dolgu.
    static var blank: NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus(); image.unlockFocus()
        return image
    }

    static func symbol(_ name: String, color: NSColor) -> NSImage? {
        tinted([name], color)
    }

    static func forItem(_ item: Item, seen: Bool) -> NSImage? {
        // trianglehead SF Symbols 6 (macOS 15); Sonoma icin eski adlar yedek.
        let symbols = item.kind == .pullRequest
            ? ["arrow.trianglehead.pull", "arrow.triangle.pull", "arrow.triangle.branch"]
            : ["smallcircle.filled.circle", "circle.circle"]
        let color: NSColor = item.isDraft
            ? .tertiaryLabelColor
            : (seen ? .secondaryLabelColor : .systemGreen)
        return tinted(symbols, color)
    }

    /// Durum cubugu ikonu template: rengi macOS verir, menu aciliip buton
    /// vurgulandiginda da sistem ikonlari gibi dogru cevrilir. Paletli surum
    /// vurgulu durumda renk cevirmiyordu.
    static func statusBar() -> NSImage? {
        for name in ["arrow.trianglehead.pull", "arrow.triangle.pull", "arrow.triangle.branch"] {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: "GHBar") {
                image.isTemplate = true
                return image
            }
        }
        return nil
    }

    static func folder(unseen: Bool) -> NSImage? {
        tinted(["folder"], unseen ? .systemGreen : .secondaryLabelColor)
    }

    static func gauge(fraction: Double) -> NSImage? {
        let color: NSColor = fraction < 0.10 ? .systemRed
                           : (fraction < 0.25 ? .systemOrange : .secondaryLabelColor)
        return tinted(["gauge.with.needle", "gauge"], color)
    }

    /// Listedeki ilk mevcut sembolu boyar. Tek ad yerine liste almasinin
    /// sebebi macOS surum farklari: hedefimiz macOS 14 ama bazi semboller
    /// (arrow.trianglehead.*) macOS 15 ile geldi. Ad bulunamazsa NSImage nil
    /// doner ve satir SESSIZCE ikonsuz kalirdi.
    private static func tinted(_ names: [String], _ color: NSColor) -> NSImage? {
        for name in names {
            guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
                continue
            }
            let configuration = NSImage.SymbolConfiguration(paletteColors: [color])
            let image = base.withSymbolConfiguration(configuration)
            image?.size = NSSize(width: size, height: size)
            return image
        }
        return nil
    }
}
