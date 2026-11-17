import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var enableLoginItemOnLaunch = false

    private var panel: IslandPanel!
    private var menuBar: MenuBar!
    private var server: EventServer!
    private var router: SessionRouter!

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = IslandPanel()
        panel.show()

        menuBar = MenuBar(
            onSimulatePrompt: { [weak self] in self?.panel.webView.send(["type": "prompt", "sessionId": "menu"]) },
            onSimulateStop:   { [weak self] in self?.panel.webView.send(["type": "stop", "sessionId": "menu"]) },
            onResetProgress:  { [weak self] in
                StateStore.shared.clear()
                self?.panel.webView.send(["type": "reset"])
            },
            onQuit: { NSApp.terminate(nil) }
        )

        startEventServer()

        if enableLoginItemOnLaunch {
            Settings.shared.launchAtLogin = true
        }

        // Keep the panel over the menu bar when the active Space changes.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.panel.repositionToTargetScreen() }

        panel.webView.onReturnFocus = { [weak self] sessionId in
            self?.panel.resignKey()
            guard let sessionId, let session = self?.router.session(for: sessionId) else { return }
            // TODO: FocusReturner.focus(session) — exact Terminal/iTerm tab.
            NSLog("notch-runner: would return focus to \(session.term ?? "?") \(session.tty ?? "?")")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    private func startEventServer() {
        router = SessionRouter()
        router.send = { [weak self] event in self?.panel.webView.send(event) }

        server = EventServer()
        server.onEvent = { [weak self] event in
            guard let self, Settings.shared.enabled else { return }
            self.router.handle(event)
        }
        do {
            try server.start()
        } catch {
            NSLog("notch-runner: event server could not start: \(error)")
        }
    }
}
