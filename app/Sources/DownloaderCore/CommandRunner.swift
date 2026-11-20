import Foundation

public struct CommandResult: Equatable, Sendable {
    public let status: Int32
    public let output: String

    public init(status: Int32, output: String) {
        self.status = status
        self.output = output
    }
}

/// Runs a system command and returns its exit status and combined output.
public protocol CommandRunner: Sendable {
    func run(_ path: String, _ args: [String], input: String?) -> CommandResult
}

extension CommandRunner {
    public func run(_ path: String, _ args: [String]) -> CommandResult {
        run(path, args, input: nil)
    }
}

public struct ProcessRunner: CommandRunner {
    public init() {}

    public func run(_ path: String, _ args: [String], input: String?) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let stdin = Pipe()
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin
        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, output: "\(error)")
        }
        if let input {
            stdin.fileHandleForWriting.write(Data(input.utf8))
            try? stdin.fileHandleForWriting.close()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus,
                             output: String(decoding: data, as: UTF8.self))
    }
}
