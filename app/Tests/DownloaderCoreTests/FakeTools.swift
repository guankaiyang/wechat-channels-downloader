import Foundation
@testable import DownloaderCore

/// Stand-ins for scutil, pgrep, nc, chown and launchctl that keep their state as files in a temp folder,
/// so the real helper/install/cleanup scripts can run without touching the Mac.
private let fakeScutil = ##"""
#!/bin/bash
D="$FAKE_DIR"
input=$(cat)
printf '%s\n' "$input" >> "$D/log"
pending=""
while IFS= read -r line; do
  case "$line" in
    "d.init") pending="" ;;
    d.add\ *)
      rest=${line#d.add }; k=${rest%% *}; v=${rest#* }; v=${v#\# }
      pending="$pending  $k : $v"$'\n' ;;
    "show State:/Network/Global/IPv4") cat "$D/global" 2>/dev/null ;;
    "list State:/Network/Service/[^/]+/Proxies")
      i=0; for f in "$D"/proxies-*; do [ -e "$f" ] || continue
        id=${f##*/proxies-}; echo "  subKey [$i] = State:/Network/Service/$id/Proxies"; i=$((i+1)); done ;;
    show\ State:/Network/Service/*/Proxies)
      id=${line#show State:/Network/Service/}; id=${id%/Proxies}
      if [ -f "$D/proxies-$id" ]; then cat "$D/proxies-$id"; else echo "  No such key"; fi ;;
    set\ State:/Network/Service/*/Proxies)
      id=${line#set State:/Network/Service/}; id=${id%/Proxies}
      printf '<dictionary> {\n%s}\n' "$pending" > "$D/proxies-$id"
      echo "SET $id" >> "$D/events" ;;
    remove\ State:/Network/Service/*/Proxies)
      id=${line#remove State:/Network/Service/}; id=${id%/Proxies}
      rm -f "$D/proxies-$id"; echo "REMOVE $id" >> "$D/events" ;;
  esac
done <<< "$input"
"""##

/// lsof: prints the `-F` listing stored for the port in its `-iTCP@host:port` argument, and records its arguments.
private let fakeLsof = ##"""
#!/bin/bash
echo "lsof $*" >> "$FAKE_DIR/log"
port=""; for a in "$@"; do case "$a" in -iTCP@*) port=${a##*:} ;; esac; done
[ -f "$FAKE_DIR/listener-$port" ] || exit 1
cat "$FAKE_DIR/listener-$port"
"""##
/// nc -z host port: succeeds when something "listens" on that port; records each probe.
private let fakeNc = ##"""
#!/bin/bash
echo "nc $*" >> "$FAKE_DIR/log"
for a in "$@"; do port=$a; done
[ -f "$FAKE_DIR/listener-$port" ]
"""##
/// stat -f %u /dev/console: the console user's uid (default 501).
private let fakeStat = "#!/bin/bash\ncat \"$FAKE_DIR/console_uid\" 2>/dev/null || echo 501\n"
private let fakeRecorder = "#!/bin/bash\necho \"$(basename \"$0\") $*\" >> \"$FAKE_DIR/events\"\n"

struct FakeSystem {
    static let marked = "<dictionary> {\n  ChannelsDownloaderGuard : 1\n  HTTPSPort : 2023\n  HTTPSProxy : 127.0.0.1\n}\n"

    let dir: URL
    let tools: SystemTools
    let location: VPNHelperLocation

    init() throws {
        let base = try makeTempDir()
        func tool(_ name: String, _ body: String) throws -> String {
            let url = base.appendingPathComponent("bin/\(name)")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try body.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return url.path
        }
        tools = SystemTools(scutil: try tool("scutil", fakeScutil), lsof: try tool("lsof", fakeLsof), nc: try tool("nc", fakeNc),
                            stat: try tool("stat", fakeStat), chown: try tool("chown", fakeRecorder),
                            launchctl: try tool("launchctl", fakeRecorder))
        location = VPNHelperLocation(label: "test.vpn-helper",
                                     scriptPath: base.appendingPathComponent("PrivilegedHelperTools/helper.sh").path,
                                     plistPath: base.appendingPathComponent("LaunchDaemons/helper.plist").path)
        dir = base
        FileManager.default.createFile(atPath: base.appendingPathComponent("events").path, contents: nil)
    }

    func setPrimary(interface: String, service: String) throws {
        try "  PrimaryInterface : \(interface)\n  PrimaryService : \(service)\n"
            .write(to: dir.appendingPathComponent("global"), atomically: true, encoding: .utf8)
    }

    /// Something listening on 127.0.0.1:2023, as `lsof -F` would describe it. By default the app is open
    /// too, serving the rule list on 2024 as the console user.
    func setListener(name: String = "wx_video_download", uid: Int = 501, appServing: Bool = true) throws {
        try setPortListener(2023, name: name, uid: uid)
        if appServing { try setPortListener(2024, name: appProcessName, uid: 501) } else { clearPortListener(2024) }
    }

    func setPortListener(_ port: Int, name: String, uid: Int) throws {
        try "p\(4242 + port)\nc\(name)\nu\(uid)\nf7\n".write(to: dir.appendingPathComponent("listener-\(port)"),
                                                       atomically: true, encoding: .utf8)
    }

    func clearPortListener(_ port: Int) { try? FileManager.default.removeItem(at: dir.appendingPathComponent("listener-\(port)")) }

    func clearListener() { clearPortListener(2023); clearPortListener(2024) }

    func setFlag(_ name: String, _ on: Bool) {
        let path = dir.appendingPathComponent(name).path
        if on { FileManager.default.createFile(atPath: path, contents: nil) } else { try? FileManager.default.removeItem(atPath: path) }
    }

    func setProxies(_ service: String, _ body: String) throws {
        try body.write(to: dir.appendingPathComponent("proxies-\(service)"), atomically: true, encoding: .utf8)
    }

    func hasProxies(_ service: String) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent("proxies-\(service)").path)
    }

    var events: String { (try? String(contentsOf: dir.appendingPathComponent("events"), encoding: .utf8)) ?? "" }
    var log: String { (try? String(contentsOf: dir.appendingPathComponent("log"), encoding: .utf8)) ?? "" }

    /// Runs a script the way the elevated command does (`sh -c script name args…`), with only the fake folder in env.
    func run(_ script: String, args: [String] = []) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "channels-downloader-helper"] + args
        process.environment = ["FAKE_DIR": dir.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    func diagnostics(_ process: Process) -> String {
        "running=\(process.isRunning) log=[\(log)] events=[\(events)]"
    }
}

/// Polls `condition` for up to `seconds` (generous: busy parallel runs were slow before).
func eventually(_ seconds: Double = 10, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return condition()
}
