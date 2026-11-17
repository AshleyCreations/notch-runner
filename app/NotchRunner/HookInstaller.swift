import Foundation

// Merges our three entries into ~/.claude/settings.json and takes them back
// out again. The rules that matter (spec §3.2): back up first, never touch
// anyone else's hooks, be idempotent, and refuse to write over invalid JSON.
enum HookInstaller {
    static let marker = "notch-runner-hook.sh"
    static let events = ["UserPromptSubmit": "prompt", "Stop": "stop", "SessionEnd": "end"]

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    // MARK: install / uninstall

    @discardableResult
    static func install() -> Bool {
        guard var root = read() else { return false }
        guard backup() else { return false }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for (event, arg) in events {
            var matchers = hooks[event] as? [[String: Any]] ?? []
            matchers.removeAll(where: { containsOurs($0) })     // idempotent
            matchers.append([
                "hooks": [[
                    "type": "command",
                    "command": "~/.notch-runner/\(marker) \(arg)",
                    "timeout": 3,
                ]]
            ])
            hooks[event] = matchers
        }
        root["hooks"] = hooks

        guard write(root) else { return false }
        print("Notch Runner hooks installed. Restart Claude Code; approve them in /hooks if asked.")
        return true
    }

    @discardableResult
    static func uninstall() -> Bool {
        guard var root = read() else { return false }
        guard var hooks = root["hooks"] as? [String: Any] else { return true }
        guard backup() else { return false }

        for event in events.keys {
            guard var matchers = hooks[event] as? [[String: Any]] else { continue }
            matchers.removeAll(where: { containsOurs($0) })
            if matchers.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = matchers }
        }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }

        guard write(root) else { return false }
        print("Notch Runner hooks removed.")
        return true
    }

    static func isInstalled() -> Bool {
        guard let root = read(), let hooks = root["hooks"] as? [String: Any] else { return false }
        return events.keys.contains { event in
            (hooks[event] as? [[String: Any]])?.contains(where: containsOurs) ?? false
        }
    }

    // MARK: helpers

    /// A matcher is ours when any of its commands mentions our hook script.
    static func containsOurs(_ matcher: [String: Any]) -> Bool {
        guard let inner = matcher["hooks"] as? [[String: Any]] else { return false }
        return inner.contains { ($0["command"] as? String)?.contains(marker) == true }
    }

    /// Returns `[:]` when the file does not exist, and nil when it is unreadable
    /// or not valid JSON — in which case we abort rather than clobber it.
    static func read() -> [String: Any]? {
        let url = settingsURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let data = try? Data(contentsOf: url) else {
            FileHandle.standardError.write(Data("error: cannot read \(url.path)\n".utf8))
            return nil
        }
        if data.isEmpty { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            FileHandle.standardError.write(Data("error: \(url.path) is not valid JSON; not touching it\n".utf8))
            return nil
        }
        return obj
    }

    static func backup() -> Bool {
        let url = settingsURL
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dest = url.deletingLastPathComponent()
            .appendingPathComponent("settings.json.notch-runner-backup-\(stamp)")
        do { try FileManager.default.copyItem(at: url, to: dest); return true }
        catch {
            FileHandle.standardError.write(Data("error: backup failed: \(error)\n".utf8))
            return false
        }
    }

    static func write(_ root: [String: Any]) -> Bool {
        let url = settingsURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(
                withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            FileHandle.standardError.write(Data("error: cannot write \(url.path): \(error)\n".utf8))
            return false
        }
    }
}
