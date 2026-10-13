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

@Suite("Auth.resolve")
struct AuthResolveTests {
    private func inputs(_ recorded: AuthSource?, signedOut: Bool = false, existing: Bool = true,
                        keychain: String? = nil, gh: String? = nil) -> Auth.Inputs {
        Auth.Inputs(recorded: recorded, signedOutByUser: signedOut, existingInstall: existing,
                    keychainToken: { keychain }, ghToken: { gh })
    }

    @Test("nothing anywhere: signed out") func nothing() {
        #expect(Auth.resolve(inputs(nil)) == nil)
    }

    @Test("first launch adopts the Keychain token before gh") func keychainFirst() {
        let r = Auth.resolve(inputs(nil, keychain: "gho_oauth", gh: "gho_gh"))
        #expect(r?.token == "gho_oauth" && r?.source == .oauth)
    }

    @Test("an install from before 0.3 keeps using gh") func ghAdopted() {
        let r = Auth.resolve(inputs(nil, gh: "gho_gh"))
        #expect(r?.token == "gho_gh" && r?.source == .githubCLI)
    }

    @Test("a new install is not signed in through gh without choosing it") func newInstallAsks() {
        #expect(Auth.resolve(inputs(nil, existing: false, gh: "gho_gh")) == nil)
        #expect(Auth.resolve(inputs(nil, existing: false, keychain: "gho_oauth"))?.source == .oauth)
    }

    @Test("after Sign Out, a signed-in gh is not picked up again") func signOutSticks() {
        #expect(Auth.resolve(inputs(nil, signedOut: true, gh: "gho_gh")) == nil)
    }

    @Test("a recorded source is the only one tried") func recordedOnly() {
        #expect(Auth.resolve(inputs(.oauth, gh: "gho_gh")) == nil)
        #expect(Auth.resolve(inputs(.githubCLI, keychain: "gho_oauth")) == nil)
        #expect(Auth.resolve(inputs(.githubCLI, gh: "gho_gh"))?.source == .githubCLI)
    }
}

@Suite("AuthState")
struct AuthStateTests {
    @Test("source and signed-in flag") func basics() {
        #expect(AuthState.signedIn(.oauth).isSignedIn)
        #expect(!AuthState.expired(.oauth).isSignedIn)
        #expect(AuthState.expired(.githubCLI).source == .githubCLI)
        #expect(AuthState.signedOut.source == nil)
    }

    @Test("expiry messages tell a refused token from a missing one") func expiryMessages() {
        #expect(AuthState.expired(.githubCLI).expiryMessage(refused: true).contains("refused"))
        #expect(AuthState.expired(.githubCLI).expiryMessage(refused: false).contains("signed out"))
        #expect(AuthState.expired(.oauth).expiryMessage(refused: true).contains("no longer accepts"))
        #expect(AuthState.expired(.oauth).expiryMessage(refused: false).contains("Keychain"))
    }
}
