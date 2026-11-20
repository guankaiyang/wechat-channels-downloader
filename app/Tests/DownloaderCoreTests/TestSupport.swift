import Foundation
@testable import DownloaderCore

/// Records every command and answers from a table keyed by `[path] + args`.
/// Answers and delays can be changed while a test runs.
final class FakeRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    private var inputs: [String?] = []
    private var responses: [[String]: CommandResult]
    private var delays: [[String]: Double] = [:]
    private var pathResponses: [String: CommandResult] = [:]
    private let fallback: CommandResult

    init(_ responses: [[String]: CommandResult] = [:],
         fallback: CommandResult = CommandResult(status: 0, output: "")) {
        self.responses = responses
        self.fallback = fallback
    }

    func set(_ key: [String], _ result: CommandResult) {
        lock.lock(); responses[key] = result; lock.unlock()
    }

    /// Answer for any call to `path` that has no exact entry.
    func setForPath(_ path: String, _ result: CommandResult) {
        lock.lock(); pathResponses[path] = result; lock.unlock()
    }

    func setDelay(_ key: [String], seconds: Double) {
        lock.lock(); delays[key] = seconds; lock.unlock()
    }

    func run(_ path: String, _ args: [String], input: String?) -> CommandResult {
        let key = [path] + args
        lock.lock()
        recorded.append(key)
        inputs.append(input)
        let answer = responses[key] ?? pathResponses[path] ?? fallback
        let delay = delays[key] ?? 0
        lock.unlock()
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        return answer
    }

    var calls: [[String]] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    var setCalls: [[String]] { calls.filter { $0.count > 1 && $0[1].hasPrefix("-set") } }

    var lastInput: String? {
        lock.lock(); defer { lock.unlock() }
        return inputs.last ?? nil
    }
}

let networksetup = "/usr/sbin/networksetup"

func ok(_ output: String) -> CommandResult { CommandResult(status: 0, output: output) }

let ourProxy = "Enabled: Yes\nServer: 127.0.0.1\nPort: 2023\nAuthenticated Proxy Enabled: 0\n"
let noProxy = "Enabled: No\nServer: \nPort: 0\nAuthenticated Proxy Enabled: 0\n"

func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cdtests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Stands in for the real rule-list server so tests never bind port 2024.
final class FakeRuleList: RuleListServing, @unchecked Sendable {
    private let lock = NSLock()
    private var running = false
    private var starts = 0
    private let failure: Error?

    init(failure: Error? = nil) { self.failure = failure }

    var isRunning: Bool { lock.withLock { running } }
    var startCount: Int { lock.withLock { starts } }

    func start() async throws {
        lock.withLock { starts += 1 }
        if let failure { throw failure }
        lock.withLock { running = true }
    }
}
