import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var enableLoginItemOnLaunch = false

    private var panel: IslandPanel!
    private var menuBar: MenuBar!

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

        if enableLoginItemOnLaunch {
            Settings.shared.launchAtLogin = true
        }

        // Keep the panel over the menu bar when the active Space changes.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.panel.repositionToTargetScreen() }
    }
}
