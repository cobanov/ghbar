import AppKit

/// Profil fotografi.
///
/// Bir kez indirilip diske yaziliyor; sonraki acilislarda diskten okunuyor.
/// Her yenilemede yeniden indirmenin anlami yok — avatar nadiren degisiyor.
/// URL degistiginde (kullanici fotografini degistirdiginde) yeniden iniyor.
enum Avatar {

    private static var directory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GHBar")
    }

    private static var imageURL: URL { directory.appendingPathComponent("avatar.png") }
    private static var stampURL: URL { directory.appendingPathComponent("avatar-source.txt") }

    /// Diskteki fotografi verilen boyutta, daire kirpilmis olarak dondurur.
    static func cached(size: CGFloat) -> NSImage? {
        guard let data = try? Data(contentsOf: imageURL),
              let image = NSImage(data: data) else { return nil }
        return circular(image, size: size)
    }

    /// Gerekliyse indirir. Ayni URL daha once indirildiyse hicbir sey yapmaz
    /// ve false doner — cagiran taraf menuyu yeniden cizip cizmeyecegini
    /// buradan anliyor.
    @discardableResult
    static func refresh(from address: String) async -> Bool {
        let previous = try? String(contentsOf: stampURL, encoding: .utf8)
        if previous == address, FileManager.default.fileExists(atPath: imageURL.path) {
            return false
        }

        guard let url = URL(string: address),
              let (data, _) = try? await URLSession.shared.data(from: url),
              NSImage(data: data) != nil else { return false }

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: imageURL, options: .atomic)
        try? address.write(to: stampURL, atomically: true, encoding: .utf8)
        return true
    }

    // MARK: - Private

    /// GitHub avatarlari kare geliyor; menude yuvarlak gostermek macOS'un
    /// kendi kisi gosterimiyle tutarli.
    private static func circular(_ source: NSImage, size: CGFloat) -> NSImage {
        let target = NSSize(width: size, height: size)
        let output = NSImage(size: target)

        output.lockFocus()
        let bounds = NSRect(origin: .zero, size: target)
        NSBezierPath(ovalIn: bounds).addClip()
        source.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        output.unlockFocus()

        return output
    }
}
