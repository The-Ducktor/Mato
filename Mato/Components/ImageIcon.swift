import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ImageIcon: View {
    @Binding var item: DirectoryItem
    var isPlayable: Bool = false
    
    @State private var thumbnail: NSImage?
    @State private var isLoading = false
    @State private var loadTask: Task<Void, Never>?
    
    // Shared thumbnail loader for better caching
    private static let sharedLoader = SimpleThumbnailLoader()
    
    var body: some View {
        Group {
            if let thumbnail = thumbnail {
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
        .task(id: item.id) {
            await loadThumbnail()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }
    
    private func loadThumbnail() async {
        // Skip thumbnail generation for directories or text-based files
        guard !item.isDirectory && !item.isTextBasedFile else {
            return
        }
        
        // Cancel existing task if any
        loadTask?.cancel()
        
        loadTask = Task {
            isLoading = true
            defer { isLoading = false }
            
            do {
                let options = SimpleThumbnailLoader.ThumbnailOptions(
                    size: CGSize(width: 128, height: 128),
                    scale: 2.0,
                    maintainAspectRatio: true
                )
                
                try Task.checkCancellation()
                let loadedThumbnail = try await Self.sharedLoader.generateThumbnail(for: item.url, options: options)
                
                try Task.checkCancellation()
                await MainActor.run {
                    self.thumbnail = loadedThumbnail
                }
            } catch {
                // Keep default icon on error
            }
        }
        
        await loadTask?.value
    }
}

extension ImageIcon {
    // Shared icon cache to avoid redundant NSWorkspace calls
    private static let iconCache = NSCache<NSURL, NSImage>()
    
    static func cachedWorkspaceIcon(for url: URL) -> NSImage {
        if let cached = iconCache.object(forKey: url as NSURL) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache.setObject(icon, forKey: url as NSURL)
        return icon
    }
}

extension DirectoryItem {
    var isTextBasedFile: Bool {
        // Use the already-fetched fileType instead of making another disk access
        return fileType.conforms(to: .text) ||
               fileType.conforms(to: .sourceCode) ||
               fileType.conforms(to: .script) ||
               fileType.conforms(to: .plainText) ||
               fileType.conforms(to: .json) ||
               fileType.conforms(to: .xml) ||
               fileType.conforms(to: .yaml)
    }
}

