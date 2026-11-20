import Foundation

public enum DownloaderState: Equatable, Sendable {
    case stopped
    case starting
    case running(pid: Int32, external: Bool)
    case stopping
    case failed(String)
}

/// Starts and stops the downloader process and keeps the Mac's proxy clean.
///
/// State is always written *before* any `await`, so work that finishes later can never
/// overwrite a newer state (e.g. a slow cleanup flipping a fresh run back to "Stopped").
/// Proxy cleanup only runs on transitions (launch, Stop, a process ending), and never
/// while something is listening on 127.0.0.1:2023 — that proxy belongs to a live downloader.
@MainActor
public final class DownloaderController: ObservableObject {
    @Published public private(set) var state: DownloaderState = .stopped
    @Published public private(set) var vpnActive = false
    /// Whether the once-installed VPN helper is installed and matches this build.
    @Published public private(set) var helperStatus: VPNHelperStatus = .notInstalled
    /// The VPN helper daemon is running.
    @Published public private(set) var helperRunning = false
    /// Why the last set-up / remove / fix didn't work (nil if it worked or was cancelled).
    @Published public private(set) var helperMessage: String?
    /// The Mac's effective HTTPS proxy is the downloader.
    @Published public private(set) var routedThroughDownloader = false
    /// The VPN connection still points at a downloader that isn't running (needs "Fix").
    @Published public private(set) var vpnProxyLeftover = false

    public let paths: DownloaderPaths
    private let runner: CommandRunner
    private let home: URL
    private let stopTimeout: Double
    private let proxyListening: @Sendable () -> Bool
    private var process: Process?
    private var logHandle: FileHandle?
    private var startTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var ruleListTask: Task<Void, Never>?
    private var checkedForLeftoverProxy = false
    private var runningSince: Date?
    private let helper: VPNHelperLocation
    private let ruleList: RuleListServing

    public static let trustFailedMessage = "Certificate wasn't trusted, so downloads can't work. Click Start to try again."
    public static let setupPrompt = "WeChat Channels Downloader needs your password once to set up VPN mode, so downloads work while your VPN is on."
    public static let removePrompt = "WeChat Channels Downloader needs your password to remove the VPN helper."
    public static let fixPrompt = "WeChat Channels Downloader needs your password to remove the downloader's proxy from your VPN connection."

    public init(paths: DownloaderPaths,
                runner: CommandRunner = ProcessRunner(),
                home: URL = FileManager.default.homeDirectoryForCurrentUser,
                stopTimeout: Double = 8,
                proxyListening: @escaping @Sendable () -> Bool = {
                    isPortListening(port: UInt16(downloaderProxyPort) ?? 2023)
                },
                helper: VPNHelperLocation = .system,
                ruleList: RuleListServing? = nil) {
        self.paths = paths
        self.runner = runner
        self.home = home
        self.stopTimeout = stopTimeout
        self.proxyListening = proxyListening
        self.helper = helper
        self.ruleList = ruleList ?? RuleListServer(downloaderUp: proxyListening)
    }

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// True while quitting must wait: a downloader is running, starting or stopping.
    public var needsShutdown: Bool {
        switch state {
        case .running, .starting, .stopping: return true
        case .stopped, .failed: return false
        }
    }

    // MARK: Start

    public func start() async {
        switch state {
        case .running, .starting, .stopping: return
        case .stopped, .failed: break
        }
        state = .starting
        let task = Task { await self.performStart() }
        startTask = task
        await task.value
        startTask = nil
    }

    private func performStart() async {
        let runner = self.runner, cert = paths.caCert, home = self.home
        let trusted = await Task.detached {
            isCertificateTrusted(cert, runner: runner) || trustCertificate(cert, runner: runner, home: home)
        }.value
        guard state == .starting else { return }
        guard trusted else {
            state = .failed(Self.trustFailedMessage)
            return
        }
        do {
            try await ruleList.start()
        } catch {
            state = .failed("Couldn't serve the proxy rule list. \(error.localizedDescription)")
            return
        }
        guard state == .starting else { return }
        // If something already owns 127.0.0.1:2023 (e.g. a Terminal-started downloader), ours will fail to
        // listen; never point the rule list at someone else's proxy.
        let portTakenBefore = await Task.detached { [proxyListening] in proxyListening() }.value
        do {
            try launch()
        } catch {
            state = .failed("Couldn't start the downloader: \(error.localizedDescription)")
            return
        }
        if !portTakenBefore {
            ruleListTask = Task { await self.turnOnRuleListOnceListening() }
        }
    }

    /// Only WeChat's addresses go through the downloader; every other app keeps connecting directly.
    /// Switches the rule list on once the downloader listens, so nobody caches the all-direct version.
    /// Stop and crash handling cancel this and wait for it before they clean up.
    private func turnOnRuleListOnceListening() async {
        let listening = self.proxyListening, runner = self.runner
        let deadline = Date().addingTimeInterval(15)
        while !Task.isCancelled, isRunning, Date() < deadline {
            if await Task.detached(operation: { listening() }).value {
                guard !Task.isCancelled, isRunning else { return }
                await Task.detached { _ = turnOnRuleList(runner: runner) }.value
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    /// Stops a pending rule-list switch-on and waits until it can't run any more.
    private func cancelRuleListSwitch() async {
        guard let task = ruleListTask else { return }
        task.cancel()
        await task.value
        ruleListTask = nil
    }

    // MARK: VPN mode

    /// Installs (or updates) the root VPN helper. macOS asks for the password once.
    public func installVPNHelper() async {
        await runElevated(script: makeHelperInstallScript(location: helper), args: [vpnHelperScript],
                          prompt: Self.setupPrompt, action: "set up VPN mode")
    }

    /// Unloads and deletes the VPN helper and removes any proxy entries it left (asks for the password).
    public func removeVPNHelper() async {
        await runElevated(script: makeHelperUninstallScript(location: helper), args: [], prompt: Self.removePrompt,
                          action: "remove the VPN helper")
    }

    public func dismissHelperMessage() { helperMessage = nil }

    private func runElevated(script: String, args: [String], prompt: String, action: String) async {
        let runner = self.runner
        let argv = elevatedCommand(script: script, args: args, prompt: prompt, background: false)
        let result = await Task.detached { runner.run("/usr/bin/osascript", argv) }.value
        helperMessage = elevatedFailureMessage(result, action: action)
        await refresh()
    }

    /// What the VPN strip should show right now.
    public var vpnStrip: VPNStripState {
        vpnStripState(vpnActive: vpnActive, isRunning: isRunning, helper: helperStatus, helperRunning: helperRunning,
                      routed: routedThroughDownloader, leftover: vpnProxyLeftover,
                      secondsSinceStart: runningSince.map { Date().timeIntervalSince($0) })
    }

    /// Removes a downloader proxy left on the VPN connection (asks for the password).
    public func fixVPNProxy() async {
        await runElevated(script: vpnCleanupScript, args: [], prompt: Self.fixPrompt, action: "remove the proxy")
    }

    private func launch() throws {
        // Run with a copy of config.yaml whose proxy.system is off: the app sets the rule list instead.
        let userConfig = (try? String(contentsOf: paths.config, encoding: .utf8)) ?? ""
        try appConfigYAML(from: userConfig).write(to: paths.appConfig, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: paths.logFile.path, contents: nil) // fresh log per run
        let log = try FileHandle(forWritingTo: paths.logFile)
        let process = Process()
        process.executableURL = paths.binary
        process.arguments = ["-c", paths.appConfig.path]
        process.currentDirectoryURL = paths.supportDir
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = log
        process.standardError = log
        process.terminationHandler = { [weak self] finished in
            let pid = finished.processIdentifier
            Task { @MainActor in await self?.processExited(pid: pid) }
        }
        try process.run()
        self.process = process
        self.logHandle = log
        runningSince = Date()
        state = .running(pid: process.processIdentifier, external: false)
    }

    /// Our own process ended. If nobody asked it to stop, it crashed or failed to start.
    private func processExited(pid: Int32) async {
        guard process?.processIdentifier == pid else { return }
        process = nil
        try? logHandle?.close()
        logHandle = nil
        guard case .running(pid, external: false) = state else { return } // stop() handles its own cleanup
        state = .failed(lastLogLines())
        await cancelRuleListSwitch()
        await cleanProxy()
    }

    // MARK: Stop

    public func stop() async {
        if let stopTask {
            await stopTask.value
            return
        }
        guard case .running(let pid, let external) = state else { return }
        state = .stopping
        let task = Task { await self.performStop(pid: pid, external: external) }
        stopTask = task
        await task.value
        stopTask = nil
    }

    private func performStop(pid: Int32, external: Bool) async {
        if !external, let process {
            process.interrupt()
            await waitForExit(seconds: stopTimeout) { !process.isRunning }
            if process.isRunning {
                kill(pid, SIGKILL)
                await waitForExit(seconds: 2) { !process.isRunning }
            }
            self.process = nil
            try? logHandle?.close()
            logHandle = nil
        } else {
            kill(pid, SIGINT)
            await waitForExit(seconds: stopTimeout) { kill(pid, 0) != 0 }
            if kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
                await waitForExit(seconds: 2) { kill(pid, 0) != 0 }
            }
        }
        await cancelRuleListSwitch()
        await cleanProxy()
        runningSince = nil // the VPN helper sees the downloader stop and removes its VPN proxy itself
        if state == .stopping { state = .stopped }
    }

    private func waitForExit(seconds: Double, _ gone: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !gone() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Used when the app quits: finish any start or stop in flight, stop what's running,
    /// and make sure the proxy is off.
    public func shutdown() async {
        if let startTask { await startTask.value }
        if let stopTask { await stopTask.value }
        if isRunning { await stop() }
        await cleanProxy()
    }

    // MARK: Refresh

    /// Picks up a downloader started elsewhere (e.g. Terminal), notices when it goes away,
    /// cleans a proxy left behind by a crash (once, at launch), and checks for a VPN.
    public func refresh() async {
        // Keep the rule list served while the app runs (also for a downloader started from Terminal
        // that the VPN helper routes with the rule list). A busy port is reported when Start is clicked.
        if !ruleList.isRunning { try? await ruleList.start() }
        let runner = self.runner, listening = self.proxyListening, helperPath = helper.scriptPath, helperPattern = vpnHelperAlivePattern(helper)
        let probe = await Task.detached { () -> RefreshProbe in
            func firstPID(_ result: CommandResult) -> Int32? {
                result.status == 0
                    ? result.output.split(whereSeparator: \.isNewline).compactMap { Int32($0) }.first
                    : nil
            }
            return RefreshProbe(
                externalPID: firstPID(runner.run("/usr/bin/pgrep", ["-x", "wx_video_download"])),
                primary: currentPrimaryInterface(runner: runner),
                routed: isDownloaderEffectiveProxy(scutilProxyOutput: runner.run("/usr/sbin/scutil", ["--proxy"]).output),
                helperScript: try? String(contentsOfFile: helperPath, encoding: .utf8),
                helperAlive: firstPID(runner.run("/usr/bin/pgrep", ["-U", "0", "-f", helperPattern])) != nil,
                portInUse: listening())
        }.value
        let externalPID = probe.externalPID
        vpnActive = probe.primary.map(isVPNInterface) ?? false
        routedThroughDownloader = probe.routed
        helperStatus = vpnHelperStatus(installedScript: probe.helperScript)
        helperRunning = probe.helperAlive
        vpnProxyLeftover = vpnActive && probe.routed && !probe.helperAlive && !probe.portInUse

        switch state {
        case .starting, .stopping, .running(_, external: false):
            return
        case .running(_, external: true):
            if let externalPID {
                state = .running(pid: externalPID, external: true)
            } else {
                state = .stopped
                runningSince = nil
                await cleanProxy()
            }
        case .stopped, .failed:
            if let externalPID {
                runningSince = Date()
                state = .running(pid: externalPID, external: true)
            } else if !checkedForLeftoverProxy {
                checkedForLeftoverProxy = true
                await cleanProxy()
            }
        }
    }

    // MARK: Helpers

    /// Turns off our rule list and any leftover downloader proxy, unless a live downloader is listening on 127.0.0.1:2023.
    private func cleanProxy() async {
        let runner = self.runner, listening = self.proxyListening
        await Task.detached {
            guard !listening() else { return }
            _ = turnOffDownloaderSettings(runner: runner)
        }.value
    }

    private func lastLogLines(_ count: Int = 3) -> String {
        let text = (try? String(contentsOf: paths.logFile, encoding: .utf8)) ?? ""
        let lines = text
            .replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let tail = lines.suffix(count).joined(separator: "\n")
        return tail.isEmpty ? "The downloader stopped unexpectedly." : tail
    }
}

/// What one refresh tick observed, gathered off the main actor.
private struct RefreshProbe: Sendable {
    let externalPID: Int32?
    let primary: String?
    let routed: Bool
    let helperScript: String?
    let helperAlive: Bool
    let portInUse: Bool
}
