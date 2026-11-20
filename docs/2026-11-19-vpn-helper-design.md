# VPN helper, set up once (design)

## Intent
VPN mode asked for the admin password on every Start. The user chose "Set up once": one password
installs a small root helper; afterwards Start never asks.

## Goals
- "Set up VPN mode" (shown in the VPN strip) installs, after one macOS password prompt:
  `/Library/PrivilegedHelperTools/local.wechat-channels-downloader.vpn-helper.sh` (root:wheel 755) and
  `/Library/LaunchDaemons/local.wechat-channels-downloader.vpn-helper.plist` (root:wheel 644, RunAtLoad, KeepAlive).
- The helper loops every 2 s. While the 127.0.0.1:2023 listener is `wx_video_download` owned by the console user AND a VPN (utun/ppp/ipsec) is primary, it adds the downloader proxy (with the
  `ChannelsDownloaderGuard : 1` marker) to that VPN service if it has no Proxies entry. When the
  downloader stops, at helper start (if no downloader), and on TERM/HUP/INT it removes every marked entry.
- The app shows: not set up → "Set up VPN mode"; outdated helper → "Update helper"; set up + idle →
  "VPN mode is set up"; capturing + routed → green; otherwise starting / blocked as before; leftover → red "Fix".
- App menu: "Remove VPN Helper…" (one password) unloads and deletes both files and removes marked entries.
- The per-Start guard and its password prompt go away.

## Anti-goals
- Helper reads no input from the app or environment (launchd runs it; paths are hard-coded).
- Never overwrite or remove a Proxies entry without the marker.
- Never leave a marked entry once no downloader is listening.

## Constraints / trade-offs
- A root daemon stays installed until removed. The trigger (after review): the process listening on
  127.0.0.1:2023 must itself be named `wx_video_download` and belong to the console (logged-in) user. Code
  running as that user could still impersonate it; while it does, the VPN connection (for every user on the
  Mac) sends proxy-aware traffic to it: it sees CONNECT host names and plain HTTP, but can't read HTTPS
  without the downloader's CA key (0600 in the user's home).
- Install/uninstall can't be exercised end to end by Claude (needs admin, changes the system): scripts are
  tested against fakes (scutil, pgrep, nc, chown, launchctl) in temp folders; the user runs the real setup.
