import AppKit

/// Pull request and issue authors' pictures, fetched once from GitHub and kept in the cache folder.
@MainActor
final class AuthorAvatars: ObservableObject {
    static let shared = AuthorAvatars()

    @Published private var images: [String: NSImage] = [:]
    /// Set for screenshots: draw initials instead of fetching anyone's picture.
    static var offline = false

    private var pending: Set<String> = []
    /// A failed fetch is tried again after a while, not on every redraw.
    private var failedAt: [String: Date] = [:]

    nonisolated private static let folder = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GHBar/avatars", isDirectory: true)

    /// The picture if it is at hand; otherwise starts loading it (disk, then GitHub) and
    /// returns nil for now. Nothing here blocks the view that asks.
    func image(_ login: String) -> NSImage? {
        guard !Self.offline else { return nil }
        if let image = images[login] { return image }
        if pending.contains(login) { return nil }
        if let failed = failedAt[login], Date().timeIntervalSince(failed) < 600 { return nil }
        pending.insert(login)
        Task {
            let image = await Self.load(login)
            pending.remove(login)
            if let image { images[login] = image } else { failedAt[login] = Date() }
        }
        return nil
    }

    nonisolated private static func load(_ login: String) async -> NSImage? {
        let file = folder.appendingPathComponent("\(login).png")
        // A cached picture is refetched after a week, so a changed one shows up eventually.
        let age = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate.map { Date().timeIntervalSince($0) } ?? .infinity
        if age < 7 * 86_400, let image = NSImage(contentsOf: file) { return image }

        guard let url = URL(string: "https://avatars.githubusercontent.com/\(login)?s=64"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = NSImage(data: data) else {
            return NSImage(contentsOf: file)   // an old picture beats initials
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file)
        return image
    }

    /// Deletes pictures nobody has needed for a month. Called once at launch.
    nonisolated static func prune() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys) else { return }
        for file in files {
            let modified = (try? file.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(modified) > 30 * 86_400 { try? FileManager.default.removeItem(at: file) }
        }
    }
}
