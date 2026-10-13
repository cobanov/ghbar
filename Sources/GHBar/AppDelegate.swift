import AppKit
import Defaults

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var panel: StatusPanel!
    private let panelModel = PanelModel()
    private var statusItem: NSStatusItem { panel.statusItem }
    private let seenStore = SeenStore(url: SeenStore.defaultURL)
    private let notifier = Notifier()
    private let welcome = WelcomeController()
    private let settingsWindow = SettingsController()
    private let session = AuthSession.shared
    /// The welcome window opens by itself once per launch while nobody is signed in.
    private var welcomedThisLaunch = false
    private var settingsObserver: Task<Void, Never>?
    private var displayObserver: Task<Void, Never>?

    private var sections: [MenuSection] = []
    private var viewer: Viewer?
    private var social: Social?
    private var rateLimit: RateLimit?
    private var errors: [AppError] = []
    private var lastRefresh: Date?
    private var refreshGate = RefreshGate()
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock'ta ikon gosterme. Asama 2'de .app paketine LSUIElement eklenecek;
        // bu satir swift run ile calistirirken ayni isi goruyor.
        NSApp.setActivationPolicy(.accessory)

        panel = StatusPanel(style: PanelPreview.style) { PanelView(model: panelModel) }
        panel.onOpen = { [weak self] in self?.panelWillOpen() }
        panelModel.actions = PanelActions(
            open: { [weak self] item in self?.panel.close(); self?.open(item.url, markSeen: true) },
            markAllSeen: { [weak self] in self?.markAllSeen() },
            markSectionSeen: { [weak self] kind in self?.markSeen(kind) },
            openProfile: { [weak self] in self?.panel.close(); self?.openProfile() },
            refresh: { [weak self] in self?.refresh() },
            openSettings: { [weak self] in self?.panel.close(); self?.openSettings() },
            signIn: { [weak self] in self?.panel.close(); self?.openWelcome() },
            toggleOrganization: { [weak self] org in self?.toggleOrganization(org) },
            clearOrganizations: { [weak self] in self?.clearOrganizations() },
            quit: { [weak self] in self?.quit() }
        )
        statusItem.button?.image = StatusIcon.image()
        statusItem.button?.imagePosition = .imageLeading
        // Sayac esit genislikli rakamlarla: sayi degistiginde menu cubugundaki
        // komsu ikonlar saga sola oynamasin.
        statusItem.button?.font = .monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize, weight: .regular
        )

        // After signing in, show what is now there: the panel opens and fills as the first
        // refresh lands.
        welcome.onSignedIn = { [weak self] in
            self?.refresh()
            self?.panel.open()
        }
        settingsWindow.onSignOut = { [weak self] in self?.signOut() }
        settingsWindow.onSignIn = { [weak self] in self?.openWelcome() }
        notifier.onOpen = { [weak self] url in self?.open(url, markSeen: true) }
        notifier.onOpenSummary = { [weak self] in self?.panel.open() }
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
            for await _ in Defaults.updates([.showEmptySections, .rateLimitVisibility], initial: false) {
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
                guard let token = session.token() else {
                    // Oturum yoklugu hata satiri degil, panelde eyleme cagri.
                    clearAccountData()
                    rebuildMenu()
                    if !welcomedThisLaunch {
                        welcomedThisLaunch = true
                        welcome.show()
                    }
                    return
                }
                welcomedThisLaunch = true
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

                // Ayarlar > Accounts icin kim oldugu (her iki kaynakta da) ve
                // Ayarlar > Repositories icin aktivite listesi.
                session.loaded(login: snapshot.viewer.login)
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
                social = snapshot.social
                rateLimit = snapshot.rateLimit
                sections = built
                errors = collected
                lastRefresh = Date()
            } catch AppError.unauthorized {
                // GitHub token'i reddetti: hata satiri degil, yeniden giris cagrisi.
                session.markExpired()
                clearAccountData()
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
        panelModel.input = PanelInput(
            viewer: viewer,
            social: social,
            sections: sections,
            rateLimit: rateLimit,
            errors: errors,
            lastRefresh: lastRefresh,
            auth: session.state,
            isRefreshing: refreshGate.isRunning,
            showOwner: settings.accounts.count > 1 || !settings.organizations.isEmpty,
            knownOrganizations: Defaults[.knownOrganizations],
            selectedOrganizations: settings.organizations,
            repositoryFilterActive: !settings.repoList.isEmpty,
            visibleSections: settings.visibleSections,
            showEmptySections: settings.showEmptySections,
            rateLimitVisibility: settings.rateLimitVisibility,
            isSeen: { [seenStore] url in seenStore.isSeen(url) },
            now: Date()
        )
        panel.contentChanged()
    }

    // MARK: - Menu eylemleri

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

    func markSeen(_ kind: SectionKind) {
        guard let section = sections.first(where: { $0.kind == kind }) else { return }

        seenStore.markSeen(section.items.map(\.url), at: Date())
        try? seenStore.save()
        rebuildMenu()
    }

    func markAllSeen() {
        seenStore.markSeen(sections.flatMap(\.items).map(\.url), at: Date())
        try? seenStore.save()
        rebuildMenu()
    }

    func openProfile() {
        guard let viewer, let url = URL(string: viewer.profileURL) else { return }
        NSWorkspace.shared.open(url)
    }

    func toggleOrganization(_ org: String) {
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

    func clearOrganizations() {
        Defaults[.organizations] = []
        // toggleOrganization ile ayni sebep: yenileme ag turunu bekliyor.
        rebuildMenu()
    }

    func openWelcome() { welcome.show() }

    func openSettings() { settingsWindow.show() }

    /// Sign Out means signed out: the token goes, and a signed-in `gh` is not picked up again
    /// until the user chooses it.
    private func signOut() {
        session.signOut()
        Defaults[.knownOrganizations] = []
        seenStore.reset()
        clearAccountData()
        rebuildMenu()
    }

    /// What belonged to the account that is no longer signed in.
    private func clearAccountData() {
        sections = []
        errors = []
        viewer = nil
        social = nil
        rateLimit = nil
        lastRefresh = nil
    }

    func quit() { NSApp.terminate(nil) }

    // MARK: - Panel

    /// Paneli art arda acip kapatmak gereksiz istek uretmesin diye 30 saniyelik
    /// alt sinir var.
    private func panelWillOpen() {
        panelModel.input?.now = Date()
        // lastRefresh nil = henuz hic basarili yenileme olmadi (ilk deneme
        // basarisiz olmus olabilir); menuyu acmak yeniden denemek icin en
        // dogru an. distantPast, 30 saniyelik esigi otomatik gecirir.
        let last = lastRefresh ?? .distantPast
        if Date().timeIntervalSince(last) > 30 { refresh() }
    }
}
