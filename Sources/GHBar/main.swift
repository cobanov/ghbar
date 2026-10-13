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

// Gizli bayrak: paneli ornek veriyle ciz ve cik. Kullanim: swift run GHBar --render-panel out.png
if let flagIndex = CommandLine.arguments.firstIndex(of: "--render-panel"),
   CommandLine.arguments.indices.contains(flagIndex + 1) {
    _ = NSApplication.shared
    MainActor.assumeIsolated { PanelPreview.render(to: CommandLine.arguments[flagIndex + 1]) }
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
