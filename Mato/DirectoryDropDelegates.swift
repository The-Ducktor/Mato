
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drop Delegates

struct DirectoryDropDelegate: DropDelegate {
    let viewModel: DirectoryViewModel

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [.fileURL]).first else {
            return false
        }

        item.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
            if let error = error {
                print("Error loading item: \(error)")
                return
            }
            
            let url: URL?
            
            // Try to handle different data types
            if let directURL = data as? URL {
                url = directURL
            } else if let urlData = data as? Data {
                // Try NSKeyedArchiver format first
                if let archivedURL = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSURL.self, from: urlData) as? URL {
                    url = archivedURL
                } else if let archivedURLs = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSURL.self], from: urlData) as? [URL],
                          let firstURL = archivedURLs.first {
                    url = firstURL
                } else {
                    // Fallback to data representation
                    url = URL(dataRepresentation: urlData, relativeTo: nil)
                }
            } else {
                url = nil
            }
            
            guard let finalURL = url else { return }

            Task { @MainActor in
                if let currentDirectory = viewModel.currentDirectory {
                    viewModel.moveFile(from: finalURL, to: currentDirectory)
                }
            }
        }

        return true
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
                if let url = try? await loadFileURL(from: itemProvider) {
                    sourceURLs.append(url)
                }
            }
            
            if !sourceURLs.isEmpty {
                viewModel.moveFiles(from: sourceURLs, to: item.url)
            }
        }

        return true
    }
    
    private func loadFileURL(from provider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                // Handle different data types
                if let url = data as? URL {
                    continuation.resume(returning: url)
                    return
                }
                
                if let data = data as? Data {
                    // Try to unarchive the URL from NSKeyedArchiver format
                    if let url = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSURL.self, from: data) as? URL {
                        continuation.resume(returning: url)
                        return
                    }
                    
                    // Try to unarchive an array of URLs
                    if let urls = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSURL.self], from: data) as? [URL],
                       let firstURL = urls.first {
                        continuation.resume(returning: firstURL)
                        return
                    }
                    
                    // Fallback: try URL(dataRepresentation:)
                    if let url = URL(dataRepresentation: data, relativeTo: nil) {
                        continuation.resume(returning: url)
                        return
                    }
                }
                
                continuation.resume(throwing: NSError(domain: "InvalidData", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not decode URL from drag data"]))
            }
        }
    }
}
