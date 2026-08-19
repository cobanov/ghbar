import AppKit
import Defaults

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var menuBuilder: MenuBuilder!
    private let seenStore = SeenStore(url: SeenStore.defaultURL)
    private let notifier = Notifier()
    private let welcome = WelcomeController()
    private let settingsWindow = SettingsController()
    private var isSignedOut = false
    private var settingsObserver: Task<Void, Never>?
    private var displayObserver: Task<Void, Never>?

    private var sections: [MenuSection] = []
    private var viewer: Viewer?
    private var rateLimit: RateLimit?
    private var errors: [AppError] = []
    private var lastRefresh: Date?
    private var refreshGate = RefreshGate()
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
        welcome.onSignedIn = { [weak self] in self?.refresh() }
        settingsWindow.onSignOut = { [weak self] in self?.signOut() }
        notifier.onOpen = { [weak self] url in self?.open(url, markSeen: true) }
        // performClick menu cubugundaki dugmeye programatik tiklama — menuyu acar.
        notifier.onOpenSummary = { [weak self] in self?.statusItem.button?.performClick(nil) }
        notifier.start()
        rebuildMenu()

        scheduleTimer()

        // Ayar degisikligi aninda yansir (spec §8): Defaults yayinlarini
        // dinle, zamanlayiciyi yeni araliga kur, yenile.
        settingsObserver = Task { [weak self] in
            for await _ in Defaults.updates([.accounts, .organizations, .repoList,
                                             .repoListIsAllowList, .showBots, .showDrafts,
                                             .showPullRequests, .showIssues,
                                             .showReviewRequested, .showChangesRequested,
                                             .showMyPullRequests,
                                             .refreshMinutes, .repoGroupThreshold], initial: false) {
                guard let self else { return }
                self.scheduleTimer()
                self.refresh()
            }
        }

        // Yalnizca cizimi degistiren ayarlar. Yukaridaki listeye konsaydi her
        // isaret bir GitHub istegi harcardi; elde olan veri zaten yeterli.
        displayObserver = Task { [weak self] in
            for await _ in Defaults.updates([.showEmptySections], initial: false) {
                guard let self else { return }
                self.rebuildMenu()
            }
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

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Settings.refreshInterval(),
                                     repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard refreshGate.begin() else { return }

        Task { @MainActor in
            defer { if refreshGate.finish() { refresh() } }

            // Kapi acildi; menu artik "Refreshing…" gosterebilir.
            rebuildMenu()

            do {
                guard let token = TokenProvider.current() else {
                    // Oturum yoklugu hata satiri degil, menude eyleme cagri.
                    isSignedOut = true
                    sections = []
                    errors = []
                    viewer = nil
                    rebuildMenu()
                    return
                }
                isSignedOut = false
                let settings = Settings.fromDefaults()
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

                // Ayarlar > Accounts icin oturum bilgisi (yalniz OAuth'ta;
                // gh token'inda nil kalir ve pane 'gh kullaniliyor' der) ve
                // Ayarlar > Repositories icin aktivite listesi.
                Defaults[.signedInLogin] = Keychain.token() != nil ? snapshot.viewer.login : nil
                Defaults[.knownOrganizations] = snapshot.viewer.organizations
                Defaults[.knownRepos] = Dictionary(grouping: all, by: \.repository)
                    .mapValues(\.count)

                // Bildirim "gorulmemis"e degil "hic bildirilmemis"e bakar.
                // Gorulmusluk kullanici tiklayinca degisen bir menu durumu;
                // ikisi ayni kume sanildiginda her yenilemede ayni eski
                // ogeler yeniden bildiriliyordu. Ilk calistirmada ve v1->v2
                // yukseltmesinde mevcut ogeler sessizce isaretlenir.
                let firstRun = seenStore.markFirstRunDone()
                let backfill = seenStore.claimNotificationBackfill()
                let fresh = (firstRun || backfill) ? [] : seenStore.unnotified(among: all)
                seenStore.markNotified(all.map(\.url))
                seenStore.prune(keeping: Set(all.map(\.url)))
                try? seenStore.save()
                if Defaults[.notificationsEnabled] { notifier.notify(about: fresh) }

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

        let settings = Settings.fromDefaults()
        let menu = menuBuilder.build(MenuBuilder.Input(
            viewer: viewer,
            sections: sections,
            rateLimit: rateLimit,
            errors: errors,
            lastRefresh: lastRefresh,
            isSignedOut: isSignedOut,
            isRefreshing: refreshGate.isRunning,
            showOwner: settings.accounts.count > 1 || !settings.organizations.isEmpty,
            knownOrganizations: Defaults[.knownOrganizations],
            selectedOrganizations: settings.organizations,
            visibleSections: settings.visibleSections,
            showEmptySections: settings.showEmptySections,
            maxRowsPerSection: Settings.default.maxRowsPerSection,
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

    @objc func toggleOrganization(_ sender: NSMenuItem) {
        guard let org = sender.representedObject as? String else { return }
        var selected = Defaults[.organizations]
        if selected.contains(org) {
            selected.removeAll { $0 == org }
        } else {
            selected.append(org)
        }
        Defaults[.organizations] = selected
        // Yenileme ag turunu bekliyor; menuyu simdi kurmazsak tik bir sonraki
        // acilista donuyor ve tiklama islenmemis gibi gorunuyor.
        rebuildMenu()
    }

    @objc func openWelcome() { welcome.show() }

    @objc func openSettings() { settingsWindow.show() }

    private func signOut() {
        Keychain.delete()
        Defaults[.signedInLogin] = nil
        Defaults[.knownOrganizations] = []
        seenStore.reset()
        sections = []
        viewer = nil
        rateLimit = nil
        // Direct varyantta gh varsa zincir ona duser (spec §5 sirasi);
        // yoksa oturumsuz duruma gecilir.
        refresh()
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
