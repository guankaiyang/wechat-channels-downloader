import AppViews
import DownloaderCore
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryModel
    @AppStorage("libraryLayout") private var layout: LibraryLayout = .grid
    @ViewState private var selection: URL?
    @ViewState private var renaming: VideoItem?
    @ViewState private var actionError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        .sheet(item: $renaming) { item in
            RenameSheet(item: item) { renaming = nil }
                .environmentObject(library)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack {
            Text("YOUR LIBRARY · \(library.items.count) \(library.items.count == 1 ? "VIDEO" : "VIDEOS")")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(Theme.accentLabel.color)
            Spacer()
            if !library.query.isEmpty {
                Text("\(library.visibleItems.count) matching “\(library.query)”")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textSecondary.color)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    @ViewBuilder private var content: some View {
        if library.items.isEmpty {
            emptyState(icon: "film.stack", title: "Your library is empty",
                       message: "Click Start, play a video in WeChat Channels and click its download button. It'll land here.")
        } else if library.visibleItems.isEmpty {
            emptyState(icon: "magnifyingglass", title: "No matches",
                       message: "No video titles contain “\(library.query)”.")
        } else if layout == .grid {
            grid
        } else {
            list
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)], spacing: 18) {
                ForEach(library.visibleItems) { item in
                    VideoCard(item: item)
                        .fileDraggable(item.url)
                        .onTapGesture(count: 2) { library.play(item) }
                        .contextMenu { menu(for: item) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .scrollContentBackground(.hidden)
    }

    private var list: some View {
        // Rows drag through the table's own drag support (copy to Finder/apps), so clicks,
        // selection and double-click keep working; cells carry no gestures.
        Table(of: VideoItem.self, selection: $selection) {
            TableColumn("Title") { item in
                HStack(spacing: 10) {
                    ThumbnailView(item: item, showsDuration: false)
                        .frame(width: 34, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text(item.title).lineLimit(2)
                }
            }
            TableColumn("Length") { item in DurationText(item: item) }.width(70)
            TableColumn("Size") { item in Text(formatSize(item.sizeBytes)).monospacedDigit() }.width(80)
            TableColumn("Downloaded") { item in
                RowSecondaryText(item.modified.formatted(date: .abbreviated, time: .shortened))
            }.width(min: 130, ideal: 160)
        } rows: {
            ForEach(library.visibleItems) { item in
                TableRow(item).itemProvider { NSItemProvider(contentsOf: item.url) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.color)
        .contextMenu(forSelectionType: URL.self) { urls in
            if let item = singleItem(for: urls, in: library.items) { menu(for: item) }
        } primaryAction: { urls in
            if let item = singleItem(for: urls, in: library.items) { library.play(item) }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.hairline.color).frame(height: 1)
            HStack(spacing: 8) {
                Image(systemName: "folder").foregroundStyle(Theme.textSecondary.color)
                Text(library.folder.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if !library.items.isEmpty {
                    Text("\(formatSize(library.totalSize)) total")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Theme.textSecondary.color)
                }
                Button("Open folder") { library.openFolder() }
                    .buttonStyle(PillButtonStyle(kind: .accent))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(Theme.surface.color)
    }

    // MARK: Helpers

    @ViewBuilder private func menu(for item: VideoItem) -> some View {
        Button("Play") { library.play(item) }
        Button("Show in Finder") { library.reveal(item) }
        Button("Rename…") { renaming = item }
        Divider()
        Button("Move to Trash", role: .destructive) {
            do { try library.moveToTrash(item) } catch { actionError = error.localizedDescription }
        }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.surface.color).frame(width: 84, height: 84)
                Circle().stroke(Theme.accent.color.opacity(0.6), lineWidth: 1.5).frame(width: 84, height: 84)
                Image(systemName: icon).font(.system(size: 32, weight: .medium)).foregroundStyle(Theme.accent.color)
            }
            .shadow(color: Theme.accent.color.opacity(0.25), radius: 18)
            Text(title).font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(message)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.textSecondary.color)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A dark card with a rounded thumbnail; on hover it lifts with a green ring and glow.
struct VideoCard: View {
    let item: VideoItem
    @ViewState private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ThumbnailView(item: item)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(hovering ? Theme.accent.color : Theme.hairlineStrong.color, lineWidth: hovering ? 2 : 1)
                )
                .shadow(color: Theme.accent.color.opacity(hovering ? 0.45 : 0), radius: 14)
            Text(item.title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.text.color)
                .lineLimit(2)
                .help(item.title)
            Text("\(formatSize(item.sizeBytes)) · \(item.modified.formatted(.relative(presentation: .named)))")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Theme.textSecondary.color)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(hovering ? Theme.surfaceRaised.color : Theme.surface.color)
        )
        .scaleEffect(hovering ? 1.02 : 1)
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { hovering = inside }
        }
    }
}

struct RenameSheet: View {
    let item: VideoItem
    let dismiss: () -> Void
    @EnvironmentObject private var library: LibraryModel
    @ViewState private var name = ""
    @ViewState private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename video").font(.system(size: 16, weight: .semibold, design: .rounded))
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.background.color))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.hairlineStrong.color))
                .onSubmit(commit)
            if let error {
                Text(error).font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.danger.color)
            }
            HStack {
                Spacer()
                Button("Cancel", action: dismiss)
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: commit)
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 400)
        .background(Theme.surface.color)
        .foregroundStyle(Theme.text.color)
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
        .onAppear { name = item.title }
    }

    private func commit() {
        do {
            try library.rename(item, to: name)
            dismiss()
        } catch let rename as RenameError {
            error = rename.message
        } catch {
            self.error = error.localizedDescription
        }
    }
}
