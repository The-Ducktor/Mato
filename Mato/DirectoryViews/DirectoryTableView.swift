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
    var viewModel: DirectoryViewModel
    @Binding var selectedItems: Set<DirectoryItem.ID>
    @Binding var sortOrder: [KeyPathComparator<DirectoryItem>]
    @State private var color: Color = .clear // testing
    @State private var isDropTargeted: Bool = false
    @State private var hoveredFolderID: DirectoryItem.ID? = nil
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
                    Text(item.formattedLastModified)
                }
                .customizationID("dateModified")
                
                TableColumn("Date Created", value: \.creationDate) { item in
                    Text(item.formattedCreationDate)
                }
                .width(min: 150)
                .alignment(.trailing)
                .customizationID("dateCreated")
                .defaultVisibility(.hidden)
                
                TableColumn("Date Added", value: \.addedDate) { item in
                    Text(item.formattedAddedDate)
                }
                .width(min: 150)
                .alignment(.trailing)
                .customizationID("dateAdded")
                .defaultVisibility(.hidden)
                
                TableColumn(
                    "Last Accessed",
                    value: \.dateLastAccessed
                ) { item in
                    Text(item.formattedLastAccessed)
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
            .animation(.none, value: localSortOrder) // Disable animations on sort order changes
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
                
                // Update sort order - SwiftUI will handle row updates efficiently
                sortUpdateTask = Task { @MainActor in
                    guard !Task.isCancelled else {
                        isProcessingSortChange = false
                        return
                    }
                    
                    // Update without forcing complete rebuild
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        viewModel.setSortOrder(newValue)
                        sortOrder = newValue
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
                // Clear selection when changing directories
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    selectedItems.removeAll()
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

    // Date formatting is now handled by DirectoryItem for better performance
    
}

// MARK: - Name Cell with hovers and drop target

// Separate view component for Name cell with Equatable for performance
@MainActor struct NameCellView: View, Equatable {
    let item: DirectoryItem
    var viewModel: DirectoryViewModel
    let selectedItems: Set<DirectoryItem.ID>
    @Binding var hoveredFolderID: DirectoryItem.ID?
    @Binding var color: Color
    @State private var isRowTargeted = false
    @State private var hoverPreloadTask: Task<Void, Never>?
    
    // Implement Equatable to prevent unnecessary re-renders
    // Note: @State properties are not included in equality check as they are view-local state
    nonisolated static func == (lhs: NameCellView, rhs: NameCellView) -> Bool {
        lhs.item.id == rhs.item.id &&
        lhs.selectedItems == rhs.selectedItems
    }
    
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
        .onHover { hovering in
            hoverPreloadTask?.cancel()
            guard hovering, item.isDirectory, !item.isAppBundle else { return }
            hoverPreloadTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                viewModel.preloadDirectory(at: item.url)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isRowTargeted) { providers in
            guard item.isDirectory else { return false }

            Task { @MainActor in
                var files: [URL] = []

                for provider in providers {
                    if let urls = try? await provider.loadFileURLs() {
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
                if let urlsFromProvider = try? await itemProvider.loadFileURLs() {
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
    
    func dropEntered(info: DropInfo) {
        // Optional: Handle visual feedback when drag enters
    }
    
    func dropExited(info: DropInfo) {
        // Optional: Handle visual feedback when drag exits
    }
}

