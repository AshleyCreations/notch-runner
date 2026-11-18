import Foundation

/// One Claude Code session. `tty` and the terminal identifiers are kept so
/// FocusReturner can land the user back on the exact window or tab the prompt
/// came from.
struct Session {
    let id: String
    var startedAt: Date
    var tty: String?
    var term: String?
    var termSession: String?
    var itermSession: String?
    var cwd: String?
    /// Whatever was frontmost when the prompt arrived — the last-resort target
    /// for terminals we cannot drive down to a tab.
    var frontmostBundleId: String?
    var isWorking: Bool
}

/// There is one island but possibly several Claude sessions, so the island
/// opens on the first prompt and only folds once the LAST session goes idle.
///
/// Call everything on the main queue; `EventServer` already delivers there.
final class SessionRouter {
    /// A stop this soon after its own prompt is held back rather than acted on.
    var debounce: TimeInterval = 0.3
    /// Esc and Ctrl+C interrupts mean Stop may never fire, so give up eventually.
    var stuckTimeout: TimeInterval = 30 * 60

    /// Emits the bridge events the web view understands.
    var send: (([String: Any]) -> Void)?
    /// Supplied by AppDelegate; kept as a closure so the router stays free of
    /// AppKit and can be tested on its own.
    var frontmostBundleId: (() -> String?)?

    private(set) var sessions: [String: Session] = [:]
    private var stuckTimers: [String: DispatchWorkItem] = [:]
    private var pendingStops: [String: DispatchWorkItem] = [:]

    var workingCount: Int { sessions.values.filter(\.isWorking).count }

    func session(for id: String) -> Session? { sessions[id] }

    /// Records each surface we have seen, so the blocklist can be set from what
    /// Claude Code actually reports rather than from guesswork. An ad-hoc signed
    /// app's NSLog output is redacted out of `log show`, so this goes to a file
    /// you can read. Removed with the rest of ~/.notch-runner on uninstall.
    private static func noteEntrypoint(_ entry: String) {
        let url = EventServer.supportDir.appendingPathComponent("entrypoints")
        let line = "\(ISO8601DateFormatter().string(from: Date()))  \(entry)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    // MARK: entry point

    /// Surfaces the island should stay out of. Claude Code itself is welcome
    /// anywhere it runs -- a terminal or the desktop app -- but Chat and Cowork
    /// are not sessions you sit and wait on, so a strip unfolding over them is
    /// just noise.
    ///
    /// Matched on CLAUDE_CODE_ENTRYPOINT. Anything unrecognised is allowed
    /// through rather than blocked: a new Claude Code surface should get the
    /// island, and the cost of being wrong is a strip you can close, not a
    /// feature that silently stops working.
    static let blockedEntrypoints: Set<String> = [
        "cowork", "claude-cowork",
        "chat", "claude-chat",
    ]

    /// Entrypoints we have already logged, so the log says each one once.
    private static var seenEntrypoints: Set<String> = []

    static func shouldRoute(_ event: HookEvent) -> Bool {
        // An explicit /playbot always plays, wherever it was typed. The player
        // asked for it; no threshold or surface rule gets to veto that.
        if event.event == "play" { return true }

        let entry = (event.entrypoint ?? "").lowercased()
        if !entry.isEmpty, seenEntrypoints.insert(entry).inserted {
            noteEntrypoint(entry)
        }
        return !blockedEntrypoints.contains(entry)
    }

    func handle(_ event: HookEvent) {
        let id = event.hook?.session_id ?? "unknown"

        // Drop everything for a session we would never open the island for,
        // rather than only the prompt: otherwise its stop would be routed and
        // could fold an island another session had opened.
        guard Self.shouldRoute(event) else { return }

        switch event.event {
        case "prompt": prompt(id, event)
        case "stop":   stop(id)
        case "end":    end(id)
        // "/playbot": open the strip with nothing to wait for. It deliberately
        // creates no session, so no stop is expected and none can arrive --
        // the player closes it themselves.
        case "play":   send?(["type": "playNow"])
        default:       NSLog("notch-runner: ignoring unknown event \(event.event)")
        }
    }

    // MARK: events

    private func prompt(_ id: String, _ event: HookEvent) {
        cancelPendingStop(id)

        let wasAnyoneWorking = workingCount > 0

        var session = sessions[id] ?? Session(id: id, startedAt: Date(), tty: nil, term: nil,
                                              termSession: nil, itermSession: nil, cwd: nil,
                                              frontmostBundleId: nil, isWorking: false)
        session.startedAt = Date()
        session.isWorking = true
        // The terminal can legitimately change between prompts, so refresh it.
        session.tty = event.tty?.isEmpty == false ? event.tty : session.tty
        session.term = event.term?.isEmpty == false ? event.term : session.term
        session.termSession = event.termSession?.isEmpty == false ? event.termSession : session.termSession
        session.itermSession = event.itermSession?.isEmpty == false ? event.itermSession : session.itermSession
        session.cwd = event.hook?.cwd ?? session.cwd
        // Only on the first prompt of a turn: once our own panel takes the
        // keyboard, the frontmost app is us, not the terminal.
        if !session.isWorking || session.frontmostBundleId == nil {
            session.frontmostBundleId = frontmostBundleId?() ?? session.frontmostBundleId
        }
        sessions[id] = session

        armStuckTimer(id)

        // Only the first working session opens the island. A second prompt while
        // one is already running must not restart the countdown underneath it.
        if !wasAnyoneWorking {
            send?(["type": "prompt", "sessionId": id])
        }
    }

    private func stop(_ id: String) {
        guard let session = sessions[id], session.isWorking else { return }

        // A stop landing on top of its own prompt is held to the end of the
        // debounce window rather than dropped, so the session can never be left
        // stuck working. Dropping it outright would wedge the island open.
        let age = Date().timeIntervalSince(session.startedAt)
        if age < debounce {
            schedulePendingStop(id, after: debounce - age)
            return
        }
        finish(id)
    }

    private func end(_ id: String) {
        guard let session = sessions[id] else { return }
        if session.isWorking {
            finish(id, removing: true)
        } else {
            clearTimers(id)
            sessions.removeValue(forKey: id)
        }
    }

    /// Marks the session idle and, if it was the last one working, folds the island.
    private func finish(_ id: String, removing: Bool = false) {
        clearTimers(id)
        if removing {
            sessions.removeValue(forKey: id)
        } else {
            sessions[id]?.isWorking = false
        }

        if workingCount == 0 {
            send?(["type": "stop", "sessionId": id])
        }
    }

    // MARK: timers

    private func schedulePendingStop(_ id: String, after delay: TimeInterval) {
        pendingStops[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingStops.removeValue(forKey: id)
            self?.finish(id)
        }
        pendingStops[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPendingStop(_ id: String) {
        pendingStops.removeValue(forKey: id)?.cancel()
    }

    private func armStuckTimer(_ id: String) {
        stuckTimers[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.sessions[id]?.isWorking == true else { return }
            NSLog("notch-runner: session \(id) never stopped; folding away")
            self.finish(id, removing: true)
        }
        stuckTimers[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + stuckTimeout, execute: work)
    }

    private func clearTimers(_ id: String) {
        stuckTimers.removeValue(forKey: id)?.cancel()
        pendingStops.removeValue(forKey: id)?.cancel()
    }
}
