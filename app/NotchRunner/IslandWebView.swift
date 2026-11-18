import AppKit
import WebKit

// The transparent WKWebView that hosts game/index.html, plus the two-way
// bridge described in NOTCH_RUNNER_SPEC.md §7.
final class IslandWebView: WKWebView, WKScriptMessageHandler, WKNavigationDelegate {
    var onIslandState: ((String, CGSize, Bool) -> Void)?
    var onClosed: (() -> Void)?
    var onWantsKeyboard: (() -> Void)?
    var onReturnFocus: ((String?) -> Void)?

    private var ready = false
    private var queued: [[String: Any]] = []

    init() {
        let config = WKWebViewConfiguration()
        super.init(frame: .zero, configuration: config)

        configuration.userContentController.add(self, name: "runner")
        navigationDelegate = self

        // Transparent so the island's own black is the only thing drawn.
        setValue(false, forKey: "drawsBackground")
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func load() {
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "game") else {
            NSLog("notch-runner: game/index.html missing from the bundle")
            return
        }
        loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    // MARK: native -> JS

    func send(_ event: [String: Any]) {
        guard ready else { queued.append(event); return }
        guard let data = try? JSONSerialization.data(withJSONObject: event),
              let json = String(data: data, encoding: .utf8) else { return }
        evaluateJavaScript("window.NotchRunner.event(\(json))")
    }

    // MARK: JS -> native

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }

        switch type {
        case "ready":
            ready = true
            if let state = StateStore.shared.load() {
                send(["type": "restore", "state": state])
            }
            send(["type": "config", "config": Settings.shared.webConfig])
            queued.forEach(send)
            queued.removeAll()

        case "island":
            let state = body["state"] as? String ?? "idle"
            let size = CGSize(width: body["width"] as? Double ?? 186,
                              height: body["height"] as? Double ?? 32)
            onIslandState?(state, size, body["interactive"] as? Bool ?? false)

        case "wantsKeyboard":
            onWantsKeyboard?()

        case "save":
            if let state = body["state"] as? [String: Any] { StateStore.shared.save(state) }

        case "returnFocus":
            onReturnFocus?(body["sessionId"] as? String)

        default:
            break
        }
    }

    // The game is offline-only: refuse anything that is not the local file.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
    }
}
