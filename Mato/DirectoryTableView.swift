import SwiftUI
import UniformTypeIdentifiers

struct DirectoryTableView: View {
    @ObservedObject var viewModel: DirectoryViewModel
    @Binding var selectedItems: Set<DirectoryItem.ID>
    @Binding var sortOrder: [KeyPathComparator<DirectoryItem>]
    @State private var hoveredItem: DirectoryItem? = nil
    
    var body: some View {
        Table(selection: $selectedItems, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { item in
                HStack {
                    ImageIcon(item: .constant(item))
                        .frame(width: 16, height: 16)
                    Text(item.name)
                        .truncationMode(.middle)
                }
                .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                    guard item.isDirectory else { return false }
                    var urls: [URL] = []
                    let dispatchGroup = DispatchGroup()
                    for provider in providers {
                        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                            dispatchGroup.enter()
                            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
                                if let urlData = data as? Data, let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                                    urls.append(url)
                                }
                                dispatchGroup.leave()
                            }
                        }
                    }
                    dispatchGroup.notify(queue: .main) {
                        Task { @MainActor in
                            viewModel.moveFiles(from: urls, to: item.url)
                        }
                    }
                    return true
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
        } rows: {
            ForEach(viewModel.items) { item in
                TableRow(item)
                    .draggable(item.url)
                    .onHover { hovering in
                        if hovering {
                            hoveredItem = item
                            
                        } else if hoveredItem == item {
                            hoveredItem = nil
                        }
                    }
            }
        }
        .onDrop(
            of: [UTType.fileURL],
            delegate: TableDropDelegate(viewModel: viewModel)
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) || calendar.isDateInYesterday(date) || calendar.isDateInTomorrow(date) {
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

// Delegate for drops on the general table area (moves to current directory)
struct TableDropDelegate: DropDelegate {
    let viewModel: DirectoryViewModel
    
    func performDrop(info: DropInfo) -> Bool {
        let itemProviders = info.itemProviders(for: [.fileURL])
        guard !itemProviders.isEmpty else { return false }

        var urls: [URL] = []
        let dispatchGroup = DispatchGroup()

        for itemProvider in itemProviders {
            dispatchGroup.enter()
            itemProvider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
                if let urlData = data as? Data, let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                    urls.append(url)
                }
                dispatchGroup.leave()
            }
        }

        dispatchGroup.notify(queue: .main) {
            Task { @MainActor in
                if let currentDirectory = viewModel.currentDirectory {
                    viewModel.moveFiles(from: urls, to: currentDirectory)
                }
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

// Delegate for drops on specific DirectoryItem rows (moves to that item if it's a directory)
struct FolderDropDelegate: DropDelegate {
    let viewModel: DirectoryViewModel
    let targetItem: DirectoryItem

    func validateDrop(info: DropInfo) -> Bool {
        // Only allow drop if the target item is a directory
        return targetItem.isDirectory
    }

    func performDrop(info: DropInfo) -> Bool {
        guard targetItem.isDirectory else { return false } // Ensure it's a directory

        let itemProviders = info.itemProviders(for: [.fileURL])
        guard !itemProviders.isEmpty else { return false }

        var urls: [URL] = []
        let dispatchGroup = DispatchGroup()

        for itemProvider in itemProviders {
            dispatchGroup.enter()
            itemProvider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
                if let urlData = data as? Data, let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                    urls.append(url)
                }
                dispatchGroup.leave()
            }
        }

        dispatchGroup.notify(queue: .main) {
            Task { @MainActor in
                viewModel.moveFiles(from: urls, to: targetItem.url)
            }
        }
        return true
    }

    func dropEntered(info: DropInfo) {
        // Optional: Visual feedback for entering a droppable area
    }

    func dropExited(info: DropInfo) {
        // Optional: Visual feedback for exiting a droppable area
    }

    func dropUpdated(info: DropInfo) -> DropProposal {
        if targetItem.isDirectory {
            return DropProposal(operation: .move) // Indicate move operation is allowed
        } else {
            return DropProposal(operation: .forbidden) // Indicate drop is not allowed
        }
    }
}
