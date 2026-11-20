# VPN Helper (Set Up Once) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Replace the per-Start root guard with a once-installed root launchd helper.
**Architecture:** `VPNHelper.swift` (DownloaderCore) builds the helper, install and uninstall scripts with tool paths injectable for tests; `DownloaderController` reports helper status and installs/removes it via `elevatedCommand`; UI strip + app-menu command.
**Spec:** `docs/2026-11-19-vpn-helper-design.md`

## Global Constraints
- Label `local.wechat-channels-downloader.vpn-helper`; helper marker line `: channels-vpn-helper v1`; poll 2 s; marker key `ChannelsDownloaderGuard`.
- Shipped scripts hard-code /usr/sbin/scutil, /usr/bin/pgrep, /usr/bin/nc, /usr/sbin/chown, /bin/launchctl.

## Review Focus
1. Helper never touches unmarked entries; removes marked ones whenever no downloader is listening.
2. Install writes root-owned, non-user-writable files atomically; plist valid; reinstall/upgrade works.
3. Uninstall leaves no daemon, no files, no marked entries.
4. App never asks for a password on Start once the helper is installed and current.
5. Outdated helper (content differs) is detected and updatable.

### Task 1: Helper + install/uninstall scripts (tests with fakes) — `VPNHelper.swift`, `VPNHelperTests.swift`
### Task 2: Controller (status, install, remove, strip state; drop per-Start guard) — `VPNControllerTests.swift`
### Task 3: UI strip states + "Remove VPN Helper…" menu command; build; install when the downloader is stopped
