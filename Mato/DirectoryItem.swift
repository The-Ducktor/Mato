//
//  DirectoryItem.swift
//  Mato
//
//  Created by on 5/22/25.
//

import Foundation
import UniformTypeIdentifiers
import CoreTransferable

public struct DirectoryItem: Identifiable, Hashable, Sendable, Transferable {
    

    public let id = UUID()
    var isDirectory: Bool
    var url: URL
    var name: String = "Unknown"
    var size: Int = 0
    var fileType: UTType = .text
    var lastModified: Date = Date()
    var creationDate: Date = Date()
    var isHidden: Bool = false
    
    public init(
        isDirectory: Bool,
        url: URL,
        name: String,
        size: Int,
        fileType: UTType,
        lastModified: Date,
        creationDate: Date,
        isHidden: Bool
    ) {
        self.isDirectory = isDirectory
        self.url = url
        self.name = name
        self.size = size
        self.fileType = fileType
        self.lastModified = lastModified
        self.creationDate = creationDate
        self.isHidden = isHidden
    }

    
    var fileTypeDescription: String {
            return fileType.localizedDescription ?? "Unknown"
        }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .fileURL) {
            $0.url.dataRepresentation
        } importing: { data in
            let url = URL(dataRepresentation: data, relativeTo: nil)!
            return try await FileManagerService.shared.getDirectoryItem(for: url)
        }
    }
}
