import AppKit
import ServiceManagement

// UserDefaults-backed settings, surfaced in the menu-bar Settings… submenu.
final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    private enum Key {
        static let enabled = "enabled"
        static let showAfterMs = "showAfterMs"
        static let takesKeyboard = "takesKeyboard"
        static let showOverFullScreen = "showOverFullScreen"
    }

    init() {
        d.register(defaults: [
            Key.enabled: true,
            Key.showAfterMs: 30_000,
            Key.takesKeyboard: true,
            Key.showOverFullScreen: false,
        ])
    }

    var enabled: Bool {
        get { d.bool(forKey: Key.enabled) }
        set { d.set(newValue, forKey: Key.enabled) }
    }

    /// Only open the island if Claude is *still* working after this long, so a
    /// quick answer never gets one. Measured, not predicted.
    var showAfterMs: Int {
        get { d.integer(forKey: Key.showAfterMs) }
        set { d.set(newValue, forKey: Key.showAfterMs) }
    }

    /// The user has just sent a prompt, so taking the keyboard is safe by default.
    var takesKeyboard: Bool {
        get { d.bool(forKey: Key.takesKeyboard) }
        set { d.set(newValue, forKey: Key.takesKeyboard) }
    }

    var showOverFullScreen: Bool {
        get { d.bool(forKey: Key.showOverFullScreen) }
        set { d.set(newValue, forKey: Key.showOverFullScreen) }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("notch-runner: login item: \(error)")
            }
        }
    }

    /// The CONFIG overrides sent to the web view once it reports ready.
    var webConfig: [String: Any] {
        ["showAfterMs": showAfterMs]
    }
}
