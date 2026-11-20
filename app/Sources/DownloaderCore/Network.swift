import Foundation

/// Extracts `PrimaryInterface` from `scutil` output for `State:/Network/Global/IPv4`.
public func primaryInterface(scutilOutput: String) -> String? {
    for line in scutilOutput.components(separatedBy: .newlines) {
        let parts = line.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              parts[0].trimmingCharacters(in: .whitespaces) == "PrimaryInterface" else { continue }
        let name = parts[1].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }
    return nil
}

/// VPN tunnels show up as utun/ppp/ipsec interfaces.
public func isVPNInterface(_ name: String) -> Bool {
    ["utun", "ppp", "ipsec"].contains { name.hasPrefix($0) }
}

public func currentPrimaryInterface(runner: CommandRunner) -> String? {
    let result = runner.run("/usr/sbin/scutil", [], input: "show State:/Network/Global/IPv4\n")
    guard result.status == 0 else { return nil }
    return primaryInterface(scutilOutput: result.output)
}

/// True when something accepts TCP connections on `host:port` (used to tell whether a downloader owns 2023).
public func isPortListening(host: String = "127.0.0.1", port: UInt16) -> Bool {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_addr.s_addr = inet_addr(host)
    addr.sin_port = port.bigEndian
    let result = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    return result == 0
}
