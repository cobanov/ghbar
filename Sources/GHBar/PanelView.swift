import AppKit
import SwiftUI

/// What the panel does when something in it is clicked; the app delegate supplies these.
struct PanelActions {
    var open: (Item) -> Void = { _ in }
    var markAllSeen: () -> Void = {}
    var markSectionSeen: (SectionKind) -> Void = { _ in }
    var openProfile: () -> Void = {}
    var refresh: () -> Void = {}
    var openSettings: () -> Void = {}
    var signIn: () -> Void = {}
    var toggleOrganization: (String) -> Void = { _ in }
    var clearOrganizations: () -> Void = {}
    var quit: () -> Void = {}
}

/// The panel's state: the same input the menu was built from, and the open tab.
@MainActor
final class PanelModel: ObservableObject {
    @Published var input: PanelInput?
    @Published var tab: SectionKind?
    var actions = PanelActions()
}

/// The panel under the menu bar item: who you are, then the work waiting for you, one kind at a
/// time. Green means one thing only: something you have not seen yet.
struct PanelView: View {
    @ObservedObject var model: PanelModel
    @State private var expanded: Set<String> = []

    private var actions: PanelActions { model.actions }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let input = model.input {
                if input.isSignedOut {
                    signedOut
                } else {
                    header(input)
                    if !input.errors.isEmpty { errors(input) }
                    work(input)
                    footer(input)
                }
            } else {
                Text("Loading…").font(Ink.meta).foregroundStyle(Ink.secondary).padding(20)
            }
        }
        .frame(width: 380)
        .foregroundStyle(Ink.primary)
        .background(shortcuts)
    }

    /// The menu's old key equivalents, kept for people who used them.
    private var shortcuts: some View {
        ZStack {
            Button("", action: actions.refresh).keyboardShortcut("r")
            Button("", action: actions.openSettings).keyboardShortcut(",")
            Button("", action: actions.openProfile).keyboardShortcut("o")
            Button("", action: actions.quit).keyboardShortcut("q")
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    // MARK: header

    private func header(_ input: PanelInput) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                Button(action: actions.openProfile) {
                    HStack(alignment: .top, spacing: 11) {
                        ViewerAvatar(viewer: input.viewer).frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(input.viewer?.displayName ?? "GitHub").font(Ink.name).lineLimit(1)
                                    .layoutPriority(1)
                                if let login = input.viewer?.login {
                                    Text(verbatim: "@\(login)").font(Ink.meta).foregroundStyle(Ink.tertiary).lineLimit(1)
                                }
                            }
                            if let social = input.social { counters(social).fixedSize() }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open your GitHub profile")
                .layoutPriority(1)
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    IconButton(symbol: "arrow.clockwise", help: "Refresh", spinning: input.isRefreshing, action: actions.refresh)
                    IconButton(symbol: "ellipsis", help: "More") { moreMenu(input) }
                }
                .padding(.top, 3)
            }
            if !input.knownOrganizations.isEmpty { organizations(input) }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func counters(_ social: Social) -> some View {
        HStack(spacing: 10) {
            counter(Formatting.grouped(social.stars) + (social.starsAreExact ? "" : "+"), "stars")
            counter(Formatting.grouped(social.followers), "followers")
            counter(Formatting.grouped(social.following), "following")
        }
    }

    private func counter(_ value: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(verbatim: value).foregroundStyle(Ink.secondary)
            Text(label).foregroundStyle(Ink.tertiary)
        }
        .font(Ink.meta)
    }

    private func organizations(_ input: PanelInput) -> some View {
        let selected = input.selectedOrganizations
        let label = selected.isEmpty ? "All organizations"
            : selected.count == 1 ? selected[0] : "\(selected.count) organizations"
        return Button {
            ChoiceMenu.show(
                [.action("All organizations", checked: selected.isEmpty, actions.clearOrganizations), .separator]
                    + input.knownOrganizations.sorted().map { org in
                        .action(org, checked: selected.contains(org)) { actions.toggleOrganization(org) }
                    }
            )
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "building.2").font(.system(size: 10.5))
                Text(label).font(Ink.meta)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(Ink.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Ink.raised))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func moreMenu(_ input: PanelInput) {
        let unseen = input.sections.reduce(0) { $0 + $1.unseenCount(input.isSeen) }
        var entries: [ChoiceMenu.Entry] = [
            .action("Open GitHub", actions.openProfile),
            .action("Settings…", actions.openSettings),
        ]
        if unseen > 0 { entries += [.separator, .action("Mark all as seen", actions.markAllSeen)] }
        entries += [.separator, .action("Quit GHBar", actions.quit)]
        ChoiceMenu.show(entries)
    }

    // MARK: errors

    private func errors(_ input: PanelInput) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(input.errors, id: \.menuText) { error in
                Label(error.menuText, systemImage: "exclamationmark.triangle.fill")
                    .font(Ink.meta)
                    .foregroundStyle(Ink.warning)
            }
            if let last = input.lastRefresh {
                Text("Showing what was there at \(Self.clock.string(from: last)).")
                    .font(Ink.meta).foregroundStyle(Ink.tertiary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    // MARK: work

    private func kinds(_ input: PanelInput) -> [SectionKind] {
        SectionKind.displayOrder.filter { kind in
            input.showEmptySections
                ? input.visibleSections.contains(kind)
                : input.sections.contains { $0.kind == kind && !$0.isEmpty }
        }
    }

    /// The open tab: the one picked, else the first with something unseen, else the first.
    private func current(_ input: PanelInput, _ kinds: [SectionKind]) -> SectionKind? {
        if let tab = model.tab, kinds.contains(tab) { return tab }
        return kinds.first { kind in section(kind, input).map { $0.unseenCount(input.isSeen) > 0 } ?? false }
            ?? kinds.first
    }

    private func section(_ kind: SectionKind, _ input: PanelInput) -> MenuSection? {
        input.sections.first { $0.kind == kind }
    }

    @ViewBuilder private func work(_ input: PanelInput) -> some View {
        let kinds = kinds(input)
        if let tab = current(input, kinds) {
            tabs(input, kinds, current: tab)
            Rectangle().fill(Ink.hairline).frame(height: 1)
            list(input, section(tab, input))
        } else if input.errors.isEmpty {
            Rectangle().fill(Ink.hairline).frame(height: 1)
            empty(input)
        }
    }

    private func tabs(_ input: PanelInput, _ kinds: [SectionKind], current: SectionKind) -> some View {
        ViewThatFits(in: .horizontal) {
            tabRow(input, kinds, current: current, short: false)
            tabRow(input, kinds, current: current, short: true)
        }
        .padding(.horizontal, 18)
    }

    private func tabRow(_ input: PanelInput, _ kinds: [SectionKind], current: SectionKind, short: Bool) -> some View {
        HStack(spacing: 18) {
            ForEach(kinds, id: \.self) { kind in
                let section = section(kind, input)
                let unseen = section?.unseenCount(input.isSeen) ?? 0
                let active = kind == current
                Button { model.tab = kind } label: {
                    VStack(spacing: 8) {
                        HStack(spacing: 5) {
                            Text(kind.tabTitle(short: short))
                                .font(active ? Ink.tabActive : Ink.tab)
                                .foregroundStyle(active ? Ink.primary : Ink.secondary)
                            if let count = section?.items.count, count > 0 {
                                Text(verbatim: "\(count)")
                                    .font(Ink.meta)
                                    .monospacedDigit()
                                    .foregroundStyle(unseen > 0 ? Ink.green : Ink.tertiary)
                            }
                        }
                        Capsule().fill(active ? Ink.primary : .clear).frame(height: 2)
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private func list(_ input: PanelInput, _ section: MenuSection?) -> some View {
        if let section, !section.isEmpty {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(section.rows, id: \.self) { row in
                        switch row {
                        case .item(let item):
                            ItemRow(item: item, input: input, open: actions.open)
                        case .group(let repository, let items):
                            GroupRow(repository: repository, items: items, input: input,
                                     expanded: expanded.contains(repository)) {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    if expanded.contains(repository) { expanded.remove(repository) }
                                    else { expanded.insert(repository) }
                                }
                            }
                            if expanded.contains(repository) {
                                ForEach(items) { item in
                                    ItemRow(item: item, input: input, open: actions.open).padding(.leading, 20)
                                }
                            }
                        }
                    }
                    if section.truncated {
                        Text("Showing the first 100. Narrow the filters in Settings to see the rest.")
                            .font(Ink.meta).foregroundStyle(Ink.tertiary)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 372)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Nothing here right now.")
                .font(Ink.body).foregroundStyle(Ink.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
        }
    }

    private func empty(_ input: PanelInput) -> some View {
        let (title, detail): (String, String) = {
            if !input.selectedOrganizations.isEmpty {
                return ("Nothing waiting in these organizations",
                        "Pull requests and issues there will show up here.")
            }
            if input.repositoryFilterActive {
                return ("Nothing waiting in the watched repositories",
                        "Change which repositories GHBar watches in Settings.")
            }
            return ("You're all caught up",
                    "New pull requests and issues on your repositories will show up here.")
        }()
        return VStack(spacing: 6) {
            Image(systemName: "checkmark.circle").font(.system(size: 22, weight: .light)).foregroundStyle(Ink.tertiary)
                .padding(.bottom, 4)
            Text(title).font(Ink.body.weight(.medium))
            Text(detail).font(Ink.meta).foregroundStyle(Ink.secondary).multilineTextAlignment(.center)
            if !input.selectedOrganizations.isEmpty {
                Button("Show all organizations", action: actions.clearOrganizations).buttonStyle(QuietButtonStyle())
                    .padding(.top, 8)
            } else if input.repositoryFilterActive {
                Button("Open Settings", action: actions.openSettings).buttonStyle(QuietButtonStyle())
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
        .padding(.vertical, 34)
    }

    // MARK: footer

    private func footer(_ input: PanelInput) -> some View {
        let kinds = kinds(input)
        let tab = current(input, kinds)
        let unseen = tab.flatMap { section($0, input) }?.unseenCount(input.isSeen) ?? 0
        return VStack(spacing: 0) {
            Rectangle().fill(Ink.hairline).frame(height: 1)
            HStack {
                if let tab, unseen > 0 {
                    Button("Mark these as seen") { actions.markSectionSeen(tab) }
                        .buttonStyle(.plain)
                        .font(Ink.meta)
                        .foregroundStyle(Ink.secondary)
                }
                Spacer()
                Text(status(input)).font(Ink.meta).foregroundStyle(Ink.tertiary)
            }
            .padding(.horizontal, 18)
            .frame(height: 38)
        }
    }

    private func status(_ input: PanelInput) -> String {
        if let limit = input.rateLimit, input.rateLimitVisibility.shows(limit) {
            return "\(Formatting.grouped(limit.remaining)) API calls left"
        }
        if input.isRefreshing { return "Refreshing" }
        guard let last = input.lastRefresh else { return "" }
        return "Updated \(Self.clock.string(from: last))"
    }

    // MARK: signed out

    private var signedOut: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 52, height: 52)
                .padding(.bottom, 6)
            Text("Sign in to GitHub").font(Ink.name)
            Text("GHBar shows the pull requests and issues people open on your repositories.")
                .font(Ink.meta).foregroundStyle(Ink.secondary).multilineTextAlignment(.center)
            Button("Sign in", action: actions.signIn).buttonStyle(QuietButtonStyle(prominent: true))
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 34)
        .padding(.vertical, 30)
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()
}

// MARK: - rows

/// One pull request or issue: who sent it, what it is, where, and how long ago.
struct ItemRow: View {
    let item: Item
    let input: PanelInput
    let open: (Item) -> Void
    @State private var hover = false

    var body: some View {
        let seen = input.isSeen(item.url)
        Button { open(item) } label: {
            HStack(alignment: .top, spacing: 11) {
                AuthorAvatar(login: item.authorLogin, isBot: item.authorIsBot)
                    .frame(width: 28, height: 28)
                    .opacity(seen ? 0.6 : 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.title)
                            .font(seen ? Ink.body : Ink.body.weight(.medium))
                            .foregroundStyle(seen ? Ink.secondary : Ink.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Text(verbatim: Formatting.age(of: item.createdAt, now: input.now))
                            .font(Ink.meta).monospacedDigit().foregroundStyle(Ink.tertiary)
                    }
                    HStack(spacing: 0) {
                        Text(verbatim: "\(input.showOwner ? item.repository : item.repositoryName) #\(item.number)")
                            .foregroundStyle(Ink.secondary)
                        Text(verbatim: " by \(item.authorLogin)").foregroundStyle(Ink.tertiary)
                        if item.isDraft { Text(", draft").foregroundStyle(Ink.tertiary) }
                    }
                    .font(Ink.meta)
                    .lineLimit(1)
                }
                Circle().fill(seen ? Color.clear : Ink.green).frame(width: 6, height: 6).padding(.top, 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover ? Ink.raised : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(item.title)
        .accessibilityLabel("\(item.repositoryName) number \(item.number), \(item.title), by \(item.authorLogin), \(seen ? "read" : "unread")")
    }
}

/// Several items from one repository folded into a row that opens in place.
struct GroupRow: View {
    let repository: String
    let items: [Item]
    let input: PanelInput
    let expanded: Bool
    let toggle: () -> Void
    @State private var hover = false

    var body: some View {
        let unseen = items.contains { !input.isSeen($0.url) }
        let name = input.showOwner ? repository : (repository.split(separator: "/").last.map(String.init) ?? repository)
        Button(action: toggle) {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Ink.raised)
                    .frame(width: 28, height: 28)
                    .overlay(Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(Ink.secondary))
                Text(verbatim: name).font(unseen ? Ink.body.weight(.medium) : Ink.body)
                    .foregroundStyle(unseen ? Ink.primary : Ink.secondary)
                    .lineLimit(1)
                Text(verbatim: "\(items.count)").font(Ink.meta).monospacedDigit()
                    .foregroundStyle(unseen ? Ink.green : Ink.tertiary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Ink.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover ? Ink.raised : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel("\(name), \(items.count) items, \(expanded ? "expanded" : "collapsed")")
    }
}

// MARK: - pieces

enum Ink {
    /// The graphite of the app icon, and its green.
    static let panel = Color(red: 0.090, green: 0.098, blue: 0.118)
    static let raised = Color.white.opacity(0.055)
    static let hairline = Color.white.opacity(0.07)
    static let primary = Color(red: 0.925, green: 0.933, blue: 0.945)
    static let secondary = Color(red: 0.569, green: 0.596, blue: 0.631)
    static let tertiary = Color(red: 0.400, green: 0.424, blue: 0.459)
    static let green = Color(red: 0.200, green: 0.761, blue: 0.369)
    static let warning = Color(red: 0.95, green: 0.66, blue: 0.27)

    static let name = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 13)
    static let meta = Font.system(size: 11.5)
    static let tab = Font.system(size: 12.5)
    static let tabActive = Font.system(size: 12.5, weight: .semibold)
}

struct IconButton: View {
    let symbol: String
    let help: String
    var spinning = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(hover ? Ink.primary : Ink.secondary)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: spinning)
                .frame(width: 28, height: 28)
                .background(Circle().fill(hover ? Ink.raised : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

struct QuietButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Ink.meta.weight(.medium))
            .foregroundStyle(prominent ? Color.black : Ink.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(prominent ? Ink.green : Ink.raised))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct ViewerAvatar: View {
    let viewer: Viewer?

    var body: some View {
        if let image = Avatar.cached(size: 68) {
            Image(nsImage: image).resizable()
        } else if let login = viewer?.login {
            AuthorAvatar(login: login, isBot: false)
        } else {
            InitialAvatar(name: "?")
        }
    }
}

/// The author's GitHub picture once loaded; a lettered circle until then, and for bots.
struct AuthorAvatar: View {
    let login: String
    let isBot: Bool
    @ObservedObject private var store = AuthorAvatars.shared

    var body: some View {
        Group {
            if !isBot, let image = store.image(login) {
                Image(nsImage: image).resizable().clipShape(Circle())
            } else {
                InitialAvatar(name: login, square: isBot)
            }
        }
        .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1).opacity(isBot ? 0 : 1))
    }
}

struct InitialAvatar: View {
    let name: String
    var square = false

    var body: some View {
        let hue = Double(abs(name.lowercased().hashValueStable) % 360) / 360
        let shape = square ? AnyShape(RoundedRectangle(cornerRadius: 7, style: .continuous)) : AnyShape(Circle())
        shape
            .fill(Color(hue: hue, saturation: 0.32, brightness: 0.42))
            .overlay(
                Text(verbatim: String(name.prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
            )
    }
}

private extension String {
    /// Same number on every run, unlike `hashValue`, so a person keeps their colour.
    var hashValueStable: Int {
        unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
    }
}

private extension SectionKind {
    func tabTitle(short: Bool) -> String {
        switch self {
        case .changesRequested: "Changes"
        case .reviewRequested: short ? "Review" : "To review"
        case .pullRequests: short ? "PRs" : "Pull requests"
        case .issues: "Issues"
        case .myPullRequests: short ? "Mine" : "My PRs"
        }
    }
}
