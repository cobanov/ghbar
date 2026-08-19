import SwiftUI
import Defaults

@MainActor
final class SettingsController {

    var onSignOut: (() -> Void)?
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let root = SettingsView(onSignOut: { [weak self] in self?.onSignOut?() })
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "GHBar Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

private struct SettingsView: View {
    var onSignOut: () -> Void

    var body: some View {
        TabView {
            AccountsPane(onSignOut: onSignOut)
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
            RepositoriesPane()
                .tabItem { Label("Repositories", systemImage: "folder") }
            GeneralPane()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 440, height: 380)
    }
}

// MARK: - Accounts

private struct AccountsPane: View {
    var onSignOut: () -> Void
    @Default(.signedInLogin) private var signedInLogin
    @Default(.accounts) private var accounts
    @State private var newAccount = ""

    var body: some View {
        Form {
            sessionSection
            Section("Watched accounts") {
                ForEach(accounts, id: \.self) { account in
                    HStack {
                        Text(account)
                        Spacer()
                        if account != "@me" {
                            Button {
                                accounts.removeAll { $0 == account }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    TextField("user or org", text: $newAccount)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newAccount.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("@me is you. Add organizations to watch their repositories too.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var sessionSection: some View {
        Section {
            if let login = signedInLogin {
                LabeledContent("Signed in as", value: "@\(login)")
                Button("Sign Out", role: .destructive) { onSignOut() }
            } else {
                // Direct varyantta gh token'iyla calisiyor olabiliriz.
                Text("Using the GitHub CLI token (gh).")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func add() {
        let name = newAccount.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty, !accounts.contains(name) else { return }
        accounts.append(name)
        newAccount = ""
    }
}

// MARK: - Repositories

private struct RepositoriesPane: View {
    @Default(.repoList) private var repoList
    @Default(.repoListIsAllowList) private var isAllowList
    @Default(.knownRepos) private var knownRepos
    @State private var newRepo = ""

    /// Gorulen repolar + listede olup artik oge uretmeyenler.
    private var rows: [String] {
        Array(Set(knownRepos.keys).union(repoList)).sorted { a, b in
            let (ca, cb) = (knownRepos[a] ?? 0, knownRepos[b] ?? 0)
            return ca != cb ? ca > cb : a < b
        }
    }

    var body: some View {
        Form {
            Section {
                // Maccy'nin ignoreAllAppsExceptListed kalibi (spec §8): TEK
                // liste, anlami tersine ceviren kutucuk. Kapaliyken isaretsiz
                // repolar dislanir; acikken yalniz isaretliler izlenir.
                Toggle("Watch only the listed repositories", isOn: $isAllowList)
                Text(isAllowList
                     ? "Only checked repositories are watched."
                     : "Unchecked repositories are hidden.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Repositories") {
                if rows.isEmpty {
                    Text("Repositories appear here as GHBar sees activity in them.")
                        .foregroundStyle(.secondary)
                }
                ForEach(rows, id: \.self) { repo in
                    Toggle(isOn: watchedBinding(repo)) {
                        HStack {
                            Text(repo)
                            Spacer()
                            if let count = knownRepos[repo] {
                                Text("\(count)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                HStack {
                    TextField("owner/name", text: $newRepo)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(!newRepo.contains("/"))
                }
            }
        }
        .formStyle(.grouped)
    }

    /// listede = (allow modunda) izleniyor / (deny modunda) gizli.
    private func watchedBinding(_ repo: String) -> Binding<Bool> {
        Binding(
            get: { isAllowList ? repoList.contains(repo) : !repoList.contains(repo) },
            set: { watched in
                let shouldBeListed = isAllowList ? watched : !watched
                if shouldBeListed {
                    if !repoList.contains(repo) { repoList.append(repo) }
                } else {
                    repoList.removeAll { $0 == repo }
                }
            }
        )
    }

    private func add() {
        let name = newRepo.trimmingCharacters(in: .whitespaces)
        guard name.contains("/"), !repoList.contains(name) else { return }
        repoList.append(name)
        newRepo = ""
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Default(.refreshMinutes) private var refreshMinutes
    @Default(.notificationsEnabled) private var notificationsEnabled
    @Default(.showBots) private var showBots
    @Default(.showDrafts) private var showDrafts
    @Default(.repoGroupThreshold) private var groupThreshold

    var body: some View {
        Form {
            Picker("Refresh every", selection: $refreshMinutes) {
                Text("1 minute").tag(1)
                Text("5 minutes").tag(5)
                Text("15 minutes").tag(15)
                Text("30 minutes").tag(30)
                Text("1 hour").tag(60)
            }
            Toggle("Show notifications", isOn: $notificationsEnabled)
            Toggle("Show bot activity", isOn: $showBots)
            Toggle("Show draft pull requests", isOn: $showDrafts)
            Picker("Group repositories with more than", selection: $groupThreshold) {
                Text("3 items").tag(3)
                Text("5 items").tag(5)
                Text("10 items").tag(10)
                Text("Never group").tag(0)
            }
            if LaunchAtLogin.isAvailable {
                Toggle("Launch at login", isOn: Binding(
                    get: { LaunchAtLogin.isEnabled },
                    set: { LaunchAtLogin.set($0) }
                ))
            }
        }
        .formStyle(.grouped)
    }
}
