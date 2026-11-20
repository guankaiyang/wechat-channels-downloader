import Foundation
import Testing
@testable import DownloaderCore

@Suite struct ProxyTests {
    @Test func proxyMatchesOnlyOurs() {
        #expect(isDownloaderProxy(ourProxy))
        #expect(!isDownloaderProxy(noProxy))
        #expect(!isDownloaderProxy("Enabled: Yes\nServer: 127.0.0.1\nPort: 9090\n"))
        #expect(!isDownloaderProxy("Enabled: Yes\nServer: proxy.school\nPort: 2023\n"))
    }

    @Test func turnsOffOnlyMatchingServices() {
        let runner = FakeRunner([
            [networksetup, "-listallnetworkservices"]:
                ok("An asterisk (*) denotes that a network service is disabled.\nWi-Fi\n*USB 10/100/1000 LAN\nThunderbolt Bridge\n"),
            [networksetup, "-getwebproxy", "Wi-Fi"]: ok(ourProxy),
            [networksetup, "-getsecurewebproxy", "Wi-Fi"]: ok(ourProxy),
            [networksetup, "-getwebproxy", "USB 10/100/1000 LAN"]: ok(noProxy),
            [networksetup, "-getsecurewebproxy", "USB 10/100/1000 LAN"]: ok(noProxy),
            [networksetup, "-getwebproxy", "Thunderbolt Bridge"]: ok("Enabled: Yes\nServer: 127.0.0.1\nPort: 9090\n"),
            [networksetup, "-getsecurewebproxy", "Thunderbolt Bridge"]: ok(noProxy),
        ])
        let changed = turnOffDownloaderProxies(runner: runner)
        #expect(changed == ["Wi-Fi"])
        let sets = runner.calls.filter { $0.count > 1 && $0[1].hasPrefix("-set") }
        #expect(sets == [
            [networksetup, "-setwebproxystate", "Wi-Fi", "off"],
            [networksetup, "-setsecurewebproxystate", "Wi-Fi", "off"],
        ])
    }
}

@Suite struct NetworkTests {
    @Test func parsesPrimaryInterface() {
        let sample = "<dictionary> {\n  PrimaryInterface : utun8\n  PrimaryService : 0195-ABC\n  Router : 10.127.124.36\n}\n"
        #expect(primaryInterface(scutilOutput: sample) == "utun8")
        #expect(primaryInterface(scutilOutput: "") == nil)
    }

    @Test func readsPrimaryInterfaceThroughScutil() {
        let runner = FakeRunner(fallback: ok("  PrimaryInterface : en0\n"))
        #expect(currentPrimaryInterface(runner: runner) == "en0")
        #expect(runner.calls == [["/usr/sbin/scutil"]])
        #expect(runner.lastInput == "show State:/Network/Global/IPv4\n")
    }

    @Test func vpnPrefixes() {
        for name in ["utun8", "ppp0", "ipsec0"] { #expect(isVPNInterface(name)) }
        for name in ["en0", "bridge0"] { #expect(!isVPNInterface(name)) }
    }
}

@Suite struct PathTests {
    let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    @Test func downloadsDirFromConfig() {
        let yaml = "download:\n  filenameTemplate: \"x\"\n  dir: \"%UserDownloads%/WeChat Channels\"\n  maxRunning: 3\n"
        #expect(downloadsDirectory(configYAML: yaml, home: home).path == "/Users/tester/Downloads/WeChat Channels")
        let absolute = "download:\n  dir: \"/tmp/x\"\n"
        #expect(downloadsDirectory(configYAML: absolute, home: home).path == "/tmp/x")
        #expect(downloadsDirectory(configYAML: "api:\n  port: 2022\n", home: home).path
                == "/Users/tester/Downloads/WeChat Channels")
    }

    @Test func ignoresDirLinesOutsideDownloadSection() {
        let yaml = "other:\n  dir: \"/wrong\"\ndownload:\n  dir: \"/right\"\n"
        #expect(downloadsDirectory(configYAML: yaml, home: home).path == "/right")
    }

    @Test func pathsHonourEnvOverride() throws {
        let dir = try makeTempDir()
        try "download:\n  dir: \"/tmp/qa-videos\"\n".write(to: dir.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        let paths = DownloaderPaths.resolve(env: ["CHANNELS_DOWNLOADER_SUPPORT_DIR": dir.path], home: home)
        #expect(paths.supportDir.path == dir.path)
        #expect(paths.binary.lastPathComponent == "wx_video_download")
        #expect(paths.caCert.path == dir.appendingPathComponent("certs/ca.pem").path)
        #expect(paths.logFile.lastPathComponent == "app.log")
        #expect(paths.downloadsDir.path == "/tmp/qa-videos")
    }

    @Test func defaultSupportDir() {
        let paths = DownloaderPaths.resolve(env: [:], home: home)
        #expect(paths.supportDir.path == "/Users/tester/Applications/WeChat Channels Downloader")
    }
}

@Suite struct CertificateTests {
    @Test func certCommandsAreExact() {
        let cert = URL(fileURLWithPath: "/s/certs/ca.pem")
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let runner = FakeRunner(fallback: CommandResult(status: 1, output: ""))
        #expect(!isCertificateTrusted(cert, runner: runner))
        #expect(!trustCertificate(cert, runner: runner, home: home))
        #expect(runner.calls == [
            ["/usr/bin/security", "verify-cert", "-c", "/s/certs/ca.pem", "-p", "basic", "-l", "-L", "-q"],
            ["/usr/bin/security", "add-trusted-cert", "-r", "trustRoot", "-k",
             "/Users/tester/Library/Keychains/login.keychain-db", "/s/certs/ca.pem"],
        ])
        let yes = FakeRunner()
        #expect(isCertificateTrusted(cert, runner: yes))
    }
}

@Suite struct PortTests {
    /// Opens a listening socket on an ephemeral 127.0.0.1 port.
    private func listener() throws -> (fd: Int32, port: UInt16) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        try #require(fd >= 0)
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) }
        }
        try #require(bound == 0)
        try #require(listen(fd, 1) == 0)
        _ = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        return (fd, UInt16(bigEndian: addr.sin_port))
    }

    @Test func portListeningDetectsListener() throws {
        let (fd, port) = try listener()
        #expect(isPortListening(port: port))
        close(fd)
        #expect(!isPortListening(port: port))
    }
}
