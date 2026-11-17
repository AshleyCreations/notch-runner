import Foundation

var failures = 0
func ev(_ type: String, _ id: String, tty: String? = nil, term: String? = nil, cwd: String? = nil) -> HookEvent {
    let json = """
    {"event":"\(type)","tty":\(tty.map{"\"\($0)\""} ?? "null"),"term":\(term.map{"\"\($0)\""} ?? "null"),
     "termSession":null,"itermSession":null,
     "hook":{"session_id":"\(id)","cwd":\(cwd.map{"\"\($0)\""} ?? "null"),"hook_event_name":null}}
    """
    return try! JSONDecoder().decode(HookEvent.self, from: Data(json.utf8))
}
func pump(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
func check(_ name: String, _ got: [String], _ want: [String]) {
    if got == want { print("  PASS  \(name)  \(got)") }
    else { print("  FAIL  \(name)\n        got:  \(got)\n        want: \(want)"); failures += 1 }
}

func newRouter() -> (SessionRouter, () -> [String]) {
    let r = SessionRouter()
    r.debounce = 0.3
    r.stuckTimeout = 1.0            // 30 min in production
    var log: [String] = []
    r.send = { log.append("\($0["type"] as! String):\($0["sessionId"] as! String)") }
    return (r, { log })
}

print("SessionRouter")

// 1. one session, normal turn
do {
    let (r, log) = newRouter()
    r.handle(ev("prompt", "a")); pump(0.4); r.handle(ev("stop", "a")); pump(0.1)
    check("single session opens then folds", log(), ["prompt:a", "stop:a"])
}

// 2. two parallel sessions: island stays until BOTH finish
do {
    let (r, log) = newRouter()
    r.handle(ev("prompt", "a")); pump(0.4)
    r.handle(ev("prompt", "b")); pump(0.4)
    r.handle(ev("stop", "a")); pump(0.1)
    let afterFirst = log()
    r.handle(ev("stop", "b")); pump(0.1)
    check("second prompt does not reopen", afterFirst, ["prompt:a"])
    check("folds only on the last stop", log(), ["prompt:a", "stop:b"])
}

// 3. debounce: a stop landing on its own prompt is held, not dropped
do {
    let (r, log) = newRouter()
    r.handle(ev("prompt", "a"))
    r.handle(ev("stop", "a"))        // immediate
    check("stop not acted on inside the window", log(), ["prompt:a"])
    pump(0.5)
    check("held stop still arrives", log(), ["prompt:a", "stop:a"])
    check("session left idle, not stuck", [String(r.workingCount)], ["0"])
}

// 4. Esc / Ctrl+C: no stop ever arrives
do {
    let (r, log) = newRouter()
    r.handle(ev("prompt", "a")); pump(0.4)
    check("still working before the timeout", log(), ["prompt:a"])
    pump(0.9)
    check("stuck timeout folds the island", log(), ["prompt:a", "stop:a"])
    check("stuck session is forgotten", [String(r.sessions.count)], ["0"])
}

// 5. SessionEnd while working behaves like a stop
do {
    let (r, log) = newRouter()
    r.handle(ev("prompt", "a")); pump(0.4); r.handle(ev("end", "a")); pump(0.1)
    check("end while working folds", log(), ["prompt:a", "stop:a"])
    check("end removes the session", [String(r.sessions.count)], ["0"])
}

// 6. noise that must not move the island
do {
    let (r, log) = newRouter()
    r.handle(ev("stop", "ghost"))           // never prompted
    r.handle(ev("end", "ghost"))
    r.handle(ev("bogus", "a"))
    pump(0.1)
    check("unknown sessions and events ignored", log(), [])
}

// 7. a second prompt in the SAME session while it is still working
do {
    let (r, log) = newRouter()
    r.handle(ev("prompt", "a")); pump(0.4)
    r.handle(ev("prompt", "a")); pump(0.4)
    check("no duplicate open", log(), ["prompt:a"])
    r.handle(ev("stop", "a")); pump(0.1)
    check("one stop still folds it", log(), ["prompt:a", "stop:a"])
}

// 8. a prompt arriving during the debounce window cancels the held stop
do {
    let (r, log) = newRouter()
    r.handle(ev("prompt", "a"))
    r.handle(ev("stop", "a"))
    r.handle(ev("prompt", "a"))      // user fires again immediately
    pump(0.6)
    check("held stop cancelled by a new prompt", log(), ["prompt:a"])
    check("session still working", [String(r.workingCount)], ["1"])
}

// 9. terminal details are kept for FocusReturner
do {
    let (r, _) = newRouter()
    r.handle(ev("prompt", "a", tty: "ttys004", term: "iTerm.app", cwd: "/tmp/x")); pump(0.4)
    let s = r.session(for: "a")
    check("terminal info retained",
          [s?.tty ?? "-", s?.term ?? "-", s?.cwd ?? "-"],
          ["ttys004", "iTerm.app", "/tmp/x"])
    r.handle(ev("prompt", "a", tty: nil, term: nil, cwd: nil)); pump(0.1)
    check("a later prompt without tty keeps the old one", [r.session(for: "a")?.tty ?? "-"], ["ttys004"])
}

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
