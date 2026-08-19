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

private struct WelcomeView: View {

    enum Stage {
        case idle
        case requesting
        case waiting(DeviceCodeGrant)
        case failed(String)
    }

    var onSignedIn: () -> Void
    @State private var stage: Stage = .idle
    @Default(.includePrivateRepos) private var includePrivate

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 72, height: 72)
            Text("GHBar").font(.title.bold())
            Text("Pull requests and issues from your\nrepositories, in the menu bar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            switch stage {
            case .idle, .failed:
                if case .failed(let message) = stage {
                    Text(message).font(.callout).foregroundStyle(.red)
                }
                Button("Sign in with GitHub") { start() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Toggle("Include private repositories", isOn: $includePrivate)
                    .toggleStyle(.checkbox)
                Text(includePrivate
                     ? "Grants the \"repo\" scope."
                     : "Only public repositories will be shown.")
                    .font(.caption).foregroundStyle(.tertiary)

            case .requesting:
                ProgressView().controlSize(.small)

            case .waiting(let grant):
                Text("Enter this code on GitHub:")
                Text(grant.userCode)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
                Button("Open github.com/login/device") {
                    if let url = URL(string: grant.verificationURI) {
                        NSWorkspace.shared.open(url)
                    }
                }
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for approval…").foregroundStyle(.secondary)
                }
            }
        }
        .padding(28)
        .frame(width: 340)
    }

    private func start() {
        stage = .requesting
        let auth = DeviceFlowAuth()
        let includePrivate = includePrivate
        Task { @MainActor in
            do {
                let grant = try await auth.requestCode(includePrivate: includePrivate)
                stage = .waiting(grant)
                // Kod panoya da konur: kullanici tarayicida yalnizca yapistirir.
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(grant.userCode, forType: .string)
                if let url = URL(string: grant.verificationURI) {
                    NSWorkspace.shared.open(url)
                }
                let token = try await auth.waitForToken(grant)
                Keychain.save(token: token)
                onSignedIn()
            } catch DeviceFlowError.denied {
                stage = .failed("Access was denied on GitHub.")
            } catch DeviceFlowError.expired {
                stage = .failed("The code expired — try again.")
            } catch {
                stage = .failed("Couldn't reach GitHub. Check your connection.")
            }
        }
    }
}
