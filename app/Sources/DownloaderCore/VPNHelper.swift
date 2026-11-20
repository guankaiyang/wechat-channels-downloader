import Foundation

/// Where the once-installed root helper lives.
public struct VPNHelperLocation: Sendable, Equatable {
    public let label: String
    public let scriptPath: String
    public let plistPath: String

    public init(label: String, scriptPath: String, plistPath: String) {
        self.label = label
        self.scriptPath = scriptPath
        self.plistPath = plistPath
    }

    public static let system = VPNHelperLocation(
        label: "local.wechat-channels-downloader.vpn-helper",
        scriptPath: "/Library/PrivilegedHelperTools/local.wechat-channels-downloader.vpn-helper.sh",
        plistPath: "/Library/LaunchDaemons/local.wechat-channels-downloader.vpn-helper.plist")
}

/// System tools the root scripts call. Fixed at build time; tests swap in fakes.
public struct SystemTools: Sendable, Equatable {
    public let scutil: String
    public let lsof: String
    public let nc: String
    public let stat: String
    public let chown: String
    public let launchctl: String

    public init(scutil: String, lsof: String, nc: String, stat: String, chown: String, launchctl: String) {
        self.scutil = scutil
        self.lsof = lsof
        self.nc = nc
        self.stat = stat
        self.chown = chown
        self.launchctl = launchctl
    }

    public static let real = SystemTools(scutil: "/usr/sbin/scutil", lsof: "/usr/sbin/lsof", nc: "/usr/bin/nc", stat: "/usr/bin/stat",
                                         chown: "/usr/sbin/chown", launchctl: "/bin/launchctl")
}

/// The app's process name, as `lsof +c 0` reports the rule-list server's owner.
public let appProcessName = "ChannelsDownloader"

/// What `pgrep -f` can find for the running helper: launchd starts it as `/bin/sh <scriptPath>`.
public func vpnHelperAlivePattern(_ location: VPNHelperLocation) -> String {
    location.scriptPath
}

/// Shell function `cleanup` (needs `S` and `MK`): removes every service State Proxies entry that carries
/// the marker line, and nothing else.
let markedCleanupShell = #"""
cleanup() {
  for K in $(printf 'list State:/Network/Service/[^/]+/Proxies\n' | "$S" | awk -F' = ' '/subKey/ {print $2}'); do
    case "$K" in State:/Network/Service/*/Proxies) ;; *) continue ;; esac
    ID=${K#State:/Network/Service/}; ID=${ID%/Proxies}
    case "$ID" in ''|*[!0-9A-Fa-f-]*) continue ;; esac
    if printf 'show %s\n' "$K" | "$S" | grep -qx "  $MK : 1"; then
      printf 'remove %s\n' "$K" | "$S"
    fi
  done
}
"""#

/// The root launchd helper. Every `interval` seconds: while the process listening on 127.0.0.1:2023 is
/// named `wx_video_download`, the rule list on 127.0.0.1:2024 is served by this app (`ChannelsDownloader`),
/// both belong to the console (logged-in) user, and a VPN is the primary
/// connection, it adds the app's proxy rule list (only WeChat goes through the downloader; marker included)
/// to that VPN service if the service has no Proxies entry. When no downloader is
/// listening any more, at start, and on TERM/HUP/INT it removes every marked entry.
public func makeVPNHelperScript(tools: SystemTools = .real, interval: String = "2") -> String {
    #"""
: channels-vpn-helper v4
S=\#(tools.scutil)
LS=\#(tools.lsof)
NC=\#(tools.nc)
ST=\#(tools.stat)
T=\#(interval)
MK=\#(vpnEntryMarkerKey)
\#(markedCleanupShell)
show() { printf 'show State:/Network/Service/%s/Proxies\n' "$1" | "$S"; }
apply() {
  printf 'd.init\nd.add %s # 1\nd.add ProxyAutoConfigEnable # 1\nd.add ProxyAutoConfigURLString \#(ruleListURL)\nd.add ExceptionsList * *.local 169.254/16 127.0.0.1 localhost\nset State:/Network/Service/%s/Proxies\n' "$MK" "$1" | "$S"
}
owned() {
  # owned PORT NAME: the 127.0.0.1:PORT listener is the program NAME run by the console user $CU.
  "$LS" -nP +c 0 -iTCP@127.0.0.1:"$1" -sTCP:LISTEN -Fpcu 2>/dev/null | awk -v want="$CU" -v name="$2" '
    /^p/ { c = ""; u = "" }
    /^c/ { c = substr($0, 2) }
    /^u/ { u = substr($0, 2) }
    c == name && u == want { ok = 1 }
    END { exit ok ? 0 : 1 }'
}
active() {
  # Cheap probe first: while nothing listens on 2023 (the usual idle case) skip the costly lsof scan.
  "$NC" -z -G 1 127.0.0.1 2023 >/dev/null 2>&1 || return 1
  "$NC" -z -G 1 127.0.0.1 \#(ruleListPort) >/dev/null 2>&1 || return 1
  CU=$("$ST" -f %u /dev/console 2>/dev/null) || return 1
  case "$CU" in ''|*[!0-9]*) return 1 ;; esac
  # The downloader, and the rule list it points at, must both belong to the logged-in user's own programs.
  owned 2023 wx_video_download && owned \#(ruleListPort) \#(appProcessName)
}
trap 'cleanup; exit 0' TERM HUP INT
active || cleanup
W=0
while :; do
  if active; then
    W=1
    G=$(printf 'show State:/Network/Global/IPv4\n' | "$S")
    I=$(printf '%s\n' "$G" | awk -F' : ' '/PrimaryInterface/ {print $2}')
    U=$(printf '%s\n' "$G" | awk -F' : ' '/PrimaryService/ {print $2}')
    case "$I" in
      utun*|ppp*|ipsec*)
        case "$U" in
          ''|*[!0-9A-Fa-f-]*) ;;
          *) case "$(show "$U")" in *"No such key"*) apply "$U" ;; esac ;;
        esac ;;
    esac
  elif [ "$W" = 1 ]; then
    cleanup
    W=0
  fi
  sleep "$T" &
  wait $!
done
"""#
}

public let vpnHelperScript = makeVPNHelperScript()

/// Root install script. `$1` is the helper script text. Writes the helper (root:wheel 755) and the
/// launchd plist (root:wheel 644) atomically, then (re)loads the daemon.
public func makeHelperInstallScript(location: VPNHelperLocation = .system, tools: SystemTools = .real) -> String {
    #"""
: channels-vpn-helper-install
H=\#(location.scriptPath)
P=\#(location.plistPath)
L=\#(location.label)
CH=\#(tools.chown)
LC=\#(tools.launchctl)
umask 022
mkdir -p "${H%/*}" "${P%/*}" || exit 1
printf '%s\n' "$1" > "$H.tmp" || exit 1
"$CH" root:wheel "$H.tmp" || exit 1
chmod 755 "$H.tmp" || exit 1
mv -f "$H.tmp" "$H" || exit 1
cat > "$P.tmp" <<PLIST || exit 1
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$L</string>
  <key>ProgramArguments</key><array><string>/bin/sh</string><string>$H</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
PLIST
"$CH" root:wheel "$P.tmp" || exit 1
chmod 644 "$P.tmp" || exit 1
mv -f "$P.tmp" "$P" || exit 1
"$LC" bootout "system/$L" >/dev/null 2>&1
"$LC" bootstrap system "$P" 2>/dev/null || { sleep 1; "$LC" bootstrap system "$P"; }
"""#
}

/// Root uninstall script: unloads the daemon, deletes its files and removes any marked entries.
public func makeHelperUninstallScript(location: VPNHelperLocation = .system, tools: SystemTools = .real) -> String {
    #"""
: channels-vpn-helper-uninstall
H=\#(location.scriptPath)
P=\#(location.plistPath)
L=\#(location.label)
LC=\#(tools.launchctl)
S=\#(tools.scutil)
MK=\#(vpnEntryMarkerKey)
\#(markedCleanupShell)
"$LC" bootout "system/$L" >/dev/null 2>&1
rm -f "$P" "$H"
cleanup
exit 0
"""#
}

public enum VPNHelperStatus: Equatable, Sendable {
    case notInstalled
    case outdated
    case installed
}

/// Compares the installed helper file (as the installer writes it: script + newline) with this build's.
public func vpnHelperStatus(installedScript: String?, expected: String = vpnHelperScript) -> VPNHelperStatus {
    guard let installedScript else { return .notInstalled }
    return installedScript == expected + "\n" ? .installed : .outdated
}
