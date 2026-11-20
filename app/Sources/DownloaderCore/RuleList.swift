import Foundation

/// The proxy rule list (a PAC file): only WeChat's addresses go through the downloader, everything else
/// connects directly. Other apps never depend on the downloader, so stopping it can't cut them off.

public let ruleListPort: UInt16 = 2024
public let ruleListURL = "http://127.0.0.1:\(ruleListPort)/proxy.pac"

/// Domains (and their subdomains) that WeChat Channels loads from.
public let weChatDomains = ["qq.com", "qpic.cn", "wechat.com"]

/// The rule list. While the downloader is down it sends everything direct, so a leftover setting is harmless.
/// "; DIRECT" lets apps fall back to a direct connection if the downloader stops mid-way.
public func ruleListScript(downloaderUp: Bool) -> String {
    guard downloaderUp else {
        return "function FindProxyForURL(url, host) {\n  return \"DIRECT\";\n}\n"
    }
    let tests = weChatDomains
        .map { "host == \"\($0)\" || dnsDomainIs(host, \".\($0)\")" }
        .joined(separator: " ||\n      ")
    return """
    function FindProxyForURL(url, host) {
      host = host.toLowerCase();
      if (\(tests))
        return "PROXY \(downloaderProxyHost):\(downloaderProxyPort); DIRECT";
      return "DIRECT";
    }

    """
}

private let networksetupPath = "/usr/sbin/networksetup"

/// Network services as `networksetup -listallnetworkservices` lists them; disabled ones start with "*".
func networkServices(runner: CommandRunner) -> [(name: String, enabled: Bool)] {
    let listing = runner.run(networksetupPath, ["-listallnetworkservices"])
    guard listing.status == 0 else { return [] }
    return listing.output
        .components(separatedBy: .newlines)
        .dropFirst() // "An asterisk (*) denotes…"
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        .map { $0.hasPrefix("*") ? (String($0.dropFirst()), false) : ($0, true) }
}

/// Parses `networksetup -getautoproxyurl <service>` ("URL: …" / "Enabled: Yes|No").
func autoProxySetting(_ output: String) -> (url: String, enabled: Bool) {
    var url = "", enabled = false
    for line in output.components(separatedBy: .newlines) {
        if line.hasPrefix("URL:") { url = line.dropFirst(4).trimmingCharacters(in: .whitespaces) }
        if line.hasPrefix("Enabled:") { enabled = line.dropFirst(8).trimmingCharacters(in: .whitespaces) == "Yes" }
    }
    return (url, enabled)
}

/// Points every enabled network service at our rule list. A service that already uses someone else's
/// rule list (e.g. a work one) is left alone. Returns the services that were changed.
@discardableResult
public func turnOnRuleList(runner: CommandRunner) -> [String] {
    var changed: [String] = []
    for service in networkServices(runner: runner) where service.enabled {
        let current = runner.run(networksetupPath, ["-getautoproxyurl", service.name])
        guard current.status == 0 else { continue }
        let setting = autoProxySetting(current.output)
        if setting.enabled && setting.url != ruleListURL { continue }
        _ = runner.run(networksetupPath, ["-setautoproxyurl", service.name, ruleListURL])
        _ = runner.run(networksetupPath, ["-setautoproxystate", service.name, "on"])
        changed.append(service.name)
    }
    return changed
}

/// Switches off our rule list wherever it is on; other rule lists are left alone.
@discardableResult
public func turnOffRuleList(runner: CommandRunner, services: [String]? = nil) -> [String] {
    var changed: [String] = []
    for service in services ?? networkServices(runner: runner).map(\.name) {
        let current = runner.run(networksetupPath, ["-getautoproxyurl", service])
        guard current.status == 0 else { continue }
        let setting = autoProxySetting(current.output)
        guard setting.enabled, setting.url == ruleListURL else { continue }
        _ = runner.run(networksetupPath, ["-setautoproxystate", service, "off"])
        changed.append(service)
    }
    return changed
}

/// Switches off everything that sends traffic to the downloader: our rule list and (older setups or a
/// Terminal-started downloader) web / secure-web proxies at 127.0.0.1:2023. Lists the services once.
@discardableResult
public func turnOffDownloaderSettings(runner: CommandRunner) -> [String] {
    let services = networkServices(runner: runner).map(\.name)
    guard !services.isEmpty else { return [] }
    let changed = turnOffRuleList(runner: runner, services: services)
        + turnOffDownloaderProxies(runner: runner, services: services)
    return services.filter(changed.contains)
}

/// The config the app runs the downloader with: the user's config.yaml with `proxy.system` set to false,
/// so the downloader doesn't switch on an all-traffic proxy itself (the app sets the rule list instead).
/// Keeps the file's line endings; ignores comments when looking for the keys.
public func appConfigYAML(from yaml: String) -> String {
    let newline = yaml.contains("\r\n") ? "\r\n" : "\n"
    var lines = yaml.components(separatedBy: newline)
    /// The line without a trailing `# comment`, trimmed (good enough for this config's plain keys).
    func content(_ line: String) -> String {
        let code = line.range(of: " #").map { String(line[..<$0.lowerBound]) } ?? line
        return code.trimmingCharacters(in: .whitespaces)
    }
    func isComment(_ line: String) -> Bool { line.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
    func isTopLevelKey(_ line: String) -> Bool {
        !line.isEmpty && !line.hasPrefix(" ") && !line.hasPrefix("\t") && !isComment(line)
    }
    guard let section = lines.firstIndex(where: { isTopLevelKey($0) && content($0) == "proxy:" }) else {
        let base = yaml.isEmpty || yaml.hasSuffix(newline) ? yaml : yaml + newline
        return base + "proxy:" + newline + "  system: false" + newline
    }
    var index = section + 1
    while index < lines.count {
        let line = lines[index]
        if isTopLevelKey(line) { break } // next top-level key
        if !isComment(line), line.hasPrefix("  system:") {
            lines[index] = "  system: false"
            return lines.joined(separator: newline)
        }
        index += 1
    }
    lines.insert("  system: false", at: section + 1)
    return lines.joined(separator: newline)
}
