import AppKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct DirectoryView: View {
    @ObservedObject var viewModel: DirectoryViewModel
    var onActivate: (() -> Void)? = nil

    @State private var selectedItems: Set<DirectoryItem.ID> = []
    @State private var quickLookURL: URL?
    @State private var showQuickLook = false
    @ObservedObject private var thumbnailLoader = SimpleThumbnailLoader()
    @State private var showingRenameAlert = false
    @State private var renameText = ""
    @State private var itemToRename: DirectoryItem?

    // Column width percentages
    private let dateModifiedWidthPercent: CGFloat = 0.25
    private let kindWidthPercent: CGFloat = 0.20
    private let sizeWidthPercent: CGFloat = 0.15
    private let nameWidthPercent: CGFloat = 0.40
    
    

    init(
        viewModel: DirectoryViewModel = DirectoryViewModel(),
        onActivate: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onActivate = onActivate
    }
    @State private var sortOrder = [
        KeyPathComparator(\DirectoryItem.lastModified, order: .reverse),
    ]
  

    var body: some View {
        VStack {
            PathBar(
                path: viewModel.currentDirectory
                    ?? URL(fileURLWithPath: "/Users"),
                viewModel: viewModel
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onActivate?()
            }

            // Directory contents
            if viewModel.isLoading {
                // Empty table structure with loading indicator
                ZStack {
                    // Empty table to maintain structure
                    Table([], selection: $selectedItems, sortOrder: $sortOrder) {
                        TableColumn("Name", value: \.name) { item in
                            HStack {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: 16, height: 16)
                                Text("")
                            }
                        }
                        .width(min: 180)
                        .alignment(.leading)

                        TableColumn("Size", value: \.size) { item in
                            Text("")
                        }
                        .width(min: 100)
                        .alignment(.trailing)

                        TableColumn("Kind", value: \.fileTypeDescription) { item in
                            Text("")
                        }
                        .alignment(.trailing)

                        TableColumn("Date Modified", value: \.lastModified) { item in
                            Text("")
                        }
                        .width(min: 150)
                        .alignment(.trailing)
                    }
                    .disabled(true)
                    
                    // Loading indicator overlay
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.2)
                        
                        Text("Loading...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.regularMaterial)
                            .shadow(radius: 2)
                    )
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onActivate?()
                }
            } else if let error = viewModel.errorMessage {
                VStack {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                    Button("Try Again") {
                        viewModel.loadDownloadsDirectory()
                        onActivate?()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    onActivate?()
                }
            } else {
                // Wrap the table in a container that handles background taps
                ZStack {
                    // Background tap area that covers the entire view
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Clear selection when clicking on empty area
                            selectedItems.removeAll()
                            onActivate?()
                        }
                    
                    // The actual table
                    Table(viewModel.items, selection: $selectedItems, sortOrder: $sortOrder) {
                        TableColumn("Name", value: \.name) { item in
                            HStack {
                                ImageIcon(item: .constant(item))
                                    .frame(width: 16, height: 16)
                                Text(item.name)
                                    .truncationMode(.middle)
                            }
                        }
                        .width(min: 180)
                        .alignment(.leading)

                        TableColumn("Size", value: \.size) { item in
                            if item.isDirectory {
                                Text("--")
                            } else {
                                Text(viewModel.formatFileSize(item.size))
                            }
                        }
                        .width(min: 100)
                        .alignment(.trailing)

                        TableColumn("Kind", value: \.fileTypeDescription) { item in
                            Text(item.fileTypeDescription)
                        }
                        .alignment(.trailing)

                        TableColumn("Date Modified", value: \.lastModified) { item in
                            Text(formatDate(item.lastModified))
                        }
                        .width(min: 150)
                        .alignment(.trailing)
                    }
                    .onChange(of: sortOrder) { _, newSortOrder in
                        applySorting(with: newSortOrder)
                    }
                    .onAppear {
                        // Apply sorting when view appears
                        applySorting(with: sortOrder)
                    }
                    .onChange(of: viewModel.currentDirectory) { _, _ in
                        // Apply sorting when directory changes
                        applySorting(with: sortOrder)
                    }
                    .onChange(of: viewModel.items) { _, _ in
                        // Apply sorting when items change (including after loading)
                        applySorting(with: sortOrder)
                    }
                    .onChange(of: selectedItems) {
                        onActivate?()
                    }
                    .contextMenu(forSelectionType: DirectoryItem.ID.self) { ids in
                        // Primary Actions Group
                        Group {
                            Button("Open") {
                                openSelectedItems(ids)
                            }
                            
                            
                            Button("Open in Terminal") {
                                openInTerminal(ids)
                            }
                            .disabled(ids.isEmpty || !canOpenInTerminal(ids))
                        }
                        
                        Divider()
                        
                        // Edit Actions Group
                        Group {
                            if ids.count == 1 {
                                Button("Rename") {
                                    startRename(ids.first!)
                                }
                            }
                            
                            Button("Copy") {
                                copyItems(ids)
                            }
                            
                            Button("Cut") {
                                cutItems(ids)
                            }
                            
                            if hasItemsInPasteboard() {
                                Button("Paste") {
                                    pasteItems()
                                }
                            }
                            
                            
                        }
                        
                        Divider()
                        
                        // Path Actions Group
                        Group {
                            Button("Copy Path") {
                                copyPaths(ids)
                            }
                            
                            Button("Copy as Pathname") {
                                copyAsPathname(ids)
                            }
                            
                            if ids.count == 1 {
                                Button("Copy Alias") {
                                    copyAlias(ids.first!)
                                }
                            }
                        }
                        
                        Divider()
                        
                        // View Actions Group
                        Group {
                            Button("Quick Look") {
                                if let firstId = ids.first {
                                    quickLookItem(firstId)
                                }
                            }
                            .disabled(ids.isEmpty)
                            
                            Button("Show in Finder") {
                                showInFinder(ids)
                            }
                            
                            
                            
                            if ids.count == 1, let item = getItem(ids.first!) {
                                Button("Show Package Contents") {
                                    showPackageContents(item)
                                }
                                .disabled(!item.url.pathExtension.lowercased().contains("app") && !item.isDirectory)
                            }
                        }
                        
                        Divider()
                        
                        // Utility Actions Group
                        Group {
                            if canCompress(ids) {
                                Button("Compress \"\(getCompressionName(ids))\"") {
                                    compressItems(ids)
                                }
                            }
                            
                            if canCreateAlias(ids) {
                                Button("Make Alias") {
                                    makeAlias(ids)
                                }
                            }
                            
                            Button("Move to Trash") {
                                moveToTrash(ids)
                            }
                            .foregroundColor(.red)
                        }
                        
                        // Services submenu (if needed)
                        if !ids.isEmpty {
                            Divider()
                            Button("Services") {
                                // Services are typically handled by the system
                                showServices(ids)
                            }
                        }
                    }
                    primaryAction: { ids in
                        openSelectedItems(ids)
                        onActivate?()
                    }
                    .onKeyPress(.space) {
                        handleSpaceKeyPress()
                        return .handled
                    }
                    .quickLookPreview(
                        $quickLookURL,
                        in: selectedItemURLs
                    )
                    // Add tap gesture to the table itself for item selection areas
                    .simultaneousGesture(
                        TapGesture()
                            .onEnded { _ in
                                onActivate?()
                            }
                    )
                }
            }
        }
        .frame(minHeight: 400)
        .focusable()
        // Add an overall tap gesture that captures any missed taps
        .contentShape(Rectangle())
        .onTapGesture {
            onActivate?()
        }
        .alert("Rename", isPresented: $showingRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { }
            Button("Rename") {
                performRename()
            }
        } message: {
            Text("Enter a new name for the item")
        }
    }

    // MARK: - Sorting Helper
    
    private func applySorting(with sortOrder: [KeyPathComparator<DirectoryItem>]) {
        DispatchQueue.main.async {
            viewModel.items.sort(using: sortOrder)
        }
    }

    private var selectedItemURLs: [URL] {
        selectedItems.compactMap { id in
            viewModel.items.first(where: { $0.id == id })?.url
        }
    }
    
    // MARK: - Context Menu Actions
    
    private func openSelectedItems(_ ids: Set<DirectoryItem.ID>) {
        for id in ids {
            if let item = getItem(id) {
                viewModel.openItem(item)
            }
        }
    }
    
    
    
    private func openInTerminal(_ ids: Set<DirectoryItem.ID>) {
        for id in ids {
            guard let item = getItem(id) else { continue }
            let targetURL = item.isDirectory ? item.url : item.url.deletingLastPathComponent()
            
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
    
    private func canOpenInTerminal(_ ids: Set<DirectoryItem.ID>) -> Bool {
        return !ids.isEmpty
    }
    
    private func startRename(_ id: DirectoryItem.ID) {
        guard let item = getItem(id) else { return }
        itemToRename = item
        renameText = item.name
        showingRenameAlert = true
    }
    
    private func performRename() {
        guard let item = itemToRename else { return }
        
        let newURL = item.url.deletingLastPathComponent().appendingPathComponent(renameText)
        
        do {
            try FileManager.default.moveItem(at: item.url, to: newURL)
            viewModel.refreshCurrentDirectory()
        } catch {
            print("Failed to rename: \(error)")
        }
        
        itemToRename = nil
        renameText = ""
    }
    
    private func copyItems(_ ids: Set<DirectoryItem.ID>) {
        let urls = getURLs(from: ids)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSPasteboardWriting])
    }
    
    private func cutItems(_ ids: Set<DirectoryItem.ID>) {
        let urls = getURLs(from: ids)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSPasteboardWriting])
        
        // Add cut operation marker
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"))
    }
    
    private func pasteItems() {
        guard let currentDir = viewModel.currentDirectory else { return }
        
        let pasteboard = NSPasteboard.general
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else { return }
        
        for url in urls {
            let destinationURL = currentDir.appendingPathComponent(url.lastPathComponent)
            
            do {
                try FileManager.default.copyItem(at: url, to: destinationURL)
            } catch {
                print("Failed to paste: \(error)")
            }
        }
        
        viewModel.refreshCurrentDirectory()
    }
    
    private func hasItemsInPasteboard() -> Bool {
        let pasteboard = NSPasteboard.general
        return pasteboard.canReadObject(forClasses: [NSURL.self], options: nil)
    }
    
   
    
    private func copyPaths(_ ids: Set<DirectoryItem.ID>) {
        let paths = ids.compactMap { id in
            getItem(id)?.url.path
        }.joined(separator: "\n")
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths, forType: .string)
    }
    
    private func copyAsPathname(_ ids: Set<DirectoryItem.ID>) {
        let paths = ids.compactMap { id in
            getItem(id)?.url.standardizedFileURL.path
        }.joined(separator: "\n")
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths, forType: .string)
    }
    
    private func copyAlias(_ id: DirectoryItem.ID) {
        guard let item = getItem(id) else { return }
        
        do {
            let aliasData = try item.url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(aliasData, forType: NSPasteboard.PasteboardType("com.apple.alias-file"))
        } catch {
            print("Failed to create alias: \(error)")
        }
    }
    
    private func quickLookItem(_ id: DirectoryItem.ID) {
        guard let item = getItem(id) else { return }
        openQuickLook(for: item.url)
    }
    
    private func showInFinder(_ ids: Set<DirectoryItem.ID>) {
        let urls = getURLs(from: ids)
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
    
    
    
    private func showPackageContents(_ item: DirectoryItem) {
        if item.isDirectory || item.url.pathExtension.lowercased().contains("app") {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: item.url.path)
        }
    }
    
    private func canCompress(_ ids: Set<DirectoryItem.ID>) -> Bool {
        return !ids.isEmpty
    }
    
    private func getCompressionName(_ ids: Set<DirectoryItem.ID>) -> String {
        if ids.count == 1, let item = getItem(ids.first!) {
            return item.name
        }
        return "\(ids.count) items"
    }
    
    private func compressItems(_ ids: Set<DirectoryItem.ID>) {
        let urls = getURLs(from: ids)
        
        // Use system compression
        let task = Process()
        task.launchPath = "/usr/bin/ditto"
        task.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent"] + urls.map(\.path) + ["Archive.zip"]
        task.currentDirectoryPath = viewModel.currentDirectory?.path ?? FileManager.default.currentDirectoryPath
        
        do {
            try task.run()
            task.waitUntilExit()
            viewModel.refreshCurrentDirectory()
        } catch {
            print("Failed to compress: \(error)")
        }
    }
    
    private func canCreateAlias(_ ids: Set<DirectoryItem.ID>) -> Bool {
        return !ids.isEmpty
    }
    
    private func makeAlias(_ ids: Set<DirectoryItem.ID>) {
        for id in ids {
            guard let item = getItem(id) else { continue }
            
            let aliasURL = item.url.appendingPathExtension("alias")
            
            do {
                let aliasData = try item.url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
                try aliasData.write(to: aliasURL)
            } catch {
                print("Failed to create alias: \(error)")
            }
        }
        
        viewModel.refreshCurrentDirectory()
    }
    
    private func moveToTrash(_ ids: Set<DirectoryItem.ID>) {
        let urls = getURLs(from: ids)
        
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                print("Failed to move to trash: \(error)")
            }
        }
        
        viewModel.refreshCurrentDirectory()
    }
    
    private func showServices(_ ids: Set<DirectoryItem.ID>) {
        _ = getURLs(from: ids)
        // Services are typically handled automatically by the system
        // This could open a services menu if needed
    }
    
    // MARK: - Helper Methods
    
    private func getItem(_ id: DirectoryItem.ID) -> DirectoryItem? {
        return viewModel.items.first(where: { $0.id == id })
    }
    
    private func getURLs(from ids: Set<DirectoryItem.ID>) -> [URL] {
        return ids.compactMap { id in
            getItem(id)?.url
        }
    }

    private func handleSpaceKeyPress() {
        guard let firstSelectedId = selectedItems.first,
            let selectedItem = viewModel.items.first(where: {
                $0.id == firstSelectedId
            })
        else {
            return
        }

        openQuickLook(for: selectedItem.url)
    }

    private func openQuickLook(for url: URL) {
        quickLookURL = url
        showQuickLook = true
    }

    private func formatDate(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) || calendar.isDateInYesterday(date)
            || calendar.isDateInTomorrow(date)
        {
            let relativeFormatter = RelativeDateTimeFormatter()
            relativeFormatter.unitsStyle = .full
            return relativeFormatter.localizedString(for: date, relativeTo: now)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
}

// MARK: - Extensions

extension DirectoryViewModel {
    func refreshCurrentDirectory() {
        // Add this method to your DirectoryViewModel to refresh the current directory
        // This should reload the items in the current directory
        if let currentDir = currentDirectory {
            loadDirectory(at: currentDir)
        }
    }
}
