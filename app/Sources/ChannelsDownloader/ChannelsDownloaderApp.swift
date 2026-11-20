import AppKit
import AppViews
import DownloaderCore
import SwiftUI

@main
struct ChannelsDownloaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("WeChat Channels Downloader", id: "main") {
            ContentView()
                .environmentObject(appDelegate.controller)
                .environmentObject(appDelegate.library)
                .frame(minWidth: 780, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 680)
        .commands {
            CommandGroup(after: .appSettings) {
                VPNHelperCommands(controller: appDelegate.controller)
            }
        }
    }
}

/// App-menu items for the VPN helper: set up / update, and remove.
struct VPNHelperCommands: View {
    @ObservedObject var controller: DownloaderController

    var body: some View {
        Button(controller.helperStatus == .outdated ? "Update VPN Helper…" : "Set Up VPN Mode…") {
            Task { await controller.installVPNHelper() }
        }
        .disabled(controller.helperStatus == .installed && controller.helperRunning)
        Button("Remove VPN Helper…") {
            Task { await controller.removeVPNHelper() }
        }
        .disabled(controller.helperStatus == .notInstalled)
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            StatusBarView()
            LibraryView()
        }
        .background(Theme.background.color.ignoresSafeArea())
        .foregroundStyle(Theme.text.color)
        .fontDesign(.rounded)
        .tint(Theme.accent.color)
        .preferredColorScheme(.dark)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller: DownloaderController
    let library: LibraryModel
    private var refreshTimer: Timer?

    override init() {
        let paths = DownloaderPaths.resolve()
        controller = DownloaderController(paths: paths)
        library = LibraryModel(folder: paths.downloadsDir)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        Task { await controller.refresh() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.controller.refresh() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Quitting always stops the downloader (finishing any start or stop in flight)
    /// so the Mac's proxy is switched back off.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard controller.needsShutdown else { return .terminateNow }
        Task {
            await controller.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
