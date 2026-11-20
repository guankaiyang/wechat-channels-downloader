import Foundation
import Testing
@testable import DownloaderCore

private let vpnService = "019566B0-ECE7-707F-9A54-EED796210EB0"

@Suite(.serialized) struct VPNHelperDaemonTests {
    private func startHelper(_ fake: FakeSystem) throws -> Process {
        try fake.run(makeVPNHelperScript(tools: fake.tools, interval: "0.1"))
    }

    @Test func appliesWhileDownloaderListensOnVPN() throws {
        let fake = try FakeSystem()
        try fake.setPrimary(interface: "utun8", service: vpnService)
        try fake.setListener()
        let helper = try startHelper(fake)
        defer { helper.terminate() }
        #expect(eventually { fake.events.contains("SET \(vpnService)") }, "\(fake.diagnostics(helper))")
        #expect(fake.log.contains("d.add ChannelsDownloaderGuard # 1"))
        // The rule list, not an all-traffic proxy: other apps on the VPN keep connecting directly.
        #expect(fake.log.contains("d.add ProxyAutoConfigEnable # 1"))
        #expect(fake.log.contains("d.add ProxyAutoConfigURLString \(ruleListURL)"))
        #expect(!fake.log.contains("HTTPSProxy"))
        #expect(!fake.log.contains("HTTPProxy"))
    }

    @Test func helperIsVersion4() {
        #expect(vpnHelperScript.hasPrefix(": channels-vpn-helper v4\n"))
    }

    @Test func removesWhenDownloaderStops() throws {
        let fake = try FakeSystem()
        try fake.setPrimary(interface: "utun8", service: vpnService)
        try fake.setListener()
        let helper = try startHelper(fake)
        defer { helper.terminate() }
        #expect(eventually { fake.events.contains("SET \(vpnService)") }, "\(fake.diagnostics(helper))")
        fake.clearListener()
        #expect(eventually { fake.events.contains("REMOVE \(vpnService)") }, "\(fake.diagnostics(helper))")
        #expect(!fake.hasProxies(vpnService))
        #expect(helper.isRunning)
    }

    @Test func needsAListeningDownloader() throws {
        let fake = try FakeSystem()
        try fake.setPrimary(interface: "utun8", service: vpnService)
        let helper = try startHelper(fake) // nothing listening on 2023
        defer { helper.terminate() }
        Thread.sleep(forTimeInterval: 0.6)
        #expect(!fake.events.contains("SET"))
    }

    @Test func idleCheckSkipsLsofWhenNothingListens() throws {
        let fake = try FakeSystem()
        try fake.setPrimary(interface: "utun8", service: vpnService)
        let helper = try startHelper(fake) // nothing on 127.0.0.1:2023
        defer { helper.terminate() }
        #expect(eventually { fake.log.contains("nc -z -G 1 127.0.0.1 2023") }, "\(fake.diagnostics(helper))")
        Thread.sleep(forTimeInterval: 0.5)
        #expect(!fake.log.contains("lsof "), "the expensive check must only run when something listens")
    }

    @Test func ignoresListenerOwnedByAnotherUser() throws {
        let fake = try FakeSystem()
        try fake.setPrimary(interface: "utun8", service: vpnService)
        try fake.setListener(uid: 502) // console user is 501
        let helper = try startHelper(fake)
        defer { helper.terminate() }
        Thread.sleep(forTimeInterval: 0.6)
        #expect(!fake.events.contains("SET"))
        #expect(fake.log.contains("lsof -nP +c 0 -iTCP@127.0.0.1:2023 -sTCP:LISTEN -Fpcu"))
    }

    @Test func ignoresListenerWithAnotherName() throws {
        let fake = try FakeSystem()
        try fake.setPrimary(interface: "utun8", service: vpnService)
        try fake.setListener(name: "nc")
        let helper = try startHelper(fake)
        defer { helper.terminate() }
        Thread.sleep(forTimeInterval: 0.6)
        #expect(!fake.events.contains("SET"))
    }

    @Test func needsTheAppServingTheRuleList() throws {
        // Root must never point the VPN at a rule-list address nobody (or somebody else) serves.
        for serve in [nil, (name: appProcessName, uid: 502), (name: "python3", uid: 501)] {
            let fake = try FakeSystem()
            try fake.setPrimary(interface: "utun8", service: vpnService)
            try fake.setListener(appServing: false)
            if let serve { try fake.setPortListener(2024, name: serve.name, uid: serve.uid) }
            let helper = try startHelper(fake)
            defer { helper.terminate() }
            #expect(eventually { fake.log.contains("nc -z -G 1 127.0.0.1 2024") }, "\(fake.diagnostics(helper))")
            Thread.sleep(forTimeInterval: 0.5)
            #expect(!fake.events.contains("SET"), "served by \(String(describing: serve))")
        }
    }

    @Test func ignoresNonVPNPrimary() throws {
        let fake = try FakeSystem()
        try fake.setPrimary(interface: "en0", service: vpnService)
        try fake.setListener()
        let helper = try startHelper(fake)
        defer { helper.terminate() }
        Thread.sleep(forTimeInterval: 0.6)
        #expect(!fake.events.contains("SET"))
    }

    @Test func leavesUnmarkedEntriesAlone() throws {
        let fake = try FakeSystem()
        try fake.setPrimary(interface: "utun8", service: vpnService)
        try fake.setProxies(vpnService, "<dictionary> {\n  HTTPSPort : 2023\n  HTTPSProxy : 127.0.0.1\n}\n")
        try fake.setListener()
        let helper = try startHelper(fake)
        Thread.sleep(forTimeInterval: 0.6)
        fake.clearListener()
        Thread.sleep(forTimeInterval: 0.6)
        helper.terminate()
        #expect(eventually { !helper.isRunning })
        #expect(!fake.events.contains("SET"))
        #expect(!fake.events.contains("REMOVE"))
        #expect(fake.hasProxies(vpnService))
    }

    @Test func cleansStaleMarkedEntriesAtStart() throws {
        let fake = try FakeSystem()
        try fake.setProxies(vpnService, FakeSystem.marked)
        let helper = try startHelper(fake)
        defer { helper.terminate() }
        #expect(eventually { fake.events.contains("REMOVE \(vpnService)") }, "\(fake.diagnostics(helper))")
        #expect(!fake.hasProxies(vpnService))
    }

    @Test func cleansUpWhenStopped() throws {
        let fake = try FakeSystem()
        try fake.setPrimary(interface: "utun8", service: vpnService)
        try fake.setListener()
        let helper = try startHelper(fake)
        #expect(eventually { fake.events.contains("SET \(vpnService)") }, "\(fake.diagnostics(helper))")
        helper.terminate() // launchd unload / uninstall sends SIGTERM
        #expect(eventually { !helper.isRunning })
        #expect(fake.events.contains("REMOVE \(vpnService)"))
        #expect(!fake.hasProxies(vpnService))
    }

    @Test func rejectsMalformedServiceID() throws {
        let fake = try FakeSystem()
        try fake.setPrimary(interface: "utun8", service: "ABC;touch /tmp/pwned")
        try fake.setListener()
        let helper = try startHelper(fake)
        defer { helper.terminate() }
        Thread.sleep(forTimeInterval: 0.6)
        #expect(!fake.events.contains("SET"))
    }

    @Test func reappliesAfterVPNReconnects() throws {
        let fake = try FakeSystem()
        try fake.setPrimary(interface: "utun8", service: vpnService)
        try fake.setListener()
        let helper = try startHelper(fake)
        defer { helper.terminate() }
        #expect(eventually { fake.events.contains("SET \(vpnService)") }, "\(fake.diagnostics(helper))")
        let next = "1A2B3C4D-0000-1111-2222-333344445555"
        try fake.setPrimary(interface: "utun9", service: next)
        #expect(eventually { fake.events.contains("SET \(next)") }, "\(fake.diagnostics(helper))")
    }
}

@Suite(.serialized) struct VPNHelperInstallTests {
    private func runToEnd(_ process: Process) -> Bool {
        eventually { !process.isRunning } && process.terminationStatus == 0
    }

    private func mode(_ path: String) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions]) as? Int
    }

    @Test func installWritesFilesAndLoadsDaemon() throws {
        let fake = try FakeSystem()
        let install = try fake.run(makeHelperInstallScript(location: fake.location, tools: fake.tools), args: ["HELPER v1"])
        #expect(runToEnd(install), "\(fake.diagnostics(install))")
        #expect(try String(contentsOfFile: fake.location.scriptPath, encoding: .utf8) == "HELPER v1\n")
        #expect(mode(fake.location.scriptPath) == 0o755)
        #expect(mode(fake.location.plistPath) == 0o644)
        let lint = Process()
        lint.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        lint.arguments = ["-lint", fake.location.plistPath]
        lint.standardOutput = FileHandle.nullDevice
        try lint.run(); lint.waitUntilExit()
        #expect(lint.terminationStatus == 0)
        let plist = try #require(NSDictionary(contentsOfFile: fake.location.plistPath))
        #expect(plist["Label"] as? String == "test.vpn-helper")
        #expect(plist["ProgramArguments"] as? [String] == ["/bin/sh", fake.location.scriptPath])
        #expect(plist["RunAtLoad"] as? Bool == true)
        #expect(plist["KeepAlive"] as? Bool == true)
        let events = fake.events
        #expect(events.components(separatedBy: "chown root:wheel").count - 1 == 2)
        #expect(events.contains("launchctl bootout system/test.vpn-helper"))
        #expect(events.contains("launchctl bootstrap system \(fake.location.plistPath)"))
    }

    @Test func aliveCheckMatchesLaunchdArguments() throws {
        let fake = try FakeSystem()
        let install = try fake.run(makeHelperInstallScript(location: fake.location, tools: fake.tools), args: ["HELPER v1"])
        #expect(runToEnd(install))
        let plist = try #require(NSDictionary(contentsOfFile: fake.location.plistPath))
        let argv = try #require(plist["ProgramArguments"] as? [String]).joined(separator: " ")
        // pgrep -f matches the process's argument list, which is what launchd starts.
        #expect(argv.contains(vpnHelperAlivePattern(fake.location)))
        #expect(vpnHelperAlivePattern(.system) == VPNHelperLocation.system.scriptPath)
    }

    @Test func reinstallReplacesHelper() throws {
        let fake = try FakeSystem()
        let script = makeHelperInstallScript(location: fake.location, tools: fake.tools)
        #expect(runToEnd(try fake.run(script, args: ["HELPER v1"])))
        #expect(runToEnd(try fake.run(script, args: ["HELPER v2"])))
        #expect(try String(contentsOfFile: fake.location.scriptPath, encoding: .utf8) == "HELPER v2\n")
    }

    @Test func uninstallRemovesEverything() throws {
        let fake = try FakeSystem()
        #expect(runToEnd(try fake.run(makeHelperInstallScript(location: fake.location, tools: fake.tools), args: ["HELPER v1"])))
        let unmarked = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try fake.setProxies(vpnService, FakeSystem.marked)
        try fake.setProxies(unmarked, "<dictionary> {\n  HTTPSPort : 2023\n  HTTPSProxy : 127.0.0.1\n}\n")
        #expect(runToEnd(try fake.run(makeHelperUninstallScript(location: fake.location, tools: fake.tools))))
        #expect(!FileManager.default.fileExists(atPath: fake.location.scriptPath))
        #expect(!FileManager.default.fileExists(atPath: fake.location.plistPath))
        #expect(fake.events.components(separatedBy: "launchctl bootout system/test.vpn-helper").count - 1 == 2)
        #expect(!fake.hasProxies(vpnService))
        #expect(fake.hasProxies(unmarked))
    }
}

@Suite struct VPNHelperStatusTests {
    @Test func statusComparesInstalledScript() {
        #expect(vpnHelperStatus(installedScript: nil) == .notInstalled)
        #expect(vpnHelperStatus(installedScript: vpnHelperScript + "\n") == .installed)
        #expect(vpnHelperStatus(installedScript: "older helper\n") == .outdated)
    }

    @Test func shippedScriptsUseFixedSystemTools() {
        #expect(vpnHelperScript.contains("S=/usr/sbin/scutil"))
        #expect(vpnHelperScript.contains("LS=/usr/sbin/lsof"))
        #expect(vpnHelperScript.contains("ST=/usr/bin/stat"))
        #expect(vpnHelperScript.contains("NC=/usr/bin/nc"))
        #expect(vpnHelperScript.contains("T=2\n"))
        let install = makeHelperInstallScript()
        #expect(install.contains("CH=/usr/sbin/chown"))
        #expect(install.contains("LC=/bin/launchctl"))
        #expect(install.contains("H=/Library/PrivilegedHelperTools/local.wechat-channels-downloader.vpn-helper.sh"))
        #expect(install.contains("P=/Library/LaunchDaemons/local.wechat-channels-downloader.vpn-helper.plist"))
        for script in [vpnHelperScript, install, makeHelperUninstallScript(), vpnCleanupScript] {
            #expect(!script.contains("${SCUTIL"))
            #expect(!script.contains("${PATH"))
        }
    }
}
