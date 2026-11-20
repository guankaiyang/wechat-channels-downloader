import Foundation
import Network

public enum RuleListServerError: Error, LocalizedError {
    case couldNotListen(String)

    public var errorDescription: String? {
        switch self {
        case .couldNotListen(let detail): return "Port \(ruleListPort) is busy or blocked (\(detail))"
        }
    }
}

/// Something that serves the rule list (the real server, or a fake in tests).
public protocol RuleListServing: AnyObject, Sendable {
    var isRunning: Bool { get }
    /// Starts serving; does nothing if already running.
    func start() async throws
}

/// Serves the proxy rule list on 127.0.0.1 only. Every request gets the current rule list, which
/// depends on whether the downloader is listening right now. If this app isn't running, nothing serves
/// the list and macOS connects everything directly.
public final class RuleListServer: RuleListServing, @unchecked Sendable {
    private let port: UInt16
    private let downloaderUp: @Sendable () -> Bool
    private let queue = DispatchQueue(label: "rule-list-server")
    private let lock = NSLock()
    private var listener: NWListener?
    private var starting: Task<Void, Error>?

    public init(port: UInt16 = ruleListPort, downloaderUp: @escaping @Sendable () -> Bool) {
        self.port = port
        self.downloaderUp = downloaderUp
    }

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return listener != nil
    }

    /// Starts listening (does nothing if already running). Callers that arrive while a start is in
    /// progress wait for that same start. Throws if the port can't be used.
    public func start() async throws {
        let task: Task<Void, Error> = lock.withLock {
            if listener != nil { return Task {} }
            if let starting { return starting }
            let fresh = Task { try await self.listen() }
            starting = fresh
            return fresh
        }
        defer { lock.withLock { if starting == task { starting = nil } } }
        try await task.value
    }

    private func listen() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw RuleListServerError.couldNotListen("\(error)")
        }
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        let once = ResumeOnce()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.lock.withLock { self?.listener = listener }
                    once.run { continuation.resume() }
                case .failed(let error), .waiting(let error):
                    listener.cancel()
                    self?.forget(listener)
                    once.run { continuation.resume(throwing: RuleListServerError.couldNotListen("\(error)")) }
                case .cancelled:
                    self?.forget(listener)
                    once.run { continuation.resume(throwing: RuleListServerError.couldNotListen("cancelled")) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    /// A listener that failed or was cancelled after starting no longer counts as running,
    /// so the next refresh starts a new one.
    private func forget(_ dead: NWListener) {
        lock.withLock { if listener === dead { listener = nil } }
    }

    public func stop() {
        lock.lock()
        let current = listener
        listener = nil
        lock.unlock()
        current?.cancel()
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(connection, received: Data())
    }

    /// Reads until the end of the request headers (or 16 KB), then answers and closes.
    private func readRequest(_ connection: NWConnection, received: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var buffer = received
            if let data { buffer.append(data) }
            let headersDone = buffer.range(of: Data("\r\n\r\n".utf8)) != nil
            if headersDone || complete || error != nil || buffer.count >= 16_384 {
                self.respond(connection)
            } else {
                self.readRequest(connection, received: buffer)
            }
        }
    }

    private func respond(_ connection: NWConnection) {
        let body = Data(ruleListScript(downloaderUp: downloaderUp()).utf8)
        let head = "HTTP/1.1 200 OK\r\nContent-Type: application/x-ns-proxy-autoconfig\r\n"
            + "Content-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}

/// Runs its closure at most once (a continuation must be resumed exactly once).
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ body: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { body() }
    }
}
