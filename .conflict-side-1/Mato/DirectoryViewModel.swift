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

    // Rename alert state
    @Published var showingRenameAlert = false
    @Published var renameText = ""
    @Published var itemToRename: DirectoryItem? = nil

    private let fileManager = FileManagerService.shared

    // Directory watching service
    private var directoryWatcherService: DirectoryWatcherService?

    init() {
        // Use default folder from settings
        let defaultURL = SettingsModel.shared.defaultFolderURL
        currentDirectory = defaultURL
        navigationStack = [defaultURL]
        loadDirectory(at: defaultURL)
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

        // Stop previous watcher by releasing the service (handled by ARC)
        directoryWatcherService = nil

        // Start watching new directory
        directoryWatcherService = DirectoryWatcherService(url: url, queue: .main) { [weak self] in
            Task { @MainActor in
                self?.refreshCurrentDirectory()
            }
        }

        // Capture the current state we need in the background task
        let shouldHideHiddenFiles = hideHiddenFiles

        Task { [weak self, fileManager] in
            do {
                // Get contents on background thread using captured fileManager
                let contents = try await fileManager.getContents(of: url)

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
        if item.isDirectory && !item.isAppBundle {
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

    // MARK: - Context Menu Actions

    func openSelectedItems(_ ids: Set<DirectoryItem.ID>) {
        for id in ids {
            if let item = getItem(id) {
                openItem(item)
            }
        }
    }

    func openInTerminal(_ ids: Set<DirectoryItem.ID>) {
        for id in ids {
            guard let item = getItem(id) else { continue }
            let targetURL =
                item.isDirectory
                ? item.url : item.url.deletingLastPathComponent()

            let script = """
                    tell application "Terminal"
                        activate
                        do script "cd '\(targetURL.path.replacingOccurrences(of: "'", with: "\\'"))'"
                    end tell
                """

            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(nil)
            }
        }
    }

    func canOpenInTerminal(_ ids: Set<DirectoryItem.ID>) -> Bool {
        return !ids.isEmpty
    }

    func startRename(_ id: DirectoryItem.ID) {
        guard let item = getItem(id) else { return }
        itemToRename = item
        renameText = item.name
        showingRenameAlert = true
    }

    func performRename() {
        guard let item = itemToRename else { return }

        let newURL = item.url.deletingLastPathComponent()
            .appendingPathComponent(renameText)

        do {
            try FileManager.default.moveItem(at: item.url, to: newURL)
            refreshCurrentDirectory()
        } catch {
            print("Failed to rename: \(error)")
        }

        itemToRename = nil
        renameText = ""
    }

    func copyItems(_ ids: Set<DirectoryItem.ID>) {
        let urls = getURLs(from: ids)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSPasteboardWriting])
    }

    func cutItems(_ ids: Set<DirectoryItem.ID>) {
        let urls = getURLs(from: ids)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSPasteboardWriting])

        pasteboard.setData(
            Data(),
            forType: NSPasteboard.PasteboardType(
                "com.apple.pasteboard.promised-file-url"
            )
        )
    }

    func pasteItems() {
        guard let currentDir = currentDirectory else { return }

        let pasteboard = NSPasteboard.general
        guard
            let urls = pasteboard.readObjects(forClasses: [NSURL.self])
                as? [URL]
        else { return }

        for url in urls {
            let destinationURL = currentDir.appendingPathComponent(
                url.lastPathComponent
            )

            do {
                try FileManager.default.copyItem(at: url, to: destinationURL)
            } catch {
                print("Failed to paste: \(error)")
            }
        }

        refreshCurrentDirectory()
    }

    func hasItemsInPasteboard() -> Bool {
        let pasteboard = NSPasteboard.general
        return pasteboard.canReadObject(forClasses: [NSURL.self], options: nil)
    }

    func copyPaths(_ ids: Set<DirectoryItem.ID>) {
        let paths = ids.compactMap { id in
            getItem(id)?.url.path
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths, forType: .string)
    }

    func copyAsPathname(_ ids: Set<DirectoryItem.ID>) {
        let paths = ids.compactMap { id in
            getItem(id)?.url.standardizedFileURL.path
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths, forType: .string)
    }

    func copyAlias(_ id: DirectoryItem.ID) {
        guard let item = getItem(id) else { return }

        do {
            let aliasData = try item.url.bookmarkData(
                options: .suitableForBookmarkFile,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(
                aliasData,
                forType: NSPasteboard.PasteboardType("com.apple.alias-file")
            )
        } catch {
            print("Failed to create alias: \(error)")
        }
    }



    func showInFinder(_ ids: Set<DirectoryItem.ID>) {
        let urls = getURLs(from: ids)
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func showPackageContents(_ item: DirectoryItem) {
        if item.isDirectory
            || item.url.pathExtension.lowercased().contains("app")
        {
            NSWorkspace.shared.selectFile(
                nil,
                inFileViewerRootedAtPath: item.url.path
            )
        }
    }

    func canCompress(_ ids: Set<DirectoryItem.ID>) -> Bool {
        return !ids.isEmpty
    }

    func getCompressionName(_ ids: Set<DirectoryItem.ID>) -> String {
        if ids.count == 1, let item = getItem(ids.first!) {
            return item.name
        }
        return "\(ids.count) items"
    }

    func compressItems(_ ids: Set<DirectoryItem.ID>) {
        let urls = getURLs(from: ids)

        let task = Process()
        task.launchPath = "/usr/bin/ditto"
        task.arguments =
            ["-c", "-k", "--sequesterRsrc", "--keepParent"] + urls.map(\.path)
            + ["Archive.zip"]
        task.currentDirectoryPath =
            currentDirectory?.path
            ?? FileManager.default.currentDirectoryPath

        do {
            try task.run()
            task.waitUntilExit()
            refreshCurrentDirectory()
        } catch {
            print("Failed to compress: \(error)")
        }
    }

    func canCreateAlias(_ ids: Set<DirectoryItem.ID>) -> Bool {
        return !ids.isEmpty
    }

    func makeAlias(_ ids: Set<DirectoryItem.ID>) {
        for id in ids {
            guard let item = getItem(id) else { continue }

            let aliasURL = item.url.appendingPathExtension("alias")

            do {
                let aliasData = try item.url.bookmarkData(
                    options: .suitableForBookmarkFile,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                try aliasData.write(to: aliasURL)
            } catch {
                print("Failed to create alias: \(error)")
            }
        }

        refreshCurrentDirectory()
    }

    func moveToTrash(_ ids: Set<DirectoryItem.ID>) {
        let urls = getURLs(from: ids)

        for url in urls {
            do {
                try FileManager.default.trashItem(
                    at: url,
                    resultingItemURL: nil
                )
            } catch {
                print("Failed to move to trash: \(error)")
            }
        }

        refreshCurrentDirectory()
    }

    func showServices(_ ids: Set<DirectoryItem.ID>) {
        _ = getURLs(from: ids)
    }

    // MARK: - Helper Methods

    func getItem(_ id: DirectoryItem.ID) -> DirectoryItem? {
        return items.first { $0.id == id }
    }

    func getURLs(from ids: Set<DirectoryItem.ID>) -> [URL] {
        return ids.compactMap { id in
            getItem(id)?.url
        }
    }

    func moveFile(from sourceURL: URL, to destinationURL: URL) {
        Task {
            do {
                try await fileManager.moveFile(from: sourceURL, to: destinationURL)
                refreshCurrentDirectory()
            } catch {
                errorMessage = "Error moving file: \(error.localizedDescription)"
            }
        }
    }

    func moveFiles(from sourceURLs: [URL], to destinationURL: URL) {
        Task {
            do {
                for sourceURL in sourceURLs {
                    try await fileManager.moveFile(from: sourceURL, to: destinationURL)
                }
                refreshCurrentDirectory()
            } catch {
                errorMessage = "Error moving files: \(error.localizedDescription)"
            }
        }
    }

    func handleDrop(info: DropInfo) -> Bool {
        let itemProviders = info.itemProviders(for: [.fileURL])
        guard !itemProviders.isEmpty else { return false }

        Task { @MainActor in
            var urls: [URL] = []
            
            for itemProvider in itemProviders {
                if let data = try? await itemProvider.loadItem(forTypeIdentifier: UTType.fileURL.identifier),
                   let urlData = data as? Data,
                   let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                    urls.append(url)
                }
            }
            
            if !urls.isEmpty, let destinationURL = self.currentDirectory {
                self.moveFiles(from: urls, to: destinationURL)
            }
        }
        return true
    }

    // MARK: - Directory Watching
    // (All logic now handled by DirectoryWatcherService)
}
