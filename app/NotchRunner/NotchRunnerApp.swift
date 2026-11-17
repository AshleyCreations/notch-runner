import AppKit

// Menu-bar only (LSUIElement). Also serves as a small CLI so install.sh can
// merge and unmerge the Claude Code hook entries without launching the UI.
@main
enum NotchRunnerMain {
    static func main() {
        let args = CommandLine.arguments

        if args.contains("--install-hooks") {
            exit(HookInstaller.install() ? 0 : 1)
        }
        if args.contains("--uninstall-hooks") {
            exit(HookInstaller.uninstall() ? 0 : 1)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        delegate.enableLoginItemOnLaunch = args.contains("--enable-login-item")
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
