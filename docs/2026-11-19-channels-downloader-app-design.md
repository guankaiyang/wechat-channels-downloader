# WeChat Channels Downloader — Mac app (design)

Approved in conversation on 2026-11-19.

## Intent
The user wants to save WeChat Channels videos without ever running a Terminal command. Today they must
press Run on `Start Downloader.command` and Ctrl+C to stop. They also want to see their downloaded videos
in one place, "like a file storage thing".

## Goals
- A normal Mac app (`WeChat Channels Downloader.app` in `~/Applications`, can be kept in the Dock).
- Start / Stop the downloader with a button; no Terminal window.
- Live status, including a warning when a VPN is the active connection (capture can't work then).
- A library of downloaded videos: thumbnail, title, length, size, date; newest first; grid/list toggle;
  search by title; new downloads appear automatically when finished.
- Double-click plays in QuickTime Player. Right-click: Show in Finder, Rename, Move to Trash.
- "Open in Finder" for the folder; "Download progress" opens the downloader's own page (127.0.0.1:2022).

## Non-goals
- Replacing the downloader itself or its in-WeChat download button.
- Showing in-progress downloads inside the app (the downloader's page does that).
- Sharing/sending videos.

## Anti-goals (failure even if it "works")
- Leaving the Mac's web proxy pointing at 127.0.0.1:2023 after Stop, Quit, or a crash (kills browsing).
- Ever installing or trusting the shared SunnyNet certificate.
- Permanently deleting videos (Move to Trash only).

## Constraints
- Downloader: `~/Applications/WeChat Channels Downloader/wx_video_download` (v261106), its `config.yaml`
  (own CA, `skipInstallRootCert: true`, downloads to `~/Downloads/WeChat Channels`).
- Build with Apple Command Line Tools only (`swiftc` 6.4, macOS 27 SDK); no Xcode project.
- The downloader may already be running from Terminal when the app opens.

## Approaches considered
1. **Native SwiftUI app compiled with swiftc** — real Mac window, live status, thumbnails via QuickLook. **Picked.**
2. AppleScript app (osacompile) — only pop-up dialogs, no live status or library.
3. Python/Tk app — dated look, depends on the user's Python install.

## Decided
- Status bar on top (state dot + text + Start/Stop), library below.
- Start: if the CA isn't trusted, run `security add-trusted-cert` (macOS password dialog), then launch the
  downloader in its folder with stdin from /dev/null and output to a log file.
- Stop / Quit: SIGINT the downloader (it restores the proxy), wait, escalate if needed, then turn off any
  web/secure-web proxy still set to 127.0.0.1:2023 on every network service (same rule as `Fix Internet.command`).
- Detect an already-running downloader (by process) and let Stop end it.
- VPN warning when the primary interface is a tunnel (utun/ppp/ipsec).

## Left to the builder
- Exact polling intervals, layout spacing, icon art, how partial (still-downloading) files are hidden.
