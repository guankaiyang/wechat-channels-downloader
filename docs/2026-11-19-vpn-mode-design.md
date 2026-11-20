# VPN mode (design)

## Intent
Capture must work while a VPN is connected. With a VPN up, macOS takes proxy
settings from the VPN's own network service, which has none, so WeChat bypasses the downloader.
The user picked "route via the VPN" over the VPN app's split tunnelling (TUN mode ruled out: clashes with VPNs).

## Goals
- On Start with a VPN as the primary connection, the app asks macOS for the user's password once and
  starts a small root "VPN guard" that adds an HTTP/HTTPS proxy (127.0.0.1:2023) to the VPN service
  (State:/Network/Service/<id>/Proxies).
- The guard watches the downloader's pid: when it exits (Stop, Quit, crash) the guard removes only the
  proxy entries it added, then exits. If the VPN reconnects as a new service, the guard adds it again.
- If the VPN comes on after Start, the status bar offers "Enable VPN mode".
- Status strip: VPN on + idle → explains the password prompt; VPN mode on → green; VPN on but not
  routed → amber with "Enable VPN mode"; VPN proxy left pointing at a dead downloader → red with "Fix".

## Anti-goals
- Never overwrite or remove a proxy on the VPN service that the app didn't add.
- Never leave the VPN connection pointing at a stopped downloader without a visible "Fix".
- The root script takes no user-controlled input except a numeric pid; service IDs read from scutil
  must be hex/dash only.

## Constraints
- No Xcode / no signed privileged helper: elevation via `osascript … with administrator privileges`.
- The VPN part can't be tested end to end by Claude (it changes network settings): unit tests run the
  guard script against a fake scutil; the user tests with their VPN on.

## Left to the builder
Poll interval (2 s), exact wording.
