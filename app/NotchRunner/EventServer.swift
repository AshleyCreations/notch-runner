import Foundation
import Network

// MARK: - Wire format

struct HookPayload: Decodable {
    let session_id: String?
    let cwd: String?
    let hook_event_name: String?
}

struct HookEvent: Decodable {
    let event: String            // "prompt" | "stop" | "end"
    let tty: String?
    let term: String?            // TERM_PROGRAM: Apple_Terminal, iTerm.app, WarpTerminal, vscode, ghostty…
    let termSession: String?
    let itermSession: String?
    let hook: HookPayload?
}

// MARK: - Server

/// A deliberately small HTTP/1.1 listener bound to loopback, so the hook script
/// needs nothing but the `curl` that ships with macOS. Everything that makes it
/// safe is here: loopback only, a shared-secret header, one route, and a body cap.
final class EventServer {
    static let portRange: ClosedRange<UInt16> = 47811...47820
    static let maxBodyBytes = 64 * 1024

    /// Delivered on the main queue.
    var onEvent: ((HookEvent) -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "io.github.ashleycreations.notchrunner.events")
    private let token: String
    private(set) var port: UInt16?

    init() {
        token = Self.loadOrCreateToken()
    }

    // MARK: lifecycle

    /// Binds the first free port in `portRange` and records it for the hook script.
    func start() throws {
        var lastError: Error?
        for candidate in Self.portRange {
            do {
                let listener = try bind(candidate)
                self.listener = listener
                self.port = candidate
                Self.write(String(candidate), to: Self.supportDir.appendingPathComponent("port"), mode: 0o644)
                NSLog("notch-runner: listening on 127.0.0.1:\(candidate)")
                return
            } catch {
                lastError = error
            }
        }
        throw lastError ?? NWError.posix(.EADDRINUSE)
    }

    /// `NWListener.start` reports a bind failure asynchronously, so wait for the
    /// listener to actually reach `.ready` before claiming the port. Without this
    /// a busy port looks like success and we never fall back.
    private func bind(_ port: UInt16) throws -> NWListener {
        let listener = try makeListener(on: port)
        let settled = DispatchSemaphore(value: 0)
        var failure: Error?

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                settled.signal()
            case .failed(let error), .waiting(let error):
                failure = error
                settled.signal()
            case .cancelled:
                failure = failure ?? NWError.posix(.ECANCELED)
                settled.signal()
            default:
                break
            }
        }
        listener.start(queue: queue)

        if settled.wait(timeout: .now() + 2) == .timedOut {
            listener.cancel()
            throw NWError.posix(.ETIMEDOUT)
        }
        if let failure {
            listener.cancel()
            throw failure
        }
        // Past startup, a later failure should not take the app down silently.
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                NSLog("notch-runner: listener failed: \(error)")
            }
        }
        return listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = nil
    }

    private func makeListener(on port: UInt16) throws -> NWListener {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcp)
        // Loopback only. Nothing off this machine can reach the server.
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)

        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        return listener
    }

    // MARK: connections

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            if error != nil { connection.cancel(); return }

            var buffer = buffer
            if let chunk { buffer.append(chunk) }

            // Cheap guard against a client that just keeps sending.
            if buffer.count > Self.maxBodyBytes + 8 * 1024 {
                self.respond(connection, status: "413 Payload Too Large")
                return
            }

            switch Request.parse(buffer) {
            case .needMoreData:
                if isComplete { connection.cancel(); return }
                self.receive(connection, buffer: buffer)
            case .malformed:
                self.respond(connection, status: "400 Bad Request")
            case .tooLarge:
                self.respond(connection, status: "413 Payload Too Large")
            case .complete(let request):
                self.route(request, on: connection)
            }
        }
    }

    private func route(_ request: Request, on connection: NWConnection) {
        guard request.method == "POST", request.path == "/event" else {
            respond(connection, status: request.method == "POST" ? "404 Not Found" : "405 Method Not Allowed")
            return
        }
        guard let presented = request.headers["x-nr-token"],
              Self.constantTimeEquals(presented, token) else {
            respond(connection, status: "401 Unauthorized")
            return
        }

        // Acknowledge before doing any work: the hook must never block Claude.
        respond(connection, status: "204 No Content")

        guard let event = try? JSONDecoder().decode(HookEvent.self, from: request.body) else {
            NSLog("notch-runner: could not decode an event body of \(request.body.count) bytes")
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }

    private func respond(_ connection: NWConnection, status: String) {
        let head = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: token and support directory

    static var supportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notch-runner")
    }

    /// Reads the shared secret, generating one on first launch. Mode 600, because
    /// anything that can read it can open the island.
    static func loadOrCreateToken() -> String {
        let url = supportDir.appendingPathComponent("token")
        if let existing = try? String(contentsOf: url, encoding: .utf8) {
            let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        write(token, to: url, mode: 0o600)
        return token
    }

    private static func write(_ contents: String, to url: URL, mode: Int) {
        let fm = FileManager.default
        try? fm.createDirectory(at: supportDir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        guard let data = contents.data(using: .utf8) else { return }
        do {
            try data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        } catch {
            NSLog("notch-runner: cannot write \(url.path): \(error)")
        }
    }

    /// Compares in time independent of where the first difference is.
    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<x.count { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}

// MARK: - A very small HTTP request parser

extension EventServer {
    struct Request {
        let method: String
        let path: String
        let headers: [String: String]   // lowercased names
        let body: Data

        enum Result {
            case needMoreData
            case malformed
            case tooLarge
            case complete(Request)
        }

        /// Returns `.needMoreData` until the headers and the whole declared body
        /// have arrived, so a request split across TCP segments still works.
        static func parse(_ buffer: Data) -> Result {
            let separator = Data("\r\n\r\n".utf8)
            guard let range = buffer.range(of: separator) else { return .needMoreData }

            guard let head = String(data: buffer[..<range.lowerBound], encoding: .utf8) else { return .malformed }
            var lines = head.components(separatedBy: "\r\n")
            guard !lines.isEmpty else { return .malformed }

            let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
            guard requestLine.count >= 2 else { return .malformed }
            let method = String(requestLine[0]).uppercased()
            // Drop any query string; we only ever serve one exact route.
            let path = String(String(requestLine[1]).split(separator: "?", maxSplits: 1)[0])

            var headers: [String: String] = [:]
            for line in lines {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                headers[name] = value
            }

            let declared = Int(headers["content-length"] ?? "0") ?? 0
            guard declared >= 0 else { return .malformed }
            guard declared <= EventServer.maxBodyBytes else { return .tooLarge }

            let bodyStart = range.upperBound
            let available = buffer.count - bodyStart
            guard available >= declared else { return .needMoreData }

            let body = buffer[bodyStart..<(bodyStart + declared)]
            return .complete(Request(method: method, path: path, headers: headers, body: Data(body)))
        }
    }
}
