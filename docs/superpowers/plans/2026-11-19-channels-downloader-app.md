# WeChat Channels Downloader App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A SwiftUI Mac app that starts/stops the installed `wx_video_download` without Terminal and shows downloaded videos as a browsable library.

**Architecture:** SwiftPM package in `app/` with a testable core library (`DownloaderCore`: paths, proxy cleanup, VPN detection, process control, video scanning) and a thin SwiftUI executable (`ChannelsDownloader`). A build script wraps the release binary into `~/Applications/WeChat Channels Downloader.app`, ad-hoc signed.

**Tech Stack:** Swift 6.4 (Command Line Tools, no Xcode), SwiftUI, AppKit, QuickLookThumbnailing, AVFoundation, Swift Testing.

**Spec:** `docs/2026-11-19-channels-downloader-app-design.md`

## Global Constraints

- Platform floor: macOS 14 (`.macOS(.v14)`); built on the macOS 27 SDK.
- Downloader support folder: `~/Applications/WeChat Channels Downloader/` (binary `wx_video_download`, `config.yaml`, `certs/ca.pem`). Override with env `CHANNELS_DOWNLOADER_SUPPORT_DIR` (tests/manual QA only).
- Downloader proxy address: `127.0.0.1:2023`. Only proxies with exactly this server and port are ever turned off.
- Never install/trust SunnyNet; only `certs/ca.pem` is ever trusted, into `~/Library/Keychains/login.keychain-db`.
- Video extensions shown: `mp4`, `mov`, `m4v` (case-insensitive). Delete = Move to Trash only.
- Bundle id `local.wechat-channels-downloader`; app name "WeChat Channels Downloader".
- No git in this workspace: skip commit steps.
- QA must not change system settings: manual runs use a support dir copy whose `config.yaml` has `proxy.system: false`, `api.port: 2032`, `proxy.port: 2033`.

## Review Focus

1. App crashes or is force-quit while running → proxy left at 127.0.0.1:2023. Next app launch with no downloader process must turn it off (Task 3 test `refreshCleansLeftoverProxy`).
2. Downloader already started from Terminal → app shows Running and Stop ends it (Task 3 test `detectsExternalProcess`).
3. Downloads folder missing on first run → empty library, no crash (Task 2 test `scanMissingDirReturnsEmpty`).
4. File still being finalized/decrypted when first seen → thumbnail/duration must refresh when size or mtime changes (Task 2 test `cacheKeyChangesWithSizeOrDate`).
5. Rename to an existing name, empty name, or name with "/" → refused with a message, nothing overwritten, extension kept (Task 2 tests `renameRejects…`).

---

### Task 1: Package skeleton, system helpers (paths, command runner, proxy, VPN, certificate)

**Files:**
- Create: `app/Package.swift` (targets `DownloaderCore`, executable `ChannelsDownloader` depends on core, test target `DownloaderCoreTests`)
- Create: `app/Sources/DownloaderCore/CommandRunner.swift`, `Paths.swift`, `Proxy.swift`, `Network.swift`, `Certificate.swift`
- Create: `app/Sources/ChannelsDownloader/main.swift` (placeholder `print`, replaced in Task 4)
- Test: `app/Tests/DownloaderCoreTests/SystemHelpersTests.swift` (with a `FakeRunner` that records calls and returns canned outputs keyed by `[path] + args`)

**Interfaces (Produces):**
- `public protocol CommandRunner: Sendable { func run(_ path: String, _ args: [String]) -> CommandResult }`, `public struct CommandResult { public let status: Int32; public let output: String }`, `public struct ProcessRunner: CommandRunner`
- `public struct DownloaderPaths: Sendable { supportDir, binary, config, caCert, downloadsDir: URL; logFile: URL /* supportDir/app.log */ ; public static func resolve(env: [String:String] = ProcessInfo.processInfo.environment, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> DownloaderPaths }`
- `public func downloadsDirectory(configYAML: String, home: URL) -> URL` — reads the `dir:` line under `download:`; replaces `%UserDownloads%` with `home/Downloads`; default `home/Downloads/WeChat Channels`.
- `public func isDownloaderProxy(_ networksetupOutput: String) -> Bool`
- `public func turnOffDownloaderProxies(runner: CommandRunner) -> [String]` — returns services changed; lists `/usr/sbin/networksetup -listallnetworkservices` (skip header line, strip leading `*`), checks `-getwebproxy` and `-getsecurewebproxy`, sets matching ones `-set…proxystate <svc> off`.
- `public func primaryInterface(scutilOutput: String) -> String?`, `public func isVPNInterface(_ name: String) -> Bool` (prefixes `utun`, `ppp`, `ipsec`), `public func currentPrimaryInterface(runner:) -> String?` (feeds `show State:/Network/Global/IPv4` to `/usr/sbin/scutil`).
- `public func isCertificateTrusted(_ cert: URL, runner:) -> Bool` → `/usr/bin/security verify-cert -c <cert> -p basic -l -L -q` status 0; `public func trustCertificate(_ cert: URL, runner:, home: URL) -> Bool` → `/usr/bin/security add-trusted-cert -r trustRoot -k <home>/Library/Keychains/login.keychain-db <cert>`.

- [ ] **Step 1: Write failing tests** — `proxyMatchesOnlyOurs` (Yes/127.0.0.1/2023 → true; `Enabled: No` → false; `Server: 127.0.0.1` + `Port: 9090` → false; `Server: proxy.school` + `Port: 2023` → false); `turnsOffOnlyMatchingServices` (services `Wi-Fi`, `*USB 10/100/1000 LAN`, `Thunderbolt Bridge`; only Wi-Fi web+secure match → exactly two set calls, both `Wi-Fi … off`; returns `["Wi-Fi"]`); `parsesPrimaryInterface` (sample with `PrimaryInterface : utun8` → `"utun8"`; empty → nil); `vpnPrefixes` (utun8/ppp0/ipsec0 true, en0/bridge0 false); `downloadsDirFromConfig` (`  dir: "%UserDownloads%/WeChat Channels"` → `<home>/Downloads/WeChat Channels`; absolute `/tmp/x` → `/tmp/x`; no dir line → default); `pathsHonourEnvOverride`; `certCommandsAreExact` (FakeRunner records exact argument arrays above).
- [ ] **Step 2: Run** `cd app && swift test` — Expected: FAIL (symbols missing).
- [ ] **Step 3: Implement** the files above with the signatures given.
- [ ] **Step 4: Run** `swift test` — Expected: all SystemHelpers tests PASS.

### Task 2: Video library core (scan, titles, search, formatting, rename, thumbnail key)

**Files:**
- Create: `app/Sources/DownloaderCore/VideoLibrary.swift`
- Test: `app/Tests/DownloaderCoreTests/VideoLibraryTests.swift` (uses a temp dir per test)

**Interfaces (Produces):**
- `public struct VideoItem: Identifiable, Hashable, Sendable { public var id: URL { url }; url: URL; title: String; sizeBytes: Int64; modified: Date }`
- `public func scanVideos(in dir: URL, fileManager: FileManager = .default) -> [VideoItem]` — non-hidden regular files with allowed extensions, newest `modified` first; missing dir → `[]`.
- `public func displayTitle(for url: URL) -> String` — filename without extension.
- `public func matches(_ item: VideoItem, query: String) -> Bool` — trimmed, case/diacritic-insensitive `contains`; empty query → true.
- `public func formatDuration(_ seconds: Double) -> String` — `m:ss` under an hour, `h:mm:ss` otherwise.
- `public func formatSize(_ bytes: Int64) -> String` — `ByteCountFormatter`, `.file` style.
- `public enum RenameError: Error, Equatable { case empty, invalidCharacters, alreadyExists }`
- `public func renameVideo(_ item: VideoItem, to newTitle: String, fileManager: FileManager = .default) throws -> URL` — keeps the original extension; rejects `/` and `:`; never overwrites.
- `public struct ThumbnailKey: Hashable, Sendable { url: URL; sizeBytes: Int64; modified: Date; init(_ item: VideoItem) }`

- [ ] **Step 1: Write failing tests** — `scanFiltersAndSorts` (create `old.mp4` mtime −60s, `new.MOV` now, `clip.mp4.part`, `seg.tmp`, `.hidden.mp4`, `notes.txt`, subfolder `sub/x.mp4` → titles `["new", "old"]`); `scanMissingDirReturnsEmpty`; `searchIsCaseInsensitiveAndHandlesChinese` (title `春节 Vlog`: `"vlog"` and `"春节"` match, `"xyz"` doesn't, `""` matches); `durationFormatting` (5→`0:05`, 92→`1:32`, 3723→`1:02:03`); `renameKeepsExtension` (`a.mp4` → "b" → `b.mp4` exists, `a.mp4` gone); `renameRejectsExisting` (throws `.alreadyExists`, both files intact); `renameRejectsSlashAndEmpty` (`"a/b"` → `.invalidCharacters`, `"  "` → `.empty`); `cacheKeyChangesWithSizeOrDate`.
- [ ] **Step 2: Run** `swift test` — Expected: FAIL.
- [ ] **Step 3: Implement** `VideoLibrary.swift`.
- [ ] **Step 4: Run** `swift test` — Expected: PASS.

### Task 3: Downloader process controller

**Files:**
- Create: `app/Sources/DownloaderCore/DownloaderController.swift`
- Test: `app/Tests/DownloaderCoreTests/DownloaderControllerTests.swift` + fixture script written at test time into a temp support dir as `wx_video_download` (bash: `trap 'echo int > "$PWD/got-int"; exit 0' INT; echo started; while :; do sleep 0.1; done`), and a failing variant (`echo "address already in use"; exit 1`).

**Interfaces:**
- Consumes: `DownloaderPaths`, `CommandRunner`, `turnOffDownloaderProxies`, `isCertificateTrusted`, `trustCertificate`, `currentPrimaryInterface`, `isVPNInterface` (Task 1).
- Produces: `public enum DownloaderState: Equatable, Sendable { case stopped, starting, running(pid: Int32, external: Bool), stopping, failed(String) }`; `@MainActor public final class DownloaderController: ObservableObject { @Published public private(set) var state: DownloaderState; @Published public private(set) var vpnActive: Bool; public init(paths:runner:); public func start(); public func stop() async; public func refresh() }`.
- Behaviour: `start()` → trust cert if untrusted (fail with message "Certificate wasn't trusted" if that fails) → launch binary, cwd = supportDir, stdin `/dev/null`, stdout+stderr appended to `logFile` → `.running(pid, external: false)`; if the process exits by itself → `.failed(<last 3 non-empty log lines>)` and run proxy cleanup. `stop()` → SIGINT, wait ≤ 8 s (poll 0.2 s), then SIGKILL, then always `turnOffDownloaderProxies` → `.stopped`; works for external pids via `kill`. `refresh()` → find external process with `/usr/bin/pgrep -x wx_video_download`; if none and state isn't starting/running, run `turnOffDownloaderProxies`; update `vpnActive`.

- [ ] **Step 1: Write failing tests** — `startRunsBinaryInSupportDir` (state becomes `.running(_, external: false)`, log contains `started`); `stopSendsInterruptAndCleansProxy` (after `await stop()`: `got-int` exists, process gone, FakeRunner saw `-listallnetworkservices`, state `.stopped`); `startupFailureShowsLogTail` (failing script → eventually `.failed` containing `address already in use`); `detectsExternalProcess` (FakeRunner returns `4242\n` for pgrep → `.running(pid: 4242, external: true)`); `refreshCleansLeftoverProxy` (pgrep returns status 1, Wi-Fi proxy is ours → set-state-off calls recorded); `untrustedCertIsTrustedBeforeLaunch` (verify-cert status 1 → add-trusted-cert called before launch).
- [ ] **Step 2: Run** `swift test` — Expected: FAIL.
- [ ] **Step 3: Implement** with `Foundation.Process`; observe termination via `terminationHandler` hopping to the main actor.
- [ ] **Step 4: Run** `swift test` — Expected: PASS (all tasks' tests).

### Task 4: SwiftUI app (status bar + library window)

**Files:**
- Create: `app/Sources/ChannelsDownloader/ChannelsDownloaderApp.swift` (`@main`, `Window`, `NSApplicationDelegateAdaptor` whose `applicationShouldTerminate` returns `.terminateLater`, awaits `controller.stop()` if running, then replies; `applicationShouldTerminateAfterLastWindowClosed` → true)
- Create: `StatusBarView.swift` (dot + text: Stopped / Starting… / Running: open Channels in WeChat / ⚠ VPN is on — downloads won't work until it's off / failure text; Start or Stop button; "Download progress" link to `http://127.0.0.1:2022`, enabled only while running)
- Create: `LibraryModel.swift` (`@MainActor ObservableObject`: `items`, `query`, rescan on folder change via `DispatchSource.makeFileSystemObjectSource` on the folder fd plus a 3 s timer; creates the folder if missing on "Open in Finder")
- Create: `LibraryView.swift` (header "Downloaded videos (N)", search field, grid/list `Picker`; grid of 180-pt cards; list as `Table` with Title/Length/Size/Date; empty state text "No videos yet. Start the downloader, play a video in WeChat Channels and click its download button."; double-click → open with QuickTime Player via `NSWorkspace.open(_:withApplicationAt:configuration:)` at `/System/Applications/QuickTime Player.app`; context menu Show in Finder / Rename… (sheet with text field, shows `RenameError` message) / Move to Trash (`FileManager.trashItem`); footer "Open in Finder")
- Create: `Thumbnails.swift` (`actor ThumbnailCache` keyed by `ThumbnailKey`: `QLThumbnailGenerator` 360×640 representation; duration from `AVURLAsset.load(.duration)`)
- Delete: placeholder `main.swift`

- [ ] **Step 1: Build** `cd app && swift build` — Expected: compiles without errors or Swift 6 concurrency warnings.
- [ ] **Step 2: Manual QA (no system changes):** make a QA support dir (copy of the support folder, QA config per Global Constraints, `download.dir` = QA folder holding 2 sample MP4s made with `ffmpeg -f lavfi -i testsrc=duration=5:size=360x640 -pix_fmt yuv420p`), run with `CHANNELS_DOWNLOADER_SUPPORT_DIR=<qa> swift run ChannelsDownloader`; verify via screenshots: thumbnails + lengths show; search filters; grid/list toggle; Start → Running (ports 2032/2033 listening, `scutil --proxy` unchanged); Stop → Stopped; drop a third MP4 in → appears within 3 s; Rename and Move to Trash work on a QA file.

### Task 5: App bundle, icon, install

**Files:**
- Create: `app/Resources/Info.plist` (CFBundleName/DisplayName "WeChat Channels Downloader", CFBundleIdentifier `local.wechat-channels-downloader`, CFBundleExecutable `ChannelsDownloader`, CFBundleIconFile `AppIcon`, LSMinimumSystemVersion `14.0`, NSHighResolutionCapable true)
- Create: `app/scripts/make-icon.swift` (draws a 1024² rounded-square green gradient with white `play.rectangle.fill` + `arrow.down` SF Symbol → iconset via `sips` → `iconutil -c icns`)
- Create: `app/scripts/build-app.sh` (`swift build -c release`; assemble `build/WeChat Channels Downloader.app/Contents/{MacOS,Resources,Info.plist}`; `codesign --force --deep -s -`; if `--install`: quit a running copy via `osascript -e 'quit app id "local.wechat-channels-downloader"'`, then replace `~/Applications/WeChat Channels Downloader.app`)

- [ ] **Step 1: Run** `app/scripts/build-app.sh` — Expected: `codesign -v` passes; `plutil -lint` OK.
- [ ] **Step 2: Run** with `--install`; launch with QA env via `open -n --env CHANNELS_DOWNLOADER_SUPPORT_DIR=<qa> -a "$HOME/Applications/WeChat Channels Downloader.app"`; screenshot shows icon, status bar, library. Expected: matches Task 4 QA.
- [ ] **Step 3: Run** `swift test` once more — Expected: all PASS.
