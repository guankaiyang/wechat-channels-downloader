import Foundation
import Testing
@testable import DownloaderCore

private let scutilGlobal = ["/usr/sbin/scutil"]
private let scutilProxy = ["/usr/sbin/scutil", "--proxy"]
private let downloaderPgrep = ["/usr/bin/pgrep", "-x", "wx_video_download"]
private let osascript = "/usr/bin/osascript"
private let onVPN = CommandResult(status: 0, output: "  PrimaryInterface : utun8\n  PrimaryService : 019566B0-ECE7-707F-9A54-EED796210EB0\n")
private let ourEffectiveProxy = CommandResult(status: 0, output: "<dictionary> {\n  HTTPSEnable : 1\n  HTTPSPort : 2023\n  HTTPSProxy : 127.0.0.1\n}\n")
private let none = CommandResult(status: 1, output: "")

private let script = """
#!/bin/bash
trap 'exit 0' INT
echo started
while :; do sleep 0.1; done
"""

private func helperPgrep(_ setup: Setup) -> [String] {
    ["/usr/bin/pgrep", "-U", "0", "-f", setup.helper.scriptPath]
}

private struct Setup {
    let paths: DownloaderPaths
    let helper: VPNHelperLocation

    init() throws {
        let dir = try makeTempDir()
        let binary = dir.appendingPathComponent("wx_video_download")
        try script.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        paths = DownloaderPaths.resolve(env: [DownloaderPaths.supportDirEnvKey: dir.path], home: dir)
        helper = VPNHelperLocation(label: "test.helper",
                                   scriptPath: dir.appendingPathComponent("helper.sh").path,
                                   plistPath: dir.appendingPathComponent("helper.plist").path)
    }

    func installHelper(_ text: String = vpnHelperScript + "\n") throws {
        try text.write(toFile: helper.scriptPath, atomically: true, encoding: .utf8)
    }

    @MainActor
    func controller(_ runner: FakeRunner, listening: Bool = false) -> DownloaderController {
        DownloaderController(paths: paths, runner: runner, home: paths.supportDir, stopTimeout: 2,
                             proxyListening: { listening }, helper: helper, ruleList: FakeRuleList())
    }
}

private func osascriptCalls(_ runner: FakeRunner) -> [[String]] { runner.calls.filter { $0.first == osascript } }

@MainActor
@Suite(.serialized) struct VPNControllerTests {
    @Test func startWithVPNNeverAsksForPassword() async throws {
        let setup = try Setup()
        try setup.installHelper()
        let runner = FakeRunner([scutilGlobal: onVPN, helperPgrep(setup): ok("77\n")])
        let c = setup.controller(runner)
        await c.refresh()
        await c.start()
        #expect(c.isRunning)
        #expect(osascriptCalls(runner).isEmpty)
        await c.stop()
    }

    @Test func refreshReportsHelperStatus() async throws {
        let setup = try Setup()
        let runner = FakeRunner([downloaderPgrep: none, helperPgrep(setup): none])
        let c = setup.controller(runner)
        await c.refresh()
        #expect(c.helperStatus == .notInstalled)
        #expect(!c.helperRunning)
        try setup.installHelper()
        runner.set(helperPgrep(setup), ok("77\n"))
        await c.refresh()
        #expect(c.helperStatus == .installed)
        #expect(c.helperRunning)
        try setup.installHelper("an older helper\n")
        await c.refresh()
        #expect(c.helperStatus == .outdated)
    }

    @Test func installVPNHelperRunsElevatedInstall() async throws {
        let setup = try Setup()
        let runner = FakeRunner()
        let c = setup.controller(runner)
        await c.installVPNHelper()
        let call = try #require(osascriptCalls(runner).first)
        #expect(Array(call.suffix(3)) == [DownloaderController.setupPrompt,
                                          makeHelperInstallScript(location: setup.helper), vpnHelperScript])
        let appleScript = call.dropLast(3).joined(separator: "\n")
        #expect(!appleScript.contains(">/dev/null 2>&1 &"), "install must wait for the result")
    }

    @Test func removeVPNHelperRunsElevatedUninstall() async throws {
        let setup = try Setup()
        let runner = FakeRunner()
        let c = setup.controller(runner)
        await c.removeVPNHelper()
        let call = try #require(osascriptCalls(runner).first)
        #expect(Array(call.suffix(2)) == [DownloaderController.removePrompt, makeHelperUninstallScript(location: setup.helper)])
    }

    @Test func refreshReportsLeftoverVPNProxy() async throws {
        let setup = try Setup()
        let runner = FakeRunner([downloaderPgrep: none, scutilGlobal: onVPN, scutilProxy: ourEffectiveProxy, helperPgrep(setup): none])
        let c = setup.controller(runner)
        await c.refresh()
        #expect(c.routedThroughDownloader)
        #expect(c.vpnProxyLeftover)
        #expect(c.vpnStrip == .leftover)
    }

    @Test func noLeftoverWhileHelperOrDownloaderIsAlive() async throws {
        let setup = try Setup()
        let a = setup.controller(FakeRunner([downloaderPgrep: none, scutilGlobal: onVPN, scutilProxy: ourEffectiveProxy, helperPgrep(setup): ok("77\n")]))
        await a.refresh()
        #expect(!a.vpnProxyLeftover)
        let b = setup.controller(FakeRunner([downloaderPgrep: none, scutilGlobal: onVPN, scutilProxy: ourEffectiveProxy, helperPgrep(setup): none]), listening: true)
        await b.refresh()
        #expect(!b.vpnProxyLeftover)
    }

    @Test func helperRunningButNotRoutedIsNotGreen() async throws {
        let setup = try Setup()
        try setup.installHelper()
        let runner = FakeRunner([downloaderPgrep: ok("4242\n"), scutilGlobal: onVPN,
                                 scutilProxy: ok("<dictionary> {\n  HTTPSEnable : 0\n}\n"), helperPgrep(setup): ok("77\n")])
        let c = setup.controller(runner, listening: true)
        await c.refresh()
        #expect(c.vpnStrip != .on)
        #expect(c.vpnStrip == .starting) // just detected: grace period; .blockedByVPNProxy after 10 s (VPNStripTests)
        runner.set(scutilProxy, ourEffectiveProxy)
        await c.refresh()
        #expect(c.vpnStrip == .on)
    }

    @Test func installFailureIsReported() async throws {
        let setup = try Setup()
        let runner = FakeRunner()
        runner.setForPath(osascript, CommandResult(status: 1, output: "0:58: execution error: Bootstrap failed: 5: Input/output error (5)\n"))
        let c = setup.controller(runner)
        await c.installVPNHelper()
        #expect(c.helperMessage?.contains("Bootstrap failed: 5") == true)
        runner.setForPath(osascript, ok(""))
        await c.installVPNHelper()
        #expect(c.helperMessage == nil)
    }

    @Test func cancelledInstallIsQuiet() async throws {
        let setup = try Setup()
        let runner = FakeRunner()
        runner.setForPath(osascript, CommandResult(status: 1, output: "0:58: execution error: User canceled. (-128)\n"))
        let c = setup.controller(runner)
        await c.installVPNHelper()
        #expect(c.helperMessage == nil)
    }

    @Test func installedButNotRunningIsItsOwnState() async throws {
        let setup = try Setup()
        try setup.installHelper()
        let runner = FakeRunner([downloaderPgrep: none, scutilGlobal: onVPN, helperPgrep(setup): none])
        let c = setup.controller(runner)
        await c.refresh()
        #expect(c.helperStatus == .installed)
        #expect(!c.helperRunning)
        #expect(c.vpnStrip == .helperNotRunning)
    }

    @Test func fixVPNProxyRunsElevatedCleanup() async throws {
        let setup = try Setup()
        let runner = FakeRunner([downloaderPgrep: none, scutilGlobal: onVPN, scutilProxy: ourEffectiveProxy, helperPgrep(setup): none])
        let c = setup.controller(runner)
        await c.fixVPNProxy()
        let call = try #require(osascriptCalls(runner).first)
        #expect(call.last == vpnCleanupScript)
        #expect(!call.dropLast(2).joined(separator: "\n").contains(">/dev/null 2>&1 &"))
    }
}

@Suite struct VPNStripTests {
    @Test func stripStates() {
        func strip(vpn: Bool = true, running: Bool = true, helper: VPNHelperStatus = .installed, helperOn: Bool = true,
                   routed: Bool = true, leftover: Bool = false, age: Double? = nil) -> VPNStripState {
            vpnStripState(vpnActive: vpn, isRunning: running, helper: helper, helperRunning: helperOn,
                          routed: routed, leftover: leftover, secondsSinceStart: age)
        }
        #expect(strip(leftover: true) == .leftover)
        #expect(strip(vpn: false) == .none)
        #expect(strip(vpn: false, helper: .notInstalled) == .none)
        #expect(strip(helper: .notInstalled, helperOn: false) == .needsSetup)
        #expect(strip(helper: .outdated) == .needsUpdate)
        #expect(strip(helperOn: false) == .helperNotRunning)
        #expect(strip(running: false) == .ready)
        #expect(strip() == .on)
        #expect(strip(routed: false, age: 3) == .starting)
        #expect(strip(routed: false, age: 30) == .blockedByVPNProxy)
        #expect(strip(routed: false, age: nil) == .blockedByVPNProxy)
    }
}
