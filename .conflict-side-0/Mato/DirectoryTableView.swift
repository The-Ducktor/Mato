import SwiftUI
import UniformTypeIdentifiers

struct DraggedFiles: Transferable {
    let urls: [URL]

    static var transferRepresentation: some TransferRepresentation {
        // Provide all URLs for multi-select support
        DataRepresentation(exportedContentType: .fileURL) { dragged in
            // Archive all URLs together for multi-select drag support
            return try NSKeyedArchiver.archivedData(withRootObject: dragged.urls as NSArray, requiringSecureCoding: false)
        }
    }
}

struct DirectoryTableView: View {
    @ObservedObject var viewModel: DirectoryViewModel
    @Binding var selectedItems: Set<DirectoryItem.ID>
    @Binding var sortOrder: [KeyPathComparator<DirectoryItem>]
    @State private var color: Color = .clear // testing
    @State private var isDropTargeted: Bool = false
    @State private var hoveredFolderID: DirectoryItem.ID? = nil
    @State private var tableRebuildID = UUID() // Force table rebuild on sort changes
    @State private var sortUpdateTask: Task<Void, Never>? = nil // Debounce sort updates
    @State private var localSortOrder: [KeyPathComparator<DirectoryItem>] = [] // Local copy to prevent binding conflicts
    @State private var isProcessingSortChange = false // Prevent re-entrant updates
    @SceneStorage("DirectoryTableViewConfig")
    private var columnCustomization: TableColumnCustomization<DirectoryItem>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Table(
                selection: $selectedItems,
                sortOrder: $localSortOrder,
                columnCustomization: $columnCustomization,
            ) {
                TableColumn("Name", value: \.name) { item in
                    NameCellView(
                        item: item,
                        viewModel: viewModel,
                        selectedItems: selectedItems,
                        hoveredFolderID: $hoveredFolderID,
                        color: $color
                    )
                }
                .width(min: 180)
                .alignment(.leading).customizationID("name")

                TableColumn("Size", value: \.size) { item in
                    if item.isDirectory {
                        Text("--")
                    } else {
                        Text(viewModel.formatFileSize(item.size))
                    }
                }
                .width(min: 100)
                .alignment(.trailing)
                .customizationID("size")

                TableColumn("Kind", value: \.fileTypeDescription) { item in
                    Text(item.fileTypeDescription)
                }
                .alignment(.trailing)
                .customizationID("kind")

                TableColumn("Date Modified", value: \.lastModified) { item in
                    Text(formatDate(item.lastModified))
                }
                .customizationID("dateModified")
                
                TableColumn("Date Created", value: \.creationDate) { item in
                    Text(formatDate(item.creationDate))
                }
                .width(min: 150)
                .alignment(.trailing)
                .customizationID("dateCreated")
                .defaultVisibility(.hidden)
                
                TableColumn("Date Added", value: \.addedDate) { item in
                    Text(formatDate(item.addedDate))
                }
                .width(min: 150)
                .alignment(.trailing)
                .customizationID("dateAdded")
                .defaultVisibility(.hidden)
                
                TableColumn(
                    "Last Accessed",
                    value: \.dateLastAccessed
                ) { item in
                    Text(formatDate(item.dateLastAccessed))
                }
                .width(min: 150)
                .alignment(.trailing)
                .customizationID("dateLastAccessed")
                .defaultVisibility(.hidden)
            } rows: {
                ForEach(viewModel.sortedItems) { item in
                    TableRow(item)
                        .draggable(makeDraggedFiles(for: item))
                }
            }
            .id(tableRebuildID) // Force complete rebuild when this changes
            .animation(.none, value: localSortOrder) // Disable animations on sort order changes to prevent crashes
            .onDrop(of: [UTType.fileURL], delegate: TableDropDelegate(viewModel: viewModel))
            .onAppear {
                // Initialize local sort order from binding
                localSortOrder = sortOrder
            }
            .onChange(of: localSortOrder) { oldValue, newValue in
                // Prevent re-entrant updates
                guard !isProcessingSortChange else { return }
                isProcessingSortChange = true
                
                // Cancel any pending sort update
                sortUpdateTask?.cancel()
                
                // Immediately clear selection to prevent index issues
                selectedItems.removeAll()
                
                // Update immediately - no delay needed since we're disabling animations
                sortUpdateTask = Task { @MainActor in
                    guard !Task.isCancelled else {
                        isProcessingSortChange = false
                        return
                    }
                    
                    // Disable animations and update sort order immediately to prevent table crashes
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        // Update the view model
                        viewModel.setSortOrder(newValue)
                        // Update the external binding
                        sortOrder = newValue
                        // Force complete table rebuild by changing the ID
                        tableRebuildID = UUID()
                    }
                    
                    isProcessingSortChange = false
                }
            }
            .onChange(of: sortOrder) { _, newValue in
                // Sync external changes back to local state (e.g., from settings)
                guard !isProcessingSortChange else { return }
                localSortOrder = newValue
            }
            .onChange(of: viewModel.currentDirectory) { _, _ in
                // Clear selection when changing directories to prevent stale references
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    selectedItems.removeAll()
                    // Force table rebuild on directory change
                    tableRebuildID = UUID()
                }
            }
        }
    }
    
    private func makeDraggedFiles(for item: DirectoryItem) -> DraggedFiles {
        let urlsToDrag: [URL]
        // Only compute URLs when drag actually happens
        if selectedItems.contains(item.id), selectedItems.count > 1 {
            // More efficient lookup for multiple selections
            let selectedSet = selectedItems
            urlsToDrag = viewModel.sortedItems.reduce(into: []) { result, current in
                if selectedSet.contains(current.id) {
                    result.append(current.url)
                }
            }
        } else {
            urlsToDrag = [item.url]
        }
        return DraggedFiles(urls: urlsToDrag)
    }

    private func loadFileURL(from provider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                // Handle different data types
                if let url = data as? URL {
                    // Direct URL object
                    continuation.resume(returning: url)
                    return
                }
                
                if let data = data as? Data {
                    // Try to unarchive the URL from NSKeyedArchiver format
                    if let url = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSURL.self, from: data) as? URL {
                        continuation.resume(returning: url)
                        return
                    }
                    
                    // Try to unarchive an array of URLs
                    if let urls = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSURL.self], from: data) as? [URL],
                       let firstURL = urls.first {
                        continuation.resume(returning: firstURL)
                        return
                    }
                    
                    // Fallback: try URL(dataRepresentation:)
                    if let url = URL(dataRepresentation: data, relativeTo: nil) {
                        continuation.resume(returning: url)
                        return
                    }
                }
                
                continuation.resume(throwing: NSError(domain: "InvalidData", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not decode URL from drag data"]))
            }
        }
    }


    // Cache formatters to avoid recreating them for every cell
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
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

    private func formatDate(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) || calendar.isDateInYesterday(date) || calendar.isDateInTomorrow(date) {
            return Self.relativeDateFormatter.localizedString(for: date, relativeTo: now)
        } else {
            return Self.dateFormatter.string(from: date)
        }
    }
    
}

// Separate view component for Name cell to properly handle @State
struct NameCellView: View {
    let item: DirectoryItem
    let viewModel: DirectoryViewModel
    let selectedItems: Set<DirectoryItem.ID>
    @Binding var hoveredFolderID: DirectoryItem.ID?
    @Binding var color: Color
    @State private var isRowTargeted = false
    
    var body: some View {
        HStack {
            ImageIcon(item: .constant(item))
                .frame(width: 16, height: 16)
            Text(item.isAppBundle ? item.url.deletingPathExtension().lastPathComponent : item.name)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isRowTargeted && item.isDirectory ? Color.accentColor.opacity(0.25) : Color.clear)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isRowTargeted) { providers in
            guard item.isDirectory else { return false }

            Task {
                var files: [URL] = []

                for provider in providers {
                    if let urls = try? await loadFileURLs(from: provider) {
                        for url in urls {
                            if item.url == url {
                                continue
                            }
                            if item.isDirectory {
                                files.append(url)
                            }
                        }
                    }
                }

                if !files.isEmpty {
                    viewModel.moveFiles(from: files, to: item.url)
                    color = .green
                }
            }
            return true
        }
        .onChange(of: isRowTargeted) { _, newValue in
            if newValue && item.isDirectory {
                hoveredFolderID = item.id
            } else if hoveredFolderID == item.id {
                hoveredFolderID = nil
            }
        }
    }
    
    private func loadFileURLs(from provider: NSItemProvider) async throws -> [URL] {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                if let url = data as? URL {
                    continuation.resume(returning: [url])
                    return
                }
                
                if let data = data as? Data {
                    // Try to unarchive an ARRAY of URLs first (multi-select case)
                    if let urls = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSURL.self], from: data) as? [URL] {
                        continuation.resume(returning: urls)
                        return
                    }
                    
                    // Try to unarchive a single URL
                    if let url = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSURL.self, from: data) as? URL {
                        continuation.resume(returning: [url])
                        return
                    }
                    
                    // Fallback: try URL(dataRepresentation:)
                    if let url = URL(dataRepresentation: data, relativeTo: nil) {
                        continuation.resume(returning: [url])
                        return
                    }
                }
                
                continuation.resume(throwing: NSError(domain: "InvalidData", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not decode URL from drag data"]))
            }
        }
    }
}

// You'll need to create a new drop delegate for the table
struct TableDropDelegate: DropDelegate {
    let viewModel: DirectoryViewModel
    var setDropMessage: ((String) -> Void)? = nil
    
    func performDrop(info: DropInfo) -> Bool {
        let itemProviders = info.itemProviders(for: [.fileURL])
        guard !itemProviders.isEmpty else { return false }

        Task { @MainActor in
            var urls: [URL] = []
            
            for itemProvider in itemProviders {
                if let urlsFromProvider = try? await loadFileURLs(from: itemProvider) {
                    urls.append(contentsOf: urlsFromProvider)
                }
            }
            
            // Deduplicate URLs - each provider may contain the full array
            let uniqueURLs = Array(Set(urls))
            
            if !uniqueURLs.isEmpty, let currentDirectory = viewModel.currentDirectory {
                viewModel.moveFiles(from: uniqueURLs, to: currentDirectory)
                // Compose message
                let fileNames = urls.map { $0.lastPathComponent }.joined(separator: ", ")
                let source = urls.first?.deletingLastPathComponent().path ?? "?"
                let dest = currentDirectory.path
                let message = "file \(fileNames) from \(source) to \(dest)"
                setDropMessage?(message)
            }
        }
        return true
    }
    
    private func loadFileURLs(from provider: NSItemProvider) async throws -> [URL] {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                // Handle different data types
                if let url = data as? URL {
                    continuation.resume(returning: [url])
                    return
                }
                
                if let data = data as? Data {
                    // Try to unarchive an ARRAY of URLs first (multi-select case)
                    if let urls = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSURL.self], from: data) as? [URL] {
                        continuation.resume(returning: urls)
                        return
                    }
                    
                    // Try to unarchive a single URL
                    if let url = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSURL.self, from: data) as? URL {
                        continuation.resume(returning: [url])
                        return
                    }
                    
                    // Fallback: try URL(dataRepresentation:)
                    if let url = URL(dataRepresentation: data, relativeTo: nil) {
                        continuation.resume(returning: [url])
                        return
                    }
                }
                
                continuation.resume(throwing: NSError(domain: "InvalidData", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not decode URL from drag data"]))
            }
        }
    }
    
    func dropEntered(info: DropInfo) {
        // Optional: Handle visual feedback when drag enters
    }
    
    func dropExited(info: DropInfo) {
        // Optional: Handle visual feedback when drag exits
    }
}

