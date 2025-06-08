//
//  DirectoryViewModel.swift
//  Mato
//
//  Created by  on 5/22/25.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
class DirectoryViewModel: ObservableObject {
    @Published var items: [DirectoryItem] = []
    @Published var currentDirectory: URL?
    @Published var navigationStack: [URL] = []
    @Published var forwardStack: [URL] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var pathString: String = ""
    @Published var hideHiddenFiles: Bool = true

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

        Task { [weak self, fileManager] in
            do {
                // Get contents on background thread using captured fileManager
                let contents = try fileManager.getContents(of: url)

                // Filter hidden files if needed
                let filteredContents = shouldHideHiddenFiles ?
                contents.filter { !($0.isHidden) } : contents
                
                // sort by date newest first
                let sortedContents = filteredContents.sorted { $0.lastModified > $1.lastModified }

                // Set items directly, no sorting.
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
}
