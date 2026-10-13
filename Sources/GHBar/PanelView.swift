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
    /// Bumped each time the panel opens, so the view can take keyboard focus.
    @Published var opened = 0
    var actions = PanelActions()
}

/// The panel under the menu bar item: who you are, then the work waiting for you, one kind at a
/// time. Green means one thing only: something you have not seen yet.
struct PanelView: View {
    @ObservedObject var model: PanelModel
    @State private var expanded: Set<String> = []
    /// The row the arrow keys are on: an item's URL or a group's key.
    @State private var cursor: String?
    @FocusState private var focused: Bool

    private var actions: PanelActions { model.actions }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let input = model.input {
                if input.isSignedOut {
                    signedOut(input.auth, refused: input.authRefused)
                } else {
                    header(input)
                    if !input.errors.isEmpty || !input.notices.isEmpty { errors(input) }
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
        // The panel works from the keyboard: arrows move between rows and tabs, Return opens.
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return]) { press in
            handle(press.key) ? .handled : .ignored
        }
        .onChange(of: model.opened) {
            cursor = nil
            focused = true
        }
        .onAppear { focused = true }
    }

    // MARK: keyboard

    /// A row as the arrow keys see it: items, groups, and the items of open groups, in order.
    private enum Entry {
        case item(Item)
        case group(key: String, items: [Item])

        var id: String {
            switch self {
            case .item(let item): item.url
            case .group(let key, _): key
            }
        }
    }

    private func entries(_ section: MenuSection) -> [Entry] {
        section.rows.flatMap { row -> [Entry] in
            switch row {
            case .item(let item):
                return [.item(item)]
            case .group(let repository, let items):
                let key = "\(section.kind.rawValue)/\(repository)"
                return [.group(key: key, items: items)] + (expanded.contains(key) ? items.map(Entry.item) : [])
            }
        }
    }

    private func handle(_ key: KeyEquivalent) -> Bool {
        guard let input = model.input, !input.isSignedOut else { return false }
        let kinds = kinds(input)
        guard let tab = current(input, kinds) else { return false }
        switch key {
        case .leftArrow, .rightArrow:
            guard let index = kinds.firstIndex(of: tab) else { return false }
            let next = index + (key == .rightArrow ? 1 : -1)
            guard kinds.indices.contains(next) else { return true }
            model.tab = kinds[next]
            cursor = nil
        case .upArrow, .downArrow:
            guard let section = section(tab, input) else { return true }
            let ids = entries(section).map(\.id)
            guard !ids.isEmpty else { return true }
            let index = cursor.flatMap(ids.firstIndex(of:))
            let next = switch (index, key == .downArrow) {
            case (nil, true): 0
            case (nil, false): ids.count - 1
            case (let i?, true): min(i + 1, ids.count - 1)
            case (let i?, false): max(i - 1, 0)
            }
            cursor = ids[next]
        case .return:
            guard let section = section(tab, input),
                  let entry = entries(section).first(where: { $0.id == cursor }) else { return true }
            switch entry {
            case .item(let item): actions.open(item)
            case .group(let key, _):
                withAnimation(.easeOut(duration: 0.18)) {
                    if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
                }
            }
        default:
            return false
        }
        return true
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
            HStack(alignment: .top, spacing: 6) {
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
                            if let social = input.social { counters(social) }
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
        let stars = counter(Self.compact(social.stars) + (social.starsAreExact ? "" : "+"), "stars")
        let followers = counter(Self.compact(social.followers), "followers")
        let following = counter(Self.compact(social.following), "following")
        // Whole counters or none: a cut-off "123…" reads worse than a missing one.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { stars; followers; following }
            HStack(spacing: 8) { stars; followers }
            stars
        }
    }

    private func counter(_ value: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(verbatim: value).foregroundStyle(Ink.secondary)
            Text(label).foregroundStyle(Ink.tertiary)
        }
        .font(Ink.meta)
        .fixedSize()
    }

    private func organizations(_ input: PanelInput) -> some View {
        let selected = input.selectedOrganizations
        // No organization picked means your own repositories; picking one switches to what is
        // assigned to you there (Query.build), so the labels say that.
        let label = selected.isEmpty ? "Your repositories"
            : selected.count == 1 ? "Assigned to you in \(selected[0])" : "Assigned to you in \(selected.count) organizations"
        return Button {
            ChoiceMenu.show(
                [.action("Your repositories", checked: selected.isEmpty, actions.clearOrganizations),
                 .separator, .header("Assigned to you in")]
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
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Only a failed refresh leaves older data on screen; say how old.
            if !input.errors.isEmpty, let last = input.lastRefresh {
                Text("Showing what was there \(Self.when(last, now: input.now)).")
                    .font(Ink.meta).foregroundStyle(Ink.tertiary)
            }
            ForEach(input.notices, id: \.self) { notice in
                Label(notice, systemImage: "info.circle")
                    .font(Ink.meta)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    /// "at 14:32" today, "on 12 Oct at 14:32" before.
    private static func when(_ date: Date, now: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now)
            ? "at \(clock.string(from: date))"
            : "on \(day.string(from: date)) at \(clock.string(from: date))"
    }

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM"
        return f
    }()

    /// 2,611 stays as it is; 12,345 becomes 12.3k, so the header never outgrows the panel.
    static func compact(_ value: Int) -> String {
        value < 10_000 ? Formatting.grouped(value) : String(format: "%.1fk", Double(value) / 1000)
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
            tabRow(input, kinds, current: current, short: false, counts: true)
            tabRow(input, kinds, current: current, short: true, counts: true)
            tabRow(input, kinds, current: current, short: true, counts: false)
        }
        .padding(.horizontal, 18)
    }

    private func tabRow(_ input: PanelInput, _ kinds: [SectionKind], current: SectionKind,
                        short: Bool, counts: Bool) -> some View {
        HStack(spacing: counts ? 18 : 14) {
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
                            // Green counts what is new; grey counts everything when nothing is.
                            if counts, let total = section?.items.count, total > 0 {
                                Text(verbatim: "\(unseen > 0 ? unseen : total)")
                                    .font(Ink.meta)
                                    .monospacedDigit()
                                    .foregroundStyle(unseen > 0 ? Ink.green : Ink.tertiary)
                            } else if !counts, unseen > 0 {
                                Circle().fill(Ink.green).frame(width: 5, height: 5)
                            }
                        }
                        Capsule().fill(active ? Ink.primary : .clear).frame(height: 2)
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kind.title)
                .accessibilityValue("\(section?.items.count ?? 0) items, \(unseen) unseen")
                .accessibilityAddTraits(active ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private func list(_ input: PanelInput, _ section: MenuSection?) -> some View {
        if let section, !section.isEmpty {
            ScrollViewReader { scroller in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(section.rows, id: \.self) { row in
                        switch row {
                        case .item(let item):
                            ItemRow(item: item, input: input, selected: cursor == item.url, open: actions.open)
                                .id(item.url)
                        case .group(let repository, let items):
                            let key = "\(section.kind.rawValue)/\(repository)"
                            GroupRow(repository: repository, items: items, input: input,
                                     expanded: expanded.contains(key), selected: cursor == key) {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    if expanded.contains(key) { expanded.remove(key) }
                                    else { expanded.insert(key) }
                                }
                            }
                            .id(key)
                            if expanded.contains(key) {
                                ForEach(items) { item in
                                    ItemRow(item: item, input: input, selected: cursor == item.url, open: actions.open)
                                        .padding(.leading, 20)
                                        .id(item.url)
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
            .onChange(of: cursor) {
                if let cursor { withAnimation(.easeOut(duration: 0.12)) { scroller.scrollTo(cursor) } }
            }
            }
        } else {
            Text("Nothing here right now.")
                .font(Ink.body).foregroundStyle(Ink.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
        }
    }

    private func empty(_ input: PanelInput) -> some View {
        let (title, detail): (String, String) = {
            if input.visibleSections.isEmpty {
                return ("All tabs are turned off", "Choose which tabs to show in Settings.")
            }
            if !input.selectedOrganizations.isEmpty {
                return ("Nothing assigned to you there",
                        "Pull requests and issues assigned to you in these organizations show up here.")
            }
            if input.repositoryFilterActive {
                return input.repositoryFilterIsAllowList
                    ? ("Nothing waiting in the watched repositories",
                       "Change which repositories GHBar watches in Settings.")
                    : ("You're all caught up",
                       "Some repositories are hidden; manage them in Settings.")
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
            } else if input.repositoryFilterActive || input.visibleSections.isEmpty {
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
                    Button("Mark these as seen") {
                        // Pin the tab first: otherwise the next tab with unseen items takes its
                        // place and the same button would clear that one too.
                        model.tab = tab
                        actions.markSectionSeen(tab)
                    }
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

    private func signedOut(_ auth: AuthState, refused: Bool) -> some View {
        let (title, detail, button): (String, String, String) = {
            switch auth {
            case .expired(.githubCLI):
                return (refused ? "GitHub refused the GitHub CLI's token" : "The GitHub CLI is signed out",
                        auth.expiryMessage(refused: refused), "Sign in with GitHub")
            case .expired:
                return ("Sign in again", auth.expiryMessage(refused: refused), "Sign in again")
            default:
                return ("Sign in to GitHub",
                        "GHBar shows the pull requests and issues people open on your repositories.", "Sign in")
            }
        }()
        return VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 52, height: 52)
                .padding(.bottom, 6)
            Text(title).font(Ink.name)
            Text(detail)
                .font(Ink.meta).foregroundStyle(Ink.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(button, action: actions.signIn).buttonStyle(QuietButtonStyle(prominent: true))
                .padding(.top, 10)
            HStack(spacing: 14) {
                Button("Settings", action: actions.openSettings)
                Button("Quit", action: actions.quit)
            }
            .buttonStyle(.plain)
            .font(Ink.meta)
            .foregroundStyle(Ink.tertiary)
            .padding(.top, 6)
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
    var selected = false
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
                        Text(verbatim: input.showOwner ? item.repository : item.repositoryName)
                            .foregroundStyle(Ink.secondary)
                            .truncationMode(.middle)
                            .layoutPriority(1)
                        Text(verbatim: " #\(item.number)").foregroundStyle(Ink.secondary)
                            .fixedSize()
                            .layoutPriority(3)
                        Text(verbatim: " by \(item.authorLogin)\(item.isDraft ? ", draft" : "")")
                            .foregroundStyle(Ink.tertiary)
                    }
                    .font(Ink.meta)
                    .lineLimit(1)
                }
                Circle().fill(seen ? Color.clear : Ink.green).frame(width: 6, height: 6).padding(.top, 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover || selected ? Ink.raised : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(item.title)
        .accessibilityLabel([
            "\(item.repositoryName) number \(item.number)",
            item.kind == .issue ? "issue" : (item.isDraft ? "draft pull request" : "pull request"),
            item.title,
            "by \(item.authorLogin)",
            Formatting.spokenAge(of: item.createdAt, now: input.now),
            seen ? "read" : "unread",
        ].joined(separator: ", "))
    }
}

/// Several items from one repository folded into a row that opens in place.
struct GroupRow: View {
    let repository: String
    let items: [Item]
    let input: PanelInput
    let expanded: Bool
    var selected = false
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
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover || selected ? Ink.raised : .clear))
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
    /// 5.3:1 on the panel, 4.6:1 on a hovered row: WCAG AA for small text.
    static let tertiary = Color(red: 0.530, green: 0.550, blue: 0.590)
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
            // Driven by the clock rather than a repeating animation, which keeps running
            // (or winds backwards) after `spinning` turns false.
            TimelineView(.animation(paused: !spinning)) { context in
                Image(systemName: symbol)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(hover ? Ink.primary : Ink.secondary)
                    .rotationEffect(.degrees(spinning ? Self.angle(at: context.date) : 0))
            }
            .frame(width: 28, height: 28)
            .background(Circle().fill(hover ? Ink.raised : .clear))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }

    /// One turn every 0.9 seconds.
    private static func angle(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360
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

extension SectionKind {
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
