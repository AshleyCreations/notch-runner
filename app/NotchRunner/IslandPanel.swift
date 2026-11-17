import AppKit

// A borderless, non-activating panel pinned to the top centre of the notched
// screen. It is always the full maximum island size; the web view draws the
// actual island inside it and tells us when to stop swallowing clicks.
final class IslandPanel: NSPanel {
    // Max island size (560 x 222) plus a margin, per the spec.
    static let size = NSSize(width: 600, height: 240)

    let webView: IslandWebView

    init() {
        webView = IslandWebView()
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true   // idle: never block the menu bar or apps below

        contentView = webView
        webView.onIslandState = { [weak self] _, interactive in
            self?.ignoresMouseEvents = !interactive
        }
        // onReturnFocus is owned by AppDelegate: it needs the SessionRouter to
        // turn a session id into the terminal to activate.
        webView.onWantsKeyboard = { [weak self] in
            guard Settings.shared.takesKeyboard else { return }
            self?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // Needed for Space, ArrowDown and Esc to reach the web view.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show() {
        repositionToTargetScreen()
        orderFrontRegardless()
        webView.load()
    }

    /// The screen with a notch, else the main screen. The panel's top edge sits
    /// flush with the screen's top so the island appears to grow out of the notch.
    func repositionToTargetScreen() {
        guard let screen = Self.targetScreen() else { return }
        let f = screen.frame
        setFrame(
            NSRect(
                x: f.midX - Self.size.width / 2,
                y: f.maxY - Self.size.height,
                width: Self.size.width,
                height: Self.size.height
            ),
            display: true
        )
        sendNotchWidth(for: screen)
    }

    static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    /// Match the idle island width to the real notch so it disappears into it.
    private func sendNotchWidth(for screen: NSScreen) {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return }
        let notchWidth = screen.frame.width - left.width - right.width
        guard notchWidth > 0 else { return }
        webView.send(["type": "config", "config": ["idleWidth": notchWidth]])
    }
}
