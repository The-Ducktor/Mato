//
//  FileManagerService.swift
//  Mato
//
//  Created by on 5/22/25.
//

import Foundation
import UniformTypeIdentifiers
import AppKit

/// Actor to manage task cancellation safely in Swift 6
private actor TaskCancellationManager: Sendable {
    private var activeTasks: [URL: Task<Void, Never>] = [:]
    
    func cancelPendingOperations(for directory: URL) {
        activeTasks[directory]?.cancel()
        activeTasks.removeValue(forKey: directory)
    }
    
    func trackTask(_ task: Task<Void, Never>, for directory: URL) {
        activeTasks[directory] = task
    }
}

final class FileManagerService: @unchecked Sendable {
    static let shared = FileManagerService()
    private let fileManager = FileManager.default
    private nonisolated let taskManager = TaskCancellationManager()
    
    private init() {}
    
    func getDownloadsDirectory() -> URL? {
        return fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }
    
    // Cancel any pending operations for a specific directory
    func cancelPendingOperations(for directory: URL) {
        // Note: This is non-blocking as it's an actor call
        Task.detached { [taskManager] in
            await taskManager.cancelPendingOperations(for: directory)
        }
    }
    
    func getContents(of directory: URL) async throws -> [DirectoryItem] {
        // Cancel any previous request for this directory
        await taskManager.cancelPendingOperations(for: directory)
        
        let task = Task.detached(priority: .userInitiated) { [self, fileManager] in
            let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [
                .isDirectoryKey,
                .fileSizeKey,
                .contentTypeKey,
                .contentModificationDateKey,
                .creationDateKey,
                .isHiddenKey,
                .addedToDirectoryDateKey,
                .isApplicationKey,
                .nameKey
            ])

            var items: [DirectoryItem] = []
            // Process items with lower priority to keep UI responsive
            for url in contents {
                try Task.checkCancellation()
                do {
                    let resourceValues = try url.resourceValues(forKeys: [
                        .isDirectoryKey,
                        .fileSizeKey,
                        .contentTypeKey,
                        .contentModificationDateKey,
                        .creationDateKey,
                        .isHiddenKey,
                        .addedToDirectoryDateKey,
                        .isApplicationKey,
                        .nameKey
                    ])
                    let item = self.makeDirectoryItem(from: url, with: resourceValues)
                    items.append(item)
                } catch {
                    print("Error getting attributes for \(url): \(error)")
                }
            }
            return items
        }
        
        // Track the task for cancellation
        await taskManager.trackTask(Task { _ = try? await task.value }, for: directory)
        
        return try await task.value
    }
    
    @MainActor
    func openFile(at url: URL) {
        NSWorkspace.shared.open(url)
    }
    
    // Now executes file operations in the background using detached tasks.
    // Move or copy files to a destination directory
    func moveItems(from sourceURLs: [URL], to destinationDirectory: URL, copy: Bool = false) async throws -> Bool {
        await Task.detached(priority: .userInitiated) {
            var success = true
            let fm = FileManager.default

            for sourceURL in sourceURLs {
                let destinationURL = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)

                do {
                    if fm.fileExists(atPath: destinationURL.path) {
                        print("File already exists at destination: \(destinationURL.path)")
                        continue
                    }

                    if copy {
                        try fm.copyItem(at: sourceURL, to: destinationURL)
                    } else {
                        try fm.moveItem(at: sourceURL, to: destinationURL)
                    }
                } catch {
                    print("Error moving/copying \(sourceURL) to \(destinationURL): \(error)")
                    success = false
                }
            }
            return success
        }.value
    }

    func getDirectoryItem(for url: URL) async throws -> DirectoryItem {
        return try await Task.detached(priority: .userInitiated) { [self] in
            let resourceValues = try url.resourceValues(forKeys: [
                .isDirectoryKey,
                .fileSizeKey,
                .contentTypeKey,
                .contentModificationDateKey,
                .creationDateKey,
                .isHiddenKey,
                .addedToDirectoryDateKey,
                .isApplicationKey,
                .nameKey
            ])
            return self.makeDirectoryItem(from: url, with: resourceValues)
        }.value
    }

    func moveFile(from sourceURL: URL, to destinationURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) { [fileManager] in
            let destinationPath = destinationURL.appendingPathComponent(sourceURL.lastPathComponent)
            try fileManager.moveItem(at: sourceURL, to: destinationPath)
        }.value
    }
    private func makeDirectoryItem(from url: URL, with resourceValues: URLResourceValues) -> DirectoryItem {
        var isDirectory = resourceValues.isDirectory ?? false
        var fileType = resourceValues.contentType ?? UTType.data
        let fileName = resourceValues.name ?? url.lastPathComponent
        let fileSize = resourceValues.fileSize ?? 0
        let modificationDate = resourceValues.contentModificationDate ?? Date.distantPast
        let creationDate = resourceValues.creationDate ?? Date.distantPast
        let addedDate = resourceValues.addedToDirectoryDate ?? creationDate
        let isHidden = (resourceValues.isHidden ?? false) || fileName.hasPrefix(".")
        let isAppBundle = (resourceValues.isApplication ?? false) || url.pathExtension == "app"

        if isAppBundle {
            isDirectory = false
            fileType = .application
        }

        return DirectoryItem(
            isDirectory: isDirectory,
            isAppBundle: isAppBundle,
            url: url,
            name: fileName,
            size: fileSize,
            fileType: fileType,
            lastModified: modificationDate,
            creationDate: creationDate,
            dateAdded: addedDate,
            isHidden: isHidden
        )
    }

}
