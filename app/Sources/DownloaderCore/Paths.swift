import Foundation

/// Where the installed downloader and its files live.
public struct DownloaderPaths: Equatable, Sendable {
    public let supportDir: URL
    public let binary: URL
    public let config: URL
    /// The copy of config.yaml the app runs the downloader with (system proxy off; see appConfigYAML).
    public let appConfig: URL
    public let caCert: URL
    public let downloadsDir: URL
    public let logFile: URL

    public static let supportDirEnvKey = "CHANNELS_DOWNLOADER_SUPPORT_DIR"

    public static func resolve(env: [String: String] = ProcessInfo.processInfo.environment,
                               home: URL = FileManager.default.homeDirectoryForCurrentUser) -> DownloaderPaths {
        let support: URL
        if let override = env[supportDirEnvKey], !override.isEmpty {
            support = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            support = home.appendingPathComponent("Applications/WeChat Channels Downloader", isDirectory: true)
        }
        let config = support.appendingPathComponent("config.yaml")
        let yaml = (try? String(contentsOf: config, encoding: .utf8)) ?? ""
        return DownloaderPaths(
            supportDir: support,
            binary: support.appendingPathComponent("wx_video_download"),
            config: config,
            appConfig: support.appendingPathComponent("app-config.yaml"),
            caCert: support.appendingPathComponent("certs/ca.pem"),
            downloadsDir: downloadsDirectory(configYAML: yaml, home: home),
            logFile: support.appendingPathComponent("app.log")
        )
    }
}

/// Reads `download.dir` from the downloader's config.yaml.
public func downloadsDirectory(configYAML: String, home: URL) -> URL {
    let fallback = home.appendingPathComponent("Downloads/WeChat Channels", isDirectory: true)
    var inDownload = false
    for line in configYAML.components(separatedBy: .newlines) {
        if !line.hasPrefix(" ") && !line.hasPrefix("\t") && !line.isEmpty {
            inDownload = line.trimmingCharacters(in: .whitespaces) == "download:"
            continue
        }
        // Only direct children of `download:` (two-space indent).
        guard inDownload, line.hasPrefix("  dir:") else { continue }
        var value = String(line.dropFirst("  dir:".count)).trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        guard !value.isEmpty else { return fallback }
        value = value.replacingOccurrences(of: "%UserDownloads%",
                                           with: home.appendingPathComponent("Downloads").path)
        return URL(fileURLWithPath: value, isDirectory: true)
    }
    return fallback
}
