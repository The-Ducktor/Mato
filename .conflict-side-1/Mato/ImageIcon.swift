import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ImageIcon: View {
    @Binding var item: DirectoryItem
    @StateObject private var thumbnailLoader = SimpleThumbnailLoader()
    @State private var thumbnail: NSImage?
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(2)
                    
                  
            } else if isLoading {
                ProgressView()
                    .scaleEffect(0.5)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .task(id: item.id) {
            await loadThumbnail()
        }
    }
    
    private func loadThumbnail() async {
        // Skip thumbnail generation for directories or text-based files
        guard !item.isDirectory && !item.isTextBasedFile else {
            thumbnail = NSWorkspace.shared.icon(forFile: item.url.path)
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let options = SimpleThumbnailLoader.ThumbnailOptions(
                size: CGSize(width: 256, height: 256),
                scale: 2.0,
                maintainAspectRatio: true
            )
            thumbnail = try await thumbnailLoader.generateThumbnail(for: item.url, options: options)
        } catch {
            // Fallback to system icon on error
            thumbnail = NSWorkspace.shared.icon(forFile: item.url.path)
        }
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
 
