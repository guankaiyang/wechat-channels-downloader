import Foundation

public let downloaderProxyHost = "127.0.0.1"
public let downloaderProxyPort = "2023"

private let networksetupPath = "/usr/sbin/networksetup"

/// True when `networksetup -get(secure)webproxy` output shows an enabled proxy pointing at the downloader.
public func isDownloaderProxy(_ networksetupOutput: String) -> Bool {
    var fields: [String: String] = [:]
    for line in networksetupOutput.components(separatedBy: .newlines) {
        guard let colon = line.firstIndex(of: ":") else { continue }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        fields[key] = value
    }
    return fields["Enabled"] == "Yes"
        && fields["Server"] == downloaderProxyHost
        && fields["Port"] == downloaderProxyPort
}

/// Turns off every web / secure-web proxy that still points at the downloader.
/// Leaves all other proxy settings alone. Returns the services that were changed.
@discardableResult
public func turnOffDownloaderProxies(runner: CommandRunner, services: [String]? = nil) -> [String] {
    var changed: [String] = []
    for service in services ?? networkServices(runner: runner).map(\.name) {
        var touched = false
        for kind in ["web", "secureweb"] {
            let current = runner.run(networksetupPath, ["-get\(kind)proxy", service])
            if current.status == 0, isDownloaderProxy(current.output) {
                _ = runner.run(networksetupPath, ["-set\(kind)proxystate", service, "off"])
                touched = true
            }
        }
        if touched { changed.append(service) }
    }
    return changed
}
