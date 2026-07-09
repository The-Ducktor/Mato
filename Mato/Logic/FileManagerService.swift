//
//  FileManagerService.swift
//  Mato
//
//  Created by on 5/22/25.
//

import Foundation
import UniformTypeIdentifiers
import AppKit
import os

private protocol AnyTask: Sendable {
    func cancel()
}
extension Task: AnyTask {}

/// Actor to manage task cancellation safely in Swift 6
private actor TaskCancellationManager: Sendable {
    private var activeTasks: [URL: any AnyTask] = [:]

    func cancelPendingOperations(for directory: URL) {
        activeTasks[directory]?.cancel()
        activeTasks.removeValue(forKey: directory)
    }

    func trackTask(_ task: some AnyTask, for directory: URL) {
        activeTasks[directory] = task
    }
}

final class FileManagerService: @unchecked Sendable {
    static let shared = FileManagerService()
    private let fileManager = FileManager.default
    private let log = Logger(subsystem: "com.mato", category: "filemanager")
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
            // contentsOfDirectory(includingPropertiesForKeys:) pre-populates the URL
            // resource cache for each key — calling url.resourceValues(forKeys:) again
            // per file would re-fetch the same data from disk unnecessarily.
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
            for url in contents {
                try Task.checkCancellation()
                do {
                    // Read from the already-populated URL resource cache.
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
                    log.error("Error getting attributes for \(url, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            return items
        }
        
        // Track the real task so cancellation actually works.
        await taskManager.trackTask(task, for: directory)
        
        return try await task.value
    }
    
    @MainActor
    func openFile(at url: URL) {
        NSWorkspace.shared.open(url)
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
