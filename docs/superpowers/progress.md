# SDD ledger — plan: docs/superpowers/plans/2026-11-19-channels-downloader-app.md
Spec: docs/2026-11-19-channels-downloader-app-design.md
Setup: Ruling: no git repo and no sdd scripts in this scratch workspace — ledger kept by hand, no commit steps, review package = file list — cost if wrong: no per-task diff ranges for the reviewer.
Pre-flight: Task1→Task3 (CommandRunner, DownloaderPaths, turnOffDownloaderProxies, cert + network helpers) consistent. Task2→Task4 (VideoItem, ThumbnailKey, renameVideo, matches, format*) consistent. Task3→Task4 (DownloaderController, DownloaderState) consistent.
Task 1: Ruling: CommandRunner.run gains `input: String?` (protocol extension keeps 2-arg call) — scutil needs stdin to read PrimaryInterface; `route get default` misses OpenVPN split routes — cost if wrong: none, additive.
Task 1: complete (tests: cd app && swift test → 10/10 passed; RED seen first: missing CommandRunner/CommandResult)
Task 2: note: one flaky build ("plugin for module 'TestingMacros' not found"), clean on immediate rerun, no code change.
Task 2: complete (tests: cd app && swift test → 19/19 passed; RED seen first: missing VideoItem)
Task 3: Ruling: start() and refresh() are `async` (plan said sync) — trusting the cert shows a password dialog and pgrep/scutil/networksetup block; running them on the main actor would freeze the window — cost if wrong: none, callers just await.
Task 3: note: TestingMacros plugin flake again on first build after a test edit; rerun showed true RED (missing DownloaderController).
Task 3: Ruling: init gains `home:` (default user home) and a `refusedTrustDoesNotLaunch` + `refreshReportsVPN` test beyond the plan — trust needs the keychain path; both cover spec lines (cert, VPN warning) — cost if wrong: none.
Task 3: complete (tests: cd app && swift test → 27/27 passed)
Task 4: Ruling: views use `@ViewState` (typealias of SwiftUI.State) instead of `@State` — macOS 27 SDK maps @State to a SwiftUIMacros plugin that Command Line Tools don't ship (plain @State fails, alias compiles, both checked) — cost if wrong: none; behaviour identical.
Task 4: Ruling: hands-on QA runs on the bundled app (Task 5) instead of `swift run` — same code, and it also checks the bundle — cost if wrong: none. QA limitation: user's own downloader (pid 20157) is running, so the app shows it as external; Stop is not clicked in QA because it would change the user's proxy; start/stop covered by unit tests with a real process.
Task 4: QA: app launched against QA dir (process up, no crash); screen access to the app was declined by the user, so visual QA (thumbnails, search, grid/list, rename, trash in UI) not done by me — flagged to user. QA instance killed with SIGKILL so its quit handler would not stop the user's real downloader.
Task 5: Ruling: tests run via `scripts/test.sh` (passes `-plugin-path …/host/plugins/testing`) instead of bare `swift test` — CLT doesn't pass the swift-testing plugin path, causing the intermittent "plugin for module 'TestingMacros' not found"; with the flag 2/2 runs after touching all tests passed — cost if wrong: none.
Task 5: complete (app built, ad-hoc signed, `codesign -v` OK, plutil OK, installed to ~/Applications/WeChat Channels Downloader.app; tests: app/scripts/test.sh → 27/27 passed)
Final review: fresh reviewer (opus) — verdict "with fixes". Re-graded: I1 unfenced 3 s proxy cleanup races Start/Terminal start (Important, agree); I2 quit during .stopping/.starting skips escalation + cleanup (Important, agree: spec anti-goal); I3 grid thumbnails overflow card for landscape (Important, agree: visible breakage); I4 list menu acts on arbitrary row of multi-selection (Important, agree: destructive on wrong file); I5 test gaps external stop / SIGKILL / no-set-while-external (Important, agree); I6 plan QA incomplete (Important: real-binary start/stop to be covered by gated integration test; visual QA needs the user).
Final: Ruling: Quit also stops a Terminal-started downloader — spec says Quit stops the downloader and the app replaces Terminal use; leaving it running would leave the proxy pointing at it after the app is gone — cost if wrong: a Terminal user's session ends when they quit the app.
Final: Ruling: binary's own proxy restore on SIGINT — not relied on; controller always runs its own cleanup after stop — cost if wrong: none.
Final: Ruling: executable target warnings — app build output had no warnings (grep of t4c.log) — cost if wrong: none.
Final: Ruling: SunnyNet fingerprint check on certs/ca.pem — not added; path is fixed to the generated CA, spec satisfied — cost if wrong: a user who swaps ca.pem by hand.
Final: minor (deferred): Minor1 stop during crash handling — fixed incidentally by setting state before awaits (I1 fix).
Final: minor (deferred): pgrep lacks -U uid / EPERM treated as gone (fast user switching).
Final: minor (deferred): rename with unchanged name says "already exists"; case-only rename refused; leading "." hides the file.
Final: minor (deferred): thumbnail cache never evicts.
Final: minor (deferred): "Download progress" link hard-coded to port 2022.
Final: minor (deferred): status labels — orphan shown as "started from Terminal"; late crash titled "Couldn't start".
Final: minor (deferred): naive YAML parse of download.dir (comments, quotes, ~, relative).
Final: minor (deferred): partial-download hiding unverified against a real download.
Final: minor (deferred): rename sheet EnvironmentObject propagation / double submit (guarded).
Final: minor (deferred): install script may rm the bundle while an old copy is still stopping (>10 s).
Final: fixed I1 (proxy cleanup only on transitions, gated on nothing listening at 127.0.0.1:2023, state written before awaits) — refreshCleansLeftoverProxyOnce, cleanupSkippedWhileProxyPortInUse, inFlightCleanupNeverOverwritesNewRun RED (mutation back to old behaviour)→GREEN, suite 35/35
Final: fixed I2 (core part: shutdown() awaits in-flight start/stop, stops, cleans) — shutdownWaitsForInFlightStop RED (mutation)→GREEN, shutdownDuringStartingStopsTheNewProcess GREEN, suite 35/35; app wiring next
Final: fixed I5 — added stopsExternalProcess, escalatesToKillWhenInterruptIgnored, no-set assertion in detectsExternalProcessAndLeavesItsProxy (coverage of existing code; first RED was compile, behaviour confirmed by mutation run above), suite 35/35
Final: fixed I2 (app wiring) — applicationShouldTerminate waits via controller.needsShutdown/shutdown() for running, starting and stopping; covered by shutdown* tests, suite green
Final: fixed I3 thumbnail overflow — ThumbnailFrame (new AppViews target) fixes the 3:4 tile first and clips the picture to it — landscapeVideoStaysInsideItsCard + portraitVideoKeepsCardShape RED→GREEN (pixel probe / height), AppViews suite 3/3
Final: fixed I4 list menu on multi-selection — single-row Table selection + singleItem(for:in:) (nil unless exactly one) — menuTargetNeedsExactlyOneSelection RED (compile)→GREEN, suite green
Final: fixed I6 (partial) — RealDownloaderTests runs the real binary from the QA folder (proxy.system:false, ports 2032/2033): start → port 2033 listening → stop → process gone, port closed, log "Downloader has been shut down"; Mac proxy unchanged. Visual UI QA still not done (screen access declined) — handed to the user.
Final: suite — QA_SUPPORT_DIR=… scripts/test.sh → DownloaderCoreTests 36/36 (incl. real binary), AppViewsTests 3/3; app rebuilt, signed, reinstalled.
Final: Ruling: no git, so superpowers:finishing-a-development-branch and workspace deletion don't apply; ledger kept in docs/superpowers/progress.md as the record — cost if wrong: none.

# SDD ledger — plan: docs/superpowers/plans/2026-11-19-night-cinema-theme.md
Spec: docs/2026-11-19-night-cinema-theme-design.md
Setup: Ruling: user said "Yes, build it" after approving the design, so I go straight from plan to execution (Native, as chosen before) without a separate plan-review stop — cost if wrong: plan details the user didn't see.
Task 1: complete (Theme, ThemeColor/contrastRatio, PillButtonStyle, PillSearchField, green chip; tests: scripts/test.sh --filter AppViewsTests → 6/6; RED seen: compile, then durationChipIsAccentGreen behavioural)
Task 2: Ruling: RealDownloaderTests read the log once after the port opened — the binary listens before it logs, so it was flaky (failed once); now polls for both — cost if wrong: none (test-only).
Task 2: complete (views restyled: hidden title bar, forced dark, rounded font, pulsing status dot, pill search/layout/Start-Stop, amber VPN strip, green section label, dark hover-glow cards, dark table, empty state, footer, rename sheet; swift build clean, no warnings; tests: QA_SUPPORT_DIR=… scripts/test.sh → 36/36 + 6/6, 3 runs; installed and opened)

# SDD ledger — plan: docs/superpowers/plans/2026-11-19-vpn-mode.md
Spec: docs/2026-11-19-vpn-mode-design.md
Setup: Ruling: the user picked "Route via the VPN" with the behaviour I described (password per Start, guard auto-removes, reconnect handling, VPN note), so the design doc records that and I go straight to the plan and build — cost if wrong: details the user didn't see in writing.
Task 1: complete (VPNMode.swift: guard + cleanup scripts, elevatedCommand, isDownloaderEffectiveProxy; tests: scripts/test.sh --filter VPNGuardTests|VPNParsingTests → 9/9; RED: compile; foreign-proxy + malformed-ID tests confirmed by mutation)
Task 2: complete (controller: enableVPNMode after Start when VPN primary, fixVPNProxy, vpnGuardRunning/routedThroughDownloader/vpnProxyLeftover via one RefreshProbe; FakeRunner.setForPath added; tests: scripts/test.sh → 51/51 + 6/6; RED: compile)
Task 3: complete (Theme successBackground/dangerBackground + contrast tests RED(compile)→GREEN; StatusBarView four-state VPN strip with Fix / Enable VPN mode buttons; build clean; scripts/test.sh → 51/51 + 6/6; installed and reopened). VPN path itself untested end to end — needs the user with their VPN on.
Final review (night cinema plan): fresh reviewer (opus) — "with fixes". Re-graded: I1 selected Table row "Downloaded" text 2.46:1 on selection blue (Important, agree: spec anti-goal); I2 failure detail truncated at 3 lines, hiding the actual error (Important, agree); Minor2 "Open folder" not green — re-graded Important: it's a spec line.
Final: minor (deferred): disabled Starting…/Stopping… pill looks enabled.
Final: minor (deferred): accessibility — layout toggle selected trait, search field label, no focus ring on pills.
Final: minor (deferred): pulse/hover ignore Reduce Motion; pulse runs while capturing.
Final: minor (deferred): only the top 28–32 pt strip drags the window.
Final: minor (deferred): top-bar controls shift when the action pill changes width.
Final: minor (deferred): no-op .scrollContentBackground on the grid ScrollView.
Final: Ruling: RealDownloaderTests polls for "System proxy is not set", which the binary prints after "Proxy service started successfully" (start.go order) — reviewer's flake concern doesn't apply — cost if wrong: a rare flaky test.
Final: minor (deferred): contrast test lacks danger-on-surface (passes 6.43:1).
Final: fixed I1 selected-row text — RowSecondaryText switches to Theme.text when the row is highlighted (backgroundProminence) — selectedRowSecondaryTextIsReadable RED(compile)→GREEN, suites 51/51 + 9/9
Final: fixed I2 truncated failure — detail has no line limit when failed, plus .help(detail) — failureDetailIsNotTruncated RED(compile)→GREEN
Final: fixed spec gap "Open folder" in green — PillButtonStyle(kind: .accent) — openFolderPillIsGreen RED(compile)→GREEN; build clean. Not installed yet: waiting for the VPN-mode review so a possible live VPN test isn't interrupted.
Final review (VPN mode): fresh reviewer (opus) — "with fixes"; mechanism confirmed live with the user's VPN (State Proxies on service 019566B0…, scutil --proxy → 127.0.0.1:2023). Re-graded: I1 green strip on guard-exists not routed (Important, agree); I2 guard has no signal trap → TERM leaves VPN pointing at dead proxy (Important, agree: anti-goal); I3 root script honours inherited SCUTIL/GUARD_INTERVAL/env (Important, agree: anti-goal; plan's env hook was the cause); Minor1 substring "ours" match removes look-alike foreign entries — re-graded Important (anti-goal: never remove what the app didn't add); Minor3 __SCOPED__ parse — fixed as part of I1.
Final: minor (deferred): new guard doesn't adopt its own leftover entry (extra Fix prompt in a rare path).
Final: minor (deferred): overlapping refresh ticks / one-tick red flash after Stop.
Final: minor (deferred): Enable/Fix buttons live while a password prompt is open; open prompt delays Quit.
Final: minor (deferred): Fix result not reported.
Final: minor (deferred): check-then-write race with a VPN client writing Proxies (no atomic CAS in scutil).
Final: fixed I1 green-only-when-routed — vpnStripState (none/leftover/idleNotice/needsEnable/starting/on/blockedByVPNProxy) + controller.vpnStrip; top-level-only effective-proxy parse — stripStates, guardAliveButNotRoutedIsNotGreen, effectiveProxyIgnoresScopedEntries RED(compile)→GREEN
Final: fixed I2 guard signal trap — cleanup() on TERM/HUP/INT and loop end — guardCleansUpWhenKilled RED(mutation)→GREEN
Final: fixed I3 no inherited environment — elevatedCommand uses `/usr/bin/env -i PATH=… /bin/sh -c`; shipped scripts hard-code S=/usr/sbin/scutil, T=2 (tests build scripts via makeVPNGuardScript/makeVPNCleanupScript) — shippedScriptsIgnoreTheEnvironment, elevatedCommandPassesArgsAsArgv RED(compile)→GREEN
Final: fixed Minor1→Important exact ownership — guard writes ChannelsDownloaderGuard : 1; guard and cleanup only remove entries with that exact line — cleanupRemovesOnlyOurEntries (look-alike 127.0.0.12:20235 and unmarked 127.0.0.1:2023 kept) RED(mutation)→GREEN
Final: suite — scripts/test.sh → 55/55 + 9/9 (incl. real binary); build clean.
Final: Ruling: intermittent guard-test failure (first SET not seen within 3 s) in 2 of ~8 full parallel runs, both while the user's live downloader/VPN session was running; not reproduced in 10 further runs (4 without, 6 with the real-binary test). Added failure diagnostics (guard/downloader status, fake scutil log) and raised the wait to 10 s — cost if wrong: a real guard stall would only show as a slower test; diagnostics will name it.
Final: suite — QA_SUPPORT_DIR=… scripts/test.sh → 56/56 + 9/9.

# SDD ledger — plan: docs/superpowers/plans/2026-11-19-vpn-helper.md
Spec: docs/2026-11-19-vpn-helper-design.md
Setup: Ruling: user chose "Set up once" after I described it (one password, helper stays installed, remove option) — design written from that, straight to build — cost if wrong: details not seen in writing.
Task 1: complete (VPNHelper.swift: helper daemon, install, uninstall scripts with SystemTools/VPNHelperLocation injection, vpnHelperStatus; shared cleanup shell; FakeTools.swift shared fakes; tests: scripts/test.sh --filter VPNHelper|VPNCleanup|VPNParsing → 19/19; RED: compile; listening/trap/chown confirmed by mutation)
Task 2: Ruling: two test expectations were wrong, not the code — (a) "no background marker" must check only the AppleScript source, the helper script argv legitimately contains ">/dev/null 2>&1 &&"; (b) a just-detected downloader is in the 10 s ".starting" grace, so the controller test asserts "not green" and the pure stripStates test covers ".blockedByVPNProxy" after 10 s — cost if wrong: none.
Task 2: complete (controller: helperStatus/helperRunning from helper file + pgrep, installVPNHelper/removeVPNHelper/fixVPNProxy via runElevated, per-Start guard and its password removed, runningSince grace; VPNStripState needsSetup/needsUpdate/ready; tests RED(compile)→GREEN)
Task 3: complete (strip: Set up VPN mode / Update helper / ready states; app menu "Set Up VPN Mode…/Update VPN Helper…" and "Remove VPN Helper…"; build clean; QA_SUPPORT_DIR=… scripts/test.sh → 64/64 + 9/9)
Final review (VPN helper): fresh reviewer (opus) — "with fixes". Re-graded: C1 helper-alive check `pgrep -f channels-vpn-helper` can never match the launchd argv (`/bin/sh <scriptPath>`), so the UI stays on "Set up VPN mode" and re-prompts (Critical, agree — plan-level error carried from the guard; test faked pgrep with the same constant); I2 trigger is two independent facts (any-user process named wx_video_download + anything listening on 2023), crossing accounts (Important, agree); I3 install/uninstall failures silent, installed-but-not-running indistinguishable from not set up (Important, agree); Minor1 menu can't repair installed-but-not-running — folded into I3.
Final: minor (deferred): uninstall ignores bootout result and leaves .tmp files from an interrupted install.
Final: minor (deferred): idle loop runs a root lsof/sleep every 2 s forever (consider longer idle interval).
Final: minor (deferred): listener probe every 2 s while capturing.
Final: minor (deferred): helper shows as an unattributed "sh" background item in Login Items (unsigned app).
Final: minor (deferred): unused background: branch in elevatedCommand; stale "guard" comment in VPNMode.swift.
Final: minor (deferred): "no password needed" wording when the first Start may still ask to trust the certificate.
Final: minor (deferred): no documented manual removal if the app is deleted first.
Final: minor (deferred): unquoted path assignments in install/uninstall scripts (safe for shipped constants).
Final: fixed C1 helper-alive check — pgrep -U 0 -f vpnHelperAlivePattern(location) (= scriptPath, what launchd's argv contains) — aliveCheckMatchesLaunchdArguments ties the plist ProgramArguments to the pattern; controller tests use the same pattern — RED(compile, then mutation)→GREEN
Final: fixed I2 trigger — helper now requires the 127.0.0.1:2023 LISTEN socket's own process to be wx_video_download owned by the console uid (lsof -Fpcu + stat -f %u /dev/console); pgrep/nc removed from the daemon; spec wording corrected — ignoresListenerOwnedByAnotherUser, ignoresListenerWithAnotherName RED(mutation)→GREEN
Final: fixed I3 silent failures — runElevated reports elevatedFailureMessage (cancel -128 is quiet) as a red strip with Dismiss; new .helperNotRunning state ("installed but not running… Login Items… Set up again"); menu "Set Up VPN Mode…" enabled unless installed AND running — installFailureIsReported, cancelledInstallIsQuiet, installedButNotRunningIsItsOwnState RED(compile)→GREEN. (Incidentally also reports Fix failures — previously a deferred minor.)
Final: suite — QA_SUPPORT_DIR=… scripts/test.sh → 70/70 + 9/9; build clean.
Final: installed app with set-up-once VPN helper (helper itself not installed: that's the user's one-time click). Live checks: real lsof -Fpcu format and 17-char command name verified read-only with throwaway listeners.

# Follow-up: idle cost of the VPN helper (user asked to fix the deferred minor)
Measured: lsof -iTCP@127.0.0.1:2023 ≈ 0.03 s as the user (root scans all ~820 processes); nc -z ≈ 0.00 s. Plan: probe the port with nc first, run stat + lsof only when something listens. Helper bumped to v3 (app will offer "Update helper").
Follow-up: complete — helper v3 probes 127.0.0.1:2023 with nc before running stat+lsof; idleCheckSkipsLsofWhenNothingListens RED (behavioural: lsof ran every loop)→GREEN; real nc exit codes checked (0 listening / 1 not); suite 71/71 + 9/9; app reinstalled. Installed helper is still v2 until the user clicks Update helper.

# Follow-up: drag and drop out of the library
Ruling: drags always copy (operation mask .copy only), as plain file URLs, via an AppKit NSDraggingSession started from a SwiftUI simultaneous DragGesture — broadest drop-target support (Finder, chat apps) and a drop can never move the original — cost if wrong: no "move" by drag.
Tests: dragSourceOnlyOffersCopy (RED compile → GREEN; mutation [.copy,.move] caught), dragItemsCarryFileURLs. Suite 71/71 + 11/11.
Real check (practice copy, sample videos, Finder folder on the same volume): grid card drag and list row drag each produced an identical copy (sha256 cb1aae75…, ba9be23a…); originals kept. Note: the computer-use step-by-step mouse_move did not generate a drag (tool limitation); left_click_drag did. Temporary NSLog debugging removed. Evidence: docs/evidence/drag-and-drop-test.jpg.

# Follow-up: list view clicks (found in VM test of drag and drop)
Bug: cell-level drag gestures in the Table blocked row selection and double-click. Fix: rows drag via TableRow.itemProvider; cells carry no gestures. Verified in the VM: single click selects, double-click plays (QuickTime), right-click menu. Drag-out from the VM could not be confirmed with the VM's instant drag tool (no drops landed for grid or list) — unverified, grid drag was verified on the real Mac earlier.

# Follow-up: proxy rule list (PAC) — plan: docs/superpowers/plans/2026-11-20-rule-list.md
Cause found: quitting the downloader dropped every app's connections; Claude app logs "Keeping system proxy http://127.0.0.1:2023 … answer direct" and failed ECONNREFUSED until restarted.
Evidence: WeChatAppEx reads PAC keys; VM rehearsal; live Mac test (VPN off) — WeChatAppEx connected to 2023 via PAC. Button not testable on that network without the VPN.
Built (TDD): RuleList.swift, RuleListServer.swift (127.0.0.1:2024, all-DIRECT while downloader down), controller (app-config.yaml via -c with proxy.system false, rule list on once listening, off on stop/crash, port-taken guard, single services listing), isDownloaderEffectiveProxy accepts PAC, helper v4 writes PAC keys. RED: compile / behavioural; mutations caught: foreign-PAC overwrite, suffix match without dot, 2024 ownership.
VM run (config.yaml system:true): capturing → secure web proxy off, PAC on, weixin → PROXY 2023, anthropic/google DIRECT; Stop → PAC off, server all-DIRECT; app force-quit while capturing → PAC left on but unreadable → everything DIRECT.
Review (fresh, opus): no Critical. Fixed #2 helper requires 2024 served by ChannelsDownloader owned by console uid (needsTheAppServingTheRuleList); #4 server single in-flight start, forget dead listener (simultaneousStartsShareOneListener); #6 appConfigYAML comments/CRLF (handlesCommentsAndWindowsLineEndings). #1 settled by VM run. #3 accepted: VPN mode needs the app open (Terminal launcher alone → WeChat direct).
Minor (deferred): disabled foreign PAC URL overwritten (not restored); manual HTTP proxy services get PAC on top (other traffic DIRECT instead of via that proxy); narrow race between port check and bind; no non-VPN UI when routing never turns on; leftover banner can fire for harmless PAC; Fix Internet.command doesn't clear the PAC; bare-IP connections go direct.
Suite: 92/92 + 11/11; real binary with -c passes.
Re-review of fixes #2/#4/#6: all correct, no new Important. Reviewer confirmed with real lsof that an NWListener shows under its own process with the full name (+c 0), so `ChannelsDownloader` matches. Helper also clears the VPN entry when the app quits (consistent with #3).
Minor (deferred): stop() doesn't cancel an in-flight start (stop() unused in Sources); a start arriving just after a failed start gets that failure (refresh retries); appConfigYAML with mixed LF/CRLF or a 4-space-indented proxy block lacking system: would produce invalid YAML (not the case for the real config).
Live check (user's Mac, VPN on, helper v4): button appears in Channels; VPN entry = PAC + marker, no HTTP/HTTPS proxy; weixin/res.wx → PROXY 2023, anthropic/claude.ai/google → DIRECT; only WeChatAppEx connected to 2023 (17). After Stop: downloader gone, VPN entry removed, no proxy, apple.com 200, server all-DIRECT, Claude app no ECONNREFUSED since 12:00. Done.
