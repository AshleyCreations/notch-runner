import Foundation

// Persists the game state the web view hands back: { saved, level, cleared,
// speed, ctx, best, everPlayed }. Stored verbatim as JSON in UserDefaults so
// the shape can change on the JS side without a native migration.
final class StateStore {
    static let shared = StateStore()
    private let key = "gameState"
    private let d = UserDefaults.standard

    func save(_ state: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: state) else { return }
        d.set(data, forKey: key)
    }

    func load() -> [String: Any]? {
        guard let data = d.data(forKey: key),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    func clear() { d.removeObject(forKey: key) }

    /// For the read-only "Tokens saved / Best" line in the menu.
    var savedTokens: Int { (load()?["saved"] as? Int) ?? 0 }
    var bestTokens: Int { (load()?["best"] as? Int) ?? 0 }
}
