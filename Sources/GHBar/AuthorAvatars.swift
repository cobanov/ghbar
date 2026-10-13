import AppKit

/// Pull request and issue authors' pictures, fetched once from GitHub and kept in the cache folder.
@MainActor
final class AuthorAvatars: ObservableObject {
    static let shared = AuthorAvatars()

    @Published private var images: [String: NSImage] = [:]
    /// Set for screenshots: draw initials instead of fetching anyone's picture.
    static var offline = false
    private var pending: Set<String> = []

    nonisolated private static let folder = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GHBar/avatars", isDirectory: true)

    /// The picture if it is at hand; otherwise starts fetching it and returns nil for now.
    func image(_ login: String) -> NSImage? {
        guard !Self.offline else { return nil }
        if let image = images[login] { return image }
        let file = Self.folder.appendingPathComponent("\(login).png")
        if let image = NSImage(contentsOf: file) {
            DispatchQueue.main.async { self.images[login] = image }
            return image
        }
        guard !pending.contains(login),
              let url = URL(string: "https://avatars.githubusercontent.com/\(login)?s=64") else { return nil }
        pending.insert(login)
        Task {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: data) else { return }
            try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try? data.write(to: file)
            self.pending.remove(login)
            self.images[login] = image
        }
        return nil
    }
}
