
import SwiftUI
import UniformTypeIdentifiers
import os

// MARK: - Shared NSItemProvider URL loading

extension NSItemProvider {
    /// Loads all file URLs from a drag-and-drop item provider.
    /// Handles the encodings produced by SwiftUI drag sources:
    ///   1. A bare `URL` value (via `loadObject`)
    ///   2. An `NSKeyedArchiver`-encoded array of `NSURL`s (multi-select)
    ///   3. An `NSKeyedArchiver`-encoded single `NSURL`
    @MainActor
    func loadFileURLs() async throws -> [URL] {
        // Try the modern sandbox-safe API first — returns security-scoped URLs
        if let url = try? await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<URL?, Error>) in
            loadObject(ofClass: NSURL.self) { object, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: object as? URL)
            }
        }), Self.isValidFileURL(url) {
            return [url]
        }

        // Fall back to the classic loadItem API for multi-select payloads
        return try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                if let url = data as? URL, Self.isValidFileURL(url) {
                    continuation.resume(returning: [url])
                    return
                }

                if let data = data as? Data {
                    // Multi-select case: array of NSURLs archived by SwiftUI
                    if let urls = try? NSKeyedUnarchiver.unarchivedObject(
                        ofClasses: [NSArray.self, NSURL.self], from: data) as? [URL] {
                        let valid = urls.filter { Self.isValidFileURL($0) }
                        if !valid.isEmpty {
                            continuation.resume(returning: valid)
                            return
                        }
                    }
                    // Single URL archived by NSKeyedArchiver
                    if let url = try? NSKeyedUnarchiver.unarchivedObject(
                        ofClass: NSURL.self, from: data) as? URL,
                       Self.isValidFileURL(url) {
                        continuation.resume(returning: [url])
                        return
                    }
                }

                continuation.resume(throwing: NSError(
                    domain: "InvalidData", code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Could not decode URL from drag data"]
                ))
            }
        }
    }

    // ponytail: rejects garbage URLs that cause NUL-embedded paths
    private static func isValidFileURL(_ url: URL) -> Bool {
        url.isFileURL && !url.path.isEmpty && !url.path.contains("\0")
    }
}

// MARK: - Drop Delegates

struct DirectoryDropDelegate: DropDelegate {
    let viewModel: DirectoryViewModel
    private let log = Logger(subsystem: "com.mato.app", category: "drop")

    func performDrop(info: DropInfo) -> Bool {
        let itemProviders = info.itemProviders(for: [.fileURL])
        guard !itemProviders.isEmpty else { return false }

        Task { @MainActor in
            var seenURLs = Set<String>()
            var sourceURLs: [URL] = []
            
            log.debug("DROP DEBUG: Got \(itemProviders.count) item providers")
            
            for (index, itemProvider) in itemProviders.enumerated() {
                let urls = try? await itemProvider.loadFileURLs()
                if let urls = urls {
                    log.debug("  Provider [\(index)] returned \(urls.count) URLs:")
                    for url in urls {
                        log.debug("    - \(url.lastPathComponent, privacy: .public)")
                        // Use the absolute path as the unique identifier
                        let path = url.path
                        if !seenURLs.contains(path) {
                            seenURLs.insert(path)
                            sourceURLs.append(url)
                        }
                    }
                }
            }
            
            log.debug("Final unique URLs: \(sourceURLs.count)")
            for url in sourceURLs {
                log.debug("  - \(url.lastPathComponent, privacy: .public)")
            }
            
            if !sourceURLs.isEmpty, let currentDirectory = viewModel.currentDirectory {
                viewModel.moveFiles(from: sourceURLs, to: currentDirectory)
            }
        }

        return true
    }
}

struct ItemDropDelegate: DropDelegate {
    let item: DirectoryItem
    let viewModel: DirectoryViewModel
    private let log = Logger(subsystem: "com.mato.app", category: "drop")

    func performDrop(info: DropInfo) -> Bool {
        guard item.isDirectory else {
            return false
        }

        let itemProviders = info.itemProviders(for: [.fileURL])
        guard !itemProviders.isEmpty else { return false }

        Task { @MainActor in
            var seenURLs = Set<String>()
            var sourceURLs: [URL] = []
            
            log.debug("ITEM DROP DEBUG: Got \(itemProviders.count) item providers")
            
            for (index, itemProvider) in itemProviders.enumerated() {
                let urls = try? await itemProvider.loadFileURLs()
                if let urls = urls {
                    log.debug("  Provider [\(index)] returned \(urls.count) URLs:")
                    for url in urls {
                        log.debug("    - \(url.lastPathComponent, privacy: .public)")
                        // Use the absolute path as the unique identifier
                        let path = url.path
                        if !seenURLs.contains(path) {
                            seenURLs.insert(path)
                            sourceURLs.append(url)
                        }
                    }
                }
            }
            
            log.debug("Final unique URLs: \(sourceURLs.count)")
            for url in sourceURLs {
                log.debug("  - \(url.lastPathComponent, privacy: .public)")
            }
            
            if !sourceURLs.isEmpty {
                viewModel.moveFiles(from: sourceURLs, to: item.url)
            }
        }

        return true
    }
}
