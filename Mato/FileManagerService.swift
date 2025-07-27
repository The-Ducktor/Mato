//
//  FileManagerService.swift
//  Mato
//
//  Created by on 5/22/25.
//

import Foundation
import UniformTypeIdentifiers
import AppKit

@MainActor
class FileManagerService {
    static let shared = FileManagerService()
    private let fileManager = FileManager.default
    
    private init() {}
    
    func getDownloadsDirectory() -> URL? {
        return fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }
    
    func getContents(of directory: URL) throws -> [DirectoryItem] {
        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [
            .isDirectoryKey,
            .fileSizeKey,
            .contentTypeKey,
            .contentModificationDateKey,
            .creationDateKey
        ])
        
        return contents.compactMap { url in
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
                return makeDirectoryItem(from: url, with: resourceValues)
            } catch {
                print("Error getting attributes for \(url): \(error)")
                return nil
            }
        }

    }
    
    func openFile(at url: URL) {
        NSWorkspace.shared.open(url)
    }
    
    // Move or copy files to a destination directory
    func moveItems(from sourceURLs: [URL], to destinationDirectory: URL, copy: Bool = false) async throws -> Bool {
        var success = true
        
        for sourceURL in sourceURLs {
            let destinationURL = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            
            do {
                // Check if an item with the same name already exists
                if fileManager.fileExists(atPath: destinationURL.path) {
                    // Handle conflict (could be expanded to show a confirmation dialog)
                    print("File already exists at destination: \(destinationURL.path)")
                    continue
                }
                
                if copy {
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
                } else {
                    try fileManager.moveItem(at: sourceURL, to: destinationURL)
                }
            } catch {
                print("Error moving/copying \(sourceURL) to \(destinationURL): \(error)")
                success = false
            }
        }
        
        return success
    }

    func getDirectoryItem(for url: URL) throws -> DirectoryItem {
       
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
        return makeDirectoryItem(from: url, with: resourceValues)

    }

    func moveFile(from sourceURL: URL, to destinationURL: URL) throws {
        let destinationPath = destinationURL.appendingPathComponent(sourceURL.lastPathComponent)
        try fileManager.moveItem(at: sourceURL, to: destinationPath)
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
