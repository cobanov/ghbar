import AppKit
import Foundation

/// Everything the panel draws, gathered by the app delegate after each refresh.
struct PanelInput {
    var viewer: Viewer?
    var social: Social?
    var sections: [MenuSection]
    var rateLimit: RateLimit?
    var errors: [AppError]
    var lastRefresh: Date?
    var auth: AuthState
    var isSignedOut: Bool { !auth.isSignedIn }
    var isRefreshing: Bool = false
    var showOwner: Bool
    var knownOrganizations: [String] = []
    var selectedOrganizations: [String] = []
    /// Whether the repository allow or block list narrows the results, so an empty panel can
    /// say why it is empty.
    var repositoryFilterActive: Bool = false
    var visibleSections: Set<SectionKind>
    /// Keep a tab for each chosen section even when it has nothing in it.
    var showEmptySections: Bool = false
    var rateLimitVisibility: RateLimitVisibility = .whenLow
    var isSeen: (String) -> Bool
    var now: Date
}

/// The menu bar icon: a template, so macOS colours it and inverts it while the panel is open.
enum StatusIcon {
    static func image() -> NSImage? {
        // trianglehead arrives with SF Symbols 6 (macOS 15); the older names cover Sonoma.
        for name in ["arrow.trianglehead.pull", "arrow.triangle.pull", "arrow.triangle.branch"] {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: "GHBar") {
                image.isTemplate = true
                return image
            }
        }
        return nil
    }
}
