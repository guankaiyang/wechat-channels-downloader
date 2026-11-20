import Foundation
import Testing
@testable import DownloaderCore

private let vpnService = "019566B0-ECE7-707F-9A54-EED796210EB0"

@Suite(.serialized) struct VPNCleanupTests {
    @Test func cleanupRemovesOnlyOurEntries() throws {
        let fake = try FakeSystem()
        let foreign = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let lookalike = "BBBBBBBB-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let unmarked = "CCCCCCCC-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try fake.setProxies(vpnService, FakeSystem.marked)
        try fake.setProxies(foreign, "<dictionary> {\n  HTTPSPort : 8080\n  HTTPSProxy : 10.0.0.1\n}\n")
        try fake.setProxies(lookalike, "<dictionary> {\n  HTTPSPort : 20235\n  HTTPSProxy : 127.0.0.12\n}\n")
        try fake.setProxies(unmarked, "<dictionary> {\n  HTTPSPort : 2023\n  HTTPSProxy : 127.0.0.1\n}\n")
        let cleanup = try fake.run(makeVPNCleanupScript(scutil: fake.tools.scutil))
        #expect(eventually { !cleanup.isRunning })
        #expect(!fake.hasProxies(vpnService))
        #expect(fake.hasProxies(foreign))
        #expect(fake.hasProxies(lookalike))
        #expect(fake.hasProxies(unmarked))
    }
}

@Suite struct VPNParsingTests {
    @Test func effectiveProxyParsing() {
        let ours = "<dictionary> {\n  HTTPEnable : 1\n  HTTPPort : 2023\n  HTTPProxy : 127.0.0.1\n  HTTPSEnable : 1\n  HTTPSPort : 2023\n  HTTPSProxy : 127.0.0.1\n}\n"
        #expect(isDownloaderEffectiveProxy(scutilProxyOutput: ours))
        #expect(!isDownloaderEffectiveProxy(scutilProxyOutput: ours.replacingOccurrences(of: "HTTPSEnable : 1", with: "HTTPSEnable : 0")))
        #expect(!isDownloaderEffectiveProxy(scutilProxyOutput: ours.replacingOccurrences(of: "HTTPSPort : 2023", with: "HTTPSPort : 9090")))
        #expect(!isDownloaderEffectiveProxy(scutilProxyOutput: "<dictionary> {\n  ExceptionsList : <array> {\n  }\n}\n"))
    }

    @Test func effectiveProxyIgnoresScopedEntries() {
        let scoped = """
        <dictionary> {
          HTTPSEnable : 0
          __SCOPED__ : <dictionary> {
            en0 : <dictionary> {
              HTTPSEnable : 1
              HTTPSPort : 2023
              HTTPSProxy : 127.0.0.1
            }
          }
        }

        """
        #expect(!isDownloaderEffectiveProxy(scutilProxyOutput: scoped))
    }

    @Test func elevatedCommandPassesArgsAsArgv() {
        let argv = elevatedCommand(script: "echo hi", args: ["123"], prompt: "Allow it", background: true)
        #expect(Array(argv.suffix(3)) == ["Allow it", "echo hi", "123"])
        let source = argv.dropLast(3).joined(separator: "\n")
        #expect(source.contains("with administrator privileges"))
        #expect(source.contains("quoted form of"))
        #expect(source.contains("/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/sh -c"))
        #expect(!source.contains("echo hi"))
        #expect(!source.contains("Allow it"))
    }

    @Test func shippedCleanupScriptIgnoresTheEnvironment() {
        #expect(!vpnCleanupScript.contains("${SCUTIL"))
        #expect(vpnCleanupScript.contains("S=/usr/sbin/scutil"))
    }
}
