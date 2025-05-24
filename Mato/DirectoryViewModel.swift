//
//  DirectoryViewModel.swift
//  Mato
//
//  Created by  on 5/22/25.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum SortOption: String, CaseIterable {
    case name = "Name"
    case dateAdded = "Date Added"
    case dateModified = "Date Modified"
    case size = "Size"
    case type = "Type"
}

@MainActor
class DirectoryViewModel: ObservableObject {
    @Published var items: [DirectoryItem] = []
    @Published var currentDirectory: URL?
    @Published var navigationStack: [URL] = []
    @Published var forwardStack: [URL] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var sortOption: SortOption = .dateAdded
    @Published var sortAscending: Bool = false
    @Published var pathString: String = ""
    @Published var hideHiddenFiles: Bool = true
    @Published var sortOrder: [KeyPathComparator<DirectoryItem>] = [
        KeyPathComparator(\DirectoryItem.name, order: .forward)
    ]
    
    private let fileManager = FileManagerService.shared
    
    init() {
        loadDownloadsDirectory()
    }
    
    func loadDownloadsDirectory() {
        guard let downloadsURL = fileManager.getDownloadsDirectory() else {
            self.errorMessage = "Could not locate Downloads directory"
            return
        }
        
        currentDirectory = downloadsURL
        navigationStack = [downloadsURL]
        forwardStack = []
        loadDirectory(at: downloadsURL)
    }
    
    func loadDirectory(at url: URL) {
        isLoading = true
        errorMessage = nil
        
        // Update path string
        pathString = url.path
        
        // Capture the current state we need in the background task
        let shouldHideHiddenFiles = hideHiddenFiles
        let currentSortOrder = sortOrder
        
        Task { [weak self, fileManager] in
            do {
                // Get contents on background thread using captured fileManager
                let contents = try fileManager.getContents(of: url)
                
                // Filter hidden files if needed
                let filteredContents = shouldHideHiddenFiles ?
                    contents.filter { !($0.isHidden ?? false) } : contents
                
                // Sort using KeyPathComparator
                let sortedContents = filteredContents.sorted(using: currentSortOrder)
                
                // Update UI on main actor
                guard let self = self else { return }
                self.items = sortedContents
                self.isLoading = false
                
            } catch {
                // Handle error on main actor
                guard let self = self else { return }
                self.errorMessage = "Error loading directory: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    func openItem(_ item: DirectoryItem) {
        if item.isDirectory {
            // When navigating to a new directory, clear the forward stack
            forwardStack.removeAll()
            
            // Navigate into the directory
            currentDirectory = item.url
            navigationStack.append(item.url)
            loadDirectory(at: item.url)
        } else {
            // Open the file
            fileManager.openFile(at: item.url)
        }
    }
    
    func navigateBack() {
        guard navigationStack.count > 1 else { return }
        
        // Get current directory before removing it from navigation stack
        if let current = currentDirectory {
            // Add current directory to forward stack for future forward navigation
            forwardStack.append(current)
        }
        
        // Remove current directory from navigation stack
        navigationStack.removeLast()
        
        // Go to previous directory
        if let previousDirectory = navigationStack.last {
            currentDirectory = previousDirectory
            loadDirectory(at: previousDirectory)
        }
    }
    
    func navigateForward() {
        guard !forwardStack.isEmpty else { return }
        
        // Get the next directory from the forward stack
        let nextDirectory = forwardStack.removeLast()
        
        // Add it to the navigation stack
        navigationStack.append(nextDirectory)
        currentDirectory = nextDirectory
        loadDirectory(at: nextDirectory)
    }
    
    func canNavigateBack() -> Bool {
        return navigationStack.count > 1
    }
    
    func canNavigateForward() -> Bool {
        return !forwardStack.isEmpty
    }
    
    func navigateToPath(_ path: String) {
        guard !path.isEmpty else { return }
        
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            // Valid directory, navigate to it
            currentDirectory = url
            
            // Reset navigation stack to just this path
            // (since we don't know the hierarchy when manually entering a path)
            navigationStack = [url]
            forwardStack = []
            loadDirectory(at: url)
        } else {
            // Invalid path
            errorMessage = "Invalid directory path"
            
            // Reset displayed path to current directory
            if let current = currentDirectory {
                pathString = current.path
            }
        }
    }
    
    func formatFileSize(_ size: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useBytes]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
    
    // Made this function nonisolated and accept parameters to avoid concurrency issues
    nonisolated func sortItems(_ items: [DirectoryItem],
                              sortOption: SortOption,
                              sortAscending: Bool) -> [DirectoryItem] {
        return Self.sortItemsStatic(items, sortOption: sortOption, sortAscending: sortAscending)
    }
    
    // Static version that can be called from detached tasks
    nonisolated static func sortItemsStatic(_ items: [DirectoryItem],
                                           sortOption: SortOption,
                                           sortAscending: Bool) -> [DirectoryItem] {
        return items.sorted { item1, item2 in
            // Sort by chosen sort option
            switch sortOption {
            case .name:
                let name1 = item1.name?.lowercased() ?? ""
                let name2 = item2.name?.lowercased() ?? ""
                return sortAscending ? name1 < name2 : name1 > name2
                
            case .dateAdded:
                guard let date1 = item1.creationDate, let date2 = item2.creationDate else {
                    return sortAscending
                }
                return sortAscending ? date1 < date2 : date1 > date2
                
            case .dateModified:
                guard let date1 = item1.lastModified, let date2 = item2.lastModified else {
                    return sortAscending
                }
                return sortAscending ? date1 < date2 : date1 > date2
                
            case .size:
                let size1 = item1.size ?? 0
                let size2 = item2.size ?? 0
                return sortAscending ? size1 < size2 : size1 > size2
                
            case .type:
                // For type sorting, group directories together first
                if item1.isDirectory && !item2.isDirectory {
                    return sortAscending
                } else if !item1.isDirectory && item2.isDirectory {
                    return !sortAscending
                }
                
                let type1 = item1.fileType?.localizedDescription?.lowercased() ?? ""
                let type2 = item2.fileType?.localizedDescription?.lowercased() ?? ""
                return sortAscending ? type1 < type2 : type1 > type2
            }
        }
    }
    
    func setSortOption(_ option: SortOption) {
        // If selecting the same option, toggle direction
        if sortOption == option {
            sortAscending.toggle()
        } else {
            sortOption = option
            // Default to ascending for name and type, descending for dates and size
            sortAscending = (option == .name || option == .type)
        }
        
        // Update sortOrder based on sortOption and sortAscending
        updateSortOrder()
        
        // Re-sort current items
        if let currentDir = currentDirectory {
            loadDirectory(at: currentDir)
        }
    }
    
    // New method to update sortOrder based on sortOption and sortAscending
    func updateSortOrder() {
        let order: SortOrder = sortAscending ? .forward : .reverse
        
        switch sortOption {
        case .name:
            sortOrder = [KeyPathComparator(\DirectoryItem.name, order: order)]
        case .dateAdded:
            sortOrder = [KeyPathComparator(\DirectoryItem.creationDate, order: order)]
        case .dateModified:
            sortOrder = [KeyPathComparator(\DirectoryItem.lastModified, order: order)]
        case .size:
            sortOrder = [KeyPathComparator(\DirectoryItem.size, order: order)]
        case .type:
            // For type, we first sort by isDirectory, then by fileType
            sortOrder = sortOrder
            
        }
    }
    
    // Method to handle changes to sortOrder from the Table view
    func applySortOrder(_ newSortOrder: [KeyPathComparator<DirectoryItem>]) {
        sortOrder = newSortOrder
        
        // Try to determine the new sortOption and sortAscending based on the first comparator
        if let firstComparator = newSortOrder.first {
            let isAscending = firstComparator.order == .forward
            
            // Determine which keyPath is being used
            if firstComparator.keyPath == \DirectoryItem.name {
                sortOption = .name
                sortAscending = isAscending
            } else if firstComparator.keyPath == \DirectoryItem.creationDate {
                sortOption = .dateAdded
                sortAscending = isAscending
            } else if firstComparator.keyPath == \DirectoryItem.lastModified {
                sortOption = .dateModified
                sortAscending = isAscending
            } else if firstComparator.keyPath == \DirectoryItem.size {
                sortOption = .size
                sortAscending = isAscending
            } else if firstComparator.keyPath == \DirectoryItem.fileType {
                sortOption = .type
                sortAscending = isAscending
            }
        }
        
        // Re-sort current items
        if let currentDir = currentDirectory {
            loadDirectory(at: currentDir)
        }
    }
}
