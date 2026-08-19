import AppKit

// Gizli bayrak: App Store ekran goruntulerini uretir ve cikar.
// Kullanim: swift run GHBar --render-screens <dizin>   (make screens)
if let flagIndex = CommandLine.arguments.firstIndex(of: "--render-screens") {
    _ = NSApplication.shared   // SwiftUI render icin app baglami yeterli, run() gerekmez
    let directory = CommandLine.arguments.indices.contains(flagIndex + 1)
        ? CommandLine.arguments[flagIndex + 1]
        : "build/screens"
    MainActor.assumeIsolated {
        ScreenshotRenderer.renderAll(to: directory)
    }
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
