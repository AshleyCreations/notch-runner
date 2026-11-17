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

    // MARK: entry point

    func handle(_ event: HookEvent) {
        let id = event.hook?.session_id ?? "unknown"
        switch event.event {
        case "prompt": prompt(id, event)
        case "stop":   stop(id)
        case "end":    end(id)
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
