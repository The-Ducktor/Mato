//
//  DirectoryViewModel.swift
//  Mato
//
//  Created by  on 5/22/25.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Observation
import os

@MainActor
@Observable
class DirectoryViewModel {
    // Sorting and sortedItems are now managed reactively and debounced for UI safety.
    var items: [DirectoryItem] = [] {
        didSet {
            // Immediately update sortedItems when items change to prevent index out of bounds
            updateSortedItems()
        }
    }
    var sortedItems: [DirectoryItem] = []
    var sortOrder: [KeyPathComparator<DirectoryItem>] = SettingsModel.keyPathComparator(for: SettingsModel.shared.defaultSortMethod) {
        didSet {
            // Immediately update sortedItems when sort order changes
            updateSortedItems()
        }
    }

    var currentDirectory: URL?
    var navigationStack: [URL] = []
    var forwardStack: [URL] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var pathString: String = ""
    var hideHiddenFiles: Bool = true
    
    // Search properties
    var isSearching: Bool = false
    var searchText: String = "" {
        didSet {
            updateSortedItems()
        }
    }
    
    
    // Per-pane view state
    var viewMode: ViewMode = .list
    var currentSortMethod: String = "date"
    var sortAscending: Bool = false

    // Rename alert state
    var showingRenameAlert = false
    var renameText = ""
    var itemToRename: DirectoryItem? = nil
    
    // File conflict alert state
    var showingFileConflictAlert = false
    var conflictMessage = ""
    @ObservationIgnored private var pendingMoveOperation: (() -> Void)?

    @ObservationIgnored private let log = Logger(subsystem: "com.mato", category: "directory")
    @ObservationIgnored private let fileManager = FileManagerService.shared
    @ObservationIgnored private let preferencesManager = DirectoryPreferencesManager.shared

    // Directory watching service
    @ObservationIgnored private var directoryWatcherService: DirectoryWatcherService?
    
    // Flag to prevent concurrent sorting operations
    @ObservationIgnored private var isUpdatingSortedItems = false
    /// Tracks the most recent sort task so we can cancel it when new sort/nav
    /// events arrive — prevents stale results from a slow task overwriting
    /// fresher data.
    @ObservationIgnored private var currentSortTask: Task<Void, Never>?

    // MARK: - Preload Cache
    // LRU-evicted cache of directory contents fetched on hover, before navigation.
    // Capped at 10 entries so memory impact is negligible.
    private static let preloadCacheLimit = 10
    @ObservationIgnored private var preloadCache: [URL: [DirectoryItem]] = [:]
    @ObservationIgnored private var preloadCacheOrder: [URL] = [] // tracks insertion order for LRU eviction
    @ObservationIgnored private var preloadTasks: [URL: Task<Void, Never>] = [:]

    init() {
        // Use default folder from settings
        let defaultURL = SettingsModel.shared.defaultFolderURL
        navigationStack = [defaultURL]
        currentDirectory = defaultURL  // Set immediately to prevent showing wrong directory
        pathString = defaultURL.path(percentEncoded: false)
        loadDirectory(at: defaultURL)
    }

    // MARK: - Hover Preloading

    /// Preloads the contents of a directory into the cache.
    /// Called on hover (after a debounce delay). Safe to call multiple times —
    /// skips if already cached or a preload is already in flight for this URL.
    func preloadDirectory(at url: URL) {
        // Only preload actual directories
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir), isDir.boolValue else { return }

        // Skip if already cached
        if preloadCache[url] != nil { return }

        // Skip if a preload task is already running for this URL
        if preloadTasks[url] != nil { return }

        let shouldHideHiddenFiles = hideHiddenFiles

        let task = Task { @MainActor [weak self, fileManager] in
            guard let self else { return }
            do {
                let contents = try await fileManager.getContents(of: url)
                let filtered = shouldHideHiddenFiles ? contents.filter { !$0.isHidden } : contents

                // Only store if we weren't cancelled and the cache entry still doesn't exist
                // (avoids overwriting a real navigation that already cleared the entry)
                if !Task.isCancelled {
                    self.storeInPreloadCache(url: url, items: filtered)
                }
            } catch {
                // Preload failures are silent — navigation will fall back to normal load
            }
            self.preloadTasks.removeValue(forKey: url)
        }

        preloadTasks[url] = task
    }

    /// Cancel a pending hover preload (e.g. if a preload task is no longer needed).
    func cancelPreload(for url: URL) {
        preloadTasks[url]?.cancel()
        preloadTasks.removeValue(forKey: url)
    }

    private func storeInPreloadCache(url: URL, items: [DirectoryItem]) {
        // Evict oldest entry if at the limit
        if preloadCacheOrder.count >= Self.preloadCacheLimit, let oldest = preloadCacheOrder.first {
            preloadCache.removeValue(forKey: oldest)
            preloadCacheOrder.removeFirst()
        }
        preloadCache[url] = items
        preloadCacheOrder.append(url)
    }

    private func consumePreloadCache(for url: URL) -> [DirectoryItem]? {
        guard let items = preloadCache[url] else { return nil }
        preloadCache.removeValue(forKey: url)
        preloadCacheOrder.removeAll { $0 == url }
        return items
    }

    func loadDownloadsDirectory() {
        guard let downloadsURL = fileManager.getDownloadsDirectory() else {
            self.errorMessage = "Could not locate Downloads directory"
            return
        }

        navigationStack = [downloadsURL]
        forwardStack = []
        loadDirectory(at: downloadsURL)
    }

    func loadDirectory(at url: URL) {
        // Stop previous watcher by releasing the service (handled by ARC)
        directoryWatcherService = nil

        // Start watching new directory
        directoryWatcherService = DirectoryWatcherService(url: url, queue: .main) { [weak self] in
            Task { @MainActor in
                self?.refreshCurrentDirectory()
            }
        }
        
        // Load per-directory preferences
        let pref = preferencesManager.getPreference(for: url)
        
        // Only load saved view mode if the setting is enabled
        if SettingsModel.shared.useSavedViewMode {
            viewMode = pref.viewMode
        }
        // Otherwise keep current view mode
        
        currentSortMethod = pref.sortMethod
        sortAscending = pref.sortAscending
        
        // Apply sort order based on preferences
        sortOrder = createSortOrder(for: pref.sortMethod, ascending: pref.sortAscending)

        // Update currentDirectory and pathString immediately to prevent showing wrong directory
        currentDirectory = url
        pathString = url.path(percentEncoded: false)

        // Cancel any in-flight preload for this URL — we're doing a real navigation now
        preloadTasks[url]?.cancel()
        preloadTasks.removeValue(forKey: url)

        let shouldHideHiddenFiles = hideHiddenFiles

        // Check if we have preloaded data for this URL
        if let cachedItems = consumePreloadCache(for: url) {
            // Show cached content instantly — no loading spinner
            errorMessage = nil
            items = cachedItems

            // Silently refresh in the background to catch any FS changes since hover
            Task { @MainActor [weak self, fileManager] in
                guard let self else { return }
                // Only refresh if we're still on this directory
                guard self.currentDirectory == url else { return }
                do {
                    let freshContents = try await fileManager.getContents(of: url)
                    let filtered = shouldHideHiddenFiles ? freshContents.filter { !$0.isHidden } : freshContents
                    // Only apply if we're still viewing the same directory
                    if self.currentDirectory == url {
                        self.items = filtered
                    }
                } catch {
                    // Silent refresh failure is fine — we already have cached data showing
                }
            }
        } else {
            // No cache — normal load with loading indicator
            isLoading = true
            errorMessage = nil

            let previousItems = items

            // Clear items immediately to prevent showing old directory content
            items = []

            Task { @MainActor [weak self, fileManager] in
                guard let self = self else { return }

                do {
                    let contents = try await fileManager.getContents(of: url)
                    let filteredContents = shouldHideHiddenFiles ?
                        contents.filter { !($0.isHidden) } : contents

                    self.items = filteredContents
                    self.isLoading = false

                } catch {
                    self.errorMessage = "Error loading directory: \(error.localizedDescription)"
                    self.items = previousItems
                    self.isLoading = false

                    if let currentDir = self.currentDirectory {
                        self.pathString = currentDir.path(percentEncoded: false)
                    }
                }
            }
        }
    }

    private func updateSortedItems() {
        // Cancel any in-flight sort so stale results never overwrite fresher data.
        currentSortTask?.cancel()

        let currentItems = items
        let currentSortOrder = sortOrder
        let currentSearchText = searchText

        let task = Task.detached(priority: .userInitiated) {
            var filtered = currentItems

            // Apply search filter if active
            if !currentSearchText.isEmpty {
                filtered = filtered.filter { item in
                    item.name.localizedCaseInsensitiveContains(currentSearchText)
                }
            }

            guard !Task.isCancelled else { return }

            // Sort items
            let sorted = filtered.sorted(using: currentSortOrder)

            guard !Task.isCancelled else { return }

            // Update on main actor
            await MainActor.run {
                self.sortedItems = sorted
            }
        }
        currentSortTask = task
    }

    func setSortOrder(_ newSortOrder: [KeyPathComparator<DirectoryItem>]) {
        // Update happens automatically via didSet, but we set it explicitly here
        // to be clear about the intent
        sortOrder = newSortOrder
    }
    
    // MARK: - View Preferences
    
    func setViewMode(_ mode: ViewMode) {
        viewMode = mode
        if let url = currentDirectory {
            preferencesManager.setViewMode(for: url, viewMode: mode)
        }
    }
    
    func setSortMethod(_ method: String, ascending: Bool = false) {
        currentSortMethod = method
        sortAscending = ascending
        
        // Update sort order
        sortOrder = createSortOrder(for: method, ascending: ascending)
        
        // Save preference
        if let url = currentDirectory {
            preferencesManager.setSortMethod(for: url, sortMethod: method, ascending: ascending)
        }
    }
    
    private func createSortOrder(for method: String, ascending: Bool) -> [KeyPathComparator<DirectoryItem>] {
        // Create comparators based on method and direction
        switch method {
        case "name":
            return [KeyPathComparator(\DirectoryItem.name, order: ascending ? .forward : .reverse)]
        case "date":
            return [KeyPathComparator(\DirectoryItem.lastModified, order: ascending ? .forward : .reverse)]
        case "size":
            return [KeyPathComparator(\DirectoryItem.size, order: ascending ? .forward : .reverse)]
        case "type":
            return [KeyPathComparator(\DirectoryItem.fileTypeDescription, order: ascending ? .forward : .reverse)]
        case "created":
            return [KeyPathComparator(\DirectoryItem.creationDate, order: ascending ? .forward : .reverse)]
        default:
            return [KeyPathComparator(\DirectoryItem.lastModified, order: ascending ? .forward : .reverse)]
        }
    }

    func openItem(_ item: DirectoryItem) {
        if item.isDirectory && !item.isAppBundle {
            // When navigating to a new directory, clear the forward stack
            forwardStack.removeAll()

            // Navigate into the directory
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
            loadDirectory(at: previousDirectory)
        }
    }

    func navigateForward() {
        guard !forwardStack.isEmpty else { return }

        // Get the next directory from the forward stack
        let nextDirectory = forwardStack.removeLast()

        // Add it to the navigation stack
        navigationStack.append(nextDirectory)
        loadDirectory(at: nextDirectory)
    }

    func canNavigateBack() -> Bool {
        return navigationStack.count > 1
    }

    func canNavigateForward() -> Bool {
        return !forwardStack.isEmpty
    }

    func navigate(to url: URL) {
        navigationStack = [url]
        forwardStack = []
        loadDirectory(at: url)
    }

    func navigateToPath(_ path: String) {
        guard !path.isEmpty else { return }

        let url = URL(filePath: path)
        var isDir: ObjCBool = false

        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir), isDir.boolValue {
            // Valid directory, navigate to it
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
                pathString = current.path(percentEncoded: false)
            }
        }
    }

    // Cached formatter — ByteCountFormatter is expensive to construct.
    nonisolated(unsafe) private static let byteCountFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB, .useBytes]
        f.countStyle = .file
        return f
    }()

    func formatFileSize(_ size: Int) -> String {
        Self.byteCountFormatter.string(fromByteCount: Int64(size))
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

            let escapedPath = targetURL.path(percentEncoded: false)
                .replacingOccurrences(of: "'", with: "\\'")
            let script = """
                    tell application "Terminal"
                        activate
                        do script "cd '\(escapedPath)'"
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

        let sourceURL = item.url
        itemToRename = nil
        renameText = ""

        Task.detached(priority: .userInitiated) {
            do {
                try FileManager.default.moveItem(at: sourceURL, to: newURL)
            } catch {
                await MainActor.run {
                    self.log.error("Failed to rename: \(error.localizedDescription)")
                }
            }
            // Directory watcher will pick up the change; explicit refresh is a
            // safety net in case the watcher fires before the file is visible.
            await MainActor.run { self.refreshCurrentDirectory() }
        }
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

        Task.detached(priority: .userInitiated) {
            for url in urls {
                let destinationURL = currentDir.appendingPathComponent(
                    url.lastPathComponent
                )
                do {
                    try FileManager.default.copyItem(at: url, to: destinationURL)
                } catch {
                    await MainActor.run {
                        self.log.error("Failed to paste: \(error.localizedDescription)")
                    }
                }
            }
            await MainActor.run { self.refreshCurrentDirectory() }
        }
    }

    func hasItemsInPasteboard() -> Bool {
        let pasteboard = NSPasteboard.general
        return pasteboard.canReadObject(forClasses: [NSURL.self], options: nil)
    }

    func copyPaths(_ ids: Set<DirectoryItem.ID>) {
        let paths = ids.compactMap { id in
            getItem(id)?.url.path(percentEncoded: false)
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths, forType: .string)
    }

    func copyAsPathname(_ ids: Set<DirectoryItem.ID>) {
        let paths = ids.compactMap { id in
            getItem(id)?.url.standardizedFileURL.path(percentEncoded: false)
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
            log.error("Failed to create alias: \(error.localizedDescription)")
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
                inFileViewerRootedAtPath: item.url.path(percentEncoded: false)
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
        let workingDir = currentDirectory?.path(percentEncoded: false)
            ?? FileManager.default.currentDirectoryPath

        // Run ditto on a background thread — waitUntilExit() blocks the calling
        // thread, so this must never be called on the main thread.
        Task.detached(priority: .userInitiated) {
            let task = Process()
            task.launchPath = "/usr/bin/ditto"
            task.arguments =
                ["-c", "-k", "--sequesterRsrc", "--keepParent"]
                + urls.map { $0.path(percentEncoded: false) }
                + ["Archive.zip"]
            task.currentDirectoryPath = workingDir

            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                await MainActor.run {
                    self.log.error("Failed to compress: \(error.localizedDescription)")
                }
            }
            await MainActor.run { self.refreshCurrentDirectory() }
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
                log.error("Failed to create alias: \(error.localizedDescription)")
            }
        }

        refreshCurrentDirectory()
    }

    func moveToTrash(_ ids: Set<DirectoryItem.ID>) {
        let urls = getURLs(from: ids)

        Task.detached(priority: .userInitiated) {
            for url in urls {
                do {
                    try FileManager.default.trashItem(
                        at: url,
                        resultingItemURL: nil
                    )
                } catch {
                    await MainActor.run {
                        self.errorMessage = "Failed to move to trash: \(error.localizedDescription)"
                    }
                }
            }
            await MainActor.run { self.refreshCurrentDirectory() }
        }
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

    func moveFiles(from sourceURLs: [URL], to destinationURL: URL, replaceExisting: Bool = false) {
        Task {
            log.debug("Moving \(sourceURLs.count) files to \(destinationURL.path)")
            for (index, url) in sourceURLs.enumerated() {
                log.debug("  [\(index)] Source: \(url.lastPathComponent) from \(url.path)")
            }
            
            var successCount = 0
            var conflictingFiles: [(source: URL, dest: URL)] = []
            var failedFiles: [(source: String, dest: String, error: String)] = []
            
            // First pass: check for conflicts
            for sourceURL in sourceURLs {
                let fileName = sourceURL.lastPathComponent
                let destinationPath = destinationURL.appendingPathComponent(fileName)
                
                if FileManager.default.fileExists(atPath: destinationPath.path) && !replaceExisting {
                    log.debug("Conflict detected: \(fileName) already exists at \(destinationPath.path)")
                    conflictingFiles.append((sourceURL, destinationPath))
                }
            }
            
            // If there are conflicts and we haven't been told to replace, show confirmation
            if !conflictingFiles.isEmpty && !replaceExisting {
                let fileNames = conflictingFiles.map { $0.source.lastPathComponent }
                if fileNames.count == 1 {
                    conflictMessage = "'\(fileNames[0])' already exists. Do you want to replace it?"
                } else {
                    conflictMessage = "\(fileNames.count) files already exist. Do you want to replace them?"
                }
                
                // Store the operation to retry with replace=true if user confirms
                pendingMoveOperation = { [weak self] in
                    self?.moveFiles(from: sourceURLs, to: destinationURL, replaceExisting: true)
                }
                
                showingFileConflictAlert = true
                return
            }
            
            // Second pass: perform the moves
            for sourceURL in sourceURLs {
                let fileName = sourceURL.lastPathComponent
                let destinationPath = destinationURL.appendingPathComponent(fileName)
                
                log.debug("Attempting to move: \(fileName)")
                log.debug("   From: \(sourceURL.path)")
                log.debug("   To: \(destinationPath.path)")
                
                do {
                    // If file exists and we're replacing, delete it first
                    if FileManager.default.fileExists(atPath: destinationPath.path) && replaceExisting {
                        log.debug("Removing existing file at destination")
                        try FileManager.default.removeItem(at: destinationPath)
                    }
                    
                    try await fileManager.moveFile(from: sourceURL, to: destinationURL)
                    log.debug("Successfully moved: \(fileName)")
                    successCount += 1
                } catch {
                    log.error("Failed to move \(fileName): \(error.localizedDescription)")
                    failedFiles.append((sourceURL.path, destinationPath.path, error.localizedDescription))
                }
            }
            
            refreshCurrentDirectory()
            
            // Show appropriate message based on results
            if successCount == sourceURLs.count {
                errorMessage = nil
            } else if successCount > 0 {
                var message = "Moved \(successCount) of \(sourceURLs.count) files."
                if !failedFiles.isEmpty {
                    // Group by destination to avoid showing duplicate filenames
                    let uniqueFailures = Dictionary(grouping: failedFiles, by: { $0.dest })
                        .map { URL(fileURLWithPath: $0.key).lastPathComponent }
                    message += " Failed: \(uniqueFailures.joined(separator: ", "))."
                }
                errorMessage = message
            } else if !failedFiles.isEmpty {
                // Show source -> destination mapping for clarity
                let details = failedFiles.map {
                    "'\(URL(fileURLWithPath: $0.source).lastPathComponent)' → '\(URL(fileURLWithPath: $0.dest).lastPathComponent)'"
                }
                errorMessage = "Failed to move files: \(details.joined(separator: ", "))"
            }
        }
    }
    
    func confirmReplaceFiles() {
        showingFileConflictAlert = false
        pendingMoveOperation?()
        pendingMoveOperation = nil
    }
    
    func cancelReplaceFiles() {
        showingFileConflictAlert = false
        pendingMoveOperation = nil
        errorMessage = "Move operation cancelled."
    }

    func handleDrop(info: DropInfo) -> Bool {
        let itemProviders = info.itemProviders(for: [.fileURL])
        guard !itemProviders.isEmpty else { return false }

        Task { @MainActor in
            var urls: [URL] = []
            
            for itemProvider in itemProviders {
                if let loaded = try? await itemProvider.loadFileURLs() {
                    urls.append(contentsOf: loaded)
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

    func refreshCurrentDirectory() {
        if let currentDir = currentDirectory {
            loadDirectory(at: currentDir)
        }
    }
}
