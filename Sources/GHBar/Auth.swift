import Defaults
import Foundation

/// Where the GitHub token comes from. It is recorded, so that signing out cannot quietly fall
/// back to another source and leave the user signed in.
enum AuthSource: String, Sendable {
    case oauth
    case githubCLI
}

enum AuthState: Equatable, Sendable {
    case signedOut
    case signedIn(AuthSource)
    /// The recorded source no longer gives a working token: GitHub rejected it, the Keychain
    /// item is gone, or `gh` was signed out.
    case expired(AuthSource)

    var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }

    var source: AuthSource? {
        switch self {
        case .signedOut: nil
        case .signedIn(let source), .expired(let source): source
        }
    }
}

/// The rule for picking a token, kept pure so it can be tested.
///
/// - A recorded source is the only one tried.
/// - With none recorded, a Keychain token is adopted (an upgrade from 0.2 that signed in).
/// - The GitHub CLI's token is adopted without asking only for an install that already ran on
///   it (0.2 used it silently), and never after Sign Out. A new install offers it in the
///   welcome window instead, so nobody is signed in without having chosen to be.
enum Auth {
    struct Inputs {
        var recorded: AuthSource?
        var signedOutByUser: Bool
        /// GHBar already ran here and saw repositories: an install from before 0.3.
        var existingInstall: Bool
        var keychainToken: () -> String?
        var ghToken: () -> String?
    }

    static func resolve(_ inputs: Inputs) -> (token: String, source: AuthSource)? {
        switch inputs.recorded {
        case .oauth:
            return inputs.keychainToken().map { ($0, .oauth) }
        case .githubCLI:
            return inputs.ghToken().map { ($0, .githubCLI) }
        case nil:
            if let token = inputs.keychainToken() { return (token, .oauth) }
            if inputs.existingInstall, !inputs.signedOutByUser, let token = inputs.ghToken() {
                return (token, .githubCLI)
            }
            return nil
        }
    }
}

/// The one place that knows whether the user is signed in, and how. The panel, the settings
/// window and the welcome window all read it.
@MainActor
final class AuthSession: ObservableObject {
    static let shared = AuthSession()

    @Published private(set) var state: AuthState = .signedOut
    @Published private(set) var login: String? = Defaults[.signedInLogin]
    /// Bumped by every sign-in and sign-out. A refresh notes it before going to the network
    /// and drops its results if it changed meanwhile.
    private(set) var generation = 0

    private var cached: (token: String, source: AuthSource)?
    /// A token GitHub refused this session; `gh` keeps handing out the same one.
    private var rejected: String?

    /// Whether the OAuth token was granted the private-repository scope.
    var privateAccess: Bool { Defaults[.includePrivateRepos] }

    /// The token to use now, adopting a source on first use. Updates `state`. The Keychain
    /// and `gh` are asked off the main thread; `gh` can take a while.
    func token() async -> String? {
        if let cached, state == .signedIn(cached.source) { return cached.token }
        let recorded = Defaults[.authSource].flatMap(AuthSource.init(rawValue:))
        let signedOutByUser = Defaults[.signedOutByUser]
        let existingInstall = !Defaults[.knownRepos].isEmpty
        let resolved = await Task.detached {
            Auth.resolve(Auth.Inputs(
                recorded: recorded,
                signedOutByUser: signedOutByUser,
                existingInstall: existingInstall,
                keychainToken: { Keychain.token() },
                ghToken: { TokenProvider.ghTokenIfAvailable() }
            )).map { [$0.token, $0.source.rawValue] }
        }.value
        guard let resolved, let source = AuthSource(rawValue: resolved[1]), resolved[0] != rejected else {
            state = recorded.map(AuthState.expired) ?? .signedOut
            return nil
        }
        if recorded == nil { Defaults[.authSource] = source.rawValue }
        cached = (resolved[0], source)
        if state != .signedIn(source) { state = .signedIn(source) }
        return resolved[0]
    }

    /// The device flow finished: this token replaces whatever was there before. False if the
    /// Keychain refused it, in which case nothing changed.
    func signedIn(oauthToken token: String, privateAccess: Bool) -> Bool {
        guard Keychain.save(token: token) else { return false }
        Defaults[.includePrivateRepos] = privateAccess
        Defaults[.authSource] = AuthSource.oauth.rawValue
        Defaults[.signedOutByUser] = false
        begin(.signedIn(.oauth), token: (token, .oauth))
        return true
    }

    /// Use the account `gh` is signed in with. False if there is none.
    func useGitHubCLI() async -> Bool {
        guard let token = await Task.detached(operation: { TokenProvider.ghTokenIfAvailable() }).value else {
            return false
        }
        Keychain.delete()
        Defaults[.authSource] = AuthSource.githubCLI.rawValue
        Defaults[.signedOutByUser] = false
        begin(.signedIn(.githubCLI), token: (token, .githubCLI))
        return true
    }

    func signOut() {
        Keychain.delete()
        Defaults[.authSource] = nil
        Defaults[.signedOutByUser] = true
        setLogin(nil)
        begin(.signedOut, token: nil)
    }

    /// GitHub answered 401 for a refresh started in `generation`. An OAuth token that GitHub
    /// refuses is of no further use; a refused `gh` token is not tried again this session.
    func markExpired(generation: Int) {
        guard generation == self.generation, let source = state.source else { return }
        if source == .oauth { Keychain.delete() }
        rejected = cached?.token
        cached = nil
        state = .expired(source)
    }

    /// The account GitHub says the token belongs to.
    func loaded(login: String) {
        if self.login != login { setLogin(login) }
    }

    private func begin(_ state: AuthState, token: (String, AuthSource)?) {
        generation += 1
        cached = token
        rejected = nil
        self.state = state
    }

    private func setLogin(_ login: String?) {
        Defaults[.signedInLogin] = login
        self.login = login
    }

    /// The login `gh` is signed in with, if this build can use the GitHub CLI and it is signed
    /// in. Never in the App Store build, which cannot run other programs.
    nonisolated static func githubCLILogin() async -> String? {
        guard let token = await Task.detached(operation: { TokenProvider.ghTokenIfAvailable() }).value,
              let url = URL(string: "https://api.github.com/user") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["login"] as? String
    }
}
