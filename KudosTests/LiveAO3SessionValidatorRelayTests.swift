import Darwin
import Foundation
import Testing
@testable import Kudos

/// M9: `LiveAO3SessionValidator` must attach `AO3RedirectCookieRelay` on the
/// wire, not just share the pure `redirectCookieAction` helper. A local
/// origin that 302s off-host must arrive at the attacker with no Cookie.
struct LiveAO3SessionValidatorRelayTests {
    @Test func validatorRedirectDoesNotForwardTheSessionCookie() async throws {
        let attacker = try LoopbackHTTPServer()
        defer { attacker.stop() }
        let attackerHits = LoopbackCounter()
        attacker.onRequest = { exchange in
            attackerHits.bump(cookie: exchange.header("Cookie"))
            exchange.status = 200
            exchange.body = Data("ok".utf8)
        }
        try attacker.start()

        let origin = try LoopbackHTTPServer()
        defer { origin.stop() }
        let originHits = LoopbackCounter()
        origin.onRequest = { exchange in
            originHits.bump()
            exchange.status = 302
            exchange.headers["Location"] = "http://127.0.0.1:\(attacker.port)/stolen"
        }
        try origin.start()

        let originURL = try #require(URL(string: "http://127.0.0.1:\(origin.port)/"))
        let validator = LiveAO3SessionValidator(validationURL: originURL)
        var request = URLRequest(url: originURL)
        request.setValue("_otwarchive_session=SECRET-SESSION", forHTTPHeaderField: "Cookie")
        // Do not swallow: a transport failure must fail the test, not pass it.
        _ = try await validator.performRequest(request)

        // Positive controls. Without these the assertions below are vacuous:
        // "the attacker saw no cookie" is also true when the attacker saw nothing.
        #expect(originHits.value == 1, "the loopback origin was never reached")
        #expect(
            attackerHits.value == 1,
            "the redirect never reached the attacker — test proved nothing"
        )
        let attackerCookie = attackerHits.cookie
        #expect(attackerCookie == nil || attackerCookie?.isEmpty == true)
        #expect(attackerCookie?.contains("SECRET-SESSION") != true)
    }
}

/// Hit / header counter shared between the accept thread and the test thread.
final class LoopbackCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    private var _cookie: String?

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    var cookie: String? {
        lock.lock()
        defer { lock.unlock() }
        return _cookie
    }

    func bump(cookie: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        _value += 1
        _cookie = cookie
    }
}

/// Minimal HTTP/1.0 listener on 127.0.0.1. One request per connection.
final class LoopbackHTTPServer: @unchecked Sendable {
    struct Exchange {
        var method = ""
        var path = ""
        var headers: [String: String] = [:]
        var status = 200
        var body = Data()

        func header(_ name: String) -> String? {
            let target = name.lowercased()
            return headers.first { $0.key.lowercased() == target }?.value
        }
    }

    var onRequest: ((inout Exchange) -> Void)?
    private(set) var port: UInt16 = 0
    private var listenFD: Int32 = -1
    private var acceptThread: Thread?

    func start() throws {
        listenFD = socket(AF_INET, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw URLError(.cannotCreateFile) }
        var yes: Int32 = 1
        setsockopt(listenFD, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, listen(listenFD, 8) == 0 else {
            stop()
            throw URLError(.cannotConnectToHost)
        }
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(listenFD, $0, &length)
            }
        }
        guard nameResult == 0 else {
            stop()
            throw URLError(.cannotConnectToHost)
        }
        port = UInt16(bigEndian: bound.sin_port)
        let thread = Thread { [weak self] in
            self?.acceptLoop()
        }
        acceptThread = thread
        thread.start()
    }

    func stop() {
        if listenFD >= 0 {
            shutdown(listenFD, SHUT_RDWR)
            close(listenFD)
            listenFD = -1
        }
    }

    private func acceptLoop() {
        while listenFD >= 0 {
            let client = accept(listenFD, nil, nil)
            if client < 0 { continue }
            handle(client: client)
        }
    }

    private func handle(client: Int32) {
        defer { close(client) }
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while received.range(of: Data("\r\n\r\n".utf8)) == nil {
            let count = read(client, &buffer, buffer.count)
            if count <= 0 { return }
            received.append(contentsOf: buffer.prefix(count))
            if received.count > 65_536 { return }
        }
        guard let text = String(data: received, encoding: .utf8) else { return }
        var exchange = Exchange()
        let lines = text.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let requestLine = lines.first {
            let parts = requestLine.split(separator: " ")
            if parts.count >= 2 {
                exchange.method = String(parts[0])
                exchange.path = String(parts[1])
            }
        }
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            exchange.headers[name] = value
        }
        onRequest?(&exchange)
        let reason = exchange.status == 302 ? "Found" : "OK"
        var headerLines = [
            "HTTP/1.1 \(exchange.status) \(reason)",
            "Content-Length: \(exchange.body.count)",
            "Connection: close"
        ]
        for (name, value) in exchange.headers {
            headerLines.append("\(name): \(value)")
        }
        let head = Data((headerLines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        _ = head.withUnsafeBytes { write(client, $0.baseAddress, head.count) }
        if !exchange.body.isEmpty {
            _ = exchange.body.withUnsafeBytes { write(client, $0.baseAddress, exchange.body.count) }
        }
    }
}
