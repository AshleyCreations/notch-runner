import AppKit

// A borderless, non-activating panel pinned to the top centre of the notched
// screen. It is always the full maximum island size; the web view draws the
// actual island inside it and tells us when to stop swallowing clicks.
final class IslandPanel: NSPanel {
    // The panel starts at the idle island's size and then tracks it. It is
    // deliberately NOT fixed at the maximum: an oversized panel with
    // ignoresMouseEvents off swallows clicks across a 600pt band of the menu
    // bar, including the status item that is the only way to close the island.
    static let idleSize = NSSize(width: 186, height: 32)

    let webView: IslandWebView
    private var islandSize = IslandPanel.idleSize
    private var pendingShrink: DispatchWorkItem?
    private let scrim: Scrim

    init() {
        webView = IslandWebView()
        // One level below the island, so the island stays above the dim.
        scrim = Scrim(level: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow))))
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.idleSize),
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
        webView.onIslandState = { [weak self] state, size, interactive in
            guard let self else { return }
            self.ignoresMouseEvents = !interactive
            self.resize(to: size)

            // Only the game strip earns a scrim: peek and done are brief, and
            // dimming the screen for them would just flicker.
            if state == "game", let screen = Self.targetScreen() {
                self.scrim.show(on: screen)
            } else {
                self.scrim.hide()
            }
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

    /// Keeps the panel the same size as the island, so clicks are only taken
    /// where the island actually is. Growing happens up front so the island is
    /// never clipped mid-animation; shrinking waits for the CSS transition.
    private func resize(to size: CGSize) {
        pendingShrink?.cancel()
        pendingShrink = nil
        let growing = size.width > islandSize.width || size.height > islandSize.height
        islandSize = size

        if growing {
            repositionToTargetScreen()
        } else {
            let work = DispatchWorkItem { [weak self] in self?.repositionToTargetScreen() }
            pendingShrink = work
            // Matches the .island width/height transition in the stylesheet.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
        }
    }

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
                x: f.midX - islandSize.width / 2,
                y: f.maxY - islandSize.height,
                width: islandSize.width,
                height: islandSize.height
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
