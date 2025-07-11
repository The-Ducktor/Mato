//
//  DirectoryItem.swift
//  Mato
//
//  Created by on 5/22/25.
//

import Foundation
import UniformTypeIdentifiers
import CoreTransferable
import SwiftUI

public struct DirectoryItem: Identifiable, Hashable, Sendable, Transferable {
    
    public let id: UUID

    var isDirectory: Bool
    var isAppBundle: Bool
    var url: URL
    var name: String = "Unknown"
    var size: Int = 0
    var fileType: UTType = .text
    var lastModified: Date = Date()
    var creationDate: Date = Date()
    var addedDate: Date = Date()
    var dateLastAccessed: Date = Date()
    var isHidden: Bool = false
    
    public init(
        id: UUID = UUID(),
        isDirectory: Bool,
        isAppBundle: Bool,
        url: URL,
        name: String,
        size: Int,
        fileType: UTType,
        lastModified: Date,
        creationDate: Date,
        dateAdded: Date,
        dateLastAccessed: Date = Date(),
        isHidden: Bool
    ) {
        self.id = id
        self.isDirectory = isDirectory
        self.isAppBundle = isAppBundle
        self.url = url
        self.name = name
        self.size = size
        self.fileType = fileType
        self.lastModified = lastModified
        self.creationDate = creationDate
        self.isHidden = isHidden
        self.addedDate = dateAdded
        self.dateLastAccessed = dateLastAccessed
        
    }
    
    var sortKeyName: String { name.localizedCaseInsensitiveCompare("") == .orderedSame ? url.lastPathComponent : name }
    
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

    public static func == (lhs: DirectoryItem, rhs: DirectoryItem) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static let byNameAscending = KeyPathComparator<DirectoryItem>(\DirectoryItem.name, order: .forward)
    static let byNameDescending = KeyPathComparator<DirectoryItem>(\DirectoryItem.name, order: .reverse)
    static let bySizeAscending = KeyPathComparator<DirectoryItem>(\DirectoryItem.size, order: .forward)
    static let bySizeDescending = KeyPathComparator<DirectoryItem>(\DirectoryItem.size, order: .reverse)
    static let byKindAscending = KeyPathComparator<DirectoryItem>(\DirectoryItem.fileTypeDescription, order: .forward)
    static let byKindDescending = KeyPathComparator<DirectoryItem>(\DirectoryItem.fileTypeDescription, order: .reverse)
    static let byModifiedAscending = KeyPathComparator<DirectoryItem>(\DirectoryItem.lastModified, order: .forward)
    static let byModifiedDescending = KeyPathComparator<DirectoryItem>(\DirectoryItem.lastModified, order: .reverse)
}
