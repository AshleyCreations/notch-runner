import Foundation

// Only the pure helpers are exercised here. Driving a real Apple Event would
// pop the automation permission dialog, which no test should do.

var failures = 0
func check(_ name: String, _ got: String?, _ want: String?) {
    if got == want { print("  PASS  \(name)  \(got.map { "\"\($0)\"" } ?? "nil")") }
    else { print("  FAIL  \(name)\n        got:  \(got ?? "nil")\n        want: \(want ?? "nil")"); failures += 1 }
}

func session(tty: String? = nil, term: String? = nil, iterm: String? = nil, frontmost: String? = nil) -> Session {
    Session(id: "s", startedAt: Date(), tty: tty, term: term, termSession: nil,
            itermSession: iterm, cwd: nil, frontmostBundleId: frontmost, isWorking: true)
}

print("FocusReturner")

// tty normalisation
check("bare tty gets /dev/",        FocusReturner.usableTTY(session(tty: "ttys003")), "/dev/ttys003")
check("absolute tty kept",          FocusReturner.usableTTY(session(tty: "/dev/ttys012")), "/dev/ttys012")
check("ps '??' is unusable",        FocusReturner.usableTTY(session(tty: "??")), nil)
check("empty is unusable",          FocusReturner.usableTTY(session(tty: "")), nil)
check("missing is unusable",        FocusReturner.usableTTY(session(tty: nil)), nil)

// the tty is interpolated into a script, so anything script-shaped must be refused
check("quote rejected",             FocusReturner.usableTTY(session(tty: "ttys0\" & (do shell script \"id\") & \"")), nil)
check("space rejected",             FocusReturner.usableTTY(session(tty: "ttys003 foo")), nil)
check("newline rejected",           FocusReturner.usableTTY(session(tty: "ttys003\nactivate")), nil)

// ITERM_SESSION_ID → unique id
check("iterm id after the colon",   FocusReturner.itermUniqueID(session(iterm: "w0t1p0:ABC-123-DEF")), "ABC-123-DEF")
check("no colon, no id",            FocusReturner.itermUniqueID(session(iterm: "w0t1p0")), nil)
check("empty tail, no id",          FocusReturner.itermUniqueID(session(iterm: "w0t1p0:")), nil)
check("quote in id rejected",       FocusReturner.itermUniqueID(session(iterm: "w0:a\"b")), nil)

// generated scripts
let term = FocusReturner.terminalScript(tty: "/dev/ttys003")
check("targets Terminal by bundle id", term.contains("application id \"com.apple.Terminal\"") ? "yes" : "no", "yes")
check("matches on the tty",            term.contains("tty of t is \"/dev/ttys003\"") ? "yes" : "no", "yes")

let itermBoth = FocusReturner.itermScript(tty: "/dev/ttys003", uniqueID: "ABC-123")
check("iterm matches tty or unique id", itermBoth.contains("or (id of s is \"ABC-123\")") ? "yes" : "no", "yes")
let itermTTYOnly = FocusReturner.itermScript(tty: "/dev/ttys003", uniqueID: nil)
check("no id clause when absent",       itermTTYOnly.contains("id of s") ? "yes" : "no", "no")

// fallback bundle ids
check("Apple_Terminal", FocusReturner.bundleId(forTerm: "Apple_Terminal"), "com.apple.Terminal")
check("iTerm.app",      FocusReturner.bundleId(forTerm: "iTerm.app"), "com.googlecode.iterm2")
check("unknown term",   FocusReturner.bundleId(forTerm: "SomeNewTerminal"), nil)

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
