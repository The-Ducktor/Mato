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
                    .creationDateKey
                ])
                
                let isDirectory = resourceValues.isDirectory ?? false
                let fileName = url.lastPathComponent
                let fileSize = resourceValues.fileSize
                let fileType = resourceValues.contentType
                let modificationDate = resourceValues.contentModificationDate
                let creationDate = resourceValues.creationDate
                let isHidden = (resourceValues.isHidden ?? false) || fileName.hasPrefix(".")
                
                
                
                return DirectoryItem(
                    isDirectory: isDirectory,
                    url: url,
                    name: fileName,
                    size: fileSize,
                    fileType: fileType,
                    lastModified: modificationDate,
                    creationDate: creationDate,
                    isHidden: isHidden
                )
            } catch {
                print("Error getting attributes for \(url): \(error)")
                return nil
            }
        }
    }
    
    func openFile(at url: URL) {
        NSWorkspace.shared.open(url)
    }
}
