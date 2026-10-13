import AppKit
import Defaults
import Network

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
    /// Warnings shown with fresh data: dropped filters, GitHub's partial errors.
    private var notices: [String] = []
    /// No refreshes until then: GitHub's rate limit is spent.
    private var rateLimitedUntil: Date?
    private let pathMonitor = NWPathMonitor()
    private var online = true
    /// A refresh that waits for the network: after wake, or after one failed offline.
    private var refreshWhenOnline = false
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
        Task.detached(priority: .background) { AuthorAvatars.prune() }
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
            // The overdue timer would fire too: restart it, and refresh once the network is
            // back, which it usually is not the moment the lid opens.
            Task { @MainActor in
                guard let self else { return }
                self.scheduleTimer()
                if self.online { self.refresh() } else { self.refreshWhenOnline = true }
            }
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let isOnline = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(isOnline) }
        }
        pathMonitor.start(queue: .global(qos: .utility))

        refresh()
    }

    // MARK: - Yenileme

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Settings.refreshInterval(),
                                     repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = Settings.refreshInterval() / 10
    }

    func refresh() {
        guard refreshGate.begin() else { return }

        Task { @MainActor in
            // The panel learns the refresh ended only here: every rebuild above still saw
            // the gate running, and the refresh button kept spinning.
            defer { if refreshGate.finish() { refresh() } else { rebuildMenu() } }

            // While GitHub's rate limit is spent, asking again only lengthens the wait.
            if let until = rateLimitedUntil, until > Date() {
                rebuildMenu()
                return
            }

            // Kapi acildi; menu artik "Refreshing…" gosterebilir.
            rebuildMenu()

            // Results of a refresh that outlives a sign-out or an account switch are dropped.
            let generation = session.generation
            guard let token = await session.token(), session.generation == generation else {
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
            rebuildMenu()   // the session is known now; drop any "Sign in" the panel showed

            do {
                let settings = Settings.fromDefaults()
                let queries = Query.build(settings)

                var notes: [String] = []
                if queries.allowListEmpty { notes.append(AppError.allowListEmpty.menuText) }
                if queries.filtersDropped { notes.append(AppError.filtersDropped.menuText) }

                guard !queries.allowListEmpty else {
                    errors = []
                    notices = notes
                    sections = []
                    rebuildMenu()
                    return
                }

                let snapshot = try await GitHubClient(token: token).fetch(queries)
                guard session.generation == generation else { return }
                apply(snapshot, settings: settings, notes: notes)
            } catch AppError.unauthorized {
                // GitHub token'i reddetti: hata satiri degil, yeniden giris cagrisi.
                guard session.generation == generation else { return }
                session.markExpired(generation: generation)
                clearAccountData()
            } catch AppError.rateLimited(let resetAt) {
                rateLimitedUntil = resetAt
                errors = [.rateLimited(resetAt)]
            } catch let error as AppError {
                errors = [error]
                if case .network = error { refreshWhenOnline = true }
            } catch {
                errors = [.network(error.localizedDescription)]
                refreshWhenOnline = true
            }

            rebuildMenu()
        }
    }

    private func apply(_ snapshot: Snapshot, settings: Settings, notes: [String]) {
        let now = Date()
        // A different account than the one whose data is stored: start over, so its
        // organizations, repositories and seen marks do not leak into the new account.
        if let owner = Defaults[.signedInLogin], owner != snapshot.viewer.login {
            resetAccountScopedState()
        }
        session.loaded(login: snapshot.viewer.login)

        let built = Filtering.sections(from: snapshot, settings: settings)
        let all = built.flatMap(\.items)

        // Ayarlar > Repositories icin aktivite listesi. Merged rather than replaced: a
        // repository hidden by the allow list must stay in the list to be ticked again.
        Defaults[.knownOrganizations] = snapshot.viewer.organizations
        var repos = Defaults[.knownRepos].mapValues { _ in 0 }
        for (repo, items) in Dictionary(grouping: all, by: \.repository) { repos[repo] = items.count }
        Defaults[.knownRepos] = repos

        // Gorulme ve bildirim kaydi. Everything GitHub returned counts as still around, even
        // what a filter hides; entries are forgotten by age.
        let returned = snapshot.prs + snapshot.issues + snapshot.review
            + snapshot.changesRequested + snapshot.myPullRequests
        seenStore.recordReturned(Set(returned.map(\.url)), at: now)
        seenStore.prune(now: now)
        var placement: [String: SectionKind] = [:]
        for section in built { for item in section.items { placement[item.url] = section.kind } }
        _ = seenStore.promote(placement)

        // Your own pull requests are not news to you: no notification, no badge.
        let incoming = built.filter { $0.kind != .myPullRequests }.flatMap(\.items)
        let firstRun = seenStore.markFirstRunDone()
        let backfill = seenStore.claimNotificationBackfill()
        let fresh = (firstRun || backfill) ? [] : seenStore.unnotified(among: incoming)
        seenStore.markNotified(all.map(\.url))
        try? seenStore.save()
        if Defaults[.notificationsEnabled] { notifier.notify(about: fresh) }

        viewer = snapshot.viewer
        social = snapshot.social
        rateLimit = snapshot.rateLimit
        rateLimitedUntil = snapshot.rateLimit.remaining == 0 ? snapshot.rateLimit.resetAt : nil
        sections = built
        errors = []
        notices = notes + snapshot.warnings
        lastRefresh = now

        // Avatar bir kez inip diske yaziliyor; it no longer holds up the results.
        let address = snapshot.viewer.avatarURL
        Task { [weak self] in
            if await Avatar.refresh(from: address) { self?.rebuildMenu() }
        }
    }

    /// The network came back (or went): a refresh that was waiting for it runs now.
    private func networkChanged(_ isOnline: Bool) {
        let cameBack = isOnline && !online
        online = isOnline
        guard cameBack, refreshWhenOnline else { return }
        refreshWhenOnline = false
        refresh()
    }

    /// What belongs to one GitHub account and must not carry over to another.
    private func resetAccountScopedState() {
        Defaults[.organizations] = []
        Defaults[.knownOrganizations] = []
        Defaults[.knownRepos] = [:]
        seenStore.reset()
        Avatar.forget()
    }

    private func rebuildMenu() {
        // Your own pull requests are never "new": they do not count, and show no green dot.
        let mine = Set(sections.filter { $0.kind == .myPullRequests }.flatMap(\.items).map(\.url))
        let unseen = sections.filter { $0.kind != .myPullRequests }.flatMap(\.items)
            .filter { !seenStore.isSeen($0.url) }.count
        statusItem.button?.title = session.state.isSignedIn && unseen > 0 ? " \(unseen)" : ""

        let settings = Settings.fromDefaults()
        panelModel.input = PanelInput(
            viewer: viewer,
            social: social,
            sections: sections,
            rateLimit: rateLimit,
            errors: errors,
            notices: notices,
            lastRefresh: lastRefresh,
            auth: session.state,
            authRefused: session.refused,
            isRefreshing: refreshGate.isRunning,
            showOwner: settings.accounts.count > 1 || !settings.organizations.isEmpty,
            knownOrganizations: Defaults[.knownOrganizations],
            selectedOrganizations: settings.organizations,
            repositoryFilterActive: !settings.repoList.isEmpty,
            repositoryFilterIsAllowList: settings.repoListIsAllowList,
            visibleSections: settings.visibleSections,
            showEmptySections: settings.showEmptySections,
            rateLimitVisibility: settings.rateLimitVisibility,
            isSeen: { [seenStore] url in mine.contains(url) || seenStore.isSeen(url) },
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
        resetAccountScopedState()
        Defaults[.signedInLogin] = nil
        clearAccountData()
        rebuildMenu()
    }

    /// What belonged to the account that is no longer signed in.
    private func clearAccountData() {
        sections = []
        errors = []
        notices = []
        rateLimitedUntil = nil
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
        panelModel.opened += 1
        // lastRefresh nil = henuz hic basarili yenileme olmadi (ilk deneme
        // basarisiz olmus olabilir); menuyu acmak yeniden denemek icin en
        // dogru an. distantPast, 30 saniyelik esigi otomatik gecirir.
        let last = lastRefresh ?? .distantPast
        if Date().timeIntervalSince(last) > 30 { refresh() }
    }
}
