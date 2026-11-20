import CFNetwork
import Foundation
import Testing
@testable import DownloaderCore

/// Runs `script` through macOS's own PAC engine and returns e.g. "PROXY 127.0.0.1:2023; DIRECT".
private func route(_ script: String, _ url: String) -> String {
    var error: Unmanaged<CFError>?
    guard let list = CFNetworkCopyProxiesForAutoConfigurationScript(
        script as CFString, URL(string: url)! as CFURL, &error)?.takeRetainedValue() as? [[String: Any]]
    else { return "error: \(String(describing: error?.takeRetainedValue()))" }
    return list.map { proxy in
        if (proxy[kCFProxyTypeKey as String] as? String) == (kCFProxyTypeNone as String) { return "DIRECT" }
        return "PROXY \(proxy[kCFProxyHostNameKey as String] ?? "?"):\(proxy[kCFProxyPortNumberKey as String] ?? "?")"
    }.joined(separator: "; ")
}

private let listServices = [networksetup, "-listallnetworkservices"]
private let services = "An asterisk (*) denotes that a network service is disabled.\nWi-Fi\n*Thunderbolt Bridge\nUSB LAN\n"

private func autoproxy(_ url: String, _ enabled: Bool) -> CommandResult {
    ok("URL: \(url)\nEnabled: \(enabled ? "Yes" : "No")\n")
}

@Suite struct RuleListScriptTests {
    @Test func weChatAddressesGoThroughTheDownloaderOthersDirect() {
        let script = ruleListScript(downloaderUp: true)
        for url in ["https://channels.weixin.qq.com/web/pages/feed", "https://res.wx.qq.com/a.js",
                    "https://mmbiz.qpic.cn/x.jpg", "http://qq.com/", "https://WWW.WeChat.com/"] {
            #expect(route(script, url) == "PROXY 127.0.0.1:2023; DIRECT", "\(url)")
        }
        for url in ["https://api.anthropic.com/v1/messages", "https://claude.ai/", "https://www.google.com/",
                    "https://notqq.com/", "https://qq.com.evil.example/", "https://qpic.cn.example/"] {
            #expect(route(script, url) == "DIRECT", "\(url)")
        }
    }

    @Test func everythingDirectWhileTheDownloaderIsDown() {
        let script = ruleListScript(downloaderUp: false)
        for url in ["https://channels.weixin.qq.com/", "https://api.anthropic.com/"] {
            #expect(route(script, url) == "DIRECT", "\(url)")
        }
    }
}

@Suite struct RuleListSwitchTests {
    @Test func turnOnSetsOurRuleListOnEnabledServicesOnly() {
        let runner = FakeRunner([listServices: ok(services)])
        runner.setForPath(networksetup, autoproxy("(null)", false))
        let changed = turnOnRuleList(runner: runner)
        #expect(changed == ["Wi-Fi", "USB LAN"])
        let sets = runner.setCalls
        #expect(sets.contains([networksetup, "-setautoproxyurl", "Wi-Fi", ruleListURL]))
        #expect(sets.contains([networksetup, "-setautoproxystate", "Wi-Fi", "on"]))
        #expect(sets.contains([networksetup, "-setautoproxyurl", "USB LAN", ruleListURL]))
        #expect(!sets.contains { $0.contains("Thunderbolt Bridge") })
    }

    @Test func turnOnLeavesSomeoneElsesRuleListAlone() {
        let runner = FakeRunner([
            listServices: ok("An asterisk (*) denotes that a network service is disabled.\nWi-Fi\n"),
            [networksetup, "-getautoproxyurl", "Wi-Fi"]: autoproxy("http://corp.example/proxy.pac", true),
        ])
        #expect(turnOnRuleList(runner: runner).isEmpty)
        #expect(runner.setCalls.isEmpty)
    }

    @Test func turnOnReplacesADisabledForeignURL() {
        let runner = FakeRunner([
            listServices: ok("An asterisk (*) denotes that a network service is disabled.\nWi-Fi\n"),
            [networksetup, "-getautoproxyurl", "Wi-Fi"]: autoproxy("http://corp.example/proxy.pac", false),
        ])
        #expect(turnOnRuleList(runner: runner) == ["Wi-Fi"])
    }

    @Test func turnOffOnlyTouchesOurEnabledRuleList() {
        let runner = FakeRunner([
            listServices: ok(services),
            [networksetup, "-getautoproxyurl", "Wi-Fi"]: autoproxy(ruleListURL, true),
            [networksetup, "-getautoproxyurl", "USB LAN"]: autoproxy("http://corp.example/proxy.pac", true),
        ])
        #expect(turnOffRuleList(runner: runner) == ["Wi-Fi"])
        #expect(runner.setCalls == [[networksetup, "-setautoproxystate", "Wi-Fi", "off"]])
    }
}

@Suite struct AppConfigTests {
    @Test func turnsOffOnlyTheDownloadersOwnSystemProxySwitch() {
        let original = """
        api:
          hostname: "127.0.0.1"
          system: true
        proxy:
          enabled: true
          system: true
          hostname: "127.0.0.1"
          port: 2023
        cookie:
          uuid: ""
        """
        let expected = original.replacingOccurrences(of: "proxy:\n  enabled: true\n  system: true",
                                                     with: "proxy:\n  enabled: true\n  system: false")
        #expect(appConfigYAML(from: original) == expected)
    }

    @Test func handlesCommentsAndWindowsLineEndings() {
        #expect(appConfigYAML(from: "proxy: # proxy settings\n  enabled: true\n  system: true\n")
                == "proxy: # proxy settings\n  enabled: true\n  system: false\n")
        #expect(appConfigYAML(from: "proxy:\r\n  system: true\r\nlog:\r\n  level: info\r\n")
                == "proxy:\r\n  system: false\r\nlog:\r\n  level: info\r\n")
        #expect(appConfigYAML(from: "proxy:\n  port: 2023\n# tuning\n  system: true  # set the Mac's proxy\n")
                == "proxy:\n  port: 2023\n# tuning\n  system: false\n")
    }

    @Test func addsTheSwitchWhenTheProxySectionLacksIt() {
        let result = appConfigYAML(from: "proxy:\n  port: 2023\ncookie:\n  uuid: \"\"\n")
        #expect(result == "proxy:\n  system: false\n  port: 2023\ncookie:\n  uuid: \"\"\n")
    }
}

@Suite(.serialized) struct RuleListServerTests {
    private func fetch(_ port: UInt16) async throws -> (String, String?) {
        let (data, response) = try await URLSession(configuration: .ephemeral)
            .data(from: URL(string: "http://127.0.0.1:\(port)/proxy.pac")!)
        return (String(decoding: data, as: UTF8.self), (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"))
    }

    @Test func servesTheRuleListThatMatchesTheDownloaderState() async throws {
        let up = LockedFlag(true)
        let server = RuleListServer(port: 20245, downloaderUp: { up.value })
        try await server.start()
        defer { server.stop() }
        let (body, type) = try await fetch(20245)
        #expect(body == ruleListScript(downloaderUp: true))
        #expect(type == "application/x-ns-proxy-autoconfig")
        up.value = false
        #expect(try await fetch(20245).0 == ruleListScript(downloaderUp: false))
    }

    @Test func startIsSafeToRepeatAndStopFreesThePort() async throws {
        let server = RuleListServer(port: 20246, downloaderUp: { true })
        try await server.start()
        try await server.start()
        server.stop()
        try await Task.sleep(for: .milliseconds(200))
        let again = RuleListServer(port: 20246, downloaderUp: { true })
        try await again.start()
        again.stop()
    }

    @Test func simultaneousStartsShareOneListener() async throws {
        let server = RuleListServer(port: 20248, downloaderUp: { true })
        defer { server.stop() }
        async let first: Void = server.start()
        async let second: Void = server.start()
        try await first
        try await second
        #expect(server.isRunning)
    }

    @Test func startFailsWhenThePortIsTaken() async throws {
        let first = RuleListServer(port: 20247, downloaderUp: { true })
        try await first.start()
        defer { first.stop() }
        let second = RuleListServer(port: 20247, downloaderUp: { true })
        await #expect(throws: (any Error).self) { try await second.start() }
    }
}

final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool
    init(_ value: Bool) { stored = value }
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

@Suite struct EffectiveProxyRuleListTests {
    @Test func ourRuleListCountsAsRouted() {
        let output = """
        <dictionary> {
          HTTPEnable : 0
          HTTPSEnable : 0
          ProxyAutoConfigEnable : 1
          ProxyAutoConfigURLString : \(ruleListURL)
        }
        """
        #expect(isDownloaderEffectiveProxy(scutilProxyOutput: output))
    }

    @Test func someoneElsesOrDisabledRuleListDoesNot() {
        #expect(!isDownloaderEffectiveProxy(scutilProxyOutput:
            "<dictionary> {\n  ProxyAutoConfigEnable : 1\n  ProxyAutoConfigURLString : http://corp.example/p.pac\n}"))
        #expect(!isDownloaderEffectiveProxy(scutilProxyOutput:
            "<dictionary> {\n  ProxyAutoConfigEnable : 0\n  ProxyAutoConfigURLString : \(ruleListURL)\n}"))
    }
}
