import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ImageIcon: View {
    @Binding var item: DirectoryItem
    var isPlayable: Bool = false

    @State private var thumbnail: NSImage?
    @State private var isLoading = false

    // Shared loader — its NSCache (500 items / 100 MB) is shared across all cells.
    private static let sharedLoader = SimpleThumbnailLoader()

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(3)
            } else {
                ZStack {
                    Image(nsImage: ImageIcon.cachedWorkspaceIcon(for: item.url))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(isLoading ? 0.5 : 1.0)

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
        // .task(id:) automatically cancels and restarts when item.id changes,
        // and cancels when the view disappears — no manual Task tracking needed.
        .task(id: item.id) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        guard !item.isDirectory && !item.isTextBasedFile else { return }

        isLoading = true
        defer {
            // Re-enter main actor to clear the loading flag.
            // (This defer runs in the .task context, which is @MainActor.)
            isLoading = false
        }

        let options = SimpleThumbnailLoader.ThumbnailOptions(
            size: CGSize(width: 128, height: 128),
            scale: 2.0,
            maintainAspectRatio: true
        )

        do {
            // generateThumbnail is @concurrent — this call hops off the main
            // actor onto the cooperative thread pool. QuickLook decode never
            // blocks scrolling or any other UI work.
            let loaded = try await Self.sharedLoader.generateThumbnail(for: item.url, options: options)

            // Back on the main actor after the await returns.
            thumbnail = loaded
        } catch {
            // Cancellation or QuickLook failure — keep the workspace icon placeholder.
        }
    }
}

extension ImageIcon {
    // Shared icon cache to avoid redundant NSWorkspace calls
    private static let iconCache = NSCache<NSURL, NSImage>()

    static func cachedWorkspaceIcon(for url: URL) -> NSImage {
        if let cached = iconCache.object(forKey: url as NSURL) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        iconCache.setObject(icon, forKey: url as NSURL)
        return icon
    }
}

extension DirectoryItem {
    var isTextBasedFile: Bool {
        return fileType.conforms(to: .text) ||
               fileType.conforms(to: .sourceCode) ||
               fileType.conforms(to: .script) ||
               fileType.conforms(to: .plainText) ||
               fileType.conforms(to: .json) ||
               fileType.conforms(to: .xml) ||
               fileType.conforms(to: .yaml)
    }
}
