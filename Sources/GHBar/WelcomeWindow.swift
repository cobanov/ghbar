import SwiftUI
import Defaults

/// Hos geldin / giris penceresi (spec §11). Token yokken menuden acilir.
@MainActor
final class WelcomeController {

    var onSignedIn: (() -> Void)?
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let root = WelcomeView { [weak self] in
            self?.close()
            self?.onSignedIn?()
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "Welcome to GHBar"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() {
        window?.close()
        window = nil
    }
}

struct WelcomeView: View {

    enum Stage {
        case idle
        case requesting
        case waiting(DeviceCodeGrant)
        case failed(String)
    }

    var onSignedIn: () -> Void
    @State private var stage: Stage = .idle
    @State private var flow: Task<Void, Never>?
    @State private var copied = false
    @Default(.includePrivateRepos) private var includePrivate
    @ObservedObject private var session = AuthSession.shared
    /// The account `gh` is signed in with, looked up once when the window opens.
    @State private var githubCLILogin: String?

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 72, height: 72)
            Text(heading).font(.title2.bold())
            Text(subheading)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch stage {
            case .idle, .failed:
                if case .failed(let message) = stage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                }
                // With gh signed in, using its account is one click and comes first.
                if let login = githubCLILogin, session.state.source != .githubCLI {
                    Button("Continue as @\(login)") {
                        if session.useGitHubCLI() { onSignedIn() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    Text("Uses the account the GitHub CLI (gh) is signed in with.")
                        .font(.caption).foregroundStyle(.tertiary)
                    Divider().padding(.vertical, 2)
                    Button("Sign in with GitHub instead") { start() }
                } else {
                    Button("Sign in with GitHub") { start() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
                Toggle("Include private repositories", isOn: $includePrivate)
                    .toggleStyle(.checkbox)
                Text(includePrivate
                     ? "GHBar will also see your private repositories."
                     : "GHBar will see public repositories only.")
                    .font(.caption).foregroundStyle(.tertiary)

            case .requesting:
                ProgressView().controlSize(.small)
                Button("Cancel", action: cancel)

            case .waiting(let grant):
                Text("Enter this code on GitHub:")
                HStack(spacing: 8) {
                    Text(grant.userCode)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .textSelection(.enabled)
                    Button(copied ? "Copied" : "Copy") { copy(grant.userCode) }
                        .controlSize(.small)
                }
                Text("It is already on your clipboard, and GitHub is open in your browser.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for you to approve on GitHub…").foregroundStyle(.secondary)
                }
                HStack {
                    Button("Open GitHub Again") {
                        if let url = URL(string: grant.verificationURI) { NSWorkspace.shared.open(url) }
                    }
                    Button("Cancel", action: cancel)
                }
            }
        }
        .padding(28)
        .frame(width: 360)
        .task { githubCLILogin = await AuthSession.githubCLILogin() }
        .onDisappear(perform: cancel)
    }

    private var heading: String {
        switch session.state {
        case .expired: "Sign in again"
        case .signedIn: "Change access"
        case .signedOut: "Welcome to GHBar"
        }
    }

    private var subheading: String {
        switch session.state {
        case .expired(.githubCLI):
            "The GitHub CLI is signed out. Sign in with GitHub here, or run gh auth login."
        case .expired:
            "GitHub no longer accepts GHBar's sign-in. It may have been revoked or have expired."
        case .signedIn:
            "Sign in again to switch account or change which repositories GHBar can see."
        case .signedOut:
            "Pull requests and issues people open on your repositories, in the menu bar."
        }
    }

    private func start() {
        stage = .requesting
        copied = false
        let auth = DeviceFlowAuth()
        let includePrivate = includePrivate
        flow = Task { @MainActor in
            do {
                let grant = try await auth.requestCode(includePrivate: includePrivate)
                try Task.checkCancellation()
                stage = .waiting(grant)
                // Kod panoya da konur: kullanici tarayicida yalnizca yapistirir.
                copy(grant.userCode)
                if let url = URL(string: grant.verificationURI) {
                    NSWorkspace.shared.open(url)
                }
                let token = try await auth.waitForToken(grant)
                try Task.checkCancellation()
                session.signedIn(oauthToken: token, privateAccess: includePrivate)
                stage = .idle
                onSignedIn()
            } catch is CancellationError {
                stage = .idle
            } catch DeviceFlowError.denied {
                stage = .failed("Access was denied on GitHub.")
            } catch DeviceFlowError.expired {
                stage = .failed("The code expired. Try again.")
            } catch {
                if Task.isCancelled { stage = .idle; return }
                stage = .failed("Couldn't reach GitHub. Check your connection.")
            }
        }
    }

    private func cancel() {
        flow?.cancel()
        flow = nil
        if case .failed = stage { return }
        stage = .idle
    }

    private func copy(_ code: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copied = true
    }
}
