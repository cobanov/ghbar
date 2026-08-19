import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var menuBuilder: MenuBuilder!
    private let seenStore = SeenStore(url: SeenStore.defaultURL)
    private let notifier = Notifier()
    private let settings = Settings.default

    private var sections: [Section] = []
    private var viewer: Viewer?
    private var rateLimit: RateLimit?
    private var errors: [AppError] = []
    private var lastRefresh: Date?
    private var isRefreshing = false
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock'ta ikon gosterme. Asama 2'de .app paketine LSUIElement eklenecek;
        // bu satir swift run ile calistirirken ayni isi goruyor.
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Icons.statusBar()
        // Sayac esit genislikli rakamlarla: sayi degistiginde menu cubugundaki
        // komsu ikonlar saga sola oynamasin.
        statusItem.button?.font = .monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize, weight: .regular
        )

        menuBuilder = MenuBuilder(target: self)
        notifier.onOpen = { [weak self] url in self?.open(url, markSeen: true) }
        // performClick menu cubugundaki dugmeye programatik tiklama — menuyu acar.
        notifier.onOpenSummary = { [weak self] in self?.statusItem.button?.performClick(nil) }
        notifier.start()
        rebuildMenu()

        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        // Uykudan uyaninca yenile; onsuz kapagi actiginda saatler oncesinin
        // verisini gorursun ve bayat oldugunu anlamanin yolu yoktur.
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        refresh()
    }

    // MARK: - Yenileme

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task { @MainActor in
            defer { isRefreshing = false }

            do {
                let token = try TokenProvider.token()
                let queries = Query.build(settings)

                var collected: [AppError] = []
                if queries.allowListEmpty { collected.append(.allowListEmpty) }
                if queries.filtersDropped { collected.append(.filtersDropped) }

                guard !queries.allowListEmpty else {
                    errors = collected
                    sections = []
                    rebuildMenu()
                    return
                }

                let snapshot = try await GitHubClient(token: token).fetch(queries)
                let built = Filtering.sections(from: snapshot, settings: settings)
                let all = built.flatMap(\.items)

                // Ilk yenilemede bildirim atilmaz (kurulumun ilk saniyesinde
                // onlarca bildirim yagardi), ama ogeler okunmamis kalir ki
                // kullanici neyi gormedigini gorebilsin.
                let wasFirstRun = seenStore.markFirstRunDone()
                let fresh = wasFirstRun ? [] : seenStore.newItems(among: all)
                seenStore.prune(keeping: Set(all.map(\.url)))
                try? seenStore.save()
                notifier.notify(about: fresh)

                // Avatar bir kez inip diske yaziliyor; URL degisirse yenileniyor.
                if await Avatar.refresh(from: snapshot.viewer.avatarURL) {
                    NSLog("GHBar: profil fotografi indirildi")
                }

                viewer = snapshot.viewer
                rateLimit = snapshot.rateLimit
                sections = built
                errors = collected
                lastRefresh = Date()
            } catch let error as AppError {
                errors = [error]
            } catch {
                errors = [.network(error.localizedDescription)]
            }

            rebuildMenu()
        }
    }

    private func rebuildMenu() {
        let unseen = sections.flatMap(\.items).filter { !seenStore.isSeen($0.url) }.count
        statusItem.button?.title = unseen > 0 ? " \(unseen)" : ""

        let menu = menuBuilder.build(MenuBuilder.Input(
            viewer: viewer,
            sections: sections,
            rateLimit: rateLimit,
            errors: errors,
            lastRefresh: lastRefresh,
            showOwner: settings.accounts.count > 1,
            maxRowsPerSection: settings.maxRowsPerSection,
            isSeen: { [seenStore] url in seenStore.isSeen(url) },
            now: Date()
        ))
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - Menu eylemleri

    @objc func openItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? Item else { return }
        // Tiklamak hem aciyor hem gorulmus isaretliyor; ayrica isaretlemeye
        // gerek kalmiyor.
        open(item.url, markSeen: true)
    }

    /// Menuden ve bildirimden ortak kullanilan acma yolu.
    private func open(_ address: String, markSeen: Bool) {
        guard let url = URL(string: address) else { return }
        if markSeen {
            seenStore.markSeen([address], at: Date())
            try? seenStore.save()
        }
        NSWorkspace.shared.open(url)
        rebuildMenu()
    }

    @objc func toggleLaunchAtLogin() {
        LaunchAtLogin.set(!LaunchAtLogin.isEnabled)
        rebuildMenu()
    }

    @objc func markSectionSeen(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let kind = SectionKind(rawValue: raw),
              let section = sections.first(where: { $0.kind == kind }) else { return }

        seenStore.markSeen(section.items.map(\.url), at: Date())
        try? seenStore.save()
        rebuildMenu()
    }

    @objc func openProfile() {
        guard let viewer, let url = URL(string: viewer.profileURL) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func refreshNow() { refresh() }

    @objc func quit() { NSApp.terminate(nil) }

    // MARK: - NSMenuDelegate

    /// Menuyu art arda acip kapatmak gereksiz istek uretmesin diye 30 saniyelik
    /// alt sinir var.
    func menuWillOpen(_ menu: NSMenu) {
        // lastRefresh nil = henuz hic basarili yenileme olmadi (ilk deneme
        // basarisiz olmus olabilir); menuyu acmak yeniden denemek icin en
        // dogru an. distantPast, 30 saniyelik esigi otomatik gecirir.
        let last = lastRefresh ?? .distantPast
        if Date().timeIntervalSince(last) > 30 { refresh() }
    }
}
