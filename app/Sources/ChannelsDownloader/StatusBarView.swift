import AppKit
import AppViews
import DownloaderCore
import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject private var controller: DownloaderController
    @EnvironmentObject private var library: LibraryModel
    @AppStorage("libraryLayout") private var layout: LibraryLayout = .grid

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                StatusDot(color: dotColor, pulsing: controller.isRunning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text(detail)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.textSecondary.color)
                        .lineLimit(statusDetailLineLimit(isFailure: isFailed))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .help(detail)
                }
                Spacer(minLength: 12)
                PillSearchField(text: $library.query).frame(width: 200)
                LayoutToggle(layout: $layout)
                if controller.isRunning {
                    Button("Progress") {
                        NSWorkspace.shared.open(URL(string: "http://127.0.0.1:2022")!)
                    }
                    .buttonStyle(PillButtonStyle())
                    .help("Open the downloader's own progress page")
                }
                actionButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 2)
            .padding(.bottom, 14)

            vpnStrip
            if let message = controller.helperMessage {
                StripView(icon: "xmark.octagon.fill", text: message,
                          foreground: Theme.danger, background: Theme.dangerBackground,
                          actionTitle: "Dismiss") { controller.dismissHelperMessage() }
            }
            Rectangle().fill(Theme.hairline.color).frame(height: 1)
        }
    }

    /// One line about the VPN: what will happen, that VPN mode is on, or what needs fixing.
    @ViewBuilder private var vpnStrip: some View {
        switch controller.vpnStrip {
        case .none:
            EmptyView()
        case .leftover:
            StripView(icon: "xmark.octagon.fill",
                      text: "Your VPN connection still points at the stopped downloader, so web pages may not load.",
                      foreground: Theme.danger, background: Theme.dangerBackground,
                      actionTitle: "Fix") { Task { await controller.fixVPNProxy() } }
        case .needsSetup:
            StripView(icon: "lock.shield",
                      text: "Your VPN is on. Set up VPN mode once (one password) so downloads work with it.",
                      foreground: Theme.warningText, background: Theme.warningBackground,
                      actionTitle: "Set up VPN mode") { Task { await controller.installVPNHelper() } }
        case .needsUpdate:
            StripView(icon: "arrow.triangle.2.circlepath",
                      text: "The VPN helper is from an older version of this app.",
                      foreground: Theme.warningText, background: Theme.warningBackground,
                      actionTitle: "Update helper") { Task { await controller.installVPNHelper() } }
        case .helperNotRunning:
            StripView(icon: "exclamationmark.triangle.fill",
                      text: "The VPN helper is installed but not running. Check System Settings › General › Login Items, or set it up again.",
                      foreground: Theme.warningText, background: Theme.warningBackground,
                      actionTitle: "Set up again") { Task { await controller.installVPNHelper() } }
        case .ready:
            StripView(icon: "lock.shield.fill",
                      text: "VPN mode is set up. Click Start; no password needed.",
                      foreground: Theme.accentLabel, background: Theme.successBackground)
        case .starting:
            StripView(icon: "lock.shield",
                      text: "Turning on VPN mode…",
                      foreground: Theme.warningText, background: Theme.warningBackground)
        case .on:
            StripView(icon: "lock.shield.fill",
                      text: "VPN mode on: WeChat goes through the downloader, then your VPN.",
                      foreground: Theme.accentLabel, background: Theme.successBackground)
        case .blockedByVPNProxy:
            StripView(icon: "exclamationmark.triangle.fill",
                      text: "VPN mode is on, but your VPN sets its own proxy, so WeChat isn't going through the downloader.",
                      foreground: Theme.warningText, background: Theme.warningBackground)
        }
    }

    @ViewBuilder private var actionButton: some View {
        switch controller.state {
        case .running:
            Button("Stop") { Task { await controller.stop() } }
                .buttonStyle(PillButtonStyle(prominent: true))
        case .starting, .stopping:
            Button(controller.state == .starting ? "Starting…" : "Stopping…") {}
                .buttonStyle(PillButtonStyle())
                .disabled(true)
        case .stopped, .failed:
            Button("Start") { Task { await controller.start() } }
                .buttonStyle(PillButtonStyle(prominent: true))
        }
    }

    private var isFailed: Bool {
        if case .failed = controller.state { return true }
        return false
    }

    private var dotColor: Color {
        switch controller.state {
        case .running: return Theme.accent.color
        case .starting, .stopping: return Theme.warningText.color
        case .failed: return Theme.danger.color
        case .stopped: return Theme.textSecondary.color
        }
    }

    private var title: String {
        switch controller.state {
        case .stopped: return "Idle"
        case .starting: return "Starting…"
        case .running(_, let external): return external ? "Capturing (started from Terminal)" : "Capturing"
        case .stopping: return "Stopping…"
        case .failed: return "Couldn't start"
        }
    }

    private var detail: String {
        switch controller.state {
        case .stopped: return "Click Start, then open Channels in WeChat."
        case .starting: return "If macOS asks for your password, it's to trust the downloader's certificate."
        case .running: return "Play a video in WeChat Channels and click its download button."
        case .stopping: return "Switching your network proxy back off."
        case .failed(let message): return message
        }
    }
}

/// Status light; while capturing it glows and sends out a slow pulse ring.
struct StatusDot: View {
    let color: Color
    let pulsing: Bool

    var body: some View {
        ZStack {
            if pulsing { PulseRing(color: color) }
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .shadow(color: color.opacity(pulsing ? 0.9 : 0), radius: 6)
        }
        .frame(width: 30, height: 30)
    }
}

private struct PulseRing: View {
    let color: Color
    @ViewState private var expanded = false

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 2)
            .frame(width: 12, height: 12)
            .scaleEffect(expanded ? 2.4 : 1)
            .opacity(expanded ? 0 : 0.8)
            .onAppear {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { expanded = true }
            }
    }
}

/// Grid / list switch as two icon pills.
struct LayoutToggle: View {
    @Binding var layout: LibraryLayout

    var body: some View {
        HStack(spacing: 2) {
            option(.grid, icon: "square.grid.2x2", label: "Grid")
            option(.list, icon: "list.bullet", label: "List")
        }
        .padding(3)
        .background(Capsule().fill(Theme.surface.color))
        .overlay(Capsule().stroke(Theme.hairlineStrong.color, lineWidth: 1))
    }

    private func option(_ value: LibraryLayout, icon: String, label: String) -> some View {
        let selected = layout == value
        return Button { layout = value } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 24)
                .foregroundStyle(selected ? Theme.onAccent.color : Theme.textSecondary.color)
                .background(Capsule().fill(selected ? Theme.accent.color : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}

/// A full-width coloured note under the top bar, with an optional button.
struct StripView: View {
    let icon: String
    let text: String
    let foreground: ThemeColor
    let background: ThemeColor
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text)
            Spacer(minLength: 8)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .overlay(Capsule().stroke(foreground.color, lineWidth: 1))
            }
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(foreground.color)
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .background(background.color)
    }
}
