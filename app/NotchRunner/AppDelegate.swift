import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var enableLoginItemOnLaunch = false

    private var panel: IslandPanel!
    private var menuBar: MenuBar!
    private var server: EventServer!

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
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    private func startEventServer() {
        server = EventServer()
        server.onEvent = { [weak self] event in self?.route(event) }
        do {
            try server.start()
        } catch {
            NSLog("notch-runner: event server could not start: \(error)")
        }
    }

    /// Straight pass-through for now. SessionRouter replaces this: it tracks one
    /// Session per session_id so the island stays open until the LAST one stops,
    /// debounces a stop that lands within 300 ms of its prompt, and folds away on
    /// the stuck timeout when an Esc interrupt means no Stop ever arrives.
    private func route(_ event: HookEvent) {
        guard Settings.shared.enabled else { return }
        let sessionId = event.hook?.session_id ?? "unknown"

        switch event.event {
        case "prompt":
            panel.webView.send(["type": "prompt", "sessionId": sessionId])
        case "stop", "end":
            panel.webView.send(["type": "stop", "sessionId": sessionId])
        default:
            NSLog("notch-runner: ignoring unknown event \(event.event)")
        }
    }
}
