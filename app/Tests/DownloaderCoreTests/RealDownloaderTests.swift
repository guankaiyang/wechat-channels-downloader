import Foundation
import Testing
@testable import DownloaderCore

/// Runs the real wx_video_download from a QA support folder whose config.yaml has
/// `proxy.system: false` (so the Mac's proxy is never touched) and ports 2032/2033.
/// Opt-in: set QA_SUPPORT_DIR. System commands still go to a FakeRunner.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["QA_SUPPORT_DIR"] != nil))
struct RealDownloaderTests {
    @Test func realBinaryStartsListensAndStops() async throws {
        let dir = try #require(ProcessInfo.processInfo.environment["QA_SUPPORT_DIR"])
        let paths = DownloaderPaths.resolve(env: [DownloaderPaths.supportDirEnvKey: dir])
        let runner = FakeRunner()
        let controller = DownloaderController(paths: paths, runner: runner, proxyListening: { false }, ruleList: FakeRuleList())
        await controller.start()
        guard case .running(let pid, external: false) = controller.state else {
            Issue.record("expected running, got \(controller.state)"); return
        }
        // The binary opens its port a moment before it logs that it started, so wait for both.
        var listening = false, logged = false, log = ""
        for _ in 0..<100 where !(listening && logged) {
            listening = isPortListening(port: 2033)
            log = (try? String(contentsOf: paths.logFile, encoding: .utf8)) ?? ""
            logged = log.contains("System proxy is not set")
            if !(listening && logged) { try await Task.sleep(for: .milliseconds(100)) }
        }
        #expect(listening)
        #expect(log.contains("Proxy service started successfully"))
        #expect(log.contains("System proxy is not set"))
        await controller.stop()
        #expect(controller.state == .stopped)
        #expect(kill(pid, 0) != 0)
        #expect(!isPortListening(port: 2033))
        let after = (try? String(contentsOf: paths.logFile, encoding: .utf8)) ?? ""
        #expect(after.contains("Downloader has been shut down"))
    }
}
