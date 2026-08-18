import Testing
@testable import GHBar

@Suite("TokenProvider.locate")
struct TokenProviderLocateTests {

    @Test("Apple Silicon konumu once denenir") func homebrewFirst() {
        let found = TokenProvider.locate(
            fileExists: { $0 == "/opt/homebrew/bin/gh" || $0 == "/usr/local/bin/gh" },
            pathEnvironment: nil
        )
        #expect(found == "/opt/homebrew/bin/gh")
    }

    @Test("Intel konumuna duser") func intelFallback() {
        let found = TokenProvider.locate(
            fileExists: { $0 == "/usr/local/bin/gh" },
            pathEnvironment: nil
        )
        #expect(found == "/usr/local/bin/gh")
    }

    @Test("bilinen konumlar yoksa PATH taranir") func pathFallback() {
        let found = TokenProvider.locate(
            fileExists: { $0 == "/custom/bin/gh" },
            pathEnvironment: "/nope:/custom/bin"
        )
        #expect(found == "/custom/bin/gh")
    }

    @Test("hicbir yerde yoksa nil doner, cokmez") func notFound() {
        #expect(TokenProvider.locate(fileExists: { _ in false }, pathEnvironment: "/a:/b") == nil)
    }

    @Test("PATH bos olabilir — .app icinde oyle olur") func emptyPath() {
        #expect(TokenProvider.locate(fileExists: { _ in false }, pathEnvironment: nil) == nil)
    }
}

@Suite("AppError")
struct AppErrorTests {
    @Test("her hatanin kullaniciya gosterilecek metni var") func menuText() {
        #expect(AppError.ghNotFound.menuText == "GitHub CLI not found — install gh")
        #expect(AppError.ghNotAuthenticated.menuText == "Not signed in — run: gh auth login")
        #expect(AppError.allowListEmpty.menuText == "No repositories selected")
    }
}
