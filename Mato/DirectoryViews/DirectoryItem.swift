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
    
    /// Stable identity derived from the file's URL path so that
    /// re-loading the same files reuses existing SwiftUI views.
    public var id: String { url.path }

    let isDirectory: Bool
    let isAppBundle: Bool
    let url: URL
    let name: String
    let size: Int
    let fileType: UTType
    let lastModified: Date
    let creationDate: Date
    let addedDate: Date
    let dateLastAccessed: Date
    let isHidden: Bool
    
    /// Pre-formatted date strings — computed once at init instead of
    /// re-formatting on every cell render.
    let formattedLastModified: String
    let formattedCreationDate: String
    let formattedAddedDate: String
    let formattedLastAccessed: String
    
    public init(
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
        
        // Cache formatted dates once
        self.formattedLastModified = Self.formatDate(lastModified)
        self.formattedCreationDate = Self.formatDate(creationDate)
        self.formattedAddedDate = Self.formatDate(dateAdded)
        self.formattedLastAccessed = Self.formatDate(dateLastAccessed)
    }
    
    var sortKeyName: String { name.localizedCaseInsensitiveCompare("") == .orderedSame ? url.lastPathComponent : name }
    
    var fileTypeDescription: String {
        return fileType.localizedDescription ?? "Unknown"
    }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .fileURL) {
            $0.url.dataRepresentation
        } importing: { data in
            guard let url = URL(dataRepresentation: data, relativeTo: nil) else {
                throw CocoaError(.fileReadInvalidFileName)
            }
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
    
    // MARK: - Cached Date Formatting
    
    // Shared formatters for performance
    // These are thread-safe in practice and only read after initialization
    nonisolated(unsafe) private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    /// Formats a date using relative formatting for today/yesterday/tomorrow,
    /// falling back to a standard date+time format for older dates.
    private static func formatDate(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) || calendar.isDateInYesterday(date) || calendar.isDateInTomorrow(date) {
            return Self.relativeDateFormatter.localizedString(for: date, relativeTo: now)
        } else {
            return Self.dateFormatter.string(from: date)
        }
    }
}
