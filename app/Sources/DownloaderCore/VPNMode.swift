import Foundation

/// VPN mode: while a VPN is the Mac's primary connection, macOS takes proxy settings from the VPN's
/// own service (which has none), so WeChat would bypass the downloader. A small root "guard" adds the
/// downloader proxy to that service and removes it again when the downloader exits.

/// Key the helper adds to every Proxies entry it writes, so "ours" is exact.
public let vpnEntryMarkerKey = "ChannelsDownloaderGuard"

/// Root cleanup script ("Fix"): removes every service State Proxies entry carrying the marker key
/// and leaves everything else alone.
public func makeVPNCleanupScript(scutil: String = "/usr/sbin/scutil") -> String {
    """
    : channels-vpn-cleanup
    S=\(scutil)
    MK=\(vpnEntryMarkerKey)
    \(markedCleanupShell)
    cleanup
    exit 0
    """
}

public let vpnCleanupScript = makeVPNCleanupScript()

/// `osascript` arguments that run `script` as root after macOS asks for the password.
/// The prompt, the script and its arguments travel as argv items, never inside AppleScript source,
/// and the root shell starts with an empty environment (`env -i`) so nothing is inherited.
public func elevatedCommand(script: String, args: [String], prompt: String, background: Bool) -> [String] {
    var source = [
        "on run argv",
        "set cmd to \"/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/sh -c \" & quoted form of (item 2 of argv) & \" channels-downloader-helper\"",
        "repeat with i from 3 to (count of argv)",
        "set cmd to cmd & \" \" & quoted form of (item i of argv)",
        "end repeat",
    ]
    if background { source.append("set cmd to cmd & \" >/dev/null 2>&1 &\"") }
    source.append("do shell script cmd with prompt (item 1 of argv) with administrator privileges")
    source.append("end run")
    return source.flatMap { ["-e", $0] } + [prompt, script] + args
}

/// True when `scutil --proxy` shows the Mac's effective proxy is the downloader: our rule list, or
/// (older setups) an HTTPS proxy at 127.0.0.1:2023.
/// Reads only the top-level keys (two-space indent), not nested per-interface dictionaries.
public func isDownloaderEffectiveProxy(scutilProxyOutput: String) -> Bool {
    var fields: [String: String] = [:]
    for line in scutilProxyOutput.components(separatedBy: .newlines) {
        guard line.hasPrefix("  "), !line.hasPrefix("   ") else { continue }
        let parts = line.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { continue }
        fields[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
    }
    if fields["ProxyAutoConfigEnable"] == "1" && fields["ProxyAutoConfigURLString"] == ruleListURL { return true }
    return fields["HTTPSEnable"] == "1"
        && fields["HTTPSProxy"] == downloaderProxyHost
        && fields["HTTPSPort"] == downloaderProxyPort
}

/// What the VPN strip under the top bar should say.
public enum VPNStripState: Equatable, Sendable {
    case none
    /// The VPN connection still points at a downloader that isn't running.
    case leftover
    /// VPN on but the helper isn't installed (or isn't running): offer "Set up VPN mode".
    case needsSetup
    /// The installed helper is from an older build: offer "Update helper".
    case needsUpdate
    /// Helper installed (current) but its daemon isn't running.
    case helperNotRunning
    /// VPN on, helper ready, downloader idle.
    case ready
    /// Downloader just started; routing not visible yet.
    case starting
    /// WeChat really goes through the downloader.
    case on
    /// Helper running but traffic isn't routed (e.g. the VPN sets its own proxy).
    case blockedByVPNProxy
}

public func vpnStripState(vpnActive: Bool, isRunning: Bool, helper: VPNHelperStatus, helperRunning: Bool,
                          routed: Bool, leftover: Bool, secondsSinceStart: Double?) -> VPNStripState {
    if leftover { return .leftover }
    guard vpnActive else { return .none }
    switch helper {
    case .notInstalled: return .needsSetup
    case .outdated: return .needsUpdate
    case .installed: break
    }
    guard helperRunning else { return .helperNotRunning }
    guard isRunning else { return .ready }
    if routed { return .on }
    if let age = secondsSinceStart, age < 10 { return .starting }
    return .blockedByVPNProxy
}

/// A short message for a failed admin action, or nil when it worked or the user cancelled the password prompt.
public func elevatedFailureMessage(_ result: CommandResult, action: String) -> String? {
    guard result.status != 0, !result.output.contains("(-128)") else { return nil }
    let detail = result.output
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: #"^\d+:\d+: execution error: "#, with: "", options: .regularExpression)
    return detail.isEmpty ? "Couldn't \(action)." : "Couldn't \(action): \(detail)"
}
