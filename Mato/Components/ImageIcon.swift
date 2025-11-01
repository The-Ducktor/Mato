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
            } else if isLoading {
                ZStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(0.5)
                    ProgressView()
                        .controlSize(.small)
                }
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
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
        // Cancel any existing load task
        loadTask?.cancel()
        
        // Skip thumbnail generation for directories or text-based files
        guard !item.isDirectory && !item.isTextBasedFile else {
            thumbnail = NSWorkspace.shared.icon(forFile: item.url.path)
            return
        }
        
        // Create a new task that can be cancelled
        loadTask = Task {
            isLoading = true
            defer { isLoading = false }
            
            do {
                let options = SimpleThumbnailLoader.ThumbnailOptions(
                    size: CGSize(width: 128, height: 128), // Reduced size for grid view
                    scale: 2.0,
                    maintainAspectRatio: true
                )
                let url = item.url
                
                // Check if task was cancelled
                try Task.checkCancellation()
                
                // Use shared loader for better cache hit rate
                let loadedThumbnail = try await Self.sharedLoader.generateThumbnail(for: url, options: options)
                
                // Check again before updating state
                try Task.checkCancellation()
                
                thumbnail = loadedThumbnail
            } catch is CancellationError {
                // Task was cancelled, do nothing
            } catch {
                // Fallback to system icon on error
                thumbnail = NSWorkspace.shared.icon(forFile: item.url.path)
            }
        }
        
        await loadTask?.value
    }
}

extension DirectoryItem {
    var isTextBasedFile: Bool {
        // Get the UTType for the file
        guard let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            // Fallback to extension-based check
            return isTextBasedByExtension
        }
        
        // Check if the file conforms to text, source code, or script types
        return contentType.conforms(to: UTType.text) ||
               contentType.conforms(to: UTType.sourceCode) ||
               contentType.conforms(to: UTType.script) ||
               contentType.conforms(to: UTType.plainText) ||
               contentType.conforms(to: UTType.json) ||
               contentType.conforms(to: UTType.xml) ||
               contentType.conforms(to: UTType.yaml)
    }
    
    private var isTextBasedByExtension: Bool {
        let textExtensions = [
            // Programming languages
            "swift", "py", "java", "js", "ts", "jsx", "tsx", "cpp", "c", "h", "hpp",
            "cs", "rb", "go", "rs", "php", "kt", "scala", "m", "mm",
            // Scripting
            "sh", "bash", "zsh", "fish", "pl", "lua",
            // Web
            "html", "css", "scss", "sass", "less", "vue", "svelte",
            // Data/Config
            "json", "xml", "yaml", "yml", "toml", "ini", "conf", "config",
            // Documentation
            "md", "txt", "log", "csv", "tsv", "rst",
            // Other
            "sql", "gradle", "properties", "env"
        ]
        return textExtensions.contains(url.pathExtension.lowercased())
    }
}
 
