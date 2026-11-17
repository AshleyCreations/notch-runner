import AppKit

// Status item + menu. The simulate items drive the island without Claude Code,
// which is how the panel and bridge are tested before the event server exists.
final class MenuBar: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let onSimulatePrompt: () -> Void
    private let onSimulateStop: () -> Void
    private let onResetProgress: () -> Void
    private let onQuit: () -> Void

    init(onSimulatePrompt: @escaping () -> Void,
         onSimulateStop: @escaping () -> Void,
         onResetProgress: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.onSimulatePrompt = onSimulatePrompt
        self.onSimulateStop = onSimulateStop
        self.onResetProgress = onResetProgress
        self.onQuit = onQuit
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = item.button {
            // TODO: replace with Bit's silhouette as a template image in Assets.xcassets.
            button.title = "▞"
            button.toolTip = "Notch Runner"
        }

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        add(menu, "Enabled", #selector(toggleEnabled), checked: Settings.shared.enabled)
        menu.addItem(.separator())

        menu.addItem(withTitle: "Tokens saved: \(Self.fmt(StateStore.shared.savedTokens))  ·  Best: \(Self.fmt(StateStore.shared.bestTokens))",
                     action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())

        add(menu, "Simulate prompt", #selector(simulatePrompt))
        add(menu, "Simulate stop", #selector(simulateStop))
        menu.addItem(.separator())

        let settings = NSMenu()
        for ms in [0, 2000, 5000, 10000] {
            let title = ms == 0 ? "Show immediately" : "Show after \(ms / 1000)s"
            let i = add(settings, title, #selector(setShowAfter(_:)), checked: Settings.shared.showAfterMs == ms)
            i.tag = ms
        }
        settings.addItem(.separator())
        add(settings, "Take keyboard when the game opens", #selector(toggleTakesKeyboard), checked: Settings.shared.takesKeyboard)
        add(settings, "Show over full-screen apps", #selector(toggleFullScreen), checked: Settings.shared.showOverFullScreen)
        add(settings, "Launch at login", #selector(toggleLaunchAtLogin), checked: Settings.shared.launchAtLogin)

        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = settings
        menu.addItem(settingsItem)

        add(menu, HookInstaller.isInstalled() ? "Remove hooks" : "Install hooks", #selector(toggleHooks))
        add(menu, "Reset progress", #selector(resetProgress))
        menu.addItem(.separator())
        add(menu, "Quit Notch Runner", #selector(quit), key: "q")
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, checked: Bool = false, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        i.state = checked ? .on : .off
        menu.addItem(i)
        return i
    }

    private static func fmt(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fK", Double(n) / 1000) : String(n)
    }

    @objc private func toggleEnabled() { Settings.shared.enabled.toggle() }
    @objc private func toggleTakesKeyboard() { Settings.shared.takesKeyboard.toggle() }
    @objc private func toggleFullScreen() { Settings.shared.showOverFullScreen.toggle() }
    @objc private func toggleLaunchAtLogin() { Settings.shared.launchAtLogin.toggle() }
    @objc private func setShowAfter(_ sender: NSMenuItem) { Settings.shared.showAfterMs = sender.tag }
    @objc private func simulatePrompt() { onSimulatePrompt() }
    @objc private func simulateStop() { onSimulateStop() }
    @objc private func resetProgress() { onResetProgress() }
    @objc private func quit() { onQuit() }

    @objc private func toggleHooks() {
        _ = HookInstaller.isInstalled() ? HookInstaller.uninstall() : HookInstaller.install()
    }
}
