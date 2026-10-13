import AppKit
import Combine
import SwiftUI

// A menu bar item whose panel hangs from it by a soft arrow, the way a popover does but drawn
// by us: a borderless, transparent NSPanel holding SwiftUI content that is clipped to
// `ArrowPanelShape`. MenuBarExtra cannot draw the arrow and NSPopover's cannot be restyled.
// Self-contained; the same file drives ATKBar (github.com/cobanov/atkctl).

/// Looks of the panel.
struct ArrowPanelStyle {
    var fill = Color.black
    var border = Color.white.opacity(0.08)
    var cornerRadius: CGFloat = 20
    /// Half the width of the arrow's base, including the flare into the panel's edge.
    var arrowHalfWidth: CGFloat = 17
    var arrowHeight: CGFloat = 9
    /// Space between the menu bar and the arrow's tip.
    var gap: CGFloat = 3
}

/// A rounded rectangle with a bell-shaped arrow rising from its top edge at `arrowX`.
struct ArrowPanelShape: Shape {
    var arrowX: CGFloat
    var style: ArrowPanelStyle

    func path(in rect: CGRect) -> Path {
        let r = style.cornerRadius, h = style.arrowHeight, w = style.arrowHalfWidth
        let top = rect.minY + h
        let ax = min(max(arrowX, rect.minX + r + w), rect.maxX - r - w)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: top))
        p.addLine(to: CGPoint(x: ax - w, y: top))
        // Each side of the arrow is one cubic: it leaves the edge flat and reaches the tip flat,
        // which gives the flared base and the rounded tip without any corner.
        p.addCurve(to: CGPoint(x: ax, y: rect.minY),
                   control1: CGPoint(x: ax - w * 0.48, y: top),
                   control2: CGPoint(x: ax - w * 0.36, y: rect.minY))
        p.addCurve(to: CGPoint(x: ax + w, y: top),
                   control1: CGPoint(x: ax + w * 0.36, y: rect.minY),
                   control2: CGPoint(x: ax + w * 0.48, y: top))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: top))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: top), tangent2End: CGPoint(x: rect.maxX, y: top + r), radius: r)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY), radius: r)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r), radius: r)
        p.addLine(to: CGPoint(x: rect.minX, y: top + r))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: top), tangent2End: CGPoint(x: rect.minX + r, y: top), radius: r)
        p.closeSubpath()
        return p
    }
}

/// Where the arrow sits; changes when the panel is moved to stay on screen.
final class ArrowPosition: ObservableObject {
    @Published var x: CGFloat = 0
}

struct ArrowPanelContainer: View {
    @ObservedObject var position: ArrowPosition
    let style: ArrowPanelStyle
    let content: AnyView

    var body: some View {
        let shape = ArrowPanelShape(arrowX: position.x, style: style)
        content
            .padding(.top, style.arrowHeight)
            .background(shape.fill(style.fill))
            .clipShape(shape)
            .overlay(shape.stroke(style.border, lineWidth: 1))
            .environment(\.colorScheme, .dark)
    }
}

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Owns the status item and its panel.
@MainActor
final class StatusPanel: NSObject {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: KeyPanel
    private let hosting: NSHostingView<ArrowPanelContainer>
    private let position = ArrowPosition()
    private let style: ArrowPanelStyle
    private var monitors: [Any] = []
    private var resignObserver: NSObjectProtocol?
    private var relayoutPending = false
    /// Called each time the panel opens, before it is shown.
    var onOpen: () -> Void = {}

    var isOpen: Bool { panel.isVisible }

    init<Content: View>(style: ArrowPanelStyle = ArrowPanelStyle(), @ViewBuilder content: () -> Content) {
        self.style = style
        hosting = NSHostingView(rootView: ArrowPanelContainer(position: position, style: style, content: AnyView(content())))
        panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        // SwiftUI content is forced dark; this makes the tooltips and menus match it.
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isReleasedWhenClosed = false
        // NSPanel hides itself whenever its app is not frontmost, and an accessory app is not
        // made frontmost reliably; the outside-click monitor closes it instead.
        panel.hidesOnDeactivate = false
        panel.contentView = hosting
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
    }

    @objc func toggle() {
        isOpen ? close() : open()
    }

    func open() {
        guard !isOpen else { return }
        onOpen()
        NSApp.activate(ignoringOtherApps: true)
        layout()
        // No fade-in: a window alpha animation does not run while an accessory app is in the
        // background, which left the panel ordered in but fully transparent.
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)
        // Any click outside the app closes the panel, as with a menu; so does Escape.
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in self?.close() }
            } as Any,
            // Clicks in the app's own windows (Settings, Welcome) close it too; clicks in the
            // panel, its menus and the status item do not.
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                if let self, let window = event.window, window !== self.panel,
                   window !== self.statusItem.button?.window, !(window.className.contains("Menu")) {
                    self.close()
                }
                return event
            } as Any,
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53, let self, event.window === self.panel else { return event }
                self.close()
                return nil
            } as Any,
        ]
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    func close() {
        guard isOpen else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        statusItem.button?.highlight(false)
        panel.orderOut(nil)
    }

    /// Call when the content may have changed size; the panel keeps its top under the menu bar.
    func contentChanged() {
        guard isOpen, !relayoutPending else { return }
        relayoutPending = true
        DispatchQueue.main.async { [weak self] in
            self?.relayoutPending = false
            self?.layout()
        }
    }

    private func layout() {
        guard let button = statusItem.button, let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = hosting.fittingSize
        let visible = screen.visibleFrame
        let x = min(max(anchor.midX - size.width / 2, visible.minX + 8), visible.maxX - 8 - size.width)
        position.x = anchor.midX - x
        panel.setFrame(NSRect(x: x, y: anchor.minY - style.gap - size.height, width: size.width, height: size.height),
                       display: true)
        // The shadow follows what is drawn, so recompute it once SwiftUI has drawn the new shape.
        DispatchQueue.main.async { [weak panel] in panel?.invalidateShadow() }
    }
}

/// Shows a pop-up menu of choices at the mouse, ticking the current one. SwiftUI's `Menu`
/// flattens custom labels on macOS, so tiles open this instead.
@MainActor
enum ChoiceMenu {
    private final class Action: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func runAction() { run() }
    }

    static func show<T: Equatable>(_ choices: [T], current: T?, title: (T) -> String, pick: @escaping (T) -> Void) {
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .darkAqua)
        var selected: NSMenuItem?
        for choice in choices {
            let action = Action { pick(choice) }
            let item = NSMenuItem(title: title(choice), action: #selector(Action.runAction), keyEquivalent: "")
            item.target = action
            item.representedObject = action  // the menu item keeps its action alive
            if choice == current { item.state = .on; selected = item }
            menu.addItem(item)
        }
        menu.popUp(positioning: selected, at: NSEvent.mouseLocation, in: nil)
    }

    enum Entry {
        case action(String, checked: Bool = false, () -> Void)
        case header(String)
        case separator
    }

    static func show(_ entries: [Entry]) {
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .darkAqua)
        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .header(let title):
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            case .action(let title, let checked, let run):
                let action = Action(run)
                let item = NSMenuItem(title: title, action: #selector(Action.runAction), keyEquivalent: "")
                item.target = action
                item.representedObject = action
                item.state = checked ? .on : .off
                menu.addItem(item)
            }
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}
