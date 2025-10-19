
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drop Delegates

struct DirectoryDropDelegate: DropDelegate {
    let viewModel: DirectoryViewModel

    func performDrop(info: DropInfo) -> Bool {
        let itemProviders = info.itemProviders(for: [.fileURL])
        guard !itemProviders.isEmpty else { return false }

        Task { @MainActor in
            var sourceURLs: [URL] = []
            
            for itemProvider in itemProviders {
                let urls = try? await loadFileURLs(from: itemProvider)
                if let urls = urls {
                    sourceURLs.append(contentsOf: urls)
                }
            }
            
            // Deduplicate URLs - each provider may contain the full array
            let uniqueURLs = Array(Set(sourceURLs))
            
            if !uniqueURLs.isEmpty, let currentDirectory = viewModel.currentDirectory {
                viewModel.moveFiles(from: uniqueURLs, to: currentDirectory)
            }
        }

        return true
    }
    
    private func loadFileURLs(from provider: NSItemProvider) async throws -> [URL] {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                // Handle different data types
                if let url = data as? URL {
                    continuation.resume(returning: [url])
                    return
                }
                
                if let data = data as? Data {
                    // Try to unarchive an ARRAY of URLs first (multi-select case)
                    if let urls = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSURL.self], from: data) as? [URL] {
                        continuation.resume(returning: urls)
                        return
                    }
                    
                    // Try to unarchive a single URL
                    if let url = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSURL.self, from: data) as? URL {
                        continuation.resume(returning: [url])
                        return
                    }
                    
                    // Fallback: try URL(dataRepresentation:)
                    if let url = URL(dataRepresentation: data, relativeTo: nil) {
                        continuation.resume(returning: [url])
                        return
                    }
                }
                
                continuation.resume(throwing: NSError(domain: "InvalidData", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not decode URL from drag data"]))
            }
        }
    }
}

struct ItemDropDelegate: DropDelegate {
    let item: DirectoryItem
    let viewModel: DirectoryViewModel

    func performDrop(info: DropInfo) -> Bool {
        guard item.isDirectory else {
            return false
        }

        let itemProviders = info.itemProviders(for: [.fileURL])
        guard !itemProviders.isEmpty else { return false }

        Task { @MainActor in
            var sourceURLs: [URL] = []
            
            for itemProvider in itemProviders {
                let urls = try? await loadFileURLs(from: itemProvider)
                if let urls = urls {
                    sourceURLs.append(contentsOf: urls)
                }
            }
            
            // Deduplicate URLs - each provider may contain the full array
            let uniqueURLs = Array(Set(sourceURLs))
            
            if !uniqueURLs.isEmpty {
                viewModel.moveFiles(from: uniqueURLs, to: item.url)
            }
        }

        return true
    }
    
    private func loadFileURLs(from provider: NSItemProvider) async throws -> [URL] {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                // Handle different data types
                if let url = data as? URL {
                    continuation.resume(returning: [url])
                    return
                }
                
                if let data = data as? Data {
                    // Try to unarchive an ARRAY of URLs first (multi-select case)
                    if let urls = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSURL.self], from: data) as? [URL] {
                        continuation.resume(returning: urls)
                        return
                    }
                    
                    // Try to unarchive a single URL
                    if let url = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSURL.self, from: data) as? URL {
                        continuation.resume(returning: [url])
                        return
                    }
                    
                    // Fallback: try URL(dataRepresentation:)
                    if let url = URL(dataRepresentation: data, relativeTo: nil) {
                        continuation.resume(returning: [url])
                        return
                    }
                }
                
                continuation.resume(throwing: NSError(domain: "InvalidData", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not decode URL from drag data"]))
            }
        }
    }
}
