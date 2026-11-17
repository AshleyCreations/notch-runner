import AppKit
import Carbon.OpenScripting

/// Puts the user back where they were typing. Terminal and iTerm can be driven
/// down to the exact tab over Apple Events; everything else only gets plain app
/// activation, which is why we also remember whatever was frontmost when the
/// prompt arrived.
enum FocusReturner {
    /// Set once Apple Events are refused, so we never prompt again this install.
    private static let deniedKey = "appleEventsDenied"
    private static var appleEventsDenied: Bool {
        get { UserDefaults.standard.bool(forKey: deniedKey) }
        set { UserDefaults.standard.set(newValue, forKey: deniedKey) }
    }

    static func focus(_ session: Session) {
        if !appleEventsDenied, let tty = usableTTY(session) {
            switch session.term {
            case "Apple_Terminal":
                if runScript(terminalScript(tty: tty)) { return }
            case "iTerm.app":
                if runScript(itermScript(tty: tty, uniqueID: itermUniqueID(session))) { return }
            default:
                break   // Warp, ghostty, vscode, Cursor…: no exact-tab story
            }
        }
        activateApp(for: session)
    }

    // MARK: fallback

    /// Prefers whatever was frontmost when the prompt arrived; that handles every
    /// terminal we have no AppleScript for, without hard-coding bundle ids.
    private static func activateApp(for session: Session) {
        let candidates = [session.frontmostBundleId, bundleId(forTerm: session.term)].compactMap { $0 }
        for id in candidates {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                app.activate()
                return
            }
        }
        NSLog("notch-runner: nothing to return focus to for term \(session.term ?? "?")")
    }

    static func bundleId(forTerm term: String?) -> String? {
        switch term {
        case "Apple_Terminal": return "com.apple.Terminal"
        case "iTerm.app":      return "com.googlecode.iterm2"
        case "WarpTerminal":   return "dev.warp.Warp-Stable"
        case "ghostty":        return "com.mitchellh.ghostty"
        case "vscode":         return "com.microsoft.VSCode"
        default:               return nil
        }
    }

    // MARK: AppleScript

    /// The tty is interpolated into a script, so only ever allow the shape a tty
    /// actually has. `ps` returns "??" when the parent has no terminal.
    static func usableTTY(_ session: Session) -> String? {
        guard let tty = session.tty, !tty.isEmpty, tty != "??" else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/-_."))
        guard tty.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
    }

    /// ITERM_SESSION_ID looks like "w0t1p0:UUID"; iTerm's `unique ID` is the tail.
    static func itermUniqueID(_ session: Session) -> String? {
        guard let raw = session.itermSession, let colon = raw.firstIndex(of: ":") else { return nil }
        let id = String(raw[raw.index(after: colon)...])
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        return id.unicodeScalars.allSatisfy(allowed.contains) && !id.isEmpty ? id : nil
    }

    // Targeting by bundle id rather than name: Terminal and iTerm have both been
    // known by more than one application name.
    static func terminalScript(tty: String) -> String {
        """
        tell application id "com.apple.Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if tty of t is "\(tty)" then
                            set selected of t to true
                            set index of w to 1
                            activate
                            return "ok"
                        end if
                    end try
                end repeat
            end repeat
        end tell
        return "notfound"
        """
    }

    static func itermScript(tty: String, uniqueID: String?) -> String {
        let idTest = uniqueID.map { " or (id of s is \"\($0)\")" } ?? ""
        return """
        tell application id "com.googlecode.iterm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        try
                            if (tty of s is "\(tty)")\(idTest) then
                                select w
                                select t
                                select s
                                activate
                                return "ok"
                            end if
                        end try
                    end repeat
                end repeat
            end repeat
        end tell
        return "notfound"
        """
    }

    /// Returns true only when the script actually found and selected the tab.
    @discardableResult
    private static func runScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)

        if let error {
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            // -1743: the user refused. -600/-609: the app is not running.
            if code == -1743 || code == errAEEventNotPermitted {
                NSLog("notch-runner: Apple Events refused; falling back to app activation from now on")
                appleEventsDenied = true
            } else {
                NSLog("notch-runner: focus script failed (\(code)): \(error[NSAppleScript.errorMessage] ?? "")")
            }
            return false
        }
        return result.stringValue == "ok"
    }
}
