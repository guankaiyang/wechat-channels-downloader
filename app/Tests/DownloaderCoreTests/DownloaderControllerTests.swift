import Foundation
import Testing
@testable import DownloaderCore

private let pgrepCall = ["/usr/bin/pgrep", "-x", "wx_video_download"]
private let listServices = [networksetup, "-listallnetworkservices"]

private let goodScript = """
#!/bin/bash
echo $$ > "$PWD/pid"
trap 'echo int > "$PWD/got-int"; exit 0' INT
echo started
while :; do sleep 0.1; done
"""

private let stubbornScript = """
#!/bin/bash
echo $$ > "$PWD/pid"
trap '' INT
echo started
while :; do sleep 0.1; done
"""

private let argsScript = """
#!/bin/bash
echo "args: $*"
trap 'exit 0' INT
while :; do sleep 0.1; done
"""

private let failingScript = """
#!/bin/bash
echo "API service started"
echo "failed to start proxy service: address already in use"
exit 1
"""

private func makeSupportDir(script: String) throws -> DownloaderPaths {
    let dir = try makeTempDir()
    let binary = dir.appendingPathComponent("wx_video_download")
    try script.write(to: binary, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("certs"), withIntermediateDirectories: true)
    try "cert".write(to: dir.appendingPathComponent("certs/ca.pem"), atomically: true, encoding: .utf8)
    return DownloaderPaths.resolve(env: [DownloaderPaths.supportDirEnvKey: dir.path], home: dir)
}

/// Wi-Fi proxy currently points at the downloader, so a cleanup would issue `-set…` calls.
private func runnerWithOurProxy(_ extra: [[String]: CommandResult] = [:]) -> FakeRunner {
    var table: [[String]: CommandResult] = [
        listServices: ok("An asterisk (*) denotes that a network service is disabled.\nWi-Fi\n"),
        [networksetup, "-getwebproxy", "Wi-Fi"]: ok(ourProxy),
        [networksetup, "-getsecurewebproxy", "Wi-Fi"]: ok(ourProxy),
    ]
    table.merge(extra) { _, new in new }
    return FakeRunner(table)
}

@MainActor
private func makeController(_ paths: DownloaderPaths, _ runner: FakeRunner,
                            listening: Bool = false, stopTimeout: Double = 8,
                            ruleList: FakeRuleList = FakeRuleList()) -> DownloaderController {
    DownloaderController(paths: paths, runner: runner, home: paths.supportDir,
                         stopTimeout: stopTimeout, proxyListening: { listening }, ruleList: ruleList)
}

/// Polls until `condition` holds or `seconds` pass.
@MainActor
private func waitUntil(_ seconds: Double = 5, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return condition()
}

private func logContains(_ paths: DownloaderPaths, _ text: String) -> Bool {
    ((try? String(contentsOf: paths.logFile, encoding: .utf8)) ?? "").contains(text)
}

private func fixturePID(_ paths: DownloaderPaths) -> Int32? {
    let text = try? String(contentsOf: paths.supportDir.appendingPathComponent("pid"), encoding: .utf8)
    return text.flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
}

private func isAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 }

@MainActor
@Suite(.serialized) struct DownloaderControllerTests {
    @Test func startRunsBinaryInSupportDir() async throws {
        let paths = try makeSupportDir(script: goodScript)
        let controller = makeController(paths, FakeRunner())
        await controller.start()
        guard case .running(_, external: false) = controller.state else {
            Issue.record("expected running, got \(controller.state)"); return
        }
        #expect(await waitUntil { logContains(paths, "started") })
        await controller.stop()
    }

    @Test func startUsesTheAppConfigAndTurnsOnTheRuleList() async throws {
        let paths = try makeSupportDir(script: argsScript)
        try "proxy:\n  enabled: true\n  system: true\n  port: 2023\n".write(to: paths.config, atomically: true, encoding: .utf8)
        let runner = FakeRunner([listServices: ok("An asterisk (*) denotes that a network service is disabled.\nWi-Fi\n")])
        runner.set([networksetup, "-getautoproxyurl", "Wi-Fi"], ok("URL: (null)\nEnabled: No\n"))
        let server = FakeRuleList()
        let listening = LockedFlag(false)
        let controller = DownloaderController(paths: paths, runner: runner, home: paths.supportDir,
                                              proxyListening: { listening.value }, ruleList: server)
        await controller.start()
        #expect(await waitUntil { logContains(paths, "args:") })
        try await Task.sleep(for: .milliseconds(500))
        #expect(!runner.setCalls.contains { $0.contains("-setautoproxystate") }) // not before it listens
        listening.value = true
        #expect(logContains(paths, "args: -c \(paths.appConfig.path)"))
        let written = try String(contentsOf: paths.appConfig, encoding: .utf8)
        #expect(written.contains("  system: false") && !written.contains("system: true"))
        #expect(try String(contentsOf: paths.config, encoding: .utf8).contains("system: true")) // user's file untouched
        #expect(server.isRunning)
        #expect(await waitUntil { runner.setCalls.contains([networksetup, "-setautoproxystate", "Wi-Fi", "on"]) })
        #expect(runner.setCalls.contains([networksetup, "-setautoproxyurl", "Wi-Fi", ruleListURL]))
        await controller.stop()
    }

    @Test func stopTurnsTheRuleListOff() async throws {
        let paths = try makeSupportDir(script: goodScript)
        let runner = FakeRunner([listServices: ok("An asterisk (*) denotes that a network service is disabled.\nWi-Fi\n")])
        let controller = makeController(paths, runner)
        await controller.start()
        #expect(await waitUntil { logContains(paths, "started") })
        runner.set([networksetup, "-getautoproxyurl", "Wi-Fi"], ok("URL: \(ruleListURL)\nEnabled: Yes\n"))
        await controller.stop()
        #expect(runner.setCalls.contains([networksetup, "-setautoproxystate", "Wi-Fi", "off"]))
    }

    @Test func startFailsClearlyWhenTheRuleListCannotBeServed() async throws {
        let paths = try makeSupportDir(script: goodScript)
        let controller = makeController(paths, FakeRunner(),
                                         ruleList: FakeRuleList(failure: RuleListServerError.couldNotListen("in use")))
        await controller.start()
        guard case .failed(let message) = controller.state else {
            Issue.record("expected failed, got \(controller.state)"); return
        }
        #expect(message.contains("2024"))
        #expect(!logContains(paths, "started"))
    }

    @Test func refreshKeepsTheRuleListServed() async throws {
        let paths = try makeSupportDir(script: goodScript)
        let server = FakeRuleList()
        let controller = makeController(paths, FakeRunner(), ruleList: server)
        await controller.refresh()
        #expect(server.isRunning)
    }

    @Test func stopSendsInterruptAndCleansProxy() async throws {
        let paths = try makeSupportDir(script: goodScript)
        let runner = runnerWithOurProxy()
        let controller = makeController(paths, runner)
        await controller.start()
        #expect(await waitUntil { logContains(paths, "started") })
        await controller.stop()
        #expect(controller.state == .stopped)
        #expect(FileManager.default.fileExists(atPath: paths.supportDir.appendingPathComponent("got-int").path))
        #expect(runner.setCalls.contains([networksetup, "-setwebproxystate", "Wi-Fi", "off"]))
    }

    @Test func escalatesToKillWhenInterruptIgnored() async throws {
        let paths = try makeSupportDir(script: stubbornScript)
        let runner = FakeRunner()
        let controller = makeController(paths, runner, stopTimeout: 0.5)
        await controller.start()
        #expect(await waitUntil { logContains(paths, "started") })
        let pid = try #require(fixturePID(paths))
        await controller.stop()
        #expect(controller.state == .stopped)
        #expect(await waitUntil(2) { !isAlive(pid) })
        #expect(runner.calls.contains(listServices))
    }

    @Test func startupFailureShowsLogTail() async throws {
        let paths = try makeSupportDir(script: failingScript)
        let runner = runnerWithOurProxy()
        let controller = makeController(paths, runner)
        await controller.start()
        #expect(await waitUntil {
            if case .failed(let message) = controller.state { return message.contains("address already in use") }
            return false
        })
        #expect(await waitUntil { !runner.setCalls.isEmpty })
    }

    @Test func cleanupSkippedWhileProxyPortInUse() async throws {
        // Our start failed because a Terminal-started downloader owns 127.0.0.1:2023: leave its proxy alone.
        let paths = try makeSupportDir(script: failingScript)
        let runner = runnerWithOurProxy()
        let controller = makeController(paths, runner, listening: true)
        await controller.start()
        #expect(await waitUntil { if case .failed = controller.state { return true }; return false })
        await controller.refresh()
        try await Task.sleep(for: .milliseconds(300))
        #expect(runner.setCalls.isEmpty)
    }

    @Test func detectsExternalProcessAndLeavesItsProxy() async throws {
        let paths = try makeSupportDir(script: goodScript)
        let runner = runnerWithOurProxy([pgrepCall: ok("4242\n")])
        let controller = makeController(paths, runner)
        await controller.refresh()
        #expect(controller.state == .running(pid: 4242, external: true))
        #expect(runner.setCalls.isEmpty)
    }

    @Test func stopsExternalProcess() async throws {
        let paths = try makeSupportDir(script: goodScript)
        let external = Process()
        external.executableURL = paths.binary
        external.currentDirectoryURL = paths.supportDir
        external.standardOutput = FileHandle.nullDevice
        try external.run()
        #expect(await waitUntil { fixturePID(paths) != nil })
        let runner = runnerWithOurProxy([pgrepCall: ok("\(external.processIdentifier)\n")])
        let controller = makeController(paths, runner)
        await controller.refresh()
        #expect(controller.state == .running(pid: external.processIdentifier, external: true))
        await controller.stop()
        #expect(controller.state == .stopped)
        #expect(FileManager.default.fileExists(atPath: paths.supportDir.appendingPathComponent("got-int").path))
        #expect(await waitUntil(2) { !external.isRunning })
        #expect(runner.setCalls.contains([networksetup, "-setwebproxystate", "Wi-Fi", "off"]))
    }

    @Test func refreshCleansLeftoverProxyOnce() async throws {
        let paths = try makeSupportDir(script: goodScript)
        let runner = runnerWithOurProxy([pgrepCall: CommandResult(status: 1, output: "")])
        let controller = makeController(paths, runner)
        await controller.refresh()
        await controller.refresh()
        await controller.refresh()
        #expect(controller.state == .stopped)
        #expect(runner.calls.filter { $0 == listServices }.count == 1)
        #expect(runner.setCalls.contains([networksetup, "-setwebproxystate", "Wi-Fi", "off"]))
    }

    @Test func refreshReportsVPN() async throws {
        let paths = try makeSupportDir(script: goodScript)
        let runner = FakeRunner([
            pgrepCall: CommandResult(status: 1, output: ""),
            ["/usr/sbin/scutil"]: ok("  PrimaryInterface : utun8\n"),
        ])
        let controller = makeController(paths, runner)
        await controller.refresh()
        #expect(controller.vpnActive)
    }

    @Test func inFlightCleanupNeverOverwritesNewRun() async throws {
        // External downloader exits on its own; refresh starts a slow cleanup, the user clicks Stop,
        // then Start. Nothing that was already in flight may flip the new run back to "Stopped".
        let paths = try makeSupportDir(script: goodScript)
        let dead = Process()
        dead.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try dead.run()
        dead.waitUntilExit()
        let runner = FakeRunner([pgrepCall: ok("\(dead.processIdentifier)\n")])
        let controller = makeController(paths, runner)
        await controller.refresh()
        #expect(controller.state == .running(pid: dead.processIdentifier, external: true))

        runner.set(pgrepCall, CommandResult(status: 1, output: ""))
        runner.setDelay(listServices, seconds: 1.5)
        async let refreshing: Void = controller.refresh()
        try await Task.sleep(for: .milliseconds(600))
        async let stopping: Void = controller.stop()
        try await Task.sleep(for: .milliseconds(1200))
        await controller.start()
        await refreshing
        await stopping
        guard case .running(_, external: false) = controller.state else {
            Issue.record("new run was overwritten: \(controller.state)"); return
        }
        runner.setDelay(listServices, seconds: 0)
        await controller.stop()
    }

    @Test func shutdownWaitsForInFlightStop() async throws {
        let paths = try makeSupportDir(script: goodScript)
        let runner = FakeRunner()
        let controller = makeController(paths, runner)
        await controller.start()
        #expect(await waitUntil { logContains(paths, "started") })
        let pid = try #require(fixturePID(paths))
        runner.setDelay(listServices, seconds: 0.5)
        async let stopping: Void = controller.stop()
        try await Task.sleep(for: .milliseconds(50))
        #expect(controller.needsShutdown)
        await controller.shutdown()
        #expect(controller.state == .stopped)
        #expect(!isAlive(pid))
        #expect(runner.calls.contains(listServices))
        await stopping
    }

    @Test func shutdownDuringStartingStopsTheNewProcess() async throws {
        let paths = try makeSupportDir(script: goodScript)
        let verify = ["/usr/bin/security", "verify-cert", "-c", paths.caCert.path, "-p", "basic", "-l", "-L", "-q"]
        let runner = FakeRunner()
        runner.setDelay(verify, seconds: 0.5)
        let controller = makeController(paths, runner)
        async let starting: Void = controller.start()
        try await Task.sleep(for: .milliseconds(100))
        #expect(controller.state == .starting)
        await controller.shutdown()
        await starting
        #expect(controller.state == .stopped)
        if let pid = fixturePID(paths) { #expect(await waitUntil(2) { !isAlive(pid) }) }
    }

    @Test func untrustedCertIsTrustedBeforeLaunch() async throws {
        let paths = try makeSupportDir(script: goodScript)
        let verify = ["/usr/bin/security", "verify-cert", "-c", paths.caCert.path, "-p", "basic", "-l", "-L", "-q"]
        let runner = FakeRunner([verify: CommandResult(status: 1, output: "")])
        let controller = makeController(paths, runner)
        await controller.start()
        #expect(runner.calls.contains { $0.count > 1 && $0[1] == "add-trusted-cert" })
        guard case .running = controller.state else {
            Issue.record("expected running, got \(controller.state)"); return
        }
        await controller.stop()
    }

    @Test func refusedTrustDoesNotLaunch() async throws {
        let paths = try makeSupportDir(script: goodScript)
        let runner = FakeRunner(fallback: CommandResult(status: 1, output: ""))
        let controller = makeController(paths, runner)
        await controller.start()
        #expect(controller.state == .failed(DownloaderController.trustFailedMessage))
        #expect(!logContains(paths, "started"))
    }
}
