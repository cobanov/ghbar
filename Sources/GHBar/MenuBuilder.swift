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
        var sections: [Section]
        var rateLimit: RateLimit?
        var errors: [AppError]
        var showOwner: Bool
        var maxRowsPerSection: Int
        var isSeen: (String) -> Bool
        var now: Date
    }

    func build(_ input: Input) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if let viewer = input.viewer {
            menu.addItem(profileItem(viewer))
            menu.addItem(.separator())
        }

        if !input.errors.isEmpty {
            for error in input.errors { menu.addItem(errorItem(error)) }
            menu.addItem(.separator())
        }

        for section in input.sections {
            menu.addItem(.sectionHeader(title: section.kind.title))
            addRows(of: section, to: menu, input: input)
            if section.truncated {
                menu.addItem(disabled("Showing first 100 — narrow your filters"))
            }
            menu.addItem(markAllSeenItem(for: section))
            menu.addItem(.separator())
        }

        if input.sections.isEmpty && input.errors.isEmpty {
            menu.addItem(disabled("Nothing waiting"))
            menu.addItem(.separator())
        }

        if let rateLimit = input.rateLimit {
            menu.addItem(.sectionHeader(title: "API"))
            menu.addItem(rateLimitItem(rateLimit, now: input.now))
            menu.addItem(.separator())
        }

        menu.addItem(action("Open GitHub", #selector(AppDelegate.openProfile), key: "o"))
        menu.addItem(action("Refresh", #selector(AppDelegate.refreshNow), key: "r"))

        if LaunchAtLogin.isAvailable {
            let launch = action("Launch at Login", #selector(AppDelegate.toggleLaunchAtLogin), key: "")
            launch.state = LaunchAtLogin.isEnabled ? .on : .off
            menu.addItem(launch)
        }

        menu.addItem(.separator())
        menu.addItem(disabled("GHBar \(AppVersion.current)"))
        menu.addItem(action("Quit GHBar", #selector(AppDelegate.quit), key: "q"))
        return menu
    }

    // MARK: - Parcalar

    private func addRows(of section: Section, to menu: NSMenu, input: Input) {
        let visible = section.rows.prefix(input.maxRowsPerSection)
        for row in visible {
            menu.addItem(item(for: row, input: input))
        }

        let overflow = section.rows.count - visible.count
        guard overflow > 0 else { return }

        let more = NSMenuItem(title: "\(overflow) more…", action: nil, keyEquivalent: "")
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
            let menuItem = NSMenuItem(
                title: RowText.groupLabel(
                    repository: repository,
                    count: items.count,
                    kind: items[0].kind,
                    showOwner: input.showOwner
                ),
                action: nil,
                keyEquivalent: ""
            )
            menuItem.image = Icons.folder(unseen: unseen)
            let submenu = NSMenu()
            for entry in items { submenu.addItem(itemRow(entry, input: input)) }
            menuItem.submenu = submenu
            return menuItem
        }
    }

    private func itemRow(_ entry: Item, input: Input) -> NSMenuItem {
        let parts = RowText.parts(for: entry, showOwner: input.showOwner, now: input.now)
        let seen = input.isSeen(entry.url)

        // Raycast menulerindeki temizligin sirri: deger, etiketin hemen devami
        // olarak akiyor — sutun hizalama veya saga yaslama yok.
        let text = NSMutableAttributedString(
            string: parts.label,
            attributes: [
                .font: MenuFont.label,
                .foregroundColor: seen ? NSColor.secondaryLabelColor : NSColor.labelColor,
            ]
        )
        text.append(NSAttributedString(
            string: "  \(parts.detail)  \(parts.age)",
            attributes: [
                .font: MenuFont.detail,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        ))

        let menuItem = NSMenuItem(
            title: "",
            action: #selector(AppDelegate.openItem(_:)),
            keyEquivalent: ""
        )
        menuItem.attributedTitle = text
        menuItem.target = target
        menuItem.representedObject = entry
        menuItem.image = Icons.forItem(entry, seen: seen)
        return menuItem
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
        return item
    }

    private func rateLimitItem(_ limit: RateLimit, now: Date) -> NSMenuItem {
        // age(of:now:) parametreleri ters verilerek "sifirlanmaya kalan sure"
        // elde ediliyor.
        let resets = Formatting.age(of: now, now: limit.resetAt)

        let text = NSMutableAttributedString(
            string: "Rate Limit",
            attributes: [.font: MenuFont.label, .foregroundColor: NSColor.labelColor]
        )
        text.append(NSAttributedString(
            string: "  \(Formatting.grouped(limit.remaining)) / \(Formatting.grouped(limit.limit))  resets \(resets)",
            attributes: [.font: MenuFont.detail, .foregroundColor: NSColor.secondaryLabelColor]
        ))

        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.attributedTitle = text
        item.isEnabled = false
        item.image = Icons.gauge(fraction: limit.fraction)
        return item
    }

    private func markAllSeenItem(for section: Section) -> NSMenuItem {
        let item = NSMenuItem(
            title: "Mark All as Seen",
            action: #selector(AppDelegate.markSectionSeen(_:)),
            keyEquivalent: ""
        )
        item.target = target
        item.representedObject = section.kind.rawValue
        item.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: nil)
        return item
    }

    private func errorItem(_ error: AppError) -> NSMenuItem {
        let item = NSMenuItem(title: error.menuText, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
        item.isEnabled = false
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = target
        return item
    }
}

/// Menu yazi tipleri.
///
/// attributedTitle kullanildiginda AppKit menunun kendi yazi tipini
/// uygulamiyor, varsayilana dusuyor ve satirlar sistem menulerinden iri
/// duruyor. menuFont(ofSize: 0) "sistemin standart menu boyutu" demek.
/// Depolanan degil hesaplanan ozellikler: NSFont bir sinif ve Sendable degil,
/// Swift 6 statik olarak tutulmasina izin vermiyor. NSFont uretimi AppKit
/// tarafindan onbelleklendigi icin her cagride yeniden istemek bedava.
enum MenuFont {
    static var label: NSFont { .menuFont(ofSize: 0) }

    /// Ikincil metin bir punto kucuk: hem hiyerarsiyi guclendiriyor hem
    /// satirin en uzun parcasi oldugu icin genisligi gozle gorulur dusuruyor.
    static var detail: NSFont { .menuFont(ofSize: NSFont.systemFontSize - 1) }
}

/// Ayri bir "okunmadi" noktasi cizilmiyor — ikonun rengi bu isi goruyor.
enum Icons {

    static func forItem(_ item: Item, seen: Bool) -> NSImage? {
        let symbol = item.kind == .pullRequest
            ? "arrow.trianglehead.pull"
            : "smallcircle.filled.circle"
        let color: NSColor = item.isDraft
            ? .tertiaryLabelColor
            : (seen ? .secondaryLabelColor : .systemGreen)
        return tinted(symbol, color)
    }

    static func folder(unseen: Bool) -> NSImage? {
        tinted("folder", unseen ? .systemGreen : .secondaryLabelColor)
    }

    static func gauge(fraction: Double) -> NSImage? {
        let color: NSColor = fraction < 0.10 ? .systemRed
                           : (fraction < 0.25 ? .systemOrange : .secondaryLabelColor)
        return tinted("gauge.with.needle", color)
    }

    private static func tinted(_ symbol: String, _ color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(paletteColors: [color])
        return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }
}
